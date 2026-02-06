import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_provider.dart';
import '../providers/imaging_provider.dart' show temperatureHistoryProvider;
import '../providers/profiles_provider.dart' show activeEquipmentProfileProvider;
import '../providers/database_provider.dart';
import '../providers/backend_provider.dart';
import '../providers/sequence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_notification_provider.dart';
import '../providers/operation_progress_provider.dart';
import '../providers/filter_offset_provider.dart';
import '../providers/current_screen_provider.dart';
import 'smart_notification_service.dart';
import '../backend/nightshade_backend.dart' hide TrackingRate;
import '../models/equipment/equipment_models.dart';
import '../models/sequence/sequence_models.dart';
import 'notification_service.dart';
import 'logging_service.dart';

// Re-export backend types for backward compatibility
// These were previously defined locally but are now consolidated in backend_types
export '../models/backend/device_types.dart' show DeviceType, DriverType;
export '../models/backend/device_info.dart' show DeviceInfo;

/// Extension methods for DeviceType display
extension DeviceTypeDisplayExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.camera: return 'Camera';
      case DeviceType.mount: return 'Mount';
      case DeviceType.focuser: return 'Focuser';
      case DeviceType.filterWheel: return 'Filter Wheel';
      case DeviceType.guider: return 'Guider';
      case DeviceType.rotator: return 'Rotator';
      case DeviceType.dome: return 'Dome';
      case DeviceType.weather: return 'Weather';
      case DeviceType.safetyMonitor: return 'Safety Monitor';
      case DeviceType.switch_: return 'Switch';
      case DeviceType.coverCalibrator: return 'Cover Calibrator';
    }
  }
}

/// Extension methods for DriverType display
extension DriverTypeDisplayExtension on DriverType {
  String get displayName {
    switch (this) {
      case DriverType.ascom: return 'ASCOM';
      case DriverType.alpaca: return 'Alpaca';
      case DriverType.indi: return 'INDI';
      case DriverType.native: return 'Native';
      case DriverType.simulator: return 'Simulator';
    }
  }
}

// Type aliases for backward compatibility
// Existing code using NightshadeDeviceType, DriverBackend, or AvailableDevice will still work
@Deprecated('Use DeviceType instead')
typedef NightshadeDeviceType = DeviceType;

@Deprecated('Use DriverType instead')
typedef DriverBackend = DriverType;

@Deprecated('Use DeviceInfo instead')
typedef AvailableDevice = DeviceInfo;

/// Service for managing device discovery and connections
///
/// This service uses the NightshadeBackend abstraction to communicate
/// with devices via different backends (FFI for desktop, Network for mobile).
class DeviceService {
  final Ref _ref;
  final NightshadeBackend _backend;
  StreamSubscription? _eventSubscription;
  Timer? _temperaturePollingTimer;
  String? _connectedCameraId;

  static const Duration _filterWheelVerifyTimeout = Duration(seconds: 60);
  static const Duration _filterWheelVerifyPollInterval = Duration(milliseconds: 250);

  static const Duration _focuserMoveTimeout = Duration(seconds: 300);
  static const Duration _focuserMovePollInterval = Duration(milliseconds: 500);

  DeviceService(this._ref, this._backend) {
    _initEventListening();
  }

