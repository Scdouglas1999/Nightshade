import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../your_sky/sky_atlas_format.dart';
import '../constellation_format.dart';

/// A follow-the-night nudge: "M31 is dark for you now and the swarm needs more
/// depth." Ready-now suggestions get the accent treatment and a Claim button;
/// the rest read as muted context (below horizon / already held).
class FollowTheNightCard extends StatelessWidget {
  final FollowTheNightSuggestion suggestion;

  /// Claim the baton for this target (take active-imager duty). Disabled while
  /// [claiming] is true; null when the baton is not available to this user.
  final VoidCallback? onClaim;
  final bool claiming;

  const FollowTheNightCard({
    super.key,
    required this.suggestion,
    required this.onClaim,
    this.claiming = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final ready = suggestion.isReadyNow;
    final accent = ready ? colors.accent : colors.textMuted;

    return NightshadeCard(
      variant: ready ? CardVariant.standard : CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(accent),
                child: Icon(
                  ready ? LucideIcons.moonStar : LucideIcons.moon,
                  size: NightshadeTokens.iconSm,
                  color: accent,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.targetName,
                      style: NightshadeTypography.labelStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCenter(suggestion.raDeg, suggestion.decDeg),
                      style: NightshadeTypography.captionSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (ready)
                const StatusPill(
                  icon: LucideIcons.sparkles,
                  label: 'NOW',
                  value: 'dark',
                  status: StatusPillStatus.active,
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Text(
            formatFollowHint(
              targetName: suggestion.targetName,
              isReadyNow: ready,
              altitudeOk: suggestion.handoff.altitudeOk,
              swarmSeconds: suggestion.swarmIntegrationSeconds,
            ),
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (suggestion.swarmIntegrationSeconds > 0) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              '${formatIntegration(suggestion.swarmIntegrationSeconds)} fused so far',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
          if (onClaim != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Align(
              alignment: Alignment.centerRight,
              child: NightshadeButton(
                label: 'Take the baton',
                icon: LucideIcons.flag,
                size: ButtonSize.small,
                isLoading: claiming,
                onPressed: claiming ? null : onClaim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
