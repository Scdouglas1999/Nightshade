part of '../ffi_backend.dart';

extension _FfiBackendBridgeModelMappers on _FfiBackendBase {
  dart_status.CameraStatus _fromBridgeCameraStatus(
    bridge_device.CameraStatus s,
  ) {
    return dart_status.CameraStatus(
      connected: s.connected,
      state: _fromBridgeCameraState(s.state),
      sensorTemp: s.sensorTemp,
      coolerPower: s.coolerPower,
      targetTemp: s.targetTemp,
      coolerOn: s.coolerOn,
      gain: s.gain,
      offset: s.offset,
      binX: s.binX,
      binY: s.binY,
      sensorWidth: s.sensorWidth,
      sensorHeight: s.sensorHeight,
      pixelSizeX: s.pixelSizeX,
      pixelSizeY: s.pixelSizeY,
      maxAdu: s.maxAdu,
      canCool: s.canCool,
      canSetGain: s.canSetGain,
      canSetOffset: s.canSetOffset,
    );
  }

  dart_types.CameraState _fromBridgeCameraState(bridge_device.CameraState s) {
    switch (s) {
      case bridge_device.CameraState.idle:
        return dart_types.CameraState.idle;
      case bridge_device.CameraState.waiting:
        return dart_types.CameraState.waiting;
      case bridge_device.CameraState.exposing:
        return dart_types.CameraState.exposing;
      case bridge_device.CameraState.reading:
        return dart_types.CameraState.reading;
      case bridge_device.CameraState.download:
        return dart_types.CameraState.download;
      case bridge_device.CameraState.error:
        return dart_types.CameraState.error;
    }
  }

  dart_status.MountStatus _fromBridgeMountStatus(bridge_device.MountStatus s) {
    return dart_status.MountStatus(
      connected: s.connected,
      tracking: s.tracking,
      slewing: s.slewing,
      parked: s.parked,
      atHome: s.atHome ?? false,
      sideOfPier: s.sideOfPier == null
          ? dart_types.PierSide.unknown
          : _fromBridgePierSide(s.sideOfPier!),
      rightAscension: s.rightAscension,
      declination: s.declination,
      altitude: s.altitude ?? 0.0,
      azimuth: s.azimuth ?? 0.0,
      siderealTime: s.siderealTime ?? 0.0,
      trackingRate: s.trackingRate == null
          ? dart_caps.TrackingRate.sidereal
          : _fromBridgeTrackingRate(s.trackingRate!),
      canPark: s.canPark,
      canSlew: s.canSlew,
      canSync: s.canSync,
      canPulseGuide: s.canPulseGuide,
      canSetTrackingRate: s.canSetTrackingRate,
      availability: s.availability.map(
        (key, value) => MapEntry(key, _fieldAvailabilityToWire(value)),
      ),
    );
  }

  /// Serialize a flutter_rust_bridge [FieldAvailability] to the stable wire
  /// string the headless API and clients expect ('available' / 'unsupported' /
  /// `error: <reason>`). Using `.toString()` would leak the Dart class name
  /// ('FieldAvailability.available()') into the JSON contract.
  String _fieldAvailabilityToWire(bridge_device.FieldAvailability v) {
    return v.when(
      available: () => 'available',
      unsupported: () => 'unsupported',
      error: (reason) => 'error: $reason',
    );
  }

  dart_types.PierSide _fromBridgePierSide(bridge_device.PierSide s) {
    switch (s) {
      case bridge_device.PierSide.east:
        return dart_types.PierSide.east;
      case bridge_device.PierSide.west:
        return dart_types.PierSide.west;
      case bridge_device.PierSide.unknown:
        return dart_types.PierSide.unknown;
    }
  }

  dart_caps.TrackingRate _fromBridgeTrackingRate(bridge_device.TrackingRate r) {
    switch (r) {
      case bridge_device.TrackingRate.sidereal:
        return dart_caps.TrackingRate.sidereal;
      case bridge_device.TrackingRate.lunar:
        return dart_caps.TrackingRate.lunar;
      case bridge_device.TrackingRate.solar:
        return dart_caps.TrackingRate.solar;
      case bridge_device.TrackingRate.king:
        return dart_caps.TrackingRate.king;
      case bridge_device.TrackingRate.custom:
        return dart_caps.TrackingRate.custom;
    }
  }

