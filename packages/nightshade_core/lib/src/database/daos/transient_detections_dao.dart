import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_provider.dart';
import '../database.dart';
import '../tables/transient_detections.dart';

part 'transient_detections_dao.g.dart';

/// Data access for [TransientDetections] — the Pillar B ("First Light")
/// difference-imaging transient log.
///
/// Feeds read **newest-first**: a fresh detection is the one a user wants to
/// triage. Dismissed rows are kept (never deleted) so the difference pipeline
/// can suppress a residual a human has already judged an artefact rather than
/// re-announcing it every clear night — [dismissedTileSignatures] exposes that
/// suppression set.
@DriftAccessor(tables: [TransientDetections])
class TransientDetectionsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$TransientDetectionsDaoMixin {
  TransientDetectionsDao(super.db);

  /// Insert one detection row, returning its assigned id.
  Future<int> insertDetection(TransientDetectionsCompanion detection) {
    return into(transientDetections).insert(detection);
  }

  /// Insert a batch of detections from a single scan in one transaction.
  Future<void> insertDetections(
    List<TransientDetectionsCompanion> detections,
  ) async {
    if (detections.isEmpty) return;
    await batch((b) => b.insertAll(transientDetections, detections));
  }

  /// All detections for a session, newest-first.
  Future<List<TransientDetectionRow>> detectionsForSession(int sessionId) {
    return (select(transientDetections)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
        .get();
  }

  /// Reactive newest-first feed for a session.
  Stream<List<TransientDetectionRow>> watchDetectionsForSession(int sessionId) {
    return (select(transientDetections)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
        .watch();
  }

  /// Every detection (across sessions), newest-first — backs the standalone
  /// transient gallery and the export hub's candidate snapshot.
  Future<List<TransientDetectionRow>> allDetections() {
    return (select(
      transientDetections,
    )..orderBy([(t) => OrderingTerm.desc(t.detectedAt)])).get();
  }

  /// Reactive variant of [allDetections].
  Stream<List<TransientDetectionRow>> watchAllDetections() {
    return (select(
      transientDetections,
    )..orderBy([(t) => OrderingTerm.desc(t.detectedAt)])).watch();
  }

  /// A single detection by id, or null if it has been removed.
  Future<TransientDetectionRow?> detectionById(int id) {
    return (select(
      transientDetections,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Coarse `(tileId, rounded-ra, rounded-dec)` signatures of dismissed
  /// detections. The difference pipeline matches a new residual against this
  /// set (within a small positional tolerance, done in the service) to skip
  /// re-announcing a residual a human has already dismissed as an artefact.
  Future<List<TransientDetectionRow>> dismissedDetections() {
    return (select(
      transientDetections,
    )..where((t) => t.dismissed.equals(true))).get();
  }

  /// Mark a detection reviewed; [dismissed] flags it as a triaged artefact.
  Future<void> markReviewed(int id, {bool dismissed = false}) async {
    await (update(transientDetections)..where((t) => t.id.equals(id))).write(
      TransientDetectionsCompanion(
        reviewed: const Value(true),
        dismissed: Value(dismissed),
      ),
    );
  }
}

/// Riverpod provider for [TransientDetectionsDao].
final transientDetectionsDaoProvider = Provider<TransientDetectionsDao>((ref) {
  return TransientDetectionsDao(ref.watch(databaseProvider));
});
