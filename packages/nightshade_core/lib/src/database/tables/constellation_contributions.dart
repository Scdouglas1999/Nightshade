import 'package:drift/drift.dart';

/// Pillar C ("Constellation") persistence — per-(hub, tile) federation receipts.
///
/// The swarm shares one storage substrate and one solve hook with Pillars A/B,
/// which is exactly why an unguarded "contribute"/"pull" loop silently corrupts
/// the shared community co-add. This table is the durable receipt that makes the
/// federation idempotent and honest:
///
///   * CONTRIBUTION side — a per-tile high-water mark so re-contributing the
///     same field ships only the new night (true delta) instead of the whole
///     accumulator from epoch. The persisted [contributionId] is the remote
///     receipt id that also unblocks the privacy "Retract" action.
///   * PULL side — a per-tile high-water of the community depth last pulled, so
///     re-pulling a tile with no new community frames is a cheap no-op instead
///     of re-folding the entire community stack into the local overlay every
///     press.
///   * JOIN side — the joined-target rehydration row so a remote companion (or a
///     relaunched host) can re-render the user's federation state without a live
///     hub round-trip.
///
/// Identity is `(hubKey, tileId, healpixOrder)` — one receipt per tile per hub.
/// [hubKey] is the federation endpoint identity (a normalized hub base URL); the
/// service normalizes scheme+host+port before using it so a cosmetic URL change
/// (http/https, trailing slash, mDNS vs IP) does not orphan receipts.
///
/// Enum-ish/text columns are stored as stable text to match the convention in
/// `tables/sky_atlas_tables.dart` / `tables/narrator_events.dart`. This table is
/// intentionally additive and never references the atlas tables by FK: a deleted
/// or re-folded tile must not cascade-drop a federation receipt that still has a
/// live remote `contributionId`.
@DataClassName('ConstellationContributionRow')
@TableIndex(
  name: 'idx_constellation_contributions_key',
  unique: true,
  columns: {#hubKey, #tileId, #healpixOrder},
)
class ConstellationContributions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Federation endpoint identity — the normalized hub base URL.
  TextColumn get hubKey => text()();

  /// HEALPix NESTED pixel id this receipt is for.
  IntColumn get tileId => integer()();

  /// HEALPix order [tileId] was computed at (mirrors the atlas tables so a
  /// future order change is detectable rather than silently mis-addressing).
  IntColumn get healpixOrder => integer()();

  // --- Contribution high-water (true-delta export anchor) ------------------

  /// Anchor timestamp for the next `exportDelta(since:)` — the fold time of the
  /// newest own-light fold already shipped to this hub. Null = nothing shipped
  /// yet (anchor falls back to epoch, i.e. the first contribution ships all
  /// post-epoch own-light folds).
  DateTimeColumn get lastContributedAt => dateTime().nullable()();

  /// ISO fold label of the newest fold shipped (mirrors the fold-label scheme
  /// `capturedAt.toIso8601String()` used at fold time) — the human-readable
  /// twin of [lastContributedAt], retained so the export anchor can be matched
  /// against per-fold labels without re-deriving it from a timestamp.
  TextColumn get lastContributedLabel => text().nullable()();

  /// Remote receipt id returned by the hub for this tile's contribution.
  /// Unblocks the privacy "Retract" action (subtract exactly what was shipped).
  TextColumn get contributionId => text().nullable()();

  /// Running tally of own-light frames / integration shipped to this hub for
  /// this tile (cumulative across contributions).
  IntColumn get contributedFrames => integer().withDefault(const Constant(0))();
  RealColumn get contributedIntegrationSeconds =>
      real().withDefault(const Constant(0))();

  // --- Pull high-water (re-pull idempotency) -------------------------------

  /// Community depth last pulled for this tile, as advertised by the hub. A
  /// re-pull whose advertised frames equal this is a no-op (the overlay already
  /// holds exactly that snapshot). Null = never pulled.
  IntColumn get lastPulledFrames => integer().nullable()();
  RealColumn get lastPulledIntegrationSeconds => real().nullable()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  // --- Join rehydration ----------------------------------------------------

  /// Whether the user has joined the target this tile belongs to on this hub.
  BoolColumn get joined => boolean().withDefault(const Constant(false))();
  TextColumn get targetName => text().nullable()();
  RealColumn get targetRaDeg => real().nullable()();
  RealColumn get targetDecDeg => real().nullable()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
