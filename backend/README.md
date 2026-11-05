# Backend API
See ../docs/SETUP.md. Configure a strong random SECRET_KEY and ADMIN_PASSWORD before startup.

Endpoints:
- GET /health
- POST /api/admin/login
- GET /api/servers (active metadata only)
- GET /api/servers/{id} (active metadata only)
- GET /api/admin/servers (Bearer)
- POST /api/admin/servers (Bearer)
- PUT /api/admin/servers/{id} (Bearer)
- DELETE /api/admin/servers/{id} (Bearer)

Important: VPN configs are intentionally not exposed to anonymous Client requests. A production subscription/user auth endpoint is required before distributing private node configs.
