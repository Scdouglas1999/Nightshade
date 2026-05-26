import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/nightshade_backend.dart';
import '../models/equipment/equipment_models.dart';
import '../models/sequence/sequence_models.dart';
import '../providers/equipment_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/sequence_provider.dart';
import '../providers/ui_notification_provider.dart';
import 'device_service.dart' show DeviceTypeDisplayExtension;
import 'logging_service.dart';
import 'notification_service.dart';

/// Coordinates the device auto-reconnect lifecycle.
///
/// Owns:
///   * the per-device attempt counter and exponential-backoff timer map,
///   * the user-initiated-disconnect debounce so manual disconnects do
///     not immediately trigger an auto-reconnect,
///   * suppress-during-backend-swap state,
///   * the post-reconnect "should I resume a paused sequence?" check.
///
/// Extracted from `DeviceService` (DEV-P1-1 + DV-P0-3) because the
/// reconnect state machine had no business being inlined alongside the
/// connect/disconnect command layer. DeviceService now drives this
/// coordinator from its device-event handlers; the coordinator never
/// reaches back into DeviceService's internals — sequencer pause/resume
/// is the one place a callback is required and is injected explicitly.
class DeviceReconnectCoordinator {
  DeviceReconnectCoordinator({
    required Ref ref,
    required NightshadeBackend backend,
    required Future<void> Function() resumeSequence,
    required Future<void> Function() pauseSequence,
  })  : _ref = ref,
        _backend = backend,
        _resumeSequence = resumeSequence,
        _pauseSequence = pauseSequence;

  final Ref _ref;
  final NightshadeBackend _backend;
  final Future<void> Function() _resumeSequence;
  final Future<void> Function() _pauseSequence;

  /// Maximum number of reconnection attempts before surfacing the
  /// "couldn't reconnect" UI notification and giving up.
  static const int maxReconnectAttempts = 3;

  /// Reconnection delay backoff (5, 10, 20 seconds).
  static const List<Duration> reconnectDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  /// How long after a user-initiated disconnect we ignore Disconnected
  /// events for that device id (so the connection-down event the user
  /// just triggered does not bounce back as a reconnect).
  static const Duration userDisconnectSuppressDuration =
      Duration(seconds: 10);

  final Map<String, int> _reconnectionAttempts = {};
  final Map<String, Timer> _reconnectionTimers = {};

  /// User-initiated disconnects suppress auto-reconnect briefly.
  final Set<String> _userInitiatedDisconnects = {};
  Timer? _userDisconnectDebounceTimer;

  /// Set during backend swap so stray Disconnected events cannot
  /// reconnect against a backend that is mid-tear-down.
  bool _suppressAutoReconnect = false;

  String _reconnectKey(DeviceType type, String deviceId) =>
      '${type.name}:$deviceId';

  /// Mark [deviceId] as a user-initiated disconnect: cancel any pending
  /// reconnect for that device, drop the attempt counter, and arm the
  /// debounce timer so any Disconnected event arriving in the next 10s
  /// is treated as expected.
  void markUserInitiatedDisconnect(String deviceId) {
    if (deviceId.isEmpty) {
      return;
    }
    _userInitiatedDisconnects.add(deviceId);
    final reconnectKeys = _reconnectionTimers.keys
        .followedBy(_reconnectionAttempts.keys)
        .where((key) => key.endsWith(':$deviceId'))
        .toSet();
    for (final key in reconnectKeys) {
      _reconnectionTimers[key]?.cancel();
      _reconnectionTimers.remove(key);
      _reconnectionAttempts.remove(key);
    }
    _userDisconnectDebounceTimer?.cancel();
    _userDisconnectDebounceTimer = Timer(userDisconnectSuppressDuration, () {
      _userInitiatedDisconnects.clear();
      _userDisconnectDebounceTimer = null;
    });
  }

  bool isUserInitiatedDisconnect(String deviceId) {
    return _userInitiatedDisconnects.contains(deviceId);
  }

