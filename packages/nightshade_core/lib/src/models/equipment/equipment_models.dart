import 'package:equatable/equatable.dart';

import '../backend/device_capabilities.dart' show TrackingRate;
import '../errors/nightshade_error.dart';

// Re-export TrackingRate from device_capabilities as the canonical source
export '../backend/device_capabilities.dart' show TrackingRate;

/// Base device state
enum DeviceConnectionState { disconnected, connecting, connected, error }

/// Device error types for categorized error handling
enum DeviceErrorType {
  /// Connection to device failed
  connectionFailed,
  /// Device was not found
  deviceNotFound,
  /// Operation timed out
  timeout,
  /// Device driver error
  driverError,
  /// Invalid parameter passed
  invalidParameter,
  /// Device is busy
  busy,
  /// Permission denied
  permissionDenied,
  /// Communication error
  communicationError,
  /// Unknown error
  unknown,
}

/// Represents an error from a device operation
class DeviceError extends Equatable {
  /// Type of error
  final DeviceErrorType type;

  /// Human-readable error message
  final String message;

  /// Optional error code from the device/driver
  final String? code;

  /// When the error occurred
  final DateTime timestamp;

  /// Device ID that caused the error
  final String? deviceId;

  /// Number of retry attempts made
  final int retryAttempts;

  /// Whether this error is recoverable (can retry)
  final bool recoverable;

  const DeviceError({
    required this.type,
    required this.message,
    this.code,
    required this.timestamp,
    this.deviceId,
    this.retryAttempts = 0,
    this.recoverable = true,
  });

  /// Create a DeviceError from an exception
  ///
  /// If the exception is a [NightshadeError], the structured error information
  /// is extracted directly. Otherwise, the error message is parsed to determine
  /// the error category.
  factory DeviceError.fromException(
    Object error, {
    String? deviceId,
    int retryAttempts = 0,
  }) {
    // If it's already a NightshadeError, convert directly
    if (error is NightshadeError) {
      return DeviceError.fromNightshadeError(
        error,
        deviceId: deviceId,
        retryAttempts: retryAttempts,
      );
    }

    final message = error.toString();

    // Try to categorize the error from the message
    DeviceErrorType type = DeviceErrorType.unknown;
    bool recoverable = true;

    if (message.toLowerCase().contains('timeout')) {
      type = DeviceErrorType.timeout;
    } else if (message.toLowerCase().contains('not found') ||
        message.toLowerCase().contains('notfound')) {
      type = DeviceErrorType.deviceNotFound;
      recoverable = false;
    } else if (message.toLowerCase().contains('connection') ||
        message.toLowerCase().contains('connect')) {
      type = DeviceErrorType.connectionFailed;
    } else if (message.toLowerCase().contains('driver')) {
      type = DeviceErrorType.driverError;
    } else if (message.toLowerCase().contains('busy')) {
      type = DeviceErrorType.busy;
    } else if (message.toLowerCase().contains('permission') ||
        message.toLowerCase().contains('denied')) {
      type = DeviceErrorType.permissionDenied;
      recoverable = false;
    }

    return DeviceError(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      deviceId: deviceId,
      retryAttempts: retryAttempts,
      recoverable: recoverable,
    );
  }

  /// Create a DeviceError from a structured [NightshadeError]
  ///
  /// This provides a more accurate conversion using the structured error
  /// information from the native backend.
  factory DeviceError.fromNightshadeError(
    NightshadeError error, {
    String? deviceId,
    int retryAttempts = 0,
  }) {
    // Map BackendErrorCategory to DeviceErrorType
    final type = switch (error.category) {
      BackendErrorCategory.connection => DeviceErrorType.connectionFailed,
      BackendErrorCategory.hardware => DeviceErrorType.communicationError,
      BackendErrorCategory.timeout => DeviceErrorType.timeout,
      BackendErrorCategory.validation => DeviceErrorType.invalidParameter,
      BackendErrorCategory.unsupported => DeviceErrorType.invalidParameter,
      BackendErrorCategory.busy => DeviceErrorType.busy,
      BackendErrorCategory.imaging => DeviceErrorType.driverError,
      BackendErrorCategory.io => DeviceErrorType.driverError,
      BackendErrorCategory.sequence => DeviceErrorType.driverError,
      BackendErrorCategory.driver => DeviceErrorType.driverError,
      BackendErrorCategory.system => DeviceErrorType.unknown,
      BackendErrorCategory.unknown => DeviceErrorType.unknown,
    };

    // Determine recoverability - prefer NightshadeError's assessment
    final recoverable = error.isRecoverable;

    return DeviceError(
      type: type,
      message: error.userMessage,
      code: error.errorCode?.toString(),
      timestamp: DateTime.now(),
      deviceId: deviceId ?? error.deviceId,
      retryAttempts: retryAttempts,
      recoverable: recoverable,
    );
  }

