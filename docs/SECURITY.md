# Security checklist before production

- [ ] Set a unique random SECRET_KEY (32+ random bytes) and a strong ADMIN_PASSWORD.
- [ ] Configure HTTPS (reverse proxy / managed certificate); do not send credentials over public HTTP.
- [ ] Change SQLite to PostgreSQL for production, configure backups and restore tests.
- [ ] Add rate limiting to the shared client access-code endpoint; rotate CLIENT_ACCESS_CODE if it is disclosed.
- [ ] Disable or protect interactive API docs in production.
- [ ] The client uses one shared access code; anyone who knows it can access client profiles. Rotate it when access must be revoked.
- [ ] Add account/device/expiry/traffic limits and a way to suspend accounts.
- [ ] Do not put private node configs, admin passwords, signing keys or .env files in Git.
- [ ] Use a private repository for operational code and configuration.
- [ ] Rotate compromised node links; each authenticated client can retrieve profiles.
- [ ] Review GPL-3.0-or-later obligations for sing-box and publish corresponding source when distributing.
- [ ] Test Android Always-on VPN / Block connections without VPN, DNS, IPv6, reconnect and kill-switch behavior.
