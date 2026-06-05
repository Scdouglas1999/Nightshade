import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'science_overlay_legend.dart';

class ScienceOverlayComposer extends ConsumerWidget {
  final NightshadeColors colors;

  const ScienceOverlayComposer({
    super.key,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayState = ref.watch(scienceOverlayStateProvider);
    final prefs = ref.watch(scienceVisualizationPrefsProvider).valueOrNull ??
        const ScienceVisualizationPrefs();

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Overlay Composer',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap ⓘ for what each layer means',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LayerChip(
                  legendKey: 'uniformity',
                  label: 'Uniformity',
                  active: overlayState.showUniformityMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showUniformityMap: !overlayState.showUniformityMap,
                    );
                  },
                ),
                _LayerChip(
                  legendKey: 'clip_high',
                  label: 'Clip High',
                  active: overlayState.showClipHighMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showClipHighMap: !overlayState.showClipHighMap,
                    );
                  },
                ),
                _LayerChip(
                  legendKey: 'clip_low',
                  label: 'Clip Low',
                  active: overlayState.showClipLowMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showClipLowMap: !overlayState.showClipLowMap,
                    );
                  },
                ),
                _LayerChip(
                  legendKey: 'residuals',
                  label: 'Residual',
                  active: overlayState.showResidualVectors,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showResidualVectors: !overlayState.showResidualVectors,
                    );
                  },
                ),
                _LayerChip(
                  legendKey: 'moving',
                  label: 'Moving Tracks',
                  active: overlayState.showMovingObjectTracks,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showMovingObjectTracks:
                          !overlayState.showMovingObjectTracks,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overlay Opacity ${(prefs.overlayOpacity * 100).round()}%',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              min: 0.05,
              max: 0.95,
              value: prefs.overlayOpacity.clamp(0.05, 0.95),
              onChanged: (value) {
                final next = prefs.copyWith(overlayOpacity: value);
                ref
                    .read(scienceVisualizationPrefsProvider.notifier)
                    .savePrefs(next);
              },
            ),
            // Show the inline gradient legend for whichever quantitative
            // overlay is currently active. This gives users immediate "color
            // = meaning" guidance the moment they enable an overlay, instead
            // of forcing them into the long-form info dialog.
            if (overlayState.showUniformityMap ||
                overlayState.showClipHighMap ||
                overlayState.showClipLowMap)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ScienceOverlayLegend.inlineFor(
                  context,
                  overlayState.showClipHighMap
                      ? 'clip_high'
                      : overlayState.showClipLowMap
                          ? 'clip_low'
                          : 'uniformity',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  final String label;
  final String legendKey;
  final bool active;
  final VoidCallback onTap;

  const _LayerChip({
    required this.label,
    required this.legendKey,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: () => ScienceOverlayLegend.show(context, legendKey),
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: active
            ? NightshadeDecorations.selectedSurface(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                color: colors.surfaceElevated,
                border: Border.all(color: colors.border),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => ScienceOverlayLegend.show(context, legendKey),
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  LucideIcons.info,
                  size: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