  /// Get a user-friendly description of the error
  String get userMessage {
    switch (type) {
      case DeviceErrorType.connectionFailed:
        return 'Failed to connect to device. Please check the device is powered on and connected.';
      case DeviceErrorType.deviceNotFound:
        return 'Device not found. The device may have been disconnected or is not available.';
      case DeviceErrorType.timeout:
        return 'Operation timed out. The device may be unresponsive.';
      case DeviceErrorType.driverError:
        return 'Device driver error. Try restarting the device or reinstalling drivers.';
      case DeviceErrorType.invalidParameter:
        return 'Invalid parameter. The requested operation is not supported.';
      case DeviceErrorType.busy:
        return 'Device is busy. Please wait and try again.';
      case DeviceErrorType.permissionDenied:
        return 'Permission denied. The device may be in use by another application.';
      case DeviceErrorType.communicationError:
        return 'Communication error. Check the connection to the device.';
      case DeviceErrorType.unknown:
        return message.isNotEmpty ? message : 'An unknown error occurred.';
    }
  }

  /// Get a suggested recovery action
  String? get suggestedAction {
    switch (type) {
      case DeviceErrorType.connectionFailed:
        return 'Try reconnecting or restart the device.';
      case DeviceErrorType.deviceNotFound:
        return 'Check device connections and refresh the device list.';
      case DeviceErrorType.timeout:
        return 'Wait a moment and try again. Consider increasing timeout settings.';
      case DeviceErrorType.driverError:
        return 'Update or reinstall device drivers.';
      case DeviceErrorType.busy:
        return 'Wait for the current operation to complete.';
      case DeviceErrorType.permissionDenied:
        return 'Close other applications using this device.';
      case DeviceErrorType.communicationError:
        return 'Check cables and connections.';
      default:
        return null;
    }
  }

  @override
  List<Object?> get props =>
      [type, message, code, timestamp, deviceId, retryAttempts, recoverable];

  @override
  String toString() =>
      'DeviceError(type: $type, message: $message, deviceId: $deviceId)';
}

/// Camera state
class CameraState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final double? temperature;
  final double? coolerPower;
  /// User-set target temperature for cooling
  final double targetTemp;
  final int? gain;
  final int? offset;
  final String? binning;
  final bool isCooling;
  final bool isExposing;
  final double? exposureProgress;
  final DeviceError? lastError;
  /// Last successful communication timestamp
  final DateTime? lastSuccessfulCommunication;
  /// Whether auto-reconnection is enabled for this device
  final bool autoReconnectEnabled;

  const CameraState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.temperature,
    this.coolerPower,
    this.targetTemp = -10.0,
    this.gain,
    this.offset,
    this.binning,
    this.isCooling = false,
    this.isExposing = false,
    this.exposureProgress,
    this.lastError,
    this.lastSuccessfulCommunication,
    this.autoReconnectEnabled = true,
  });

  /// Whether the camera has an error
  bool get hasError => lastError != null;

  /// Whether the device is healthy (communicated within last 30 seconds)
  bool get isHealthy {
    if (connectionState != DeviceConnectionState.connected) return false;
    if (lastSuccessfulCommunication == null) return true; // Optimistic for new connections
    return DateTime.now().difference(lastSuccessfulCommunication!).inSeconds < 30;
  }

  /// Clear error and return a new state
  CameraState clearError() => copyWith(lastError: null);

  CameraState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    double? temperature,
    double? coolerPower,
    double? targetTemp,
    int? gain,
    int? offset,
    String? binning,
    bool? isCooling,
    bool? isExposing,
    double? exposureProgress,
    DeviceError? lastError,
    DateTime? lastSuccessfulCommunication,
    bool? autoReconnectEnabled,
    bool clearError = false,
  }) {
    return CameraState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      temperature: temperature ?? this.temperature,
      coolerPower: coolerPower ?? this.coolerPower,
      targetTemp: targetTemp ?? this.targetTemp,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      binning: binning ?? this.binning,
      isCooling: isCooling ?? this.isCooling,
      isExposing: isExposing ?? this.isExposing,
      exposureProgress: exposureProgress ?? this.exposureProgress,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastSuccessfulCommunication: lastSuccessfulCommunication ?? this.lastSuccessfulCommunication,
      autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        temperature,
        coolerPower,
        targetTemp,
        gain,
        offset,
        binning,
        isCooling,
        isExposing,
        exposureProgress,
        lastError,
        lastSuccessfulCommunication,
        autoReconnectEnabled,
      ];
}

