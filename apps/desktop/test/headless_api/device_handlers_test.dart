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

    test('last image jpeg missing deviceId returns bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleCameraGetLastImageJpeg(
        Request('GET', Uri.parse('http://localhost/api/camera/last-image/jpeg')),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
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

    test(
        'filter wheel get position returns 200 with null fields when '
        'disconnected', () async {
      // Why: with no driver connected (the bare ProviderContainer state),
      // FilterWheelStateNotifier reports
      // (currentPosition=null, isMoving=false, filterNames=[]). The
      // handler should still respond 200 with `position: null,
      // name: null, isMoving: false` — disconnection is not an error,
      // it's a real state phones need to render.
      final response = await translateHandlerErrors(
        handlers.handleFilterWheelGetPosition(
          Request(
            'GET',
            Uri.parse('http://localhost/api/filter-wheel/position'),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['position'], isNull);
      expect(body['name'], isNull);
      expect(body['isMoving'], isFalse);
    });
  });
}
