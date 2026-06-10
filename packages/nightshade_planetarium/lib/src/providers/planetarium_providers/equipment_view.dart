part of '../planetarium_providers.dart';

// ============================================================================
// Mount Position Provider
// ============================================================================

/// Tracking status for the mount
enum MountTrackingStatus { disconnected, parked, slewing, tracking, stopped }

/// Mount position state for displaying on planetarium
class MountPositionState {
  final double? raHours;
  final double? decDegrees;
  final MountTrackingStatus status;
  final bool isConnected;

  const MountPositionState({
    this.raHours,
    this.decDegrees,
    this.status = MountTrackingStatus.disconnected,
    this.isConnected = false,
  });

  /// Get the mount position as celestial coordinates
  CelestialCoordinate? get coordinates {
    if (raHours == null || decDegrees == null) return null;
    return CelestialCoordinate(ra: raHours!, dec: decDegrees!);
  }

  MountPositionState copyWith({
    double? raHours,
    double? decDegrees,
    MountTrackingStatus? status,
    bool? isConnected,
  }) {
    return MountPositionState(
      raHours: raHours ?? this.raHours,
      decDegrees: decDegrees ?? this.decDegrees,
      status: status ?? this.status,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class MountPositionNotifier extends StateNotifier<MountPositionState> {
  MountPositionNotifier() : super(const MountPositionState());

  /// Update the mount position from external source (e.g., equipment provider)
  void updatePosition({
    required double? raHours,
    required double? decDegrees,
    required MountTrackingStatus status,
    required bool isConnected,
  }) {
    state = MountPositionState(
      raHours: raHours,
      decDegrees: decDegrees,
      status: status,
      isConnected: isConnected,
    );
  }

  void setDisconnected() {
    state = const MountPositionState();
  }
}

final mountPositionProvider =
    StateNotifierProvider<MountPositionNotifier, MountPositionState>((ref) {
      return MountPositionNotifier();
    });

// ============================================================================
// Selected Object Provider
// ============================================================================

/// Currently selected celestial object
class SelectedObjectState {
  final CelestialObject? object;
  final CelestialCoordinate? coordinates;
  final ObjectVisibility? visibility;
  final (double alt, double az)? currentAltAz;

  const SelectedObjectState({
    this.object,
    this.coordinates,
    this.visibility,
    this.currentAltAz,
  });
}

class SelectedObjectNotifier extends StateNotifier<SelectedObjectState> {
  final Ref _ref;

  SelectedObjectNotifier(this._ref) : super(const SelectedObjectState());

  void selectObject(CelestialObject object) {
    final location = _ref.read(observerLocationProvider);
    final time = _ref.read(observationTimeProvider);

    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: object.coordinates.raDegrees,
      decDeg: object.coordinates.dec,
      date: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    final altAz = AstronomyCalculations.objectAltAz(
      raDeg: object.coordinates.raDegrees,
      decDeg: object.coordinates.dec,
      dt: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    state = SelectedObjectState(
      object: object,
      coordinates: object.coordinates,
      visibility: visibility,
      currentAltAz: altAz,
    );
  }

  void selectCoordinates(CelestialCoordinate coord) {
    final location = _ref.read(observerLocationProvider);
    final time = _ref.read(observationTimeProvider);

    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: coord.raDegrees,
      decDeg: coord.dec,
      date: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    final altAz = AstronomyCalculations.objectAltAz(
      raDeg: coord.raDegrees,
      decDeg: coord.dec,
      dt: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    state = SelectedObjectState(
      coordinates: coord,
      visibility: visibility,
      currentAltAz: altAz,
    );
  }

  void clearSelection() {
    state = const SelectedObjectState();
  }
}

final selectedObjectProvider =
    StateNotifierProvider<SelectedObjectNotifier, SelectedObjectState>((ref) {
      return SelectedObjectNotifier(ref);
    });

// ============================================================================
// Equipment FOV Provider
// ============================================================================

/// Equipment configuration for FOV display
class EquipmentFOVState {
  final CameraSensorSpecs? camera;
  final TelescopeSpecs? telescope;
  final double focalReducer;
  final double rotation;

  const EquipmentFOVState({
    this.camera,
    this.telescope,
    this.focalReducer = 1.0,
    this.rotation = 0,
  });

  /// Get effective focal length
  double? get effectiveFocalLength {
    if (telescope == null) return null;
    return telescope!.focalLengthMm * focalReducer;
  }

  /// Get calculated FOV
  (double width, double height)? get fov {
    if (camera == null || effectiveFocalLength == null) return null;

    return FOVCalculator.calculateFOV(
      sensorWidthMm: camera!.widthMm,
      sensorHeightMm: camera!.heightMm,
      focalLengthMm: effectiveFocalLength!,
    );
  }

  /// Get image scale in arcsec/pixel
  double? get imageScale {
    if (camera == null || effectiveFocalLength == null) return null;

    return FOVCalculator.calculateImageScale(
      pixelSizeMicrons: camera!.pixelSizeMicrons,
      focalLengthMm: effectiveFocalLength!,
    );
  }

  EquipmentFOVState copyWith({
    CameraSensorSpecs? camera,
    TelescopeSpecs? telescope,
    double? focalReducer,
    double? rotation,
  }) {
    return EquipmentFOVState(
      camera: camera ?? this.camera,
      telescope: telescope ?? this.telescope,
      focalReducer: focalReducer ?? this.focalReducer,
      rotation: rotation ?? this.rotation,
    );
  }
}

class EquipmentFOVNotifier extends StateNotifier<EquipmentFOVState> {
  EquipmentFOVNotifier() : super(const EquipmentFOVState());

  void setCamera(CameraSensorSpecs camera) {
    state = state.copyWith(camera: camera);
  }

  void setTelescope(TelescopeSpecs telescope) {
    state = state.copyWith(telescope: telescope);
  }

  void setFocalReducer(double multiplier) {
    state = state.copyWith(focalReducer: multiplier);
  }

  void setRotation(double rotation) {
    state = state.copyWith(rotation: rotation % 360);
  }
}

final equipmentFOVProvider =
    StateNotifierProvider<EquipmentFOVNotifier, EquipmentFOVState>((ref) {
      return EquipmentFOVNotifier();
    });
