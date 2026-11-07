# VPN13 Xray Unified Core Migration

Status: native Xray bridge is wired to HomeScreen and sing-box runtime dependency/selection have been removed. Physical-device traffic validation and final removal of the temporary FlutterVless parser dependency remain outstanding.

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
5. Add config parsing/conversion tests before UI wiring:
   - VLESS URI (including IPv6 authority, percent-decoding, REALITY, TLS, XHTTP mode and extra/xPaddingBytes)
   - VMess URI/base64 JSON
   - Trojan URI
   - Shadowsocks URI (including SIP002 plugin/options and SS2022 constraints)
   - raw Xray JSON validation
   - explicitly reject unsupported sing-box-only fields instead of silently changing semantics.
6. HomeScreen now uses `NativeXray` as its only connection path. `sing_box` has been removed. `flutter_vless` remains temporarily as a Dart profile parser/converter; remove it only after an equivalent parser has passed protocol parity tests. Keep existing UI/profile/backend contracts where possible.
7. Verify on device: permission flow, start/stop/reconnect, process death/Always-on behavior, IPv4/IPv6, DNS, XHTTP+REALITY+IPv6, traffic counters, and non-XHTTP protocols.
8. Build ARM64 APK, compare APK/AAB contents and size to baseline, then test before merging.

## Important constraints

- A successful `startLoop` is not proof of data-plane connectivity; verify actual traffic.
- Do not put real node credentials in Git, examples, CI logs, or diagnostic output.
- Keep the existing branch intact; this migration is isolated in `feature/xray-unified-core`.
- The Android directory is Flutter-generated/ignored in the current repository. Native source and Gradle changes must be deliberately added to Git and checked against the local generated Android project before a build.
- GPL/LGPL obligations and notices must be reviewed for the exact core artifact and distribution model.
