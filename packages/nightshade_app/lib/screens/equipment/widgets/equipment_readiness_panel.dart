import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/readiness/readiness_panel.dart';

/// Full-width "ready to image" panel for the Equipment screen.
///
/// Replaces the vague setup guidance with the concrete, actionable readiness
/// checklist: a [SectionHeader] summarizing the overall state, wrapped in a
/// [SectionWell] containing the itemized [ReadinessPanel]. Each not-ready row
/// carries a **Fix** action that deep-links to the relevant screen.
///
/// The panel's own header banner is suppressed ([ReadinessPanel.showHeader]
/// is false) because this widget supplies an equivalent summary through the
/// [SectionHeader], keeping the equipment screen visually consistent with its
/// other sections.
///
/// Mounted in `screens/equipment/equipment_screen.dart` above the device
/// dashboard, so the readiness checklist leads the Equipment screen.
class EquipmentReadinessPanel extends ConsumerWidget {
  const EquipmentReadinessPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(readinessReportProvider);
    final outstanding = report.blockedItems.length + report.cautionItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'Ready to image',
          subtitle: _subtitle(report, outstanding),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        const SectionWell(
          // Outstanding-only keeps the inline checklist compact: it lists the
          // items that still need action (with their Fix deep-links) and shows
          // a single "ready" confirmation when nothing remains, rather than
          // repeating every already-green check. maxItems caps the inline rows
          // so the panel cannot overflow the (non-scrolling) equipment column
          // on a short phone screen; any surplus collapses into a "View all"
          // button that opens the full itemized dialog.
          child: ReadinessPanel(
            showHeader: false,
            outstandingOnly: true,
            maxItems: 3,
            // Equipment-screen inline panel: let the user ✕ a row (plate
            // solver, dark library, …) for the session so an item they've
            // consciously deferred stops nagging until next launch.
            dismissible: true,
          ),
        ),
      ],
    );
  }

  String _subtitle(ReadinessReport report, int outstanding) {
    switch (report.overall) {
      case ReadinessLevel.ready:
        return 'Everything required for first light is in place.';
      case ReadinessLevel.caution:
        return '$outstanding ${outstanding == 1 ? 'item' : 'items'} to '
            'review before imaging.';
      case ReadinessLevel.blocked:
        final blocked = report.blockedItems.length;
        return '$blocked ${blocked == 1 ? 'item is' : 'items are'} blocking '
            'first light.';
    }
  }
}
