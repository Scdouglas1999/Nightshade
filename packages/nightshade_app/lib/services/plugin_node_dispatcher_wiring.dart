// Wires the `pluginNodeDispatcherProvider` (defined in
// `nightshade_core`) to the real `PluginNodeExecutor` (defined in
// `nightshade_plugins`).
//
// `nightshade_core` does NOT depend on `nightshade_plugins` — the
// dispatcher abstraction is intentionally kept in core so the sequence
// executor can route plugin requests without a circular dependency.
// This file lives in `nightshade_app` (the only package that already
// depends on both) and provides the `pluginNodeDispatcherOverride`
// helper that the desktop / mobile entry point installs in its
// `ProviderScope`.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';

/// Build the Riverpod override that swaps the default unwired
/// dispatcher stub for one backed by the real plugin host + executor.
///
/// Use in the app entry point:
///
/// ```dart
/// final container = ProviderContainer(
///   overrides: [
///     backendProvider.overrideWith(...),
///     pluginNodeDispatcherOverride(),
///   ],
/// );
/// ```
Override pluginNodeDispatcherOverride() {
  return pluginNodeDispatcherProvider.overrideWith((ref) {
    // Build one PluginNodeExecutor per ProviderContainer. The executor
    // is stateless (it resolves the registration on every call) so a
    // single instance is fine to share across every sequencer request.
    final host = ref.watch(pluginHostProvider);
    final registry = ref.watch(pluginNodeRegistryProvider);
    final executor = PluginNodeExecutor(host: host, registry: registry);

    return (request) async {
      // Parse the opaque config JSON the Rust side forwarded. Empty /
      // unparseable JSON degrades to an empty params map; the plugin's
      // own `validate()` is the canonical surface for "this config is
      // bad" errors.
      Map<String, dynamic> params = const {};
      if (request.configJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(request.configJson);
          if (decoded is Map<String, dynamic>) {
            params = decoded;
          } else if (decoded is Map) {
            // jsonDecode on a JSON object returns Map<String, dynamic>
            // already, but some toolchains produce a Map<dynamic,
            // dynamic> when the source is hand-built. Coerce by key.
            params = decoded.map((k, v) => MapEntry(k.toString(), v));
          }
        } catch (_) {
          // Fall through with an empty map; the plugin will surface
          // the validation error itself.
        }
      }

      final result = await executor.run(
        pluginId: request.pluginId,
        nodeTypeId: request.nodeTypeId,
        params: params,
        timeout: Duration(seconds: request.timeoutSecs),
      );

      // Plugins MAY return an opaque message — we surface it as-is via
      // both the verdict message AND a synthetic structured detail so
      // the dashboard's plugin-node panel has something to render even
      // when the plugin author didn't author one.
      final detailObject = <String, dynamic>{
        'plugin_id': request.pluginId,
        'node_type_id': request.nodeTypeId,
        'success': result.success,
        if (result.message != null) 'message': result.message,
      };

      return PluginNodeDispatchResult(
        success: result.success,
        message: result.message,
        structuredDetailJson: jsonEncode(detailObject),
      );
    };
  });
}
