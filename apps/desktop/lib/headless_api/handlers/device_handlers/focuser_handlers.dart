part of '../device_handlers.dart';

extension FocuserDeviceHandlers on DeviceHandlers {
  Future<Response> handleFocuserMoveTo(Request request) async {
    _logInfo('[API] POST /api/focuser/move-to');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-to',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.focuserMoveTo(deviceId, position);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'moving',
    });
  }

  Future<Response> handleFocuserMoveRelative(Request request) async {
    _logInfo('[API] POST /api/focuser/move-relative');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final delta = requireInt(payload, 'delta');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-relative',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.focuserMoveRelative(deviceId, delta);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'moving',
    });
  }

  Future<Response> handleFocuserHalt(Request request) async {
    _logInfo('[API] POST /api/focuser/halt');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.focuserHalt(deviceId);

    return jsonOk({'status': 'halted'});
  }

  Future<Response> handleAutofocusStart(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/start');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final cameraId = requireString(payload, 'cameraId');
    final exposureTime = requireDouble(payload, 'exposureTime');
    final stepSize = requireInt(payload, 'stepSize');
    final stepsOut = requireInt(payload, 'stepsOut');
    final method = optionalString(payload, 'method') ?? 'VCurve';
    final binning = optionalInt(payload, 'binning') ?? 1;

    // P1-4: register the command so any later event with a matching
    // operation kind picks up `correlatingCommandId`. We still register
    // even in the new job-model path because the event correlator's
    // matching is independent of the job's own jobId — they evolve in
    // parallel (the audit's §3 lays out the rationale).
    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.autofocus.start',
      deviceId: deviceId,
    );

    // P1-2 / P1-3: when a JobManager is wired up and the client has
    // NOT opted into the legacy synchronous shape, return `{jobId,
    // status: queued, commandId}` immediately and run the autofocus
    // work in the background. Progress + completion arrive via WS
    // events (category=job).
    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      final job = mgr.start(
        operation: 'focuser.autofocus',
        deviceId: deviceId,
        commandId: commandId,
        work: (sink, cancellation) async {
          sink.update(null, 'Starting autofocus');
          final backend = container.read(deviceBackendProvider);
          // The backend call is currently a long synchronous FFI
          // operation — see audit Q6 — so cooperative cancellation has
          // to wait for it to return. We race the work against the
          // cancellation token so the JobManager can flag the job as
          // cancelled even though the FFI side keeps running. A future
          // wave will plumb cancellation into Rust.
          final workFuture = backend.autofocusStart(
            deviceId: deviceId,
            cameraId: cameraId,
            exposureTime: exposureTime,
            stepSize: stepSize,
            stepsOut: stepsOut,
            method: method,
            binning: binning,
          );
          final result = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then((_) => _CancelledMarker.instance),
          ]);
          if (result is _CancelledMarker) {
            throw const JobCancelledException(
              'Autofocus cancellation requested by client',
            );
          }
          final typed = result as AutofocusResult;
          return typed.toJson();
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        if (commandId != null) 'commandId': commandId,
        'operation': job.operation,
      });
    }

    // Legacy fallback (no JobManager wired or client opted into
    // synchronous shape). Existing behaviour preserved.
    final backend = container.read(deviceBackendProvider);
    final result = await backend.autofocusStart(
      deviceId: deviceId,
      cameraId: cameraId,
      exposureTime: exposureTime,
      stepSize: stepSize,
      stepsOut: stepsOut,
      method: method,
      binning: binning,
    );

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      ...result.toJson(),
    });
  }

  Future<Response> handleAutofocusCancel(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/cancel');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.autofocus.cancel',
    );
    final backend = container.read(deviceBackendProvider);
    await backend.autofocusCancel();

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'cancelled',
    });
  }
}
