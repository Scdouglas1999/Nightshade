part of '../device_handlers.dart';

extension FilterWheelDeviceHandlers on DeviceHandlers {
  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  Future<Response> handleFilterWheelSetPosition(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/position');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'filter-wheel.set-position',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetPosition(deviceId, position);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'ok',
    });
  }

  Future<Response> handleFilterWheelGetNames(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(deviceBackendProvider);
    final names = await backend.filterWheelGetNames(deviceId);

    return jsonOk({'names': names});
  }

  Future<Response> handleFilterWheelSetNames(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/names');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final names = requireList<String>(payload, 'names');

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetNames(deviceId, names);

    return jsonOk({'status': 'ok'});
  }

  /// remote GET for the current filter-wheel position/state.
  ///
  /// Reads from `filterWheelStateProvider` which the device-service
  /// keeps in sync with the underlying driver via the position-settle
  /// poll. Why this provider (not a backend call): the StateNotifier
  /// already aggregates the position, the slot-name table, and the
  /// `isMoving` flag in one place. Going directly to the backend would
  /// give us the integer but miss the resolved filter name and the
  /// move-in-progress flag, which is exactly what mobile callers need.
  ///
  /// The response shape matches the task spec:
  ///   { "position": int|null, "name": string|null, "isMoving": bool }
  /// Position is null when the wheel is disconnected or has not yet
  /// reported a starting slot. Name is null when no slot label is
  /// available for the current position (driver returned a short array
  /// or the wheel is disconnected).
  Future<Response> handleFilterWheelGetPosition(Request request) async {
    _logInfo('[API] GET /api/filter-wheel/position');
    final state = container.read(filterWheelStateProvider);
    return jsonOk({
      'position': state.currentPosition,
      'name': state.currentFilterName,
      'isMoving': state.isMoving,
    });
  }

  Future<Response> handleFilterWheelSetByName(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/set-by-name');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final name = requireString(payload, 'name');

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetByName(deviceId, name);

    return jsonOk({'status': 'ok'});
  }
}
