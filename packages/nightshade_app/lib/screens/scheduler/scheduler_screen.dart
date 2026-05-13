import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../planner/widgets/scheduler_tab_content.dart';

/// Thin shell that hosts [SchedulerTabContent].
///
/// Scheduler merged into Plan Tonight as a tab in §UX consolidation
/// (W8-SCHED-MERGE). The `/scheduler` route now redirects to
/// `/planner?tab=scheduler`, so this screen is unreachable through the
/// router. It is kept so any direct embedding (tests, debug entry points)
/// keeps working until the redirect is removed.
class SchedulerScreen extends StatelessWidget {
  const SchedulerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      body: const SchedulerTabContent(),
    );
  }
}
