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
