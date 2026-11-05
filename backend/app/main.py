from datetime import datetime, timedelta, timezone
from typing import Optional
import hmac, json, warnings, hashlib
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import create_engine, String, Text, Boolean, Integer, DateTime, select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session, sessionmaker

class Settings(BaseSettings):
    model_config=SettingsConfigDict(env_file=".env",extra="ignore")
    database_url:str="sqlite:///./vpn13.db"
    secret_key:str="CHANGE_ME_TO_A_LONG_RANDOM_SECRET"
    admin_username:str="admin"
    admin_password:str="CHANGE_ME_NOW"
    client_access_code:str="CHANGE_ME_ACCESS_CODE"
    access_token_minutes:int=60
    cors_origins:str=""
settings=Settings()
if settings.secret_key.startswith("CHANGE_ME") or settings.admin_password=="CHANGE_ME_NOW":
    warnings.warn("Set SECRET_KEY and ADMIN_PASSWORD in backend/.env before production use.", RuntimeWarning)
engine=create_engine(settings.database_url,connect_args={"check_same_thread":False} if settings.database_url.startswith("sqlite") else {},pool_pre_ping=True)
SessionLocal=sessionmaker(bind=engine,autoflush=False,expire_on_commit=False)
admin_oauth=OAuth2PasswordBearer(tokenUrl="/api/admin/login")
client_oauth=OAuth2PasswordBearer(tokenUrl="/api/client/access")
class Base(DeclarativeBase):pass
class Server(Base):
    __tablename__="servers"
    id:Mapped[int]=mapped_column(Integer,primary_key=True)
    name:Mapped[str]=mapped_column(String(100),unique=True,index=True)
    config:Mapped[str]=mapped_column(Text)
    description:Mapped[Optional[str]]=mapped_column(String(500),default=None)
    active:Mapped[bool]=mapped_column(Boolean,default=True)
    sort_order:Mapped[int]=mapped_column(Integer,default=0)
    created_at:Mapped[datetime]=mapped_column(DateTime,default=lambda:datetime.now(timezone.utc))
Base.metadata.create_all(engine)
app=FastAPI(title="VPN13 API",version="0.2.0")
app.add_middleware(CORSMiddleware,allow_origins=[x.strip() for x in settings.cors_origins.split(",") if x.strip()],allow_methods=["GET","POST","PUT","DELETE"],allow_headers=["Authorization","Content-Type"])
def db():
 s=SessionLocal()
 try:yield s
 finally:s.close()
class Login(BaseModel):
 username:str=Field(min_length=1,max_length=80);password:str=Field(min_length=1,max_length=128)
class ClientAccess(BaseModel):
    code:str=Field(min_length=6,max_length=128)
class ServerIn(BaseModel):
 name:str=Field(min_length=1,max_length=100);config:str=Field(min_length=1,max_length=20000);description:Optional[str]=Field(default=None,max_length=500);active:bool=True;sort_order:int=Field(default=0,ge=0,le=100000)
 @field_validator("config")
 @classmethod
 def valid_config(cls,v):
  v=v.strip()
  if v.startswith("{"):
   try:
    data=json.loads(v)
    if not isinstance(data,dict):raise ValueError()
   except Exception:raise ValueError("JSON کانفیگ معتبر نیست")
  elif not any(v.lower().startswith(s) for s in ("vless://","vmess://","trojan://","ss://","shadowsocks://","hysteria2://","hy2://","hysteria://","tuic://","wireguard://","wg://")):
   raise ValueError("فرمت کانفیگ یا لینک پشتیبانی‌شده نیست")
  return v
class ServerOut(BaseModel):id:int;name:str;description:Optional[str];active:bool;sort_order:int
class ServerAdminOut(ServerOut):config:str
def token_for(subject:str,role:str):
 payload={"sub":subject,"role":role,"exp":datetime.now(timezone.utc)+timedelta(minutes=settings.access_token_minutes)}
 if role=="client":payload["code_version"]=hashlib.sha256(settings.client_access_code.encode("utf-8")).hexdigest()
 return jwt.encode(payload,settings.secret_key,algorithm="HS256")
def claims(token:str):
 try:return jwt.decode(token,settings.secret_key,algorithms=["HS256"])
 except JWTError:raise HTTPException(401,"توکن نامعتبر یا منقضی است",headers={"WWW-Authenticate":"Bearer"})