/// Mount state
class MountState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final double? ra;
  final double? dec;
  final double? altitude;
  final double? azimuth;
  final bool isTracking;
  final bool isSlewing;
  final bool isParked;
  final String? sideOfPier;
  final TrackingRate trackingRate;
  final bool canSetTrackingRate;
  final DeviceError? lastError;

  const MountState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.ra,
    this.dec,
    this.altitude,
    this.azimuth,
    this.isTracking = false,
    this.isSlewing = false,
    this.isParked = true,
    this.sideOfPier,
    this.trackingRate = TrackingRate.sidereal,
    this.canSetTrackingRate = false,
    this.lastError,
  });

  bool get hasError => lastError != null;
  MountState clearError() => copyWith(clearError: true);

  MountState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    double? ra,
    double? dec,
    double? altitude,
    double? azimuth,
    bool? isTracking,
    bool? isSlewing,
    bool? isParked,
    String? sideOfPier,
    TrackingRate? trackingRate,
    bool? canSetTrackingRate,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return MountState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ra: ra ?? this.ra,
      dec: dec ?? this.dec,
      altitude: altitude ?? this.altitude,
      azimuth: azimuth ?? this.azimuth,
      isTracking: isTracking ?? this.isTracking,
      isSlewing: isSlewing ?? this.isSlewing,
      isParked: isParked ?? this.isParked,
      sideOfPier: sideOfPier ?? this.sideOfPier,
      trackingRate: trackingRate ?? this.trackingRate,
      canSetTrackingRate: canSetTrackingRate ?? this.canSetTrackingRate,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        ra,
        dec,
        altitude,
        azimuth,
        isTracking,
        isSlewing,
        isParked,
        sideOfPier,
        trackingRate,
        canSetTrackingRate,
        lastError,
      ];
}

/// Focuser state
class FocuserState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final int? position;
  final int? maxPosition;
  final double? temperature;
  final bool isMoving;
  final DeviceError? lastError;

  const FocuserState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.position,
    this.maxPosition,
    this.temperature,
    this.isMoving = false,
    this.lastError,
  });

  bool get hasError => lastError != null;
  FocuserState clearError() => copyWith(clearError: true);

  FocuserState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    int? position,
    int? maxPosition,
    double? temperature,
    bool? isMoving,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return FocuserState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      position: position ?? this.position,
      maxPosition: maxPosition ?? this.maxPosition,
      temperature: temperature ?? this.temperature,
      isMoving: isMoving ?? this.isMoving,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        position,
        maxPosition,
        temperature,
        isMoving,
        lastError,
      ];
}

/// Filter wheel state
class FilterWheelState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final int? currentPosition;
  final List<String> filterNames;
  final bool isMoving;
  final DeviceError? lastError;

  const FilterWheelState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.currentPosition,
    this.filterNames = const [],
    this.isMoving = false,
    this.lastError,
  });

  String? get currentFilterName {
    if (currentPosition != null && currentPosition! < filterNames.length) {
      return filterNames[currentPosition!];
    }
    return null;
  }

  bool get hasError => lastError != null;
  FilterWheelState clearError() => copyWith(clearError: true);

  FilterWheelState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    int? currentPosition,
    List<String>? filterNames,
    bool? isMoving,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return FilterWheelState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      currentPosition: currentPosition ?? this.currentPosition,
      filterNames: filterNames ?? this.filterNames,
      isMoving: isMoving ?? this.isMoving,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        currentPosition,
        filterNames,
        isMoving,
        lastError,
      ];
}

