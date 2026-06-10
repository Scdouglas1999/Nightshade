part of '../device_service.dart';

extension _DeviceServiceFilterWheelControls on DeviceService {
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

    return _activeProfileDeviceId((profile) => profile.filterWheelId);
  }

  /// Set filter wheel position
  ///
  /// Changes the filter wheel to the specified position and automatically
  /// applies focus offset if configured for the selected filter.
  Future<void> _setFilterWheelPosition(int position) async {
    final deviceId = await _getFilterWheelDeviceId();
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

    var hardwareStillMoving = false;
    try {
      // Move the filter wheel
      _ref
          .read(loggingServiceProvider)
          .debug(
            'Changing filter wheel $deviceId to $filterName '
            '(position $position)',
            source: 'DeviceService',
          );
      await _backend.filterWheelSetPosition(deviceId, position);

      final verifyGeneration = ++_filterWheelVerifyGeneration;
      await _verifyFilterWheelPosition(
        deviceId: deviceId,
        expectedPosition: position,
        filterNames: filterNames,
        generation: verifyGeneration,
      );

      // Apply focus offset only after position is verified (DV-P0-6).
      if (position >= 0 && position < filterNames.length) {
        await _applyFilterFocusOffset(filterNames[position]);
      }
    } catch (e) {
      hardwareStillMoving = await _recoverFilterWheelMovingState(
        deviceId,
        filterWheelNotifier,
      );
      rethrow;
    } finally {
      if (!hardwareStillMoving) {
        filterWheelNotifier.setMoving(false);
      }
      operationsNotifier.completeOperation(OperationType.filterChange);
    }
  }
}
