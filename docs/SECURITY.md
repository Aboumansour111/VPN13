# Security checklist before production

- [ ] Set a unique random SECRET_KEY (32+ random bytes) and a strong ADMIN_PASSWORD.
- [ ] Configure HTTPS (reverse proxy / managed certificate); do not send credentials over public HTTP.
- [ ] Change SQLite to PostgreSQL for production, configure backups and restore tests.
- [ ] Add registration throttling, login throttling and API rate limiting.
- [ ] Disable or protect interactive API docs in production.
- [ ] Add subscription/invite controls; registration is open in this MVP.
- [ ] Add account/device/expiry/traffic limits and a way to suspend accounts.
- [ ] Do not put private node configs, admin passwords, signing keys or .env files in Git.
- [ ] Use a private repository for operational code and configuration.
- [ ] Rotate compromised node links; each authenticated client can retrieve profiles.
- [ ] Review GPL-3.0-or-later obligations for sing-box and publish corresponding source when distributing.
- [ ] Test Android Always-on VPN / Block connections without VPN, DNS, IPv6, reconnect and kill-switch behavior.
