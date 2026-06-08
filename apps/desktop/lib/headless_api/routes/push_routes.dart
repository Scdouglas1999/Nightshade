/// Declarative route table for the cellular-push endpoints (Phase D).
///
/// Counterpart to `handlers/push_handlers.dart`. NONE of these paths are in
/// the global `publicPaths` set — a push-token registration or preference
/// change must come from an already-paired client, so all four routes sit
/// behind the auth middleware (unlike `/api/pairing/{start,verify}`, which
/// have to be public to bootstrap a token in the first place).
library;

import '../handlers/push_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PushHandlers].
List<HeadlessRoute> buildPushRoutes(PushHandlers h) => <HeadlessRoute>[
      HeadlessRoute(
          HttpMethod.post, '/api/push/register-token', h.handleRegisterToken),
      HeadlessRoute(
          HttpMethod.delete, '/api/push/token', h.handleDeleteToken),
      HeadlessRoute(
          HttpMethod.get, '/api/push/preferences', h.handleGetPreferences),
      HeadlessRoute(
          HttpMethod.put, '/api/push/preferences', h.handlePutPreferences),
    ];
