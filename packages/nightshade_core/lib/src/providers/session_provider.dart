import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import 'database_provider.dart';
import '../services/session_service.dart';
import '../database/daos/sequence_checkpoints_dao.dart';

// ============================================================================
// Session State Model
// ============================================================================

/// Current imaging session state
/// Tracks the active imaging session with all relevant details
class SessionState extends Equatable {
  /// Whether a session is currently active
  final bool isActive;
  
  /// Session start time (Unix timestamp ms)
  final DateTime? startTime;
  
  /// Current target being imaged
  final String? targetName;
  final double? targetRa;
  final double? targetDec;
  
  /// Exposure tracking
  final int totalExposures;
  final int completedExposures;
  final int failedExposures;
  final double totalIntegrationSecs;
  
  /// Current state flags
  final String? currentFilter;
  final bool isGuiding;
  final bool isCapturing;
  final bool isDithering;
  final bool isAutofocusing;
  
  /// Session quality metrics (running averages)
  final double? avgHfr;
  final double? avgGuidingRmsRa;
  final double? avgGuidingRmsDec;
  
  /// Database session ID (for persisting statistics)
  final int? dbSessionId;

  const SessionState({
    this.isActive = false,
    this.startTime,
    this.targetName,
    this.targetRa,
    this.targetDec,
    this.totalExposures = 0,
    this.completedExposures = 0,
    this.failedExposures = 0,
    this.totalIntegrationSecs = 0.0,
    this.currentFilter,
    this.isGuiding = false,
    this.isCapturing = false,
    this.isDithering = false,
    this.isAutofocusing = false,
    this.avgHfr,
    this.avgGuidingRmsRa,
    this.avgGuidingRmsDec,
    this.dbSessionId,
  });

  SessionState copyWith({
    bool? isActive,
    DateTime? startTime,
    String? targetName,
    double? targetRa,
    double? targetDec,
    int? totalExposures,
    int? completedExposures,
    int? failedExposures,
    double? totalIntegrationSecs,
    String? currentFilter,
    bool? isGuiding,
    bool? isCapturing,
    bool? isDithering,
    bool? isAutofocusing,
    double? avgHfr,
    double? avgGuidingRmsRa,
    double? avgGuidingRmsDec,
    int? dbSessionId,
  }) {
    return SessionState(
      isActive: isActive ?? this.isActive,
      startTime: startTime ?? this.startTime,
      targetName: targetName ?? this.targetName,
      targetRa: targetRa ?? this.targetRa,
      targetDec: targetDec ?? this.targetDec,
      totalExposures: totalExposures ?? this.totalExposures,
      completedExposures: completedExposures ?? this.completedExposures,
      failedExposures: failedExposures ?? this.failedExposures,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      currentFilter: currentFilter ?? this.currentFilter,
      isGuiding: isGuiding ?? this.isGuiding,
      isCapturing: isCapturing ?? this.isCapturing,
      isDithering: isDithering ?? this.isDithering,
      isAutofocusing: isAutofocusing ?? this.isAutofocusing,
      avgHfr: avgHfr ?? this.avgHfr,
      avgGuidingRmsRa: avgGuidingRmsRa ?? this.avgGuidingRmsRa,
      avgGuidingRmsDec: avgGuidingRmsDec ?? this.avgGuidingRmsDec,
      dbSessionId: dbSessionId ?? this.dbSessionId,
    );
  }

  /// Session duration
  Duration? get duration {
    if (startTime == null) return null;
    return DateTime.now().difference(startTime!);
  }

  /// Calculate success rate
  double get successRate {
    if (completedExposures + failedExposures == 0) return 1.0;
    return completedExposures / (completedExposures + failedExposures);
  }

  @override
  List<Object?> get props => [
    isActive,
    startTime,
    targetName,
    targetRa,
    targetDec,
    totalExposures,
    completedExposures,
    failedExposures,
    totalIntegrationSecs,
    currentFilter,
    isGuiding,
    isCapturing,
    isDithering,
    isAutofocusing,
    avgHfr,
    avgGuidingRmsRa,
    avgGuidingRmsDec,
    dbSessionId,
  ];
}

