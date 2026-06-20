import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../constellation_format.dart';

/// A slim two-tone bar showing your share of a shared target's fused depth:
/// your contribution filled in the accent, the rest of the swarm in a muted
/// track, with a `2.1h of 12h (18%)` caption beneath.
///
/// Pure presentation — the seconds are resolved by the caller's provider.
class ContributionBar extends StatelessWidget {
  final double yourSeconds;
  final double swarmSeconds;

  const ContributionBar({
    super.key,
    required this.yourSeconds,
    required this.swarmSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final fraction = yourContributionFraction(
      yourSeconds: yourSeconds,
      swarmSeconds: swarmSeconds,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Your contribution',
              style: NightshadeTypography.labelSm.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              formatYourContribution(
                yourSeconds: yourSeconds,
                swarmSeconds: swarmSeconds,
              ),
              style: NightshadeTypography.labelSm.copyWith(
                color: yourSeconds > 0 ? colors.accent : colors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        ClipRRect(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: colors.surfaceAlt),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction == 0 ? 0.0 : fraction.clamp(0.04, 1.0),
                  child: Container(color: colors.accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
