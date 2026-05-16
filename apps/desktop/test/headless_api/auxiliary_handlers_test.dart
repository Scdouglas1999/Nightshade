import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/auxiliary_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('AuxiliaryHandlers', () {
    late ProviderContainer container;
    late AuxiliaryHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = AuxiliaryHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('cover status reports missing deviceId as JSON bad request', () async {
      final response = await translateHandlerErrors(handlers.handleCoverStatus(
        Request('GET', Uri.parse('http://localhost/api/cover/status')),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'deviceId query parameter is required');
    });

    test('switch set reports missing deviceId as JSON bad request', () async {
      final response = await translateHandlerErrors(handlers.handleSwitchSet(
        Request(
          'POST',
          Uri.parse('http://localhost/api/switch/set'),
          body: jsonEncode({'switchId': 0, 'value': true}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'deviceId is required');
    });

    test('cover brightness validates required and non-negative values',
        () async {
      final missingDevice =
          await translateHandlerErrors(handlers.handleCoverBrightness(
        Request(
          'POST',
          Uri.parse('http://localhost/api/cover/brightness'),
          body: jsonEncode({'brightness': 10}),
        ),
      ));
      expect(missingDevice.statusCode, HttpStatus.badRequest);
      expect(missingDevice.headers['content-type'], 'application/json');
      expect(
        (jsonDecode(await missingDevice.readAsString()) as Map)['error'],
        'deviceId is required',
      );

      final negativeBrightness =
          await translateHandlerErrors(handlers.handleCoverBrightness(
        Request(
          'POST',
          Uri.parse('http://localhost/api/cover/brightness'),
          body: jsonEncode({'deviceId': 'cover-1', 'brightness': -1}),
        ),
      ));
      expect(negativeBrightness.statusCode, HttpStatus.badRequest);
      expect(
        (jsonDecode(await negativeBrightness.readAsString()) as Map)['error'],
        'Value must be >= 0.0',
      );
    });

    test('calibrator on validates defaultable brightness before bridge calls',
        () async {
      final response = await translateHandlerErrors(handlers.handleCalibratorOn(
        Request(
          'POST',
          Uri.parse('http://localhost/api/cover/calibrator-on'),
          body: jsonEncode({'deviceId': 'cover-1', 'brightness': -10}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Value must be >= 0.0');
    });
  });
}
