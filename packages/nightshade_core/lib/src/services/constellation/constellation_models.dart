// Pillar C ("Constellation") — Dart value types for the hub wire contract.
//
// These decode the JSON the Constellation hub (`docs/nightshade_5_0_contracts.md`
// §5) returns and carry the typed error surface the client raises. Field names
// mirror the wire contract (camelCase) so the maps round-trip straight through.

/// How a [ConstellationException] should be classified by callers (retry vs
/// surface vs reauth). Mirrors the WebDAV sync target's error taxonomy.
enum ConstellationErrorKind {
  network,
  auth,
  notFound,
  conflict,
  geometryMismatch,
  server,
  protocol,
  unknown,
}

/// Raised on any hub interaction that fails or returns an unusable payload.
class ConstellationException implements Exception {
  final String message;
  final ConstellationErrorKind kind;
  final int? statusCode;

  const ConstellationException(
    this.message, {
    this.kind = ConstellationErrorKind.unknown,
    this.statusCode,
  });

  @override
  String toString() => 'ConstellationException($kind): $message';
}

/// `GET /v1/info` result — hub identity and tiling parameters.
class HubInfo {
  final String name;
  final String fingerprint; // SHA-256 hex server identity
  final String version;
  final int healpixOrder;
  final int tilePixels;
  final bool selfHosted;

  /// Whether this hub accepts raw FITS subframes in addition to additive sums.
  /// Drives whether the contribute sheet may offer the SUBS privacy option at
  /// all — when false the option is disabled with an explanatory note, because
  /// the hub has no endpoint to receive raw frames. Defaults false (older hubs
  /// that don't advertise the flag are treated as sums-only).
  final bool acceptsRawSubs;

  const HubInfo({
    required this.name,
    required this.fingerprint,
    required this.version,
    required this.healpixOrder,
    required this.tilePixels,
    required this.selfHosted,
    this.acceptsRawSubs = false,
  });

  factory HubInfo.fromJson(Map<String, dynamic> json) => HubInfo(
    name: json['name'] as String? ?? '',
    fingerprint: json['fingerprint'] as String? ?? '',
    version: json['version'] as String? ?? '',
    healpixOrder: (json['healpixOrder'] as num?)?.toInt() ?? 0,
    tilePixels: (json['tilePixels'] as num?)?.toInt() ?? 0,
    selfHosted: json['selfHosted'] as bool? ?? true,
    acceptsRawSubs: json['acceptsRawSubs'] as bool? ?? false,
  );
}

/// `POST /v1/accounts` result — the issued account id + bearer token.
class HubAccount {
  final String accountId;
  final String bearerToken;
  final double trust;

  const HubAccount({
    required this.accountId,
    required this.bearerToken,
    required this.trust,
  });

  factory HubAccount.fromJson(Map<String, dynamic> json) => HubAccount(
    accountId: json['accountId'] as String? ?? '',
    bearerToken: json['bearerToken'] as String? ?? '',
    trust: (json['trust'] as num?)?.toDouble() ?? 0.0,
  );
}

/// `POST /v1/tiles/{id}/contributions` result — the hub's acceptance receipt.
class ContributionReceipt {
  final String contributionId;
  final bool accepted;
  final double trustApplied;
  final int totalFramesAfter;
  final double integrationSecondsAfter;

  const ContributionReceipt({
    required this.contributionId,
    required this.accepted,
    required this.trustApplied,
    required this.totalFramesAfter,
    required this.integrationSecondsAfter,
  });

  factory ContributionReceipt.fromJson(Map<String, dynamic> json) =>
      ContributionReceipt(
        contributionId: json['contributionId'] as String? ?? '',
        accepted: json['accepted'] as bool? ?? false,
        trustApplied: (json['trustApplied'] as num?)?.toDouble() ?? 0.0,
        totalFramesAfter: (json['totalFramesAfter'] as num?)?.toInt() ?? 0,
        integrationSecondsAfter:
            (json['integrationSecondsAfter'] as num?)?.toDouble() ?? 0.0,
      );
}

/// `POST /v1/tiles/{id}/subframes` result — the hub's raw-subframe receipt.
///
/// Unlike a sums [ContributionReceipt], a raw subframe is stored as its own
/// immutable file (not fused), so the receipt carries only the opaque
/// [contributionId] (the handle a later delete acts on) and the stored size.
class SubframeReceipt {
  final String contributionId;
  final bool accepted;
  final int storedBytes;

  const SubframeReceipt({
    required this.contributionId,
    required this.accepted,
    required this.storedBytes,
  });

  factory SubframeReceipt.fromJson(Map<String, dynamic> json) =>
      SubframeReceipt(
        contributionId: json['contributionId'] as String? ?? '',
        accepted: json['accepted'] as bool? ?? false,
        storedBytes: (json['storedBytes'] as num?)?.toInt() ?? 0,
      );
}

/// `DELETE /v1/contributions/{id}` result — the post-retraction tile depth.
class RetractionReceipt {
  final bool retracted;
  final int totalFramesAfter;

  const RetractionReceipt({
    required this.retracted,
    required this.totalFramesAfter,
  });

  factory RetractionReceipt.fromJson(Map<String, dynamic> json) =>
      RetractionReceipt(
        retracted: json['retracted'] as bool? ?? false,
        totalFramesAfter: (json['totalFramesAfter'] as num?)?.toInt() ?? 0,
      );
}

/// `GET|POST /v1/handoff/{targetId}` result — the follow-the-night baton state.
class HandoffClaim {
  final int targetId;

