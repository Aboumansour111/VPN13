# VPN13 server list

The Android client downloads `servers.json` directly from this directory. No separate API server is required.

## Add a server

Edit `servers.json` and add an object to the `servers` array:

- `id`: unique integer; do not reuse IDs for different servers.
- `name`: display name shown in the app.
- `description`: optional short label.
- `config`: complete sing-box configuration as a JSON string. It must be a configuration accepted by the sing-box engine used by the app.

Example structure (replace the placeholder with a real, valid sing-box configuration):

```json
{
  "version": 1,
  "servers": [
    {
      "id": 1,
      "name": "Germany 1",
      "description": "VLESS / Reality",
      "config": "{ \"log\": { \"level\": \"warn\" }, \"outbounds\": [] }"
    }
  ]
}
```

The example config is illustrative only and is not connectable. Never put private credentials or server configurations in a public repository: anyone can read them. If the repository is public, every configuration committed here is public.
