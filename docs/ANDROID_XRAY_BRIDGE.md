# Android native bridge contract (implementation checklist)

This is the contract for the Kotlin/Flutter integration. It must be implemented against the pinned `libv2ray.aar`; do not copy v2rayNG's whole app or its Compose UI.

## Flutter MethodChannel

Channel: `vpn13/xray`

Methods:
- `initialize`: idempotent; initialize Libv2ray environment and create controller/callback.
- `connect`: arguments `{config: String, profileName: String}`; request VPN permission in Activity first; start foreground service; await service result.
- `disconnect`: stop core, close TUN descriptor, stop foreground service.
- `getStatus`: return current state.
- `getStats`: return traffic counters if the pinned library exposes stats APIs; otherwise explicitly report unsupported until implemented.

Event channel: `vpn13/xray/events`
- `state`: connecting / connected / disconnecting / disconnected / error.
- `message`: sanitized native message (never include full profile/config).
- `traffic`: upload/download counters if supported.

## Native lifecycle

1. Activity calls `VpnService.prepare(context)`; if non-null, launch the returned permission Intent and resume connect only after result.
2. Start `Vpn13XrayVpnService` as foreground service with profile name and config. Do not place config in logs or notification text.
3. Service creates Android `VpnService.Builder`, sets session, MTU, IPv4/IPv6 addresses, routes and DNS. Establish TUN and retain `ParcelFileDescriptor`.
4. Initialize `Seq.setContext(applicationContext)`, `Libv2ray.initCoreEnv(assetPath, deviceId)`, create callback and `Libv2ray.newCoreController(callback)`.
5. Call `controller.startLoop(configJson, tunFd)`. Treat errors from config parse/start as failed; verify `controller.isRunning`.
6. Stop: `controller.stopLoop()`, close TUN descriptor exactly once, remove foreground notification and stop service. Handle `onRevoke()`, `onDestroy()`, duplicate start and process restart.
7. Core sockets must be protected from VPN recursion where the exact AndroidLibXrayLite integration requires it. Verify upstream's current approach before shipping.

## Constraints

- Core callback methods are `Startup(): Int`, `Shutdown(): Int`, `OnEmitStatus(int, String): Int`.
- The AAR uses generated Go package `libv2ray`; signatures are Java/Gomobile generated and must be checked by IDE after downloading the pinned AAR.
- Never call blocking core start/stop from the main thread.
- Use a single service/core instance; serialize connect/disconnect.
- Ensure Android manifest includes `BIND_VPN_SERVICE`, foreground service permissions/types and exported=false as appropriate for the target SDK.
- No build should be labeled ready until the Android native project is tracked/reproducible and device traffic tests pass.
