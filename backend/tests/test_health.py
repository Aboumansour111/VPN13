from fastapi.testclient import TestClient
from app.main import app
client=TestClient(app)
def test_health():
    response=client.get("/health")
    assert response.status_code==200
    assert response.json()=={"status":"ok"}
def test_public_server_list_does_not_include_configs():
    response=client.get("/api/servers")
    assert response.status_code==200
    assert isinstance(response.json(),list)
    assert all("config" not in item for item in response.json())

def test_private_profile_requires_client_token():
    response=client.get("/api/client/servers/1/profile")
    assert response.status_code==401
def test_admin_routes_require_bearer_token():
    response=client.get("/api/admin/servers")
    assert response.status_code==401
def test_health_survives_api_start():
    assert client.get("/health").json()["status"]=="ok"
