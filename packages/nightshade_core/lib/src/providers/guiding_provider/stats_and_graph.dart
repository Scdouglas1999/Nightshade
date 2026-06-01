part of '../guiding_provider.dart';

double _guideAxisPixels(Map<String, dynamic> json, {required bool isRa}) {
  if (isRa) {
    final raw = json['RADistanceRaw'] ?? json['raPx'];
    return (raw ?? 0).toDouble();
  }
  final raw = json['DECDistanceRaw'] ?? json['decPx'];
  return (raw ?? 0).toDouble();
}

/// Listens to [backendProvider.eventStream] and re-binds when the backend
/// instance changes (e.g. mobile companion connects via [NetworkBackend]).
class _BackendGuidingEventBinding {
  _BackendGuidingEventBinding(this._ref, this._onEvent);

  final Ref _ref;
  final void Function(NightshadeEvent event) _onEvent;
  StreamSubscription<NightshadeEvent>? _sub;

  void start() {
    _bind(_ref.read(backendProvider));
    _ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      _bind(next);
    });
  }

  void _bind(NightshadeBackend backend) {
    _sub?.cancel();
    _sub = backend.eventStream.listen(_onEvent);
  }

  void dispose() {
    _sub?.cancel();
  }
}

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
final guideStatsProvider =
    StateNotifierProvider<GuideStatsNotifier, Phd2GuideStats>((ref) {
  return GuideStatsNotifier(ref);
});

/// Notifier that maintains rolling RMS statistics
class GuideStatsNotifier extends StateNotifier<Phd2GuideStats> {
  final Ref ref;
  late final _BackendGuidingEventBinding _events;
  LoggingService get _logger => ref.read(loggingServiceProvider);

  // Rolling RMS calculators for accurate statistics
  final _rmsRaCalculator = RollingRmsCalculator(windowSize: 100);
  final _rmsDecCalculator = RollingRmsCalculator(windowSize: 100);
  int _frameCount = 0;

  GuideStatsNotifier(this.ref)
      : super(const Phd2GuideStats(
          rmsRa: 0,
          rmsDec: 0,
          rmsTotal: 0,
          snr: 0,
          starMass: 0,
          frameCount: 0,
        )) {
    _events = _BackendGuidingEventBinding(ref, _onBackendEvent);
    _events.start();
  }

  void _onBackendEvent(NightshadeEvent event) {
    if (!mounted) return;
    if (event.category == EventCategory.guiding) {
      if (event.eventType == 'GuideStep') {
        _logger.debug('Received GuideStep event', source: 'GuideStatsNotifier');
        _handleGuideStep(event.data);
      } else if (event.eventType == 'GuideStats') {
        final snr = (event.data['SNR'] ?? 0).toDouble();
        final starMass = (event.data['StarMass'] ?? 0).toDouble();
        _logger.debug('Received GuideStats: SNR=$snr, StarMass=$starMass',
            source: 'GuideStatsNotifier');
        updateStarData(snr, starMass);
      } else if (event.eventType == 'GuidingStopped') {
        _logger.debug('Received GuidingStopped', source: 'GuideStatsNotifier');
        reset();
      }
    }
  }

  void _handleGuideStep(Map<String, dynamic> json) {
    final raDistance = _guideAxisPixels(json, isRa: true);
    final decDistance = _guideAxisPixels(json, isRa: false);

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
    state = const Phd2GuideStats(
      rmsRa: 0,
      rmsDec: 0,
      rmsTotal: 0,
      snr: 0,
      starMass: 0,
      frameCount: 0,
    );
  }

  /// Update just the star data (SNR and star mass) from a separate event
  void updateStarData(double snr, double starMass) {
    state = Phd2GuideStats(
      rmsRa: state.rmsRa,
      rmsDec: state.rmsDec,
      rmsTotal: state.rmsTotal,
      snr: snr,
      starMass: starMass,
      frameCount: state.frameCount,
    );
  }

  @override
  void dispose() {
    _events.dispose();
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
final guideGraphProvider =
    StateNotifierProvider<GuideGraphNotifier, List<GuideGraphPoint>>((ref) {
  return GuideGraphNotifier(ref);
});

class GuideGraphNotifier extends StateNotifier<List<GuideGraphPoint>> {
  final Ref ref;
  late final _BackendGuidingEventBinding _events;
  static const int maxPoints = 100;
  final Queue<GuideGraphPoint> _buffer = Queue<GuideGraphPoint>();
  LoggingService get _logger => ref.read(loggingServiceProvider);

  GuideGraphNotifier(this.ref) : super([]) {
    _events = _BackendGuidingEventBinding(ref, _onBackendEvent);
    _events.start();

    ref.listen<GuiderState>(guiderStateProvider, (previous, next) {
      if (next.connectionState == DeviceConnectionState.disconnected) {
        clear();
      }
    });
  }

  void _onBackendEvent(NightshadeEvent event) {
    if (!mounted) return;
    if (event.category == EventCategory.guiding &&
        event.eventType == 'GuideStep') {
      final json = event.data;
      final ra = _guideAxisPixels(json, isRa: true);
      final dec = _guideAxisPixels(json, isRa: false);
      _logger.debug('Adding point: RA=$ra, Dec=$dec',
          source: 'GuideGraphNotifier');
      addPoint(ra, dec);
    } else if (event.category == EventCategory.guiding &&
        event.eventType == 'GuidingStopped') {
      clear();
    }
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
    _events.dispose();
    super.dispose();
  }
}
