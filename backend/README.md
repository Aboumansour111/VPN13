# VPN13 Backend

Install: `pip install -r requirements.txt`; configure .env; run `uvicorn app.main:app`.

Routes:
- GET /health
- POST /api/admin/login
- GET /api/servers (active metadata only; no config)
- GET /api/servers/{id} (active metadata only)
- GET/POST/PUT/DELETE /api/admin/servers (Bearer admin)
- POST /api/client/access (one shared access code; no individual registration)
- GET /api/client/servers/{id}/profile (Bearer client; private node config)

All clients use the same CLIENT_ACCESS_CODE configured in backend/.env. There are no individual client accounts or registrations. Rotate the shared code by changing CLIENT_ACCESS_CODE and restarting the backend. Add rate limiting and HTTPS before production. Configs are only delivered to clients with a valid shared-code token; never expose them on public endpoints.
