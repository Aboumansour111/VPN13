from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from passlib.context import CryptContext
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import create_engine, String, Text, Boolean, Integer, DateTime, select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session, sessionmaker

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./mahdvpn.db"
    secret_key: str = "CHANGE_ME_TO_A_LONG_RANDOM_SECRET"
    admin_username: str = "admin"
    admin_password: str = "CHANGE_ME_NOW"
    access_token_minutes: int = 60
    cors_origins: str = "http://localhost:3000"

settings = Settings()
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth = OAuth2PasswordBearer(tokenUrl="/api/admin/login")

class Base(DeclarativeBase): pass
class Server(Base):
    __tablename__ = "servers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    config: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

Base.metadata.create_all(engine)
app = FastAPI(title="MahdiVPN API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=[x.strip() for x in settings.cors_origins.split(",") if x.strip()], allow_methods=["GET","POST","PUT","DELETE"], allow_headers=["Authorization","Content-Type"])

def db():
    s=SessionLocal()
    try: yield s
    finally: s.close()

class Login(BaseModel):
    username: str
    password: str
class ServerIn(BaseModel):
    name: str = Field(min_length=1,max_length=100)
    config: str = Field(min_length=1,max_length=20000)
    description: Optional[str] = Field(default=None,max_length=500)
    active: bool = True
    sort_order: int = 0
class ServerOut(BaseModel):
    id: int; name: str; description: Optional[str]; active: bool; sort_order: int
class ServerAdminOut(ServerOut):
    config: str

def token_for(sub: str):
    exp=datetime.now(timezone.utc)+timedelta(minutes=settings.access_token_minutes)
    return jwt.encode({"sub":sub,"exp":exp},settings.secret_key,algorithm="HS256")

def admin(token: str=Depends(oauth)):
    try:
        data=jwt.decode(token,settings.secret_key,algorithms=["HS256"])
        if data.get("sub") != settings.admin_username: raise ValueError()
    except (JWTError,ValueError):
        raise HTTPException(status_code=401,detail="اعتبار ورود مدیر منقضی یا نامعتبر است",headers={"WWW-Authenticate":"Bearer"})
    return data["sub"]

@app.get("/health")
def health(): return {"status":"ok"}

@app.post("/api/admin/login")
def login(body: Login):
    # Admin password is environment-only; constant-time hash verification is used.
    if body.username != settings.admin_username or not pwd.verify(body.password, pwd.hash(settings.admin_password)):
        raise HTTPException(status_code=401,detail="نام کاربری یا رمز عبور اشتباه است")
    return {"access_token":token_for(body.username),"token_type":"bearer","expires_in":settings.access_token_minutes*60}

@app.get("/api/servers",response_model=list[ServerOut])
def public_servers(s: Session=Depends(db)):
    return list(s.scalars(select(Server).where(Server.active==True).order_by(Server.sort_order,Server.id)))

@app.get("/api/servers/{server_id}",response_model=ServerOut)
def public_server(server_id:int,s:Session=Depends(db)):
    x=s.get(Server,server_id)
    if not x or not x.active: raise HTTPException(404,"سرور پیدا نشد")
    return x

@app.get("/api/admin/servers",response_model=list[ServerAdminOut])
def all_servers(_:str=Depends(admin),s:Session=Depends(db)):
    return list(s.scalars(select(Server).order_by(Server.sort_order,Server.id)))

@app.post("/api/admin/servers",response_model=ServerAdminOut,status_code=201)
def add_server(body:ServerIn,_:str=Depends(admin),s:Session=Depends(db)):
    if s.scalar(select(Server).where(Server.name==body.name)): raise HTTPException(409,"نام سرور تکراری است")
    x=Server(**body.model_dump());s.add(x);s.commit();s.refresh(x);return x

@app.put("/api/admin/servers/{server_id}",response_model=ServerAdminOut)
def edit_server(server_id:int,body:ServerIn,_:str=Depends(admin),s:Session=Depends(db)):
    x=s.get(Server,server_id)
    if not x: raise HTTPException(404,"سرور پیدا نشد")
    duplicate=s.scalar(select(Server).where(Server.name==body.name,Server.id!=server_id))
    if duplicate: raise HTTPException(409,"نام سرور تکراری است")
    for k,v in body.model_dump().items(): setattr(x,k,v)
    s.commit();s.refresh(x);return x

@app.delete("/api/admin/servers/{server_id}",status_code=204)
def delete_server(server_id:int,_:str=Depends(admin),s:Session=Depends(db)):
    x=s.get(Server,server_id)
    if not x: raise HTTPException(404,"سرور پیدا نشد")
    s.delete(x);s.commit()

# Client accounts protect node credentials from anonymous API access.
class ClientUser(Base):
    __tablename__ = "client_users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
Base.metadata.create_all(engine)
client_oauth = OAuth2PasswordBearer(tokenUrl="/api/client/login")
class ClientRegister(BaseModel):
    username: str = Field(min_length=3,max_length=80,pattern=r"^[a-zA-Z0-9_.-]+$")
    password: str = Field(min_length=10,max_length=128)
def client_identity(token: str=Depends(client_oauth),s:Session=Depends(db)):
    try: data=jwt.decode(token,settings.secret_key,algorithms=["HS256"])
    except JWTError: raise HTTPException(401,"توکن نامعتبر است")
    sub=data.get("sub","")
    if not sub.startswith("client:"): raise HTTPException(403,"ورود کاربر لازم است")
    try: user=s.get(ClientUser,int(sub.split(":",1)[1]))
    except ValueError: user=None
    if not user or not user.active: raise HTTPException(403,"حساب کاربری غیرفعال است")
    return user
def client_token(user:ClientUser):
    exp=datetime.now(timezone.utc)+timedelta(minutes=settings.access_token_minutes)
    return jwt.encode({"sub":f"client:{user.id}","exp":exp},settings.secret_key,algorithm="HS256")
@app.post("/api/client/register",status_code=201)
def client_register(body:ClientRegister,s:Session=Depends(db)):
    if s.scalar(select(ClientUser).where(ClientUser.username==body.username)): raise HTTPException(409,"نام کاربری قبلاً ثبت شده")
    u=ClientUser(username=body.username,password_hash=pwd.hash(body.password));s.add(u);s.commit();s.refresh(u)
    return {"access_token":client_token(u),"token_type":"bearer","expires_in":settings.access_token_minutes*60}
@app.post("/api/client/login")
def client_login(body:Login,s:Session=Depends(db)):
    u=s.scalar(select(ClientUser).where(ClientUser.username==body.username))
    if not u or not u.active or not pwd.verify(body.password,u.password_hash): raise HTTPException(401,"نام کاربری یا رمز اشتباه است")
    return {"access_token":client_token(u),"token_type":"bearer","expires_in":settings.access_token_minutes*60}
@app.get("/api/client/servers/{server_id}/profile")
def client_profile(server_id:int,_:ClientUser=Depends(client_identity),s:Session=Depends(db)):
    x=s.get(Server,server_id)
    if not x or not x.active: raise HTTPException(404,"سرور پیدا نشد")
    return {"id":x.id,"name":x.name,"config":x.config}
