import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/focus_model_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  group('FocusModelHandlers', () {
    late Directory tempDir;
    late ProviderContainer container;
    late FocusModelHandlers handlers;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('focus-model-handler-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
      container = ProviderContainer();
      handlers = FocusModelHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('get focus data without active profile returns JSON bad request',
        () async {
      final response = await handlers.handleGetFocusData(
        Request('GET', Uri.parse('http://localhost/api/focus-model/data')),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'No active equipment profile. Load a profile first.',
      );
    });

    test('predict without active profile returns JSON bad request', () async {
      final response = await handlers.handlePredictFocus(
        Request(
          'GET',
          Uri.parse('http://localhost/api/focus-model/predict'),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'No active equipment profile. Load a profile first.',
      );
    });

    test('import without active profile returns JSON bad request', () async {
      final response = await handlers.handleImportFocusData(
        Request(
          'POST',
          Uri.parse('http://localhost/api/focus-model/import'),
          body: '{',
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'No active equipment profile. Load a profile first.',
      );
    });
  });
}
