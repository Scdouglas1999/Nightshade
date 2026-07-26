/// Declarative route table for the plugin-management surface.
///
/// Counterpart to `handlers/plugin_handlers.dart`. The upload route remains
/// registered for protocol compatibility and reports 501 because Dart AOT
/// cannot load uploaded plugin code.
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