/// Guider state
class GuiderState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final bool isGuiding;
  final bool isCalibrating;
  final double? rmsRa;
  final double? rmsDec;
  final double? rmsTotal;
  final DeviceError? lastError;

  const GuiderState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.isGuiding = false,
    this.isCalibrating = false,
    this.rmsRa,
    this.rmsDec,
    this.rmsTotal,
    this.lastError,
  });

  bool get hasError => lastError != null;
  GuiderState clearError() => copyWith(clearError: true);

  GuiderState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    bool? isGuiding,
    bool? isCalibrating,
    double? rmsRa,
    double? rmsDec,
    double? rmsTotal,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return GuiderState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      isGuiding: isGuiding ?? this.isGuiding,
      isCalibrating: isCalibrating ?? this.isCalibrating,
      rmsRa: rmsRa ?? this.rmsRa,
      rmsDec: rmsDec ?? this.rmsDec,
      rmsTotal: rmsTotal ?? this.rmsTotal,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        isGuiding,
        isCalibrating,
        rmsRa,
        rmsDec,
        rmsTotal,
        lastError,
      ];
}

/// Rotator state
class RotatorState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final double? position;
  final double? mechanicalPosition;
  final bool isMoving;
  final bool isReversed;
  final DeviceError? lastError;

  const RotatorState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.position,
    this.mechanicalPosition,
    this.isMoving = false,
    this.isReversed = false,
    this.lastError,
  });

  bool get hasError => lastError != null;
  RotatorState clearError() => copyWith(clearError: true);

  RotatorState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    double? position,
    double? mechanicalPosition,
    bool? isMoving,
    bool? isReversed,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return RotatorState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      position: position ?? this.position,
      mechanicalPosition: mechanicalPosition ?? this.mechanicalPosition,
      isMoving: isMoving ?? this.isMoving,
      isReversed: isReversed ?? this.isReversed,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        position,
        mechanicalPosition,
        isMoving,
        isReversed,
        lastError,
      ];
}

/// Dome shutter status
enum ShutterStatus { open, closed, opening, closing, error, unknown }

/// Dome state
class DomeState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final double? azimuth;
  final ShutterStatus shutterStatus;
  final bool isSlewing;
  final bool isParked;
  final bool isAtHome;
  final bool isSlaved;
  final DeviceError? lastError;

  const DomeState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.azimuth,
    this.shutterStatus = ShutterStatus.unknown,
    this.isSlewing = false,
    this.isParked = false,
    this.isAtHome = false,
    this.isSlaved = false,
    this.lastError,
  });

  bool get hasError => lastError != null;
  DomeState clearError() => copyWith(clearError: true);

  DomeState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    double? azimuth,
    ShutterStatus? shutterStatus,
    bool? isSlewing,
    bool? isParked,
    bool? isAtHome,
    bool? isSlaved,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return DomeState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      azimuth: azimuth ?? this.azimuth,
      shutterStatus: shutterStatus ?? this.shutterStatus,
      isSlewing: isSlewing ?? this.isSlewing,
      isParked: isParked ?? this.isParked,
      isAtHome: isAtHome ?? this.isAtHome,
      isSlaved: isSlaved ?? this.isSlaved,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        azimuth,
        shutterStatus,
        isSlewing,
        isParked,
        isAtHome,
        isSlaved,
        lastError,
      ];
}

