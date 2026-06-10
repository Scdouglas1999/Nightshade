part of '../device_handlers.dart';

extension DeviceConnectionHandlers on DeviceHandlers {
  // ===========================================================================
  // Connection lifecycle
  //
  // Audit DEV-P0-2: the previous headless implementation called
  // `backend.connectDevice` / `backend.disconnectDevice` directly. That
  // shipped a "connected" response to remote clients while skipping the
  // full per-device-type connect flow that the desktop UI runs through
  // `DeviceService`:
  //
  //   * cameras: cool-on-connect, target-temp seeding, recommended-gain
  //     auto-apply, temperature polling, heartbeat monitoring
  //   * mounts: initial status snapshot (RA/Dec/Alt/Az + park/track flags),
  //     heartbeat monitoring
  //   * focusers: status snapshot (position, max position, temperature)
  //   * filter wheels: position settling poll, filter-name sync to driver
  //     from active profile / session
  //   * guiders: PHD2 handshake when applicable
  //
  // It also left the per-device-type StateNotifier (`cameraStateProvider`,
  // `mountStateProvider`, ...) untouched, so any local UI listening to the
  // Riverpod state still believed nothing was connected — exactly the same
  // failure mode we just fixed for sequencer start (audit C3).
  //
  // The fix routes every connect through `DeviceService.connect<Type>` so
  // remote clients are first-class consumers of the same code path the
  // desktop UI uses.
  // ===========================================================================

  /// POST /api/devices/connect
  ///
  /// Body: `{deviceId, deviceType}`. The `deviceType` value must match one
  /// of [DeviceType]'s names (case-insensitive). Returns
  /// `{status: "connected", deviceId, deviceType}` on success and surfaces
  /// validation/state errors as 4xx with a structured body so a remote
  /// dashboard can render the same "device not found" / "no profile active"
  /// hints the desktop dialog does.
  Future<Response> handleConnectDevice(Request request) async {
    _logInfo('[API] POST /api/devices/connect');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final deviceTypeStr = requireString(payload, 'deviceType');
    final deviceType = parseDeviceType(deviceTypeStr);
    if (deviceType == null) {
      throw BadRequestError(
        field: 'deviceType',
        expected: validDeviceTypeList(),
        message: 'Unknown device type: $deviceTypeStr',
      );
    }

    final service = container.read(deviceServiceProvider);
    try {
      await _dispatchConnect(service, deviceType, deviceId);
    } on _DeviceNotFoundFailure catch (e) {
      throw HandlerFailure(
        code: 'device_not_found',
        message: e.message,
        statusCode: 404,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
      );
    } catch (e, stackTrace) {
      // The connect threw after passing discovery — most likely the
      // underlying driver refused (cable unplugged, ASCOM driver not
      // installed, INDI server unreachable, etc.). Surface a 502 with the
      // service's own message so the remote operator sees the same
      // diagnostic the desktop UI would have surfaced via a snackbar.
      _logWarning(
        '[API] POST /api/devices/connect failed for ${deviceType.name} '
        '$deviceId: $e',
      );
      throw HandlerFailure(
        code: 'device_connect_failed',
        message: _sanitizeConnectErrorMessage(e),
        statusCode: 502,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
        cause: e,
        stackTrace: stackTrace,
      );
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.equipment,
      action: HostMutationAction.connected,
      entityId: deviceId,
      extra: {
        'deviceType': deviceType.name,
        'deviceId': deviceId,
      },
    );

    return jsonOk({
      'status': 'connected',
      'deviceId': deviceId,
      'deviceType': deviceType.name,
    });
  }

  /// POST /api/devices/disconnect
  ///
  /// Body: `{deviceId, deviceType}`. The disconnect path always operates on
  /// the device currently held in the matching StateNotifier; we still
  /// require `deviceId` so the caller cannot silently disconnect a
  /// different device than they think they are. If the supplied `deviceId`
  /// does not match the currently-connected one, we return 409 rather than
  /// guess.
  Future<Response> handleDisconnectDevice(Request request) async {
    _logInfo('[API] POST /api/devices/disconnect');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final deviceTypeStr = requireString(payload, 'deviceType');
    final deviceType = parseDeviceType(deviceTypeStr);
    if (deviceType == null) {
      throw BadRequestError(
        field: 'deviceType',
        expected: validDeviceTypeList(),
        message: 'Unknown device type: $deviceTypeStr',
      );
    }

    final connectedId = _connectedDeviceIdFor(deviceType);
    if (connectedId == null || connectedId.isEmpty) {
      throw HandlerFailure(
        code: 'device_not_connected',
        message: 'No ${deviceType.name} is currently connected',
        statusCode: 409,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
      );
    }
    if (connectedId != deviceId) {
      throw HandlerFailure(
        code: 'device_id_mismatch',
        message:
            'Requested deviceId does not match the currently-connected ${deviceType.name}',
        statusCode: 409,
        details: {
          'requestedDeviceId': deviceId,
          'connectedDeviceId': connectedId,
          'deviceType': deviceType.name,
        },
      );
    }

    final service = container.read(deviceServiceProvider);
    try {
      await _dispatchDisconnect(service, deviceType);
    } catch (e, stackTrace) {
      _logWarning(
        '[API] POST /api/devices/disconnect failed for ${deviceType.name} '
        '$deviceId: $e',
      );
      throw HandlerFailure(
        code: 'device_disconnect_failed',
        message: _sanitizeConnectErrorMessage(e),
        statusCode: 502,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
        cause: e,
        stackTrace: stackTrace,
      );
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.equipment,
      action: HostMutationAction.disconnected,
      entityId: deviceId,
      extra: {
        'deviceType': deviceType.name,
        'deviceId': deviceId,
      },
    );

    return jsonOk({
      'status': 'disconnected',
      'deviceId': deviceId,
      'deviceType': deviceType.name,
    });
  }