// ============================================================================
// Session State Notifier
// ============================================================================

/// Notifier for managing session state
class SessionStateNotifier extends StateNotifier<SessionState> {
  final Ref _ref;
  int _autofocusCount = 0;

  SessionStateNotifier(this._ref) : super(const SessionState());

  /// Start a new imaging session
  Future<void> startSession({
    String? targetName,
    double? targetRa,
    double? targetDec,
    int? targetId,
    int? profileId,
  }) async {
    // Use SessionService to create and manage the session
    final sessionService = _ref.read(sessionServiceProvider);
    final dbId = await sessionService.startSession(
      name: targetName,
      targetId: targetId,
      profileId: profileId,
    );

    _autofocusCount = 0;

    state = SessionState(
      isActive: true,
      startTime: DateTime.now(),
      targetName: targetName,
      targetRa: targetRa,
      targetDec: targetDec,
      dbSessionId: dbId,
    );
  }

  /// End the current session
  Future<void> endSession({String status = 'completed'}) async {
    if (!state.isActive || state.dbSessionId == null) return;

    // Use SessionService to finalize the session with latest stats
    final sessionService = _ref.read(sessionServiceProvider);

    // Update session service with final statistics before ending
    await _updateSessionServiceStats();

    await sessionService.endSession(status: status);

    _autofocusCount = 0;
    state = const SessionState();
  }

  /// Abort the current session
  Future<void> abortSession() async {
    await endSession(status: 'aborted');
  }

  /// Recover a previously interrupted session
  Future<void> recoverSession(SessionRecoveryInfo recoveryInfo) async {
    final sessionService = _ref.read(sessionServiceProvider);
    await sessionService.recoverSession(recoveryInfo.sessionId);

    state = SessionState(
      isActive: true,
      startTime: recoveryInfo.startTime,
      targetName: recoveryInfo.targetName,
      dbSessionId: recoveryInfo.sessionId,
      completedExposures: recoveryInfo.stats.completedExposures,
      failedExposures: recoveryInfo.stats.failedExposures,
      totalIntegrationSecs: recoveryInfo.stats.totalIntegrationSecs,
      avgHfr: recoveryInfo.stats.avgHfr,
      avgGuidingRmsDec: recoveryInfo.stats.avgGuidingRms,
    );

    _autofocusCount = recoveryInfo.stats.autofocusCount;
  }

  /// Set the current target
  void setTarget({
    required String name,
    double? ra,
    double? dec,
  }) {
    state = state.copyWith(
      targetName: name,
      targetRa: ra,
      targetDec: dec,
    );
  }

  /// Record a completed exposure
  void recordExposureComplete({
    required double exposureTime,
    double? hfr,
  }) {
    // Update running average HFR
    double? newAvgHfr = state.avgHfr;
    if (hfr != null) {
      if (state.avgHfr == null) {
        newAvgHfr = hfr;
      } else {
        // Simple running average
        final count = state.completedExposures;
        newAvgHfr = (state.avgHfr! * count + hfr) / (count + 1);
      }
    }

    state = state.copyWith(
      completedExposures: state.completedExposures + 1,
      totalIntegrationSecs: state.totalIntegrationSecs + exposureTime,
      avgHfr: newAvgHfr,
    );

    // Update session service (triggers checkpoint if needed)
    _updateSessionServiceStats();
  }

  /// Record a failed exposure
  void recordExposureFailed() {
    state = state.copyWith(
      failedExposures: state.failedExposures + 1,
    );

    // Update session service (triggers checkpoint if needed)
    _updateSessionServiceStats();
  }

  /// Increment autofocus count
  void incrementAutofocusCount() {
    _autofocusCount++;
    _updateSessionServiceStats();
  }

  /// Update the expected total exposures
  void setTotalExposures(int total) {
    state = state.copyWith(totalExposures: total);
  }

  /// Set capturing state
  void setCapturing(bool isCapturing) {
    state = state.copyWith(isCapturing: isCapturing);
  }

