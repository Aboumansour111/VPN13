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
VPN13 uses the Xray-backed `flutter_vless` runtime for Android VPN sessions. The client downloads complete Xray JSON configurations and passes them directly to the engine. No share-link parser or sing-box converter is used by the client.

Each entry in `config/servers.json` must have a `config` object containing a valid Xray configuration with `inbounds`, `outbounds`, and any required `routing` rules. Keep server credentials private; a public repository makes every committed server credential publicly readable.

The Android app's minimum SDK must be 23 or higher, as required by the Xray Android runtime.

## Build
From `client/`:

```bash
flutter pub get
flutter analyze
flutter build apk --release --split-per-abi
```

Verify VPN permission, tunnel startup, DNS, traffic and disconnect behavior on a real Android device with working server profiles.
