# Headless Secure Setup

Nightshade headless mode runs the desktop backend without the Flutter UI and
exposes the remote-control API for browser, mobile, and automation clients.
Treat it like rig-control infrastructure: bind narrowly by default, require a
token before LAN exposure, and verify the server before connecting devices.

## Network Modes

| Mode | Binding | Authentication | Intended Use |
|------|---------|----------------|--------------|
| Local loopback | `127.0.0.1` | Optional | Same-machine automation, reverse proxy, development |
| Authenticated LAN | LAN interface | Required | Mobile or browser control from trusted LAN clients |
| Unauthenticated LAN | LAN interface | None | Isolated development networks only |

The headless entry point binds to loopback unless one of these is true:

- `--auth-token=<token>` is provided.
- `NIGHTSHADE_AUTH_TOKEN` is set.
- `--require-auth` is provided, which generates a token at startup.
- `--allow-unauthenticated-lan` or
  `NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN=true` is provided.

Do not use unauthenticated LAN mode for normal imaging. It exposes control
commands such as slew, park, device connect, sequence start, and backup restore
to any client that can reach the port.

## Start Headless Mode

Development run:

```powershell
flutter run -d windows --target=lib/main_headless.dart -- --require-auth
```

Packaged Windows run:

```powershell
.\build\windows\x64\runner\Release\nightshade_desktop.exe --headless --require-auth
```

Packaged Linux run:

```bash
./build/linux/x64/release/bundle/nightshade_desktop --headless --require-auth
```

Use a fixed token when clients need a stable credential:

```powershell
$env:NIGHTSHADE_AUTH_TOKEN = "replace-with-a-long-random-token"
$env:NIGHTSHADE_PORT = "8080"
.\nightshade_desktop.exe --headless
```

## Client Authentication

REST clients send the token as a bearer token:

```http
Authorization: Bearer replace-with-a-long-random-token
```

Headless mode supports three token scopes:

| Scope | Intended use | Allowed access |
| --- | --- | --- |
| `view` | Dashboards and monitoring clients | Read ordinary status endpoints and subscribe to WebSocket events. |
| `control` | Imaging-control clients | View access plus device, capture, mount, guider, sequencer, dome, safety, switch, and cover control routes. |
| `admin` | Trusted operators and maintenance tools | Full protected API access, including self-test, settings, file browsing, and backup/restore. |

The legacy `--auth-token` and `NIGHTSHADE_AUTH_TOKEN` values are admin tokens.
Use narrower tokens for clients that do not need administrative access:

```powershell
$env:NIGHTSHADE_VIEW_TOKEN = "replace-with-a-long-random-view-token"
$env:NIGHTSHADE_CONTROL_TOKEN = "replace-with-a-long-random-control-token"
.\nightshade_desktop.exe --headless --auth-token=replace-with-a-long-random-admin-token
```

Equivalent CLI flags are available:

```powershell
.\nightshade_desktop.exe --headless `
  --auth-token=replace-with-a-long-random-admin-token `
  --view-token=replace-with-a-long-random-view-token `
  --control-token=replace-with-a-long-random-control-token
```

WebSocket clients may use the same bearer header when the platform supports it.
Browser-style WebSocket clients can pass the token as a query parameter:

```text
ws://host:8080/events?token=replace-with-a-long-random-token
```

`GET /api/info` and dashboard static files are public so clients can discover
server metadata and load the local dashboard. Control, status, OpenAPI,
self-test, WebSocket, backup, file browsing, and device routes require an
appropriately scoped token when authentication is enabled.

## Firewall And Ports

Allow only the ports needed for the deployment:

| Port | Protocol | Purpose |
|------|----------|---------|
| `8080` or `NIGHTSHADE_PORT` | TCP | REST API, dashboard, WebSocket updates |
| `45679` | UDP | LAN discovery advertisement when LAN binding is enabled |

Keep the TCP API port blocked from untrusted networks. If exposing Nightshade
through a VPN or reverse proxy, terminate TLS at that layer and keep the
headless server bound to loopback when possible.

## Verification Checklist

1. Confirm `/api/info` reports the expected version, platform, auth mode, and
   platform capabilities:

   ```powershell
   Invoke-RestMethod http://localhost:8080/api/info
   ```

2. Confirm authenticated endpoints reject missing credentials:

   ```powershell
   Invoke-WebRequest http://localhost:8080/api/self-test
   ```

   A protected server should return `401 Unauthorized`.

3. Confirm the token works:

   ```powershell
   Invoke-RestMethod `
     -Headers @{ Authorization = "Bearer replace-with-a-long-random-token" } `
     http://localhost:8080/api/self-test
   ```

4. Confirm the OpenAPI route document is available to authenticated clients:

   ```powershell
   Invoke-RestMethod `
     -Headers @{ Authorization = "Bearer replace-with-a-long-random-token" } `
     http://localhost:8080/api/openapi.json
   ```

5. Confirm mobile or browser clients reject incompatible server versions before
   entering remote-control mode.

6. Confirm WebSocket clients send `ping`, receive `pong`, and reconnect after a
   heartbeat timeout.

## Operational Notes

- Use long random tokens and rotate them when a client device is lost.
- Give monitoring clients `view` tokens instead of admin tokens.
- Prefer a dedicated observatory VLAN, VPN, or local-only reverse proxy for
  remote access.
- Keep the machine clock, site location, storage path, and device drivers
  configured before starting an unattended sequence.
- Run `/api/self-test` after updates and before hardware smoke tests.
- Review audit logs for high-risk remote commands after remote sessions.
