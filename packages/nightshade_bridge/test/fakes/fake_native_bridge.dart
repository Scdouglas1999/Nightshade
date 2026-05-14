// Test-only fake — never imported from `lib/`.

/// FakeNativeBridge — controllable test double for [NativeBridge].
///
/// # Design choices (audit-tests §6 / CQ-W5-FAKE-BRIDGE)
///
/// `NativeBridge` in `lib/src/bridge_stub.dart` is a class of `static` methods,
/// so there is no abstract interface to implement polymorphically. This fake
/// mirrors the public method *surface* as instance methods instead. Test code
/// that calls the real bridge as `NativeBridge.x(...)` must indirect through
/// a higher-level seam (e.g. `NightshadeBackend`) or be refactored to receive
/// this fake by injection. The widget-test harness landed in CQ-W5-WIDGET-HARNESS
/// is the primary consumer.
///
/// # Default-behavior contract
///
/// Every method has TWO sources of return data, checked in this order:
///
/// 1. `setError(name, ex)` was called → throws `ex` immediately. Use this to
///    drive sad-path widget tests (error banners, recovery flows).
/// 2. `setResponse(name, value)` was called → returns `value` cast to the
///    method's expected return type. A `TypeError` is thrown synchronously on
///    cast failure — explicit, NOT silent (CLAUDE.md "Errors are a feature").
/// 3. Otherwise → returns a permissive default: empty list, `false`, default
///    value for the return type. Defaults are documented per-method below.
///
/// We choose **permissive defaults** over throw-on-unconfigured because the
/// audit's stated goal is unblocking widget-test coverage of 100k+ LOC; most
/// tests care about ONE call and want everything else to fade into the
/// background. Tests that need strict verification can inspect [recordedCalls]
/// after each interaction.
///
/// # Event stream
///
/// One `StreamController<NightshadeEvent>.broadcast()` backs both [eventStream]
/// and [sequencerEventStream] (the latter filtered by `EventCategory.sequencer`).
/// Tests inject events via [emitEvent]; multiple listeners are supported.
///
/// # Call recording
///
/// Every public method appends a [_RecordedCall] to [recordedCalls] before
/// returning. Tests can assert call counts, ordering, and argument values.

import 'dart:async';
import 'dart:typed_data';

import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_bridge/src/bridge_stub.dart' as bridge_stub;

/// Record of a single method invocation against [FakeNativeBridge].
class FakeBridgeCall {
  /// Method name (matches the [NativeBridge] static method name).
  final String method;

  /// Positional + named arguments captured at call time, keyed by parameter name.
  /// Positional arguments use synthesized keys `arg0`, `arg1`, ...
  final Map<String, Object?> args;

  const FakeBridgeCall(this.method, this.args);

  @override
  String toString() => '$method($args)';
}

/// In-memory, deterministic stand-in for [NativeBridge]. See file header for
/// the contract.
class FakeNativeBridge {
  /// Canned responses, keyed by method name. Type cast happens at call site.
  final Map<String, Object?> _responses = {};

  /// Error injections, keyed by method name. When present, the method throws
  /// the stored object instead of returning.
  final Map<String, Object> _errors = {};

  /// All calls made against this fake, in invocation order.
  final List<FakeBridgeCall> recordedCalls = [];

  /// Broadcast controller backing [eventStream] and [sequencerEventStream].
  ///
  /// Broadcast (not single-subscription) because real `NativeBridge.eventStream()`
  /// returns a stream that multiple providers subscribe to (`GuideStatsNotifier`,
  /// `GuideGraphNotifier`, etc. per CLAUDE.md), and tests that wire several
  /// notifiers need the same semantics.
  final StreamController<NightshadeEvent> _events =
      StreamController<NightshadeEvent>.broadcast();

  /// Monotonic event-id counter used by [emitEvent] when the caller does not
  /// supply one explicitly.
  BigInt _nextEventId = BigInt.one;

  /// Set to true once [dispose] runs. Subsequent calls throw to surface
  /// teardown bugs in tests (e.g. notifier listening past widget disposal).
  bool _disposed = false;

  // ===========================================================================
  // Test API — configuration, injection, inspection
  // ===========================================================================

  /// Configure the value that [methodName] will return on its next (and every
  /// subsequent) invocation. Overwrites any prior response for the same name.
  void setResponse(String methodName, Object? value) {
    _ensureLive();
    _responses[methodName] = value;
  }

  /// Configure [methodName] to throw [error] on its next (and every
  /// subsequent) invocation. Use [clearError] to remove the injection.
  void setError(String methodName, Object error) {
    _ensureLive();
    _errors[methodName] = error;
  }

  /// Remove an error injection added by [setError]. Safe to call when none is
  /// configured.
  void clearError(String methodName) {
    _errors.remove(methodName);
  }

  /// Push [event] into [eventStream] (and [sequencerEventStream] if the event's
  /// category is `sequencer`). Synchronous w.r.t. the controller; listeners
  /// receive on the next microtask, matching real broadcast-stream semantics.
  void emitEvent(NightshadeEvent event) {
    _ensureLive();
    _events.add(event);
  }

