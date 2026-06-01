import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../sequencer/widgets/run_dashboard/run_dashboard_format.dart';
import '../../sequencer/widgets/run_dashboard/run_dashboard_providers.dart';

/// Merged "Now Imaging" cockpit strip — the active target header + exposure
/// progress condensed into a single compact full-width row.
///
/// Replaces the standalone `RunDashboardTargetHeader` and
/// `RunDashboardExposureProgress` panels, which were both tall and both about
/// "current run status." This strip keeps every essential readout — target
/// name + coordinates, altitude (color-coded), time-to-meridian, time-to-set,
/// the per-frame countdown with a thin inline bar, and the sequence
/// progress — while dropping the niche per-target integration-budget panel
/// (still available via the opt-in full target-header tile).
///
/// Reads the same providers as the originals:
/// [runDashboardActiveTargetProvider], [runDashboardSkyStatsProvider],
/// [exposureProgressProvider], [sequenceProgressProvider], and
/// [sequenceExecutionStateProvider]. Per-frame / sequence progress only render
/// while execution is active.
class CockpitNowImaging extends ConsumerWidget {
  const CockpitNowImaging({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final target = ref.watch(runDashboardActiveTargetProvider);

    if (target == null) {
      return _Shell(
        colors: colors,
        child: Row(
          children: [
            Icon(LucideIcons.target, size: 15, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                'No active target — load a sequence to begin.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final sky = ref.watch(runDashboardSkyStatsProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final hasLocation = settingsAsync.valueOrNull != null &&
        (settingsAsync.valueOrNull!.latitude != 0.0 ||
            settingsAsync.valueOrNull!.longitude != 0.0);

    final altText = sky != null
        ? '${sky.altitudeDeg.toStringAsFixed(1)}°'
        : (hasLocation ? '—' : 'set location');
    final altColor = sky == null
        ? colors.textMuted
        : sky.altitudeDeg < 30
            ? colors.warning
            : colors.success;

    final setLabel = sky == null
        ? 'To set'
        : sky.horizonDeg <= 0.01
            ? 'To set'
            : 'To ${sky.horizonDeg.toStringAsFixed(0)}°';

    final identity = _Identity(colors: colors, target: target);

    final chips = <Widget>[
      _StatChip(
        colors: colors,
        icon: LucideIcons.mountain,
        label: 'Altitude',
        value: altText,
        valueColor: altColor,
      ),
      _StatChip(
        colors: colors,
        icon: LucideIcons.timer,
        label: 'To meridian',
        value: formatDuration(sky?.timeToTransit),
      ),
      _StatChip(
        colors: colors,
        icon: LucideIcons.sunset,
        label: setLabel,
        value: formatDuration(sky?.timeToSet),
      ),
      _FrameChip(colors: colors),
      _SequenceChip(colors: colors),
    ];

    return _Shell(
      colors: colors,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: NightshadeTokens.spaceLg,
        runSpacing: NightshadeTokens.spaceSm,
        children: [
          identity,
          ...chips,
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;

  const _Identity({required this.colors, required this.target});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            target.displayName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.compass, size: 11, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              '${formatRA(target.raHours)}  ${formatDec(target.decDegrees)}',
              style: NightshadeTypography.withTabular(
                NightshadeTypography.captionSm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact label-over-value stat (altitude / to-meridian / to-set).
class _StatChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: colors.textMuted,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// This-frame countdown (mm:ss) with a thin inline progress bar. Hidden when no
/// exposure is in flight.
class _FrameChip extends ConsumerWidget {
  final NightshadeColors colors;

  const _FrameChip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isActive = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused ||
        executionState == SequenceExecutionState.stopping;
    if (!isActive) return const SizedBox.shrink();

    final exposure = ref.watch(exposureProgressProvider);
    final hasFrame = exposure.frameNumber > 0 && exposure.remaining > 0;
    if (!hasFrame && !exposure.isDownloading) return const SizedBox.shrink();

    final exposurePct = exposure.percent.clamp(0.0, 100.0) / 100.0;
    final valueText = hasFrame
        ? formatSeconds(exposure.remaining)
        : 'Downloading…';
    final valueColor = hasFrame ? colors.primary : colors.warning;

    return SizedBox(
      width: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.timer, size: 10, color: colors.textMuted),
              const SizedBox(width: 4),
              Text(
                'This frame',
                style: TextStyle(
                  fontSize: 9.5,
                  color: colors.textMuted,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            valueText,
            style: NightshadeTypography.withTabular(
              TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(height: 3),
          NightshadeProgressBar(
            value: hasFrame ? exposurePct : 0,
            height: 3,
          ),
        ],
      ),
    );
  }
}

/// Sequence progress: X/Y · % · ~ETA. Hidden when execution is not active.
class _SequenceChip extends ConsumerWidget {
  final NightshadeColors colors;

  const _SequenceChip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isActive = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused ||
        executionState == SequenceExecutionState.stopping;
    if (!isActive) return const SizedBox.shrink();

    final seq = ref.watch(sequenceProgressProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.listOrdered, size: 10, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              'Sequence',
              style: TextStyle(
                fontSize: 9.5,
                color: colors.textMuted,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${seq.completedExposures}/${seq.totalExposures}',
              style: NightshadeTypography.withTabular(
                TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(seq.progressPercent * 100).toStringAsFixed(0)}%',
              style: NightshadeTypography.withTabular(
                TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
            if (seq.estimatedRemainingSecs != null) ...[
              const SizedBox(width: 6),
              Text(
                '~${formatSeconds(seq.estimatedRemainingSecs!)}',
                style: NightshadeTypography.withTabular(
                  TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Self-chromed container matching the cockpit card styling, sized to a single
/// compact row.
class _Shell extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _Shell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: child,
    );
  }
}
