part of '../guiding_provider.dart';

/// Controller to manage PHD2 connection and state updates
final phd2ControllerProvider = Provider<Phd2Controller>((ref) {
  final backend = ref.watch(backendProvider);
  final controller = Phd2Controller(ref, backend);
  ref.onDispose(() => controller.dispose());
  return controller;
});

class Phd2Controller {
  final Ref ref;
  final NightshadeBackend backend;
  StreamSubscription? _eventSub;
  bool _disposed = false;
  LoggingService get _logger => ref.read(loggingServiceProvider);

  Phd2Controller(this.ref, this.backend) {
    _init();
  }

  /// PHD2 closed externally (EOF) or bridge published [Disconnected].
  void _handlePhd2LinkLost() {
    ref.read(phd2StateProvider.notifier).state = Phd2State.stopped;
    unawaited(_syncPhd2BackendAfterLinkLost());
    ref.read(guiderStateProvider.notifier).setDisconnected();
  }

  /// Clear Rust registration/storage so status polls and device lists match UI.
  Future<void> _syncPhd2BackendAfterLinkLost() async {
    try {
      await backend.phd2Disconnect();
    } catch (e, st) {
      _logger.debug(
        'PHD2 backend cleanup after link loss: $e\n$st',
        source: 'Phd2Controller',
      );
    }
  }

  void _init() {
    // Listen to backend events
    _eventSub = backend.eventStream.listen((event) {
      if (event.category != EventCategory.guiding) return;
      if (_disposed) return;

      _logger.debug('Received guiding event: ${event.eventType}',
          source: 'Phd2Controller');

      // Update the main GuiderState used by the UI
      final guiderNotifier = ref.read(guiderStateProvider.notifier);

      switch (event.eventType) {
        case 'Connected':
          ref.read(guiderStateProvider.notifier).setConnected();
          break;
        case 'Disconnected':
          _handlePhd2LinkLost();
          return;
        case 'AppState':
          _updateStateFromString(event.data['State']);
          break;
        case 'GuideStep':
          _logger.debug('Processing GuideStep event', source: 'Phd2Controller');
          _handleGuideStep(event.data);
          break;
        case 'GuideStats':
          _logger.debug('Processing GuideStats event',
              source: 'Phd2Controller');
          _handleGuideStats(event.data);
          break;
        case 'GuidingStarted':
          ref.read(phd2StateProvider.notifier).state = Phd2State.guiding;
          guiderNotifier.setGuiding(true);
          break;
        case 'GuidingStopped':
          ref.read(phd2StateProvider.notifier).state = Phd2State.stopped;
          guiderNotifier.setGuiding(false);
          break;
        case 'Paused':
          ref.read(phd2StateProvider.notifier).state = Phd2State.paused;
          break;
        case 'Resumed':
          ref.read(phd2StateProvider.notifier).state = Phd2State.guiding;
          guiderNotifier.setGuiding(true);
          break;
        case 'StarLost':
          ref.read(phd2StateProvider.notifier).state = Phd2State.lostLock;
          _handleStarLost();
          break;
        case 'Settling':
          ref.read(phd2StateProvider.notifier).state = Phd2State.settling;
          break;
        case 'SettleDone':
          // Settle complete - return to guiding state
          ref.read(phd2StateProvider.notifier).state = Phd2State.guiding;
          _logger.info('Settle complete', source: 'PHD2');
          break;
        case 'LoopingExposures':
          ref.read(phd2StateProvider.notifier).state = Phd2State.looping;
          break;
        case 'Calibrating':
          ref.read(phd2StateProvider.notifier).state = Phd2State.calibrating;
          break;
        case 'CalibrationComplete':
          _logger.info('Calibration complete', source: 'PHD2');
          final calibrationNotifier =
              ref.read(calibrationStateProvider.notifier);
          if (calibrationNotifier.mounted) {
            unawaited(calibrationNotifier.refreshCalibrationData());
          }
          break;
        // Note: StarSelected is handled by LockPositionNotifier's own event listener
      }

      // Liveness traffic only — never promote back to connected after Disconnected.
      if (isPhd2GuidingHeartbeatEvent(event.eventType) &&
          ref.read(guiderStateProvider).connectionState !=
              DeviceConnectionState.connected) {
        guiderNotifier.setConnected();
      }
    }, onError: (err) {
      _logger.error('Controller Event Error: $err', source: 'PHD2');
      _handlePhd2LinkLost();
    });
  }

