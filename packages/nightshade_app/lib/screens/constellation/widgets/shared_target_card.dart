import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../your_sky/sky_atlas_format.dart';
import '../constellation_ui_providers.dart';
import 'contribution_bar.dart';

/// A browse-list card for one shared community target: its name and coordinates,
/// the fused swarm depth + contributor count, and — once your local atlas
/// overlaps it — your personal contribution bar. Tapping opens the detail.
class SharedTargetCard extends ConsumerWidget {
  final SharedTarget target;
  final VoidCallback onTap;

  const SharedTargetCard({
    super.key,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final yourSecondsAsync = ref.watch(
      yourContributionSecondsProvider(target),
    );
    final yourSeconds = yourSecondsAsync.valueOrNull ?? 0.0;

    return NightshadeCard(
      enableHover: true,
      onTap: onTap,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(colors.accent),
                child: Icon(
                  LucideIcons.users,
                  size: NightshadeTokens.iconSm,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.name.isEmpty
                          ? 'Target #${target.targetId}'
                          : target.name,
                      style: NightshadeTypography.labelStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCenter(target.raDeg, target.decDeg),
                      style: NightshadeTypography.captionSm.copyWith(
                        color: colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: NightshadeTokens.iconSm,
                color: colors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          ResponsiveStatStrip(
            minCellWidth: 110,
            stats: [
              ResponsiveStat(
                label: 'FUSED',
                value: formatIntegration(target.integrationSeconds),
                icon: LucideIcons.layers,
              ),
              ResponsiveStat(
                label: 'IMAGERS',
                value: '${target.contributors}',
                icon: LucideIcons.users,
              ),
            ],
          ),
          if (yourSeconds > 0) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            ContributionBar(
              yourSeconds: yourSeconds,
              swarmSeconds: target.integrationSeconds,
            ),
          ],
        ],
      ),
    );
  }
}
