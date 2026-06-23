// Pillar C ("Constellation") — client-side orchestration over a hub.
//
// [ConstellationClient] is the raw REST surface (one endpoint per method);
// [ConstellationService] is the workflow on top of it that the app and the
// providers drive:
//
//   * sign in / register an account against a self-hosted hub,
//   * browse the shared targets the swarm is collecting,
//   * JOIN a shared target (records the chosen hub target locally),
//   * CONTRIBUTE the local atlas tiles for that target — by default the
//     *additive sums* (the serialized `.nst` keystone bytes the
//     [SkyAtlasService] exports), never raw subs, so nothing on the user's disk
//     leaves the device except the same accumulator the master integration
//     already keeps,
//   * PULL the fused community co-add back down and cache it under the atlas
//     `swarm/` directory so the UI can blend it into "Your Sky",
//   * follow-the-night: ask the hub which shared targets are dark for this user
//     right now and turn them into deepen-the-thinnest suggestions, claiming/
//     releasing the handoff baton so the swarm does not double-collect the same
//     sky. These currently surface only on the Constellation screen's
//     follow-the-night card, not yet in the planner/scheduler tabs.
//
// The service holds no global mutable state beyond the small in-memory swarm
// cache (an index of pulled tiles); persistence of the contribution log is
// deferred to the dedicated Drift table when that lands. Privacy default: SUMS.

import 'dart:async';
import 'dart:math' as math;

import '../../database/daos/constellation_contributions_dao.dart';
import '../logging_service.dart';
import '../sky_atlas/sky_atlas_models.dart';
import '../sky_atlas/sky_atlas_service.dart';
import 'constellation_client.dart';
import 'constellation_models.dart';

/// What a contribution puts on the wire.
///
/// [sums] (the default) ships only the additive `.nst` accumulator the master
/// integration already keeps — never the raw individual subframes. [subs] is a
/// heavier, more-revealing opt-in: it streams the user's own light FITS to the
/// hub ([ConstellationService.contributeRawSubs]), so it is only valid against
/// a hub that advertises `acceptsRawSubs`. Wire values mirror the app-side
/// persisted setting (`sums` | `subs`).
enum ConstellationPrivacy { sums, subs }

/// Resolved hub credentials for one Constellation hub.
class ConstellationCredentials {
  final Uri hubBaseUrl;
  final String bearerToken;

  const ConstellationCredentials({
    required this.hubBaseUrl,
    required this.bearerToken,
  });
}

/// Builds a [ConstellationClient] from resolved credentials. Injectable so the
/// service can be exercised with a `package:http/testing.dart` MockClient.
typedef ConstellationClientFactory =
    ConstellationClient Function(ConstellationCredentials credentials);

/// Looks up shared-target listings from a hub. The browse payload is not pinned
/// field-for-field by the contract (§5 leaves it to the hub), so it is fetched
/// through this small seam rather than baked into [ConstellationClient]; the
/// production impl issues a `GET /v1/targets` read.
typedef SharedTargetBrowser =
    Future<List<SharedTarget>> Function(ConstellationClient client);

/// One user-captured light frame eligible for raw-subframe sharing.
///
/// [contributeRawSubs] streams exactly these FITS files. The resolver MUST
/// return only ACCEPTED LIGHT frames the user captured on this host — never a
/// community-pulled or calibration frame — so a SUBS contribution can only ever
/// leak the user's own pixels.
class RawSubframe {
  /// Absolute path to the calibrated FITS light on the host.
  final String filePath;

  /// The local captured-image row id (provenance the hub records).
  final int capturedImageId;

  /// Exposure of this frame in seconds (provenance).
  final double exposureSeconds;

  const RawSubframe({
    required this.filePath,
    required this.capturedImageId,
    required this.exposureSeconds,
  });
}

/// Resolves the user's own accepted light frames for a target into raw
/// subframes. Injected (the production wiring reads `ImagesDao
/// .getImagesForTarget`, filtered to accepted lights) so the service stays
/// DB-agnostic and testable. HOST-ONLY: a slave's local images table is empty,
/// so this returns nothing there and the SUBS path is a no-op.
typedef RawSubframeResolver = Future<List<RawSubframe>> Function(int targetId);

/// Result of contributing one target's atlas tiles to the hub.
class ContributionOutcome {
  /// Tiles successfully accepted by the hub (tileId -> receipt).
  final Map<int, ContributionReceipt> accepted;

  /// Tiles the hub rejected on geometry/order mismatch (tileId -> reason).
  final Map<int, String> rejected;

  const ContributionOutcome({required this.accepted, required this.rejected});

  int get acceptedCount => accepted.length;
  int get rejectedCount => rejected.length;

