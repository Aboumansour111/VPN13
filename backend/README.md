# MahdiVPN Backend

Install: `pip install -r requirements.txt`; configure .env; run `uvicorn app.main:app`.

Routes:
- GET /health
- POST /api/admin/login
- GET /api/servers (active metadata only; no config)
- GET /api/servers/{id} (active metadata only)
- GET/POST/PUT/DELETE /api/admin/servers (Bearer admin)
- POST /api/client/register (username + password >=10 chars)
- POST /api/client/login
- GET /api/client/servers/{id}/profile (Bearer client; private node config)

Client registration is currently open (no subscription/approval/limits). Before production, add invite/subscription controls, rate limits, HTTPS reverse proxy, admin account management, backups and monitoring. Configs are only delivered to logged-in client accounts; never expose them on public endpoints.
