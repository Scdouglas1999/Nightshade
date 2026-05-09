import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' as db;
import '../database/daos/equipment_profiles_dao.dart';
import '../database/daos/sequence_checkpoints_dao.dart';
import '../database/daos/sequences_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/targets_dao.dart';
import '../models/equipment/equipment_models.dart';
import '../providers/database_provider.dart';
import '../providers/session_provider.dart' show sequenceCheckpointsDaoProvider;
import '../utils/json_validation.dart';

// =============================================================================
// EquipmentSnapshot - Captures equipment state for quick session resumption
// =============================================================================

/// Represents a snapshot of equipment state at a point in time.
/// Used to restore equipment settings when resuming a session.
class EquipmentSnapshot {
  /// Target temperature for camera cooling (Celsius)
  final double? coolerTargetTemp;

  /// Camera gain setting
  final int? cameraGain;

  /// Camera offset setting
  final int? cameraOffset;

  /// Camera horizontal binning
  final int? cameraBinX;

  /// Camera vertical binning
  final int? cameraBinY;

  /// Filter wheel position (0-indexed)
  final int? filterPosition;

  /// Focuser position in steps
  final int? focuserPosition;

  /// Last used exposure time in seconds
  final double? exposureTime;

  /// When this snapshot was captured
  final DateTime capturedAt;

  const EquipmentSnapshot({
    this.coolerTargetTemp,
    this.cameraGain,
    this.cameraOffset,
    this.cameraBinX,
    this.cameraBinY,
    this.filterPosition,
    this.focuserPosition,
    this.exposureTime,
    required this.capturedAt,
  });

