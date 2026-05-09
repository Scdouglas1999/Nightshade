import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/filesystem_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('FileSystemHandlers', () {
    late ProviderContainer container;
    late FileSystemHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = FileSystemHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('browse returns directory entries with JSON helper headers', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('nightshade_browse_test_');
      final childDir = await Directory('${tempDir.path}/child').create();
      final response = await handlers.handleBrowseDirectories(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/files/browse?path=${Uri.encodeQueryComponent(tempDir.path)}',
          ),
        ),
      );

      try {
        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['currentPath'], isNotNull);
        final directories = body['directories'] as List;
        expect(
          directories.any((entry) => entry is Map && entry['name'] == 'child'),
          isTrue,
        );
        expect(await childDir.exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('browse reports missing directory as JSON not found', () async {
      final missingPath = Directory.systemTemp
          .createTempSync('nightshade_missing_parent_')
          .path;
      await Directory(missingPath).delete(recursive: true);

      final response = await handlers.handleBrowseDirectories(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/files/browse?path=${Uri.encodeQueryComponent(missingPath)}',
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.notFound);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Directory not found');
    });

    test('validate directory reports required path errors as JSON', () async {
      final response = await handlers.handleValidateDirectory(
        Request(
          'POST',
          Uri.parse('http://localhost/api/files/validate'),
          body: jsonEncode({'path': ''}),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['valid'], isFalse);
      expect(body['error'], 'Path is required');
    });
  });
}
