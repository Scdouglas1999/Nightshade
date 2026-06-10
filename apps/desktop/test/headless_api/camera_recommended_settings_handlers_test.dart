import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/backend/disconnected_backend.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    show CameraRecommendedSettings;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_desktop/headless_api/handlers/device_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GET /api/camera/recommended-settings', () {
    late ProviderContainer container;
    late DeviceHandlers handlers;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith((ref) => _TestBackendNotifier(ref)),
        ],
      );
      handlers = DeviceHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'returns 200 with full CameraRecommendedSettings JSON shape',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleCameraGetRecommendedSettings(
            Request(
              'GET',
              Uri.parse(
                'http://localhost/api/camera/recommended-settings'
                '?deviceId=native:zwo:1',
              ),
            ),
          ),
        );

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body, containsPair('unityGain', 120));
        expect(body, containsPair('hcgGain', isNull));
        expect(body, containsPair('defaultOffset', 30));
        expect(body, containsPair('notes', 'fixture'));
      },
    );

    test('returns 400 when deviceId query parameter is missing', () async {
      final response = await translateHandlerErrors(
        handlers.handleCameraGetRecommendedSettings(
          Request(
            'GET',
            Uri.parse('http://localhost/api/camera/recommended-settings'),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
      expect(body['error'], contains('deviceId'));
    });
  });
}

class _FixtureBackend extends DisconnectedBackend {
  @override
  Future<CameraRecommendedSettings> cameraGetRecommendedSettings(
    String deviceId,
  ) async {
    // Returns a deterministic non-empty struct so the handler test can
    // assert the wire shape exactly (unityGain present, hcgGain null,
    // defaultOffset present, notes carried through).
    return const CameraRecommendedSettings(
      unityGain: 120,
      defaultOffset: 30,
      notes: 'fixture',
    );
  }
}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref) {
    state = _FixtureBackend();
  }
}
