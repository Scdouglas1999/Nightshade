part of '../device_handlers.dart';

extension MountDeviceHandlers on DeviceHandlers {
  Future<Response> handleMountSlew(Request request) async {
    _logInfo('[API] POST /api/mount/slew');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final ra = requireDouble(payload, 'ra', min: 0, max: 24);
    final dec = requireDouble(payload, 'dec', min: -90, max: 90);

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.slew',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountSlewToCoordinates(deviceId, ra, dec);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'slewing',
    });
  }

  Future<Response> handleMountSync(Request request) async {
    _logInfo('[API] POST /api/mount/sync');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final ra = requireDouble(payload, 'ra', min: 0, max: 24);
    final dec = requireDouble(payload, 'dec', min: -90, max: 90);

    final backend = container.read(deviceBackendProvider);
    await backend.mountSync(deviceId, ra, dec);

    return jsonOk({'status': 'synced'});
  }

  Future<Response> handleMountPark(Request request) async {
    _logInfo('[API] POST /api/mount/park');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.park',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountPark(deviceId);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'parking',
    });
  }

  Future<Response> handleMountUnpark(Request request) async {
    _logInfo('[API] POST /api/mount/unpark');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.unpark',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountUnpark(deviceId);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'unparked',
    });
  }

  Future<Response> handleMountSetTracking(Request request) async {
    _logInfo('[API] POST /api/mount/tracking');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(deviceBackendProvider);
    await backend.mountSetTracking(deviceId, enabled);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountPulseGuide(Request request) async {
    _logInfo('[API] POST /api/mount/pulse-guide');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final direction = requireString(payload, 'direction');
    if (!const {
      'north',
      'south',
      'east',
      'west',
    }.contains(direction.toLowerCase())) {
      throw BadRequestError(
        field: 'direction',
        expected: 'north|south|east|west',
        message: 'direction must be north, south, east, or west',
      );
    }
    final durationMs = requireInt(payload, 'durationMs', min: 1);

    final backend = container.read(deviceBackendProvider);
    await backend.mountPulseGuide(
      deviceId: deviceId,
      direction: direction,
      durationMs: durationMs,
    );

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountAbort(Request request) async {
    _logInfo('[API] POST /api/mount/abort');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.mountAbort(deviceId);

    return jsonOk({'status': 'aborted'});
  }

  Future<Response> handleMountGetStatus(Request request) async {
    final backend = container.read(deviceBackendProvider);

    // Resolve the target mount. When the caller omits `deviceId` (the common
    // case for a tablet that just wants "the" mount), fall back to the single
    // connected mount instead of passing an empty id straight to the backend,
    // which previously produced an opaque 500 ("Device not found:"). Only when
    // no mount is connected do we surface a clean 400.
    var deviceId = request.url.queryParameters['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      final connected = await backend.getConnectedDevices();
      final mounts = connected
          .where((d) => d.deviceType == DeviceType.mount)
          .toList();
      if (mounts.isEmpty) {
        throw BadRequestError(
          field: 'deviceId',
          expected: 'string',
          message:
              'deviceId query parameter is required (no mount is connected)',
        );
      }
      deviceId = mounts.first.id;
    }

    // Use getMountStatus (returns the domain MountStatus with a real toJson())
    // rather than mountGetStatus (returns the raw flutter_rust_bridge object,
    // which has no toJson and so makes jsonEncode throw -> internal_error for
    // every remote client). Both route through the same native apiGetMountStatus
    // under the hood, so simulator and real mounts are handled identically.
    final status = await backend.getMountStatus(deviceId);

    return jsonOk(status.toJson());
  }

  Future<Response> handleMountSetTrackingRate(Request request) async {
    _logInfo('[API] POST /api/mount/set-tracking-rate');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final rate = requireInt(payload, 'rate', min: 0, max: 3);

    final backend = container.read(deviceBackendProvider);
    await backend.mountSetTrackingRate(deviceId, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountMoveAxis(Request request) async {
    _logInfo('[API] POST /api/mount/move-axis');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final axis = requireInt(payload, 'axis', min: 0, max: 1);
    final rate = requireDouble(payload, 'rate');

    final backend = container.read(deviceBackendProvider);
    await backend.mountMoveAxis(deviceId, axis, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountSlewAltAz(Request request) async {
    _logInfo('[API] POST /api/mount/slew-alt-az');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final altitude = requireDouble(payload, 'altitude', min: -90, max: 90);
    final azimuth = requireDouble(payload, 'azimuth', min: 0, max: 360);

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.slew-alt-az',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountSlewAltAz(deviceId, altitude, azimuth);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'slewing',
    });
  }

  Future<Response> handleMountFindHome(Request request) async {
    _logInfo('[API] POST /api/mount/find-home');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.mountFindHome(deviceId);

    return jsonOk({'status': 'finding_home'});
  }

  // ===========================================================================
}
