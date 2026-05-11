import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sequencer_screen.dart';
import '../../../utils/snackbar_helper.dart';

/// Sequencer > Library tab.
///
/// Browses the five bundled READ-ONLY sample sequences and lets the user
/// clone any of them into the current builder with one tap. Per audit §8.3.5
/// these provide beginners something to load and run immediately instead of
/// staring at an empty sequence canvas.
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final samplesAsync = ref.watch(sampleSequencesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(colors: colors),
          const SizedBox(height: 24),
          Expanded(
            child: samplesAsync.when(
              data: (samples) => _SampleGrid(samples: samples, colors: colors),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _LibraryError(
                colors: colors,
                error: error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _LibraryHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.library, size: 22, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sample Sequence Library',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bundled, read-only templates you can load and run as-is. '
                'Tap "Use this template" to copy a sample into your current sequence.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SampleGrid extends ConsumerWidget {
  final List<SampleSequence> samples;
  final NightshadeColors colors;

  const _SampleGrid({required this.samples, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (samples.isEmpty) {
      return Center(
        child: Text(
          'No sample sequences are bundled with this build.',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _columnsForWidth(constraints.maxWidth);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: samples.length,
          itemBuilder: (context, index) => _SampleCard(
            sample: samples[index],
            colors: colors,
          ),
        );
      },
    );
  }

  static int _columnsForWidth(double width) {
    if (width < 640) return 1;
    if (width < 1100) return 2;
    return 3;
  }
}

class _SampleCard extends ConsumerWidget {
  final SampleSequence sample;
  final NightshadeColors colors;

  const _SampleCard({required this.sample, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _skillColor(colors, sample.skillLevel)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconFor(sample.iconName),
                    color: _skillColor(colors, sample.skillLevel),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sample.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _SkillBadge(
                            colors: colors,
                            skillLevel: sample.skillLevel,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.clock,
                                  size: 11,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    sample.expectedTotalTime,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  sample.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    onPressed: () => _useTemplate(context, ref),
                    label: 'Use this template',
                    icon: LucideIcons.copy,
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _useTemplate(BuildContext context, WidgetRef ref) {
    final service = ref.read(sampleSequenceServiceProvider);
    final notifier = ref.read(currentSequenceProvider.notifier);

    final cloned = service.cloneForUse(sample);
    notifier.loadSequence(cloned);

    // Switch to Builder tab so the user sees the loaded sequence.
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showSuccessSnackBar(
      'Loaded "${sample.displayName}" into the builder',
    );
  }

  static Color _skillColor(
    NightshadeColors colors,
    SampleSequenceSkillLevel level,
  ) {
    switch (level) {
      case SampleSequenceSkillLevel.beginner:
        return colors.success;
      case SampleSequenceSkillLevel.intermediate:
        return colors.primary;
      case SampleSequenceSkillLevel.advanced:
        return colors.warning;
    }
  }

  static IconData _iconFor(String name) {
    switch (name) {
      case 'camera':
        return LucideIcons.camera;
      case 'moon':
        return LucideIcons.moon;
      case 'aperture':
        return LucideIcons.aperture;
      case 'circle':
        return LucideIcons.circle;
      case 'layers':
        return LucideIcons.layers;
      default:
        return LucideIcons.fileText;
    }
  }
}

class _SkillBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SampleSequenceSkillLevel skillLevel;

  const _SkillBadge({required this.colors, required this.skillLevel});

  @override
  Widget build(BuildContext context) {
    final color = _SampleCard._skillColor(colors, skillLevel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        skillLevel.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _LibraryError extends StatelessWidget {
  final NightshadeColors colors;
  final Object error;

  const _LibraryError({required this.colors, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertTriangle, size: 32, color: colors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load sample sequences',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
