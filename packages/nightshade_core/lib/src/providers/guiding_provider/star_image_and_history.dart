part of '../guiding_provider.dart';

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
    final guiderId = ref.read(guiderStateProvider).deviceId;

    if (guiderId == null || guiderId.isEmpty) {
      return;
    }

    try {
      final image =
          await backend.guiderGetStarImage(deviceId: guiderId, size: size);
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
class TargetDisplayHistoryNotifier
    extends StateNotifier<List<GuideErrorPoint>> {
  final Ref ref;
  StreamSubscription? _sub;
  final Queue<GuideErrorPoint> _buffer = Queue<GuideErrorPoint>();
  LoggingService get _logger => ref.read(loggingServiceProvider);

  TargetDisplayHistoryNotifier(this.ref) : super([]) {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (!mounted) return;
      if (event.category == EventCategory.guiding &&
          event.eventType == 'GuideStep') {
        _logger.debug('Received GuideStep event',
            source: 'TargetDisplayHistoryNotifier');
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
    if (!mounted) return;
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