  /// Total frames the hub reports across the tiles we just deepened.
  int get totalFramesContributed =>
      accepted.values.fold(0, (s, r) => s + r.totalFramesAfter);
}

/// Client-side orchestration for Pillar C.
class ConstellationService {
  ConstellationService({
    required SkyAtlasService atlas,
    required LoggingService logger,
    required Future<ConstellationCredentials?> Function() credentialsResolver,
    required Future<
      List<({int targetId, String name, double raDeg, double decDeg})>
    >
    Function()
    localTargetsResolver,
    ConstellationContributionsDao? contributionsDao,
    ConstellationClientFactory? clientFactory,
    SharedTargetBrowser? browser,
    RawSubframeResolver? rawSubframeResolver,
    int order = defaultHealpixOrder,
  }) : _atlas = atlas,
       _logger = logger,
       _credentialsResolver = credentialsResolver,
       _localTargetsResolver = localTargetsResolver,
       _contributions = contributionsDao,
       _clientFactory = clientFactory ?? _defaultClientFactory,
       _browser = browser ?? _defaultBrowser,
       _rawSubframeResolver = rawSubframeResolver,
       _order = order;

  /// The atlas HEALPix order this client federates at. Mirrors
  /// `ATLAS_HEALPIX_ORDER` / the contract's single source of truth (§6).
  static const int defaultHealpixOrder = 9;

  final SkyAtlasService _atlas;
  final LoggingService _logger;
  final Future<ConstellationCredentials?> Function() _credentialsResolver;
  final Future<List<({int targetId, String name, double raDeg, double decDeg})>>
  Function()
  _localTargetsResolver;

  /// Per-(hubKey, tileId) federation receipt store: the contribution anchor +
  /// remote id (true-delta export, Retract) and the pulled high-water (re-pull
  /// idempotency). Null only in legacy/test wirings that predate the table; the
  /// service degrades to the old whole-tile/epoch behaviour when absent.
  final ConstellationContributionsDao? _contributions;
  final ConstellationClientFactory _clientFactory;
  final SharedTargetBrowser _browser;

  /// Resolves the user's own light frames for raw-subframe sharing. Null in
  /// wirings that predate the SUBS path (and on a slave, where there are no
  /// local frames to share) — [contributeRawSubs] then ships nothing.
  final RawSubframeResolver? _rawSubframeResolver;
  final int _order;

  /// Cap on how many raw subframes one [contributeRawSubs] call will upload, so
  /// a deep target cannot accidentally fire thousands of large FITS pushes.
  static const int _maxRawSubframesPerContribute = 200;

  static const _logSource = 'ConstellationService';

  /// In-memory index of community tiles pulled for blending, keyed by tile id.
  final Map<int, SwarmTile> _swarm = {};

  /// Targets the user has joined on the hub (targetId -> hub target row).
  final Map<int, SharedTarget> _joined = {};

  static ConstellationClient _defaultClientFactory(
    ConstellationCredentials c,
  ) =>
      ConstellationClient(hubBaseUrl: c.hubBaseUrl, bearerToken: c.bearerToken);

