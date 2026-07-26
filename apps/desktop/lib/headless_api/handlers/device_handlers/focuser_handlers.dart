part of '../device_handlers.dart';

extension FocuserDeviceHandlers on DeviceHandlers {
  /// Reject a focuser target that lies outside the driver's advertised travel.
  ///
  /// Why: `requireInt(..., min: 0)` guarded only the lower bound, so a target
  /// above `maxPosition` was accepted and answered `200 {"status":"moving"}`.
  /// Observed on the rig against an ASCOM focuser advertising
  /// `maxPosition: 50000`: `move-to 999999` was accepted, and `move-relative`
  /// with `delta: 900000` drove the focuser for roughly 40 seconds before the
  /// driver silently clamped it at 50000 — so a mistyped extra zero became a
  /// long blind run to the mechanical limit that reported success and ended
  /// somewhere the operator never asked for. Drivers are not required to clamp;
  /// one that does not would be commanded into its end stop. The negative case
  /// was already refused with a precise 400, so only the upper half of the same
  /// check was missing.
  ///
  /// `maxPosition <= 0` means the driver advertised no travel range (its
  /// `MaxStep` threw `PropertyNotImplementedException`), so there is nothing to
  /// validate against and the request is passed through untouched.
  ///
  /// Takes the already-read [status] rather than fetching its own: a relative
  /// move needs the current position anyway, and ASCOM focusers are polled over
  /// COM, so reading the same status twice per request would double the driver
  /// traffic and the chance of hitting a transient property fault.
  ///
  /// A null [status] means the status read itself failed, in which case there is
  /// no bound to check against and the request passes through — see
  /// [_tryFocuserStatus].
  void _requireWithinTravel({
    required String deviceId,
    required FocuserStatus? status,
    required int target,
    required String field,
    String? origin,
  }) {
    if (status == null) return;
    final maxPosition = status.maxPosition;
    if (maxPosition <= 0) return;
    if (target >= 0 && target <= maxPosition) return;

    throw BadRequestError(
      field: field,
      expected: '0 to $maxPosition',
      message: origin == null
          ? 'Focuser target $target is outside the travel range 0 to '
                '$maxPosition reported by $deviceId'
          : 'Focuser target $target ($origin) is outside the travel range 0 '
                'to $maxPosition reported by $deviceId',
    );
  }

  /// Read focuser status for the range check, tolerating a failed read.
  ///
  /// Why it must not propagate: before the range check existed the move went
  /// straight to the driver, so letting an unreadable status turn into a failed
  /// move would invent a new way for a previously working operation to fail —
  /// and on a USB-contended rig a focuser status poll can transiently fault
  /// while the move itself would have succeeded. Returning null skips the guard
  /// and lets the driver arbitrate, exactly as it did before.
  Future<FocuserStatus?> _tryFocuserStatus(String deviceId) async {
    try {
      return await container
          .read(deviceBackendProvider)
          .getFocuserStatus(deviceId);
    } catch (error) {
      _logInfo(
        'focuser travel-range check skipped for $deviceId: '
        'status read failed ($error)',
      );
      return null;
    }
  }

  Future<Response> handleFocuserMoveTo(Request request) async {
    _logInfo('[API] POST /api/focuser/move-to');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position', min: 0);

    final backend = container.read(deviceBackendProvider);
    _requireWithinTravel(
      deviceId: deviceId,
      status: await _tryFocuserStatus(deviceId),
      target: position,
      field: 'position',
    );

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-to',
      deviceId: deviceId,
    );
    try {
      await backend.focuserMoveTo(deviceId, position);
    } catch (error) {
      if (_isFocuserBusy(error)) {
        return jsonError(
          code: 'device_busy',
          message: 'The focuser is already moving.',
          statusCode: HttpStatus.conflict,
          details: {'deviceId': deviceId},
        );
      }
      rethrow;
    }

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