  /// The tile currently being deepened for this target (the hub's active id).
  final int? activeTileId;

  /// Account id currently holding the baton, or null when free.
  final String? holder;

  /// Whether the target is high enough for *this* user to image now.
  final bool altitudeOk;

  /// Opaque claim token returned by `/claim` (null on a plain query).
  final String? claimToken;

  /// Expiry of a granted claim (ISO-8601), when the hub supplies one.
  final DateTime? expiresAt;

  const HandoffClaim({
    required this.targetId,
    required this.activeTileId,
    required this.holder,
    required this.altitudeOk,
    required this.claimToken,
    required this.expiresAt,
  });

  /// True when no one holds the baton and the target is up for this user — the
  /// "go image this now" signal the planner surfaces.
  bool get isAvailableNow => holder == null && altitudeOk;

  factory HandoffClaim.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expiresAt'] as String?;
    return HandoffClaim(
      targetId: (json['targetId'] as num?)?.toInt() ?? 0,
      activeTileId: (json['activeTileId'] as num?)?.toInt(),
      holder: json['holder'] as String?,
      altitudeOk: json['altitudeOk'] as bool? ?? false,
      claimToken: json['claimToken'] as String?,
      expiresAt: (expiresRaw == null || expiresRaw.isEmpty)
          ? null
          : DateTime.tryParse(expiresRaw),
    );
  }
}

/// A shared target advertised by the hub (browse / "what's dark now").
///
/// The hub's swarm-target listing is not pinned field-for-field in the contract
/// (§5 leaves the browse payload to the hub), so this decodes the stable subset
/// every hub returns and tolerates the rest.
class SharedTarget {
  final int targetId;
  final String name;
  final double raDeg;
  final double decDeg;

  /// Total fused integration depth across the swarm for this target (seconds).
  final double integrationSeconds;

  /// Number of distinct contributors currently feeding the target.
  final int contributors;

  /// The hub's primary tile id for the target's centre, when advertised.
  final int? activeTileId;

  const SharedTarget({
    required this.targetId,
    required this.name,
    required this.raDeg,
    required this.decDeg,
    required this.integrationSeconds,
    required this.contributors,
    required this.activeTileId,
  });

  factory SharedTarget.fromJson(Map<String, dynamic> json) => SharedTarget(
    targetId: (json['targetId'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    raDeg: (json['raDeg'] as num?)?.toDouble() ?? 0.0,
    decDeg: (json['decDeg'] as num?)?.toDouble() ?? 0.0,
    integrationSeconds: (json['integrationSeconds'] as num?)?.toDouble() ?? 0.0,
    contributors: (json['contributors'] as num?)?.toInt() ?? 0,
    activeTileId: (json['activeTileId'] as num?)?.toInt(),
  );
}

/// A community tile pulled down and cached locally for blending into "Your Sky".
///
/// The pulled blob lives on disk under the atlas `swarm/` directory; this is the
/// cheap index row the blend overlay renders from.
class SwarmTile {
  final int tileId;
  final int order;
  final String localPath;
  final bool finalized;
  final int totalFrames;
  final double integrationSeconds;
  final int contributors;
  final DateTime pulledAt;

  const SwarmTile({
    required this.tileId,
    required this.order,
    required this.localPath,
    required this.finalized,
    required this.totalFrames,
    required this.integrationSeconds,
    required this.contributors,
    required this.pulledAt,
  });
}

/// A local imageable target offered as a candidate to seed a shared target on
/// the hub ("Share one of my targets"). Coordinates are in degrees.
class ShareableLocalTarget {
  final int targetId;
  final String name;
  final double raDeg;
  final double decDeg;

  const ShareableLocalTarget({
    required this.targetId,
    required this.name,
    required this.raDeg,
    required this.decDeg,
  });
}

/// One tile this device has contributed to a hub — the retractable unit.
///
/// Sourced from the persisted `constellation_contributions` receipt table (the
/// Wave-0 substrate): every row carrying a remote [contributionId] is a
/// contribution the hub can subtract back off the fused co-add exactly. This is
/// what the "Your contributions" list renders and the Retract action acts on.
class ContributionRecord {
  /// HEALPix NESTED tile id contributed.
  final int tileId;

  /// Remote receipt id the hub issued — the handle Retract subtracts.
  final String contributionId;

  /// Cumulative own-light frames shipped to the hub for this tile.
  final int contributedFrames;

  /// Cumulative own-light integration (seconds) shipped for this tile.
  final double contributedIntegrationSeconds;

  /// When this tile was last contributed (null if the receipt predates the
  /// timestamp column).
  final DateTime? lastContributedAt;

  const ContributionRecord({
    required this.tileId,
    required this.contributionId,
    required this.contributedFrames,
    required this.contributedIntegrationSeconds,
    required this.lastContributedAt,
  });
}

/// One shared target the planner should surface tonight, pairing the local
/// target row with the hub's live handoff state.
class FollowTheNightSuggestion {
  final int targetId;
  final String targetName;
  final double raDeg;
  final double decDeg;
  final HandoffClaim handoff;

  /// Community integration depth so far (seconds), for ranking dark targets.
  final double swarmIntegrationSeconds;

  const FollowTheNightSuggestion({
    required this.targetId,
    required this.targetName,
    required this.raDeg,
    required this.decDeg,
    required this.handoff,
    required this.swarmIntegrationSeconds,
  });

  /// True when the baton is free and the target is up for this user now.
  bool get isReadyNow => handoff.isAvailableNow;
}