  void _updateStateFromString(String? stateStr) {
    if (stateStr == null) return;

    Phd2State state;
    switch (stateStr) {
      case 'Stopped':
        state = Phd2State.stopped;
        break;
      case 'Selected':
        state = Phd2State.selected;
        break;
      case 'Calibrating':
        state = Phd2State.calibrating;
        break;
      case 'Guiding':
        state = Phd2State.guiding;
        break;
      case 'LostLock':
        state = Phd2State.lostLock;
        break;
      case 'Paused':
        state = Phd2State.paused;
        break;
      case 'Looping':
        state = Phd2State.looping;
        break;
      default:
        state = Phd2State.stopped;
    }

    ref.read(phd2StateProvider.notifier).state = state;

    // Update UI provider
    final guiderNotifier = ref.read(guiderStateProvider.notifier);
    guiderNotifier.setGuiding(state == Phd2State.guiding);
  }

  void _handleGuideStep(Map<String, dynamic> json) {
    // GuideStatsNotifier handles the proper rolling RMS calculation
    // Just update the UI state provider with the current stats
    final stats = ref.read(guideStatsProvider);

    ref.read(guiderStateProvider.notifier).updateRms(
          stats.rmsRa,
          stats.rmsDec,
          stats.rmsTotal,
        );
  }

  void _handleGuideStats(Map<String, dynamic> json) {
    // Update SNR and star mass from GuideStats event
    final snr = (json['SNR'] ?? 0).toDouble();
    final starMass = (json['StarMass'] ?? 0).toDouble();

    // Update the guide stats provider with SNR and star mass
    ref.read(guideStatsProvider.notifier).updateStarData(snr, starMass);
  }

  void _handleStarLost() {
    // Record the event timestamp
    ref.read(starLostEventProvider.notifier).state = DateTime.now();

    // Update UI state
    final guiderNotifier = ref.read(guiderStateProvider.notifier);
    guiderNotifier.setGuiding(false);

    // Log the event
    _logger.warning('Guide star lost! Guiding paused.', source: 'PHD2');

    // Note: The sequencer can monitor starLostEventProvider to pause/abort
    // or implement automatic recovery logic. Currently this path notifies only; automatic recovery is tracked separately.
    // Future enhancement: Could trigger automatic recovery attempt after delay
  }

  Future<void> connect(String host, int port) async {
    if (backend is FfiBackend) {
      // Desktop owns launch + socket connect via DeviceService (polls port,
      // uses configured path or Rust registry discovery).
      await ref.read(deviceServiceProvider).connectGuider('phd2_guider');
      return;
    }

    const deviceId = 'phd2_guider';
    ref
        .read(guiderStateProvider.notifier)
        .setConnecting(deviceId, 'Connecting to PHD2');
    try {
      // Remote companions delegate launch + socket connect to the imaging host
      // via POST /api/phd2/connect. Never spawn PHD2 locally on mobile.
      await backend.phd2Connect(host: host, port: port);
      final status = await pollPhd2Connected(backend);
      if (!status.connected) {
        throw StateError(
          'Imaging host did not report a PHD2 connection after connect request.',
        );
      }
      ref.read(guiderStateProvider.notifier).setConnected();
    } catch (e) {
      _logger.error('Failed to connect to PHD2 at $host:$port: $e',
          source: 'PHD2');
      ref.read(guiderStateProvider.notifier).setDisconnected();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await backend.phd2Disconnect();
    ref.read(phd2StateProvider.notifier).state = Phd2State.stopped;
    ref.read(guiderStateProvider.notifier).setDisconnected();
  }

  Future<void> startGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderStartGuiding(
      deviceId: guiderId,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  Future<void> stopGuiding() async {
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderStopGuiding(deviceId: guiderId);
  }

  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderDither(
      deviceId: guiderId,
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  /// Start looping exposures without guiding
  Future<void> loop() async {
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderLoop(deviceId: guiderId);
  }

  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
  }
}