  /// Cancel every pending reconnect timer and zero the counters. Used
  /// during backend swap and from `DeviceService.dispose`.
  void cancelAll() {
    for (final timer in _reconnectionTimers.values) {
      timer.cancel();
    }
    _reconnectionTimers.clear();
    _reconnectionAttempts.clear();
  }

  /// Wind down before a backend swap: cancel timers, clear debounce
  /// state, and lock out future reconnect attempts until [reset] is
  /// called.
  void prepareForBackendSwap() {
    _suppressAutoReconnect = true;
    cancelAll();
    _userInitiatedDisconnects.clear();
    _userDisconnectDebounceTimer?.cancel();
    _userDisconnectDebounceTimer = null;
  }

  /// Re-enable auto-reconnect after a swap. Not currently called (the
  /// post-swap `DeviceService` instance constructs a fresh coordinator)
  /// but kept symmetrical with [prepareForBackendSwap] for future use.
  void reset() {
    _suppressAutoReconnect = false;
  }

  /// Schedule a reconnection attempt for [type]/[deviceId] subject to:
  ///   * suppress-during-swap,
  ///   * user-initiated-disconnect debounce,
  ///   * per-type `autoReconnectEnabled` flag,
  ///   * `maxReconnectAttempts` cap (notifies the user and gives up).
  Future<void> attemptReconnect(DeviceType type, String deviceId) async {
    if (_suppressAutoReconnect) {
      return;
    }

    if (isUserInitiatedDisconnect(deviceId)) {
      _safeLog(
        (logger) => logger.info(
          'Skipping auto-reconnect for user-initiated disconnect of '
          '${type.displayName} ($deviceId)',
          source: 'DeviceReconnectCoordinator',
        ),
      );
      return;
    }

    final autoReconnectEnabled = _getAutoReconnectFor(type);

    if (!autoReconnectEnabled) {
      _safeLog(
        (logger) => logger.info(
          'Auto-reconnect disabled for ${type.displayName} ($deviceId)',
          source: 'DeviceReconnectCoordinator',
        ),
      );
      return;
    }

    final reconnectKey = _reconnectKey(type, deviceId);

    final attemptCount = _reconnectionAttempts[reconnectKey] ?? 0;

    if (attemptCount >= maxReconnectAttempts) {
      _safeLog(
        (logger) => logger.error(
          'Failed to reconnect ${type.displayName} ($deviceId) after '
          '$maxReconnectAttempts attempts',
          source: 'DeviceReconnectCoordinator',
        ),
      );
      _showReconnectionFailedNotification(type, deviceId);
      _reconnectionAttempts.remove(reconnectKey);
      return;
    }

    _reconnectionAttempts[reconnectKey] = attemptCount + 1;

    final delay = attemptCount < reconnectDelays.length
        ? reconnectDelays[attemptCount]
        : reconnectDelays.last;

    _safeLog(
      (logger) => logger.info(
        'Scheduling reconnection attempt ${attemptCount + 1}/'
        '$maxReconnectAttempts for ${type.displayName} ($deviceId) '
        'in ${delay.inSeconds}s at '
        '${DateTime.now().add(delay).toIso8601String()}',
        source: 'DeviceReconnectCoordinator',
      ),
    );

    _reconnectionTimers[reconnectKey]?.cancel();

    _reconnectionTimers[reconnectKey] = Timer(delay, () async {
      try {
        _safeLog(
          (logger) => logger.info(
            'Attempting reconnection ${attemptCount + 1}/'
            '$maxReconnectAttempts for ${type.displayName} ($deviceId) at '
            '${DateTime.now().toIso8601String()}',
            source: 'DeviceReconnectCoordinator',
          ),
        );

        await _performReconnection(type, deviceId);

        _reconnectionAttempts.remove(reconnectKey);
        _reconnectionTimers.remove(reconnectKey);

        _safeLog(
          (logger) => logger.info(
            'Successfully reconnected ${type.displayName} ($deviceId) at '
            '${DateTime.now().toIso8601String()}',
            source: 'DeviceReconnectCoordinator',
          ),
        );

        _showReconnectionSuccessNotification(type, deviceId);

        await _considerSequenceResume(type);
      } catch (e) {
        _safeLog(
          (logger) => logger.warning(
            'Reconnection attempt ${attemptCount + 1}/'
            '$maxReconnectAttempts failed for ${type.displayName} '
            '($deviceId): $e',
            source: 'DeviceReconnectCoordinator',
          ),
        );

        unawaited(attemptReconnect(type, deviceId));
      }
    });
  }

