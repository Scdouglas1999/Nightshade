import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign_rollup.dart';
import '../services/campaign_rollup_service.dart';
import '../services/scheduler/integration_goal_service.dart';
import 'database_provider.dart';

/// Service provider for [CampaignRollupService].
final campaignRollupServiceProvider =
    Provider<CampaignRollupService>((ref) {
  return CampaignRollupService(
    sessionsDao: ref.watch(sessionsDaoProvider),
    imagesDao: ref.watch(imagesDaoProvider),
    targetsDao: ref.watch(targetsDaoProvider),
    goalService: ref.watch(integrationGoalServiceProvider),
  );
});

/// Multi-night campaign rollup for one target.
///
/// Family-keyed by `targetId`. Auto-invalidates when the underlying database
/// providers change.
final campaignRollupProvider =
    FutureProvider.family<CampaignRollup, int>((ref, targetId) async {
  return ref.watch(campaignRollupServiceProvider).buildForTarget(targetId);
});