  /// Create a copy with some fields replaced
  EquipmentSnapshot copyWith({
    double? coolerTargetTemp,
    int? cameraGain,
    int? cameraOffset,
    int? cameraBinX,
    int? cameraBinY,
    int? filterPosition,
    int? focuserPosition,
    double? exposureTime,
    DateTime? capturedAt,
  }) {
    return EquipmentSnapshot(
      coolerTargetTemp: coolerTargetTemp ?? this.coolerTargetTemp,
      cameraGain: cameraGain ?? this.cameraGain,
      cameraOffset: cameraOffset ?? this.cameraOffset,
      cameraBinX: cameraBinX ?? this.cameraBinX,
      cameraBinY: cameraBinY ?? this.cameraBinY,
      filterPosition: filterPosition ?? this.filterPosition,
      focuserPosition: focuserPosition ?? this.focuserPosition,
      exposureTime: exposureTime ?? this.exposureTime,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }

  /// Convert to JSON map for database storage
  Map<String, dynamic> toJson() {
    return {
      'coolerTargetTemp': coolerTargetTemp,
      'cameraGain': cameraGain,
      'cameraOffset': cameraOffset,
      'cameraBinX': cameraBinX,
      'cameraBinY': cameraBinY,
      'filterPosition': filterPosition,
      'focuserPosition': focuserPosition,
      'exposureTime': exposureTime,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  /// Create from JSON map (from database)
  factory EquipmentSnapshot.fromJson(Map<String, dynamic> json) {
    return EquipmentSnapshot(
      coolerTargetTemp: jsonDouble(
        json['coolerTargetTemp'],
        context: 'equipment_snapshot.coolerTargetTemp',
      ),
      cameraGain:
          jsonInt(json['cameraGain'], context: 'equipment_snapshot.cameraGain'),
      cameraOffset: jsonInt(
        json['cameraOffset'],
        context: 'equipment_snapshot.cameraOffset',
      ),
      cameraBinX:
          jsonInt(json['cameraBinX'], context: 'equipment_snapshot.cameraBinX'),
      cameraBinY:
          jsonInt(json['cameraBinY'], context: 'equipment_snapshot.cameraBinY'),
      filterPosition: jsonInt(
        json['filterPosition'],
        context: 'equipment_snapshot.filterPosition',
      ),
      focuserPosition: jsonInt(
        json['focuserPosition'],
        context: 'equipment_snapshot.focuserPosition',
      ),
      exposureTime: jsonDouble(
        json['exposureTime'],
        context: 'equipment_snapshot.exposureTime',
      ),
      capturedAt: jsonDateTime(
            json['capturedAt'],
            context: 'equipment_snapshot.capturedAt',
          ) ??
          DateTime.now(),
    );
  }

  /// Convert to JSON string for database storage
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string (from database)
  factory EquipmentSnapshot.fromJsonString(String jsonStr) {
    final json = decodeJsonObjectString(
      jsonStr,
      context: 'imaging_sessions.equipment_snapshot',
    );
    return EquipmentSnapshot.fromJson(json);
  }

  /// Check if this snapshot has meaningful equipment data
  bool get hasEquipmentData {
    return coolerTargetTemp != null ||
        cameraGain != null ||
        cameraOffset != null ||
        cameraBinX != null ||
        cameraBinY != null ||
        filterPosition != null ||
        focuserPosition != null ||
        exposureTime != null;
  }

  @override
  String toString() {
    return 'EquipmentSnapshot('
        'coolerTargetTemp: $coolerTargetTemp, '
        'cameraGain: $cameraGain, '
        'cameraOffset: $cameraOffset, '
        'cameraBinX: $cameraBinX, '
        'cameraBinY: $cameraBinY, '
        'filterPosition: $filterPosition, '
        'focuserPosition: $focuserPosition, '
        'exposureTime: $exposureTime, '
        'capturedAt: $capturedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EquipmentSnapshot &&
        other.coolerTargetTemp == coolerTargetTemp &&
        other.cameraGain == cameraGain &&
        other.cameraOffset == cameraOffset &&
        other.cameraBinX == cameraBinX &&
        other.cameraBinY == cameraBinY &&
        other.filterPosition == filterPosition &&
        other.focuserPosition == focuserPosition &&
        other.exposureTime == exposureTime &&
        other.capturedAt == capturedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      coolerTargetTemp,
      cameraGain,
      cameraOffset,
      cameraBinX,
      cameraBinY,
      filterPosition,
      focuserPosition,
      exposureTime,
      capturedAt,
    );
  }
}

// =============================================================================
// QuickStartContext - Full context for quick session resumption
// =============================================================================

/// Contains all the information needed to quickly resume a previous session.
/// This includes session details, target info, sequence progress, and equipment state.
class QuickStartContext {
  /// Database ID of the session
  final int sessionId;

  /// User-provided session name
  final String? sessionName;

  /// Equipment profile ID used in this session
  final int? profileId;

  /// Equipment profile name
  final String? profileName;

  /// Target ID being imaged
  final int? targetId;

  /// Target name (e.g., "Orion Nebula")
  final String? targetName;

  /// Target right ascension in decimal hours
  final double? targetRa;

  /// Target declination in decimal degrees
  final double? targetDec;

  /// Sequence ID being executed
  final int? sequenceId;

  /// Sequence name
  final String? sequenceName;

  /// Number of frames completed in the sequence
  final int completedFrames;

  /// Total frames planned in the sequence
  final int totalFrames;

  /// When the session was last active
  final DateTime lastSessionDate;

  /// Captured equipment state
  final EquipmentSnapshot? equipmentSnapshot;

  /// Total integration time accumulated in hours
  final double totalIntegrationHours;

  const QuickStartContext({
    required this.sessionId,
    this.sessionName,
    this.profileId,
    this.profileName,
    this.targetId,
    this.targetName,
    this.targetRa,
    this.targetDec,
    this.sequenceId,
    this.sequenceName,
    this.completedFrames = 0,
    this.totalFrames = 0,
    required this.lastSessionDate,
    this.equipmentSnapshot,
    this.totalIntegrationHours = 0.0,
  });

  /// Calculate the percentage of frames completed
  double get progressPercentage {
    if (totalFrames == 0) return 0.0;
    return (completedFrames / totalFrames * 100).clamp(0.0, 100.0);
  }

  /// Check if the session has meaningful progress
  bool get hasProgress => completedFrames > 0 || totalIntegrationHours > 0;

  /// Check if this context has target coordinates
  bool get hasTargetCoordinates => targetRa != null && targetDec != null;

  /// Check if this context has equipment snapshot
  bool get hasEquipmentSnapshot =>
      equipmentSnapshot != null && equipmentSnapshot!.hasEquipmentData;

  /// Get a display-friendly session description
  String get displayDescription {
    final parts = <String>[];

    if (targetName != null) {
      parts.add(targetName!);
    } else if (sessionName != null) {
      parts.add(sessionName!);
    } else {
      parts.add('Session #$sessionId');
    }

    if (completedFrames > 0) {
      parts.add('$completedFrames/$totalFrames frames');
    }

    if (totalIntegrationHours > 0) {
      parts.add('${totalIntegrationHours.toStringAsFixed(1)}h');
    }

    return parts.join(' - ');
  }

  /// Get how long ago the session was active
  Duration get timeSinceLastSession {
    return DateTime.now().difference(lastSessionDate);
  }

  /// Check if this is a recent session (within 7 days)
  bool get isRecent {
    return timeSinceLastSession.inDays <= 7;
  }

  /// Check if this session was from tonight (within 12 hours)
  bool get isFromTonight {
    return timeSinceLastSession.inHours <= 12;
  }

  @override
  String toString() {
    return 'QuickStartContext('
        'sessionId: $sessionId, '
        'sessionName: $sessionName, '
        'targetName: $targetName, '
        'completedFrames: $completedFrames/$totalFrames, '
        'lastSessionDate: $lastSessionDate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuickStartContext &&
        other.sessionId == sessionId &&
        other.sessionName == sessionName &&
        other.profileId == profileId &&
        other.profileName == profileName &&
        other.targetId == targetId &&
        other.targetName == targetName &&
        other.targetRa == targetRa &&
        other.targetDec == targetDec &&
        other.sequenceId == sequenceId &&
        other.sequenceName == sequenceName &&
        other.completedFrames == completedFrames &&
        other.totalFrames == totalFrames &&
        other.lastSessionDate == lastSessionDate &&
        other.equipmentSnapshot == equipmentSnapshot &&
        other.totalIntegrationHours == totalIntegrationHours;
  }

  @override
  int get hashCode {
    return Object.hash(
      sessionId,
      sessionName,
      profileId,
      profileName,
      targetId,
      targetName,
      targetRa,
      targetDec,
      sequenceId,
      sequenceName,
      completedFrames,
      totalFrames,
      lastSessionDate,
      equipmentSnapshot,
      totalIntegrationHours,
    );
  }
}

// =============================================================================
// QuickStartService - Service for quick session resumption
// =============================================================================

/// Service for capturing and restoring session state for quick resumption.
///
/// This service provides functionality to:
/// - Capture current equipment state as a snapshot
/// - Save snapshots to session records
/// - Retrieve quick start context from recent sessions
/// - Determine if quick start is available
class QuickStartService {
  final SessionsDao sessionsDao;
  final EquipmentProfilesDao profilesDao;
  final TargetsDao targetsDao;
  final SequencesDao sequencesDao;
  final SequenceCheckpointsDao checkpointsDao;

  QuickStartService({
    required this.sessionsDao,
    required this.profilesDao,
    required this.targetsDao,
    required this.sequencesDao,
    required this.checkpointsDao,
  });

  /// Get the quick start context from the most recent recoverable session.
  ///
  /// This method retrieves the most recent session that has:
  /// - A status of 'active' (interrupted) or 'completed' within 7 days
  /// - Preference given to active sessions with progress
  ///
  /// Returns null if no suitable session is found.
  Future<QuickStartContext?> getQuickStartContext() async {
    debugPrint('QuickStartService: Getting quick start context...');

    // First, check for active (interrupted) sessions
    final activeSessions = await sessionsDao.getActiveSessions();
    if (activeSessions.isNotEmpty) {
      // Return the most recent active session
      final session = activeSessions.first;
      debugPrint(
          'QuickStartService: Found active session ${session.id} from ${session.startTime}');
      return _buildQuickStartContext(session);
    }

    // If no active sessions, look for recent completed sessions
    final recentSessions = await sessionsDao.getRecentSessions(limit: 10);

    // Filter to sessions within the last 7 days that have meaningful progress
    final candidateSessions = recentSessions.where((session) {
      final sessionAge = DateTime.now().difference(session.startTime);
      final hasProgress =
          session.successfulExposures > 0 || session.totalIntegrationSecs > 0;
      return sessionAge.inDays <= 7 && hasProgress;
    }).toList();

    if (candidateSessions.isEmpty) {
      debugPrint(
          'QuickStartService: No suitable sessions found for quick start');
      return null;
    }

    // Return the most recent completed session with progress
    final session = candidateSessions.first;
    debugPrint(
        'QuickStartService: Found recent session ${session.id} from ${session.startTime}');
    return _buildQuickStartContext(session);
  }

  /// Build a QuickStartContext from a session record.
  Future<QuickStartContext> _buildQuickStartContext(
      db.ImagingSession session) async {
    // Try to get extended session data (sequenceId, equipmentSnapshot) from raw SQL
    // since these fields may not be in the generated model yet
    final extendedData = await _getExtendedSessionData(session.id);
    final sequenceId = extendedData['sequenceId'] as int?;
    final equipmentSnapshotJson = extendedData['equipmentSnapshot'] as String?;

    // Fetch related data in parallel for efficiency
    final profileFuture = session.profileId != null
        ? profilesDao.getProfileById(session.profileId!)
        : Future<db.EquipmentProfile?>.value(null);

    final targetFuture = session.targetId != null
        ? targetsDao.getTargetById(session.targetId!)
        : Future<db.Target?>.value(null);

    final sequenceFuture = sequenceId != null
        ? sequencesDao.getSequenceById(sequenceId)
        : Future<db.Sequence?>.value(null);

    final checkpointFuture = sequenceId != null
        ? checkpointsDao.getCheckpoint(sequenceId)
        : Future<db.SequenceCheckpoint?>.value(null);

    // Wait for all futures to complete
    final results = await Future.wait<Object?>([
      profileFuture,
      targetFuture,
      sequenceFuture,
      checkpointFuture,
    ]);

    final profile = results[0] as db.EquipmentProfile?;
    final target = results[1] as db.Target?;
    final sequence = results[2] as db.Sequence?;
    final checkpoint = results[3] as db.SequenceCheckpoint?;

    // Parse equipment snapshot if available
    EquipmentSnapshot? equipmentSnapshot;
    if (equipmentSnapshotJson != null && equipmentSnapshotJson.isNotEmpty) {
      try {
        equipmentSnapshot =
            EquipmentSnapshot.fromJsonString(equipmentSnapshotJson);
      } catch (e) {
        debugPrint('QuickStartService: Failed to parse equipment snapshot: $e');
      }
    }

    // Get frame counts from checkpoint if available
    int completedFrames = 0;
    int totalFrames = 0;
    if (checkpoint != null) {
      completedFrames = checkpoint.completedFrames;
      totalFrames = checkpoint.totalFrames;
    } else {
      // Fall back to session stats
      completedFrames = session.successfulExposures;
      totalFrames = session.totalExposures;
    }

    // Calculate total integration in hours
    final totalIntegrationHours = session.totalIntegrationSecs / 3600.0;

    return QuickStartContext(
      sessionId: session.id,
      sessionName: session.name,
      profileId: session.profileId,
      profileName: profile?.name,
      targetId: session.targetId,
      targetName: target?.name,
      targetRa: target?.ra,
      targetDec: target?.dec,
      sequenceId: sequenceId,
      sequenceName: sequence?.name,
      completedFrames: completedFrames,
      totalFrames: totalFrames,
      lastSessionDate: session.endTime ?? session.startTime,
      equipmentSnapshot: equipmentSnapshot,
      totalIntegrationHours: totalIntegrationHours,
    );
  }

  /// Get extended session data that may not be in the generated model yet.
  /// Returns a map with 'sequenceId' and 'equipmentSnapshot' if available.
  Future<Map<String, dynamic>> _getExtendedSessionData(int sessionId) async {
    try {
      final database = sessionsDao.attachedDatabase;
      // Try to select the extended columns - they may not exist yet
      final result = await database.customSelect(
        'SELECT sequence_id, equipment_snapshot FROM imaging_sessions WHERE id = ?',
        variables: [Variable<int>(sessionId)],
      ).getSingleOrNull();

      if (result == null) {
        return {};
      }

      return {
        'sequenceId': result.data['sequence_id'] as int?,
        'equipmentSnapshot': result.data['equipment_snapshot'] as String?,
      };
    } catch (e) {
      // Columns may not exist yet - this is fine, return empty
      debugPrint('QuickStartService: Extended columns not available: $e');
      return {};
    }
  }

  /// Capture current equipment state as a snapshot.
  ///
  /// This method extracts relevant settings from the current device states
  /// and creates an EquipmentSnapshot that can be saved with a session.
  EquipmentSnapshot captureEquipmentSnapshot({
    required CameraState cameraState,
    required FilterWheelState filterWheelState,
    required FocuserState focuserState,
    double? exposureTime,
  }) {
    // Parse binning from camera state (format: "NxM" or just "N")
    int? binX;
    int? binY;
    if (cameraState.binning != null && cameraState.binning!.isNotEmpty) {
      final binningParts = cameraState.binning!.split('x');
      if (binningParts.length == 2) {
        binX = int.tryParse(binningParts[0]);
        binY = int.tryParse(binningParts[1]);
      } else if (binningParts.length == 1) {
        // Assume symmetric binning if only one value
        final bin = int.tryParse(binningParts[0]);
        binX = bin;
        binY = bin;
      }
    }

    return EquipmentSnapshot(
      coolerTargetTemp: cameraState.targetTemp,
      cameraGain: cameraState.gain,
      cameraOffset: cameraState.offset,
      cameraBinX: binX,
      cameraBinY: binY,
      filterPosition: filterWheelState.currentPosition,
      focuserPosition: focuserState.position,
      exposureTime: exposureTime,
      capturedAt: DateTime.now(),
    );
  }

  /// Save an equipment snapshot to a session record.
  ///
  /// The snapshot is serialized to JSON and stored in the session's
  /// equipmentSnapshot field.
  Future<void> saveEquipmentSnapshot(
      int sessionId, EquipmentSnapshot snapshot) async {
    debugPrint(
        'QuickStartService: Saving equipment snapshot for session $sessionId');

    try {
      final session = await sessionsDao.getSessionById(sessionId);
      if (session == null) {
        throw Exception('Session $sessionId not found');
      }

      final snapshotJson = snapshot.toJsonString();
      await sessionsDao.updateEquipmentSnapshot(sessionId, snapshotJson);
    } catch (e, stackTrace) {
      debugPrint('QuickStartService: Error saving equipment snapshot: $e');
      debugPrint('QuickStartService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Check if quick start is available.
  ///
  /// Quick start is available if there's a recent session (within 7 days)
  /// that has meaningful progress or an active (interrupted) session.
  Future<bool> isQuickStartAvailable() async {
    debugPrint('QuickStartService: Checking if quick start is available...');

    // Check for active sessions first
    final hasActive = await sessionsDao.hasIncompleteSessions();
    if (hasActive) {
      debugPrint(
          'QuickStartService: Quick start available (active session found)');
      return true;
    }

    // Check for recent completed sessions with progress
    final recentSessions = await sessionsDao.getRecentSessions(limit: 5);

    for (final session in recentSessions) {
      final sessionAge = DateTime.now().difference(session.startTime);
      final hasProgress =
          session.successfulExposures > 0 || session.totalIntegrationSecs > 0;

      if (sessionAge.inDays <= 7 && hasProgress) {
        debugPrint(
            'QuickStartService: Quick start available (recent session with progress found)');
        return true;
      }
    }

    debugPrint('QuickStartService: Quick start not available');
    return false;
  }

  /// Get multiple quick start contexts for displaying a list of resumable sessions.
  ///
  /// Returns up to [limit] sessions that are suitable for quick start,
  /// ordered by recency.
  Future<List<QuickStartContext>> getQuickStartContexts({int limit = 5}) async {
    debugPrint(
        'QuickStartService: Getting quick start contexts (limit: $limit)...');
    final contexts = <QuickStartContext>[];

    // Get active sessions first
    final activeSessions = await sessionsDao.getActiveSessions();
    for (final session in activeSessions) {
      if (contexts.length >= limit) break;
      contexts.add(await _buildQuickStartContext(session));
    }

    // If we need more, get recent completed sessions
    if (contexts.length < limit) {
      final recentSessions = await sessionsDao.getRecentSessions(
        limit: limit * 2, // Fetch extra to filter
      );

      for (final session in recentSessions) {
        if (contexts.length >= limit) break;

        // Skip if already included (from active sessions)
        if (contexts.any((c) => c.sessionId == session.id)) continue;

        // Skip if session is too old or has no progress
        final sessionAge = DateTime.now().difference(session.startTime);
        final hasProgress =
            session.successfulExposures > 0 || session.totalIntegrationSecs > 0;

        if (sessionAge.inDays <= 7 && hasProgress) {
          contexts.add(await _buildQuickStartContext(session));
        }
      }
    }

    debugPrint(
        'QuickStartService: Found ${contexts.length} quick start contexts');
    return contexts;
  }
}

// =============================================================================
// Providers
// =============================================================================

/// Provider for the QuickStartService
final quickStartServiceProvider = Provider<QuickStartService>((ref) {
  return QuickStartService(
    sessionsDao: ref.watch(sessionsDaoProvider),
    profilesDao: ref.watch(equipmentProfilesDaoProvider),
    targetsDao: ref.watch(targetsDaoProvider),
    sequencesDao: ref.watch(sequencesDaoProvider),
    checkpointsDao: ref.watch(sequenceCheckpointsDaoProvider),
  );
});

/// Provider for the quick start context (most recent session)
final quickStartContextProvider =
    FutureProvider<QuickStartContext?>((ref) async {
  final service = ref.watch(quickStartServiceProvider);
  return service.getQuickStartContext();
});

/// Provider for checking if quick start is available
final quickStartAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(quickStartServiceProvider);
  return service.isQuickStartAvailable();
});

/// Provider for multiple quick start contexts (for session list display)
final quickStartContextsProvider =
    FutureProvider.family<List<QuickStartContext>, int>((ref, limit) async {
  final service = ref.watch(quickStartServiceProvider);
  return service.getQuickStartContexts(limit: limit);
});
