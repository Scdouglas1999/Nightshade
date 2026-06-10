part of '../device_service.dart';

extension _DeviceServiceFocuserRotatorControls on DeviceService {
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

    return _activeProfileDeviceId((profile) => profile.cameraId);
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

    return _activeProfileDeviceId((profile) => profile.focuserId);
  }

  /// Move focuser to absolute position
  Future<void> _moveFocuserTo(int position) async {
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
      final verifyGeneration = ++_focuserVerifyGeneration;
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: position,
        generation: verifyGeneration,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Move focuser by relative amount
  /// Uses the backend's native relative move which queries actual device position
  Future<void> _moveFocuserRelative(int delta) async {
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
      final verifyGeneration = ++_focuserVerifyGeneration;
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: targetPosition,
        generation: verifyGeneration,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Halt focuser movement
  Future<void> _haltFocuser() async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    _focuserVerifyGeneration++;

    try {
      await _backend.focuserHalt(deviceId);
      // Query actual position from device after halt
      final status = await _backend.getFocuserStatus(deviceId);
      focuserNotifier.updatePosition(status.position);
    } finally {
      focuserNotifier.setMoving(false);
    }
  }

  // ===========================================================================
  // Rotator Control
  // ===========================================================================

  /// Get the connected rotator device ID.
  /// First checks the currently connected rotator state, then falls back to active profile.
  Future<String?> _getRotatorDeviceId() async {
    final rotatorState = _ref.read(rotatorStateProvider);
    if (rotatorState.connectionState == DeviceConnectionState.connected &&
        rotatorState.deviceId != null &&
        rotatorState.deviceId!.isNotEmpty) {
      return rotatorState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.rotatorId);
  }

  /// Move rotator to an absolute angle (0-360 degrees).
  Future<void> _moveRotatorTo(double angle) async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    rotatorNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.rotatorMove,
      description: 'Moving rotator to ${angle.toStringAsFixed(1)}°',
    );

    try {
      await _backend.rotatorMoveTo(deviceId, angle);
      // Poll until movement completes
      final verifyGeneration = ++_rotatorVerifyGeneration;
      await _verifyRotatorPosition(
        deviceId: deviceId,
        targetAngle: angle,
        generation: verifyGeneration,
      );
    } finally {
      rotatorNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.rotatorMove);
    }
  }

  /// Move rotator by a relative angle (degrees).
  Future<void> _moveRotatorRelative(double delta) async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    final direction = delta > 0 ? 'CW' : 'CCW';
    rotatorNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.rotatorMove,
      description: 'Rotating ${delta.abs().toStringAsFixed(1)}° $direction',
    );

    try {
      // Get current angle to compute target for verification
      final currentAngle = await _backend.rotatorGetAngle(deviceId);
      final targetAngle = (currentAngle + delta) % 360.0;

      await _backend.rotatorMoveRelative(deviceId, delta);
      final verifyGeneration = ++_rotatorVerifyGeneration;
      await _verifyRotatorPosition(
        deviceId: deviceId,
        targetAngle: targetAngle,
        generation: verifyGeneration,
      );
    } finally {
      rotatorNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.rotatorMove);
    }
  }

  /// Halt rotator movement.
  Future<void> _haltRotator() async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);
    _rotatorVerifyGeneration++;

    try {
      await _backend.rotatorHalt(deviceId);
      // Query actual angle from device after halt
      final angle = await _backend.rotatorGetAngle(deviceId);
      rotatorNotifier.updatePosition(angle);
    } finally {
      rotatorNotifier.setMoving(false);
    }
  }

  /// Verify rotator reached target angle with polling and timeout.
  ///
  /// Polls the rotator angle every 500ms until it reaches the target
  /// (within 0.5 degree tolerance). Times out after 120 seconds.
  static const Duration _rotatorMoveTimeout = Duration(seconds: 120);
  static const Duration _rotatorMovePollInterval = Duration(milliseconds: 500);

  Future<void> _verifyRotatorPosition({
    required String deviceId,
    required double targetAngle,
    required int generation,
  }) async {
    final deadline = DateTime.now().add(_rotatorMoveTimeout);
    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);

    while (true) {
      if (_disposed || generation != _rotatorVerifyGeneration) {
        throw StateError('Rotator verification was cancelled.');
      }

      final status = await _backend.getRotatorStatus(deviceId);
      if (_disposed || generation != _rotatorVerifyGeneration) {
        throw StateError('Rotator verification was cancelled.');
      }
      rotatorNotifier.updatePosition(
        status.position,
        mechanicalPosition: status.mechanicalPosition,
      );
      rotatorNotifier.setMoving(status.moving);

      // Check if we're within tolerance (handle wraparound at 0/360)
      final diff = (status.position - targetAngle).abs();
      final wrappedDiff = (360.0 - diff).abs();
      final effectiveDiff = diff < wrappedDiff ? diff : wrappedDiff;

      if (effectiveDiff < 0.5) {
        rotatorNotifier.setMoving(false);
        return;
      }

      // Check if rotator stopped moving but hasn't reached target (stall)
      if (!status.moving && effectiveDiff >= 0.5) {
        throw Exception(
          'Rotator stalled at ${status.position.toStringAsFixed(1)}°, '
          'target was ${targetAngle.toStringAsFixed(1)}° '
          '(diff: ${effectiveDiff.toStringAsFixed(1)}°).',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Rotator did not reach ${targetAngle.toStringAsFixed(1)}° within '
          '${_rotatorMoveTimeout.inSeconds}s '
          '(last reported angle: ${status.position.toStringAsFixed(1)}°).',
        );
      }

      await Future.delayed(_rotatorMovePollInterval);
    }
  }
}
