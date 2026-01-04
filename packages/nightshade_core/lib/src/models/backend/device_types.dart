/// Device types and connection state for Nightshade equipment management.

/// Device types supported by Nightshade
enum DeviceType {
  camera,
  mount,
  focuser,
  filterWheel,
  guider,
  dome,
  rotator,
  weather,
  safetyMonitor,
  switch_,
  coverCalibrator,
}

/// Driver backend type
enum DriverType {
  ascom,
  alpaca,
  indi,
  native,
  simulator,
}

/// Device connection state
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Side of pier for German Equatorial mounts
enum PierSide {
  east,
  west,
  unknown,
}

/// Camera operational state
enum CameraState {
  idle,
  waiting,
  exposing,
  reading,
  download,
  error,
}
