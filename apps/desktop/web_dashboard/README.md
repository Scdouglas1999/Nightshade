# Nightshade Web Dashboard

A single-page browser dashboard for the Nightshade headless API.

This SPA lives next to the Run-Watch PWA (`apps/desktop/web_run_watch/`)
and is served by the desktop's `HeadlessApiServer` at `/dashboard/`.
The Run-Watch view is the mobile-first one-glance run monitor; the
dashboard is the laptop-first surface that lets an operator watch and
control a session without installing the desktop app.

## Stack

Vanilla JavaScript, no build step. Two source files do everything:

- `js/api.js` — wraps every `/api/...` endpoint the server exposes,
  plus the `/events` WebSocket and `/api/logs/tail` SSE subscription.
- `js/app.js` — bootstraps the dashboard, handles the WebSocket event
  fan-out, panel rendering, hash routing, gallery, log tail, and the
  login overlay.

CSS lives in `css/dashboard.css`. Markup is `index.html`.

## URL routes (hash-based)

The dashboard is a single-page grid; the hash drives which panel the
operator's eye lands on after a bookmark is opened or a deep link is
shared:

| URL fragment | Panel that scrolls into view |
|--------------|------------------------------|
| `#/run`      | Sequencer (current run)      |
| `#/devices`  | Devices                      |
| `#/gallery`  | Image gallery                |
| `#/logs`     | Server log tail              |
| `#/mount`    | Mount                        |
| `#/camera`   | Camera                       |
| `#/guiding`  | Guiding (PHD2)               |
| `#/sequences`| Saved sequences (ops)        |
| `#/analytics`| Profile + analytics (ops)    |
| `#/planetarium` | Planetarium (remote slew) |
| `#/settings` | Host settings                |

`#/run/<runId>` is reserved for the desktop replay scrubber; on the
web dashboard it currently lands on the sequencer panel and logs a
hint that the deeper replay UI is desktop-only.

## Authentication

On first visit the SPA shows a login overlay. The flow is:

1. The SPA reads `sessionStorage.nightshade_token` — if present, it
   skips the overlay and connects.
2. Otherwise, it calls `GET /api/auth/csrf`: a `200` indicates an
   HttpOnly cookie session is alive and the SPA reuses it.
3. Otherwise, it calls `GET /api/info`: a server reporting
   `authRequired: false` is connected without a token.
4. Otherwise, the overlay surfaces with two options:
   - **Pair this browser** — launches the existing 6-digit pairing
     modal, which calls `POST /api/pairing/start` and
     `POST /api/pairing/verify` to mint a fresh bearer.
   - **Sign in** — uses a bearer token the operator pasted (e.g. from
     the desktop's "Remote Access" screen).

The "Remember on this device for 30 days" toggle controls whether the
SPA upgrades the bearer to an `HttpOnly nightshade_session` cookie via
`POST /api/auth/cookie`. Unticking it keeps the bearer in
`sessionStorage` only, so it dies when the tab closes.

## Live data sources

| Surface | Endpoint | Notes |
|--------|----------|-------|
| Event firehose | `WebSocket /events?ticket=...` | Single-use 60s ticket from `POST /api/ws/ticket`; falls back to `?token=` for compatibility |
| Image preview  | `GET /api/camera/last-image/jpeg`, polled via the camera panel | Driven by `ExposureComplete` events; a 30s grace timer kicks a manual fetch if no event arrives |
| Image gallery  | `GET /api/images?limit=24` + `GET /api/images/<id>/thumbnail` | Modal preview uses the same thumbnail endpoint at higher resolution |
| Log tail       | `EventSource /api/logs/tail?minSeverity=info&access_token=...` | Bearer goes in the query string because EventSource lacks a header API |
| Sequencer state | `GET /api/sequencer/status` + WS sequencer events | WS-driven; REST fallback only when WS is silent for 10s |

## Smoke test recipe

After a code change, manually verify against a running headless
server. The recipe is:

1. **Start the headless server**. From the repo root:

   ```powershell
   cd apps/desktop
   .\start_headless.bat
   ```

   Or run the regular desktop app and check the Remote Access screen
   for the LAN URL.

2. **Open the dashboard** in any browser at the URL the server prints
   (e.g. `http://127.0.0.1:8080/dashboard/`). Expected: the login
   overlay appears.

3. **Pair the browser**. Click "Pair this browser". A 6-digit code
   appears on the desktop console. Type it and click Pair. The
   overlay closes and the dashboard loads with a green "Connected"
   dot in the top bar.

4. **Verify hash routing**. Click each of the Run / Devices / Gallery
   / Logs nav buttons. The URL hash should update (e.g.
   `…/dashboard/#/gallery`) and the matching panel should scroll into
   view with a brighter outline.

5. **Verify the gallery**. Navigate to `#/gallery`. The grid loads
   recent captures via `/api/images?limit=24`. Click a thumbnail —
   the modal preview opens with a "Download original" link.

6. **Verify the log tail**. Navigate to `#/logs`. The "live" badge
   should appear within a second. Trigger a server-side log line
   (e.g. capture an exposure) and confirm it appears in the panel.
   Click Pause → the badge flips to "offline" and the stream
   disconnects. Click Resume → the badge returns to "live".

7. **Verify the run dashboard**. Start a small sequence on the
   desktop and navigate to `#/run`. The sequencer panel should
   update its status, target, current node, and ETA in real time.

8. **Verify the 30-day session**. Tick "Remember on this device" in
   the login overlay before signing in, then close the browser and
   reopen the dashboard URL. Expected: no login overlay; the
   dashboard auto-connects via the HttpOnly cookie. The cookie's
   `Max-Age` is 30 days per `headless_api/handlers/auth_handlers.dart`.

9. **Verify the no-auth path**. Stop the server, set
   `NIGHTSHADE_REQUIRE_AUTH=false`, restart, and re-open the
   dashboard. Expected: no overlay appears at all; the dashboard
   auto-connects.

10. **Manually exercise edge cases**:
    - Disconnect the server while the dashboard is open — the status
      dot should turn red and the WS should reconnect with backoff.
    - Pause the log tail, trigger 200 log lines, then resume — the
      stream should reattach without dropping the panel's scroll
      position.
    - Type a malformed token into the login overlay — the status
      line should surface the server's `401` text instead of failing
      silently.

If any of these steps fails, treat it as a regression. The dashboard
covers remote control via the headless API only — full GPU planetarium
rendering remains desktop/mobile-only.

## Adding a new endpoint or panel

1. Add the wire method to `NightshadeApi` in `js/api.js` next to the
   existing endpoints. Keep the method name aligned with the server
   route's purpose (e.g. `imagesGetAll`, not `getImageList`).
2. Add markup to `index.html`. Re-use the existing `.panel /
   .panel-header / .panel-body` skeleton.
3. Add CSS to `css/dashboard.css` (the cascade matters — append to
   the file, don't rewrite earlier rules).
4. Wire setup + render functions in `js/app.js`. Hook into the
   `api.on('event', ...)` firehose if the panel needs to react to
   server events; otherwise poll via the existing
   `fetchAllStatus()` loop.
5. If the panel is route-addressable, add a hash route entry to
   `HASH_ROUTES` and a `data-route` nav button to the
   `.capability-nav` row.