  /// Convenience constructor for a minimal [NightshadeEvent]. Tests that only
  /// care about category/severity (e.g. checking that an error banner shows)
  /// don't have to build a full `EventPayload`.
  NightshadeEvent makeEvent({
    required EventCategory category,
    EventSeverity severity = EventSeverity.info,
    EventPayload? payload,
    String? deviceId,
    String? correlationId,
    BigInt? causedBy,
  }) {
    final id = _nextEventId;
    _nextEventId += BigInt.one;
    return NightshadeEvent(
      eventId: id,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: severity,
      category: category,
      payload: payload ??
          // SystemEvent.notification is the cheapest default payload — it's
          // accepted by EventPayload.system and carries free-form strings.
          EventPayload.system(
            SystemEvent.notification(
              title: 'fake',
              message: 'fake',
              level: severity.name,
            ),
          ),
      deviceId: deviceId,
      correlationId: correlationId,
      causedBy: causedBy,
    );
  }

  /// All calls whose [FakeBridgeCall.method] equals [methodName].
  List<FakeBridgeCall> callsTo(String methodName) =>
      recordedCalls.where((c) => c.method == methodName).toList(growable: false);

  /// Number of times [methodName] was invoked.
  int callCount(String methodName) =>
      recordedCalls.where((c) => c.method == methodName).length;

  /// Drop ALL recorded calls, responses, and errors. Resets event counter too.
  /// Does not close [eventStream] — use [dispose] for that.
  void reset() {
    _ensureLive();
    recordedCalls.clear();
    _responses.clear();
    _errors.clear();
    _nextEventId = BigInt.one;
  }