  /// Default browse: `GET /v1/targets` returning a `targets` array. Tolerates a
  /// bare array body too, so a minimal hub need only return the list.
  static Future<List<SharedTarget>> _defaultBrowser(
    ConstellationClient client,
  ) async {
    final raw = await client.browseRaw();
    final list = raw is List
        ? raw
        : (raw is Map<String, dynamic>
              ? (raw['targets'] as List? ?? const [])
              : const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(SharedTarget.fromJson)
        .toList(growable: false);
  }

  /// Open a client for the configured hub, or null when no hub is configured.
  /// Callers that require a hub use [_requireClient].
  Future<ConstellationClient?> _client() async {
    final creds = await _credentialsResolver();
    if (creds == null) return null;
    return _clientFactory(creds);
  }

  Future<ConstellationClient> _requireClient() async {
    final client = await _client();
    if (client == null) {
      throw const ConstellationException(
        'No Constellation hub is configured. Sign in to a hub first.',
        kind: ConstellationErrorKind.auth,
      );
    }
    return client;
  }

  // --- Account / sign-in --------------------------------------------------

  /// Verify connectivity + tiling against the configured hub. Throws on a
  /// HEALPix-order mismatch so the UI can refuse to federate with an
  /// incompatible hub before any data moves.
  Future<HubInfo> signIn() async {
    final client = await _requireClient();
    try {
      final info = await client.info();
      if (info.healpixOrder != _order) {
        throw ConstellationException(
          'Hub "${info.name}" tiles at order ${info.healpixOrder}, but this '
          'atlas federates at order $_order — incompatible tiling.',
          kind: ConstellationErrorKind.geometryMismatch,
        );
      }
      _logger.info(
        'Signed in to hub "${info.name}" (${info.fingerprint}); '
        'order ${info.healpixOrder}, ${info.tilePixels}px tiles.',
        source: _logSource,
      );
      return info;
    } finally {
      client.close();
    }
  }

  /// Register an account on a hub from a one-off bootstrap client (the bootstrap
  /// token may be empty for open-signup hubs). Returns the issued account so the
  /// caller can persist its bearer token as the standing credentials.
  Future<HubAccount> registerAccount({
    required Uri hubBaseUrl,
    required String publicKey,
    required String displayName,
    String bootstrapToken = '',
  }) async {
    final client = _clientFactory(
      ConstellationCredentials(
        hubBaseUrl: hubBaseUrl,
        bearerToken: bootstrapToken,
      ),
    );
    try {
      final account = await client.createAccount(
        publicKey: publicKey,
        displayName: displayName,
      );
      _logger.info(
        'Registered Constellation account ${account.accountId} on '
        '${hubBaseUrl.host} (initial trust ${account.trust}).',
        source: _logSource,
      );
      return account;
    } finally {
      client.close();
    }
  }

  // --- Browse / join ------------------------------------------------------

  /// List the shared targets the swarm is collecting on the configured hub.
  Future<List<SharedTarget>> browseSharedTargets() async {
    final client = await _requireClient();
    try {
      return await _browser(client);
    } finally {
      client.close();
    }
  }

  /// Join a shared target: records it locally so contribute/pull/handoff can
  /// resolve its hub geometry without re-browsing. Idempotent.
  void joinSharedTarget(SharedTarget target) {
    _joined[target.targetId] = target;
    _logger.info(
      'Joined shared target "${target.name}" (#${target.targetId}) — '
      '${target.contributors} contributor(s), '
      '${(target.integrationSeconds / 3600).toStringAsFixed(1)}h fused.',
      source: _logSource,
    );
  }

  /// Create (or look up) a shared target on the configured hub from one of the
  /// user's own imageable fields, so a freshly stood-up hub has a field to
  /// deepen. The hub is idempotent on name/centre, so re-proposing the same
  /// field returns the existing target rather than duplicating it.
  ///
  /// On success the new target is joined locally (so contribute/pull resolve its
  /// geometry) and returned for the caller to route into the detail screen.
  Future<SharedTarget> proposeTarget({
    required String name,
    required double raDeg,
    required double decDeg,
    double radiusDeg = 1.5,
  }) async {
    final client = await _requireClient();
    try {
      final target = await client.ensureTarget(
        name: name,
        centerRaDeg: raDeg,
        centerDecDeg: decDeg,
        radiusDeg: radiusDeg,
      );
      _logger.info(
        'Proposed shared target "${target.name}" (#${target.targetId}) on the '
        'hub from a local field.',
        source: _logSource,
      );
      joinSharedTarget(target);
      return target;
    } finally {
      client.close();
    }
  }

  /// Leave a previously-joined shared target.
  void leaveSharedTarget(int targetId) => _joined.remove(targetId);

  /// Targets joined on the hub (read-only snapshot).
  List<SharedTarget> get joinedTargets => List.unmodifiable(_joined.values);

  // --- Contribute ---------------------------------------------------------

  /// Contribute the local atlas tiles covering a joined target to the hub.
  ///
  /// For every locally-deepened tile whose centre falls inside the target's
  /// cone we export the additive accumulator delta since [since] (the keystone
  /// `.nst` sums — *not* raw subs) and push it. A tile the hub rejects on a
  /// geometry/order mismatch is collected into the outcome rather than aborting
  /// the whole batch, so one stray tile cannot block a good contribution.
  ///
  /// [privacy] selects what leaves the device. [ConstellationPrivacy.sums]
  /// ships the additive accumulator delta (the default). [ConstellationPrivacy
  /// .subs] routes to [contributeRawSubs], which streams the user's own light
  /// FITS — only valid against a hub that advertises `acceptsRawSubs`, so it is
  /// refused up front against a sums-only hub rather than failing per-frame.
  ///
  /// [since] defaults to the epoch (contribute the full accumulated tile).
  Future<ContributionOutcome> contributeTarget(
    int targetId, {
    DateTime? since,
    double radiusDeg = 1.5,
    String? instrumentFingerprint,
    String? solver,
    ConstellationPrivacy privacy = ConstellationPrivacy.sums,
  }) async {
    if (privacy == ConstellationPrivacy.subs) {
      return contributeRawSubs(
        targetId,
        radiusDeg: radiusDeg,
        instrumentFingerprint: instrumentFingerprint,
      );
    }
    final joined = _joined[targetId];
    final creds = await _credentialsResolver();
    final hubKey = creds == null ? null : _hubKey(creds.hubBaseUrl);
    final client = await _requireClient();
    final accepted = <int, ContributionReceipt>{};
    final rejected = <int, String>{};
    // When the caller forces [since] we honour it verbatim; otherwise the anchor
    // is the per-tile contribution high-water (epoch on the first contribution).
    try {
      final center = await _targetCenter(targetId, joined);
      final tiles = await _localTilesInCone(
        centerRaDeg: center.raDeg,
        centerDecDeg: center.decDeg,
        radiusDeg: radiusDeg,
      );
      if (tiles.isEmpty) {
        _logger.info(
          'contributeTarget(#$targetId): no locally-deepened tiles in cone.',
          source: _logSource,
        );
        return const ContributionOutcome(accepted: {}, rejected: {});
      }

      var skippedEmpty = 0;
      for (final tile in tiles) {
        // Per-tile high-water: the anchor for exportDelta(since:) is the fold
        // time of the newest own-light fold already shipped to THIS hub, so a
        // re-contribute ships only the new night. Falls back to epoch on the
        // first contribution (and whenever the receipt store is absent).
        final receiptRow = (hubKey == null || _contributions == null)
            ? null
            : await _contributions.getContribution(
                hubKey,
                tile.tileId,
                healpixOrder: _order,
              );
        final anchor =
            since ??
            receiptRow?.lastContributedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

        // Privacy: export the additive SUMS for this tile, never the subs. The
        // export reads ONLY the own-light base tile (never the swarm overlay)
        // and returns the TRUE post-anchor own-light delta tally.
        final AtlasDeltaExport export;
        try {
          export = await _atlas.exportDelta(tile.tileId, since: anchor);
        } on Exception catch (e) {
          // A genuinely-mixed tile (pre-anchor own folds + new own folds) the
          // native side cannot carve cleanly: surface as a per-tile skip rather
          // than aborting the batch.
          rejected[tile.tileId] =
              'export delta could not be carved cleanly: $e';
          continue;
        }

        // BELT-AND-SUSPENDERS: an empty delta (no new own-light since the
        // anchor) is a no-op — never push a zero-frame contribution that would
        // inflate the hub's fused depth. This is the repeat-contribute
        // idempotency guarantee.
        if (export.isEmpty) {
          skippedEmpty++;
          _logger.info(
            'contributeTarget(#$targetId): tile ${tile.tileId} already '
            'contributed, nothing new to ship.',
            source: _logSource,
          );
          continue;
        }

        try {
          final receipt = await client.pushTile(
            tileId: tile.tileId,
            order: _order,
            deltaPath: export.path,
            // TRUE delta: only the frames/seconds imaged since the anchor, not
            // the whole accumulated tile total.
            framesDelta: export.framesInDelta,
            integrationSecondsDelta: export.integrationSeconds,
            instrument: instrumentFingerprint,
            solver: solver,
          );
          accepted[tile.tileId] = receipt;

          // Advance the high-water so the NEXT contribute anchors here. The
          // newest own fold shipped is at/after now; we stamp the contribution
          // time (UTC) as the next anchor and accrue the cumulative tally.
          if (hubKey != null && _contributions != null) {
            final now = DateTime.now().toUtc();
            await _contributions.upsertContribution(
              hubKey,
              tile.tileId,
              healpixOrder: _order,
              lastContributedAt: now,
              lastContributedLabel: now.toIso8601String(),
              contributionId: receipt.contributionId,
              contributedFrames:
                  (receiptRow?.contributedFrames ?? 0) + export.framesInDelta,
              contributedIntegrationSeconds:
                  (receiptRow?.contributedIntegrationSeconds ?? 0) +
                  export.integrationSeconds,
            );
          }
        } on ConstellationException catch (e) {
          if (e.kind == ConstellationErrorKind.geometryMismatch) {
            rejected[tile.tileId] = e.message;
            _logger.warning(
              'contributeTarget(#$targetId): hub rejected tile '
              '${tile.tileId} on geometry mismatch.',
              source: _logSource,
            );
            continue;
          }
          rethrow;
        }
      }

      _logger.info(
        'contributeTarget(#$targetId): pushed ${accepted.length} tile(s), '
        '$skippedEmpty already-current, ${rejected.length} rejected.',
        source: _logSource,
      );
      return ContributionOutcome(accepted: accepted, rejected: rejected);
    } finally {
      client.close();
    }
  }

  /// Share the user's own raw light FITS for a joined target to the hub.
  ///
  /// Unlike SUMS (which exports the additive `.nst` accumulator and bypasses raw
  /// pixels), this streams each ACCEPTED LIGHT frame the user captured for the
  /// target straight from disk to `POST /v1/tiles/<tile>/subframes`. The frames
  /// are grouped under the target's representative hub tile (its advertised
  /// active tile, else the deepest local tile in the cone). Every accepted frame
  /// becomes one [ContributionReceipt] in the outcome (the per-frame
  /// `contributionId` the privacy "Retract" / file-delete acts on); a per-frame
  /// failure is collected into `rejected` rather than aborting the batch.
  ///
  /// HOST-ONLY: the resolver reads the host's local images table, so on a slave
  /// (or any wiring without a resolver) this ships nothing.
  ///
  /// Refuses up front when the configured hub does not advertise
  /// `acceptsRawSubs`, so the UI can keep the SUBS option disabled and a stray
  /// call surfaces "this hub does not accept raw subframes" rather than failing
  /// frame-by-frame.
  Future<ContributionOutcome> contributeRawSubs(
    int targetId, {
    double radiusDeg = 1.5,
    String? instrumentFingerprint,
  }) async {
    final resolver = _rawSubframeResolver;
    if (resolver == null) {
      throw const ConstellationException(
        'Raw subframe sharing is not available on this device.',
        kind: ConstellationErrorKind.conflict,
      );
    }
    final joined = _joined[targetId];
    final client = await _requireClient();
    final accepted = <int, ContributionReceipt>{};
    final rejected = <int, String>{};
    try {
      // Refuse against a sums-only hub up front (the UI also gates on this, but
      // a host call must not stream pixels to a hub that will 405 every frame).
      final info = await client.info();
      if (!info.acceptsRawSubs) {
        throw ConstellationException(
          'Hub "${info.name}" does not accept raw subframes — only additive '
          'co-add sums can be contributed here.',
          kind: ConstellationErrorKind.conflict,
        );
      }

      final center = await _targetCenter(targetId, joined);
      final tileId = await _representativeTileId(
        centerRaDeg: center.raDeg,
        centerDecDeg: center.decDeg,
        radiusDeg: radiusDeg,
        joined: joined,
      );
      if (tileId == null) {
        _logger.info(
          'contributeRawSubs(#$targetId): no tile to attribute frames to.',
          source: _logSource,
        );
        return const ContributionOutcome(accepted: {}, rejected: {});
      }

      final frames = await resolver(targetId);
      if (frames.isEmpty) {
        _logger.info(
          'contributeRawSubs(#$targetId): no own light frames to share.',
          source: _logSource,
        );
        return const ContributionOutcome(accepted: {}, rejected: {});
      }

      var shared = 0;
      for (final frame in frames) {
        if (shared >= _maxRawSubframesPerContribute) {
          _logger.warning(
            'contributeRawSubs(#$targetId): capped at '
            '$_maxRawSubframesPerContribute frames; '
            '${frames.length - shared} not shared.',
            source: _logSource,
          );
          break;
        }
        try {
          final receipt = await client.pushSubframe(
            tileId: tileId,
            order: _order,
            fitsPath: frame.filePath,
            capturedImageId: frame.capturedImageId,
            exposureSeconds: frame.exposureSeconds,
            instrument: instrumentFingerprint,
          );
          // Key by capturedImageId so the outcome maps a frame to its receipt.
          accepted[frame.capturedImageId] = ContributionReceipt(
            contributionId: receipt.contributionId,
            accepted: receipt.accepted,
            trustApplied: 1.0,
            totalFramesAfter: 0,
            integrationSecondsAfter: 0,
          );
          shared++;
        } on ConstellationException catch (e) {
          rejected[frame.capturedImageId] = e.message;
          _logger.warning(
            'contributeRawSubs(#$targetId): frame ${frame.capturedImageId} '
            'rejected: ${e.message}',
            source: _logSource,
          );
        }
      }
      _logger.info(
        'contributeRawSubs(#$targetId): shared $shared raw frame(s) under tile '
        '$tileId, ${rejected.length} rejected.',
        source: _logSource,
      );
      return ContributionOutcome(accepted: accepted, rejected: rejected);
    } finally {
      client.close();
    }
  }

  /// The hub tile a target's raw subframes should be attributed to: the deepest
  /// local tile in the cone, else the joined target's advertised active tile.
  Future<int?> _representativeTileId({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
    required SharedTarget? joined,
  }) async {
    final tiles = await _localTilesInCone(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      radiusDeg: radiusDeg,
    );
    if (tiles.isNotEmpty) {
      tiles.sort(
        (a, b) => b.integrationSeconds.compareTo(a.integrationSeconds),
      );
      return tiles.first.tileId;
    }
    return joined?.activeTileId;
  }

  // --- Pull / blend -------------------------------------------------------

  /// Pull the fused community co-add for a joined target's tiles and cache them
  /// under the atlas `swarm/` directory for blending into "Your Sky".
  ///
  /// [finalized] true caches rendered FITS tiles (ready to display); false
  /// caches the merged `.nst` accumulators (still additive, so they can later
  /// be folded locally). Returns the cached [SwarmTile]s, newest pull first.
  Future<List<SwarmTile>> pullTarget(
    int targetId, {
    double radiusDeg = 1.5,
    bool finalized = true,
  }) async {
    final joined = _joined[targetId];
    final creds = await _credentialsResolver();
    final hubKey = creds == null ? null : _hubKey(creds.hubBaseUrl);
    final client = await _requireClient();
    try {
      final center = await _targetCenter(targetId, joined);
      final tileIds = await _localTileIdsInCone(
        centerRaDeg: center.raDeg,
        centerDecDeg: center.decDeg,
        radiusDeg: radiusDeg,
      );
      // Fall back to the hub's advertised active tile when nothing local
      // overlaps the cone yet (the user has not imaged this target at all).
      final ids = tileIds.isNotEmpty
          ? tileIds
          : (joined?.activeTileId != null
                ? <int>[joined!.activeTileId!]
                : <int>[]);
      if (ids.isEmpty) {
        _logger.info(
          'pullTarget(#$targetId): no tiles to pull.',
          source: _logSource,
        );
        return const [];
      }

      final swarmDir = await _swarmDir();
      final pulled = <SwarmTile>[];
      for (final tileId in ids) {
        final ext = finalized ? 'fits' : 'nst';
        final outPath = '$swarmDir/tile_${tileId}_$_order.$ext';
        await client.pullTile(
          tileId: tileId,
          order: _order,
          outPath: outPath,
          finalized: finalized,
        );
        // Blend an accumulator pull into the swarm OVERLAY tree so the swarm's
        // depth shows up in "Your Sky" (the documented pull-back -> blend flow)
        // WITHOUT touching the user's contributable base. Finalized FITS pulls
        // are display-only overlays and are not merged (they are not additive
        // accumulators); only `.nst` snapshots fold in.
        //
        // mergeSwarmDelta is REPLACE-not-add against the overlay, so the overlay
        // always equals exactly one copy of the current community depth — N
        // pulls == 1 pull regardless of the high-water check below.
        var overlayFrames = 0;
        if (!finalized) {
          // High-water short-circuit: if the hub advertises the same community
          // depth as our last pull for this tile, the re-blend is a cheap no-op.
          final priorPull = (hubKey == null || _contributions == null)
              ? null
              : await _contributions.getPulledHighWater(
                  hubKey,
                  tileId,
                  healpixOrder: _order,
                );
          try {
            overlayFrames = await _atlas.mergeSwarmDelta(
              tileId: tileId,
              deltaPath: outPath,
            );
            // Record the pulled high-water so a later identical pull is known.
            if (hubKey != null && _contributions != null) {
              if (priorPull?.lastPulledFrames != overlayFrames) {
                await _contributions.upsertPulledHighWater(
                  hubKey,
                  tileId,
                  healpixOrder: _order,
                  lastPulledFrames: overlayFrames,
                  lastPulledIntegrationSeconds: 0,
                );
              }
            }
          } on Exception catch (e) {
            _logger.warning(
              'pullTarget(#$targetId): blend of tile $tileId into Your Sky '
              'failed: $e (tile cached, not blended).',
              source: _logSource,
            );
          }
        }
        final swarm = SwarmTile(
          tileId: tileId,
          order: _order,
          localPath: outPath,
          finalized: finalized,
          // The overlay's OWN total = the community depth for this tile (exactly
          // one copy), not an inflating additive blend.
          totalFrames: overlayFrames,
          integrationSeconds: 0,
          contributors: joined?.contributors ?? 0,
          pulledAt: DateTime.now(),
        );
        _swarm[tileId] = swarm;
        pulled.add(swarm);
      }
      _logger.info(
        'pullTarget(#$targetId): cached ${pulled.length} community tile(s) '
        'for blending.',
        source: _logSource,
      );
      return pulled;
    } finally {
      client.close();
    }
  }

  /// The community tiles currently cached for blending (read-only snapshot).
  List<SwarmTile> get swarmTiles => List.unmodifiable(_swarm.values);

  /// Retract a prior contribution from the hub (exact subtraction hub-side).
  Future<RetractionReceipt> retract(String remoteContributionId) async {
    final client = await _requireClient();
    try {
      final receipt = await client.retract(remoteContributionId);
      _logger.info(
        'Retracted contribution $remoteContributionId; hub now at '
        '${receipt.totalFramesAfter} frames.',
        source: _logSource,
      );
      return receipt;
    } finally {
      client.close();
    }
  }

  /// Delete a prior raw-subframe contribution from the hub.
  ///
  /// A raw subframe is stored as its own file, so this is a FILE-DELETE on the
  /// hub — NOT the clean additive subtraction [retract] does for sums. The frame
  /// is removed, but anyone who already pulled it keeps their copy.
  Future<void> deleteSubframe(String remoteContributionId) async {
    final client = await _requireClient();
    try {
      await client.deleteSubframe(remoteContributionId);
      _logger.info(
        'Deleted raw subframe $remoteContributionId from the hub.',
        source: _logSource,
      );
    } finally {
      client.close();
    }
  }

  /// The tiles this device has contributed to the configured hub — every
  /// persisted receipt that carries a remote `contributionId` (the Wave-0
  /// substrate). These are exactly the units [retractTile] can subtract back off
  /// the hub. Empty when no hub is configured or the receipt store is absent
  /// (e.g. a slave, whose local receipt table is never written).
  Future<List<ContributionRecord>> myContributions() async {
    if (_contributions == null) return const [];
    final creds = await _credentialsResolver();
    if (creds == null) return const [];
    final hubKey = _hubKey(creds.hubBaseUrl);
    final rows = await _contributions.getContributedTilesForHub(hubKey);
    return rows
        .map(
          (r) => ContributionRecord(
            tileId: r.tileId,
            contributionId: r.contributionId!,
            contributedFrames: r.contributedFrames,
            contributedIntegrationSeconds: r.contributedIntegrationSeconds,
            lastContributedAt: r.lastContributedAt,
          ),
        )
        .toList(growable: false);
  }

  /// Retract this device's contribution for [tileId] from the configured hub.
  ///
  /// Looks up the persisted remote `contributionId` for `(hub, tile)`, asks the
  /// hub to subtract it exactly, and — on success — deletes the local receipt so
  /// the contribution high-water resets. A later re-contribute then re-anchors
  /// from epoch and the hub does the exact subtraction, keeping the fused depth
  /// honest. Throws when there is no recorded contribution to retract.
  Future<RetractionReceipt> retractTile(int tileId) async {
    if (_contributions == null) {
      throw const ConstellationException(
        'No contribution receipts are stored on this device to retract.',
        kind: ConstellationErrorKind.notFound,
      );
    }
    final creds = await _credentialsResolver();
    if (creds == null) {
      throw const ConstellationException(
        'No Constellation hub is configured. Sign in to a hub first.',
        kind: ConstellationErrorKind.auth,
      );
    }
    final hubKey = _hubKey(creds.hubBaseUrl);
    final row = await _contributions.getContribution(
      hubKey,
      tileId,
      healpixOrder: _order,
    );
    final contributionId = row?.contributionId;
    if (contributionId == null || contributionId.isEmpty) {
      throw ConstellationException(
        'No recorded contribution for tile $tileId on this hub to retract.',
        kind: ConstellationErrorKind.notFound,
      );
    }
    final receipt = await retract(contributionId);
    if (receipt.retracted) {
      await _contributions.deleteContribution(
        hubKey,
        tileId,
        healpixOrder: _order,
      );
      _logger.info(
        'Cleared local contribution receipt for tile $tileId on $hubKey; the '
        'next contribute re-anchors from epoch.',
        source: _logSource,
      );
    }
    return receipt;
  }

  // --- Follow-the-night ---------------------------------------------------

  /// Ask the hub which joined targets are dark + available for this user now and
  /// turn them into deepen-the-thinnest-first suggestions, ranked by how shallow
  /// the swarm co-add still is. Targets the hub has no handoff state for are
  /// skipped silently.
  ///
  /// The returned list pairs the local target row (id/name/coords from
  /// [localTargetsResolver], which the provider wires to `TargetsDao`) with the
  /// hub's live baton state. As of 5.0 the only consumer is the Constellation
  /// screen's follow-the-night card; it is not yet surfaced in the planner /
  /// scheduler tabs, so it does not feed automated scheduling.
  Future<List<FollowTheNightSuggestion>> followTheNight() async {
    final client = await _client();
    if (client == null) return const [];
    try {
      final locals = await _localTargetsResolver();
      final byId = {for (final t in locals) t.targetId: t};
      final suggestions = <FollowTheNightSuggestion>[];

      // Consider both joined targets and any local target that maps to a hub
      // target id, so a freshly-imported plan still gets handoff signals.
      final candidateIds = <int>{..._joined.keys, ...byId.keys};
      for (final id in candidateIds) {
        final HandoffClaim? handoff;
        try {
          handoff = await client.queryHandoff(id);
        } on ConstellationException catch (e) {
          // A per-target handoff failure (e.g. not-found beyond the 404 the
          // client already maps to null) must not sink the whole sweep.
          _logger.debug(
            'followTheNight: handoff query for #$id failed: ${e.message}',
            source: _logSource,
          );
          continue;
        }
        if (handoff == null) continue;

        final local = byId[id];
        final shared = _joined[id];
        final raDeg = local?.raDeg ?? shared?.raDeg ?? 0.0;
        final decDeg = local?.decDeg ?? shared?.decDeg ?? 0.0;
        suggestions.add(
          FollowTheNightSuggestion(
            targetId: id,
            targetName: local?.name ?? shared?.name ?? 'Target #$id',
            raDeg: raDeg,
            decDeg: decDeg,
            handoff: handoff,
            swarmIntegrationSeconds: shared?.integrationSeconds ?? 0.0,
          ),
        );
      }

      // Ready-now first, then the shallowest swarm depth (deepen the thinnest).
      suggestions.sort((a, b) {
        if (a.isReadyNow != b.isReadyNow) return a.isReadyNow ? -1 : 1;
        return a.swarmIntegrationSeconds.compareTo(b.swarmIntegrationSeconds);
      });
      return suggestions;
    } finally {
      client.close();
    }
  }

  /// Claim the follow-the-night baton for a target (take active-imager duty).
  Future<HandoffClaim?> claimHandoff(int targetId) async {
    final client = await _requireClient();
    try {
      return await client.claimHandoff(targetId);
    } finally {
      client.close();
    }
  }

  /// Release the follow-the-night baton for a target.
  Future<void> releaseHandoff(int targetId) async {
    final client = await _requireClient();
    try {
      await client.releaseHandoff(targetId);
    } finally {
      client.close();
    }
  }

  // --- Internals ----------------------------------------------------------

  /// Normalize a hub base URL to a stable receipt key (`scheme://host[:port]`),
  /// so http-vs-https, a trailing slash, or a path suffix do not orphan a hub's
  /// receipts and re-ship a whole tile.
  static String _hubKey(Uri hubBaseUrl) {
    final port = hubBaseUrl.hasPort ? ':${hubBaseUrl.port}' : '';
    return '${hubBaseUrl.scheme}://${hubBaseUrl.host}$port';
  }

  /// Resolve a target's sky centre from the joined hub row, falling back to the
  /// local target table when the hub did not advertise coordinates.
  Future<({double raDeg, double decDeg})> _targetCenter(
    int targetId,
    SharedTarget? joined,
  ) async {
    if (joined != null && (joined.raDeg != 0.0 || joined.decDeg != 0.0)) {
      return (raDeg: joined.raDeg, decDeg: joined.decDeg);
    }
    final locals = await _localTargetsResolver();
    for (final t in locals) {
      if (t.targetId == targetId) {
        return (raDeg: t.raDeg, decDeg: t.decDeg);
      }
    }
    throw ConstellationException(
      'Cannot resolve sky coordinates for target #$targetId — '
      'join it or add it to the local catalog first.',
      kind: ConstellationErrorKind.notFound,
    );
  }

  /// Local atlas tiles whose centre falls within [radiusDeg] of the cone centre.
  Future<List<AtlasTileCoverage>> _localTilesInCone({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
  }) async {
    final coverage = await _atlas.coverage();
    return coverage
        .where(
          (t) =>
              _angularSeparationDeg(
                centerRaDeg,
                centerDecDeg,
                t.centerRaDeg,
                t.centerDecDeg,
              ) <=
              radiusDeg,
        )
        .toList(growable: false);
  }

  Future<List<int>> _localTileIdsInCone({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
  }) async {
    final tiles = await _localTilesInCone(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      radiusDeg: radiusDeg,
    );
    return tiles.map((t) => t.tileId).toList(growable: false);
  }

  Future<String> _swarmDir() async {
    final root = await _atlas.atlasRoot();
    return '$root/swarm/$_order';
  }

  /// Great-circle separation (deg) via the haversine formula — robust at small
  /// angles where the spherical law of cosines loses precision.
  static double _angularSeparationDeg(
    double ra1Deg,
    double dec1Deg,
    double ra2Deg,
    double dec2Deg,
  ) {
    const deg2rad = math.pi / 180.0;
    final dRa = (ra2Deg - ra1Deg) * deg2rad;
    final dDec = (dec2Deg - dec1Deg) * deg2rad;
    final lat1 = dec1Deg * deg2rad;
    final lat2 = dec2Deg * deg2rad;
    final a =
        math.sin(dDec / 2) * math.sin(dDec / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dRa / 2) * math.sin(dRa / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return c / deg2rad;
  }
}
