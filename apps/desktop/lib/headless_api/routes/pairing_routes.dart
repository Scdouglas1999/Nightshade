/// Declarative route table for the pairing flow.
///
/// Counterpart to `handlers/pairing_handlers.dart`. `/api/pairing/start`
/// and `/api/pairing/verify` are in the global `publicPaths` set
/// (otherwise no client could ever bootstrap a token);
/// `/api/pairing/active` is admin-only and authenticated.
library;

import '../handlers/pairing_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PairingHandlers].
List<HeadlessRoute> buildPairingRoutes(PairingHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.post, '/api/pairing/start', h.handlePairingStart),
  HeadlessRoute(HttpMethod.post, '/api/pairing/verify', h.handlePairingVerify),
  // admin-only view of currently-valid pairing sessions. Behind
  // the auth middleware (the path is NOT in `publicPaths`) and gated
  // to admin scope via `_adminOnlyPaths`. Lets headless operators on
  // a paired admin client retrieve the active code without watching
  // stdout.
  HeadlessRoute(
    HttpMethod.get,
    '/api/pairing/active',
    h.handlePairingActiveList,
  ),
];
