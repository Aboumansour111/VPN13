# Android native Xray bridge

The Flutter UI is connected to one native AndroidLibXrayLite Xray runtime.

## Flutter channels

- MethodChannel: `vpn13/xray`
  - `prepare`: requests Android VPN permission and resolves after the user's decision.
  - `connect`: starts the foreground VPN service with Xray JSON and the selected profile name.
  - `disconnect`: stops the service and core.
  - `getStatus`: returns the current native state and traffic counters.
  - `getVersion`: returns the linked libv2ray/Xray version.
- EventChannel: `vpn13/xray/events`
  - Emits connecting/connected/disconnected/error states and periodic upload/download speed and total counters.

## Native implementation

- `MainActivity.kt`: MethodChannel, EventChannel and VPN permission result.
- `XrayVpnService.kt`: foreground service, IPv4/IPv6 TUN interface, DNS routes, app-UID bypass and CoreController lifecycle.
- `AndroidManifest.xml`: VPN service declaration, BIND_VPN_SERVICE and foreground-service permissions.
- `build.gradle.kts`: links the pinned local `libs/libv2ray.aar`.
- `scripts/setup-xray-core.ps1`: downloads AndroidLibXrayLite v26.10.31 and verifies SHA-256.

## Traffic statistics

The generated Xray configuration enables outbound uplink/downlink counters. The service polls `CoreController.queryAllOutboundTrafficStats()` once per second and emits deltas and accumulated totals through the EventChannel. Statistics polling is stopped before the controller is released.

## Validation still required

1. Flutter analyze and unit tests pass after `flutter pub get`.
2. ARM64 APK builds against the pinned AAR.
3. VPN permission prompt, service lifecycle, foreground notification and revocation work on a physical device.
4. Xray core starts with real Shadowsocks 2022 and VLESS + XHTTP + REALITY configurations.
5. IPv4/IPv6 traffic passes, DNS resolves, and the core's sockets do not loop back into the TUN.
6. Stop/reconnect, screen-off, network handover and process recreation behave correctly.
7. Traffic counters increase and reset correctly between sessions.

A successful `startLoop` or a connected VPN icon is not proof of working data-plane traffic. Test actual requests through the tunnel before release.
