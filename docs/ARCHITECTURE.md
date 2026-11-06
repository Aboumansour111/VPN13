# Architecture

- Client/Admin: Flutter UI and API client.
- Backend: FastAPI administration API.
- **Engine routing:** `EngineRouter` detects XHTTP profiles and selects Xray; other supported profiles remain on sing-box.
- **Single VPN owner:** Android permits one active VPN tunnel per user/profile. VPN13 stops the current engine before starting the other; the engines are not run as competing TUN services.
- **sing-box:** managed by the `sing_box` Flutter plugin and native libbox runtime.
- **Xray:** managed by the `flutter_vless` Flutter plugin and its native Xray runtime. It is selected for XHTTP profiles.
- XHTTP transport parameters are preserved as Xray configuration. XHTTP is not downgraded to HTTPUpgrade.
- Secrets should remain outside public source control. Production should use HTTPS, authenticated profile delivery, PostgreSQL, backups, rate limiting and monitoring.
