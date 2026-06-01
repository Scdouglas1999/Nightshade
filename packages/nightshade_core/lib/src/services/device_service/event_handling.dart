part of '../device_service.dart';

extension _DeviceServiceEventHandling on DeviceService {
  void _markUserInitiatedDisconnect(String deviceId) =>
      _reconnectCoordinator.markUserInitiatedDisconnect(deviceId);

  /// Resolve a display name without running discovery. Falls back to
  /// [getConnectedDevices] when the backend already knows this device
  /// (DV-P0-4).
  Future<String> _resolveDeviceDisplayName(
    DeviceType type,
    String deviceId,
  ) async {
    try {
      final connected = await _backend.getConnectedDevices();
      for (final device in connected) {
        if (device.id == deviceId && device.deviceType == type) {
          if (device.name.isNotEmpty) {
            return device.name;
          }
        }
      }
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'getConnectedDevices lookup failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'resolve-device-name',
      );
    }
    // Before connect completes the backend's connected list is empty, so fall
    // back to the friendly model name captured during startup discovery (e.g.
    // "ZWO ASI1600MM-Cool"). This is the same source the rest of the UI uses,
    // so a profile connect-all — which only knows the persisted device id —
    // still shows the model name on the card instead of the raw id.
    final discoveryName = _discoveryNameFromId(deviceId);
    if (discoveryName != null) {
      return discoveryName;
    }
    return _friendlyNameFromId(deviceId);
  }

  /// The friendly model name for [deviceId] from the last device-discovery
  /// scan, or `null` when discovery hasn't seen this id (or only knows it by
  /// its raw id). Read synchronously from [unifiedDiscoveryProvider]'s cached
  /// results — no scan is triggered.
  String? _discoveryNameFromId(String deviceId) {
    try {
      final raw = _ref.read(unifiedDiscoveryProvider).rawDevices;
      for (final device in raw) {
        if (device.id == deviceId &&
            device.name.isNotEmpty &&
            device.name != deviceId) {
          return device.name;
        }
      }
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'discovery name lookup failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'discovery-device-name',
      );
    }
    return null;
  }

  void _handleEquipmentEvent(NightshadeEvent event) {
    final data = event.data;
    switch (event.eventType) {
      // Connection events
      case 'Connecting':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        if (deviceType != null && deviceId != null) {
          _applyDeviceConnecting(deviceType, deviceId);
        }
        break;

      case 'Connected':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        if (deviceType != null && deviceId != null) {
          _applyDeviceConnected(deviceType, deviceId);
        }
        break;

      case 'Disconnected':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        _handleDeviceDisconnected(deviceType, deviceId);
        break;

      // DEV-P0-5: surface driver errors published from Rust via
      // report_error / connect_device_internal / heartbeat. Previously
      // dropped on the floor — the user never saw the actual driver
      // message. Per CLAUDE.md "errors are a feature", we route the
      // payload through the structured errorService (which also pushes
      // to UI notifications) AND set the matching device state to
      // error so the equipment card subtitle renders it.
      case 'Error':
        _handleDeviceError(
          deviceType: data['device_type'] as String?,
          deviceId: data['device_id'] as String?,
          message: data['message'] as String?,
          errorCode:
              data['error_code']?.toString() ?? data['errorCode']?.toString(),
          severity: event.severity,
        );
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
          _ref
              .read(mountStateProvider.notifier)
              .setSlewing(data['isSlewing'] as bool);
        }
        if (data['isTracking'] != null) {
          _ref
              .read(mountStateProvider.notifier)
              .setTracking(data['isTracking'] as bool);
        }
        if (data['isParked'] != null) {
          _ref
              .read(mountStateProvider.notifier)
              .setParked(data['isParked'] as bool);
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
          _ref
              .read(mountStateProvider.notifier)
              .updatePosition(ra, dec, 0.0, 0.0);
        }
        // Smart notification - only show if not on imaging/planetarium screens
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
              message: 'Slew completed',
              relevantScreens: [
                AppScreen.imaging,
                AppScreen.planetarium,
                AppScreen.sequencer
              ],
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
          _ref
              .read(focuserStateProvider.notifier)
              .setMoving(data['isMoving'] as bool);
        }
        if (data['temperature'] != null) {
          _ref
              .read(focuserStateProvider.notifier)
              .updateTemperature((data['temperature'] as num).toDouble());
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
          _ref
              .read(focuserStateProvider.notifier)
              .updateTemperature(temperature);
        }
        break;

      // Legacy filter wheel position event (keep for backward compatibility)
      case 'FilterWheelPositionChanged':
        final pos = data['position'] as int;
        _ref.read(filterWheelStateProvider.notifier).updatePosition(pos);
        if (data['isMoving'] != null) {
          _ref
              .read(filterWheelStateProvider.notifier)
              .setMoving(data['isMoving'] as bool);
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

      // ---------------------------------------------------------------
      // DEV-P3-2: Heartbeat-health routing.
      //
      // The Rust heartbeat monitor publishes status changes via the
      // equipment EventBus. We forward them into the dedicated
      // `deviceHeartbeatHealthProvider` so per-device cards can render
      // a colored indicator without each card subscribing to the
      // entire equipment event stream itself. Connection-state
      // notifiers (DEV-P0-1) and the driver-error handler (DEV-P0-5)
      // are intentionally untouched here — heartbeat health is a
      // separate gradient layered on top of connection state.
      //
      // Each case wraps the dispatch in a try/catch because the
      // notifier provider may be unavailable mid-disposal (e.g. during
      // a backend swap) and we never want a heartbeat-routing failure
      // to mask the higher-priority connection events that share this
      // method.
      // ---------------------------------------------------------------
      case 'HeartbeatStarted':
        _heartbeat.onHeartbeatStarted(data['device_id'] as String?);
        break;

      case 'HeartbeatStatusChanged':
        final hbStatus = data['status'] as String?;
        _heartbeat.onStatusChanged(
          deviceId: data['device_id'] as String?,
          status: hbStatus,
          consecutiveFailures: (data['consecutive_failures'] as num?)?.toInt(),
          lastRttMs:
              DeviceHeartbeatRouter.coerceIntFromBigInt(data['last_rtt_ms']),
        );
        // Polish #5: the heartbeat-lost path no longer emits a standalone
        // `EquipmentEvent::Disconnected` (it was deduped away to stop a
        // third, redundant disconnect toast). But that event was the ONLY
        // trigger for the load-bearing disconnect side effects in
        // `_handleDeviceDisconnected`: clearing the per-device heartbeat
        // health dot AND honoring the user's per-type auto-reconnect
        // preference. So the canonical `HeartbeatStatusChanged{Disconnected}`
        // status now drives those side effects directly. This is the state
        // transition + reconnect, NOT a toast — the user-facing notification
        // still comes solely from the accompanying `Error` event, so the
        // dedupe goal (one toast) is preserved.
        if (hbStatus != null && hbStatus.toLowerCase() == 'disconnected') {
          _handleDeviceDisconnected(
            data['device_type'] as String?,
            data['device_id'] as String?,
          );
        }
        break;

      case 'HeartbeatReconnecting':
        _heartbeat.onReconnecting(
          deviceId: data['device_id'] as String?,
          attempt: (data['attempt'] as num?)?.toInt(),
          maxAttempts: (data['max_attempts'] as num?)?.toInt(),
        );
        break;

      case 'HeartbeatReconnected':
        _heartbeat.onReconnected(
          deviceId: data['device_id'] as String?,
          afterAttempts: (data['after_attempts'] as num?)?.toInt(),
        );
        break;

      case 'HeartbeatStopped':
        // Heartbeat monitoring intentionally stopped (e.g. user
        // disconnected the device through the UI). Clear the entry so
        // the indicator returns to the gray "unknown" baseline. The
        // matching `Disconnected` event handler also clears, but the
        // events are emitted independently and either may arrive
        // first.
        final stoppedId = data['device_id'] as String?;
        if (stoppedId != null && stoppedId.isNotEmpty) {
          _heartbeat.clearDevice(stoppedId);
        }
        break;
    }
  }

  // Heartbeat event routing + start/stop helpers live in
  // [DeviceHeartbeatRouter] (`_heartbeat`). DeviceService just hands
  // event payloads to it from `_handleEquipmentEvent` and calls
  // `_heartbeat.start` / `_heartbeat.stop` from connect/disconnect
  // flows; see `device_heartbeat_router.dart`.

  /// Handle device connection event from the native EventBus.
  void _applyDeviceConnected(String deviceType, String deviceId) {
    // Resolve a friendly model name so the authoritative backend 'Connected'
    // event does not overwrite the device name with the raw device id.
    // Prefer the startup-discovery model name (e.g. "ZWO ASI1600MM-Cool");
    // when discovery hasn't seen the device, fall back to the id-pattern
    // formatter rather than the bare id.
    final resolvedName =
        _discoveryNameFromId(deviceId) ?? _friendlyNameFromId(deviceId);
    switch (deviceType.toLowerCase()) {
      case 'camera':
        final notifier = _ref.read(cameraStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'mount':
        final notifier = _ref.read(mountStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'focuser':
        final notifier = _ref.read(focuserStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'filterwheel':
      case 'filter wheel':
        final notifier = _ref.read(filterWheelStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'guider':
        final notifier = _ref.read(guiderStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'rotator':
        final notifier = _ref.read(rotatorStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'dome':
        final notifier = _ref.read(domeStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'weather':
        final notifier = _ref.read(weatherStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'safetymonitor':
      case 'safety monitor':
        final notifier = _ref.read(safetyMonitorStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider.
        final notifier = _ref.read(switchStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        final notifier = _ref.read(coverCalibratorStateProvider.notifier);
        notifier.setConnecting(deviceId, resolvedName);
        notifier.setConnected();
        break;
    }

    // Drive sequence-resume off this authoritative connected event so a
    // reconnect from ANY source — including the Rust reconnection loop after
    // the Dart coordinator has exhausted its own ~35s budget — resumes a
    // paused sequence. Previously resume only fired inside the coordinator's
    // own retry success, so a later out-of-band reconnect left the rig
    // connected but idle until morning.
    final lower = deviceType.toLowerCase();
    if (lower == 'camera' || lower == 'mount') {
      unawaited(_reconnectCoordinator.onAuthoritativeDeviceConnected(lower));
    }
  }

  void _applyDeviceConnecting(String deviceType, String deviceId) {
    // See _applyDeviceConnected: prefer the discovery model name over the raw
    // id so the "Connecting…" label and card show the friendly name.
    final resolvedName =
        _discoveryNameFromId(deviceId) ?? _friendlyNameFromId(deviceId);
    switch (deviceType.toLowerCase()) {
      case 'camera':
        _ref
            .read(cameraStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'mount':
        _ref
            .read(mountStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'focuser':
        _ref
            .read(focuserStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'filterwheel':
      case 'filter wheel':
        _ref
            .read(filterWheelStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'guider':
        _ref
            .read(guiderStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'rotator':
        _ref
            .read(rotatorStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'dome':
        _ref
            .read(domeStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'weather':
        _ref
            .read(weatherStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'safetymonitor':
      case 'safety monitor':
        _ref
            .read(safetyMonitorStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider.
        _ref
            .read(switchStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        _ref
            .read(coverCalibratorStateProvider.notifier)
            .setConnecting(deviceId, resolvedName);
        break;
    }
  }

  /// Handle device disconnection event
  void _handleDeviceDisconnected(String? deviceType, String? deviceId) {
    if (deviceType == null || deviceId == null) return;

    // DEV-P3-2: clear the heartbeat health entry so the per-card
    // indicator falls back to "unknown" (gray dot) rather than getting
    // stuck on the last-known value. Done unconditionally up-front so
    // a clear failure here cannot block the existing connection-state
    // teardown below (DEV-P0-1 / DEV-P0-5 paths).
    _heartbeat.clearDevice(deviceId);

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
    final isCriticalDevice = deviceType.toLowerCase() == 'camera' ||
        deviceType.toLowerCase() == 'mount';
    if (isCriticalDevice) {
      _handleCriticalDeviceDisconnect(deviceType, deviceId);
    }

    // Update connection state based on device type
    switch (deviceType.toLowerCase()) {
      case 'camera':
        // DEV-P1-4: only tear down camera-scoped polling state if the
        // disconnect event is for the camera we're actually tracking.
        // A stale event for a previously-disconnected camera must not
        // kill polling/IDs for the CURRENT camera. We still flip the
        // notifier and schedule reconnect — those operations are
        // device-id aware via _attemptReconnect/setDisconnected.
        final trackedCameraId = _temperaturePoller.connectedCameraId;
        if (trackedCameraId != null && trackedCameraId == deviceId) {
          _temperaturePoller.stop();
        } else if (trackedCameraId != null) {
          _safeLog(
            (logger) => logger.warning(
              'Ignoring stale camera Disconnected for $deviceId; '
              'currently-tracked camera is $trackedCameraId',
              source: 'DeviceService',
            ),
            'camera-disconnect-guard',
          );
        }
        _ref.read(cameraStateProvider.notifier).setDisconnected();
        // Attempt auto-reconnection for camera
        unawaited(_attemptReconnect(DeviceType.camera, deviceId));
        break;

      case 'mount':
        _ref.read(mountStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.mount, deviceId));
        break;

      case 'focuser':
        _focuserVerifyGeneration++;
        _ref.read(focuserStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.focuser, deviceId));
        break;

      case 'filterwheel':
      case 'filter wheel':
        _filterWheelVerifyGeneration++;
        _lastAppliedFilterOffsetByWheel.remove(deviceId);
        _ref.read(filterWheelStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.filterWheel, deviceId));
        break;

      case 'guider':
        _ref.read(guiderStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.guider, deviceId));
        break;

      case 'rotator':
        _rotatorVerifyGeneration++;
        _ref.read(rotatorStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.rotator, deviceId));
        break;

      case 'dome':
        _ref.read(domeStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.dome, deviceId));
        break;

      case 'weather':
        _ref.read(weatherStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.weather, deviceId));
        break;

      case 'safetymonitor':
      case 'safety monitor':
        _ref.read(safetyMonitorStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.safetyMonitor, deviceId));
        break;

      // DEV-P0-1: cover calibrator + switch cases. Previously these
      // device types would never propagate a Disconnected event to the
      // UI — cards stayed "connected" until app restart. Cover
      // calibrator has a state provider; switch does not yet (DEV-P2-1)
      // so we log loudly and surface a UI notification so the user
      // knows the device is gone.
      case 'covercalibrator':
      case 'cover calibrator':
        _ref.read(coverCalibratorStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.coverCalibrator, deviceId));
        break;

      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider,
        // so disconnects route through `setDisconnected` and the
        // standard auto-reconnect path — same shape as safety monitor.
        _ref.read(switchStateProvider.notifier).setDisconnected();
        unawaited(_attemptReconnect(DeviceType.switch_, deviceId));
        break;
    }
  }

  /// DEV-P0-5: Handle a driver/heartbeat error event published from Rust.
  ///
  /// Three responsibilities:
  ///   1. Always log (driver, device id, message, error code if any).
  ///   2. Update the matching device-type StateNotifier with the error
  ///      so equipment-card subtitles render it.
  ///   3. Surface to the user via the structured errorService (which
  ///      also pushes to the UI notification stream).
  ///
  /// Fail-loud: this method MUST NOT swallow the payload. Individual
  /// downstream emissions are wrapped so one channel failing (e.g.
  /// notification provider mid-disposal) cannot mask the others.
  void _handleDeviceError({
    required String? deviceType,
    required String? deviceId,
    required String? message,
    required String? errorCode,
    required EventSeverity severity,
  }) {
    // Compose a human-readable error string. Even if device_type or
    // device_id are missing we still want the message visible.
    final composedMessage = StringBuffer();
    if (message != null && message.isNotEmpty) {
      composedMessage.write(message);
    } else {
      composedMessage.write('Driver reported an error (no message provided)');
    }
    if (errorCode != null && errorCode.isNotEmpty) {
      composedMessage.write(' [code: $errorCode]');
    }
    final fullMessage = composedMessage.toString();

    // 1. Log loudly with full context.
    _safeLog(
      (logger) => logger.error(
        'Driver error: type=${deviceType ?? "unknown"} '
        'id=${deviceId ?? "unknown"} code=${errorCode ?? "none"} :: '
        '$fullMessage',
        source: 'DeviceService',
      ),
      'device-error-log',
    );

    // 2. Update the matching device-type state notifier so equipment
    //    cards display the error in their subtitle.
    final exception =
        Exception(fullMessage); // setError expects Object — wrap once.
    final typeKey = (deviceType ?? '').toLowerCase();
    switch (typeKey) {
      case 'camera':
        _ref.read(cameraStateProvider.notifier).setError(exception);
        break;
      case 'mount':
        _ref.read(mountStateProvider.notifier).setError(exception);
        break;
      case 'focuser':
        _ref.read(focuserStateProvider.notifier).setError(exception);
        break;
      case 'filterwheel':
      case 'filter wheel':
        _ref.read(filterWheelStateProvider.notifier).setError(exception);
        break;
      case 'guider':
        _ref.read(guiderStateProvider.notifier).setError(exception);
        break;
      case 'rotator':
        _ref.read(rotatorStateProvider.notifier).setError(exception);
        break;
      case 'dome':
        _ref.read(domeStateProvider.notifier).setError(exception);
        break;
      case 'weather':
        _ref.read(weatherStateProvider.notifier).setError(exception);
        break;
      case 'safetymonitor':
      case 'safety monitor':
        _ref.read(safetyMonitorStateProvider.notifier).setError(exception);
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        _ref.read(coverCalibratorStateProvider.notifier).setError(exception);
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider,
        // so driver errors surface in the equipment card subtitle.
        _ref.read(switchStateProvider.notifier).setError(exception);
        break;
      default:
        _safeLog(
          (logger) => logger.warning(
            'Error event for unknown device type "$deviceType"; '
            'no state notifier updated. Message: $fullMessage',
            source: 'DeviceService',
          ),
          'device-error-unknown-type',
        );
    }

    // 3. Surface via the structured errorService. This routes through
    //    the error history (visible in diagnostics) AND pushes a UI
    //    notification toast (errorService internally calls
    //    uiNotificationProvider for error/critical severities).
    try {
      final errSvc = _ref.read(errorServiceProvider);
      final mappedSeverity = switch (severity) {
        EventSeverity.info => ErrorSeverity.info,
        EventSeverity.warning => ErrorSeverity.warning,
        EventSeverity.error => ErrorSeverity.error,
        EventSeverity.critical => ErrorSeverity.critical,
      };
      // Use deviceType for the structured entry's title. If absent we
      // still want the entry recorded, so default to "Device".
      errSvc.logDeviceError(
        operation: 'driver_error',
        message: fullMessage,
        deviceType: deviceType ?? 'Device',
        deviceId: deviceId,
        severity: mappedSeverity,
        context: errorCode == null ? null : {'error_code': errorCode},
      );
    } on Object catch (errSvcErr) {
      _safeLog(
        (logger) => logger.warning(
          'errorService emission for driver error failed: $errSvcErr '
          '(original: $fullMessage)',
          source: 'DeviceService',
        ),
        'device-error-errorservice',
      );
      // Fallback: try uiNotificationProvider directly so the user
      // still sees the message even if errorService is unavailable.
      try {
        _ref.read(uiNotificationProvider.notifier).showError(
              fullMessage,
              title: '${deviceType ?? "Device"} Error',
              duration: const Duration(seconds: 12),
            );
      } on Object catch (uiErr) {
        _safeLog(
          (logger) => logger.warning(
            'UI notification fallback also failed: $uiErr '
            '(original: $fullMessage)',
            source: 'DeviceService',
          ),
          'device-error-ui-fallback',
        );
      }
    }
  }

  /// Schedule a reconnection attempt via the [DeviceReconnectCoordinator].
  Future<void> _attemptReconnect(DeviceType type, String deviceId) =>
      _reconnectCoordinator.attemptReconnect(type, deviceId);

  Future<void> _handleCriticalDeviceDisconnect(
          String deviceType, String deviceId) =>
      _reconnectCoordinator.handleCriticalDeviceDisconnect(
          deviceType, deviceId);

  void _handleSequencerEvent(NightshadeEvent event) {
    applySequencerEventToSequenceProviders(_ref.read, event);
  }
}
