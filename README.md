# VPN13

Flutter Android VPN client powered by the Xray core.

## Repository layout
- `client/`: Flutter VPN13 application
- `config/servers.json`: remotely hosted server list; each server stores a complete Xray JSON configuration
- `backend/`: optional FastAPI administration backend
- `admin/`: administration application
- `scripts/`: local build helpers
- `docs/`: project documentation

## VPN engine
VPN13 uses the Xray-backed `flutter_vless` runtime for Android VPN sessions. The previous `sing_box` engine and browser-based sing-box converter are no longer part of the client.

Add or update servers by placing a complete Xray JSON object in the server's `config` field in `config/servers.json`. Each profile must include an Xray `inbounds` section and at least one valid `outbounds` entry. The client passes the selected JSON directly to the Xray runtime; it does not convert sing-box configurations.

The Android app's minimum SDK must be 23 or higher, as required by the Xray Android runtime.

## Build
From `client/`:

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

Verify VPN permission, tunnel startup, DNS, traffic and disconnect behavior on a real Android device with working server profiles.

## Security
Never commit signing keys, private app credentials, database dumps or unrelated secrets.