def admin(token:str=Depends(admin_oauth)):
 d=claims(token)
 if d.get("role")!="admin" or d.get("sub")!=settings.admin_username:raise HTTPException(403,"دسترسی مدیر لازم است")
 return d["sub"]
def client_user(token:str=Depends(client_oauth)):
 d=claims(token)
 if d.get("role")!="client" or d.get("sub")!="shared" or d.get("code_version")!=hashlib.sha256(settings.client_access_code.encode("utf-8")).hexdigest():raise HTTPException(403,"کد دسترسی معتبر نیست یا تغییر کرده است")
 return True
@app.get("/health")
def health():return {"status":"ok"}
@app.post("/api/admin/login")
def admin_login(body:Login):
 if settings.secret_key.startswith("CHANGE_ME") or settings.admin_password=="CHANGE_ME_NOW":raise HTTPException(503,"تنظیمات امنیتی مدیر کامل نشده است")
 if body.username!=settings.admin_username or not hmac.compare_digest(body.password.encode("utf-8"),settings.admin_password.encode("utf-8")):raise HTTPException(401,"نام کاربری یا رمز عبور اشتباه است")
 return {"access_token":token_for(body.username,"admin"),"token_type":"bearer","expires_in":settings.access_token_minutes*60}
@app.post("/api/client/access")
def client_access(body:ClientAccess):
 if settings.client_access_code=="CHANGE_ME_ACCESS_CODE" or len(settings.client_access_code)<6:raise HTTPException(503,"کد دسترسی مشترک باید در تنظیمات سرور و با حداقل ۶ نویسه تعیین شود")
 if settings.secret_key.startswith("CHANGE_ME"):raise HTTPException(503,"کلید امنیتی SECRET_KEY در تنظیمات سرور تعیین نشده است")
 if not hmac.compare_digest(body.code.encode('utf-8'),settings.client_access_code.encode('utf-8')):raise HTTPException(401,"کد دسترسی اشتباه است")
 return {"access_token":token_for("shared","client"),"token_type":"bearer","expires_in":settings.access_token_minutes*60}
@app.get("/api/servers",response_model=list[ServerOut])
def public_servers(s:Session=Depends(db)):return list(s.scalars(select(Server).where(Server.active.is_(True)).order_by(Server.sort_order,Server.id)))
@app.get("/api/servers/{server_id}",response_model=ServerOut)
def public_server(server_id:int,s:Session=Depends(db)):
 x=s.get(Server,server_id)
 if not x or not x.active:raise HTTPException(404,"سرور پیدا نشد")
 return x
@app.get("/api/client/servers/{server_id}/profile")
def client_profile(server_id:int,_:bool=Depends(client_user),s:Session=Depends(db)):
 x=s.get(Server,server_id)
 if not x or not x.active:raise HTTPException(404,"سرور پیدا نشد")
 return {"id":x.id,"name":x.name,"config":x.config}
@app.get("/api/admin/servers",response_model=list[ServerAdminOut])
def all_servers(_:str=Depends(admin),s:Session=Depends(db)):return list(s.scalars(select(Server).order_by(Server.sort_order,Server.id)))
@app.post("/api/admin/servers",response_model=ServerAdminOut,status_code=201)
def add_server(body:ServerIn,_:str=Depends(admin),s:Session=Depends(db)):
 if s.scalar(select(Server).where(Server.name==body.name)):raise HTTPException(409,"نام سرور تکراری است")
 x=Server(**body.model_dump());s.add(x);s.commit();s.refresh(x);return x
@app.put("/api/admin/servers/{server_id}",response_model=ServerAdminOut)
def edit_server(server_id:int,body:ServerIn,_:str=Depends(admin),s:Session=Depends(db)):
 x=s.get(Server,server_id)
 if not x:raise HTTPException(404,"سرور پیدا نشد")
 if s.scalar(select(Server).where(Server.name==body.name,Server.id!=server_id)):raise HTTPException(409,"نام سرور تکراری است")
 for k,v in body.model_dump().items():setattr(x,k,v)
 s.commit();s.refresh(x);return x
@app.delete("/api/admin/servers/{server_id}",status_code=204)
def delete_server(server_id:int,_:str=Depends(admin),s:Session=Depends(db)):
 x=s.get(Server,server_id)
 if not x:raise HTTPException(404,"سرور پیدا نشد")
 s.delete(x);s.commit()