  /// Set guiding state with optional RMS values
  void setGuiding(bool isGuiding, {double? rmsRa, double? rmsDec}) {
    state = state.copyWith(
      isGuiding: isGuiding,
      avgGuidingRmsRa: rmsRa ?? state.avgGuidingRmsRa,
      avgGuidingRmsDec: rmsDec ?? state.avgGuidingRmsDec,
    );
  }

  /// Set dithering state
  void setDithering(bool isDithering) {
    state = state.copyWith(isDithering: isDithering);
  }

  /// Set autofocusing state
  void setAutofocusing(bool isAutofocusing) {
    state = state.copyWith(isAutofocusing: isAutofocusing);
  }

  /// Set current filter
  void setFilter(String? filter) {
    state = state.copyWith(currentFilter: filter);
  }

  /// Update guiding RMS values
  void updateGuidingRms(double rmsRa, double rmsDec) {
    state = state.copyWith(
      avgGuidingRmsRa: rmsRa,
      avgGuidingRmsDec: rmsDec,
    );
  }

  /// Helper to update session service with current stats
  Future<void> _updateSessionServiceStats() async {
    if (!state.isActive || state.dbSessionId == null) return;

    final sessionService = _ref.read(sessionServiceProvider);

    // Calculate combined guiding RMS (RMS of both axes)
    double? combinedGuidingRms;
    if (state.avgGuidingRmsRa != null && state.avgGuidingRmsDec != null) {
      combinedGuidingRms = (state.avgGuidingRmsRa! + state.avgGuidingRmsDec!) / 2.0;
    }

    final stats = SessionStats(
      completedExposures: state.completedExposures,
      failedExposures: state.failedExposures,
      totalIntegrationSecs: state.totalIntegrationSecs,
      avgHfr: state.avgHfr,
      avgGuidingRms: combinedGuidingRms,
      autofocusCount: _autofocusCount,
      lastUpdated: DateTime.now(),
    );

    await sessionService.updateSessionProgress(stats);
  }
}

// ============================================================================
// Providers
// ============================================================================

/// DAO provider for sequence checkpoints (optional, for sequence integration)
final sequenceCheckpointsDaoProvider = Provider<SequenceCheckpointsDao>((ref) {
  return SequenceCheckpointsDao(ref.watch(databaseProvider));
});

/// SessionService provider
final sessionServiceProvider = Provider<SessionService>((ref) {
  final service = SessionService(
    sessionsDao: ref.watch(sessionsDaoProvider),
    checkpointsDao: ref.watch(sequenceCheckpointsDaoProvider),
  );

  ref.onDispose(() => service.dispose());

  return service;
});

/// Provider for session service status stream
final sessionServiceStatusProvider = StreamProvider<String>((ref) {
  final service = ref.watch(sessionServiceProvider);
  return service.statusStream;
});

/// Session state provider for tracking active imaging sessions
final sessionStateProvider = StateNotifierProvider<SessionStateNotifier, SessionState>((ref) {
  return SessionStateNotifier(ref);
});

/// Convenience provider for checking if a session is active
final isSessionActiveProvider = Provider<bool>((ref) {
  return ref.watch(sessionStateProvider).isActive;
});

/// Provider for session progress (0.0 - 1.0)
final sessionProgressProvider = Provider<double>((ref) {
  final session = ref.watch(sessionStateProvider);
  if (session.totalExposures == 0) return 0.0;
  return session.completedExposures / session.totalExposures;
});

/// Provider for session duration as a formatted string
final sessionDurationProvider = Provider<String>((ref) {
  final session = ref.watch(sessionStateProvider);
  final duration = session.duration;
  if (duration == null) return '--:--:--';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  return '${hours.toString().padLeft(2, '0')}:'
         '${minutes.toString().padLeft(2, '0')}:'
         '${seconds.toString().padLeft(2, '0')}';
});

/// Provider for incomplete sessions that can be recovered
final incompleteSessionsProvider = FutureProvider<List<SessionRecoveryInfo>>((ref) async {
  final sessionService = ref.watch(sessionServiceProvider);
  return await sessionService.findIncompleteSessionsForRecovery();
});





