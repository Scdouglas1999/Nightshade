/// Declarative route table for the target catalog CRUD surface.
///
/// Counterpart to `handlers/target_handlers.dart`. The literal sub-paths
/// (`favorites`, `search`, `by-type`, `by-priority`) MUST register
/// before the parametric `<id>` route or shelf_router will match
/// `favorites` etc. as the path-param value.
library;

import '../handlers/target_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [TargetHandlers].
List<HeadlessRoute> buildTargetRoutes(TargetHandlers h) => <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/targets', h.handleGetAllTargets),
      HeadlessRoute(HttpMethod.get, '/api/targets/favorites',
          h.handleGetFavoriteTargets),
      HeadlessRoute(
          HttpMethod.get, '/api/targets/search', h.handleSearchTargets),
      HeadlessRoute(
          HttpMethod.get, '/api/targets/by-type', h.handleGetTargetsByType),
      HeadlessRoute(HttpMethod.get, '/api/targets/by-priority',
          h.handleGetTargetsByPriority),
      HeadlessRoute(
          HttpMethod.get, '/api/targets/<id>', h.handleGetTargetById),
      HeadlessRoute(HttpMethod.post, '/api/targets', h.handleCreateTarget),
      HeadlessRoute(HttpMethod.put, '/api/targets/<id>', h.handleUpdateTarget),
      HeadlessRoute(
          HttpMethod.delete, '/api/targets/<id>', h.handleDeleteTarget),
      HeadlessRoute(HttpMethod.post, '/api/targets/<id>/favorite',
          h.handleToggleFavorite),
      HeadlessRoute(HttpMethod.put, '/api/targets/<id>/progress',
          h.handleUpdateProgress),
    ];
