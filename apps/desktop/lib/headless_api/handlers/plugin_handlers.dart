// Plugin management endpoints.
//
// Endpoints:
//   GET    /api/plugins              — list installed plugins
//   POST   /api/plugins/upload       — multipart-ish: body=bytes, ?filename=
//   POST   /api/plugins/<id>/enable  — flip enabled flag on
//   POST   /api/plugins/<id>/disable — flip enabled flag off
//   DELETE /api/plugins/<id>         — uninstall (removes the archive +
//                                       registry row)
//
// Why a separate handler file: every other functional area gets one and
// this one is small but completely self-contained. The headless server
// only needs to instantiate the handler and bind four routes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

class PluginHandlers {
  final ProviderContainer container;

  PluginHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);
  PluginManagementService get _service =>
      container.read(pluginManagementServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'PluginHandlers');

  /// GET /api/plugins
  Future<Response> handleListPlugins(Request request) async {
    _logInfo('[API] GET /api/plugins');
    final plugins = await _service.listPlugins();
    return jsonOk({
      'items': plugins.map((p) => p.toJson()).toList(growable: false),
      'total': plugins.length,
    });
  }

  /// POST /api/plugins/upload?filename=&sha256=
  ///
  /// Body is the raw archive bytes. `?filename=` is required so the
  /// service can name the on-disk copy. `?sha256=` is optional: when
  /// supplied, the server recomputes the digest of the received bytes
  /// and rejects the upload if it disagrees. This is the real
  /// signature scheme for this wave — see PluginManagementService docs.
  Future<Response> handleUploadPlugin(Request request) async {
    _logInfo('[API] POST /api/plugins/upload');

    final filename = request.url.queryParameters['filename']?.trim();
    if (filename == null || filename.isEmpty) {
      throw BadRequestError(
        field: 'filename',
        expected: 'non-empty string',
        message:
            'POST /api/plugins/upload requires a `filename` query parameter',
      );
    }
    final declaredSha256 = request.url.queryParameters['sha256']
        ?.trim()
        .toLowerCase();

    // Buffer the whole body. Plugins are small (manifests + a few
    // hundred KB of Dart code at most) so a streaming pipeline is
    // overkill; the request-size middleware already caps the body.
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw BadRequestError(
        field: 'body',
        expected: 'non-empty plugin archive',
        message: 'Plugin upload body must not be empty',
      );
    }

    try {
      final manifest = await _service.installFromBytes(
        bytes,
        filename: filename,
        declaredSha256: (declaredSha256 == null || declaredSha256.isEmpty)
            ? null
            : declaredSha256,
      );
      return jsonOk({'status': 'installed', 'manifest': manifest.toJson()});
    } on PluginVerificationException catch (e) {
      // Surface the verification message verbatim so a remote operator
      // can see what failed (digest mismatch / missing manifest field /
      // etc.) without having to read the server log.
      return jsonBadRequest({
        'error': 'plugin_verification_failed',
        'message': e.reason,
      });
    }
  }

  /// POST `/api/plugins/<id>/enable`
  Future<Response> handleEnablePlugin(Request request, String pluginId) async {
    _logInfo('[API] POST /api/plugins/$pluginId/enable');
    return _setEnabled(pluginId, true);
  }

  /// POST `/api/plugins/<id>/disable`
  Future<Response> handleDisablePlugin(Request request, String pluginId) async {
    _logInfo('[API] POST /api/plugins/$pluginId/disable');
    return _setEnabled(pluginId, false);
  }

  Future<Response> _setEnabled(String pluginId, bool enabled) async {
    if (pluginId.trim().isEmpty) {
      throw BadRequestError(field: 'pluginId', expected: 'non-empty string');
    }
    try {
      final manifest = await _service.setEnabled(pluginId, enabled);
      return jsonOk({
        'status': enabled ? 'enabled' : 'disabled',
        'manifest': manifest.toJson(),
      });
    } on PluginNotFoundException {
      return jsonNotFound({'error': 'plugin_not_found', 'pluginId': pluginId});
    }
  }

  /// DELETE `/api/plugins/<id>`
  Future<Response> handleUninstallPlugin(
    Request request,
    String pluginId,
  ) async {
    _logInfo('[API] DELETE /api/plugins/$pluginId');
    if (pluginId.trim().isEmpty) {
      throw BadRequestError(field: 'pluginId', expected: 'non-empty string');
    }
    try {
      await _service.uninstall(pluginId);
      return jsonOk({'status': 'uninstalled', 'pluginId': pluginId});
    } on PluginNotFoundException {
      return jsonNotFound({'error': 'plugin_not_found', 'pluginId': pluginId});
    }
  }
}
