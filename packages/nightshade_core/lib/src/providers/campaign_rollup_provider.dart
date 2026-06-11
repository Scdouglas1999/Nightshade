import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign_rollup.dart';
import '../services/campaign_rollup_service.dart';
import '../services/imaging_records_repository.dart';
import '../services/scheduler/integration_goal_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

/// Service provider for [CampaignRollupService].
final campaignRollupServiceProvider = Provider<CampaignRollupService>((ref) {
  return CampaignRollupService(
    records: ref.watch(imagingRecordsRepositoryProvider),
    targetsDao: ref.watch(targetsDaoProvider),
    goalService: ref.watch(integrationGoalServiceProvider),
  );
});

/// Multi-night campaign rollup for one target.
///
/// Family-keyed by `targetId`. Auto-invalidates when the underlying database
/// providers change.
final campaignRollupProvider = FutureProvider.autoDispose
    .family<CampaignRollup, int>((ref, targetId) async {
      return ref.watch(campaignRollupServiceProvider).buildForTarget(targetId);
    });

/// Bulk campaign rollups for the entire target catalog.
///
/// Used by the Targets tab to render the "Total integration: 24h Lum,
/// 8h Ha across 6 sessions" column and by the History tab to derive a
/// per-target campaign badge for each run.
///
/// Returns rollups keyed by target id. Targets with no captures still
/// appear in the map (with empty filter / session lists) so the UI
/// can render "no captures yet" tiles.
final campaignRollupAllTargetsProvider =
    FutureProvider.autoDispose<Map<int, CampaignRollup>>((ref) async {
      return ref.watch(campaignRollupServiceProvider).buildForAllTargets();
    });

/// Resolve a campaign rollup by **target name** (case-insensitive).
///
/// The History tab keys its rows by sequence-run, not by Drift target id —
/// the per-run stats blob stores the target name as a free-string. We
/// look up the corresponding [CampaignRollup] via this provider so the
/// campaign badge can join across the two surfaces without re-querying
/// the database for every row.
///
/// Honors the [AppSettingsState.campaignRollupGroupingMode] setting:
///   * `by_target_name` (default) — match on `rollup.targetName` lowercased.
///     The catalog id is also accepted because that's what's commonly
///     embedded in display strings ("M31", "NGC 7000").
///   * `by_target_id` — strict match on `rollup.targetId.toString()`. The
///     UI calls this when it has the Drift id at hand.
///   * `by_user_tag` — name match plus a tag prefix; today we treat this
///     as a synonym for `by_target_name` because the targets table does
///     not yet have a tags column. The branch is kept so the setting has
///     a real switch point.
final campaignRollupByNameProvider = FutureProvider.autoDispose
    .family<CampaignRollup?, String>((ref, targetName) async {
      final lookup = targetName.trim().toLowerCase();
      if (lookup.isEmpty) return null;
      final mode =
          ref
              .watch(appSettingsProvider)
              .valueOrNull
              ?.campaignRollupGroupingMode ??
          'by_target_name';
      final all = await ref.watch(campaignRollupAllTargetsProvider.future);
      for (final rollup in all.values) {
        switch (mode) {
          case 'by_target_id':
            if (rollup.targetId.toString() == lookup) return rollup;
            break;
          case 'by_user_tag':
          case 'by_target_name':
          default:
            if (rollup.targetName.toLowerCase() == lookup) return rollup;
        }
      }
      return null;
    });
