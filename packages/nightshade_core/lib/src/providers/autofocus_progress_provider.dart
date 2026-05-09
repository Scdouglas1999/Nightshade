import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/autofocus_progress.dart';
import '../models/backend/autofocus_result.dart';
import '../models/backend/event_types.dart';
import 'backend_provider.dart';

/// State for the non-blocking autofocus progress overlay
class AutofocusOverlayState {
  /// Whether an autofocus run is currently active
  final bool isRunning;

  /// Current point index (1-based)
  final int currentPoint;

  /// Total expected points
  final int totalPoints;

  /// All V-curve data points collected so far
  final List<VCurvePoint> vcurvePoints;

  /// Current HFR measurement
  final double currentHfr;

  /// Best HFR seen so far in this run
  final double bestHfr;

  /// Current star count
  final int starCount;

  /// Status message
  final String status;

  /// Final autofocus result (null while running)
  final AutofocusResult? result;

  /// Whether the overlay is minimized
  final bool isMinimized;

  /// Whether the overlay should be visible at all
  final bool isVisible;

  /// Focus range for the current run
  final FocusRange? focusRange;

  /// Star crops from the latest measurement
  final List<StarCrop> starCrops;

  /// Whether the autofocus run ended in an error (avoids stringly-typed checks)
  final bool hasError;

  const AutofocusOverlayState({
    this.isRunning = false,
    this.currentPoint = 0,
    this.totalPoints = 0,
    this.vcurvePoints = const [],
    this.currentHfr = 0.0,
    this.bestHfr = 0.0,
    this.starCount = 0,
    this.status = '',
    this.result,
    this.isMinimized = false,
    this.isVisible = false,
    this.focusRange,
    this.starCrops = const [],
    this.hasError = false,
  });

  AutofocusOverlayState copyWith({
    bool? isRunning,
    int? currentPoint,
    int? totalPoints,
    List<VCurvePoint>? vcurvePoints,
    double? currentHfr,
    double? bestHfr,
    int? starCount,
    String? status,
    AutofocusResult? result,
    bool clearResult = false,
    bool? isMinimized,
    bool? isVisible,
    FocusRange? focusRange,
    List<StarCrop>? starCrops,
    bool? hasError,
  }) {
    return AutofocusOverlayState(
      isRunning: isRunning ?? this.isRunning,
      currentPoint: currentPoint ?? this.currentPoint,
      totalPoints: totalPoints ?? this.totalPoints,
      vcurvePoints: vcurvePoints ?? this.vcurvePoints,
      currentHfr: currentHfr ?? this.currentHfr,
      bestHfr: bestHfr ?? this.bestHfr,
      starCount: starCount ?? this.starCount,
      status: status ?? this.status,
      result: clearResult ? null : (result ?? this.result),
      isMinimized: isMinimized ?? this.isMinimized,
      isVisible: isVisible ?? this.isVisible,
      focusRange: focusRange ?? this.focusRange,
      starCrops: starCrops ?? this.starCrops,
      hasError: hasError ?? this.hasError,
    );
  }
}

/// Notifier that tracks autofocus progress from the backend event stream
class AutofocusOverlayNotifier extends StateNotifier<AutofocusOverlayState> {
  final Ref _ref;
  StreamSubscription? _eventSubscription;

  AutofocusOverlayNotifier(this._ref) : super(const AutofocusOverlayState()) {
    _listenToEvents();
  }

  void _listenToEvents() {
    _eventSubscription = _ref.read(backendProvider).eventStream.listen((event) {
      if (!mounted) return;
      if (event.category == EventCategory.equipment &&
          event.eventType == 'AutofocusProgress') {
        _handleAutofocusProgress(event);
      }
    });
  }

  void _handleAutofocusProgress(NightshadeEvent event) {
    final detail = event.data['detail'] as String?;
    if (detail == null) {
      onAutofocusFailed('Autofocus progress event was missing detail payload');
      return;
    }

    final progressData = AutofocusProgressData.tryParse(detail);
    if (progressData == null) {
      onAutofocusFailed('Autofocus progress event could not be parsed');
      return;
    }

    // Detect the start of a new autofocus run. If we receive point 1 and the
    // overlay is not currently running (or we were showing results from a
    // previous run), reset all state so old V-curve points and star crops
    // from the prior run don't persist.
    if (progressData.point == 1 && (!state.isRunning || state.result != null)) {
      onAutofocusStarted();
    }

    // Compute best HFR from all V-curve points
    final newBestHfr = progressData.vcurvePoints.isEmpty
        ? 0.0
        : progressData.vcurvePoints
            .map((p) => p.hfr)
            .reduce((a, b) => a < b ? a : b);

    state = state.copyWith(
      isRunning: true,
      isVisible: true,
      currentPoint: progressData.point,
      totalPoints: progressData.totalPoints,
      vcurvePoints: progressData.vcurvePoints,
      currentHfr: progressData.hfr,
      bestHfr: newBestHfr,
      starCount: progressData.starCount,
      focusRange: progressData.focusRange,
      starCrops: progressData.starCrops,
      status: 'Measuring point ${progressData.point}/${progressData.totalPoints}',
    );
  }

  /// Called when autofocus starts (from any trigger: focus tab, dashboard, sequencer)
  void onAutofocusStarted() {
    state = const AutofocusOverlayState(
      isRunning: true,
      isVisible: true,
      hasError: false,
      status: 'Initializing autofocus...',
    );
  }

  /// Called when autofocus completes with a result
  void onAutofocusCompleted(AutofocusResult result) {
    state = state.copyWith(
      isRunning: false,
      hasError: false,
      result: result,
      status: 'Complete - HFR: ${result.bestHfr.toStringAsFixed(2)} '
          'at position ${result.bestPosition}',
    );
  }

  /// Called when autofocus fails
  void onAutofocusFailed(String error) {
    state = state.copyWith(
      isRunning: false,
      hasError: true,
      status: 'Failed: $error',
    );
  }

  /// Toggle minimized state
  void toggleMinimized() {
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  /// Close/dismiss the overlay
  void dismiss() {
    state = state.copyWith(
      isVisible: false,
      isRunning: false,
      clearResult: true,
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for the autofocus progress overlay state
final autofocusOverlayProvider =
    StateNotifierProvider<AutofocusOverlayNotifier, AutofocusOverlayState>(
        (ref) {
  return AutofocusOverlayNotifier(ref);
});
