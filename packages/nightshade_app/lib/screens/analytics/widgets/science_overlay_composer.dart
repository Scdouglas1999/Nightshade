import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
            Text(
              'Overlay Composer',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LayerChip(
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
                      fontSize: 12,
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
          ],
        ),
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LayerChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: active
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
