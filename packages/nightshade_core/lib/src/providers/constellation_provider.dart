import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/constellation_contributions_dao.dart';
import '../database/daos/settings_dao.dart';
import '../services/constellation/constellation_models.dart';
import '../services/constellation/constellation_service.dart';
import '../services/logging_service.dart';
import 'database_provider.dart';
import 'sky_atlas_provider.dart';

/// Riverpod surface for Pillar C ("Constellation") — the community hub client.
///
/// [constellationServiceProvider] assembles the orchestration service from the
/// sky-atlas service (Pillar A, the source of the additive tile deltas), the
/// settings-backed hub credentials, and the targets table (for the
/// follow-the-night target mapping). The read providers expose the hub's
/// shared-target listing ([swarmTilesProvider]) and the per-target handoff feed
/// ([followTheNightProvider]) the Constellation screen's follow-the-night card
/// renders (it is not yet wired into the planner/scheduler tabs).

/// Settings keys the hub credentials persist under (LAN-only, self-hosted).
const String constellationHubUrlSettingKey = 'constellation.hub_url';
const String constellationHubTokenSettingKey = 'constellation.hub_token';

/// Resolve the configured hub credentials from settings, or null when the user
/// has not signed in to any hub yet.
Future<ConstellationCredentials?> resolveConstellationCredentials(
  SettingsDao settings,
) async {
  final url = await settings.getSetting(constellationHubUrlSettingKey);
  final token = await settings.getSetting(constellationHubTokenSettingKey);
  if (url == null || url.isEmpty || token == null || token.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.hasScheme) return null;
  return ConstellationCredentials(hubBaseUrl: parsed, bearerToken: token);
}

/// The Constellation orchestration service.
final constellationServiceProvider = Provider<ConstellationService>((ref) {
  final settings = ref.watch(settingsDaoProvider);
  return ConstellationService(
    atlas: ref.watch(skyAtlasServiceProvider),
    logger: ref.watch(loggingServiceProvider),
    contributionsDao: ref.watch(constellationContributionsDaoProvider),
    credentialsResolver: () => resolveConstellationCredentials(settings),
    localTargetsResolver: () async {
      // Resolve through the remote-aware targets provider so a slave maps the
      // MASTER's targets (its own local table is never populated); on the host
      // this yields the same db.Target rows the local DAO would.
      final targets = await ref.read(allDbTargetsProvider.future);
      return targets
          .map(
            (t) => (
              targetId: t.id,
              name: t.name,
              // Target rows store RA in decimal hours; the hub/atlas work in
              // degrees, so convert here at the boundary.
              raDeg: t.ra * 15.0,
              decDeg: t.dec,
            ),
          )
          .toList(growable: false);
    },
  );
});

/// Whether a hub is configured (drives the "sign in" vs "connected" UI).
final constellationConfiguredProvider = FutureProvider<bool>((ref) async {
  final settings = ref.watch(settingsDaoProvider);
  final creds = await resolveConstellationCredentials(settings);
  return creds != null;
});

/// The swarm's shared-target listing on the configured hub.
final sharedTargetsProvider = FutureProvider<List<SharedTarget>>((ref) {
  return ref.watch(constellationServiceProvider).browseSharedTargets();
});

/// Community tiles pulled and blended into "Your Sky" for one target.
///
/// Pulling is a side-effecting fetch (it writes the cached blobs to disk), so
/// this provider performs the pull and returns the resulting [SwarmTile] index.
///
/// We pull with `finalized: false` — the additive `.nst` accumulator — because
/// that is the only form [ConstellationService.pullTarget] actually folds into
/// the local atlas (via `mergeSwarmDelta`) so the swarm's depth shows up in Your
/// Sky. A `finalized: true` FITS pull is a display-only blob with no consumer,
/// so it would leave the advertised "blended into Your Sky" payoff a no-op.
final swarmTilesProvider = FutureProvider.family<List<SwarmTile>, int>((
  ref,
  targetId,
) {
  return ref
      .watch(constellationServiceProvider)
      .pullTarget(targetId, finalized: false);
});

/// Follow-the-night suggestions: which shared targets are dark and available for
/// this user right now, ranked deepen-the-thinnest-first. Consumed by the
/// Constellation screen's follow-the-night card (not the planner/scheduler tabs).
/// Keyed by target id so a single-target card can watch just one; pass a
/// negative id (e.g. -1) to request the full sweep.
final followTheNightProvider =
    FutureProvider.family<List<FollowTheNightSuggestion>, int>((
      ref,
      targetId,
    ) async {
      final all = await ref
          .watch(constellationServiceProvider)
          .followTheNight();
      if (targetId < 0) return all;
      return all.where((s) => s.targetId == targetId).toList(growable: false);
    });
