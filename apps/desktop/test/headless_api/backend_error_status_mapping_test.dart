import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_error;
import 'package:nightshade_desktop/headless_api/validation.dart';
import 'package:shelf/shelf.dart';

/// Pins the `NightshadeError` -> HTTP status table in
/// `errorTranslationMiddleware`.
///
/// The table exists so a remote client gets an actionable status instead of an
/// opaque 500, and only genuinely internal faults fall through to `orElse`.
/// Regression driving this file: a completely saturated frame from a real
/// ASI1600MM-Cool answered `500 internal_error`, because the bridge reported the
/// rejection as the unclassified `OperationFailed` and nothing mapped the
/// frame-rejection case. `ExposureFailed` now carries it and maps to 422.
void main() {
  Future<Response> throwing(bridge_error.NightshadeError error) async {
    final handler = errorTranslationMiddleware(
      logError: (_, {fields}) {},
      requestIdFor: (_) => 'test-request-id',
    )((_) => throw error);
    return await handler(Request('POST', Uri.parse('http://localhost/api/x')));
  }

  Future<({int status, Map<String, Object?> body})> call(
    bridge_error.NightshadeError error,
  ) async {
    final response = await throwing(error);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    return (status: response.statusCode, body: body);
  }

  test('a validation-rejected frame is 422, not 500', () async {
    const reason =
        'Image is completely saturated (min value 65224 >= 65024) - '
        'significantly reduce exposure time or gain';
    final result = await call(
      const bridge_error.NightshadeError.exposureFailed(
        cameraId: 'native:zwo:0',
        reason: reason,
      ),
    );

    expect(result.status, 422);
    // Below 500 the envelope must say `device_error`: the camera worked and the
    // server did not fail, so a retry-on-5xx client must not treat this as
    // transient.
    expect(result.body['error'], 'device_error');
    // The operator-actionable reason has to survive to the wire.
    expect(result.body['message'], contains('completely saturated'));
    expect(result.body['message'], contains('reduce exposure time or gain'));
    expect(result.body['requestId'], 'test-request-id');
    // The wire body must never carry the freezed constructor form. Named-field
    // variants have no `field0`, so before this was special-cased the message
    // shipped as
    // "NightshadeError.exposureFailed(cameraId: native:zwo:0, reason: ...)"
    // — observed live against the rig.
    expect(result.body['message'], reason, reason: 'reason verbatim, no wrapper');
    expect(result.body['message'], isNot(contains('NightshadeError')));
    expect(result.body['message'], isNot(contains('cameraId:')));
  });

  test('genuine internal faults still answer 500 internal_error', () async {
    final result = await call(
      const bridge_error.NightshadeError.operationFailed(
        'SDK error: Failed to call method StartExposure',
      ),
    );

    expect(result.status, 500);
    expect(result.body['error'], 'internal_error');
  });

  // Regression: the wire `message` is rendered verbatim by remote/mobile
  // clients, so it must always be a sentence an operator can act on. Observed
  // live on a running instance with no image captured:
  //   GET /api/camera/last-image  -> {"error":"device_error",
  //        "message":"NightshadeError.noImageAvailable()"}
  //   GET /api/imaging/raw-data   -> same
  //   GET /api/run-watch/frame-thumbnail ->
  //        "Failed to fetch last image: NightshadeError.noImageAvailable()"
  // Cause: the message cleaner only unwrapped variants with a single
  // positional `field0`; zero-arg and named-field variants fell through to
  // `toString()`, which is the freezed constructor form.
  test('no variant ever leaks the freezed constructor form', () async {
    final variants = <bridge_error.NightshadeError>[
      // zero-arg
      const bridge_error.NightshadeError.noImageAvailable(),
      const bridge_error.NightshadeError.exposureCancelled(),
      const bridge_error.NightshadeError.cancelled(),
      // named-field, previously unhandled
      const bridge_error.NightshadeError.comError(
        message: 'Member not found',
        hresult: -2147352573,
      ),
      const bridge_error.NightshadeError.ascomError(
        progId: 'ASCOM.ASICamera2.Camera',
        message: 'Gain not implemented',
        errorCode: 1024,
      ),
      const bridge_error.NightshadeError.alpacaError(
        baseUrl: 'http://127.0.0.1:11111',
        deviceNumber: 0,
        message: 'NotImplemented',
        errorCode: 1024,
      ),
      const bridge_error.NightshadeError.indiError(
        server: 'localhost',
        port: 7624,
        deviceName: 'CCD Simulator',
        message: 'BLOB timeout',
      ),
      const bridge_error.NightshadeError.nativeError(
        vendor: 'ZWO',
        message: 'ASI_ERROR_INVALID_SIZE',
        errorCode: 6,
      ),
      const bridge_error.NightshadeError.hardwareError(
        deviceId: 'native:zwo:0',
        message: 'shutter jam',
      ),
      const bridge_error.NightshadeError.communicationError(
        deviceId: 'native:zwo:0',
        message: 'usb stall',
      ),
      const bridge_error.NightshadeError.connectionFailed(
        deviceId: 'native:zwo:0',
        reason: 'device busy',
      ),
      const bridge_error.NightshadeError.deviceDisconnected(
        deviceId: 'native:zwo:0',
        reason: 'cable pulled',
      ),
      const bridge_error.NightshadeError.deviceTimeout(
        deviceId: 'native:zwo:0',
        operation: 'download',
        timeoutSecs: 30,
      ),
      const bridge_error.NightshadeError.connectionTimeout(
        deviceId: 'native:zwo:0',
        timeoutSecs: 10,
      ),
      const bridge_error.NightshadeError.parameterOutOfRange(
        paramName: 'gain',
        value: '99999',
        min: '0',
        max: '600',
      ),
      const bridge_error.NightshadeError.deviceBusy(
        deviceId: 'native:zwo:0',
        currentOperation: 'exposing',
      ),
      const bridge_error.NightshadeError.resourceExhausted(
        resource: 'disk',
        message: 'no space left',
      ),
      const bridge_error.NightshadeError.downloadFailed(
        cameraId: 'native:zwo:0',
        reason: 'usb reset',
      ),
      const bridge_error.NightshadeError.notSupported(
        deviceId: '',
        operation: 'Operation not supported',
      ),
      const bridge_error.NightshadeError.invalidDeviceId(
        deviceId: '',
        reason: 'Invalid INDI device ID format',
      ),
      // positional
      const bridge_error.NightshadeError.operationFailed('sdk blew up'),
      const bridge_error.NightshadeError.internal('bug'),
      const bridge_error.NightshadeError.runtimeInitFailed('no tokio'),
      const bridge_error.NightshadeError.alreadyConnected('native:zwo:0'),
      const bridge_error.NightshadeError.imageError('bad stride'),
      const bridge_error.NightshadeError.cameraError('no sensor'),
      const bridge_error.NightshadeError.ioError('disk gone'),
      const bridge_error.NightshadeError.serializationError('bad json'),
      const bridge_error.NightshadeError.plateSolveError('no match'),
      const bridge_error.NightshadeError.sequenceError('node missing'),
      const bridge_error.NightshadeError.invalidInput('nope'),
    ];

    for (final variant in variants) {
      final result = await call(variant);
      final message = result.body['message'] as String?;
      expect(
        message,
        isNotNull,
        reason: '${variant.runtimeType} produced no message',
      );
      expect(
        message,
        isNot(contains('NightshadeError')),
        reason: '${variant.runtimeType} leaked the constructor form: $message',
      );
      expect(
        message!.trim(),
        isNotEmpty,
        reason: '${variant.runtimeType} produced an empty message',
      );
    }
  });

  test('the rest of the mapping table is unchanged', () async {
    final expected = <bridge_error.NightshadeError, int>{
      const bridge_error.NightshadeError.notSupported(
        deviceId: 'ascom:X',
        operation: 'setGain',
      ): 501,
      const bridge_error.NightshadeError.notConnected('native:zwo:0'): 409,
      const bridge_error.NightshadeError.deviceNotFound('native:zwo:9'): 404,
      const bridge_error.NightshadeError.invalidParameter('gain'): 400,
      const bridge_error.NightshadeError.exposureCancelled(): 409,
      const bridge_error.NightshadeError.noImageAvailable(): 404,
      const bridge_error.NightshadeError.timeout('slew'): 504,
    };

    for (final entry in expected.entries) {
      final result = await call(entry.key);
      expect(
        result.status,
        entry.value,
        reason: '${entry.key.runtimeType} should map to ${entry.value}',
      );
      expect(
        result.body['error'],
        entry.value >= 500 ? 'internal_error' : 'device_error',
      );
    }
  });
}
