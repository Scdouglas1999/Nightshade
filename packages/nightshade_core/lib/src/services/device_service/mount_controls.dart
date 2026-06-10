part of '../device_service.dart';

extension _DeviceServiceMountControls on DeviceService {
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

    return _activeProfileDeviceId((profile) => profile.mountId);
  }

  /// Slew mount to coordinates
  Future<void> _slewMountToCoordinates(double ra, double dec) async {
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
  Future<void> _syncMountToCoordinates(double ra, double dec) async {
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
  Future<void> _parkMount() async {
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
  Future<void> _unparkMount() async {
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
  Future<void> _setMountTracking(bool enabled) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSetTracking(deviceId, enabled);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setTracking(enabled);
  }

  /// Set mount tracking rate
  Future<void> _setMountTrackingRate(int rate) async {
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
  Future<void> _abortMountSlew() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountAbort(deviceId);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setSlewing(false);
  }

  /// Slew mount to horizontal (alt/az) coordinates
  Future<void> _slewMountToAltAz(double altitude, double azimuth) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description:
          'Slewing to Alt ${altitude.toStringAsFixed(1)}, Az ${azimuth.toStringAsFixed(1)}',
      canCancel: true,
    );

    try {
      await _backend.mountSlewAltAz(deviceId, altitude, azimuth);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Find mount home position
  Future<void> _findMountHome() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description: 'Finding mount home position',
    );

    try {
      await _backend.mountFindHome(deviceId);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Pulse guide the mount in a given direction for a duration
  Future<void> _pulseGuidMount({
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
}
