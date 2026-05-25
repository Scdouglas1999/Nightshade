import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

typedef SmartNightProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Launches an accepted Smart Night plan.
///
/// Keep this outside the dialog so the launch contract is testable: the
/// generated sequence is loaded into the editor, the executor is started, and
/// the draft is marked started only after the executor accepts the run.
class SmartNightPlanLauncher {
  const SmartNightPlanLauncher();

  Future<void> launch({
    required SmartNightProviderRead read,
    required SmartNightPlan plan,
    String? draftId,
  }) async {
    read(currentSequenceProvider.notifier).loadSequence(
      plan.sequence,
      discardUnsaved: true,
    );

    await read(sequenceExecutorProvider).start();

    if (draftId != null) {
      await SmartNightDraftService(
        settingsDao: read(settingsDaoProvider),
      ).markStarted(draftId);
    }
  }
}
