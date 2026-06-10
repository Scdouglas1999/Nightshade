import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Banner shown when image SNR has improved significantly since the last
/// annotation pass, suggesting the user re-annotate to find more objects.
class ReAnnotateSuggestionBanner extends ConsumerWidget {
  final NightshadeColors colors;

  const ReAnnotateSuggestionBanner({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = ref.watch(reAnnotateSuggestionProvider);

    if (!suggestion.shouldShow) {
      return const SizedBox.shrink();
    }

    final foreground = identical(colors, NightshadeColors.redNight)
        ? colors.textPrimary
        : colors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: NightshadeDecorations.statusChip(
        colors.success,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            NightshadeIcons.sparkle,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Image quality improved ${suggestion.improvementPercent.toStringAsFixed(0)}% - '
              're-annotate to find more objects?',
              style: NightshadeTypography.labelSm
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              ref.read(reAnnotateSuggestionProvider.notifier).state =
                  const ReAnnotateSuggestion.none();
              ref.read(annotationServiceProvider).reAnnotate();
            },
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: NightshadeDecorations.tintedBadge(
                colors.success,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Text(
                'Re-annotate',
                style: NightshadeTypography.labelStrongSm
                    .copyWith(color: foreground),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              ref.read(reAnnotateSuggestionProvider.notifier).state =
                  const ReAnnotateSuggestion.none();
            },
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                NightshadeIcons.close,
                size: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
