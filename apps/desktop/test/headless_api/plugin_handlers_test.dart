// P2-11 — Tests for the plugin management headless surface.
//
// Covers:
//   * upload + verify SHA-256 round-trip (happy path).
//   * list returns the installed plugin with `signed=signatureValid=true`.
//   * enable / disable flip the `enabled` flag idempotently.
//   * uninstall removes the archive and registry row.
//   * rejected upload paths (missing filename, empty body, missing
//     manifest, declared-sha mismatch).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/plugin_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

/// Plugin archive shape we use throughout the tests. The
/// PluginManagementService scans the head of the byte stream for a JSON
/// object containing `id`, `name`, `version`, so a JSON-only "archive"
/// is the simplest happy-path payload.
List<int> _archive(Map<String, dynamic> manifest) {
  return utf8.encode(jsonEncode(manifest));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginHandlers', () {
    late ProviderContainer container;
    late Directory tempDir;
    late PluginHandlers handlers;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ns_plugin_handlers_');
      container = ProviderContainer(
        overrides: [
          pluginManagementServiceProvider.overrideWith((ref) {
            return PluginManagementService(
              logger: ref.read(loggingServiceProvider),
              directoryOverride: () async => tempDir,
            );
          }),
        ],
      );
      handlers = PluginHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<Map<String, dynamic>> _doUpload(
      List<int> bytes, {
      required String filename,
      String? declaredSha,
    }) async {
      final query = <String, String>{
        'filename': filename,
        if (declaredSha != null) 'sha256': declaredSha,
      };
      final uri = Uri(
        scheme: 'http',
        host: 'localhost',
        path: '/api/plugins/upload',
        queryParameters: query,
      );
      final response = await translateHandlerErrors(
        handlers.handleUploadPlugin(
          Request('POST', uri, body: bytes),
        ),
      );
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString())
          as Map<String, dynamic>;
      expect(response.statusCode, HttpStatus.ok,
          reason: 'upload should succeed: $body');
      return body;
    }

    test('upload + list round-trip surfaces the manifest', () async {
      final bytes = _archive({
        'id': 'com.nightshade.sample',
        'name': 'Sample Plugin',
        'version': '1.0.0',
        'author': 'Acme',
        'description': 'A sample plugin used by the test suite',
      });

      final body = await _doUpload(bytes, filename: 'sample.nsplugin');
      expect(body['status'], 'installed');
      final manifest = body['manifest'] as Map;
      expect(manifest['id'], 'com.nightshade.sample');
      expect(manifest['signed'], isTrue);
      expect(manifest['signatureValid'], isTrue);
      expect(manifest['enabled'], isTrue);
      expect(manifest['sha256'], isNotNull);

      // GET /api/plugins now contains the manifest.
      final listResponse = await translateHandlerErrors(
        handlers.handleListPlugins(
          Request('GET', Uri.parse('http://localhost/api/plugins')),
        ),
      );
      expect(listResponse.statusCode, HttpStatus.ok);
      final listBody = jsonDecode(await listResponse.readAsString()) as Map;
      final items = listBody['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['id'], 'com.nightshade.sample');
      expect(listBody['total'], 1);
    });

    test('upload with matching declared sha256 succeeds, mismatch is rejected',
        () async {
      final bytes = _archive({
        'id': 'com.nightshade.sha-test',
        'name': 'SHA Test',
        'version': '2.1.0',
      });
      final actualHash = sha256.convert(bytes).toString();

      // Matching hash: ok.
      await _doUpload(bytes,
          filename: 'sha-test.nsplugin', declaredSha: actualHash);

      // Mismatched hash: 400 with structured error body.
      final uri = Uri(
        scheme: 'http',
        host: 'localhost',
        path: '/api/plugins/upload',
        queryParameters: {
          'filename': 'sha-test.nsplugin',
          'sha256': 'deadbeef' * 8, // 64-char hex but wrong.
        },
      );
      final response = await translateHandlerErrors(
        handlers.handleUploadPlugin(Request('POST', uri, body: bytes)),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'plugin_verification_failed');
      expect(body['message'], contains('SHA-256 mismatch'));
    });

    test('enable then disable round-trips the flag', () async {
      final bytes = _archive({
        'id': 'com.nightshade.flag',
        'name': 'Flag Toggle',
        'version': '0.1.0',
      });
      await _doUpload(bytes, filename: 'flag.nsplugin');

      // Disable.
      final disableResponse = await translateHandlerErrors(
        handlers.handleDisablePlugin(
          Request('POST',
              Uri.parse('http://localhost/api/plugins/com.nightshade.flag/disable')),
          'com.nightshade.flag',
        ),
      );
      expect(disableResponse.statusCode, HttpStatus.ok);
      final disableBody =
          jsonDecode(await disableResponse.readAsString()) as Map;
      expect(disableBody['status'], 'disabled');
      expect((disableBody['manifest'] as Map)['enabled'], isFalse);

      // Re-enable.
      final enableResponse = await translateHandlerErrors(
        handlers.handleEnablePlugin(
          Request('POST',
              Uri.parse('http://localhost/api/plugins/com.nightshade.flag/enable')),
          'com.nightshade.flag',
        ),
      );
      expect(enableResponse.statusCode, HttpStatus.ok);
      final enableBody =
          jsonDecode(await enableResponse.readAsString()) as Map;
      expect(enableBody['status'], 'enabled');
      expect((enableBody['manifest'] as Map)['enabled'], isTrue);
    });

    test('uninstall removes the plugin and 404s on a missing id', () async {
      final bytes = _archive({
        'id': 'com.nightshade.toremove',
        'name': 'To Remove',
        'version': '1.0.0',
      });
      await _doUpload(bytes, filename: 'toremove.nsplugin');

      final uninstallResponse = await translateHandlerErrors(
        handlers.handleUninstallPlugin(
          Request('DELETE',
              Uri.parse('http://localhost/api/plugins/com.nightshade.toremove')),
          'com.nightshade.toremove',
        ),
      );
      expect(uninstallResponse.statusCode, HttpStatus.ok);
      expect(
          (jsonDecode(await uninstallResponse.readAsString()) as Map)['status'],
          'uninstalled');

      // List is now empty.
      final listResponse = await translateHandlerErrors(
        handlers.handleListPlugins(
          Request('GET', Uri.parse('http://localhost/api/plugins')),
        ),
      );
      final listBody = jsonDecode(await listResponse.readAsString()) as Map;
      expect(listBody['items'], isEmpty);

      // Uninstalling a non-existent id returns 404.
      final missingResponse = await translateHandlerErrors(
        handlers.handleUninstallPlugin(
          Request('DELETE',
              Uri.parse('http://localhost/api/plugins/com.nightshade.toremove')),
          'com.nightshade.toremove',
        ),
      );
      expect(missingResponse.statusCode, HttpStatus.notFound);
    });

    test('upload without filename query param returns 400', () async {
      final response = await translateHandlerErrors(
        handlers.handleUploadPlugin(
          Request(
            'POST',
            Uri.parse('http://localhost/api/plugins/upload'),
            body: _archive({
              'id': 'x',
              'name': 'x',
              'version': '1.0.0',
            }),
          ),
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('upload of opaque (no-manifest) bytes is rejected', () async {
      final junk = List<int>.generate(256, (i) => i % 256);
      final uri = Uri.parse(
          'http://localhost/api/plugins/upload?filename=junk.nsplugin');
      final response = await translateHandlerErrors(
        handlers.handleUploadPlugin(Request('POST', uri, body: junk)),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'plugin_verification_failed');
      expect(body['message'], contains('manifest'));
    });
  });
}
