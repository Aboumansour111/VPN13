# VPN13

Flutter Android VPN client powered by the native sing-box engine.

## Repository layout
- `client/`: Flutter VPN13 application
- `config/servers.json`: remotely hosted server list; each server stores a sing-box outbound JSON object as a JSON string
- `backend/`: optional FastAPI administration backend
- `admin/`: administration application
- `scripts/`: local build helpers
- `docs/`: project documentation

## VPN engine
VPN13 uses the `sing_box` Flutter plugin and native sing-box runtime. The app initializes sing-box at startup and passes the selected server's sing-box outbound JSON directly to the runtime.

The server list can be loaded from GitHub or from the bundled `client/assets/servers.json` file using the manual offline test option. Each `config` value must be a JSON string containing one sing-box outbound.

## Build
From `client/`:

```bash
flutter clean
flutter pub get
flutter analyze
flutter build apk --release --split-per-abi
```

Test VPN permission, tunnel startup, DNS, traffic and disconnect behavior on a real Android device.
