part of '../device_service.dart';

extension _DeviceServiceConnections on DeviceService {
  /// Connect to a camera
  Future<void> _connectCamera(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(cameraStateProvider.notifier);

      // Skip the discovery precondition. We used to run a full
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
      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.camera, deviceId);

      notifier.setConnecting(deviceId, deviceName);

      try {
        // Connect via native bridge
        await _backend.connectDevice(DeviceType.camera, deviceId);

        notifier.setConnected();

        // Apply active profile's cooling target temperature if available
        // and auto-start cooling if coolOnConnect is enabled
        try {
          final activeProfile = _ref.read(activeEquipmentProfileProvider);
          if (activeProfile?.defaultGain != null) {
            try {
              await _backend.cameraSetGain(
                deviceId,
                activeProfile!.defaultGain!,
              );
            } catch (e) {
              _safeLog(
                (l) => l.warning(
                  'Profile gain could not be applied on connect: $e',
                  source: 'DeviceService',
                ),
                'profile-gain-on-connect',
              );
            }
          }
          if (activeProfile?.defaultOffset != null) {
            try {
              await _backend.cameraSetOffset(
                deviceId,
                activeProfile!.defaultOffset!,
              );
            } catch (e) {
              _safeLog(
                (l) => l.warning(
                  'Profile offset could not be applied on connect: $e',
                  source: 'DeviceService',
                ),
                'profile-offset-on-connect',
              );
            }
          }
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

        // Auto-detect manufacturer-recommended gain/offset from the
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
    // Defense-in-depth: reject a non-finite setpoint before it reaches the
    // driver. The GUI dialog already validates its text field, but non-UI
    // callers (headless API, sequencer instructions, tests) route through here
    // too, and a NaN/±∞ setpoint would either be silently coerced by the
    // driver or corrupt the cooler control loop. A null target is the valid
    // "disable cooling" / "keep current setpoint" case and is left untouched.
    if (targetTemp != null && !targetTemp.isFinite) {
      throw ArgumentError.value(
        targetTemp,
        'targetTemp',
        'Cooling target temperature must be a finite value',
      );
    }

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

      // Audit surface "nothing connected" as a typed precondition
      // instead of a silent no-op so the equipment screen's bulk-disconnect
      // sweep can distinguish "already disconnected" (skip cleanly) from
      // "real disconnect failure" (toast + log).
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('camera');
      }

      _markUserInitiatedDisconnect(deviceId);
      try {
        // Best-effort cooler shutdown: ASCOM/INDI driver-side coolers keep
        // running after the client disconnects, so an intentional
        // disconnect with the cooler at setpoint would silently keep
        // pulling power (and surprise the user packing up the rig).
        // Fail-soft — an unreachable driver must not block the disconnect.
        if (state.isCooling) {
          try {
            await _backend.cameraSetCooling(deviceId: deviceId, enabled: false);
            notifier.setCooling(false);
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
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        _temperaturePoller.start(deviceId);
        await _heartbeat.start(
          deviceType: DeviceType.camera,
          deviceId: deviceId,
          intervalMs: 10000,
        );
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Connect to a mount
  Future<void> _connectMount(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(mountStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('mount', deviceId);
      }

      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.mount,
        deviceId,
      );
      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.mount, deviceId);

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

      // Audit see [disconnectCamera] for the rationale.
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
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        await _heartbeat.start(
          deviceType: DeviceType.mount,
          deviceId: deviceId,
          intervalMs: 10000,
        );
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Connect to a focuser
  Future<void> _connectFocuser(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(focuserStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('focuser', deviceId);
      }

      final deviceName = await _resolveDeviceDisplayName(
        DeviceType.focuser,
        deviceId,
      );
      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.focuser, deviceId);

      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.focuser, deviceId);

        // Get actual focuser status from the backend (now typed FocuserStatus).
        // Some drivers (notably INDI) stream device properties asynchronously
        // AFTER the connection is established, so an immediate status read can
        // race the property stream and throw ("Position not available") even
        // though the focuser is connected and movable. The connection itself is
        // up — retry the initial snapshot for a couple of seconds before giving
        // up, mirroring the filter-wheel encoder-settle poll.
        FocuserStatus? status;
        Object? lastStatusError;
        for (var attempt = 0; attempt < 5; attempt++) {
          try {
            status = await _backend.getFocuserStatus(deviceId);
            break;
          } catch (e) {
            lastStatusError = e;
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        if (status == null) {
          throw StateError(
            'Focuser connected but did not report status in time '
            '(driver property stream too slow): $lastStatusError',
          );
        }

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
        await _heartbeat.start(
          deviceType: DeviceType.focuser,
          deviceId: deviceId,
          intervalMs: 10000,
        );
      } catch (e) {
        try {
          await _backend.disconnectDevice(DeviceType.focuser, deviceId);
        } catch (_) {
          // The connect itself may have failed before the backend registered
          // the device. Preserve the original, more useful failure.
        }
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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('focuser');
      }

      _markUserInitiatedDisconnect(deviceId);
      _focuserVerifyGeneration++;

      try {
        await _heartbeat.stop(
          deviceType: DeviceType.focuser,
          deviceId: deviceId,
        );
        await _backend.disconnectDevice(DeviceType.focuser, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        await _heartbeat.start(
          deviceType: DeviceType.focuser,
          deviceId: deviceId,
          intervalMs: 10000,
        );
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Connect to a filter wheel
  Future<void> _connectFilterWheel(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(filterWheelStateProvider.notifier);
      final logger = _ref.read(loggingServiceProvider);

      // Format check only; backend is the source of truth for
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

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.filterWheel, deviceId);

      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.filterWheel, deviceId);

        // Give the filter wheel firmware time to synchronise the actual
        // encoder position after the USB/COM connection is established.
        // Some SDKs (ZWO EFW, ASCOM wrappers) report position 0 or -1
        // immediately after opening before the firmware has read the encoder.
        // Allow up to 10 s for a stable reading. Empirical testing on a ZWO
        // EFW after an unclean process restart showed that the SDK can remain
        // at -1 for more than 3 s even though the wheel is healthy; rejecting
        // it that early caused a noisy disconnect/reconnect cycle at startup.
        FilterWheelStatus status;
        int pollAttempts = 0;
        const maxPolls = 20;
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
        if (status.position < 0) {
          throw StateError(
            'Filter wheel connected but did not report a valid position '
            'after ${maxPolls + 1} status reads',
          );
        }

        notifier.setConnected(filterNames: status.filterNames);
        notifier.setDeviceName(deviceName);
        notifier.updatePosition(status.position);
        notifier.setMoving(status.moving);
        await _heartbeat.start(
          deviceType: DeviceType.filterWheel,
          deviceId: deviceId,
          intervalMs: 10000,
        );

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
        await _syncFilterNamesToDriver(status.filterNames);
      } catch (e) {
        try {
          await _backend.disconnectDevice(DeviceType.filterWheel, deviceId);
        } catch (_) {
          // Preserve the original connect/status failure.
        }
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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('filter wheel');
      }

      _markUserInitiatedDisconnect(deviceId);
      _filterWheelVerifyGeneration++;

      try {
        await _heartbeat.stop(
          deviceType: DeviceType.filterWheel,
          deviceId: deviceId,
        );
        await _backend.disconnectDevice(DeviceType.filterWheel, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        await _heartbeat.start(
          deviceType: DeviceType.filterWheel,
          deviceId: deviceId,
          intervalMs: 10000,
        );
        rethrow;
      }
      _lastAppliedFilterOffsetByWheel.remove(deviceId);
      notifier.setDisconnected();
    });
  }

  /// Connect to a guider
  Future<void> _connectGuider(String deviceId, {String? host, int? port}) {
    return _trackInFlight(() async {
      final notifier = _ref.read(guiderStateProvider.notifier);
      // PHD2 recognition is centralized in `utils/device_id.dart` so the
      // several representations a profile may have stored ('phd2',
      // 'phd2_guider', 'phd2:host:port', 'phd2://…') are handled identically
      // everywhere.
      final isPhd2 = isPhd2DeviceId(deviceId);

      // Release whatever guider currently owns the slot (see
      // [_releaseDisplacedDevice]); PHD2 normalises to its canonical id.
      await _releaseDisplacedDevice(
        DeviceType.guider,
        isPhd2 ? kPhd2CanonicalId : deviceId,
      );

      // Special handling for PHD2 guider - uses different connection method
      if (isPhd2) {
        notifier.setConnecting(kPhd2CanonicalId, 'PHD2 Guiding');
        try {
          final settings = await _ref.read(appSettingsProvider.future);
          // The caller may pin the endpoint (guiding controller's
          // `connect(host, port)`); otherwise fall back to the configured
          // PHD2 host/port. Either way the launch path uses `settings.phd2Path`
          // — the override only steers where we open the socket, never whether
          // we honour the host-authoritative NetworkBackend rule below.
          final requestedHost = host ?? settings.phd2Host;
          final requestedPort = port ?? settings.phd2Port;
          // Auto-launch PHD2 on the imaging host when the socket is local.
          // Remote companions (NetworkBackend) must not spawn processes here —
          // they delegate launch to the desktop via POST /api/phd2/connect.
          // For remote PHD2 hosts (host != localhost/127.0.0.1) we never spawn.
          final connectHost = resolvePhd2ConnectHost(requestedHost);
          if (_backend is! NetworkBackend &&
              _phd2Launcher.isLocalHost(requestedHost)) {
            await _phd2Launcher.ensureRunning(
              executablePath: settings.phd2Path,
              host: connectHost,
              port: requestedPort,
            );
          }
          await _backend.phd2Connect(host: connectHost, port: requestedPort);
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
      // Format check only; backend is the source of truth for
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

      // Audit see [disconnectCamera] for the rationale.
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
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Connect to a dome
  Future<void> _connectDome(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(domeStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('dome', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.dome, deviceId);

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.dome, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.dome, deviceId);
        notifier.setConnected();
        // Seed the card with a real reading immediately, then keep it live.
        // A failed first read is NOT a connect failure — the dome is connected
        // and commandable; the readouts simply stay unknown and the periodic
        // poll surfaces the error.
        if (_backend is DomeStatusBackend) {
          try {
            await _readDomeStatusInto(_backend as DomeStatusBackend, deviceId);
          } catch (_) {
            // Reported by the poll loop; never fabricate telemetry here.
          }
        }
        _ensureEnvironmentPolling();
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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('dome');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.dome, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
      _stopEnvironmentPollingIfIdle();
    });
  }

  /// Connect to a weather device
  Future<void> _connectWeather(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(weatherStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('weather station', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.weather, deviceId);

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.weather, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.weather, deviceId);
        if (_backend is EnvironmentalStatusBackend) {
          final environmental = _backend as EnvironmentalStatusBackend;
          final conditions = await environmental.getHardwareWeatherConditions(
            deviceId,
          );
          notifier.updateConditions(
            temperature: conditions.temperature,
            humidity: conditions.humidity,
            pressure: conditions.pressure,
            cloudCover: conditions.cloudCover,
            dewPoint: conditions.dewPoint,
            windSpeed: conditions.windSpeed,
            windDirection: conditions.windDirection,
            skyQuality: conditions.skyQuality,
            skyTemperature: conditions.skyTemperature,
            rainRate: conditions.rainRate,
          );
        }
        notifier.setConnected();
        _ensureEnvironmentPolling();
      } catch (e) {
        try {
          await _backend.disconnectDevice(DeviceType.weather, deviceId);
        } catch (_) {
          // Preserve the telemetry failure that made the connection unsafe.
        }
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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('weather station');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.weather, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
      _stopEnvironmentPollingIfIdle();
    });
  }

  /// Connect to a safety monitor
  Future<void> _connectSafetyMonitor(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('safety monitor', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.safetyMonitor, deviceId);

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.safetyMonitor, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.safetyMonitor, deviceId);
        if (_backend is EnvironmentalStatusBackend) {
          final environmental = _backend as EnvironmentalStatusBackend;
          final isSafe = await environmental.getHardwareSafetyStatus(deviceId);
          notifier.updateSafetyStatus(isSafe);
        }
        notifier.setConnected();
        _ensureEnvironmentPolling();
      } catch (e) {
        try {
          await _backend.disconnectDevice(DeviceType.safetyMonitor, deviceId);
        } catch (_) {
          // Preserve the status-read failure; safety must fail closed.
        }
        // A safety-monitor transport failure is an unsafe/unknown verdict,
        // not a clean disconnected state. `setDisconnected` resets the model
        // to its historical `isSafe: true` default, which could briefly show
        // a green safety result after the driver status read failed. Retain
        // the device id and publish an explicit fail-closed error instead.
        notifier.setError(e);
        rethrow;
      }
    });
  }

  /// Disconnect safety monitor
  Future<void> _disconnectSafetyMonitor() {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);
      final state = _ref.read(safetyMonitorStateProvider);

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('safety monitor');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.safetyMonitor, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
      _stopEnvironmentPollingIfIdle();
    });
  }

  void _ensureEnvironmentPolling() {
    if (_environmentPollTimer != null) return;
    // The dome is a separate optional role, so the loop must start for a
    // dome-only rig too — otherwise the dome card's azimuth / shutter readouts
    // are never populated on a host with no weather or safety monitor.
    if (_backend is! EnvironmentalStatusBackend &&
        _backend is! DomeStatusBackend) {
      return;
    }
    _environmentPollTimer = Timer.periodic(
      DeviceService.environmentPollInterval,
      (_) => unawaited(_pollEnvironmentalStatus()),
    );
  }

  void _stopEnvironmentPollingIfIdle() {
    final weatherPollable = _shouldPollEnvironmentSource(
      _ref.read(weatherStateProvider).connectionState,
    );
    final safetyPollable = _shouldPollEnvironmentSource(
      _ref.read(safetyMonitorStateProvider).connectionState,
    );
    final domePollable = _shouldPollEnvironmentSource(
      _ref.read(domeStateProvider).connectionState,
    );
    if (!weatherPollable && !safetyPollable && !domePollable) {
      _environmentPollTimer?.cancel();
      _environmentPollTimer = null;
    }
  }

  /// Simulator campaign 2026-07-28 (S1): a read failure moves the device to
  /// `error`, and polling only `connected` devices meant the poll loop dropped
  /// the source permanently — a sensor that came back stayed unread until the
  /// operator reconnected it by hand. Keep polling a faulted device that still
  /// has an id so recovery is detected.
  static bool _shouldPollEnvironmentSource(DeviceConnectionState state) =>
      state == DeviceConnectionState.connected ||
      state == DeviceConnectionState.error;

  Future<void> _pollEnvironmentalStatus() async {
    if (_disposed || _environmentPollInFlight) return;
    final environmental = _backend is EnvironmentalStatusBackend
        ? _backend as EnvironmentalStatusBackend
        : null;
    final domeStatusBackend = _backend is DomeStatusBackend
        ? _backend as DomeStatusBackend
        : null;
    if (environmental == null && domeStatusBackend == null) return;

    _environmentPollInFlight = true;
    try {
      final weather = _ref.read(weatherStateProvider);
      final weatherId = weather.deviceId;
      if (environmental != null &&
          _shouldPollEnvironmentSource(weather.connectionState) &&
          weatherId != null) {
        try {
          final conditions = await environmental
              .getHardwareWeatherConditions(weatherId)
              .timeout(DeviceService._environmentReadTimeout);
          if (weather.connectionState == DeviceConnectionState.error) {
            _ref.read(weatherStateProvider.notifier).setConnected();
          }
          _ref
              .read(weatherStateProvider.notifier)
              .updateConditions(
                temperature: conditions.temperature,
                humidity: conditions.humidity,
                pressure: conditions.pressure,
                cloudCover: conditions.cloudCover,
                dewPoint: conditions.dewPoint,
                windSpeed: conditions.windSpeed,
                windDirection: conditions.windDirection,
                skyQuality: conditions.skyQuality,
                skyTemperature: conditions.skyTemperature,
                rainRate: conditions.rainRate,
              );
        } catch (error) {
          _ref.read(weatherStateProvider.notifier).setError(error);
        }
      }

      final safety = _ref.read(safetyMonitorStateProvider);
      final safetyId = safety.deviceId;
      if (environmental != null &&
          _shouldPollEnvironmentSource(safety.connectionState) &&
          safetyId != null) {
        try {
          final isSafe = await environmental
              .getHardwareSafetyStatus(safetyId)
              .timeout(DeviceService._environmentReadTimeout);
          if (safety.connectionState == DeviceConnectionState.error) {
            _ref.read(safetyMonitorStateProvider.notifier).setConnected();
          }
          _ref
              .read(safetyMonitorStateProvider.notifier)
              .updateSafetyStatus(isSafe);
        } catch (error) {
          _ref.read(safetyMonitorStateProvider.notifier).setError(error);
        }
      }

      final dome = _ref.read(domeStateProvider);
      final domeId = dome.deviceId;
      if (domeStatusBackend != null &&
          _shouldPollEnvironmentSource(dome.connectionState) &&
          domeId != null) {
        try {
          await _readDomeStatusInto(domeStatusBackend, domeId);
          if (dome.connectionState == DeviceConnectionState.error) {
            _ref.read(domeStateProvider.notifier).setConnected();
          }
        } catch (error) {
          _ref.read(domeStateProvider.notifier).setError(error);
        }
      }
    } finally {
      _environmentPollInFlight = false;
    }
  }

  /// Read one dome telemetry sample and publish it to [domeStateProvider].
  ///
  /// Throws whatever the driver / transport threw so the caller decides whether
  /// that is a connect abort, a poll error, or a best-effort refresh.
  Future<void> _readDomeStatusInto(
    DomeStatusBackend backend,
    String deviceId,
  ) async {
    final status = await backend
        .getHardwareDomeStatus(deviceId)
        .timeout(DeviceService._environmentReadTimeout);
    _ref
        .read(domeStateProvider.notifier)
        .applyStatus(
          azimuth: status.azimuth,
          shutterStatus: _shutterStatusFromCode(status.shutterStatus),
          isSlewing: status.isSlewing,
          isAtHome: status.isAtHome,
          isParked: status.isParked,
          isSlaved: status.isSlaved,
        );
  }

  /// Refresh dome telemetry immediately (used right after a dome command so the
  /// card reflects the new shutter/park state instead of waiting out the 5 s
  /// poll). Best-effort: a failed refresh leaves the previous reading in place
  /// and the periodic poll reports the error on its own next tick.
  Future<void> _refreshDomeStatus() async {
    if (_disposed) return;
    if (_backend is! DomeStatusBackend) return;
    final deviceId = _ref.read(domeStateProvider).deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    try {
      await _readDomeStatusInto(_backend as DomeStatusBackend, deviceId);
    } catch (_) {
      // Left to the periodic poll to classify.
    }
  }

  /// Map the raw ASCOM shutter code onto the UI enum. `null` (driver does not
  /// implement the property, or reported an unrecognised code) stays
  /// [ShutterStatus.unknown] instead of defaulting to `closed`.
  static ShutterStatus _shutterStatusFromCode(int? code) {
    switch (code) {
      case 0:
        return ShutterStatus.open;
      case 1:
        return ShutterStatus.closed;
      case 2:
        return ShutterStatus.opening;
      case 3:
        return ShutterStatus.closing;
      case 4:
        return ShutterStatus.error;
      default:
        return ShutterStatus.unknown;
    }
  }

  /// Connect to a switch device.
  ///
  /// Switch is a first-class device type with its own state
  /// provider and equipment-profile column. The Rust bridge exposes
  /// per-channel get/set under `api_switch_*`; per-channel UI is future
  /// work (see [SwitchState] docs) but the connect/disconnect path is
  /// real and must succeed before the user can flip any channels.
  Future<void> _connectSwitch(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('switch', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.switch_, deviceId);

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.switch_, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.switch_, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }

      // Best-effort snapshot after the connection itself is authoritative.
      // Refresh errors are surfaced by SwitchChannelService but must not turn
      // a genuinely connected power box back into a disconnected device.
      try {
        await _refreshSwitchChannels();
      } on Object {
        // The card retains a manual retry control.
      }
    });
  }

  /// Disconnect switch device.
  Future<void> _disconnectSwitch() {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);
      final state = _ref.read(switchStateProvider);

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('switch');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.switch_, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
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

  /// Set a numeric/PWM switch channel after validating its advertised range.
  Future<void> _setSwitchChannelValue(int channelIndex, double value) {
    return _trackInFlight(
      () => _switchChannels.setChannelValue(channelIndex, value),
    );
  }

  /// Connect to a rotator
  Future<void> _connectRotator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(rotatorStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('rotator', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.rotator, deviceId);

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.rotator, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.rotator, deviceId);
        notifier.setConnected();

        // Seed the real angle immediately. Otherwise a newly connected local
        // rotator displays "---" until the first movement event, even though
        // the driver already knows its position.
        try {
          final status = await _backend.getRotatorStatus(deviceId);
          notifier.updatePosition(
            status.position,
            mechanicalPosition: status.mechanicalPosition,
          );
          notifier.setMoving(status.moving || status.isMoving);
        } catch (e) {
          _safeLog(
            (logger) => logger.warning(
              'Failed to get initial rotator status for $deviceId: $e',
              source: 'DeviceService',
            ),
            'rotator-initial-status-fail',
          );
        }
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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('rotator');
      }

      _markUserInitiatedDisconnect(deviceId);
      _rotatorVerifyGeneration++;

      try {
        await _backend.disconnectDevice(DeviceType.rotator, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Connect to a cover calibrator (flat panel)
  Future<void> _connectCoverCalibrator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(coverCalibratorStateProvider.notifier);

      // Format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('cover calibrator', deviceId);
      }

      // Hand the type slot over cleanly rather than orphaning the
      // incumbent's driver connection (see [_releaseDisplacedDevice]).
      await _releaseDisplacedDevice(DeviceType.coverCalibrator, deviceId);

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

      // Audit see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('cover calibrator');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.coverCalibrator, deviceId);
      } catch (_) {
        _clearUserInitiatedDisconnect(deviceId);
        rethrow;
      }
      notifier.setDisconnected();
    });
  }

  /// Release the device about to be displaced from its type slot.
  ///
  /// Each device type owns exactly ONE notifier slot. Connecting a second
  /// device of the same type overwrote that slot while the incumbent's driver
  /// connection stayed open, and because every disconnect path matches on the
  /// slot's `deviceId`, the displaced device became unaddressable — its
  /// ASCOM/native handle stayed open for the rest of the session. Verified on
  /// the rig: after a simulator mount took the slot, a real NYX-101 kept
  /// answering position polls, `/api/devices/connected` listed both mounts, and
  /// `POST /api/devices/disconnect` for the real one returned
  /// `device_id_mismatch` — so nothing could ever close it. The same hole is
  /// reachable from the equipment dropdown and from activating a profile that
  /// names a different device for a type.
  ///
  /// Hand the slot over through the incumbent's own `_disconnectX` so the
  /// type-specific teardown (cooler off, heartbeat stop, pollers) still runs.
  ///
  /// Fail-soft: a displaced device whose cable is already gone must not block
  /// the incoming connect, so a failed teardown is logged and swallowed.
  Future<void> _releaseDisplacedDevice(
    DeviceType type,
    String incomingDeviceId,
  ) async {
    final currentId = _slotDeviceIdFor(type);
    if (currentId == null ||
        currentId.isEmpty ||
        currentId == incomingDeviceId) {
      return;
    }
    _safeLog(
      (l) => l.info(
        'Connecting ${type.name} $incomingDeviceId displaces $currentId; '
        'disconnecting the incumbent first so its driver handle is released',
        source: 'DeviceService',
      ),
      'device-slot-handover',
    );
    try {
      await _disconnectForType(type);
    } catch (e) {
      _safeLog(
        (l) => l.warning(
          'Displaced ${type.name} $currentId did not disconnect cleanly: $e',
          source: 'DeviceService',
        ),
        'device-slot-handover-failed',
      );
    }
  }

  /// deviceId currently held in [type]'s notifier slot, or `null` when the
  /// slot is empty. `setDisconnected()` resets the state object, so a
  /// non-null id here means a device still owns the slot.
  String? _slotDeviceIdFor(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return _ref.read(cameraStateProvider).deviceId;
      case DeviceType.mount:
        return _ref.read(mountStateProvider).deviceId;
      case DeviceType.focuser:
        return _ref.read(focuserStateProvider).deviceId;
      case DeviceType.filterWheel:
        return _ref.read(filterWheelStateProvider).deviceId;
      case DeviceType.guider:
        return _ref.read(guiderStateProvider).deviceId;
      case DeviceType.rotator:
        return _ref.read(rotatorStateProvider).deviceId;
      case DeviceType.dome:
        return _ref.read(domeStateProvider).deviceId;
      case DeviceType.weather:
        return _ref.read(weatherStateProvider).deviceId;
      case DeviceType.safetyMonitor:
        return _ref.read(safetyMonitorStateProvider).deviceId;
      case DeviceType.coverCalibrator:
        return _ref.read(coverCalibratorStateProvider).deviceId;
      case DeviceType.switch_:
        return _ref.read(switchStateProvider).deviceId;
    }
  }

  /// Route to the type-specific disconnect so the displaced device gets its
  /// real teardown rather than a bare backend call.
  Future<void> _disconnectForType(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return _disconnectCamera();
      case DeviceType.mount:
        return _disconnectMount();
      case DeviceType.focuser:
        return _disconnectFocuser();
      case DeviceType.filterWheel:
        return _disconnectFilterWheel();
      case DeviceType.guider:
        return _disconnectGuider();
      case DeviceType.rotator:
        return _disconnectRotator();
      case DeviceType.dome:
        return _disconnectDome();
      case DeviceType.weather:
        return _disconnectWeather();
      case DeviceType.safetyMonitor:
        return _disconnectSafetyMonitor();
      case DeviceType.coverCalibrator:
        return _disconnectCoverCalibrator();
      case DeviceType.switch_:
        return _disconnectSwitch();
    }
  }
}
