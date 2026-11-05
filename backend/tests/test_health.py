from fastapi.testclient import TestClient
from app.main import app, settings
import pytest
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

def test_shared_access_code_authenticates_all_clients(monkeypatch):
    monkeypatch.setattr(settings, "client_access_code", "Vpn-2026-Shared")
    monkeypatch.setattr(settings, "secret_key", "test-only-secret-key-with-at-least-32-bytes")
    monkeypatch.setattr(settings, "client_access_code", "12345")
    too_short=client.post("/api/client/access", json={"code":"123456"})
    assert too_short.status_code==503
    monkeypatch.setattr(settings, "client_access_code", "Vpn-2026-Shared")
    denied=client.post("/api/client/access", json={"code":"wrong-code"})
    assert denied.status_code==401
    accepted=client.post("/api/client/access", json={"code":"Vpn-2026-Shared"})
    assert accepted.status_code==200
    assert accepted.json()["access_token"]
    token=accepted.json()["access_token"]
    profile=client.get("/api/client/servers/999/profile", headers={"Authorization":f"Bearer {token}"})
    assert profile.status_code==404
    monkeypatch.setattr(settings, "client_access_code", "New-Code-2026")
    revoked=client.get("/api/client/servers/999/profile", headers={"Authorization":f"Bearer {token}"})
    assert revoked.status_code==403
def test_admin_login_rejects_non_ascii_password_without_server_error(monkeypatch):
    monkeypatch.setattr(settings, "secret_key", "test-only-secret-key-with-at-least-32-bytes")
    monkeypatch.setattr(settings, "admin_password", "Valid-ASCII-Test-Password")
    response=client.post("/api/admin/login", json={"username":"admin","password":"رمز اشتباه"})
    assert response.status_code==401

def test_admin_routes_require_bearer_token():
    response=client.get("/api/admin/servers")
    assert response.status_code==401
def test_health_survives_api_start():
    assert client.get("/health").json()["status"]=="ok"
