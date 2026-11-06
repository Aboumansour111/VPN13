# Android native bridge implementation

The first Kotlin bridge is now present under `client/android`. It is intentionally isolated from the existing Flutter engine path until it is built and verified on a device.

## Flutter channels

- MethodChannel: `vpn13/xray`
  - `prepare`: requests Android's VPN permission and resolves only after the user's decision.
  - `connect`: starts the foreground VPN service with an Xray JSON config.
  - `disconnect`: stops the service and core.
  - `getStatus`: returns the current native state and sanitized message.
  - `getVersion`: returns the linked libv2ray/Xray version.
- EventChannel: `vpn13/xray/events`
  - Emits state and sanitized core status messages.

## Native implementation

- `MainActivity.kt`: MethodChannel, EventChannel and VPN permission result.
- `XrayVpnService.kt`: foreground service, IPv4/IPv6 TUN interface, DNS routes and CoreController lifecycle.
- `AndroidManifest.xml`: VPN service declaration, BIND_VPN_SERVICE and foreground-service permissions.
- `build.gradle.kts`: links the pinned local `libs/libv2ray.aar`.

Download and verify the AAR from the repository root:

```powershell
.\scripts\setup-xray-core.ps1
```

The script pins AndroidLibXrayLite v26.10.31 and verifies SHA-256 before Gradle can use the artifact.

## Verified upstream API shape

The pinned Go package exposes `Libv2ray.initCoreEnv`, `Libv2ray.newCoreController`, `CoreController.startLoop(configJson, tunFd)`, `CoreController.stopLoop()`, and `CoreController.isRunning`.

Gomobile callback signatures used by the Kotlin bridge (as used by the upstream Android client):

```kotlin
override fun startup(): Long
override fun shutdown(): Long
override fun onEmitStatus(code: Long, message: String?): Long
```

## Important validation still required

This bridge is an initial integration, not a release-ready VPN implementation. Before removing the previous engines or publishing an APK, build against the pinned AAR and verify on a physical Android device:

1. Kotlin/Gomobile signatures compile with the exact AAR.
2. VPN permission prompt, service lifecycle, foreground notification and revocation.
3. Xray core starts with a real VLESS + XHTTP + REALITY config.
4. IPv4 and IPv6 traffic pass, DNS resolves, and there is no traffic leak or routing loop.
5. Stop/reconnect, screen-off, network handover and process recreation.
6. Confirm the Xray TUN integration protects core sockets from VPN recursion. Do not ship if this is not demonstrated.
7. Measure final APK size and inspect packaged native ABIs.

The Flutter UI still uses the previous engines at this stage. Do not delete `sing_box` or `flutter_vless` until the native bridge passes the checks above and all supported profile formats have a tested Xray config conversion path.
