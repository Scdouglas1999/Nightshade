import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/filesystem_handlers.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSystemHandlers', () {
    late ProviderContainer container;
    late FileSystemHandlers handlers;

    setUp(() {
      container = ProviderContainer(
        overrides: [appSettingsProvider.overrideWith(_TestSettings.new)],
      );
      handlers = FileSystemHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('browse returns allow-listed roots with JSON helper headers',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleBrowseDirectories(
        Request(
          'GET',
          Uri.parse('http://localhost/api/files/browse'),
        ),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['currentPath'], isNull);
      expect(body['directories'], isA<List>());
    });

    test('browse reports missing directory as JSON not found', () async {
      final missingPath = Directory.systemTemp
          .createTempSync('nightshade_missing_parent_')
          .path;
      await Directory(missingPath).delete(recursive: true);

      final response =
          await translateHandlerErrors(handlers.handleBrowseDirectories(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/files/browse?path=${Uri.encodeQueryComponent(missingPath)}',
          ),
        ),
      ));

      expect(response.statusCode, HttpStatus.notFound);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Directory not found');
    });

    test('validate directory reports required path errors as JSON', () async {
      final response =
          await translateHandlerErrors(handlers.handleValidateDirectory(
        Request(
          'POST',
          Uri.parse('http://localhost/api/files/validate'),
          body: jsonEncode({'path': ''}),
        ),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['valid'], isFalse);
      expect(body['error'], 'Path is required');
    });
  });
}

class _TestSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState();
}