  /// Close the event stream. After dispose, any test method call throws
  /// [StateError]. Tests must invoke this in `tearDown`.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
  }

  // ===========================================================================
  // Mirrored NativeBridge API — see lib/src/bridge_stub.dart for canonical docs
  // ===========================================================================

  // --- Initialization / metadata ----------------------------------------------

  Future<void> init({String? logDirectory}) async {
    _record('init', {'logDirectory': logDirectory});
    _maybeThrow('init');
    // Permissive default: act as if the native bridge is now ready.
  }

  bool get isNativeAvailable {
    _record('isNativeAvailable', const {});
    _maybeThrow('isNativeAvailable');
    return _typed<bool>('isNativeAvailable', defaultValue: true);
  }

  String getNativeVersion() {
    _record('getNativeVersion', const {});
    _maybeThrow('getNativeVersion');
    return _typed<String>('getNativeVersion', defaultValue: '0.0.0-fake');
  }

  void invalidateDiscoveryCache() {
    _record('invalidateDiscoveryCache', const {});
    _maybeThrow('invalidateDiscoveryCache');
  }

  // --- Event streams ----------------------------------------------------------

  Stream<NightshadeEvent> eventStream() {
    _record('eventStream', const {});
    _maybeThrow('eventStream');
    return _events.stream;
  }

  Stream<NightshadeEvent> sequencerEventStream() {
    _record('sequencerEventStream', const {});
    _maybeThrow('sequencerEventStream');
    return _events.stream
        .where((event) => event.category == EventCategory.sequencer);
  }

  // --- Discovery / connection -------------------------------------------------

  Future<List<DeviceInfo>> apiDiscoverIndiAtAddress({
    required String host,
    required int port,
  }) async {
    _record(
      'apiDiscoverIndiAtAddress',
      {'host': host, 'port': port},
    );
    _maybeThrow('apiDiscoverIndiAtAddress');
    return _typed<List<DeviceInfo>>(
      'apiDiscoverIndiAtAddress',
      defaultValue: const <DeviceInfo>[],
    );
  }

  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
    _record('discoverDevices', {'deviceType': deviceType});
    _maybeThrow('discoverDevices');
    return _typed<List<DeviceInfo>>(
      'discoverDevices',
      defaultValue: const <DeviceInfo>[],
    );
  }

  Future<void> connectDevice(DeviceType deviceType, String deviceId) async {
    _record('connectDevice', {'deviceType': deviceType, 'deviceId': deviceId});
    _maybeThrow('connectDevice');
  }

  Future<void> disconnectDevice(DeviceType deviceType, String deviceId) async {
    _record(
      'disconnectDevice',
      {'deviceType': deviceType, 'deviceId': deviceId},
    );
    _maybeThrow('disconnectDevice');
  }

  Future<bool> isDeviceConnected(DeviceType deviceType, String deviceId) async {
    _record(
      'isDeviceConnected',
      {'deviceType': deviceType, 'deviceId': deviceId},
    );
    _maybeThrow('isDeviceConnected');
    return _typed<bool>('isDeviceConnected', defaultValue: false);
  }

  Future<List<DeviceInfo>> getConnectedDevices() async {
    _record('getConnectedDevices', const {});
    _maybeThrow('getConnectedDevices');
    return _typed<List<DeviceInfo>>(
      'getConnectedDevices',
      defaultValue: const <DeviceInfo>[],
    );
  }

  // --- Camera -----------------------------------------------------------------

  Future<CameraStatus> getCameraStatus(String deviceId) async {
    _record('getCameraStatus', {'deviceId': deviceId});
    _maybeThrow('getCameraStatus');
    return _typed<CameraStatus>(
      'getCameraStatus',
      defaultValue: _defaultCameraStatus,
    );
  }

  Future<void> setCameraCooler(
    String deviceId,
    bool enabled,
    double? targetTemp,
  ) async {
    _record(
      'setCameraCooler',
      {'deviceId': deviceId, 'enabled': enabled, 'targetTemp': targetTemp},
    );
    _maybeThrow('setCameraCooler');
  }

  Future<void> setCameraGain(String deviceId, int gain) async {
    _record('setCameraGain', {'deviceId': deviceId, 'gain': gain});
    _maybeThrow('setCameraGain');
  }

  Future<void> setCameraOffset(String deviceId, int offset) async {
    _record('setCameraOffset', {'deviceId': deviceId, 'offset': offset});
    _maybeThrow('setCameraOffset');
  }

  Future<void> setCameraBinning(String deviceId, int binX, int binY) async {
    _record(
      'setCameraBinning',
      {'deviceId': deviceId, 'binX': binX, 'binY': binY},
    );
    _maybeThrow('setCameraBinning');
  }

  Future<void> setReadoutMode({
    required String deviceId,
    required int modeIndex,
  }) async {
    _record(
      'setReadoutMode',
      {'deviceId': deviceId, 'modeIndex': modeIndex},
    );
    _maybeThrow('setReadoutMode');
  }

  Future<void> startExposure({
    required String deviceId,
    required double durationSecs,
    required int gain,
    required int offset,
    required int binX,
    required int binY,
  }) async {
    _record('startExposure', {
      'deviceId': deviceId,
      'durationSecs': durationSecs,
      'gain': gain,
      'offset': offset,
      'binX': binX,
      'binY': binY,
    });
    _maybeThrow('startExposure');
  }

  Future<void> cancelExposure(String deviceId) async {
    _record('cancelExposure', {'deviceId': deviceId});
    _maybeThrow('cancelExposure');
  }

  Future<CapturedImageResult?> getLastImage({required String deviceId}) async {
    _record('getLastImage', {'deviceId': deviceId});
    _maybeThrow('getLastImage');
    return _typed<CapturedImageResult?>(
      'getLastImage',
      // null is the documented "no image yet" return per bridge_stub.dart.
      defaultValue: null,
    );
  }

  // --- Mount ------------------------------------------------------------------

  Future<MountStatus> getMountStatus(String deviceId) async {
    _record('getMountStatus', {'deviceId': deviceId});
    _maybeThrow('getMountStatus');
    return _typed<MountStatus>(
      'getMountStatus',
      defaultValue: _defaultMountStatus,
    );
  }

  Future<void> mountSlewToCoordinates(
    String deviceId,
    double ra,
    double dec,
  ) async {
    _record(
      'mountSlewToCoordinates',
      {'deviceId': deviceId, 'ra': ra, 'dec': dec},
    );
    _maybeThrow('mountSlewToCoordinates');
  }

  Future<void> mountSync(String deviceId, double ra, double dec) async {
    _record('mountSync', {'deviceId': deviceId, 'ra': ra, 'dec': dec});
    _maybeThrow('mountSync');
  }

  Future<void> mountPark(String deviceId) async {
    _record('mountPark', {'deviceId': deviceId});
    _maybeThrow('mountPark');
  }

  Future<void> mountUnpark(String deviceId) async {
    _record('mountUnpark', {'deviceId': deviceId});
    _maybeThrow('mountUnpark');
  }

  Future<void> mountSetTracking(String deviceId, bool enabled) async {
    _record('mountSetTracking', {'deviceId': deviceId, 'enabled': enabled});
    _maybeThrow('mountSetTracking');
  }

  Future<void> mountPulseGuide(
    String deviceId,
    String direction,
    int durationMs,
  ) async {
    _record('mountPulseGuide', {
      'deviceId': deviceId,
      'direction': direction,
      'durationMs': durationMs,
    });
    _maybeThrow('mountPulseGuide');
  }

  Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    _record('mountSetTrackingRate', {'deviceId': deviceId, 'rate': rate});
    _maybeThrow('mountSetTrackingRate');
  }

  Future<int> mountGetTrackingRate(String deviceId) async {
    _record('mountGetTrackingRate', {'deviceId': deviceId});
    _maybeThrow('mountGetTrackingRate');
    // 0 == sidereal — matches TrackingRate.sidereal index in device.dart.
    return _typed<int>('mountGetTrackingRate', defaultValue: 0);
  }

  Future<void> mountMoveAxis(String deviceId, int axis, double rate) async {
    _record(
      'mountMoveAxis',
      {'deviceId': deviceId, 'axis': axis, 'rate': rate},
    );
    _maybeThrow('mountMoveAxis');
  }

  Future<void> mountSlewAltAz(
    String deviceId,
    double altitude,
    double azimuth,
  ) async {
    _record('mountSlewAltAz', {
      'deviceId': deviceId,
      'altitude': altitude,
      'azimuth': azimuth,
    });
    _maybeThrow('mountSlewAltAz');
  }

  Future<void> mountFindHome(String deviceId) async {
    _record('mountFindHome', {'deviceId': deviceId});
    _maybeThrow('mountFindHome');
  }

  Future<void> mountAbort(String deviceId) async {
    _record('mountAbort', {'deviceId': deviceId});
    _maybeThrow('mountAbort');
  }

  // --- Focuser ----------------------------------------------------------------

  Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    _record('getFocuserStatus', {'deviceId': deviceId});
    _maybeThrow('getFocuserStatus');
    return _typed<FocuserStatus>(
      'getFocuserStatus',
      defaultValue: _defaultFocuserStatus,
    );
  }

  Future<void> focuserMoveTo(String deviceId, int position) async {
    _record('focuserMoveTo', {'deviceId': deviceId, 'position': position});
    _maybeThrow('focuserMoveTo');
  }

  Future<void> focuserMoveRelative(String deviceId, int delta) async {
    _record('focuserMoveRelative', {'deviceId': deviceId, 'delta': delta});
    _maybeThrow('focuserMoveRelative');
  }

  Future<void> apiFocuserHalt({required String deviceId}) async {
    _record('apiFocuserHalt', {'deviceId': deviceId});
    _maybeThrow('apiFocuserHalt');
  }

  // --- Filter wheel -----------------------------------------------------------

  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    _record('getFilterWheelStatus', {'deviceId': deviceId});
    _maybeThrow('getFilterWheelStatus');
    return _typed<FilterWheelStatus>(
      'getFilterWheelStatus',
      defaultValue: _defaultFilterWheelStatus,
    );
  }

  Future<void> filterWheelSetPosition(String deviceId, int position) async {
    _record(
      'filterWheelSetPosition',
      {'deviceId': deviceId, 'position': position},
    );
    _maybeThrow('filterWheelSetPosition');
  }

  Future<void> apiFilterwheelSetPosition({
    required String deviceId,
    required int position,
  }) async {
    _record(
      'apiFilterwheelSetPosition',
      {'deviceId': deviceId, 'position': position},
    );
    _maybeThrow('apiFilterwheelSetPosition');
  }

  Future<List<String>> apiFilterwheelGetNames({required String deviceId}) async {
    _record('apiFilterwheelGetNames', {'deviceId': deviceId});
    _maybeThrow('apiFilterwheelGetNames');
    return _typed<List<String>>(
      'apiFilterwheelGetNames',
      defaultValue: const <String>[],
    );
  }

  Future<void> apiFilterwheelSetByName({
    required String deviceId,
    required String name,
  }) async {
    _record(
      'apiFilterwheelSetByName',
      {'deviceId': deviceId, 'name': name},
    );
    _maybeThrow('apiFilterwheelSetByName');
  }

  // --- Rotator ----------------------------------------------------------------

  Future<void> apiRotatorMoveTo({
    required String deviceId,
    required double angle,
  }) async {
    _record('apiRotatorMoveTo', {'deviceId': deviceId, 'angle': angle});
    _maybeThrow('apiRotatorMoveTo');
  }

  Future<void> apiRotatorMoveRelative({
    required String deviceId,
    required double delta,
  }) async {
    _record(
      'apiRotatorMoveRelative',
      {'deviceId': deviceId, 'delta': delta},
    );
    _maybeThrow('apiRotatorMoveRelative');
  }

  Future<RotatorStatus> apiGetRotatorStatus({required String deviceId}) async {
    _record('apiGetRotatorStatus', {'deviceId': deviceId});
    _maybeThrow('apiGetRotatorStatus');
    return _typed<RotatorStatus>(
      'apiGetRotatorStatus',
      defaultValue: _defaultRotatorStatus,
    );
  }

  Future<void> apiRotatorHalt({required String deviceId}) async {
    _record('apiRotatorHalt', {'deviceId': deviceId});
    _maybeThrow('apiRotatorHalt');
  }

  Future<void> apiRotatorSyncToPa({
    required String deviceId,
    required double pa,
  }) async {
    _record('apiRotatorSyncToPa', {'deviceId': deviceId, 'pa': pa});
    _maybeThrow('apiRotatorSyncToPa');
  }

  // --- Session ----------------------------------------------------------------

  Future<bridge_stub.NativeSessionState> getSessionState() async {
    _record('getSessionState', const {});
    _maybeThrow('getSessionState');
    return _typed<bridge_stub.NativeSessionState>(
      'getSessionState',
      defaultValue: _defaultSessionState,
    );
  }

  Future<void> startSession({
    String? targetName,
    double? ra,
    double? dec,
  }) async {
    _record('startSession', {
      'targetName': targetName,
      'ra': ra,
      'dec': dec,
    });
    _maybeThrow('startSession');
  }

  Future<void> endSession() async {
    _record('endSession', const {});
    _maybeThrow('endSession');
  }

  // --- Plate solving ----------------------------------------------------------

  bool isPlateSolverAvailable() {
    _record('isPlateSolverAvailable', const {});
    _maybeThrow('isPlateSolverAvailable');
    return _typed<bool>('isPlateSolverAvailable', defaultValue: false);
  }

  String? getPlateSolverPath() {
    _record('getPlateSolverPath', const {});
    _maybeThrow('getPlateSolverPath');
    return _typed<String?>('getPlateSolverPath', defaultValue: null);
  }

  Future<PlateSolveResult> plateSolveBlind(String filePath) async {
    _record('plateSolveBlind', {'filePath': filePath});
    _maybeThrow('plateSolveBlind');
    // No sensible permissive default for a solve result — tests must inject.
    return _requiredResponse<PlateSolveResult>('plateSolveBlind');
  }

  Future<PlateSolveResult> plateSolveNear(
    String filePath,
    double hintRa,
    double hintDec,
    double searchRadius,
  ) async {
    _record('plateSolveNear', {
      'filePath': filePath,
      'hintRa': hintRa,
      'hintDec': hintDec,
      'searchRadius': searchRadius,
    });
    _maybeThrow('plateSolveNear');
    return _requiredResponse<PlateSolveResult>('plateSolveNear');
  }

  // --- Autofocus --------------------------------------------------------------

  Future<AutofocusResultApi> apiRunAutofocus({
    required String deviceId,
    required String cameraId,
    required AutofocusConfigApi config,
  }) async {
    _record('apiRunAutofocus', {
      'deviceId': deviceId,
      'cameraId': cameraId,
      'config': config,
    });
    _maybeThrow('apiRunAutofocus');
    return _requiredResponse<AutofocusResultApi>('apiRunAutofocus');
  }

  Future<void> apiCancelAutofocus() async {
    _record('apiCancelAutofocus', const {});
    _maybeThrow('apiCancelAutofocus');
  }

  // --- PHD2 / Guider ----------------------------------------------------------

  Future<bool> isPhd2Running({String host = 'localhost', int port = 4400}) async {
    _record('isPhd2Running', {'host': host, 'port': port});
    _maybeThrow('isPhd2Running');
    return _typed<bool>('isPhd2Running', defaultValue: false);
  }

  Future<void> phd2Connect({String? host, int? port}) async {
    _record('phd2Connect', {'host': host, 'port': port});
    _maybeThrow('phd2Connect');
  }

  Future<void> phd2Disconnect() async {
    _record('phd2Disconnect', const {});
    _maybeThrow('phd2Disconnect');
  }

  Future<void> phd2StartGuiding({
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    _record('phd2StartGuiding', {
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
    _maybeThrow('phd2StartGuiding');
  }

  Future<void> phd2StopGuiding() async {
    _record('phd2StopGuiding', const {});
    _maybeThrow('phd2StopGuiding');
  }

  Future<void> phd2PauseGuiding() async {
    _record('phd2PauseGuiding', const {});
    _maybeThrow('phd2PauseGuiding');
  }

  Future<void> phd2ResumeGuiding() async {
    _record('phd2ResumeGuiding', const {});
    _maybeThrow('phd2ResumeGuiding');
  }

  Future<void> phd2Dither({
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    _record('phd2Dither', {
      'amount': amount,
      'raOnly': raOnly,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
    _maybeThrow('phd2Dither');
  }

  Future<Phd2Status> phd2GetStatus() async {
    _record('phd2GetStatus', const {});
    _maybeThrow('phd2GetStatus');
    return _typed<Phd2Status>(
      'phd2GetStatus',
      defaultValue: _defaultPhd2Status,
    );
  }

  Future<void> guiderStartGuiding({
    required String deviceId,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    _record('guiderStartGuiding', {
      'deviceId': deviceId,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
    _maybeThrow('guiderStartGuiding');
  }

  Future<void> guiderStop({required String deviceId}) async {
    _record('guiderStop', {'deviceId': deviceId});
    _maybeThrow('guiderStop');
  }

  Future<void> guiderDither({
    required String deviceId,
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    _record('guiderDither', {
      'deviceId': deviceId,
      'amount': amount,
      'raOnly': raOnly,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
    _maybeThrow('guiderDither');
  }

  Future<void> guiderLoop({required String deviceId}) async {
    _record('guiderLoop', {'deviceId': deviceId});
    _maybeThrow('guiderLoop');
  }

  Future<(double, double)> guiderFindStar({required String deviceId}) async {
    _record('guiderFindStar', {'deviceId': deviceId});
    _maybeThrow('guiderFindStar');
    return _typed<(double, double)>(
      'guiderFindStar',
      defaultValue: const (0.0, 0.0),
    );
  }

  Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  }) async {
    _record('guiderSetLockPosition', {
      'deviceId': deviceId,
      'x': x,
      'y': y,
      'exact': exact,
    });
    _maybeThrow('guiderSetLockPosition');
  }

  Future<(double, double)> guiderGetLockPosition({
    required String deviceId,
  }) async {
    _record('guiderGetLockPosition', {'deviceId': deviceId});
    _maybeThrow('guiderGetLockPosition');
    return _typed<(double, double)>(
      'guiderGetLockPosition',
      defaultValue: const (0.0, 0.0),
    );
  }

  Future<void> guiderDeselectStar({required String deviceId}) async {
    _record('guiderDeselectStar', {'deviceId': deviceId});
    _maybeThrow('guiderDeselectStar');
  }

  Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  }) async {
    _record('guiderGetStarImage', {'deviceId': deviceId, 'size': size});
    _maybeThrow('guiderGetStarImage');
    return _requiredResponse<Phd2StarImage>('guiderGetStarImage');
  }

  // --- Built-in guider config -------------------------------------------------

  Future<Map<String, dynamic>> builtinGuiderGetConfigRaw() async {
    _record('builtinGuiderGetConfigRaw', const {});
    _maybeThrow('builtinGuiderGetConfigRaw');
    return _typed<Map<String, dynamic>>(
      'builtinGuiderGetConfigRaw',
      defaultValue: const <String, dynamic>{},
    );
  }

  Future<void> builtinGuiderSetConfigRaw({
    required double exposureSecs,
    required int gain,
    required int offset,
    required int binning,
    required int calibrationMs,
    required int settleSleepMs,
    required double minPulseMs,
    required double maxPulseMs,
  }) async {
    _record('builtinGuiderSetConfigRaw', {
      'exposureSecs': exposureSecs,
      'gain': gain,
      'offset': offset,
      'binning': binning,
      'calibrationMs': calibrationMs,
      'settleSleepMs': settleSleepMs,
      'minPulseMs': minPulseMs,
      'maxPulseMs': maxPulseMs,
    });
    _maybeThrow('builtinGuiderSetConfigRaw');
  }

  // --- Sequencer --------------------------------------------------------------

  Future<void> sequencerSubscribeEvents() async {
    _record('sequencerSubscribeEvents', const {});
    _maybeThrow('sequencerSubscribeEvents');
  }

  Future<void> sequencerLoadJson(String json) async {
    _record('sequencerLoadJson', {'json': json});
    _maybeThrow('sequencerLoadJson');
  }

  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    _record('sequencerSetDevices', {
      'cameraId': cameraId,
      'mountId': mountId,
      'focuserId': focuserId,
      'filterwheelId': filterwheelId,
      'rotatorId': rotatorId,
      'filterNames': filterNames,
      'filterFocusOffsets': filterFocusOffsets,
    });
    _maybeThrow('sequencerSetDevices');
  }

  Future<void> sequencerSetSafetyFailMode(String mode) async {
    _record('sequencerSetSafetyFailMode', {'mode': mode});
    _maybeThrow('sequencerSetSafetyFailMode');
  }

  Future<void> sequencerSetSavePath({String? path}) async {
    _record('sequencerSetSavePath', {'path': path});
    _maybeThrow('sequencerSetSavePath');
  }

  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    _record('sequencerUpdateDitherConfig', {
      'pixels': pixels,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
      'raOnly': raOnly,
    });
    _maybeThrow('sequencerUpdateDitherConfig');
  }

  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    _record(
      'sequencerUpdateLocation',
      {'latitude': latitude, 'longitude': longitude},
    );
    _maybeThrow('sequencerUpdateLocation');
  }

  Future<void> sequencerUpdateFilterOffsets({
    required Map<String, int> offsets,
  }) async {
    _record('sequencerUpdateFilterOffsets', {'offsets': offsets});
    _maybeThrow('sequencerUpdateFilterOffsets');
  }

  Future<void> sequencerStart() async {
    _record('sequencerStart', const {});
    _maybeThrow('sequencerStart');
  }

  Future<void> sequencerPause() async {
    _record('sequencerPause', const {});
    _maybeThrow('sequencerPause');
  }

  Future<void> sequencerResume() async {
    _record('sequencerResume', const {});
    _maybeThrow('sequencerResume');
  }

  Future<void> sequencerStop() async {
    _record('sequencerStop', const {});
    _maybeThrow('sequencerStop');
  }

  Future<void> sequencerSkip() async {
    _record('sequencerSkip', const {});
    _maybeThrow('sequencerSkip');
  }

  Future<void> sequencerReset() async {
    _record('sequencerReset', const {});
    _maybeThrow('sequencerReset');
  }

  bridge_stub.SequencerState getSequencerState() {
    _record('getSequencerState', const {});
    _maybeThrow('getSequencerState');
    return _typed<bridge_stub.SequencerState>(
      'getSequencerState',
      defaultValue: bridge_stub.SequencerState.idle,
    );
  }

  Future<void> sequencerSetSimulationMode(bool enabled) async {
    _record('sequencerSetSimulationMode', {'enabled': enabled});
    _maybeThrow('sequencerSetSimulationMode');
  }

  bool isSimulationMode() {
    _record('isSimulationMode', const {});
    _maybeThrow('isSimulationMode');
    return _typed<bool>('isSimulationMode', defaultValue: false);
  }

  Future<bridge_stub.SequencerStatus> sequencerGetStatus() async {
    _record('sequencerGetStatus', const {});
    _maybeThrow('sequencerGetStatus');
    return _typed<bridge_stub.SequencerStatus>(
      'sequencerGetStatus',
      defaultValue: _defaultSequencerStatus,
    );
  }

  // --- Checkpoints ------------------------------------------------------------

  Future<void> sequencerSetCheckpointDir(String path) async {
    _record('sequencerSetCheckpointDir', {'path': path});
    _maybeThrow('sequencerSetCheckpointDir');
  }

  Future<bool> sequencerHasCheckpoint() async {
    _record('sequencerHasCheckpoint', const {});
    _maybeThrow('sequencerHasCheckpoint');
    return _typed<bool>('sequencerHasCheckpoint', defaultValue: false);
  }

  Future<CheckpointInfoApi?> sequencerGetCheckpointInfo() async {
    _record('sequencerGetCheckpointInfo', const {});
    _maybeThrow('sequencerGetCheckpointInfo');
    return _typed<CheckpointInfoApi?>(
      'sequencerGetCheckpointInfo',
      defaultValue: null,
    );
  }

  Future<void> sequencerResumeFromCheckpoint() async {
    _record('sequencerResumeFromCheckpoint', const {});
    _maybeThrow('sequencerResumeFromCheckpoint');
  }

  Future<void> sequencerDiscardCheckpoint() async {
    _record('sequencerDiscardCheckpoint', const {});
    _maybeThrow('sequencerDiscardCheckpoint');
  }

  Future<void> sequencerSaveCheckpoint() async {
    _record('sequencerSaveCheckpoint', const {});
    _maybeThrow('sequencerSaveCheckpoint');
  }

  // --- Profiles ---------------------------------------------------------------

  Future<List<EquipmentProfile>> apiGetProfiles() async {
    _record('apiGetProfiles', const {});
    _maybeThrow('apiGetProfiles');
    return _typed<List<EquipmentProfile>>(
      'apiGetProfiles',
      defaultValue: const <EquipmentProfile>[],
    );
  }

  Future<void> apiSaveProfile({required EquipmentProfile profile}) async {
    _record('apiSaveProfile', {'profile': profile});
    _maybeThrow('apiSaveProfile');
  }

  Future<void> apiDeleteProfile({required String profileId}) async {
    _record('apiDeleteProfile', {'profileId': profileId});
    _maybeThrow('apiDeleteProfile');
  }

  Future<void> apiLoadProfile({required String profileId}) async {
    _record('apiLoadProfile', {'profileId': profileId});
    _maybeThrow('apiLoadProfile');
  }

  Future<EquipmentProfile?> apiGetActiveProfile() async {
    _record('apiGetActiveProfile', const {});
    _maybeThrow('apiGetActiveProfile');
    return _typed<EquipmentProfile?>(
      'apiGetActiveProfile',
      defaultValue: null,
    );
  }

  // --- Settings & location ----------------------------------------------------

  Future<void> apiInitProfileStorage({required String storagePath}) async {
    _record('apiInitProfileStorage', {'storagePath': storagePath});
    _maybeThrow('apiInitProfileStorage');
  }

  Future<void> apiInitSettingsStorage({required String storagePath}) async {
    _record('apiInitSettingsStorage', {'storagePath': storagePath});
    _maybeThrow('apiInitSettingsStorage');
  }

  Future<AppSettings> apiGetSettings() async {
    _record('apiGetSettings', const {});
    _maybeThrow('apiGetSettings');
    return _requiredResponse<AppSettings>('apiGetSettings');
  }

  Future<void> apiUpdateSettings({required AppSettings settings}) async {
    _record('apiUpdateSettings', {'settings': settings});
    _maybeThrow('apiUpdateSettings');
  }

  Future<ObserverLocation?> apiGetLocation() async {
    _record('apiGetLocation', const {});
    _maybeThrow('apiGetLocation');
    return _typed<ObserverLocation?>('apiGetLocation', defaultValue: null);
  }

  Future<void> apiSetLocation({ObserverLocation? location}) async {
    _record('apiSetLocation', {'location': location});
    _maybeThrow('apiSetLocation');
  }

  // --- Image processing -------------------------------------------------------

  Future<bridge_stub.ImageStats> apiGetImageStats({
    required int width,
    required int height,
    required Uint16List data,
  }) async {
    _record(
      'apiGetImageStats',
      {'width': width, 'height': height, 'dataLength': data.length},
    );
    _maybeThrow('apiGetImageStats');
    return _typed<bridge_stub.ImageStats>(
      'apiGetImageStats',
      defaultValue: _defaultImageStats,
    );
  }

  Future<Uint8List> apiAutoStretchImage({
    required int width,
    required int height,
    required Uint16List data,
  }) async {
    _record(
      'apiAutoStretchImage',
      {'width': width, 'height': height, 'dataLength': data.length},
    );
    _maybeThrow('apiAutoStretchImage');
    return _typed<Uint8List>(
      'apiAutoStretchImage',
      // Empty Uint8List signals "no display data yet" — the imaging panel
      // already treats zero-length pixel buffers as a degenerate state.
      defaultValue: Uint8List(0),
    );
  }

  Future<Uint8List> apiDebayerImage({
    required int width,
    required int height,
    required Uint16List data,
    required String patternStr,
    required String algoStr,
  }) async {
    _record('apiDebayerImage', {
      'width': width,
      'height': height,
      'dataLength': data.length,
      'patternStr': patternStr,
      'algoStr': algoStr,
    });
    _maybeThrow('apiDebayerImage');
    return _typed<Uint8List>('apiDebayerImage', defaultValue: Uint8List(0));
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  void _record(String method, Map<String, Object?> args) {
    _ensureLive();
    recordedCalls.add(FakeBridgeCall(method, args));
  }

  void _maybeThrow(String method) {
    final injected = _errors[method];
    if (injected != null) {
      // ignore: only_throw_errors
      throw injected;
    }
  }

  /// Return `responses[method]` cast to [T], or [defaultValue] when no canned
  /// response is registered. Throws `TypeError` on cast mismatch so tests fail
  /// loudly per CLAUDE.md ("Errors are a feature").
  T _typed<T>(String method, {required T defaultValue}) {
    if (!_responses.containsKey(method)) return defaultValue;
    return _responses[method] as T;
  }

  /// Variant for methods with no sensible permissive default (e.g. plate-solve
  /// results). Throws [StateError] with a remediation hint if the test forgot
  /// to wire a response — explicit failure beats a silent fallback.
  T _requiredResponse<T>(String method) {
    if (!_responses.containsKey(method)) {
      throw StateError(
        'FakeNativeBridge: no canned response for "$method". '
        'Call setResponse("$method", ...) in the test before invoking it.',
      );
    }
    return _responses[method] as T;
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError(
        'FakeNativeBridge used after dispose(). Tests must not call methods '
        'after tearDown closes the fake.',
      );
    }
  }

  // ===========================================================================
  // Permissive default values
  // ===========================================================================
  //
  // These mirror the "disconnected, idle, all-capabilities-true" defaults
  // bridge_stub.dart installs via _initializeDefaultStates, which is what
  // every widget test sees when the user hasn't configured anything.

  static const CameraStatus _defaultCameraStatus = CameraStatus(
    connected: false,
    state: CameraState.idle,
    sensorTemp: 20.0,
    coolerPower: 0.0,
    targetTemp: -10.0,
    coolerOn: false,
    gain: 100,
    offset: 10,
    binX: 1,
    binY: 1,
    sensorWidth: 4144,
    sensorHeight: 2822,
    pixelSizeX: 3.76,
    pixelSizeY: 3.76,
    maxAdu: 65535,
    canCool: true,
    canSetGain: true,
    canSetOffset: true,
  );

  static const MountStatus _defaultMountStatus = MountStatus(
    connected: false,
    tracking: false,
    slewing: false,
    parked: true,
    atHome: false,
    sideOfPier: PierSide.unknown,
    rightAscension: 0.0,
    declination: 0.0,
    altitude: 0.0,
    azimuth: 0.0,
    siderealTime: 0.0,
    trackingRate: TrackingRate.sidereal,
    canPark: true,
    canSlew: true,
    canSync: true,
    canPulseGuide: true,
    canSetTrackingRate: true,
    availability: <String, FieldAvailability>{},
  );

  static const FocuserStatus _defaultFocuserStatus = FocuserStatus(
    connected: false,
    position: 25000,
    moving: false,
    temperature: 20.0,
    maxPosition: 50000,
    stepSize: 1.0,
    isAbsolute: true,
    hasTemperature: true,
  );

  static const FilterWheelStatus _defaultFilterWheelStatus = FilterWheelStatus(
    connected: false,
    position: 0,
    moving: false,
    filterCount: 7,
    filterNames: <String>['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'],
  );

  static const RotatorStatus _defaultRotatorStatus = RotatorStatus(
    connected: false,
    position: 0.0,
    moving: false,
    mechanicalPosition: 0.0,
    isMoving: false,
    canReverse: true,
  );

  static final bridge_stub.NativeSessionState _defaultSessionState =
      bridge_stub.NativeSessionState(
    isActive: false,
    totalExposures: 0,
    completedExposures: 0,
    totalIntegrationSecs: 0.0,
    isGuiding: false,
    isCapturing: false,
    isDithering: false,
  );

  static const Phd2Status _defaultPhd2Status = Phd2Status(
    connected: false,
    state: 'Disconnected',
    rmsRa: 0,
    rmsDec: 0,
    rmsTotal: 0,
    snr: 0,
    starMass: 0,
    pixelScale: 0,
  );

  static final bridge_stub.SequencerStatus _defaultSequencerStatus =
      bridge_stub.SequencerStatus(
    state: 'idle',
    progress: 0.0,
  );

  static final bridge_stub.ImageStats _defaultImageStats = bridge_stub.ImageStats(
    min: 0,
    max: 0,
    mean: 0,
    median: 0,
    stdDev: 0,
    mad: 0,
  );
}
