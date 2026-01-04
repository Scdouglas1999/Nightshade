import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' hide EventCategory, Phd2GuideStats, Phd2StarImage, Phd2CalibrationData;
import '../backend/nightshade_backend.dart';
import '../models/equipment/equipment_models.dart';
import '../models/phd2_models.dart';
import 'backend_provider.dart';
import 'equipment_provider.dart';

/// Provider for PHD2 connection status - derived from guiderStateProvider
/// This is a computed provider that automatically stays in sync
final phd2ConnectedProvider = Provider<bool>((ref) {
  final guiderState = ref.watch(guiderStateProvider);
  return guiderState.connectionState == DeviceConnectionState.connected;
});

/// Provider for PHD2 state (Guiding, Stopped, etc.)
final phd2StateProvider = StateProvider<Phd2State>((ref) => Phd2State.stopped);

/// Provider for star lost events (timestamp of last star lost event)
final starLostEventProvider = StateProvider<DateTime?>((ref) => null);

/// Provider for current guide stats with rolling RMS calculation
final guideStatsProvider = StateNotifierProvider<GuideStatsNotifier, Phd2GuideStats>((ref) {
  return GuideStatsNotifier(ref);
});

/// Notifier that maintains rolling RMS statistics
class GuideStatsNotifier extends StateNotifier<Phd2GuideStats> {
  final Ref ref;
  StreamSubscription? _sub;

  // Rolling RMS calculators for accurate statistics
  final _rmsRaCalculator = RollingRmsCalculator(windowSize: 100);
  final _rmsDecCalculator = RollingRmsCalculator(windowSize: 100);
  int _frameCount = 0;

  GuideStatsNotifier(this.ref)
      : super(Phd2GuideStats(
          rmsRa: 0,
          rmsDec: 0,
          rmsTotal: 0,
          snr: 0,
          starMass: 0,
          frameCount: 0,
        )) {
    _init();
  }

