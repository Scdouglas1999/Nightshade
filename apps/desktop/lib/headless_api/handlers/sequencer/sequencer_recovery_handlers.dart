part of '../sequencer_handlers.dart';

/// Recovery-mode HTTP handlers.
extension _SequencerRecovery on SequencerHandlers {
  // ==========================================================================
  // Recovery Mode — HTTP handlers
  // ==========================================================================
  //
  // These mirror the NetworkBackend client calls in
  // `network_backend.dart > recoveryTryNow/recoveryAbort/updateRecoveryConfig/
  // getCurrentRecoveryJson/getRecoveryHistoryJson`. The shape of the JSON
  // wire payload here is what `_post`/`_get` produces / expects on the
  // client side; do not change one without changing the other.

  /// Operator pressed "Try Now" remotely (mobile companion, web dashboard).
  /// Punches through the wait timer and forces the next recovery attempt
  /// immediately. No-op when the executor is not in `Recovering`.
  Future<Response> _handleSequencerRecoveryTryNow(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/try-now');
    final backend = container.read(sequencerBackendProvider);
    await backend.recoveryTryNow();
    return jsonOk({'status': 'try_now_requested'});
  }

  /// Operator pressed "Abort" remotely. Exits the recovery loop and
  /// transitions the executor to `Failed`. No-op when not in `Recovering`.
  Future<Response> _handleSequencerRecoveryAbort(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/abort');
    final backend = container.read(sequencerBackendProvider);
    await backend.recoveryAbort();
    return jsonOk({'status': 'abort_requested'});
  }

  /// Push updated recovery defaults from a remote settings UI. All five
  /// fields are required; the Rust side validates positivity gates and
  /// returns a structured InvalidParameter on a non-positive interval /
  /// duration. We surface those via the existing translateHandlerErrors
  /// middleware.
  Future<Response> _handleSequencerUpdateRecoveryConfig(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/update-config');
    final payload = await readJsonObject(request);
    final retryIntervalSecs = requireDouble(payload, 'retryIntervalSecs');
    final maxDurationSecs = requireDouble(payload, 'maxDurationSecs');
    final stopTrackingDuringRecovery = requireBool(
      payload,
      'stopTrackingDuringRecovery',
    );
    final abortOnMeridian = requireBool(payload, 'abortOnMeridian');
    final audibleAlertWhenEntered = requireBool(
      payload,
      'audibleAlertWhenEntered',
    );

    final backend = container.read(sequencerBackendProvider);
    await backend.updateRecoveryConfig(
      retryIntervalSecs: retryIntervalSecs,
      maxDurationSecs: maxDurationSecs,
      stopTrackingDuringRecovery: stopTrackingDuringRecovery,
      abortOnMeridian: abortOnMeridian,
      audibleAlertWhenEntered: audibleAlertWhenEntered,
    );
    return jsonOk({'status': 'ok'});
  }

  /// GET — snapshot the current in-flight recovery context as a JSON
  /// string. Returns `{"context": null}` when not recovering and
  /// `{"context": "<json>"}` while recovering. The wrapped-string shape
  /// matches what `NetworkBackend.getCurrentRecoveryJson` expects.
  Future<Response> _handleSequencerGetCurrentRecovery(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final ctx = await backend.getCurrentRecoveryJson();
    return jsonOk({'context': ctx});
  }

  /// GET — dump every completed recovery loop in the current run. Returns
  /// `{"history": "<json-array-string>"}`. Empty array `[]` when no
  /// recoveries have completed yet.
  Future<Response> _handleSequencerGetRecoveryHistory(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final history = await backend.getRecoveryHistoryJson();
    return jsonOk({'history': history});
  }
}
