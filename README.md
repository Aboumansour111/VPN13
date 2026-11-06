# VPN13

Flutter Android VPN client with two native proxy engines: sing-box and Xray.

## Repository layout
- `client/`: Flutter VPN13 application
- `config/servers.json`: remotely hosted server list
- `backend/`: optional FastAPI administration backend
- `admin/`: administration application
- `scripts/`: local build helpers
- `docs/`: architecture and setup notes

## VPN engines

VPN13 selects the runtime from each server configuration:

- **sing-box** handles the existing supported protocols and profiles.
- **Xray** handles XHTTP transports, including VLESS + XHTTP.

Only one engine owns the Android VPN tunnel at a time. Before switching engines, VPN13 stops the active engine and then starts the selected one. XHTTP is never rewritten as HTTPUpgrade or another transport.

The Flutter packages are:
- `sing_box`: native sing-box / libbox runtime.
- `flutter_vless`: native Xray runtime with XHTTP support.

## Server configuration

The server list is loaded from `config/servers.json`. Each `config` field contains a sing-box outbound JSON object as a JSON string, or a supported share link. Profiles with `transport.type = "xhttp"` are routed to Xray; other supported profiles continue to use sing-box.

For example, a VLESS XHTTP outbound can use:
```json
{
  "type": "vless",
  "tag": "vpn13-xhttp",
  "server": "example.com",
  "server_port": 443,
  "uuid": "00000000-0000-4000-8000-000000000000",
  "tls": {
    "enabled": true,
    "server_name": "example.com"
  },
  "transport": {
    "type": "xhttp",
    "path": "/your-path",
    "mode": "auto"
  }
}
```

Use real server values in your private configuration source; do not commit production credentials to a public repository.

## Build

From `client/`:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Test both engines on a physical Android device: VPN permission, startup, DNS, actual traffic, stats, switching between engines, and disconnect cleanup.
