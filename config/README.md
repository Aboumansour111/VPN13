# VPN13 server list

The Android client downloads `servers.json` directly from this directory. No separate API server is required.

## Add a server

Edit `servers.json` and add an object to the `servers` array:

- `id`: unique integer; do not reuse IDs for different servers.
- `name`: display name shown in the app.
- `description`: optional short label.
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
      "config": "vmess://BASE64_OR_SHARE_LINK"
    }
  ]
}
```

Put each share link on one line as the value of `config`. Keep the quotation marks and escape any double quotes if a link format ever contains them. Separate server objects with commas.

The app's sing-box engine accepts common share-link formats including VLESS, VMess, Trojan, Shadowsocks, Hysteria/Hysteria2, TUIC, AnyTLS, WireGuard, SOCKS and HTTP(S). Unsupported transports or malformed links will fail when connecting.

## Important privacy note

The repository is public. Every server link committed here is visible to anyone, including credentials and subscription details embedded in the link. Only publish links you are willing to expose publicly. Do not put private subscription URLs, personal tokens, or credentials in this repository.
