import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
    final background = colors.success.withValues(alpha: 0.12);
    final border = colors.success.withValues(alpha: 0.45);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.sparkles,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Image quality improved ${suggestion.improvementPercent.toStringAsFixed(0)}% - '
              're-annotate to find more objects?',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              ref.read(reAnnotateSuggestionProvider.notifier).state =
                  const ReAnnotateSuggestion.none();
              ref.read(annotationServiceProvider).reAnnotate();
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Re-annotate',
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              ref.read(reAnnotateSuggestionProvider.notifier).state =
                  const ReAnnotateSuggestion.none();
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.x,
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
