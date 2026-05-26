import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/nightshade_backend.dart';
import '../models/equipment/equipment_models.dart';
import '../providers/equipment_provider.dart';
import 'logging_service.dart';

/// Drives the gradual camera warm-up routine.
///
/// Warming a cooled astrophotography sensor requires stepping the target
/// temperature up slowly to avoid thermal shock and condensation. The
/// algorithm is deliberately NOT temperature-aware: we keep raising the
/// setpoint until the cooler's PID loop reports near-zero power, then
/// disable the cooler. A temperature-based stopping condition would
/// stall in cold-ambient conditions where the cooler power hits zero
/// well before the sensor reaches an arbitrary target temperature.
///
/// Extracted from `DeviceService` to isolate the periodic-timer state
/// machine. The controller owns its own cancellation flag and timer so
/// the parent never reaches into half-completed state during a backend
/// swap or device-swap.
class CameraWarmupController {
  CameraWarmupController({
    required Ref ref,
    required NightshadeBackend backend,
  })  : _ref = ref,
        _backend = backend;

  final Ref _ref;
  final NightshadeBackend _backend;

  Timer? _timer;
  bool _cancelled = false;

  /// True while a warm-up timer is currently running.
  bool get isWarming => _timer != null;

  /// Begin a gradual warm-up. Throws if the camera is not connected or
  /// has no live device id. Any prior warm-up is cancelled first.
  Future<void> start({double ratePerMin = 2.0}) async {
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw Exception('Camera not connected');
    }

    final deviceId = cameraState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No camera device ID available');
    }

    // Drop any in-flight warming before we touch state.
    cancel();

    final notifier = _ref.read(cameraStateProvider.notifier);
    notifier.setWarming(true);
    _cancelled = false;

    final currentTemp = cameraState.temperature ?? cameraState.targetTemp;

    const tickInterval = Duration(seconds: 10);
    final stepPerTick = ratePerMin / 6.0; // six 10-second ticks per minute
    var currentSetpoint = currentTemp;

    const maxWarmingDuration = Duration(minutes: 30);
    final warmingStartTime = DateTime.now();

    _log(
      (l) => l.info(
        'Starting gradual warm-up from ${currentTemp.toStringAsFixed(1)}°C '
        'at ${ratePerMin.toStringAsFixed(1)}°C/min (power-based stopping)',
      ),
    );

    // Keep cooler tracking, but seed the setpoint at the current sensor
    // temp so the cooler does not first work harder before easing off.
    await _backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: true,
      targetTemp: currentSetpoint,
    );

    _timer = Timer.periodic(tickInterval, (timer) async {
      if (_cancelled) {
        timer.cancel();
        _timer = null;
        notifier.setWarming(false);
        return;
      }

      final state = _ref.read(cameraStateProvider);
      if (state.connectionState != DeviceConnectionState.connected) {
        timer.cancel();
        _timer = null;
        notifier.setWarming(false);
        return;
      }

      final coolerPower = state.coolerPower ?? 0.0;
      if (coolerPower <= 2.0) {
        timer.cancel();
        _timer = null;
        try {
          await _backend.cameraSetCooling(
            deviceId: deviceId,
            enabled: false,
          );
          _log(
            (l) => l.info(
              'Warm-up complete. Cooler power reached '
              '${coolerPower.toStringAsFixed(0)}%, cooler disabled. '
              'Sensor: ${state.temperature?.toStringAsFixed(1) ?? "?"}°C',
            ),
          );
        } catch (e) {
          _log(
            (l) => l.error('Failed to disable cooler at end of warm-up: $e'),
          );
        }
        notifier.setWarming(false);
        return;
      }

      if (DateTime.now().difference(warmingStartTime) > maxWarmingDuration) {
        timer.cancel();
        _timer = null;
        try {
          await _backend.cameraSetCooling(
            deviceId: deviceId,
            enabled: false,
          );
          _log(
            (l) => l.warning(
              'Warm-up safety timeout (30 min). Cooler disabled at power '
              '${coolerPower.toStringAsFixed(0)}%, sensor '
              '${state.temperature?.toStringAsFixed(1) ?? "?"}°C',
            ),
          );
        } catch (e) {
          _log(
            (l) =>
                l.error('Failed to disable cooler after warm-up timeout: $e'),
          );
        }
        notifier.setWarming(false);
        return;
      }

      currentSetpoint += stepPerTick;
      try {
        await _backend.cameraSetCooling(
          deviceId: deviceId,
          enabled: true,
          targetTemp: currentSetpoint,
        );
        notifier.setTargetTemp(currentSetpoint);
      } catch (e) {
        _log(
          (l) => l.error(
            'Error during warm-up step '
            '(setpoint ${currentSetpoint.toStringAsFixed(1)}°C): $e',
          ),
        );
        // Don't cancel on transient errors - try again next tick
      }
    });
  }

  /// Cancel any in-progress warm-up. The cooler is left in whatever
  /// state it was in at the moment of cancellation (callers that need
  /// the cooler off should call `cameraSetCooling(enabled: false)`
  /// themselves).
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    try {
      _ref.read(cameraStateProvider.notifier).setWarming(false);
    } on Object {
      // Notifier may be unavailable during teardown; warming-state
      // recovery is strictly cosmetic at that point.
    }
  }

  /// Dispose the controller. Currently identical to [cancel].
  void dispose() => cancel();

  void _log(void Function(LoggingService logger) emit) {
    try {
      final logger = _ref.read(loggingServiceProvider);
      emit(logger);
    } on Object catch (loggerErr) {
      // Diagnostic-only path; never let logger emission failures mask
      // a higher-priority cooling fault.
      // ignore: avoid_print
      print('CameraWarmupController: logger emission failed: $loggerErr');
    }
  }
}