  /// Start polling camera temperature every 5 seconds
  void _startTemperaturePolling(String deviceId) {
    _connectedCameraId = deviceId;
    _temperaturePollingTimer?.cancel();
    _temperaturePollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _pollCameraTemperature();
    });
    // Poll immediately on start
    _pollCameraTemperature();
  }

  /// Stop temperature polling
  void _stopTemperaturePolling() {
    _temperaturePollingTimer?.cancel();
    _temperaturePollingTimer = null;
    _connectedCameraId = null;
  }

  /// Poll camera temperature and update providers
  Future<void> _pollCameraTemperature() async {
    if (_connectedCameraId == null) return;

    try {
      final status = await _backend.getCameraStatus(_connectedCameraId!);

      // Use typed CameraStatus accessors
      final temp = status.sensorTemp;
      final power = status.coolerPower;
      final targetTemp = status.targetTemp;

      // Log temperature readings for debugging
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.debug(
          'Camera temp: ${temp?.toStringAsFixed(1) ?? "null"}°C, power: ${power?.toStringAsFixed(0) ?? "null"}%, target: ${targetTemp?.toStringAsFixed(1) ?? "null"}°C',
          source: 'DeviceService',
        );
      } catch (_) {}

      if (temp != null) {
        // Update camera state
        _ref.read(cameraStateProvider.notifier).updateTemperature(temp, power ?? 0.0);

        // Update temperature history for the graph
        _ref.read(temperatureHistoryProvider.notifier).addPoint(
          temp,
          targetTemp: targetTemp,
          coolerPower: power,
        );
      }
    } catch (e) {
      // Log polling errors for debugging
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.warning('Temperature polling error: $e', source: 'DeviceService');
      } catch (_) {}
    }
  }

  /// Extract temperature from status response (handles different backend formats)
  double? _extractTemperature(dynamic status) {
    if (status is Map<String, dynamic>) {
      // Try various field names
      final temp = status['temperature'] ?? status['ccdTemperature'] ?? status['sensorTemp'];
      if (temp is num) return temp.toDouble();
    }
    // If status is a typed object from the bridge (CameraStatus has sensorTemp)
    try {
      return (status as dynamic).sensorTemp?.toDouble();
    } catch (_) {}
    try {
      return (status as dynamic).ccdTemperature?.toDouble();
    } catch (_) {}
    try {
      return (status as dynamic).temperature?.toDouble();
    } catch (_) {}
    return null;
  }

  /// Extract cooler power from status
  double? _extractCoolerPower(dynamic status) {
    if (status is Map<String, dynamic>) {
      final power = status['coolerPower'] ?? status['coolerOn'];
      if (power is num) return power.toDouble();
      if (power is bool) return power ? 100.0 : 0.0;
    }
    try {
      return (status as dynamic).coolerPower?.toDouble();
    } catch (_) {}
    return null;
  }

  /// Extract target temperature from status
  double? _extractTargetTemperature(dynamic status) {
    if (status is Map<String, dynamic>) {
      final target = status['setccdTemperature'] ?? status['targetTemperature'] ?? status['setCcdTemperature'] ?? status['targetTemp'];
      if (target is num) return target.toDouble();
    }
    // If status is a typed object from the bridge (CameraStatus has targetTemp)
    try {
      return (status as dynamic).targetTemp?.toDouble();
    } catch (_) {}
    try {
      return (status as dynamic).setCcdTemperature?.toDouble();
    } catch (_) {}
    try {
      return (status as dynamic).targetTemperature?.toDouble();
    } catch (_) {}
    return null;
  }

  void _initEventListening() {
    _eventSubscription = _backend.eventStream.listen((event) {
      if (event.category == EventCategory.equipment) {
        _handleEquipmentEvent(event);
      } else if (event.category == EventCategory.sequencer) {
        _handleSequencerEvent(event);
      }
    });
  }

  void _handleEquipmentEvent(NightshadeEvent event) {
    final data = event.data;
    switch (event.eventType) {
      // Connection events
      case 'Disconnected':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        _handleDeviceDisconnected(deviceType, deviceId);
        break;

      // Legacy camera temperature event (keep for backward compatibility)
      case 'CameraTemperatureChanged':
        final temp = (data['temperature'] as num).toDouble();
        final power = (data['coolerPower'] as num).toDouble();
        _ref.read(cameraStateProvider.notifier).updateTemperature(temp, power);
        break;

      // Legacy mount position event (keep for backward compatibility)
      case 'MountPositionChanged':
        final ra = (data['ra'] as num).toDouble();
        final dec = (data['dec'] as num).toDouble();
        final alt = (data['altitude'] as num?)?.toDouble() ?? 0.0;
        final az = (data['azimuth'] as num?)?.toDouble() ?? 0.0;
        _ref.read(mountStateProvider.notifier).updatePosition(ra, dec, alt, az);

        if (data['isSlewing'] != null) {
          _ref.read(mountStateProvider.notifier).setSlewing(data['isSlewing'] as bool);
        }
        if (data['isTracking'] != null) {
          _ref.read(mountStateProvider.notifier).setTracking(data['isTracking'] as bool);
        }
        if (data['isParked'] != null) {
          _ref.read(mountStateProvider.notifier).setParked(data['isParked'] as bool);
        }
        break;

      // Mount Slew Events
      case 'MountSlewStarted':
        final ra = (data['ra'] as num?)?.toDouble();
        final dec = (data['dec'] as num?)?.toDouble();
        _ref.read(mountStateProvider.notifier).setSlewing(true);
        if (ra != null && dec != null) {
          // Optionally update target position
        }
        break;

      case 'MountSlewCompleted':
        final ra = (data['ra'] as num?)?.toDouble();
        final dec = (data['dec'] as num?)?.toDouble();
        _ref.read(mountStateProvider.notifier).setSlewing(false);
        if (ra != null && dec != null) {
          _ref.read(mountStateProvider.notifier).updatePosition(ra, dec, 0.0, 0.0);
        }
        // Smart notification - only show if not on imaging/planetarium screens
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
          message: 'Slew completed',
          relevantScreens: [AppScreen.imaging, AppScreen.planetarium, AppScreen.sequencer],
          title: 'Mount',
        );
        break;

      // Mount Tracking Events
      case 'MountTrackingStarted':
        _ref.read(mountStateProvider.notifier).setTracking(true);
        break;

      case 'MountTrackingStopped':
        _ref.read(mountStateProvider.notifier).setTracking(false);
        break;

      // Mount Park Events
      case 'MountParkStarted':
        _ref.read(mountStateProvider.notifier).setSlewing(true);
        break;

      case 'MountParkCompleted':
        _ref.read(mountStateProvider.notifier).setSlewing(false);
        _ref.read(mountStateProvider.notifier).setParked(true);
        _ref.read(mountStateProvider.notifier).setTracking(false);
        // Smart notification
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
          message: 'Mount parked',
          relevantScreens: [AppScreen.imaging, AppScreen.equipment],
          title: 'Mount',
        );
        break;

      case 'MountUnparked':
        _ref.read(mountStateProvider.notifier).setParked(false);
        // Smart notification
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
          message: 'Mount unparked',
          relevantScreens: [AppScreen.imaging, AppScreen.equipment],
          title: 'Mount',
        );
        break;

      // Legacy focuser position event (keep for backward compatibility)
      case 'FocuserPositionChanged':
        final pos = data['position'] as int;
        _ref.read(focuserStateProvider.notifier).updatePosition(pos);
        if (data['isMoving'] != null) {
          _ref.read(focuserStateProvider.notifier).setMoving(data['isMoving'] as bool);
        }
        if (data['temperature'] != null) {
          _ref.read(focuserStateProvider.notifier).updateTemperature((data['temperature'] as num).toDouble());
        }
        break;

      // Focuser Events
      case 'FocuserMoveStarted':
        _ref.read(focuserStateProvider.notifier).setMoving(true);
        break;

      case 'FocuserMoveCompleted':
        final position = data['position'] as int?;
        _ref.read(focuserStateProvider.notifier).setMoving(false);
        if (position != null) {
          _ref.read(focuserStateProvider.notifier).updatePosition(position);
        }
        break;

      case 'FocuserTemperatureChanged':
        final temperature = (data['temperature'] as num?)?.toDouble();
        if (temperature != null) {
          _ref.read(focuserStateProvider.notifier).updateTemperature(temperature);
        }
        break;

      // Legacy filter wheel position event (keep for backward compatibility)
      case 'FilterWheelPositionChanged':
        final pos = data['position'] as int;
        _ref.read(filterWheelStateProvider.notifier).updatePosition(pos);
        if (data['isMoving'] != null) {
          _ref.read(filterWheelStateProvider.notifier).setMoving(data['isMoving'] as bool);
        }
        break;

      // Filter Wheel Events
      case 'FilterChanging':
        _ref.read(filterWheelStateProvider.notifier).setMoving(true);
        break;

      case 'FilterChanged':
        final position = data['position'] as int?;
        _ref.read(filterWheelStateProvider.notifier).setMoving(false);
        if (position != null) {
          _ref.read(filterWheelStateProvider.notifier).updatePosition(position);
        }
        break;

      // Rotator Events
      case 'RotatorMoveStarted':
        _ref.read(rotatorStateProvider.notifier).setMoving(true);
        break;

      case 'RotatorMoveCompleted':
        final angle = (data['angle'] as num?)?.toDouble();
        _ref.read(rotatorStateProvider.notifier).setMoving(false);
        if (angle != null) {
          _ref.read(rotatorStateProvider.notifier).updatePosition(angle);
        }
        break;

      // Camera Cooling Events
      case 'CameraCoolingStarted':
        final targetTemp = (data['target_temp'] as num?)?.toDouble();
        _ref.read(cameraStateProvider.notifier).setCooling(true);
        if (targetTemp != null) {
          _ref.read(cameraStateProvider.notifier).setTargetTemp(targetTemp);
        }
        break;

      case 'CameraCoolingReached':
        final temp = (data['temperature'] as num?)?.toDouble();
        if (temp != null) {
          _ref.read(cameraStateProvider.notifier).updateTemperature(temp, 0.0);
        }
        break;

      case 'CameraWarmingStarted':
        _ref.read(cameraStateProvider.notifier).setCooling(false);
        break;

      case 'CameraWarmingCompleted':
        // Warming finished - no additional action needed
        break;
    }
  }

  /// Handle device disconnection event
  void _handleDeviceDisconnected(String? deviceType, String? deviceId) {
    if (deviceType == null || deviceId == null) return;

    // Log the disconnection event with timestamp
    try {
      final logger = _ref.read(loggingServiceProvider);
      logger.warning(
        'Device disconnected: $deviceType ($deviceId) at ${DateTime.now().toIso8601String()}',
        source: 'DeviceService',
      );
    } catch (e) {
      // Logging service not available, continue without it
    }

    // Check if this is a critical device and sequence is running
    final isCriticalDevice = deviceType.toLowerCase() == 'camera' || deviceType.toLowerCase() == 'mount';
    if (isCriticalDevice) {
      _handleCriticalDeviceDisconnect(deviceType, deviceId);
    }

    // Update connection state based on device type
    switch (deviceType.toLowerCase()) {
      case 'camera':
        _stopTemperaturePolling();
        _ref.read(cameraStateProvider.notifier).setDisconnected();
        // Attempt auto-reconnection for camera
        _attemptReconnect(DeviceType.camera, deviceId);
        break;

      case 'mount':
        _ref.read(mountStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.mount, deviceId);
        break;

      case 'focuser':
        _ref.read(focuserStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.focuser, deviceId);
        break;

      case 'filterwheel':
      case 'filter wheel':
        _ref.read(filterWheelStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.filterWheel, deviceId);
        break;

      case 'guider':
        _ref.read(guiderStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.guider, deviceId);
        break;

      case 'rotator':
        _ref.read(rotatorStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.rotator, deviceId);
        break;

      case 'dome':
        _ref.read(domeStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.dome, deviceId);
        break;

      case 'weather':
        _ref.read(weatherStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.weather, deviceId);
        break;

      case 'safetymonitor':
      case 'safety monitor':
        _ref.read(safetyMonitorStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.safetyMonitor, deviceId);
        break;
    }
  }

  /// Stored reconnection attempts for each device
  final Map<String, int> _reconnectionAttempts = {};

  /// Timers for reconnection delays
  final Map<String, Timer> _reconnectionTimers = {};

  /// Maximum number of reconnection attempts
  static const int _maxReconnectAttempts = 3;

  /// Reconnection delay backoff (5, 10, 20 seconds)
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  /// Attempt to reconnect to a device with exponential backoff
  Future<void> _attemptReconnect(DeviceType type, String deviceId) async {
    // Check if auto-reconnect is enabled for this device
    bool autoReconnectEnabled = true;

    switch (type) {
      case DeviceType.camera:
        final state = _ref.read(cameraStateProvider);
        autoReconnectEnabled = state.autoReconnectEnabled;
        break;
      default:
        // Other device types auto-reconnect by default
        break;
    }

    if (!autoReconnectEnabled) {
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.info(
          'Auto-reconnect disabled for ${type.displayName} ($deviceId)',
          source: 'DeviceService',
        );
      } catch (e) {
        // Logging service not available
      }
      return;
    }

    // Get current attempt count
    final attemptCount = _reconnectionAttempts[deviceId] ?? 0;

    if (attemptCount >= _maxReconnectAttempts) {
      // Max attempts reached - notify user
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.error(
          'Failed to reconnect ${type.displayName} ($deviceId) after $_maxReconnectAttempts attempts',
          source: 'DeviceService',
        );
      } catch (e) {
        // Logging service not available
      }
      _showReconnectionFailedNotification(type, deviceId);
      _reconnectionAttempts.remove(deviceId);
      return;
    }

    // Increment attempt count
    _reconnectionAttempts[deviceId] = attemptCount + 1;

    // Get delay for this attempt
    final delay = attemptCount < _reconnectDelays.length
        ? _reconnectDelays[attemptCount]
        : _reconnectDelays.last;

    // Log reconnection attempt
    try {
      final logger = _ref.read(loggingServiceProvider);
      logger.info(
        'Scheduling reconnection attempt ${attemptCount + 1}/$_maxReconnectAttempts for ${type.displayName} ($deviceId) in ${delay.inSeconds}s at ${DateTime.now().add(delay).toIso8601String()}',
        source: 'DeviceService',
      );
    } catch (e) {
      // Logging service not available
    }

    // Cancel any existing reconnection timer for this device
    _reconnectionTimers[deviceId]?.cancel();

    // Schedule reconnection attempt
    _reconnectionTimers[deviceId] = Timer(delay, () async {
      try {
        // Log the actual attempt
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Attempting reconnection ${attemptCount + 1}/$_maxReconnectAttempts for ${type.displayName} ($deviceId) at ${DateTime.now().toIso8601String()}',
            source: 'DeviceService',
          );
        } catch (e) {
          // Logging service not available
        }

        await _performReconnection(type, deviceId);

        // Success - reset attempt count
        _reconnectionAttempts.remove(deviceId);
        _reconnectionTimers.remove(deviceId);

        // Log success
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Successfully reconnected ${type.displayName} ($deviceId) at ${DateTime.now().toIso8601String()}',
            source: 'DeviceService',
          );
        } catch (e) {
          // Logging service not available
        }

        // Show success notification
        _showReconnectionSuccessNotification(type, deviceId);

        // If this was a critical device and sequence is paused, consider resuming
        await _considerSequenceResume(type);
      } catch (e) {
        // Log the failure
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Reconnection attempt ${attemptCount + 1}/$_maxReconnectAttempts failed for ${type.displayName} ($deviceId): $e',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }

        // Reconnection failed - try again
        await _attemptReconnect(type, deviceId);
      }
    });
  }

  /// Consider resuming the sequence if reconnection was successful
  Future<void> _considerSequenceResume(DeviceType type) async {
    // Only for critical devices
    if (type != DeviceType.camera && type != DeviceType.mount) {
      return;
    }

    // Check if sequence is paused
    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.paused) {
      return;
    }

    // Check if both critical devices are connected (if they're in the profile)
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    if (activeProfile == null) {
      return;
    }

    bool allCriticalDevicesConnected = true;

    // Check camera if in profile
    if (activeProfile.cameraId != null && activeProfile.cameraId!.isNotEmpty) {
      final cameraState = _ref.read(cameraStateProvider);
      if (cameraState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    // Check mount if in profile
    if (activeProfile.mountId != null && activeProfile.mountId!.isNotEmpty) {
      final mountState = _ref.read(mountStateProvider);
      if (mountState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    // Resume if all critical devices are connected
    if (allCriticalDevicesConnected) {
      try {
        await resumeSequence();
      } catch (e) {
        // Log error if available
      }
    }
  }

  /// Perform the actual reconnection based on device type
  Future<void> _performReconnection(DeviceType type, String deviceId) async {
    switch (type) {
      case DeviceType.camera:
        final notifier = _ref.read(cameraStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.mount:
        final notifier = _ref.read(mountStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.focuser:
        final notifier = _ref.read(focuserStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.filterWheel:
        final notifier = _ref.read(filterWheelStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.guider:
        final notifier = _ref.read(guiderStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.rotator:
        final notifier = _ref.read(rotatorStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.dome:
        final notifier = _ref.read(domeStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.weather:
        final notifier = _ref.read(weatherStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.safetyMonitor:
        final notifier = _ref.read(safetyMonitorStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.switch_:
        // Switch devices not yet supported for reconnection
        break;

      case DeviceType.coverCalibrator:
        // Cover calibrator devices not yet supported for reconnection
        break;
    }
  }

  /// Show notification that reconnection failed after max attempts
  void _showReconnectionFailedNotification(DeviceType type, String deviceId) {
    // Show UI notification with detailed troubleshooting info
    try {
      final uiNotifier = _ref.read(uiNotificationProvider.notifier);
      uiNotifier.showError(
        'Failed to reconnect ${type.displayName} after $_maxReconnectAttempts attempts.\n\n'
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
    } catch (e) {
      // Ignore errors if notification system is not available
    }

    // Also send external notifications (Discord/Pushover) with detailed info
    try {
      final notificationService = _ref.read(notificationServiceProvider);
      notificationService.notifyError(
        errorTitle: 'Device Reconnection Failed',
        errorMessage: '${type.displayName} ($deviceId) could not be reconnected after $_maxReconnectAttempts attempts.\n\n'
            'Auto-reconnection has stopped. Manual intervention required.\n'
            'Check device power, connections, and drivers.',
        source: 'Device Monitor',
      );
    } catch (e) {
      // Ignore errors if notification service is not available
    }
  }

  /// Show notification that reconnection succeeded
  void _showReconnectionSuccessNotification(DeviceType type, String deviceId) {
    // Show UI notification
    try {
      final uiNotifier = _ref.read(uiNotificationProvider.notifier);
      uiNotifier.showSuccess(
        '${type.displayName} has been reconnected successfully.',
        title: 'Device Reconnected',
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      // Ignore errors if notification system is not available
    }

    // Also send external notifications if this was a critical device
    if (type == DeviceType.camera || type == DeviceType.mount) {
      try {
        final notificationService = _ref.read(notificationServiceProvider);
        notificationService.notifyCustom(
          title: 'Device Reconnected',
          message: '${type.displayName} ($deviceId) has been reconnected successfully and is back online.',
          priority: NotificationPriority.normal,
        );
      } catch (e) {
        // Ignore errors if notification service is not available
      }
    }
  }

  /// Cancel all pending reconnection attempts
  void _cancelAllReconnections() {
    for (final timer in _reconnectionTimers.values) {
      timer.cancel();
    }
    _reconnectionTimers.clear();
    _reconnectionAttempts.clear();
  }

  /// Handle disconnection of critical devices (camera, mount) during sequence execution
  Future<void> _handleCriticalDeviceDisconnect(String deviceType, String deviceId) async {
    // Check if sequence is currently running
    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.running) {
      return; // Not running, no action needed
    }

    // Pause the sequence
    try {
      await pauseSequence();
    } catch (e) {
      // Log error if available
    }

    // The sequence will resume automatically if reconnection succeeds
    // The reconnection logic in _performReconnection will handle resuming
  }

  void _handleSequencerEvent(NightshadeEvent event) {
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    final data = event.data;

    switch (event.eventType) {
      case 'SequenceStarted':
        final sequenceName = data['sequence_name'] as String? ?? 'Unknown';
        progressNotifier.updateState(SequenceExecutionState.running);
        progressNotifier.updateProgress(message: 'Started sequence: $sequenceName');
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;
        break;

      case 'SequencePaused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.paused;
        break;

      case 'SequenceResumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;
        break;

      case 'SequenceStopped':
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.idle;
        break;

      case 'SequenceCompleted':
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.completed;
        break;

      case 'NodeStarted':
        final nodeId = data['node_id'] as String? ?? '';
        final nodeType = data['node_type'] as String? ?? '';
        progressNotifier.updateProgress(
          currentNodeId: nodeId,
          currentNodeName: nodeType,
          currentNodeStatus: NodeStatus.running,
        );
        progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
        break;

      case 'NodeCompleted':
        final nodeId = data['node_id'] as String? ?? '';
        final success = data['success'] as bool? ?? true;
        progressNotifier.updateNodeStatus(
          nodeId,
          success ? NodeStatus.success : NodeStatus.failure,
        );
        break;

      case 'Progress':
        final current = (data['current'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        progressNotifier.updateProgress(completedExposures: current);
        progressNotifier.setTotals(total, 0);
        break;

      case 'TargetChanged':
        final targetName = data['target_name'] as String? ?? '';
        progressNotifier.updateProgress(currentTarget: targetName);
        break;

      case 'TargetCompleted':
        final targetName = data['target_name'] as String? ?? '';
        progressNotifier.updateProgress(message: 'Completed target: $targetName');
        break;

      case 'ExposureStarted':
        final frame = (data['frame'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final filter = data['filter'] as String?;
        final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        progressNotifier.updateProgress(
          currentFilter: filter,
          message: 'Exposure $frame/$total - ${durationSecs}s${filter != null ? " ($filter)" : ""}',
        );
        break;

      case 'ExposureCompleted':
        final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        final currentCompleted = _ref.read(sequenceProgressProvider).completedExposures;
        final currentIntegration = _ref.read(sequenceProgressProvider).completedIntegrationSecs;
        progressNotifier.updateProgress(
          completedExposures: currentCompleted + 1,
          completedIntegrationSecs: currentIntegration + durationSecs,
        );
        break;

      case 'Error':
        final message = data['message'] as String? ?? 'Unknown error';
        progressNotifier.updateProgress(message: 'Error: $message');
        break;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _temperaturePollingTimer?.cancel();
    _cancelAllReconnections();
  }
  
  /// Discover available devices of a specific type
  ///
  /// Returns a list of [DeviceInfo] objects representing available devices.
  /// The DeviceInfo type is now the canonical type for device information.
  Future<List<DeviceInfo>> discoverDevices(DeviceType type) async {
    // Backend now returns DeviceInfo directly - no conversion needed
    return await _backend.discoverDevices(type);
  }

  /// Discover INDI devices at a specific server address
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    // Backend returns DeviceInfo directly
    return await _backend.discoverIndiAtAddress(host, port);
  }

  /// Discover Alpaca devices at a specific server address
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(String host, int port) async {
    // Backend returns DeviceInfo directly
    return await _backend.discoverAlpacaAtAddress(host, port);
  }

  /// Connect to a camera
  Future<void> connectCamera(String deviceId) async {
    final notifier = _ref.read(cameraStateProvider.notifier);
    
    // Find device info
    final devices = await discoverDevices(DeviceType.camera);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Camera not found: $deviceId'),
    );
    
    notifier.setConnecting(deviceId, device.name);
    
    try {
      // Connect via native bridge
      await _backend.connectDevice(DeviceType.camera, deviceId);

      notifier.setConnected();

      // Apply active profile's cooling target temperature if available
      // and auto-start cooling if coolOnConnect is enabled
      try {
        final activeProfile = _ref.read(activeEquipmentProfileProvider);
        if (activeProfile?.defaultCoolingTemp != null) {
          notifier.setTargetTemp(activeProfile!.defaultCoolingTemp!);

          if (activeProfile.coolOnConnect) {
            await _backend.cameraSetCooling(
              deviceId: deviceId,
              enabled: true,
              targetTemp: activeProfile.defaultCoolingTemp,
            );
            notifier.setCooling(true);
          }
        }
      } catch (_) {
        // Profile provider not available or cooling command failed - use defaults
      }

      // Start temperature polling (this will immediately poll and update)
      _startTemperaturePolling(deviceId);

      // Start heartbeat monitoring (10 second interval)
      try {
        await _backend.startDeviceHeartbeat(
          deviceType: DeviceType.camera,
          deviceId: deviceId,
          intervalMs: 10000,
        );

        // Log successful heartbeat start
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Started heartbeat monitoring for Camera ($deviceId) with 10s interval',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      } catch (e) {
        // Heartbeat monitoring is optional - log but don't fail connection
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Failed to start heartbeat monitoring for Camera ($deviceId): $e. Device will remain connected but automatic reconnection may not work if connection is lost.',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      }
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Set camera cooling
  Future<void> setCameraCooling({
    required bool enabled,
    double? targetTemp,
  }) async {
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw Exception('Camera not connected');
    }

    // Use the connected device's ID from state, not the profile
    final deviceId = cameraState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No camera device ID available');
    }

    await _backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: enabled,
      targetTemp: targetTemp,
    );
  }
  
  /// Disconnect camera
  Future<void> disconnectCamera() async {
    // Stop temperature polling first
    _stopTemperaturePolling();

    final notifier = _ref.read(cameraStateProvider.notifier);
    final state = _ref.read(cameraStateProvider);

    // Use the connected device's ID from state, not the profile
    final deviceId = state.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      // Stop heartbeat monitoring
      try {
        await _backend.stopDeviceHeartbeat(deviceId);

        // Log successful heartbeat stop
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Stopped heartbeat monitoring for Camera ($deviceId)',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      } catch (e) {
        // Ignore errors during cleanup but log them
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Error stopping heartbeat monitoring for Camera ($deviceId): $e',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      }

      // Disconnect device
      await _backend.disconnectDevice(DeviceType.camera, deviceId);
    }
    notifier.setDisconnected();
  }
  
  /// Connect to a mount
  Future<void> connectMount(String deviceId) async {
    final notifier = _ref.read(mountStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.mount);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Mount not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.mount, deviceId);

      notifier.setConnected();

      // Fetch actual mount status from hardware instead of hardcoding defaults
      try {
        final status = await _backend.getMountStatus(deviceId);
        notifier.updatePosition(
          status.rightAscension,
          status.declination,
          status.altitude,
          status.azimuth,
        );
        notifier.setParked(status.parked);
        notifier.setTracking(status.tracking);
        notifier.setSlewing(status.slewing);
      } catch (e) {
        // If status query fails, log but don't fail the connection
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Failed to get initial mount status for ($deviceId): $e',
            source: 'DeviceService',
          );
        } catch (_) {}
      }

      // Start heartbeat monitoring (10 second interval) for critical device
      try {
        await _backend.startDeviceHeartbeat(
          deviceType: DeviceType.mount,
          deviceId: deviceId,
          intervalMs: 10000,
        );

        // Log successful heartbeat start
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Started heartbeat monitoring for Mount ($deviceId) with 10s interval',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      } catch (e) {
        // Heartbeat monitoring is optional - log but don't fail connection
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Failed to start heartbeat monitoring for Mount ($deviceId): $e. Device will remain connected but automatic reconnection may not work if connection is lost.',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      }
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect mount
  Future<void> disconnectMount() async {
    final notifier = _ref.read(mountStateProvider.notifier);
    final state = _ref.read(mountStateProvider);

    // Use the connected device's ID from state, not the profile
    final deviceId = state.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      // Stop heartbeat monitoring
      try {
        await _backend.stopDeviceHeartbeat(deviceId);

        // Log successful heartbeat stop
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Stopped heartbeat monitoring for Mount ($deviceId)',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      } catch (e) {
        // Ignore errors during cleanup but log them
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Error stopping heartbeat monitoring for Mount ($deviceId): $e',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }
      }

      await _backend.disconnectDevice(
        DeviceType.mount,
        deviceId,
      );
    }
    notifier.setDisconnected();
  }
  
  /// Connect to a focuser
  Future<void> connectFocuser(String deviceId) async {
    final notifier = _ref.read(focuserStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.focuser);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Focuser not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.focuser, deviceId);

      // Get actual focuser status from the backend (now typed FocuserStatus)
      final status = await _backend.getFocuserStatus(deviceId);

      notifier.setConnected(maxPosition: status.maxPosition);
      notifier.updatePosition(status.position);
      if (status.temperature != null) {
        notifier.updateTemperature(status.temperature!);
      }
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Extract max position from focuser status
  int _extractFocuserMaxPosition(dynamic status) {
    if (status is Map<String, dynamic>) {
      return (status['maxPosition'] as num?)?.toInt() ?? 50000;
    }
    try {
      return (status as dynamic).maxPosition as int? ?? 50000;
    } catch (_) {
      return 50000;
    }
  }

  /// Extract current position from focuser status
  int _extractFocuserPosition(dynamic status) {
    if (status is Map<String, dynamic>) {
      return (status['position'] as num?)?.toInt() ?? 0;
    }
    try {
      return (status as dynamic).position as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Extract temperature from focuser status
  double? _extractFocuserTemperature(dynamic status) {
    if (status is Map<String, dynamic>) {
      final temp = status['temperature'];
      if (temp is num) return temp.toDouble();
      return null;
    }
    try {
      return (status as dynamic).temperature as double?;
    } catch (_) {
      return null;
    }
  }
  
  /// Disconnect focuser
  Future<void> disconnectFocuser() async {
    final notifier = _ref.read(focuserStateProvider.notifier);
    final state = _ref.read(focuserStateProvider);

    // Use the connected device's ID from state, not the profile
    final deviceId = state.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      await _backend.disconnectDevice(
        DeviceType.focuser,
        deviceId,
      );
    }
    notifier.setDisconnected();
  }
  
  /// Connect to a filter wheel
  Future<void> connectFilterWheel(String deviceId) async {
    final notifier = _ref.read(filterWheelStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.filterWheel);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Filter wheel not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.filterWheel, deviceId);

      // Fetch current filter wheel status (position + names) from backend
      final status = await _backend.getFilterWheelStatus(deviceId);
      debugPrint('[DeviceService] connectFilterWheel: backend returned ${status.filterNames.length} filter names: ${status.filterNames}');

      notifier.setConnected(
        filterNames: status.filterNames,
      );
      notifier.updatePosition(status.position);
      notifier.setMoving(status.moving);
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }
  
  /// Disconnect filter wheel
  Future<void> disconnectFilterWheel() async {
    final notifier = _ref.read(filterWheelStateProvider.notifier);
    final state = _ref.read(filterWheelStateProvider);

    // Use the connected device's ID from state, not the profile
    final deviceId = state.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      await _backend.disconnectDevice(
        DeviceType.filterWheel,
        deviceId,
      );
    }
    notifier.setDisconnected();
  }
  
  /// Connect to a guider
  Future<void> connectGuider(String deviceId) async {
    final notifier = _ref.read(guiderStateProvider.notifier);

    // Special handling for PHD2 guider - uses different connection method
    if (deviceId == 'phd2_guider') {
      notifier.setConnecting('phd2_guider', 'PHD2 Guiding');
      try {
        final settings = await _ref.read(appSettingsProvider.future);
        await _backend.phd2Connect(
          host: settings.phd2Host,
          port: settings.phd2Port,
        );
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
      return;
    }

    // Standard guider connection (ASCOM/Alpaca/INDI)
    final devices = await discoverDevices(DeviceType.guider);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Guider not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.guider, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }
  
  /// Disconnect guider
  Future<void> disconnectGuider() async {
    final notifier = _ref.read(guiderStateProvider.notifier);
    final state = _ref.read(guiderStateProvider);

    // Use the connected device's ID from state, not the profile
    final deviceId = state.deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      // Special handling for PHD2
      if (deviceId == 'phd2_guider') {
        await _backend.phd2Disconnect();
      } else {
        await _backend.disconnectDevice(
          DeviceType.guider,
          deviceId,
        );
      }
    }
    notifier.setDisconnected();
  }

  /// Connect to a dome
  Future<void> connectDome(String deviceId) async {
    final notifier = _ref.read(domeStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.dome);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Dome not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.dome, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect dome
  Future<void> disconnectDome() async {
    final notifier = _ref.read(domeStateProvider.notifier);
    final state = _ref.read(domeStateProvider);
    if (state.deviceId != null) {
      await _backend.disconnectDevice(DeviceType.dome, state.deviceId!);
    }
    notifier.setDisconnected();
  }

  /// Connect to a weather device
  Future<void> connectWeather(String deviceId) async {
    final notifier = _ref.read(weatherStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.weather);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Weather device not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.weather, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect weather device
  Future<void> disconnectWeather() async {
    final notifier = _ref.read(weatherStateProvider.notifier);
    final state = _ref.read(weatherStateProvider);
    if (state.deviceId != null) {
      await _backend.disconnectDevice(DeviceType.weather, state.deviceId!);
    }
    notifier.setDisconnected();
  }

  /// Connect to a safety monitor
  Future<void> connectSafetyMonitor(String deviceId) async {
    final notifier = _ref.read(safetyMonitorStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.safetyMonitor);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Safety monitor not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.safetyMonitor, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect safety monitor
  Future<void> disconnectSafetyMonitor() async {
    final notifier = _ref.read(safetyMonitorStateProvider.notifier);
    final state = _ref.read(safetyMonitorStateProvider);
    if (state.deviceId != null) {
      await _backend.disconnectDevice(DeviceType.safetyMonitor, state.deviceId!);
    }
    notifier.setDisconnected();
  }

  /// Connect to a rotator
  Future<void> connectRotator(String deviceId) async {
    final notifier = _ref.read(rotatorStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.rotator);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Rotator not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.rotator, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect rotator
  Future<void> disconnectRotator() async {
    final notifier = _ref.read(rotatorStateProvider.notifier);
    final state = _ref.read(rotatorStateProvider);
    if (state.deviceId != null) {
      await _backend.disconnectDevice(DeviceType.rotator, state.deviceId!);
    }
    notifier.setDisconnected();
  }

  /// Connect to a cover calibrator (flat panel)
  Future<void> connectCoverCalibrator(String deviceId) async {
    final notifier = _ref.read(coverCalibratorStateProvider.notifier);

    final devices = await discoverDevices(DeviceType.coverCalibrator);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Cover calibrator not found: $deviceId'),
    );

    notifier.setConnecting(deviceId, device.name);

    try {
      await _backend.connectDevice(DeviceType.coverCalibrator, deviceId);
      notifier.setConnected();
    } catch (e) {
      notifier.setDisconnected();
      rethrow;
    }
  }

  /// Disconnect cover calibrator
  Future<void> disconnectCoverCalibrator() async {
    final notifier = _ref.read(coverCalibratorStateProvider.notifier);
    final state = _ref.read(coverCalibratorStateProvider);
    if (state.deviceId != null) {
      await _backend.disconnectDevice(DeviceType.coverCalibrator, state.deviceId!);
    }
    notifier.setDisconnected();
  }

  /// Connect all devices from a profile
  Future<void> connectProfile({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
  }) async {
    final futures = <Future>[];
    final errors = <String>[];
    
    if (cameraId != null && cameraId.isNotEmpty) {
      futures.add(
        connectCamera(cameraId).catchError((e) {
          errors.add('Camera: $e');
        }),
      );
    }
    
    if (mountId != null && mountId.isNotEmpty) {
      futures.add(
        connectMount(mountId).catchError((e) {
          errors.add('Mount: $e');
        }),
      );
    }
    
    if (focuserId != null && focuserId.isNotEmpty) {
      futures.add(
        connectFocuser(focuserId).catchError((e) {
          errors.add('Focuser: $e');
        }),
      );
    }
    
    if (filterWheelId != null && filterWheelId.isNotEmpty) {
      futures.add(
        connectFilterWheel(filterWheelId).catchError((e) {
          errors.add('Filter Wheel: $e');
        }),
      );
    }
    
    if (guiderId != null && guiderId.isNotEmpty) {
      futures.add(
        connectGuider(guiderId).catchError((e) {
          errors.add('Guider: $e');
        }),
      );
    }
    
    await Future.wait(futures);
    
    if (errors.isNotEmpty) {
      throw Exception('Some devices failed to connect:\n${errors.join('\n')}');
    }
  }
  
  /// Connect all devices from the active equipment profile
  Future<void> connectActiveProfile() async {
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    
    if (activeProfile == null) {
      throw Exception('No active equipment profile selected');
    }
    
    await connectProfile(
      cameraId: activeProfile.cameraId,
      mountId: activeProfile.mountId,
      focuserId: activeProfile.focuserId,
      filterWheelId: activeProfile.filterWheelId,
      guiderId: activeProfile.guiderId,
    );
  }
  
  /// Disconnect all devices
  Future<void> disconnectAll() async {
    await Future.wait([
      disconnectCamera(),
      disconnectMount(),
      disconnectFocuser(),
      disconnectFilterWheel(),
      disconnectGuider(),
    ]);
  }
  
  // ===========================================================================
  // Mount Control
  // ===========================================================================
  
  /// Get the connected mount device ID from mount state (preferred) or active profile
  Future<String?> _getMountDeviceId() async {
    // First check if a mount is currently connected via state provider
    final mountState = _ref.read(mountStateProvider);
    if (mountState.connectionState == DeviceConnectionState.connected &&
        mountState.deviceId != null &&
        mountState.deviceId!.isNotEmpty) {
      return mountState.deviceId;
    }

    // Fall back to active profile
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    return activeProfile?.mountId;
  }
  
  /// Slew mount to coordinates
  Future<void> slewMountToCoordinates(double ra, double dec) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description: 'Slewing to RA ${_formatRA(ra)}, Dec ${_formatDec(dec)}',
      canCancel: true,
    );

    try {
      await _backend.mountSlewToCoordinates(deviceId, ra, dec);
      mountNotifier.updatePosition(ra, dec, 0.0, 0.0);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Format RA for display (hours:minutes)
  String _formatRA(double raHours) {
    final h = raHours.floor();
    final m = ((raHours - h) * 60).floor();
    return '${h}h ${m}m';
  }

  /// Format Dec for display (degrees)
  String _formatDec(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '';
    return '$sign${decDeg.toStringAsFixed(1)}°';
  }

  /// Sync mount to coordinates
  Future<void> syncMountToCoordinates(double ra, double dec) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }
    
    await _backend.mountSync(deviceId, ra, dec);
    
    // Update local state
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.updatePosition(ra, dec, 0.0, 0.0);
  }
  
  /// Park the mount
  Future<void> parkMount() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.parkMount,
      description: 'Parking mount',
    );

    try {
      await _backend.mountPark(deviceId);
      mountNotifier.setParked(true);
      mountNotifier.setTracking(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.parkMount);
    }
  }
  
  /// Unpark the mount
  Future<void> unparkMount() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.unparkMount,
      description: 'Unparking mount',
    );

    try {
      await _backend.mountUnpark(deviceId);
      final mountNotifier = _ref.read(mountStateProvider.notifier);
      mountNotifier.setParked(false);
    } finally {
      operationsNotifier.completeOperation(OperationType.unparkMount);
    }
  }

  /// Enable or disable mount tracking
  Future<void> setMountTracking(bool enabled) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSetTracking(deviceId, enabled);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setTracking(enabled);
  }

  /// Set mount tracking rate
  Future<void> setMountTrackingRate(int rate) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSetTrackingRate(deviceId, rate);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    // Update the state with the new tracking rate
    mountNotifier.setTrackingRate(TrackingRate.values[rate]);
  }

  /// Abort mount slew (emergency stop)
  Future<void> abortMountSlew() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountAbort(deviceId);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setSlewing(false);
  }

  /// Pulse guide the mount in a given direction for a duration
  Future<void> pulseGuidMount({
    required String direction,
    required int durationMs,
  }) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null) {
      throw Exception('No mount connected');
    }

    await _backend.mountPulseGuide(
      deviceId: deviceId,
      direction: direction,
      durationMs: durationMs,
    );
  }

  // ===========================================================================
  // Device ID Helpers
  // ===========================================================================

  /// Get the connected camera device ID
  /// First checks the currently connected camera state, then falls back to active profile
  Future<String?> _getCameraDeviceId() async {
    // First check if we have a currently connected camera
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState == DeviceConnectionState.connected &&
        cameraState.deviceId != null &&
        cameraState.deviceId!.isNotEmpty) {
      return cameraState.deviceId;
    }

    // Fall back to active profile
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    return activeProfile?.cameraId;
  }

  // ===========================================================================
  // Focuser Control
  // ===========================================================================

  /// Get the connected focuser device ID
  /// First checks the currently connected focuser state, then falls back to active profile
  Future<String?> _getFocuserDeviceId() async {
    // First check if we have a currently connected focuser
    final focuserState = _ref.read(focuserStateProvider);
    if (focuserState.connectionState == DeviceConnectionState.connected &&
        focuserState.deviceId != null &&
        focuserState.deviceId!.isNotEmpty) {
      return focuserState.deviceId;
    }

    // Fall back to active profile
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    return activeProfile?.focuserId;
  }
  
  /// Move focuser to absolute position
  Future<void> moveFocuserTo(int position) async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.focuserMove,
      description: 'Moving focuser to $position',
    );

    try {
      await _backend.focuserMoveTo(deviceId, position);
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: position,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Move focuser by relative amount
  /// Uses the backend's native relative move which queries actual device position
  Future<void> moveFocuserRelative(int delta) async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    final direction = delta > 0 ? 'out' : 'in';
    operationsNotifier.startOperation(
      type: OperationType.focuserMove,
      description: 'Moving focuser ${delta.abs()} steps $direction',
    );

    try {
      // Get current position to compute target
      final currentStatus = await _backend.getFocuserStatus(deviceId);
      final targetPosition = currentStatus.position + delta;

      // Use backend's native relative move which queries actual device position
      await _backend.focuserMoveRelative(deviceId, delta);
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: targetPosition,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Halt focuser movement
  Future<void> haltFocuser() async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);

    try {
      await _backend.focuserHalt(deviceId);
      // Query actual position from device after halt
      final status = await _backend.getFocuserStatus(deviceId);
      focuserNotifier.updatePosition(status.position);
    } finally {
      focuserNotifier.setMoving(false);
    }
  }

  /// Verify focuser reached target position with polling and timeout.
  ///
  /// Polls the focuser position every 500ms until it reaches the target
  /// (within 1 step tolerance). Times out after 300 seconds.
  Future<void> _verifyFocuserPosition({
    required String deviceId,
    required int targetPosition,
  }) async {
    final deadline = DateTime.now().add(_focuserMoveTimeout);
    final focuserNotifier = _ref.read(focuserStateProvider.notifier);

    while (true) {
      final status = await _backend.getFocuserStatus(deviceId);
      focuserNotifier.updatePosition(status.position);

      // Check if we've reached the target (within 1 step tolerance)
      if ((status.position - targetPosition).abs() <= 1) {
        focuserNotifier.setMoving(false);
        return;
      }

      // Check if focuser stopped moving but hasn't reached target (stall)
      if (!status.moving && (status.position - targetPosition).abs() > 1) {
        throw Exception(
          'Focuser stalled at position ${status.position}, '
          'target was $targetPosition.',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Focuser did not reach position $targetPosition within '
          '${_focuserMoveTimeout.inSeconds}s '
          '(last reported position: ${status.position}).',
        );
      }

      await Future.delayed(_focuserMovePollInterval);
    }
  }

  /// Run autofocus routine
  /// Returns full autofocus result including focus curve data
  Future<AutofocusResult> runAutofocus({
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
  }) async {
    final focuserDeviceId = await _getFocuserDeviceId();
    if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    // Use the connected camera's device ID
    final cameraDeviceId = await _getCameraDeviceId();
    if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
      throw Exception('No camera connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.autofocus,
      description: 'Running autofocus ($method)',
      currentStep: 'Initializing...',
      canCancel: true,
    );

    try {
      final result = await _backend.autofocusStart(
        deviceId: focuserDeviceId,
        cameraId: cameraDeviceId,
        exposureTime: exposureTime,
        stepSize: stepSize,
        stepsOut: stepsOut,
        method: method,
        binning: binning,
      );

      // Smart notification for autofocus completion
      final hfrText = result.bestHfr.toStringAsFixed(2);
      _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
        message: 'Autofocus complete (HFR: $hfrText)',
        relevantScreens: [AppScreen.imaging, AppScreen.equipment, AppScreen.sequencer],
        title: 'Autofocus',
      );

      return result;
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.autofocus);
    }
  }
  
  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================
  
  /// Get the connected filter wheel device ID
  /// First checks the currently connected filter wheel state, then falls back to active profile
  Future<String?> _getFilterWheelDeviceId() async {
    // First check if we have a currently connected filter wheel
    final filterWheelState = _ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState == DeviceConnectionState.connected &&
        filterWheelState.deviceId != null &&
        filterWheelState.deviceId!.isNotEmpty) {
      return filterWheelState.deviceId;
    }

    // Fall back to active profile
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    return activeProfile?.filterWheelId;
  }
  
  /// Set filter wheel position
  ///
  /// Changes the filter wheel to the specified position and automatically
  /// applies focus offset if configured for the selected filter.
  Future<void> setFilterWheelPosition(int position) async {
    debugPrint('[DeviceService] setFilterWheelPosition called with position: $position');
    final deviceId = await _getFilterWheelDeviceId();
    debugPrint('[DeviceService] Filter wheel deviceId: $deviceId');
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No filter wheel connected');
    }

    final filterWheelNotifier = _ref.read(filterWheelStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    // Get filter name for display
    final filterWheelState = _ref.read(filterWheelStateProvider);
    final filterNames = filterWheelState.filterNames;
    final filterName = position >= 0 && position < filterNames.length
        ? filterNames[position]
        : 'Position $position';

    filterWheelNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.filterChange,
      description: 'Changing filter to $filterName',
    );

    try {
      // Move the filter wheel
      debugPrint('[DeviceService] Calling backend.filterWheelSetPosition($deviceId, $position)');
      await _backend.filterWheelSetPosition(deviceId, position);
      debugPrint('[DeviceService] Backend call completed, verifying position');

      await _verifyFilterWheelPosition(
        deviceId: deviceId,
        expectedPosition: position,
        filterNames: filterNames,
      );

      // Apply focus offset if filter name is available and focuser is connected
      if (position >= 0 && position < filterNames.length) {
        await _applyFilterFocusOffset(filterNames[position]);
      }
    } finally {
      filterWheelNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.filterChange);
    }
  }

  Future<void> _verifyFilterWheelPosition({
    required String deviceId,
    required int expectedPosition,
    required List<String> filterNames,
  }) async {
    final deadline = DateTime.now().add(_filterWheelVerifyTimeout);
    final filterWheelNotifier = _ref.read(filterWheelStateProvider.notifier);

    while (true) {
      final status = await _backend.getFilterWheelStatus(deviceId);
      final isMoving = status.moving || status.position < 0;

      filterWheelNotifier.updatePosition(status.position);
      filterWheelNotifier.setMoving(isMoving);

      if (!isMoving && status.position == expectedPosition) {
        return;
      }

      if (!isMoving && status.position != expectedPosition) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final actualName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel reported "$actualName" after change, expected "$expectedName".',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final lastName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel did not reach "$expectedName" within ${_filterWheelVerifyTimeout.inSeconds}s '
          '(last reported "$lastName").',
        );
      }

      await Future.delayed(_filterWheelVerifyPollInterval);
    }
  }

  String _formatFilterName(List<String> filterNames, int position) {
    if (position >= 0 && position < filterNames.length) {
      return filterNames[position];
    }
    return 'Position $position';
  }

  /// Apply focus offset for a given filter
  ///
  /// Checks if there's a configured offset for this filter and moves
  /// the focuser accordingly. This is called automatically by setFilterWheelPosition.
  Future<void> _applyFilterFocusOffset(String filterName) async {
    try {
      // Check if focuser is connected
      final focuserDeviceId = await _getFocuserDeviceId();
      if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
        // No focuser connected, skip offset application
        return;
      }

      // Check if focuser is ready
      final focuserState = _ref.read(focuserStateProvider);
      if (focuserState.connectionState != DeviceConnectionState.connected) {
        return;
      }

      // Get filter offset
      final filterOffsetState = _ref.read(filterOffsetProvider);
      final offset = filterOffsetState.offsets[filterName];

      if (offset == null || offset == 0) {
        // No offset configured for this filter
        return;
      }

      // Move focuser by the offset amount
      final currentPosition = focuserState.position ?? 0;
      final targetPosition = currentPosition + offset;

      final focuserNotifier = _ref.read(focuserStateProvider.notifier);
      focuserNotifier.setMoving(true);

      try {
        await _backend.focuserMoveTo(focuserDeviceId, targetPosition);
        focuserNotifier.updatePosition(targetPosition);

        // Log the offset application
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.info(
          'Applied focus offset for filter "$filterName": $offset steps (moved to position $targetPosition)'
        );
      } finally {
        focuserNotifier.setMoving(false);
      }
    } catch (e) {
      // Don't fail filter change if focus offset fails
      final loggingService = _ref.read(loggingServiceProvider);
      loggingService.error('Failed to apply focus offset for filter "$filterName": $e');
    }
  }
  
  // ===========================================================================
  // Guiding Control
  // ===========================================================================
  
  /// Get the connected guider device ID
  /// First checks the currently connected guider state, then falls back to active profile
  Future<String?> _getGuiderDeviceId() async {
    // First check if we have a currently connected guider
    final guiderState = _ref.read(guiderStateProvider);
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.deviceId != null &&
        guiderState.deviceId!.isNotEmpty) {
      return guiderState.deviceId;
    }

    // Fall back to active profile
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();
    return activeProfile?.guiderId;
  }
  
  /// Start guiding
  Future<void> startGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.guideSettle,
      description: 'Starting guiding and settling',
      currentStep: 'Calibrating...',
    );

    try {
      await _backend.guiderStartGuiding(
        deviceId: deviceId,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      final guiderNotifier = _ref.read(guiderStateProvider.notifier);
      guiderNotifier.setGuiding(true);
    } finally {
      operationsNotifier.completeOperation(OperationType.guideSettle);
    }
  }
  
  /// Stop guiding
  Future<void> stopGuiding() async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }
    
    await _backend.guiderStopGuiding(deviceId: deviceId);
    
    final guiderNotifier = _ref.read(guiderStateProvider.notifier);
    guiderNotifier.setGuiding(false);
  }
  
  /// Dither
  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.dither,
      description: 'Dithering ${amount.toStringAsFixed(1)} px',
      currentStep: 'Moving...',
    );

    try {
      await _backend.guiderDither(
        deviceId: deviceId,
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
    } finally {
      operationsNotifier.completeOperation(OperationType.dither);
    }
  }

  // ===========================================================================
  // Sequencer Control
  // ===========================================================================

  Future<void> startSequence() async {
    await _backend.sequencerStart();
  }

  Future<void> stopSequence() async {
    await _backend.sequencerStop();
  }

  Future<void> pauseSequence() async {
    await _backend.sequencerPause();
  }

  Future<void> resumeSequence() async {
    await _backend.sequencerResume();
  }

  Future<void> loadSequence(String json) async {
    await _backend.sequencerLoadJson(json);
  }

  Future<SequencerStatus> getSequencerStatus() async {
    return await _backend.sequencerGetStatus();
  }
}

/// Provider for the device service
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final backend = ref.watch(backendProvider);
  final service = DeviceService(ref, backend);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for available cameras
final availableCamerasProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.camera);
});

/// Provider for available mounts
final availableMountsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.mount);
});

/// Provider for available focusers
final availableFocusersProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.focuser);
});

/// Provider for available filter wheels
final availableFilterWheelsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.filterWheel);
});

/// Provider for available guiders
final availableGuidersProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.guider);
});

/// Provider for available rotators
final availableRotatorsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.rotator);
});

/// Provider for available domes
final availableDomesProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.dome);
});

/// Provider for available weather devices
final availableWeatherProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.weather);
});

/// Provider for available safety monitors
final availableSafetyMonitorsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.safetyMonitor);
});
