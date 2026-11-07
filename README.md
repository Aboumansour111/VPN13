# VPN13

VPN13 is a Flutter Android VPN client powered by one VPN engine: **Xray-core**.

## Repository layout
- `client/`: Android VPN13 application
- `config/servers.json`: GitHub-hosted server list consumed directly by the app
- `scripts/`: client build and Xray setup helpers
- `docs/`: architecture and setup notes

The separate admin application was cancelled. Server configuration is managed by editing and committing `config/servers.json` in this repository; no admin APK or separate backend is required for the client server list.

## VPN architecture

- **Only runtime engine:** Xray-core through the pinned AndroidLibXrayLite AAR.
- **Android tunnel owner:** `XrayVpnService` owns VPN permission, TUN interface, foreground notification and Xray lifecycle.
- **Flutter bridge:** `NativeXray` uses MethodChannel and EventChannel for connect, disconnect, state and traffic statistics.
- **Profile conversion:** `EngineRouter` converts supported share links, Xray JSON, Clash YAML and compatible sing-box-format JSON profiles into Xray JSON using the local pure-Dart `xray_profile_parser` package.
- **No sing-box runtime:** sing-box is not a dependency and no profile is routed to a second engine. sing-box-shaped JSON, where used, is only an input data format.

## Automatic server-list updates

The client downloads `config/servers.json` directly from the repository's `main` branch when the app starts. The user can also request a refresh from the server-list screen. Updating and committing this file on GitHub changes the list delivered to clients; rebuilding or reinstalling the APK is not required for server-list changes.

The file format is:

```json
{
  "version": 1,
  "servers": [
    {
      "id": 1,
      "name": "Sweden",
      "description": "VLESS Reality",
      "config": "vless://..."
    }
  ]
}
```

Each server needs a unique integer `id`, a display `name`, and a supported `config` value. Do not commit production credentials, UUIDs, private keys or passwords to a public repository: anyone can read them. Use a private authenticated source if server credentials must remain private.

## Build

Run from the repository root in Windows PowerShell. This builds **only the client ARM64 APK**; the cancelled admin application is not built:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\\scripts\\build-apks.ps1"
```

The script prepares the Android Gradle scaffold, downloads and verifies the pinned Xray AAR, resolves packages, runs analysis and tests, then builds the release APK.

Test on a physical Android device: VPN permission, startup, DNS, IPv4/IPv6 traffic, supported VLESS transports, Shadowsocks 2022, traffic counters, reconnect and disconnect cleanup. A successful service start alone does not prove traffic is passing.