  /// Dispatches connect by [DeviceType] to the matching `DeviceService`
  /// method. The DeviceService methods do all the bookkeeping (state
  /// notifier transitions, cool-on-connect, recommended-gain auto-apply,
  /// heartbeat start, filter-name sync, ...).
  ///
  /// DEV-P2-1 brought switches in line with every other device type:
  /// `DeviceService.connectSwitch` / `disconnectSwitch` drive the
  /// `switchStateProvider` notifier and own the auto-reconnect loop, so
  /// the dispatcher routes switches through the service like everything
  /// else.
  Future<void> _dispatchConnect(
    DeviceService service,
    DeviceType type,
    String deviceId,
  ) async {
    try {
      switch (type) {
        case DeviceType.camera:
          await service.connectCamera(deviceId);
          break;
        case DeviceType.mount:
          await service.connectMount(deviceId);
          break;
        case DeviceType.focuser:
          await service.connectFocuser(deviceId);
          break;
        case DeviceType.filterWheel:
          await service.connectFilterWheel(deviceId);
          break;
        case DeviceType.guider:
          await service.connectGuider(deviceId);
          break;
        case DeviceType.rotator:
          await service.connectRotator(deviceId);
          break;
        case DeviceType.dome:
          await service.connectDome(deviceId);
          break;
        case DeviceType.weather:
          await service.connectWeather(deviceId);
          break;
        case DeviceType.safetyMonitor:
          await service.connectSafetyMonitor(deviceId);
          break;
        case DeviceType.coverCalibrator:
          await service.connectCoverCalibrator(deviceId);
          break;
        case DeviceType.switch_:
          await service.connectSwitch(deviceId);
          break;
      }
    } on Exception catch (e) {
      // DeviceService throws `Exception('<Kind> not found: <id>')` when
      // discovery doesn't surface the requested device. Translate that
      // into a structured 404 so remote clients can distinguish
      // "you asked for a device that does not exist" from
      // "the driver failed to open the device".
      // Internal use only: the curated "<Kind> not found: <id>" service
      // message is matched here and re-thrown as a structured 404 below —
      // the raw exception object itself is never serialized.
      final message = '$e';
      if (message.contains('not found:')) {
        throw _DeviceNotFoundFailure(message.replaceFirst('Exception: ', ''));
      }
      rethrow;
    }
  }

  Future<void> _dispatchDisconnect(
    DeviceService service,
    DeviceType type,
  ) async {
    switch (type) {
      case DeviceType.camera:
        await service.disconnectCamera();
        break;
      case DeviceType.mount:
        await service.disconnectMount();
        break;
      case DeviceType.focuser:
        await service.disconnectFocuser();
        break;
      case DeviceType.filterWheel:
        await service.disconnectFilterWheel();
        break;
      case DeviceType.guider:
        await service.disconnectGuider();
        break;
      case DeviceType.rotator:
        await service.disconnectRotator();
        break;
      case DeviceType.dome:
        await service.disconnectDome();
        break;
      case DeviceType.weather:
        await service.disconnectWeather();
        break;
      case DeviceType.safetyMonitor:
        await service.disconnectSafetyMonitor();
        break;
      case DeviceType.coverCalibrator:
        await service.disconnectCoverCalibrator();
        break;
      case DeviceType.switch_:
        await service.disconnectSwitch();
        break;
    }
  }

  /// Reads the deviceId currently held by the matching equipment
  /// StateNotifier. Used by the disconnect endpoint to verify that the
  /// caller is asking to disconnect the device that is actually connected.
  String? _connectedDeviceIdFor(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return container.read(cameraStateProvider).deviceId;
      case DeviceType.mount:
        return container.read(mountStateProvider).deviceId;
      case DeviceType.focuser:
        return container.read(focuserStateProvider).deviceId;
      case DeviceType.filterWheel:
        return container.read(filterWheelStateProvider).deviceId;
      case DeviceType.guider:
        return container.read(guiderStateProvider).deviceId;
      case DeviceType.rotator:
        return container.read(rotatorStateProvider).deviceId;
      case DeviceType.dome:
        return container.read(domeStateProvider).deviceId;
      case DeviceType.weather:
        return container.read(weatherStateProvider).deviceId;
      case DeviceType.safetyMonitor:
        return container.read(safetyMonitorStateProvider).deviceId;
      case DeviceType.coverCalibrator:
        return container.read(coverCalibratorStateProvider).deviceId;
      case DeviceType.switch_:
        return container.read(switchStateProvider).deviceId;
    }
  }

  /// Strips the leading `Exception: ` Dart prepends so the wire message
  /// reads cleanly to a remote operator. Internal type names and stacks
  /// stay in the structured log via [HandlerFailure.cause].
  String _sanitizeConnectErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
