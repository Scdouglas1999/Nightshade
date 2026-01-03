import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/daos/sessions_dao.dart';
import '../database/daos/sequence_checkpoints_dao.dart';

/// Configuration for session checkpointing
class SessionCheckpointConfig {
  /// Checkpoint after this many images captured
  final int checkpointImageInterval;

  /// Checkpoint after this time interval
  final Duration checkpointTimeInterval;

  /// Whether automatic checkpointing is enabled
  final bool enabled;

  const SessionCheckpointConfig({
    this.checkpointImageInterval = 5,
    this.checkpointTimeInterval = const Duration(minutes: 5),
    this.enabled = true,
  });

  SessionCheckpointConfig copyWith({
    int? checkpointImageInterval,
    Duration? checkpointTimeInterval,
    bool? enabled,
  }) {
    return SessionCheckpointConfig(
      checkpointImageInterval: checkpointImageInterval ?? this.checkpointImageInterval,
      checkpointTimeInterval: checkpointTimeInterval ?? this.checkpointTimeInterval,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Statistics tracked during a session for checkpointing
class SessionStats {
  final int completedExposures;
  final int failedExposures;
  final double totalIntegrationSecs;
  final double? avgHfr;
  final double? avgGuidingRms;
  final int autofocusCount;
  final int? lastImageId;
  final DateTime lastUpdated;

  const SessionStats({
    this.completedExposures = 0,
    this.failedExposures = 0,
    this.totalIntegrationSecs = 0.0,
    this.avgHfr,
    this.avgGuidingRms,
    this.autofocusCount = 0,
    this.lastImageId,
    required this.lastUpdated,
  });

  SessionStats copyWith({
    int? completedExposures,
    int? failedExposures,
    double? totalIntegrationSecs,
    double? avgHfr,
    double? avgGuidingRms,
    int? autofocusCount,
    int? lastImageId,
    DateTime? lastUpdated,
  }) {
    return SessionStats(
      completedExposures: completedExposures ?? this.completedExposures,
      failedExposures: failedExposures ?? this.failedExposures,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      avgHfr: avgHfr ?? this.avgHfr,
      avgGuidingRms: avgGuidingRms ?? this.avgGuidingRms,
      autofocusCount: autofocusCount ?? this.autofocusCount,
      lastImageId: lastImageId ?? this.lastImageId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  /// Calculate success rate
  double get successRate {
    final total = completedExposures + failedExposures;
    if (total == 0) return 1.0;
    return completedExposures / total;
  }
}

/// Result of a session recovery operation
class SessionRecoveryInfo {
  final int sessionId;
  final String? sessionName;
  final int? targetId;
  final String? targetName;
  final DateTime startTime;
  final SessionStats stats;

  const SessionRecoveryInfo({
    required this.sessionId,
    this.sessionName,
    this.targetId,
    this.targetName,
    required this.startTime,
    required this.stats,
  });

  Duration get duration => DateTime.now().difference(startTime);
}

/// Service for managing imaging session lifecycle with persistence and recovery
class SessionService {
  final SessionsDao sessionsDao;
  final SequenceCheckpointsDao? checkpointsDao; // Optional, for sequence integration

  SessionCheckpointConfig _config = const SessionCheckpointConfig();
  Timer? _checkpointTimer;

  // Current session tracking
  int? _currentSessionId;
  SessionStats? _currentStats;
  DateTime? _lastCheckpoint;
  int _imagesSinceCheckpoint = 0;

  // Status tracking
  final _statusController = StreamController<String>.broadcast();

  SessionService({
    required this.sessionsDao,
    this.checkpointsDao,
  });

  /// Stream of status updates
  Stream<String> get statusStream => _statusController.stream;

  /// Current session ID (null if no active session)
  int? get currentSessionId => _currentSessionId;

  /// Whether a session is currently active
  bool get hasActiveSession => _currentSessionId != null;

  /// Current session statistics
  SessionStats? get currentStats => _currentStats;

  /// Start a new imaging session
  /// Returns the session ID
  Future<int> startSession({
    String? name,
    int? targetId,
    int? profileId,
  }) async {
    if (_currentSessionId != null) {
      throw Exception('Session already active. End current session before starting a new one.');
    }

    debugPrint('SessionService: Starting new session...');
    debugPrint('  Name: $name');
    debugPrint('  Target ID: $targetId');
    debugPrint('  Profile ID: $profileId');

    // Create database session record with 'active' status
    final sessionId = await sessionsDao.startSession(
      name: name,
      profileId: profileId,
      targetId: targetId,
    );

    // Initialize tracking
    _currentSessionId = sessionId;
    _currentStats = SessionStats(lastUpdated: DateTime.now());
    _lastCheckpoint = DateTime.now();
    _imagesSinceCheckpoint = 0;

    // Start checkpoint timer if enabled
    if (_config.enabled) {
      _startCheckpointTimer();
    }

    _statusController.add('Session started: ID $sessionId');
    debugPrint('SessionService: Session started with ID: $sessionId');

    return sessionId;
  }

  /// Update session progress with new statistics
  /// Automatically triggers checkpoint if threshold reached
  Future<void> updateSessionProgress(SessionStats stats) async {
    if (_currentSessionId == null) {
      debugPrint('SessionService: No active session to update');
      return;
    }

    _currentStats = stats;
    _imagesSinceCheckpoint++;

    // Check if checkpoint is needed
    final imageThresholdReached = _imagesSinceCheckpoint >= _config.checkpointImageInterval;
    final timeThresholdReached = _lastCheckpoint != null &&
        DateTime.now().difference(_lastCheckpoint!) >= _config.checkpointTimeInterval;

    if (_config.enabled && (imageThresholdReached || timeThresholdReached)) {
      await _performCheckpoint();
    }
  }

  /// Manually trigger a checkpoint save
  Future<void> checkpoint() async {
    if (_currentSessionId == null || _currentStats == null) {
      debugPrint('SessionService: No active session to checkpoint');
      return;
    }

    await _performCheckpoint();
  }

  /// End the current session with finalization
  Future<void> endSession({String status = 'completed'}) async {
    if (_currentSessionId == null) {
      debugPrint('SessionService: No active session to end');
      return;
    }

    debugPrint('SessionService: Ending session $_currentSessionId with status: $status');

    try {
      // Perform final checkpoint to save latest stats
      if (_currentStats != null) {
        await _performCheckpoint();
      }

      // Calculate final statistics
      final stats = _currentStats ?? SessionStats(lastUpdated: DateTime.now());

      // Update session with final statistics and status
      await sessionsDao.updateSessionStats(
        _currentSessionId!,
        totalExposures: stats.completedExposures + stats.failedExposures,
        successfulExposures: stats.completedExposures,
        failedExposures: stats.failedExposures,
        totalIntegrationSecs: stats.totalIntegrationSecs,
        avgHfr: stats.avgHfr,
        avgGuidingRms: stats.avgGuidingRms,
        autofocusCount: stats.autofocusCount,
      );

      // Set end time and status
      await sessionsDao.endSession(_currentSessionId!, status: status);

      _statusController.add('Session ended: $_currentSessionId ($status)');
      debugPrint('SessionService: Session finalized');
      debugPrint('  Completed: ${stats.completedExposures}');
      debugPrint('  Failed: ${stats.failedExposures}');
      debugPrint('  Integration: ${stats.totalIntegrationSecs}s');
      debugPrint('  Success rate: ${(stats.successRate * 100).toStringAsFixed(1)}%');
    } catch (e) {
      debugPrint('SessionService: Error ending session: $e');
      rethrow;
    } finally {
      // Clean up
      _stopCheckpointTimer();
      _currentSessionId = null;
      _currentStats = null;
      _lastCheckpoint = null;
      _imagesSinceCheckpoint = 0;
    }
  }

  /// Abort the current session (marks as 'aborted' status)
  Future<void> abortSession() async {
    await endSession(status: 'aborted');
  }

  /// Mark session as error state
  Future<void> errorSession(String errorMessage) async {
    if (_currentSessionId != null && _currentStats != null) {
      // Optionally store error message in notes
      final currentSession = await sessionsDao.getSessionById(_currentSessionId!);
      if (currentSession != null) {
        final notes = currentSession.notes ?? '';
        final errorNotes = notes.isEmpty ? errorMessage : '$notes\n\nError: $errorMessage';
        await sessionsDao.updateNotes(_currentSessionId!, errorNotes);
      }
    }
    await endSession(status: 'error');
  }

  /// Check for incomplete sessions (crashed/interrupted sessions)
  /// Returns list of sessions that can be recovered
  Future<List<SessionRecoveryInfo>> findIncompleteSessionsForRecovery() async {
    debugPrint('SessionService: Checking for incomplete sessions...');

    try {
      final allSessions = await sessionsDao.getAllSessions();

      // Find sessions with 'active' status (not completed/aborted/error)
      final incompleteSessions = allSessions.where((s) => s.status == 'active').toList();

      if (incompleteSessions.isEmpty) {
        debugPrint('SessionService: No incomplete sessions found');
        return [];
      }

      debugPrint('SessionService: Found ${incompleteSessions.length} incomplete session(s)');

      // Convert to recovery info
      final recoveryInfoList = <SessionRecoveryInfo>[];
      for (final session in incompleteSessions) {
        final stats = SessionStats(
          completedExposures: session.successfulExposures,
          failedExposures: session.failedExposures,
          totalIntegrationSecs: session.totalIntegrationSecs,
          avgHfr: session.avgHfr,
          avgGuidingRms: session.avgGuidingRms,
          autofocusCount: session.autofocusCount,
          lastUpdated: session.startTime, // Use start time as fallback
        );

        recoveryInfoList.add(SessionRecoveryInfo(
          sessionId: session.id,
          sessionName: session.name,
          targetId: session.targetId,
          startTime: session.startTime,
          stats: stats,
        ));
      }

      return recoveryInfoList;
    } catch (e) {
      debugPrint('SessionService: Error finding incomplete sessions: $e');
      return [];
    }
  }

  /// Resume an interrupted session
  Future<void> recoverSession(int sessionId) async {
    if (_currentSessionId != null) {
      throw Exception('Cannot recover session while another session is active');
    }

    debugPrint('SessionService: Recovering session $sessionId...');

    // Verify session exists and is in 'active' state
    final session = await sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session $sessionId not found');
    }

    if (session.status != 'active') {
      throw Exception('Session $sessionId is not in active state (status: ${session.status})');
    }

    // Restore session state
    _currentSessionId = sessionId;
    _currentStats = SessionStats(
      completedExposures: session.successfulExposures,
      failedExposures: session.failedExposures,
      totalIntegrationSecs: session.totalIntegrationSecs,
      avgHfr: session.avgHfr,
      avgGuidingRms: session.avgGuidingRms,
      autofocusCount: session.autofocusCount,
      lastUpdated: DateTime.now(),
    );
    _lastCheckpoint = DateTime.now();
    _imagesSinceCheckpoint = 0;

    // Start checkpoint timer
    if (_config.enabled) {
      _startCheckpointTimer();
    }

    _statusController.add('Session recovered: $sessionId');
    debugPrint('SessionService: Session $sessionId recovered successfully');
    debugPrint('  Exposures completed: ${session.successfulExposures}');
    debugPrint('  Integration time: ${session.totalIntegrationSecs}s');
  }

  /// Mark a session as aborted (for recovery dialog when user chooses not to resume)
  Future<void> markSessionAborted(int sessionId) async {
    debugPrint('SessionService: Marking session $sessionId as aborted');
    await sessionsDao.endSession(sessionId, status: 'aborted');
  }

  /// Update checkpoint configuration
  void updateConfig(SessionCheckpointConfig config) {
    final wasEnabled = _config.enabled;
    _config = config;

    if (_config.enabled && !wasEnabled && _currentSessionId != null) {
      // Checkpointing was just enabled, start timer
      _startCheckpointTimer();
    } else if (!_config.enabled && wasEnabled) {
      // Checkpointing was just disabled, stop timer
      _stopCheckpointTimer();
    } else if (_config.enabled && _config.checkpointTimeInterval != config.checkpointTimeInterval) {
      // Interval changed, restart timer
      _stopCheckpointTimer();
      _startCheckpointTimer();
    }

    debugPrint('SessionService: Configuration updated');
  }

  /// Get current configuration
  SessionCheckpointConfig get config => _config;

  // Private helper methods

  void _startCheckpointTimer() {
    _stopCheckpointTimer(); // Ensure no duplicate timers
    _checkpointTimer = Timer.periodic(_config.checkpointTimeInterval, (_) {
      if (_currentSessionId != null && _currentStats != null) {
        _performCheckpoint();
      }
    });
    debugPrint('SessionService: Checkpoint timer started (interval: ${_config.checkpointTimeInterval.inMinutes} min)');
  }

  void _stopCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
  }

  Future<void> _performCheckpoint() async {
    if (_currentSessionId == null || _currentStats == null) return;

    debugPrint('SessionService: Performing checkpoint for session $_currentSessionId...');

    try {
      // Save current statistics to database
      await sessionsDao.updateSessionStats(
        _currentSessionId!,
        totalExposures: _currentStats!.completedExposures + _currentStats!.failedExposures,
        successfulExposures: _currentStats!.completedExposures,
        failedExposures: _currentStats!.failedExposures,
        totalIntegrationSecs: _currentStats!.totalIntegrationSecs,
        avgHfr: _currentStats!.avgHfr,
        avgGuidingRms: _currentStats!.avgGuidingRms,
        autofocusCount: _currentStats!.autofocusCount,
      );

      _lastCheckpoint = DateTime.now();
      _imagesSinceCheckpoint = 0;

      _statusController.add('Checkpoint saved');
      debugPrint('SessionService: Checkpoint saved successfully');
    } catch (e) {
      debugPrint('SessionService: Error performing checkpoint: $e');
      _statusController.add('Checkpoint failed: $e');
    }
  }

  /// Dispose of resources
  void dispose() {
    _stopCheckpointTimer();
    _statusController.close();
    debugPrint('SessionService: Disposed');
  }
}
