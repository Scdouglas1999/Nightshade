part of '../device_service.dart';

extension _DeviceServiceConnections on DeviceService {
  /// Connect to a camera
  Future<void> _connectCamera(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(cameraStateProvider.notifier);

      // DEV-P1-7: skip the discovery precondition. We used to run a full
      // `discoverDevices(camera)` sweep and reject any unknown id with
      // "Camera not found: $id" — that made a reconnect of a known-good
      // device fail whenever a discovery transient (USB blip, backend
      // swap, ...) had blanked the cache. The backend's `connectDevice`
      // is the only honest source of truth for "is this actually
      // reachable?", so we keep the cheap structural format check here
      // and let the backend report the real outcome.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('camera', deviceId);
      }

      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.camera,
        deviceId,
      );
      notifier.setConnecting(deviceId, deviceName);

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
        } catch (e) {
          _safeLog(
            (l) => l.warning(
              'Cool-on-connect failed (profile lookup or cooling command): $e',
              source: 'DeviceService',
            ),
            'cool-on-connect',
          );
        }

        // IMG-P3-2: auto-detect manufacturer-recommended gain/offset from the
        // camera SDK and populate the active equipment profile when the user
        // has NOT explicitly set those values. We never overwrite an existing
        // profile value — the SDK recommendation is a starting point, not an
        // override of the user's deliberate choice.
        //
        // Failures here are non-fatal: connection has already succeeded, and
        // a missing recommendation is the honest "the SDK didn't tell us"
        // answer (most ASCOM/Alpaca/INDI cameras, and several native vendors,
        // don't expose this). The user can still set values manually.
        await _autoApplyRecommendedCameraSettings(deviceId, deviceName);

        // Start temperature polling (this will immediately poll and update)
        _temperaturePoller.start(deviceId);

        // Start heartbeat monitoring (10 second interval). Optional —
        // failures inside DeviceHeartbeatRouter.start are logged but
        // never thrown so connect cannot fail on a missing heartbeat.
        await _heartbeat.start(
          deviceType: DeviceType.camera,
          deviceId: deviceId,
          intervalMs: 10000,
        );
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Public re-entry point: re-query the SDK for the recommendation. Used by
  /// the equipment-screen "Auto-detect" button.
  ///
  /// Returns the raw [CameraRecommendedSettings] from the backend so the UI
  /// can present the values BEFORE deciding whether to apply them.
  Future<CameraRecommendedSettings> _queryRecommendedCameraSettings(
    String deviceId,
  ) {
    return _backend.cameraGetRecommendedSettings(deviceId);
  }

  /// Public re-entry point: apply a recommendation to the active profile,
  /// overwriting whatever was there. Used by the equipment-screen
  /// "Auto-detect" UI when the user explicitly confirms the apply.
  ///
  /// Returns true if at least one field was updated.
  Future<bool> _applyRecommendedCameraSettings(
    CameraRecommendedSettings rec,
  ) async {
    final activeProfile = _ref.read(activeEquipmentProfileProvider);
    if (activeProfile == null || activeProfile.id == null) {
      return false;
    }
    if (rec.unityGain == null && rec.defaultOffset == null) {
      return false;
    }

    final updated = activeProfile.copyWith(
      defaultGain: rec.unityGain ?? activeProfile.defaultGain,
      defaultOffset: rec.defaultOffset ?? activeProfile.defaultOffset,
    );
    final notifier = _ref.read(equipmentProfilesProvider.notifier);
    await notifier.updateProfile(updated);
    return true;
  }

  /// Set camera cooling
  Future<void> _setCameraCooling({
    required bool enabled,
    double? targetTemp,
  }) async {
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw const ConnectionException(
        message: 'Camera not connected',
        userMessage: 'The camera is not connected',
      );
    }

    // Use the connected device's ID from state, not the profile
    final deviceId = cameraState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw const ConnectionException(
        message: 'No camera device ID available',
        userMessage: 'The camera device is not available',
      );
    }

    await _backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: enabled,
      targetTemp: targetTemp,
    );
  }

  /// Gradually warm the camera by stepping the target temperature up
  /// until the cooler power drops near 0%, then disabling the cooler.
  ///
  /// Delegates to [CameraWarmupController] — see that class for the full
  /// algorithm and rationale.
  Future<void> _warmCamera({double ratePerMin = 2.0}) =>
      _warmupController.start(ratePerMin: ratePerMin);

  /// Cancel an in-progress gradual warm-up.
  /// The cooler remains in whatever state it was in at the time of cancellation.
  void _cancelWarmCamera() => _warmupController.cancel();

  /// Disconnect camera
  Future<void> _disconnectCamera() {
    return _trackInFlight(() async {
      // Cancel any warming in progress
      _cancelWarmCamera();
      // Stop temperature polling first
      _temperaturePoller.stop();

      final notifier = _ref.read(cameraStateProvider.notifier);
      final state = _ref.read(cameraStateProvider);

      // Audit DEV-P2-6: surface "nothing connected" as a typed precondition
      // instead of a silent no-op so the equipment screen's bulk-disconnect
      // sweep can distinguish "already disconnected" (skip cleanly) from
      // "real disconnect failure" (toast + log).
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('camera');
      }

      _markUserInitiatedDisconnect(deviceId);
      _rotatorVerifyGeneration++;

      try {
        // Best-effort cooler shutdown: ASCOM/INDI driver-side coolers keep
        // running after the client disconnects, so an intentional
        // disconnect with the cooler at setpoint would silently keep
        // pulling power (and surprise the user packing up the rig).
        // Fail-soft — an unreachable driver must not block the disconnect.
        if (state.isCooling) {
          try {
            await _backend.cameraSetCooling(deviceId: deviceId, enabled: false);
            _safeLog(
              (l) => l.info(
                'Cooler disabled as part of camera disconnect',
                source: 'DeviceService',
              ),
              'disconnect-cooler-off',
            );
          } catch (e) {
            _safeLog(
              (l) => l.warning(
                'Could not disable cooler during disconnect: $e',
                source: 'DeviceService',
              ),
              'disconnect-cooler-off',
            );
          }
        }

        // Stop heartbeat monitoring. DeviceHeartbeatRouter.stop is
        // fail-soft: it logs and swallows so the disconnect proceeds
        // even if the driver is already gone.
        await _heartbeat.stop(
          deviceType: DeviceType.camera,
          deviceId: deviceId,
        );

        // Disconnect device
        await _backend.disconnectDevice(DeviceType.camera, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a mount
  Future<void> _connectMount(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(mountStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('mount', deviceId);
      }

      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.mount,
        deviceId,
      );
      notifier.setConnecting(deviceId, deviceName);

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
          _safeLog(
            (l) => l.warning(
              'Failed to get initial mount status for ($deviceId): $e',
              source: 'DeviceService',
            ),
            'mount-initial-status-fail',
          );
        }

        // Start heartbeat monitoring (10 second interval) for critical
        // device. Fail-soft inside DeviceHeartbeatRouter.start so a
        // missing heartbeat cannot abort connect.
        await _heartbeat.start(
          deviceType: DeviceType.mount,
          deviceId: deviceId,
          intervalMs: 10000,
        );
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect mount
  Future<void> _disconnectMount() {
    return _trackInFlight(() async {
      final notifier = _ref.read(mountStateProvider.notifier);
      final state = _ref.read(mountStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('mount');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        // Stop heartbeat monitoring; fail-soft inside the router so the
        // matching disconnectDevice call below proceeds regardless.
        await _heartbeat.stop(deviceType: DeviceType.mount, deviceId: deviceId);

        await _backend.disconnectDevice(DeviceType.mount, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a focuser
  Future<void> _connectFocuser(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(focuserStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('focuser', deviceId);
      }

      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.focuser,
        deviceId,
      );
      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.focuser, deviceId);

        // Get actual focuser status from the backend (now typed FocuserStatus)
        final status = await _backend.getFocuserStatus(deviceId);

        notifier.setConnected(
          maxPosition: status.maxPosition,
          stepSize: status.stepSize,
          isAbsolute: status.isAbsolute,
          hasTemperature: status.hasTemperature,
        );
        notifier.updatePosition(status.position);
        notifier.setMoving(status.moving);
        if (status.temperature != null) {
          notifier.updateTemperature(status.temperature!);
        }
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect focuser
  Future<void> _disconnectFocuser() {
    return _trackInFlight(() async {
      final notifier = _ref.read(focuserStateProvider.notifier);
      final state = _ref.read(focuserStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('focuser');
      }

      _markUserInitiatedDisconnect(deviceId);
      _focuserVerifyGeneration++;

      try {
        await _backend.disconnectDevice(DeviceType.focuser, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a filter wheel
  Future<void> _connectFilterWheel(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(filterWheelStateProvider.notifier);
      final logger = _ref.read(loggingServiceProvider);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('filter wheel', deviceId);
      }

      // Derive a friendly name without running discovery.
      // Discovery opens/closes hardware (e.g. ZWO EFW via native SDK) which
      // can interfere with subsequent position reads.  The device manager will
      // register the full DeviceInfo during api_connect_device anyway.
      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.filterWheel,
        deviceId,
      );

      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.filterWheel, deviceId);

        // Give the filter wheel firmware time to synchronise the actual
        // encoder position after the USB/COM connection is established.
        // Some SDKs (ZWO EFW, ASCOM wrappers) report position 0 or -1
        // immediately after opening before the firmware has read the encoder.
        // Poll up to 5 times over ~2.5 s to get a stable reading.
        FilterWheelStatus status;
        int pollAttempts = 0;
        const maxPolls = 5;
        const pollDelay = Duration(milliseconds: 500);

        status = await _backend.getFilterWheelStatus(deviceId);
        logger.debug(
          'Filter wheel poll #0: position=${status.position}, '
          'moving=${status.moving}',
          source: 'DeviceService',
        );

        // Keep polling while position is -1 (moving/initializing)
        while (status.position < 0 && pollAttempts < maxPolls) {
          pollAttempts++;
          await Future.delayed(pollDelay);
          status = await _backend.getFilterWheelStatus(deviceId);
          logger.debug(
            'Filter wheel poll #$pollAttempts: position=${status.position}, '
            'moving=${status.moving}',
            source: 'DeviceService',
          );
        }

        logger.debug(
          'Filter wheel final status: ${status.filterNames.length} filter '
          'names=${status.filterNames}, position=${status.position}',
          source: 'DeviceService',
        );

        notifier.setConnected(filterNames: status.filterNames);
        notifier.setDeviceName(deviceName);
        notifier.updatePosition(status.position);
        notifier.setMoving(status.moving);

        // Seed the per-wheel "last applied offset" baseline with the CURRENT
        // filter's configured offset. The map entry is cleared on disconnect,
        // so without this seed the first filter change after a reconnect
        // computes its focuser delta against 0 — double-applying an offset
        // that is already physically embodied in the focuser position (the
        // rig was focused with the current filter in place).
        if (status.position >= 0 &&
            status.position < status.filterNames.length) {
          _lastAppliedFilterOffsetByWheel[deviceId] =
              _resolveConfiguredFilterOffset(
                status.filterNames[status.position],
              );
        }

        // After connection, sync profile/session filter names to the native
        // driver so user-defined names (Ha, OIII, SII, etc.) are used in
        // sequences and UI instead of generic "Filter 1", "Filter 2".
        await _syncFilterNamesToDriver(deviceId, status.filterNames);
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect filter wheel
  Future<void> _disconnectFilterWheel() {
    return _trackInFlight(() async {
      final notifier = _ref.read(filterWheelStateProvider.notifier);
      final state = _ref.read(filterWheelStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('filter wheel');
      }

      _markUserInitiatedDisconnect(deviceId);
      _filterWheelVerifyGeneration++;
      _lastAppliedFilterOffsetByWheel.remove(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.filterWheel, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a guider
  Future<void> _connectGuider(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(guiderStateProvider.notifier);
      // PHD2 recognition is centralized in `utils/device_id.dart` so the
      // several representations a profile may have stored ('phd2',
      // 'phd2_guider', 'phd2:host:port', 'phd2://…') are handled identically
      // everywhere.
      final isPhd2 = isPhd2DeviceId(deviceId);

      // Special handling for PHD2 guider - uses different connection method
      if (isPhd2) {
        notifier.setConnecting(kPhd2CanonicalId, 'PHD2 Guiding');
        try {
          final settings = await _ref.read(appSettingsProvider.future);
          // Auto-launch PHD2 on the imaging host when the socket is local.
          // Remote companions (NetworkBackend) must not spawn processes here —
          // they delegate launch to the desktop via POST /api/phd2/connect.
          // For remote PHD2 hosts (host != localhost/127.0.0.1) we never spawn.
          final connectHost = resolvePhd2ConnectHost(settings.phd2Host);
          if (_backend is! NetworkBackend &&
              _phd2Launcher.isLocalHost(settings.phd2Host)) {
            await _phd2Launcher.ensureRunning(
              executablePath: settings.phd2Path,
              host: connectHost,
              port: settings.phd2Port,
            );
          }
          await _backend.phd2Connect(
            host: connectHost,
            port: settings.phd2Port,
          );
          await pollPhd2Connected(_backend);
          notifier.setConnected();
        } catch (e) {
          notifier.setDisconnected();
          try {
            await _backend.phd2Disconnect();
          } catch (_) {
            // Best-effort cleanup after a failed connect attempt.
          }
          rethrow;
        }
        return;
      }

      // Standard guider connection (ASCOM/Alpaca/INDI).
      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('guider', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.guider, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.guider, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect guider
  Future<void> _disconnectGuider() {
    return _trackInFlight(() async {
      final notifier = _ref.read(guiderStateProvider.notifier);
      final state = _ref.read(guiderStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('guider');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        // Special handling for PHD2 (recognition centralized in device_id.dart)
        if (isPhd2DeviceId(deviceId)) {
          await _backend.phd2Disconnect();
        } else {
          await _backend.disconnectDevice(DeviceType.guider, deviceId);
        }
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a dome
  Future<void> _connectDome(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(domeStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('dome', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.dome, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.dome, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect dome
  Future<void> _disconnectDome() {
    return _trackInFlight(() async {
      final notifier = _ref.read(domeStateProvider.notifier);
      final state = _ref.read(domeStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('dome');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.dome, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a weather device
  Future<void> _connectWeather(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(weatherStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('weather station', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.weather, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.weather, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect weather device
  Future<void> _disconnectWeather() {
    return _trackInFlight(() async {
      final notifier = _ref.read(weatherStateProvider.notifier);
      final state = _ref.read(weatherStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('weather station');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.weather, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a safety monitor
  Future<void> _connectSafetyMonitor(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('safety monitor', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.safetyMonitor, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.safetyMonitor, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect safety monitor
  Future<void> _disconnectSafetyMonitor() {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);
      final state = _ref.read(safetyMonitorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('safety monitor');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.safetyMonitor, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a switch device.
  ///
  /// DEV-P2-1: switch is a first-class device type with its own state
  /// provider and equipment-profile column. The Rust bridge exposes
  /// per-channel get/set under `api_switch_*`; per-channel UI is future
  /// work (see [SwitchState] docs) but the connect/disconnect path is
  /// real and must succeed before the user can flip any channels.
  Future<void> _connectSwitch(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('switch', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.switch_, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.switch_, deviceId);
        notifier.setConnected();
        // Best-effort: fetch the channel snapshot so the card can render
        // per-channel toggles. Only attempted when the active backend is
        // the local FfiBackend (NetworkBackend would need a separate REST
        // endpoint that does not exist yet — tracked as follow-up).
        // Failures here MUST NOT abort the connect (CLAUDE.md "errors
        // are a feature" — surface as a warning but keep the device
        // marked connected).
        await _refreshSwitchChannels();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect switch device.
  Future<void> _disconnectSwitch() {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);
      final state = _ref.read(switchStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('switch');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.switch_, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Refresh the cached channel snapshot for the currently-connected
  /// switch device. Delegates to [SwitchChannelService.refreshChannels];
  /// see that class for the full contract (per-channel fallbacks,
  /// backend gating, ErrorService surfacing).
  Future<void> _refreshSwitchChannels() => _switchChannels.refreshChannels();

  /// Toggle a single switch channel on or off. Delegates to
  /// [SwitchChannelService.setChannel] inside [_trackInFlight] so the
  /// per-switch write participates in the facade's quiesce accounting.
  /// See [SwitchChannelService.setChannel] for thrown exceptions and
  /// error-routing semantics.
  Future<void> _setSwitchChannel(int channelIndex, bool on) {
    return _trackInFlight(() => _switchChannels.setChannel(channelIndex, on));
  }

  /// Connect to a rotator
  Future<void> _connectRotator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(rotatorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('rotator', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.rotator, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.rotator, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect rotator
  Future<void> _disconnectRotator() {
    return _trackInFlight(() async {
      final notifier = _ref.read(rotatorStateProvider.notifier);
      final state = _ref.read(rotatorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('rotator');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.rotator, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a cover calibrator (flat panel)
  Future<void> _connectCoverCalibrator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(coverCalibratorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('cover calibrator', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.coverCalibrator, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.coverCalibrator, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect cover calibrator
  Future<void> _disconnectCoverCalibrator() {
    return _trackInFlight(() async {
      final notifier = _ref.read(coverCalibratorStateProvider.notifier);
      final state = _ref.read(coverCalibratorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('cover calibrator');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.coverCalibrator, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }
}
