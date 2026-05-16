import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/device_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('DeviceHandlers', () {
    late ProviderContainer container;
    late DeviceHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = DeviceHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('camera expose malformed payload returns JSON internal error',
        () async {
      final response = await translateHandlerErrors(handlers.handleCameraExpose(
        Request(
          'POST',
          Uri.parse('http://localhost/api/camera/expose'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('mount slew malformed payload returns JSON internal error', () async {
      final response = await translateHandlerErrors(handlers.handleMountSlew(
        Request(
          'POST',
          Uri.parse('http://localhost/api/mount/slew'),
          body: jsonEncode({'deviceId': 'mount-1'}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('rotator halt malformed payload returns JSON internal error',
        () async {
      final response = await translateHandlerErrors(handlers.handleRotatorHalt(
        Request(
          'POST',
          Uri.parse('http://localhost/api/rotator/halt'),
          body: '{',
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
