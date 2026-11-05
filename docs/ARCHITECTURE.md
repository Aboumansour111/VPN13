# Architecture

- Client/Admin: Flutter UI and API client, separate app IDs and entry points.
- Backend: FastAPI, SQLAlchemy models, password hashing, signed bearer tokens, admin-only CRUD.
- Public API returns only safe server metadata; private node configuration is delivered only to authenticated client accounts through /api/client/servers/{id}/profile. Current initial implementation deliberately does not expose config through public list.
- VPN data plane is handled by sing-box native core through Android VpnService; Flutter does not implement tunneling itself.
- Secrets are environment variables; production should use HTTPS, PostgreSQL, reverse proxy, backups, rate limiting and monitoring.
