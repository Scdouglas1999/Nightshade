import 'package:drift/drift.dart';

/// Living Sky (Pillars A/B/C) — Wave 3 retention bookkeeping.
///
/// Every Living Sky pillar accrues unbounded append-only state and re-reads it
/// hot: Pillar A's per-tile sidecars + cutout/delta cache, Pillar B's
/// `transient_detections` log, Pillar C's swarm `.nst`/`.fits` blobs. Wave 3
/// caps each with an age/size-bounded sweep run off the existing maintenance
/// schedule. This table is the durable "where did the last sweep get to" marker
/// for each of those sweeps, so a maintenance pass is incremental (resume from
/// the high-water) instead of re-scanning all history on every run — and so the
/// pruning stays cheap on the constrained Pi/appliance target after a heavy
/// season.
///
/// One row per [scope] (a stable string key — see [LivingSkyRetentionScope]),
/// keyed unique so a sweep does an upsert. The columns are deliberately generic
/// (a timestamp high-water + an int high-water + a free-form note) so every
/// pillar's sweep can record its own kind of progress without a bespoke table:
///
///   * [lastPrunedAt] — the most-recent record timestamp pruning has caught up
///     to (e.g. dismissed transients older than this are gone; swarm blobs last
///     swept at this wall-clock).
///   * [lastPrunedId] — a monotonic row/id high-water where a timestamp is too
///     coarse (e.g. the highest `transient_detections.id` considered).
///   * [prunedCount] — running tally of records reclaimed by this sweep, for
///     ops visibility in logs / a future "storage reclaimed" readout.
///   * [note] — free-form JSON/string the sweep owns (e.g. bytes reclaimed, the
///     configured retention window at last run).
///
/// Intentionally additive and FK-free: a retention marker must survive the
/// deletion of anything it tracks (that deletion is the whole point).
@DataClassName('LivingSkyRetentionRow')
@TableIndex(
  name: 'idx_living_sky_retention_scope',
  unique: true,
  columns: {#scope},
)
class LivingSkyRetention extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable sweep key — one of [LivingSkyRetentionScope]'s constants.
  TextColumn get scope => text()();

  /// Timestamp high-water the sweep has pruned up to (null = never run).
  DateTimeColumn get lastPrunedAt => dateTime().nullable()();

  /// Monotonic id high-water the sweep has considered (null = never run).
  IntColumn get lastPrunedId => integer().nullable()();

  /// Running count of records reclaimed across all runs of this sweep.
  IntColumn get prunedCount => integer().withDefault(const Constant(0))();

  /// Free-form note the sweep owns (e.g. bytes reclaimed, retention window).
  TextColumn get note => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Stable [LivingSkyRetention.scope] keys, one per Wave 3 sweep. Kept as
/// constants (not an enum) so a forward-compatible reader/writer degrades
/// gracefully and a new sweep can be added without a schema change.
abstract final class LivingSkyRetentionScope {
  /// Pillar B — `transient_detections` age-out of dismissed/artefact rows.
  static const String transientDetections = 'transient_detections';

  /// Pillar A — `<atlasRoot>/cache` cutout/delta LRU sweep.
  static const String atlasCache = 'atlas_cache';

  /// Pillar C — `<atlasRoot>/swarm` pull/delta blob sweep.
  static const String swarmBlobs = 'swarm_blobs';
}
