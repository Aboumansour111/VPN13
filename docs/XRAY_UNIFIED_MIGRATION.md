# VPN13 Xray Unified Core Migration

Status: HomeScreen now uses the native AndroidLibXrayLite Xray service as its only VPN connection path. The sing-box and FlutterVless platform plugins are removed; profile conversion uses the local pure-Dart parser. CI and physical-device traffic validation remain outstanding.

## Target

Use one Xray Core runtime via the AndroidLibXrayLite library (the same Android binding family used by v2rayNG), with Flutter retained as the UI and Kotlin owning Android VPN lifecycle.

- Flutter: screens, profile list, user actions, state rendering.
- Kotlin: MethodChannel, foreground `VpnService`, VPN permission, TUN descriptor, notification, lifecycle and native callbacks.
- AndroidLibXrayLite: Xray core/controller.
- Config pipeline: supported URI/profile -> validated Xray JSON -> native core.
- Exactly one VPN service/tunnel owner.

## Verified upstream API shape

The v2rayNG source currently uses:

- `libv2ray.Libv2ray.initCoreEnv(assetPath, deviceId)`
- `Libv2ray.newCoreController(CoreCallbackHandler)`
- `CoreController.startLoop(configJson, tunFd)`
- `CoreController.stopLoop()`
- `CoreController.isRunning`
- `CoreCallbackHandler` callbacks for state/messages

Upstream references:
- https://github.com/2dust/v2rayNG
- https://github.com/2dust/AndroidLibXrayLite
- v2rayNG CoreNativeManager / CoreServiceManager / CoreVpnService

Do not assume signatures beyond the pinned AAR's generated API. Pin the exact upstream release/commit and inspect its generated classes before coding against it.

## Migration sequence

1. Record current APK size and inspect ZIP entries / native libraries. Do not infer size causes from the total alone.
2. Pin an AndroidLibXrayLite release/commit and integrate its AAR + required ABI files into Android Gradle. ARM64-only release should package `arm64-v8a`; avoid universal/multi-ABI output for the user's Honor X9b.
3. Implement a Kotlin foreground `VpnService`: `prepare()`, establish TUN with IPv4/IPv6/DNS/routes, pass TUN fd to CoreController, protect any core-owned sockets if required by the pinned library, and close fd/controller on stop/revoke/destroy. Keep service ownership and notifications singular.
4. Expose a small MethodChannel contract: `initialize`, `connect(configJson, profileName)`, `disconnect`, `status`, and callback events (connecting/connected/disconnected/error/stats). Never send secrets to logs.
5. Parser tests currently cover Shadowsocks 2022 outbound conversion and VLESS XHTTP/REALITY conversion with traffic counters. Extend the matrix with VLESS IPv6 authority/percent-decoding, VMess, Trojan, raw Xray JSON and explicit rejection of unsupported sing-box-only fields.
6. HomeScreen now uses `NativeXray` as its only connection path. `sing_box` has been removed. `flutter_vless` has been replaced by the local pure-Dart `xray_profile_parser` package, so only the AndroidLibXrayLite native runtime is packaged. Keep existing UI/profile/backend contracts where possible.
7. Verify on device: permission flow, start/stop/reconnect, process death/Always-on behavior, IPv4/IPv6, DNS, XHTTP+REALITY+IPv6, traffic counters, and non-XHTTP protocols.
8. Build ARM64 APK, compare APK/AAB contents and size to baseline, then test before merging.

## Important constraints

- A successful `startLoop` is not proof of data-plane connectivity; verify actual traffic.
- Do not put real node credentials in Git, examples, CI logs, or diagnostic output.
- Keep the existing branch intact; this migration is isolated in `feature/xray-unified-core`.
- The tracked Android source includes the manifest, app Gradle file and native Kotlin bridge. `scripts/ensure-client-android-scaffold.ps1` generates missing Flutter Gradle wrapper/scaffold files while preserving the tracked native files. The 60 MB AAR is downloaded separately and SHA-256 verified; it is intentionally not committed.
- GPL/LGPL obligations and notices must be reviewed for the exact core artifact and distribution model.