/// Weather state
class WeatherState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final double? temperature;
  final double? humidity;
  final double? pressure;
  final double? cloudCover;
  final double? dewPoint;
  final double? windSpeed;
  final double? windDirection;
  final double? skyQuality;
  final double? skyTemperature;
  final double? rainRate;
  final DateTime? lastUpdated;
  final DeviceError? lastError;

  const WeatherState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.temperature,
    this.humidity,
    this.pressure,
    this.cloudCover,
    this.dewPoint,
    this.windSpeed,
    this.windDirection,
    this.skyQuality,
    this.skyTemperature,
    this.rainRate,
    this.lastUpdated,
    this.lastError,
  });

  bool get hasError => lastError != null;
  WeatherState clearError() => copyWith(clearError: true);

  WeatherState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    double? temperature,
    double? humidity,
    double? pressure,
    double? cloudCover,
    double? dewPoint,
    double? windSpeed,
    double? windDirection,
    double? skyQuality,
    double? skyTemperature,
    double? rainRate,
    DateTime? lastUpdated,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return WeatherState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      pressure: pressure ?? this.pressure,
      cloudCover: cloudCover ?? this.cloudCover,
      dewPoint: dewPoint ?? this.dewPoint,
      windSpeed: windSpeed ?? this.windSpeed,
      windDirection: windDirection ?? this.windDirection,
      skyQuality: skyQuality ?? this.skyQuality,
      skyTemperature: skyTemperature ?? this.skyTemperature,
      rainRate: rainRate ?? this.rainRate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        temperature,
        humidity,
        pressure,
        cloudCover,
        dewPoint,
        windSpeed,
        windDirection,
        skyQuality,
        skyTemperature,
        rainRate,
        lastUpdated,
        lastError,
      ];
}

/// Safety monitor state
class SafetyMonitorState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final bool isSafe;
  final DateTime? lastChecked;
  final DeviceError? lastError;

  const SafetyMonitorState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.isSafe = true,
    this.lastChecked,
    this.lastError,
  });

  bool get hasError => lastError != null;
  SafetyMonitorState clearError() => copyWith(clearError: true);

  SafetyMonitorState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    bool? isSafe,
    DateTime? lastChecked,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return SafetyMonitorState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      isSafe: isSafe ?? this.isSafe,
      lastChecked: lastChecked ?? this.lastChecked,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        isSafe,
        lastChecked,
        lastError,
      ];
}

// ============================================================================
// Cover Calibrator State
// ============================================================================

/// Cover position status
enum CoverStatus {
  notPresent,
  closed,
  moving,
  open,
  unknown,
  error,
}

/// Calibrator (flat light) status
enum CalibratorStatus {
  notPresent,
  off,
  notReady,
  ready,
  unknown,
  error,
}

class CoverCalibratorState extends Equatable {
  final DeviceConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final CoverStatus coverStatus;
  final CalibratorStatus calibratorStatus;
  final int brightness;
  final int maxBrightness;
  final DeviceError? lastError;

  const CoverCalibratorState({
    this.connectionState = DeviceConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.coverStatus = CoverStatus.unknown,
    this.calibratorStatus = CalibratorStatus.unknown,
    this.brightness = 0,
    this.maxBrightness = 100,
    this.lastError,
  });

  bool get hasError => lastError != null;
  bool get hasCover => coverStatus != CoverStatus.notPresent;
  bool get hasCalibrator => calibratorStatus != CalibratorStatus.notPresent;
  bool get isCoverOpen => coverStatus == CoverStatus.open;
  bool get isCoverClosed => coverStatus == CoverStatus.closed;
  bool get isCoverMoving => coverStatus == CoverStatus.moving;
  bool get isCalibratorOn => calibratorStatus == CalibratorStatus.ready;

  CoverCalibratorState clearError() => copyWith(clearError: true);

  CoverCalibratorState copyWith({
    DeviceConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    CoverStatus? coverStatus,
    CalibratorStatus? calibratorStatus,
    int? brightness,
    int? maxBrightness,
    DeviceError? lastError,
    bool clearError = false,
  }) {
    return CoverCalibratorState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      coverStatus: coverStatus ?? this.coverStatus,
      calibratorStatus: calibratorStatus ?? this.calibratorStatus,
      brightness: brightness ?? this.brightness,
      maxBrightness: maxBrightness ?? this.maxBrightness,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        connectionState,
        deviceId,
        deviceName,
        coverStatus,
        calibratorStatus,
        brightness,
        maxBrightness,
        lastError,
      ];
}

