# VPN13

Flutter Android VPN client using one VPN engine: **Xray-core**.

## Repository layout
- `client/`: Flutter VPN13 application
- `config/servers.json`: remotely hosted server list
- `backend/`: optional FastAPI administration backend
- `admin/`: administration application
- `scripts/`: local build helpers
- `docs/`: architecture and setup notes

## VPN architecture

- **Only runtime engine:** Xray-core through the pinned AndroidLibXrayLite AAR.
- **Android tunnel owner:** `XrayVpnService` owns VPN permission, TUN interface, foreground notification and Xray lifecycle.
- **Flutter bridge:** `NativeXray` uses MethodChannel and EventChannel for connect, disconnect, state and traffic statistics.
- **Profile conversion:** `EngineRouter` converts supported share links, Xray JSON, Clash YAML and sing-box-format JSON profiles into Xray JSON using the local pure-Dart `xray_profile_parser` package (MIT-licensed parser source).
- **No sing-box runtime:** `sing_box` is not a dependency and no profile is routed to a second engine.

The server list may retain sing-box outbound JSON as an input data format. That does not mean sing-box is used as a runtime: every profile is converted to Xray JSON before it reaches the native service. The `flutter_vless` platform plugin is not a dependency, so it contributes no second VPN service or native runtime.

## Supported server configuration

The server list is loaded from `config/servers.json`. Each `config` value may be a supported share link, raw Xray JSON, or a supported sing-box outbound/profile JSON string. XHTTP transport parameters are preserved as Xray `xhttp` settings and are never downgraded to HTTPUpgrade or another transport.

Do not commit production credentials, UUIDs, private keys or passwords to a public repository. Use a private authenticated profile source for production deployments.

## Build

From the repository root, one command generates any missing Android Gradle scaffolding, downloads and verifies the pinned Xray AAR, resolves packages, runs analysis/tests and builds the client as ARM64:

```powershell
.\\scripts\\build-apks.ps1
```

For a manual client-only build, first run `scripts/ensure-client-android-scaffold.ps1` and `scripts/setup-xray-core.ps1` from the repository root, then run `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` and `flutter build apk --release --target-platform android-arm64` from `client/`.

Test on a physical Android device: VPN permission, startup, DNS, IPv4/IPv6 traffic, XHTTP + REALITY, Shadowsocks 2022, traffic counters, reconnect, and disconnect cleanup. A successful service start alone does not prove traffic is passing.
