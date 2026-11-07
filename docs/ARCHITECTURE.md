# Architecture

- Client/Admin: Flutter UI and API client.
- Backend: FastAPI administration API.
- **Single VPN engine:** Xray-core through the pinned AndroidLibXrayLite runtime.
- **Single tunnel owner:** `XrayVpnService` owns Android's VPN interface, foreground lifecycle and Xray controller. No sing-box runtime or engine switching remains.
- **Flutter bridge:** `NativeXray` exposes VPN permission, connect, disconnect, status and traffic events.
- **Profile conversion:** `EngineRouter` converts supported share links, raw Xray JSON, Clash YAML and supported sing-box-format profiles into Xray JSON using the local pure-Dart `xray_profile_parser` package. The FlutterVless platform plugin is not included.
- **Traffic statistics:** Xray outbound counters are enabled in the generated config and read through AndroidLibXrayLite's `queryAllOutboundTrafficStats` API.
- XHTTP transport parameters remain XHTTP and are not downgraded to HTTPUpgrade.
- Secrets should remain outside public source control. Production should use HTTPS, authenticated profile delivery, PostgreSQL, backups, rate limiting and monitoring.
