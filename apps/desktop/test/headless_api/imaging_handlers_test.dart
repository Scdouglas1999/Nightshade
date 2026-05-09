import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/imaging_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('ImagingHandlers', () {
    late ProviderContainer container;
    late ImagingHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = ImagingHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('star crops missing device ID returns JSON bad request', () async {
      final response = await handlers.handleGetStarCrops(
        Request('GET', Uri.parse('http://localhost/api/imaging/star-crops')),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], "Missing 'deviceId' parameter.");
    });

    test('plate solve malformed payload returns JSON internal error', () async {
      final response = await handlers.handlePlateSolve(
        Request(
          'POST',
          Uri.parse('http://localhost/api/plate-solve'),
          body: jsonEncode({}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('raw image invalid backend call returns JSON internal error',
        () async {
      final response = await handlers.handleGetLastRawImageData(
        Request(
          'GET',
          Uri.parse('http://localhost/api/imaging/raw?deviceId=camera-1'),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