    final backend = container.read(deviceBackendProvider);
    // A relative move is only meaningful against the current position, so the
    // range check is applied to the resolved target rather than to the delta.
    // Without a readable position there is no target to check, so the guard is
    // skipped rather than failing a move that used to work.
    final status = await _tryFocuserStatus(deviceId);
    if (status != null) {
      final current = status.position;
      _requireWithinTravel(
        deviceId: deviceId,
        status: status,
        target: current + delta,
        field: 'delta',
        origin: 'position $current + delta $delta',
      );
    }

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-relative',
      deviceId: deviceId,
    );
    try {
      await backend.focuserMoveRelative(deviceId, delta);
    } catch (error) {
      if (_isFocuserBusy(error)) {
        return jsonError(
          code: 'device_busy',
          message: 'The focuser is already moving.',
          statusCode: HttpStatus.conflict,
          details: {'deviceId': deviceId},
        );
      }
      rethrow;
    }

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

  bool _isFocuserBusy(Object error) {
    final message = error is bridge_error.NightshadeError
        ? error.maybeMap(
            operationFailed: (failure) => failure.field0,
            orElse: () => error.toString(),
          )
        : error.toString();
    final normalized = message.toLowerCase();
    return normalized.contains('move failure') ||
        normalized.contains('already moving') ||
        normalized.contains('device busy') ||
        normalized.contains('focuser is busy');
  }

  Future<Response> handleAutofocusStart(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/start');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final cameraId = requireString(payload, 'cameraId');
    final exposureTime = requireDouble(
      payload,
      'exposureTime',
      min: 0.1,
      max: 300,
    );
    final stepSize = requireInt(payload, 'stepSize', min: 1, max: 10000);
    final stepsOut = requireInt(payload, 'stepsOut', min: 1, max: 50);
    final method = optionalString(payload, 'method') ?? 'VCurve';
    final binning = optionalInt(payload, 'binning', min: 1, max: 4) ?? 1;
    final gain = optionalInt(payload, 'gain', min: 0);
    final offset = optionalInt(payload, 'offset', min: 0);
    final curveFitting =
        optionalString(payload, 'curveFitting') ?? 'Hyperbolic';
    final numberOfAttempts =
        optionalInt(payload, 'numberOfAttempts', min: 1, max: 10) ?? 1;
    final exposuresPerPoint =
        optionalInt(payload, 'exposuresPerPoint', min: 1, max: 20) ?? 1;
    final rSquaredThreshold =
        optionalDouble(payload, 'rSquaredThreshold', min: 0, max: 1) ?? 0.7;
    final outerCropRatio =
        optionalDouble(payload, 'outerCropRatio', min: 0, max: 1) ?? 1.0;
    final innerCropRatio =
        optionalDouble(payload, 'innerCropRatio', min: 0, max: 1) ?? 0.0;
    if (outerCropRatio == 0 || innerCropRatio >= outerCropRatio) {
      throw BadRequestError(
        field: 'innerCropRatio/outerCropRatio',
        expected: '0 <= inner < outer <= 1',
        message: 'Crop ratios must satisfy 0 <= inner < outer <= 1',
      );
    }
    final useBrightestNStars =
        optionalInt(payload, 'useBrightestNStars', min: 0, max: 500) ?? 0;
    final focuserSettleTimeMs =
        optionalInt(payload, 'focuserSettleTimeMs', min: 0, max: 10000) ?? 500;
    final backlashCompMethod =
        optionalString(payload, 'backlashCompMethod') ?? 'Overshoot';
    final backlashIn =
        optionalInt(payload, 'backlashIn', min: 0, max: 10000) ?? 350;
    final backlashOut =
        optionalInt(payload, 'backlashOut', min: 0, max: 10000) ?? 0;

    // register the command so any later event with a matching
    // operation kind picks up `correlatingCommandId`. We still register
    // even in the new job-model path because the event correlator's
    // matching is independent of the job's own jobId — they evolve in
    // parallel (the audit's §3 lays out the rationale).
    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.autofocus.start',
      deviceId: deviceId,
    );

    // when a JobManager is wired up and the client has
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
          // Race the long-running call against the job token. If the client
          // cancels, propagate that request through the backend before marking
          // the job cancelled; otherwise the REST job would disappear while
          // the camera and focuser continued a physical autofocus sweep.
          final workFuture = backend.autofocusStart(
            deviceId: deviceId,
            cameraId: cameraId,
            exposureTime: exposureTime,
            stepSize: stepSize,
            stepsOut: stepsOut,
            method: method,
            binning: binning,
            gain: gain,
            offset: offset,
            curveFitting: curveFitting,
            numberOfAttempts: numberOfAttempts,
            exposuresPerPoint: exposuresPerPoint,
            rSquaredThreshold: rSquaredThreshold,
            outerCropRatio: outerCropRatio,
            innerCropRatio: innerCropRatio,
            useBrightestNStars: useBrightestNStars,
            focuserSettleTimeMs: focuserSettleTimeMs,
            backlashCompMethod: backlashCompMethod,
            backlashIn: backlashIn,
            backlashOut: backlashOut,
          );
          final result = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then((_) => _CancelledMarker.instance),
          ]);
          if (result is _CancelledMarker) {
            await backend.autofocusCancel();
            // `autofocusCancel` only requests cancellation. The native sweep
            // still has to halt the motor and command its return position, so
            // keep the job running until the original work future actually
            // settles. A terminal JobCancelled event before that point would
            // let clients start another sweep on moving hardware.
            try {
              await workFuture;
            } catch (error) {
              // Cancellation normally makes the work future fail with the
              // backend's typed cancelled error. The user's cancellation is
              // authoritative once the cancel command itself succeeded.
              _logger.debug(
                'Autofocus work settled with an error after client cancellation: '
                '$error',
                source: 'DeviceHandlers',
              );
            }
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
      gain: gain,
      offset: offset,
      curveFitting: curveFitting,
      numberOfAttempts: numberOfAttempts,
      exposuresPerPoint: exposuresPerPoint,
      rSquaredThreshold: rSquaredThreshold,
      outerCropRatio: outerCropRatio,
      innerCropRatio: innerCropRatio,
      useBrightestNStars: useBrightestNStars,
      focuserSettleTimeMs: focuserSettleTimeMs,
      backlashCompMethod: backlashCompMethod,
      backlashIn: backlashIn,
      backlashOut: backlashOut,
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
    final manager = jobManager;
    final activeJobs = manager
        ?.list(operation: 'focuser.autofocus')
        .where((job) => !job.state.isTerminal)
        .toList(growable: false);
    if (activeJobs != null && activeJobs.isNotEmpty) {
      // Drive the same cooperative token owned by the job. Its work callback
      // propagates the request to the backend and does not become terminal
      // until the physical sweep future settles.
      for (final job in activeJobs) {
        manager!.cancel(job.jobId);
      }
      return jsonOk({
        if (commandId != null) 'commandId': commandId,
        'status': 'cancellation_requested',
        'jobIds': activeJobs.map((job) => job.jobId).toList(growable: false),
      });
    }

    // Legacy/no-job run (or a sweep started by another in-process surface).
    final backend = container.read(deviceBackendProvider);
    await backend.autofocusCancel();

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'cancellation_requested',
    });
  }
}