  /// Handle disconnection of critical devices (camera, mount) during
  /// sequence execution: snapshot a fresh checkpoint and pause the run.
  /// The reconnect path will resume automatically via
  /// [_considerSequenceResume] once both critical devices are back.
  Future<void> handleCriticalDeviceDisconnect(
      String deviceType, String deviceId) async {
    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.running &&
        sequenceState != SequenceExecutionState.paused) {
      return;
    }

    try {
      await _backend.saveCheckpoint();
    } catch (e) {
      _safeLog(
        (logger) => logger.error(
          'Failed to save checkpoint after critical $deviceType disconnect '
          '($deviceId): $e',
          source: 'DeviceReconnectCoordinator',
        ),
      );
      try {
        _ref.read(uiNotificationProvider.notifier).showError(
              'Failed to save a sequence checkpoint after $deviceType '
              'disconnected.',
              title: 'Checkpoint Failed',
              duration: const Duration(seconds: 12),
            );
      } on Object {
        // Notification failure must not mask the hardware-protection pause.
      }
    }

    if (sequenceState == SequenceExecutionState.paused) {
      return;
    }

    try {
      await _pauseSequence();
    } catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'Failed to pause sequence after critical $deviceType disconnect '
          '($deviceId): $e',
          source: 'DeviceReconnectCoordinator',
        ),
      );
    }
  }

  bool _getAutoReconnectFor(DeviceType type) {
    return switch (type) {
      DeviceType.camera => _ref.read(cameraStateProvider).autoReconnectEnabled,
      DeviceType.mount => _ref.read(mountStateProvider).autoReconnectEnabled,
      DeviceType.focuser =>
        _ref.read(focuserStateProvider).autoReconnectEnabled,
      DeviceType.filterWheel =>
        _ref.read(filterWheelStateProvider).autoReconnectEnabled,
      DeviceType.guider => _ref.read(guiderStateProvider).autoReconnectEnabled,
      DeviceType.rotator =>
        _ref.read(rotatorStateProvider).autoReconnectEnabled,
      DeviceType.dome => _ref.read(domeStateProvider).autoReconnectEnabled,
      DeviceType.weather =>
        _ref.read(weatherStateProvider).autoReconnectEnabled,
      DeviceType.safetyMonitor =>
        _ref.read(safetyMonitorStateProvider).autoReconnectEnabled,
      DeviceType.coverCalibrator =>
        _ref.read(coverCalibratorStateProvider).autoReconnectEnabled,
      DeviceType.switch_ => _ref.read(switchStateProvider).autoReconnectEnabled,
    };
  }

  Future<void> _performReconnection(DeviceType type, String deviceId) async {
    switch (type) {
      case DeviceType.camera:
        await _ref
            .read(cameraStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.mount:
        await _ref
            .read(mountStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.focuser:
        await _ref
            .read(focuserStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.filterWheel:
        await _ref
            .read(filterWheelStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.guider:
        await _ref
            .read(guiderStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.rotator:
        await _ref
            .read(rotatorStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.dome:
        await _ref
            .read(domeStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.weather:
        await _ref
            .read(weatherStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.safetyMonitor:
        await _ref
            .read(safetyMonitorStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.switch_:
        await _ref
            .read(switchStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
      case DeviceType.coverCalibrator:
        await _ref
            .read(coverCalibratorStateProvider.notifier)
            .connect(deviceId, maxRetries: 1);
        break;
    }
  }

  /// After a successful reconnect, resume a paused sequence if and only
  /// if every critical device listed in the active profile is back.
  Future<void> _considerSequenceResume(DeviceType type) async {
    if (type != DeviceType.camera && type != DeviceType.mount) {
      return;
    }

    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.paused) {
      return;
    }

    final activeProfile = _ref.read(activeEquipmentProfileProvider);
    if (activeProfile == null) {
      return;
    }

    bool allCriticalDevicesConnected = true;

    if (activeProfile.cameraId != null && activeProfile.cameraId!.isNotEmpty) {
      final cameraState = _ref.read(cameraStateProvider);
      if (cameraState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    if (activeProfile.mountId != null && activeProfile.mountId!.isNotEmpty) {
      final mountState = _ref.read(mountStateProvider);
      if (mountState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    if (allCriticalDevicesConnected) {
      try {
        await _resumeSequence();
      } catch (e) {
        _safeLog(
          (logger) => logger.warning(
            'Failed to resume sequence after reconnecting ${type.displayName}: '
            '$e',
            source: 'DeviceReconnectCoordinator',
          ),
        );
      }
    }
  }

  void _showReconnectionFailedNotification(DeviceType type, String deviceId) {
    try {
      _ref.read(uiNotificationProvider.notifier).showError(
            'Failed to reconnect ${type.displayName} after '
            '$maxReconnectAttempts attempts.\n\n'
            'Troubleshooting steps:\n'
            '• Check device power and USB/network connections\n'
            '• Verify device drivers are installed and up to date\n'
            '• Try unplugging and reconnecting the device\n'
            '• Restart the device software (ASCOM/INDI/etc.)\n'
            '• Check for device error messages or logs\n\n'
            'Please fix the issue and reconnect manually.',
            title: '${type.displayName} Reconnection Failed',
            duration: const Duration(seconds: 15),
          );
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'UI notification for reconnect-failed dropped: $e',
          source: 'DeviceReconnectCoordinator',
        ),
      );
    }

    try {
      _ref.read(notificationServiceProvider).notifyError(
            errorTitle: 'Device Reconnection Failed',
            errorMessage: '${type.displayName} ($deviceId) could not be '
                'reconnected after $maxReconnectAttempts attempts.\n\n'
                'Auto-reconnection has stopped. Manual intervention required.\n'
                'Check device power, connections, and drivers.',
            source: 'Device Monitor',
          );
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'External notification for reconnect-failed dropped: $e',
          source: 'DeviceReconnectCoordinator',
        ),
      );
    }
  }

  void _showReconnectionSuccessNotification(DeviceType type, String deviceId) {
    try {
      _ref.read(uiNotificationProvider.notifier).showSuccess(
            '${type.displayName} has been reconnected successfully.',
            title: 'Device Reconnected',
            duration: const Duration(seconds: 5),
          );
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'UI notification for reconnect-success dropped: $e',
          source: 'DeviceReconnectCoordinator',
        ),
      );
    }

    if (type == DeviceType.camera || type == DeviceType.mount) {
      try {
        _ref.read(notificationServiceProvider).notifyCustom(
              title: 'Device Reconnected',
              message: '${type.displayName} ($deviceId) has been reconnected '
                  'successfully and is back online.',
              priority: NotificationPriority.normal,
            );
      } on Object catch (e) {
        _safeLog(
          (logger) => logger.warning(
            'External notification for reconnect-success dropped: $e',
            source: 'DeviceReconnectCoordinator',
          ),
        );
      }
    }
  }

  void _safeLog(void Function(LoggingService logger) emit) {
    try {
      final logger = _ref.read(loggingServiceProvider);
      emit(logger);
    } on Object {
      // Logger may be unavailable mid-disposal. Diagnostic-only failure;
      // do not propagate up the reconnect path.
    }
  }
}
