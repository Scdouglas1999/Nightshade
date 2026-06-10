/// Declarative route table for the P2-11 plugin-management surface.
///
/// Counterpart to `handlers/plugin_handlers.dart`. The upload endpoint
/// uses the raw body for the archive bytes; the `filename` and
/// optional `sha256` come in as query parameters (same shape as
/// `/api/catalog/upload`).
///
/// Order constraint: the literal `upload` sub-path MUST register
/// before any `<pluginId>` route on `/api/plugins`.
library;

import '../handlers/plugin_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PluginHandlers].
List<HeadlessRoute> buildPluginRoutes(PluginHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/plugins', h.handleListPlugins),
  HeadlessRoute(HttpMethod.post, '/api/plugins/upload', h.handleUploadPlugin),
  HeadlessRoute(
    HttpMethod.post,
    '/api/plugins/<pluginId>/enable',
    h.handleEnablePlugin,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/plugins/<pluginId>/disable',
    h.handleDisablePlugin,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/plugins/<pluginId>',
    h.handleUninstallPlugin,
  ),
];
