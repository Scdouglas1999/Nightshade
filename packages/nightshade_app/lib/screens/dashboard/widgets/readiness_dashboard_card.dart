import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/readiness/readiness_panel.dart';
import '../../../widgets/readiness/readiness_status_chip.dart';

/// Dashboard surfacing of the "ready to image" report.
///
/// An elevated [NightshadeCard] that pairs the compact [ReadinessStatusChip]
/// with an inline preview of the single most-important outstanding item (the
/// first blocked item if any, otherwise the first caution item) and a
/// **View all** affordance that opens the full [ReadinessPanel] dialog.
///
/// When everything is ready the card collapses to nothing
/// ([SizedBox.shrink]) so a fully-configured rig is not nagged — the chip is
/// still available elsewhere for an at-a-glance check.
///
/// Mounted on the dashboard via `ReadinessDashboardOverlay`, which owns the
/// floating placement in the dashboard `Stack` (alongside
/// `SmartNightPromptCard`). This widget owns content; the overlay owns layout.
class ReadinessDashboardCard extends ConsumerWidget {
  const ReadinessDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final report = ref.watch(readinessReportProvider);

    // Nothing to act on — stay out of the way.
    if (report.overall == ReadinessLevel.ready) {
      return const SizedBox.shrink();
    }

    final ReadinessItem? topItem = report.blockedItems.isNotEmpty
        ? report.blockedItems.first
        : (report.cautionItems.isNotEmpty ? report.cautionItems.first : null);

    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ReadinessStatusChip(),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              NightshadeButton(
                label: 'View all',
                icon: LucideIcons.listChecks,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: () => showReadinessDialog(context),
              ),
            ],
          ),
          if (topItem != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            _TopItem(item: topItem, colors: colors),
          ],
        ],
      ),
    );
  }
}

class _TopItem extends StatelessWidget {
  final ReadinessItem item;
  final NightshadeColors colors;

  const _TopItem({required this.item, required this.colors});

  @override
  Widget build(BuildContext context) {
    final levelColor = readinessLevelColor(item.level, colors);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs + 1),
          child: StatusDot(
            color: levelColor,
            variant: item.level == ReadinessLevel.blocked
                ? StatusDotVariant.urgent
                : StatusDotVariant.static,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                style: NightshadeTypography.bodyMedium
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Text(
                item.detail,
                style: NightshadeTypography.caption
                    .copyWith(color: colors.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