  dart_status.FocuserStatus _fromBridgeFocuserStatus(
    bridge_device.FocuserStatus s,
  ) {
    return dart_status.FocuserStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      temperature: s.temperature,
      maxPosition: s.maxPosition,
      stepSize: s.stepSize,
      isAbsolute: s.isAbsolute,
      hasTemperature: s.hasTemperature,
    );
  }

  dart_status.FilterWheelStatus _fromBridgeFilterWheelStatus(
    bridge_device.FilterWheelStatus s,
  ) {
    return dart_status.FilterWheelStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      filterCount: s.filterCount,
      filterNames: s.filterNames,
    );
  }

  dart_status.RotatorStatus _fromBridgeRotatorStatus(
    bridge_device.RotatorStatus s,
  ) {
    return dart_status.RotatorStatus(
      connected: s.connected,
      position: s.position,
      moving: s.moving,
      mechanicalPosition: s.mechanicalPosition,
      isMoving: s.isMoving,
      canReverse: s.canReverse,
    );
  }

  // Type conversion helpers

  bridge.DeviceType _toBridgeDeviceType(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return bridge.DeviceType.camera;
      case DeviceType.mount:
        return bridge.DeviceType.mount;
      case DeviceType.focuser:
        return bridge.DeviceType.focuser;
      case DeviceType.filterWheel:
        return bridge.DeviceType.filterWheel;
      case DeviceType.guider:
        return bridge.DeviceType.guider;
      case DeviceType.dome:
        return bridge.DeviceType.dome;
      case DeviceType.rotator:
        return bridge.DeviceType.rotator;
      case DeviceType.weather:
        return bridge.DeviceType.weather;
      case DeviceType.safetyMonitor:
        return bridge.DeviceType.safetyMonitor;
      case DeviceType.switch_:
        return bridge.DeviceType.switch_;
      case DeviceType.coverCalibrator:
        return bridge.DeviceType.coverCalibrator;
    }
  }

  DeviceType _fromBridgeDeviceType(bridge.DeviceType type) {
    switch (type) {
      case bridge.DeviceType.camera:
        return DeviceType.camera;
      case bridge.DeviceType.mount:
        return DeviceType.mount;
      case bridge.DeviceType.focuser:
        return DeviceType.focuser;
      case bridge.DeviceType.filterWheel:
        return DeviceType.filterWheel;
      case bridge.DeviceType.guider:
        return DeviceType.guider;
      case bridge.DeviceType.dome:
        return DeviceType.dome;
      case bridge.DeviceType.rotator:
        return DeviceType.rotator;
      case bridge.DeviceType.weather:
        return DeviceType.weather;
      case bridge.DeviceType.safetyMonitor:
        return DeviceType.safetyMonitor;
      case bridge.DeviceType.switch_:
        return DeviceType.switch_;
      case bridge.DeviceType.coverCalibrator:
        return DeviceType.coverCalibrator;
    }
  }

  DriverType _fromBridgeDriverType(bridge.DriverType type) {
    switch (type) {
      case bridge.DriverType.ascom:
        return DriverType.ascom;
      case bridge.DriverType.alpaca:
        return DriverType.alpaca;
      case bridge.DriverType.indi:
        return DriverType.indi;
      case bridge.DriverType.native:
        return DriverType.native;
      case bridge.DriverType.simulator:
        return DriverType.simulator;
    }
  }

  // Mappers
  models.AppSettings _fromBridgeSettings(bridge.AppSettings s) {
    final loc = s.location != null ? _fromBridgeLocation(s.location!) : null;
    return models.AppSettings(
      location: loc,
      theme: s.theme,
      language: s.language,
      autoConnect: s.autoConnect,
      // Map location fields to direct fields for compatibility
      latitude: loc?.latitude ?? 0.0,
      longitude: loc?.longitude ?? 0.0,
      elevation: loc?.elevation ?? 0.0,
      // Keep defaults for other fields
      fileNamingPattern: '',
      meridianFlipMinutes: 5,
      autoFocusEveryMinutes: 60,
      ditherEveryFrames: 3,
      plateSolveTimeout: 60,
      plateSolveSearchRadius: 30.0,
      discordWebhook: '',
      pushoverKey: '',
      pushoverUser: '',
    );
  }

  bridge.AppSettings _toBridgeSettings(models.AppSettings s) {
    // Use location if available, otherwise create from direct fields
    final loc =
        s.location ??
        (s.latitude != 0.0 || s.longitude != 0.0
            ? models.ObserverLocation(
                latitude: s.latitude,
                longitude: s.longitude,
                elevation: s.elevation,
              )
            : null);
    return bridge.AppSettings(
      location: loc != null ? _toBridgeLocation(loc) : null,
      theme: s.theme,
      language: s.language,
      autoConnect: s.autoConnect,
    );
  }

  models.ObserverLocation _fromBridgeLocation(bridge.ObserverLocation l) {
    return models.ObserverLocation(
      latitude: l.latitude,
      longitude: l.longitude,
      elevation: l.elevation,
    );
  }

  bridge.ObserverLocation _toBridgeLocation(models.ObserverLocation l) {
    return bridge.ObserverLocation(
      latitude: l.latitude,
      longitude: l.longitude,
      elevation: l.elevation,
    );
  }

  EquipmentProfile _fromBridgeProfile(bridge.EquipmentProfile p) {
    return EquipmentProfile(
      id: p.id,
      name: p.name,
      cameraId: p.cameraId,
      mountId: p.mountId,
      focuserId: p.focuserId,
      filterWheelId: p.filterWheelId,
      guiderId: p.guiderId,
      rotatorId: p.rotatorId,
      domeId: p.domeId,
      weatherId: p.weatherId,
      safetyMonitorId: p.safetyMonitorId,
      coverCalibratorId: p.coverCalibratorId,
      telescopeFocalLength: p.telescopeFocalLength,
      telescopeAperture: p.telescopeAperture,
    );
  }

  bridge.EquipmentProfile _toBridgeProfile(EquipmentProfile p) {
    return bridge.EquipmentProfile(
      id: p.id,
      name: p.name,
      cameraId: p.cameraId,
      mountId: p.mountId,
      focuserId: p.focuserId,
      filterWheelId: p.filterWheelId,
      guiderId: p.guiderId,
      rotatorId: p.rotatorId,
      domeId: p.domeId,
      weatherId: p.weatherId,
      safetyMonitorId: p.safetyMonitorId,
      coverCalibratorId: p.coverCalibratorId,
      // The bridge schema still carries the legacy telescope* field names,
      // while current Drift profiles store optics in focalLength/aperture.
      // Serialize the effective values so legacy and current rows both reach
      // FFI consumers (notably the headless planetarium FOV endpoint).
      telescopeFocalLength: p.focalLength > 0
          ? p.focalLength
          : p.telescopeFocalLength,
      telescopeAperture: p.aperture > 0 ? p.aperture : p.telescopeAperture,
    );
  }
}
