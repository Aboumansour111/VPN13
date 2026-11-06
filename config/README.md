# VPN13 server list

The Android client downloads this file directly from GitHub. No separate backend is required.

## Add a server

Add one object for each server inside the `servers` array:

- `id`: unique integer.
- `name`: server name shown in the app.
- `description`: optional label, such as protocol or location.
- `config`: paste the complete share link exactly as received. Do not convert it to JSON.

Example:

```json
{
  "version": 1,
  "servers": [
    {
      "id": 1,
      "name": "سوئد",
      "description": "VLESS Reality",
      "config": "vless://UUID@SERVER:PORT?encryption=none&security=reality&sni=example.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#Sweden"
    },
    {
      "id": 2,
      "name": "آلمان",
      "description": "VMess",
      "config": "vmess://BASE64_CONFIGURATION"
    }
  ]
}
```

Keep valid JSON syntax:
- Put a comma between server objects, but not after the last object.
- Use double quotes around keys and values.
- If a link contains a double quote or backslash, escape it as required by JSON.
- Every server must have a different `id`.

The app's sing-box engine accepts supported share links directly, including VLESS, VMess, Trojan, Shadowsocks, Hysteria, Hysteria2, TUIC, AnyTLS, WireGuard, SOCKS and HTTP. Support for individual link options depends on the protocol and sing-box core version.

You can also put a complete sing-box configuration in `config` instead of a share link.

## Privacy warning

If this GitHub repository is public, every link and its credentials stored here are publicly readable. Do not publish private subscription URLs or credentials unless you intend them to be public.