  void _init() {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (event.category == EventCategory.guiding) {
        if (event.eventType == 'GuideStep') {
          _handleGuideStep(event.data);
        } else if (event.eventType == 'GuidingStopped') {
          reset();
        }
      }
    });
  }

  void _handleGuideStep(Map<String, dynamic> json) {
    // Get raw distance values from PHD2
    final raDistance = (json['RADistanceRaw'] ?? 0).toDouble();
    final decDistance = (json['DECDistanceRaw'] ?? 0).toDouble();

    // Add values to rolling RMS calculators
    _rmsRaCalculator.add(raDistance);
    _rmsDecCalculator.add(decDistance);
    _frameCount++;

    // Calculate proper RMS using rolling window
    // Formula: sqrt(mean(x²)) for each axis
    final rmsRa = _rmsRaCalculator.rms;
    final rmsDec = _rmsDecCalculator.rms;

    // Total RMS is pythagorean combination of RA and Dec RMS
    var rmsTotal = math.sqrt(rmsRa * rmsRa + rmsDec * rmsDec);

    // PHD2 also sends cumulative RMS in AvgDist - prefer our calculation
    // but fall back to PHD2's value if our window is small
    if (_rmsRaCalculator.count < 10) {
      final avgDist = json['AvgDist'];
      if (avgDist != null) {
        rmsTotal = avgDist.toDouble();
      }
    }

    state = Phd2GuideStats(
      rmsRa: rmsRa,
      rmsDec: rmsDec,
      rmsTotal: rmsTotal,
      snr: (json['SNR'] ?? 0).toDouble(),
      starMass: (json['StarMass'] ?? 0).toDouble(),
      frameCount: _frameCount,
    );
  }

  void reset() {
    _rmsRaCalculator.clear();
    _rmsDecCalculator.clear();
    _frameCount = 0;
    state = Phd2GuideStats(
      rmsRa: 0,
      rmsDec: 0,
      rmsTotal: 0,
      snr: 0,
      starMass: 0,
      frameCount: 0,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Data point for the guiding graph
class GuideGraphPoint {
  final double ra;
  final double dec;
  final DateTime time;

  GuideGraphPoint(this.ra, this.dec, this.time);
}

/// Provider for guiding graph data (last N points)
final guideGraphProvider = StateNotifierProvider<GuideGraphNotifier, List<GuideGraphPoint>>((ref) {
  return GuideGraphNotifier(ref);
});

class GuideGraphNotifier extends StateNotifier<List<GuideGraphPoint>> {
  final Ref ref;
  StreamSubscription? _sub;
  static const int maxPoints = 100;
  final Queue<GuideGraphPoint> _buffer = Queue<GuideGraphPoint>();

  GuideGraphNotifier(this.ref) : super([]) {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (event.category == EventCategory.guiding && event.eventType == 'GuideStep') {
        final json = event.data;
        final ra = (json['RADistanceRaw'] ?? 0).toDouble();
        final dec = (json['DECDistanceRaw'] ?? 0).toDouble();
        addPoint(ra, dec);
      } else if (event.eventType == 'GuidingStopped') {
        // Clear graph when guiding stops for fresh start
        clear();
      }
    });

    // Clear graph when PHD2 disconnects
    ref.listen<GuiderState>(guiderStateProvider, (previous, next) {
      if (next.connectionState == DeviceConnectionState.disconnected) {
        clear();
      }
    });
  }

  void addPoint(double ra, double dec) {
    final point = GuideGraphPoint(ra, dec, DateTime.now());
    _buffer.add(point);
    if (_buffer.length > maxPoints) {
      _buffer.removeFirst();
    }
    state = _buffer.toList(); // Single list creation instead of two
  }

  void clear() {
    _buffer.clear();
    state = [];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

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

  Phd2Controller(this.ref, this.backend) {
    _init();
  }

  void _init() {
    // Listen to backend events
    _eventSub = backend.eventStream.listen((event) {
      if (event.category != EventCategory.guiding) return;

      // Update the main GuiderState used by the UI
      final guiderNotifier = ref.read(guiderStateProvider.notifier);
      
      switch (event.eventType) {
        case 'AppState':
          _updateStateFromString(event.data['State']);
          break;
        case 'GuideStep':
          _handleGuideStep(event.data);
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
          debugPrint('PHD2: Settle complete');
          break;
        case 'LoopingExposures':
          ref.read(phd2StateProvider.notifier).state = Phd2State.looping;
          break;
      }
      
      // If we are receiving events, assume we are connected
      if (ref.read(guiderStateProvider).connectionState != DeviceConnectionState.connected) {
        guiderNotifier.setConnected();
      }
      
    }, onError: (err) {
      debugPrint('PHD2 Controller Event Error: $err');
      ref.read(guiderStateProvider.notifier).setDisconnected();
    });
  }
  
  void _updateStateFromString(String? stateStr) {
    if (stateStr == null) return;
    
    Phd2State state;
    switch (stateStr) {
      case 'Stopped': state = Phd2State.stopped; break;
      case 'Selected': state = Phd2State.selected; break;
      case 'Calibrating': state = Phd2State.calibrating; break;
      case 'Guiding': state = Phd2State.guiding; break;
      case 'LostLock': state = Phd2State.lostLock; break;
      case 'Paused': state = Phd2State.paused; break;
      case 'Looping': state = Phd2State.looping; break;
      default: state = Phd2State.stopped;
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

  void _handleStarLost() {
    // Record the event timestamp
    ref.read(starLostEventProvider.notifier).state = DateTime.now();

    // Update UI state
    final guiderNotifier = ref.read(guiderStateProvider.notifier);
    guiderNotifier.setGuiding(false);

    // Log the event
    debugPrint('PHD2: Guide star lost! Guiding paused.');

    // Note: The sequencer can monitor starLostEventProvider to pause/abort
    // or implement automatic recovery logic. For now, we just notify.
    // Future enhancement: Could trigger automatic recovery attempt after delay
  }

  Future<void> connect(String host, int port) async {
    // Create a device ID for PHD2 connection
    final deviceId = 'phd2://$host:$port';
    ref.read(guiderStateProvider.notifier).setConnecting(deviceId, 'PHD2');
    await backend.phd2Connect(host: host, port: port);
    ref.read(guiderStateProvider.notifier).setConnected();
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
    await backend.phd2StartGuiding(
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  Future<void> stopGuiding() async {
    await backend.phd2StopGuiding();
  }

  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await backend.phd2Dither(
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );
  }

  /// Start looping exposures without guiding
  Future<void> loop() async {
    await backend.phd2Loop();
  }

  void dispose() {
    _eventSub?.cancel();
  }
}

// =============================================================================
// PHD2 STAR IMAGE PROVIDER - Polls star image for guide star view
// =============================================================================

/// Provider for star image polling configuration
final starImageSizeProvider = StateProvider<int>((ref) => 50);

/// Provider for star image polling interval (milliseconds)
final starImagePollIntervalProvider = StateProvider<int>((ref) => 500);

/// Provider for star image data
final starImageProvider =
    StateNotifierProvider<StarImageNotifier, AsyncValue<Phd2StarImage>>((ref) {
  return StarImageNotifier(ref);
});

/// Notifier that polls PHD2 for star image data
class StarImageNotifier extends StateNotifier<AsyncValue<Phd2StarImage>> {
  final Ref ref;
  Timer? _pollTimer;

  StarImageNotifier(this.ref) : super(const AsyncValue.loading()) {
    // Start polling when guiding or looping
    ref.listen<Phd2State>(phd2StateProvider, (previous, next) {
      if (next == Phd2State.guiding ||
          next == Phd2State.looping ||
          next == Phd2State.calibrating) {
        _startPolling();
      } else {
        _stopPolling();
      }
    });

    // Stop polling and reset state when PHD2 disconnects
    ref.listen<GuiderState>(guiderStateProvider, (previous, next) {
      if (next.connectionState == DeviceConnectionState.disconnected) {
        _stopPolling();
        state = const AsyncValue.loading();
      }
    });
  }

  void _startPolling() {
    _stopPolling();
    final interval = ref.read(starImagePollIntervalProvider);
    _pollTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      _fetchStarImage();
    });
    // Fetch immediately
    _fetchStarImage();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchStarImage() async {
    final backend = ref.read(backendProvider);
    final size = ref.read(starImageSizeProvider);

    try {
      final image = await backend.phd2GetStarImage(size: size);
      if (mounted) {
        state = AsyncValue.data(image);
      }
    } catch (e) {
      if (mounted) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    }
  }

  /// Manually trigger a fetch
  Future<void> refresh() async {
    await _fetchStarImage();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

// =============================================================================
// TARGET DISPLAY HISTORY PROVIDER - Tracks error history for target display
// =============================================================================

/// Maximum number of error points to keep
const int maxTargetHistoryPoints = 50;

/// Provider for target display error history
final targetDisplayHistoryProvider =
    StateNotifierProvider<TargetDisplayHistoryNotifier, List<GuideErrorPoint>>(
        (ref) {
  return TargetDisplayHistoryNotifier(ref);
});

/// Notifier that tracks guide error history for target display
class TargetDisplayHistoryNotifier extends StateNotifier<List<GuideErrorPoint>> {
  final Ref ref;
  StreamSubscription? _sub;
  final Queue<GuideErrorPoint> _buffer = Queue<GuideErrorPoint>();

  TargetDisplayHistoryNotifier(this.ref) : super([]) {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (event.category == EventCategory.guiding &&
          event.eventType == 'GuideStep') {
        final json = event.data;
        final raError = (json['RADistanceRaw'] ?? 0).toDouble();
        final decError = (json['DECDistanceRaw'] ?? 0).toDouble();
        _addPoint(raError, decError);
      } else if (event.eventType == 'GuidingStopped' ||
          event.eventType == 'GuidingStarted') {
        clear();
      }
    });
  }

  void _addPoint(double raError, double decError) {
    final point = GuideErrorPoint(
      raError: raError,
      decError: decError,
      timestamp: DateTime.now(),
    );
    _buffer.add(point);
    if (_buffer.length > maxTargetHistoryPoints) {
      _buffer.removeFirst();
    }
    state = _buffer.toList();
  }

  void clear() {
    _buffer.clear();
    state = [];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// =============================================================================
// PHD2 BRAIN PARAMS PROVIDER - Fetches algorithm parameters
// =============================================================================

/// Provider for PHD2 brain parameters
final brainParamsProvider =
    StateNotifierProvider<BrainParamsNotifier, AsyncValue<Phd2BrainParams>>(
        (ref) {
  return BrainParamsNotifier(ref);
});

/// Notifier that fetches and caches PHD2 brain parameters
class BrainParamsNotifier extends StateNotifier<AsyncValue<Phd2BrainParams>> {
  final Ref ref;
  bool _hasFetched = false;

  BrainParamsNotifier(this.ref) : super(const AsyncValue.loading()) {
    // Auto-fetch when PHD2 is connected
    final guiderState = ref.read(guiderStateProvider);
    if (guiderState.connectionState == DeviceConnectionState.connected) {
      fetch();
    }

    // Listen for connection changes to fetch when connected
    ref.listen<GuiderState>(guiderStateProvider, (previous, next) {
      if (next.connectionState == DeviceConnectionState.connected && !_hasFetched) {
        fetch();
      } else if (next.connectionState == DeviceConnectionState.disconnected) {
        _hasFetched = false;
        state = const AsyncValue.loading();
      }
    });
  }

  /// Fetch all brain parameters from PHD2
  Future<void> fetch() async {
    if (!mounted) return;
    state = const AsyncValue.loading();

    final backend = ref.read(backendProvider);

    try {
      // Fetch parameter names for both axes
      final raNames = await backend.phd2GetAlgoParamNames(axis: 'ra');
      final decNames = await backend.phd2GetAlgoParamNames(axis: 'dec');

      // Fetch all parameter values
      final raParams = <String, double>{};
      for (final name in raNames) {
        raParams[name] = await backend.phd2GetAlgoParam(axis: 'ra', name: name);
      }

      final decParams = <String, double>{};
      for (final name in decNames) {
        decParams[name] =
            await backend.phd2GetAlgoParam(axis: 'dec', name: name);
      }

      if (mounted) {
        _hasFetched = true;
        state = AsyncValue.data(Phd2BrainParams(
          raParamNames: raNames,
          decParamNames: decNames,
          raParams: raParams,
          decParams: decParams,
        ));
      }
    } catch (e) {
      if (mounted) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    }
  }

  /// Update a single parameter
  Future<void> setParam(String axis, String name, double value) async {
    final backend = ref.read(backendProvider);

    try {
      await backend.phd2SetAlgoParam(axis: axis, name: name, value: value);

      // Update local state
      state.whenData((params) {
        if (axis == 'ra' || axis == 'x') {
          final newRaParams = Map<String, double>.from(params.raParams);
          newRaParams[name] = value;
          state = AsyncValue.data(params.copyWith(raParams: newRaParams));
        } else {
          final newDecParams = Map<String, double>.from(params.decParams);
          newDecParams[name] = value;
          state = AsyncValue.data(params.copyWith(decParams: newDecParams));
        }
      });
    } catch (e) {
      debugPrint('Failed to set brain param $name: $e');
      rethrow;
    }
  }
}

// =============================================================================
// PHD2 CALIBRATION STATE PROVIDER
// =============================================================================

/// Provider for calibration state
final calibrationStateProvider =
    StateNotifierProvider<CalibrationStateNotifier, Phd2CalibrationData>((ref) {
  return CalibrationStateNotifier(ref);
});

/// Notifier that tracks calibration state
class CalibrationStateNotifier extends StateNotifier<Phd2CalibrationData> {
  final Ref ref;
  StreamSubscription? _sub;
  bool _hasFetched = false;

  CalibrationStateNotifier(this.ref)
      : super(const Phd2CalibrationData()) {
    debugPrint('PHD2 CalibrationStateNotifier: Initializing...');

    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (event.category == EventCategory.guiding) {
        switch (event.eventType) {
          case 'CalibrationComplete':
            debugPrint('PHD2: CalibrationComplete event received');
            state = state.copyWith(
              isCalibrated: true,
              calibratedAt: DateTime.now(),
            );
            break;
          case 'CalibrationFailed':
            debugPrint('PHD2: CalibrationFailed event received');
            state = state.copyWith(isCalibrated: false);
            break;
          case 'CalibrationDataFlipped':
            // Calibration was flipped (meridian flip)
            debugPrint('PHD2: Calibration data flipped');
            break;
        }
      }
    });

    // Fetch calibration data when PHD2 connects
    ref.listen<GuiderState>(guiderStateProvider, (previous, next) {
      debugPrint('PHD2 CalibrationStateNotifier: guiderState changed from ${previous?.connectionState} to ${next.connectionState}');
      if (next.connectionState == DeviceConnectionState.connected && !_hasFetched) {
        debugPrint('PHD2 CalibrationStateNotifier: PHD2 connected, fetching calibration data...');
        _fetchCalibrationData();
      } else if (next.connectionState == DeviceConnectionState.disconnected) {
        debugPrint('PHD2 CalibrationStateNotifier: PHD2 disconnected, resetting state');
        _hasFetched = false;
        state = const Phd2CalibrationData();
      }
    });

    // Also check current state on initialization
    final guiderState = ref.read(guiderStateProvider);
    debugPrint('PHD2 CalibrationStateNotifier: Initial guiderState.connectionState = ${guiderState.connectionState}');
    if (guiderState.connectionState == DeviceConnectionState.connected) {
      debugPrint('PHD2 CalibrationStateNotifier: Already connected on init, fetching calibration data...');
      _fetchCalibrationData();
    }
  }

  /// Fetch calibration data from PHD2
  Future<void> _fetchCalibrationData() async {
    try {
      final backend = ref.read(backendProvider);
      final data = await backend.phd2GetCalibrationData();
      _hasFetched = true;

      if (mounted) {
        state = data;
        debugPrint('PHD2: Fetched calibration data - calibrated: ${data.isCalibrated}');
      }
    } catch (e) {
      debugPrint('PHD2: Failed to fetch calibration data: $e');
    }
  }

  /// Clear calibration data
  Future<void> clearCalibration({String which = 'both'}) async {
    final backend = ref.read(backendProvider);
    await backend.phd2ClearCalibration(which: which);
    state = const Phd2CalibrationData(isCalibrated: false);
  }

  /// Flip calibration (after meridian flip)
  Future<void> flipCalibration() async {
    final backend = ref.read(backendProvider);
    await backend.phd2FlipCalibration();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// =============================================================================
// PHD2 LOCK POSITION PROVIDER
// =============================================================================

/// Provider for current guide star lock position
final lockPositionProvider =
    StateNotifierProvider<LockPositionNotifier, ({double x, double y})?>(
        (ref) {
  return LockPositionNotifier(ref);
});

/// Notifier that tracks guide star lock position
class LockPositionNotifier extends StateNotifier<({double x, double y})?> {
  final Ref ref;
  StreamSubscription? _sub;

  LockPositionNotifier(this.ref) : super(null) {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (event.category == EventCategory.guiding) {
        if (event.eventType == 'StarSelected' ||
            event.eventType == 'LockPositionSet') {
          final x = (event.data['X'] ?? event.data['x'] ?? 0).toDouble();
          final y = (event.data['Y'] ?? event.data['y'] ?? 0).toDouble();
          state = (x: x, y: y);
        } else if (event.eventType == 'StarLost') {
          // Keep the last known position but could mark as lost
        }
      }
    });
  }

  /// Set a new lock position
  Future<void> setLockPosition(double x, double y,
      {bool exact = false}) async {
    final backend = ref.read(backendProvider);
    await backend.phd2SetLockPosition(x: x, y: y, exact: exact);
    state = (x: x, y: y);
  }

  /// Find a star automatically
  Future<void> findStar() async {
    final backend = ref.read(backendProvider);
    final pos = await backend.phd2FindStar();
    state = (x: pos.$1, y: pos.$2);
  }

  /// Deselect the current star
  Future<void> deselectStar() async {
    final backend = ref.read(backendProvider);
    await backend.phd2DeselectStar();
    state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
