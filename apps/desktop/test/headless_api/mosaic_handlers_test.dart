import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/mosaic_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('MosaicHandlers', () {
    late ProviderContainer container;
    late MosaicHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = MosaicHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    Map<String, Object?> config() => {
          'centerRa': 12.0,
          'centerDec': 30.0,
          'panelWidthArcmin': 60.0,
          'panelHeightArcmin': 40.0,
          'overlapPercent': 10.0,
          'panelsHorizontal': 2,
          'panelsVertical': 2,
        };

    test('generate panels returns JSON helper response', () async {
      final response = await handlers.handleGeneratePanels(
        Request(
          'POST',
          Uri.parse('http://localhost/api/mosaic/generate-panels'),
          body: jsonEncode({'config': config()}),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      final panels = body['panels'] as List;
      expect(panels, hasLength(4));
      expect((panels.first as Map)['panelIndex'], 0);
    });

    test('calculate area returns total panel metadata as JSON', () async {
      final response = await handlers.handleCalculateArea(
        Request(
          'POST',
          Uri.parse('http://localhost/api/mosaic/calculate-area'),
          body: jsonEncode({'config': config()}),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['areaSquareDegrees'], isA<num>());
      expect(body['totalPanels'], 4);
    });

    test('invalid payload returns JSON internal server error', () async {
      final response = await handlers.handleValidateMosaic(
        Request(
          'POST',
          Uri.parse('http://localhost/api/mosaic/validate'),
          body: jsonEncode({'config': {}}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
