/// The authentication-exempt surface of the headless API, in one place.
///
/// Two things need this set and they must never disagree: `_authMiddleware`
/// waves these paths through without a bearer token, and `GET /api/info`
/// publishes them as `publicEndpoints` so a client can tell what it may call
/// before it holds one. They used to be two hand-written copies, and the
/// published copy had drifted — it omitted `/api/broadcast/info`,
/// `/api/broadcast/live-stack`, `/api/broadcast/sse`, `/broadcast`, `/` and
/// `/favicon.ico`, every one of which the middleware serves unauthenticated.
/// The middleware and the catalog now read the same declaration.
library;

/// Exact paths served without a bearer token.
///
/// Pairing endpoints are public because a client has no token until the user
/// completes the first pairing flow; the code shown on the desktop console is
/// the out-of-band trust factor. The broadcast endpoints carry their own
/// access gate (the LiveStackingNode's `auth_token`, constant-time compared
/// inside `BroadcastService.authorize`) so an audience phone can reach them
/// unpaired. `/` only redirects or answers a JSON pointer, and `/favicon.ico`
/// is requested unprompted by every browser.
const Set<String> publicApiPaths = {
  '/api/info',
  '/api/pairing/start',
  '/api/pairing/verify',
  // One-tap LAN pairing. Pre-auth like start/verify; the handler enforces the
  // private-LAN source-address + lanOpen-policy gate itself.
  '/api/pairing/lan-claim',
  '/api/broadcast/info',
  '/api/broadcast/live-stack',
  '/api/broadcast/sse',
  '/broadcast',
  // Public browser pairing page: static HTML that drives the (already-public)
  // pairing endpoints client-side, so an operator can pair from any LAN
  // browser without the mobile app or terminal access.
  '/pair',
  '/',
  '/favicon.ico',
};

/// Roots whose whole subtree is served without a bearer token.
///
/// These are the two SPA bundles, which must load before the user has any
/// token at all. Once the loaded page calls `/api/*` it attaches the bearer
/// token like every other client, so only the bundle is exempt. The match is
/// the root itself or a child of it, mirroring the `'/dashboard'`,
/// `'/dashboard/'`, `'/dashboard/<path|.*>'` triples in
/// `routes/static_file_routes.dart`.
const Set<String> publicApiPathRoots = {'/dashboard', '/run-watch'};

/// Whether [path] is served without authentication.
bool isPublicApiPath(String path) {
  if (publicApiPaths.contains(path)) return true;
  for (final root in publicApiPathRoots) {
    if (path == root || path.startsWith('$root/')) return true;
  }
  return false;
}

/// The exempt surface as `GET /api/info` publishes it: every exact path plus
/// every subtree root, sorted so the catalog is stable across restarts. Each
/// entry is itself reachable unauthenticated, and a root entry stands for its
/// subtree exactly as the middleware matches it.
List<String> publishedPublicEndpoints() =>
    <String>[...publicApiPaths, ...publicApiPathRoots]..sort();
