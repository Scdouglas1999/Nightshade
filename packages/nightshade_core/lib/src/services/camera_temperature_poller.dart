import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/nightshade_backend.dart';
import '../providers/equipment_provider.dart';
import '../providers/imaging_provider.dart' show temperatureHistoryProvider;
import 'logging_service.dart';

/// Polls a connected camera's sensor temperature and cooler power on a
/// fixed cadence, pushing values into [cameraStateProvider] and
/// [temperatureHistoryProvider].
///
/// Extracted from `DeviceService` so the polling lifecycle is owned by a
/// dedicated collaborator. The poller is started by
/// [DeviceService.connectCamera] and stopped by
/// [DeviceService.disconnectCamera] / `prepareForBackendSwap` /
/// `dispose`. A monotonic generation counter is used to ignore stale
/// timer ticks left over from a previous camera id, which is essential
/// when the user swaps cameras without explicitly disconnecting first.
class CameraTemperaturePoller {
  CameraTemperaturePoller({
    required Ref ref,
    required NightshadeBackend backend,
    Duration interval = const Duration(seconds: 5),
  })  : _ref = ref,
        _backend = backend,
        _interval = interval;

  final Ref _ref;
  final NightshadeBackend _backend;
  final Duration _interval;

  Timer? _timer;
  String? _connectedCameraId;
  int _generation = 0;

  /// Identifier of the camera currently being polled, if any.
  String? get connectedCameraId => _connectedCameraId;

  /// Begin polling [deviceId]. Cancels any in-progress polling first.
  void start(String deviceId) {
    _connectedCameraId = deviceId;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) async {
      await _poll(deviceId, generation);
    });
    // Poll immediately on start so the UI does not need to wait one tick
    // for the first sample.
    unawaited(_poll(deviceId, generation));
  }

  /// Stop polling. Subsequent timer ticks (if any are mid-flight) are
  /// dropped by the generation guard.
  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _connectedCameraId = null;
  }

  /// Dispose the poller. Currently identical to [stop]; kept distinct so
  /// owners can call it from their own `dispose` hook unambiguously.
  void dispose() {
    stop();
  }

  Future<void> _poll(String deviceId, int generation) async {
    if (_connectedCameraId != deviceId || _generation != generation) {
      return;
    }

    try {
      final status = await _backend.getCameraStatus(deviceId);
      if (_connectedCameraId != deviceId || _generation != generation) {
        return;
      }

      final temp = status.sensorTemp;
      final power = status.coolerPower;
      final targetTemp = status.targetTemp;

      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.debug(
          'Camera temp: ${temp?.toStringAsFixed(1) ?? "null"}°C, '
          'power: ${power?.toStringAsFixed(0) ?? "null"}%, '
          'target: ${targetTemp?.toStringAsFixed(1) ?? "null"}°C',
          source: 'CameraTemperaturePoller',
        );
      } on Object catch (e) {
        // Why: logger lookup happens inside a temperature poll tick; if the
        // logging service itself is mid-disposal we must not propagate up the
        // poll loop. Diagnostic-only failure — emit to stderr so it isn't
        // fully silent.
        // ignore: avoid_print
        print('CameraTemperaturePoller: temp-log emission failed: $e');
      }

      if (temp != null) {
        _ref
            .read(cameraStateProvider.notifier)
            .updateTemperature(temp, power ?? 0.0);

        _ref.read(temperatureHistoryProvider.notifier).addPoint(
              temp,
              targetTemp: targetTemp,
              coolerPower: power,
            );
      }
    } catch (e) {
      if (_connectedCameraId != deviceId || _generation != generation) {
        return;
      }
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.warning('Temperature polling error: $e',
            source: 'CameraTemperaturePoller');
      } on Object catch (loggerErr) {
        // Why: nested catch around logger emission during the poll-loop's
        // error path. If the logging provider is itself disposing we must
        // not re-throw — that would mask the original temperature-polling
        // failure. Surface to stderr so it isn't fully silent.
        // ignore: avoid_print
        print('CameraTemperaturePoller: warn-log emission failed: '
            '$loggerErr (original temp-poll error: $e)');
      }
    }
  }
}
