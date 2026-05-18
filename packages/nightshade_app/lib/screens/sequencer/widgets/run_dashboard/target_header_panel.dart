import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard_format.dart';
import 'run_dashboard_providers.dart';

/// Wide header at the top of the Run dashboard showing the active target
/// name, coordinates, current altitude, time-to-set, time-to-meridian, and
/// per-target execution progress.
///
/// Read-only by construction. Renders an informative null-state when no
/// target is bound (the dashboard's empty state replaces the whole tab
/// for the idle case; this panel handles the "running but no target node"
/// edge case).
///
/// The progress bar reads from [targetExecutionProgressProvider] — the
/// same provider that drives the in-tree `TargetHeaderCard` on the Builder
/// tab — so "12/24 frames on M31" appears identically in both places.
class RunDashboardTargetHeader extends ConsumerWidget {
  const RunDashboardTargetHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final target = ref.watch(runDashboardActiveTargetProvider);
    final sky = ref.watch(runDashboardSkyStatsProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final hasLocation = settingsAsync.valueOrNull != null &&
        (settingsAsync.valueOrNull!.latitude != 0.0 ||
            settingsAsync.valueOrNull!.longitude != 0.0);

    if (target == null) {
      return _HeaderShell(
        colors: colors,
        child: Row(
          children: [
            Icon(LucideIcons.target, size: 18, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Text(
              'No target configured',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final isMobile = Responsive.isMobile(context);

    final altText = sky != null
        ? '${sky.altitudeDeg.toStringAsFixed(1)}°'
        : (hasLocation ? '—' : 'set location');
    final altColor = sky == null
        ? colors.textMuted
        : sky.altitudeDeg < 20
            ? colors.warning
            : sky.altitudeDeg < 30
                ? colors.warning
                : colors.success;

    final meridianText = formatDuration(sky?.timeToTransit);
    final setText = formatDuration(sky?.timeToSet);
    // Label the "to set" stat with the actual horizon used so 20° and 0°
    // configurations are not visually confusing.
    final setLabel = sky == null
        ? 'To set'
        : sky.horizonDeg <= 0.01
            ? 'To set'
            : 'To ${sky.horizonDeg.toStringAsFixed(0)}°';

    final stats = <Widget>[
      _HeaderStat(
        colors: colors,
        icon: LucideIcons.mountain,
        label: 'Altitude',
        value: altText,
        valueColor: altColor,
      ),
      _HeaderStat(
        colors: colors,
        icon: LucideIcons.timer,
        label: 'To meridian',
        value: meridianText,
      ),
      _HeaderStat(
        colors: colors,
        icon: LucideIcons.sunset,
        label: setLabel,
        value: setText,
      ),
    ];

    final name = Text(
      target.displayName,
      style: TextStyle(
        fontSize: isMobile ? 18 : 22,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      overflow: TextOverflow.ellipsis,
    );

    final coords = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.compass, size: 12, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          '${formatRA(target.raHours)}   ${formatDec(target.decDegrees)}',
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        name,
        const SizedBox(height: 4),
        coords,
      ],
    );

    final progress = _TargetProgress(
      colors: colors,
      targetNodeId: target.id,
    );

    if (isMobile) {
      return _HeaderShell(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            identity,
            const SizedBox(height: NightshadeTokens.spaceMd),
            Wrap(
              spacing: NightshadeTokens.spaceLg,
              runSpacing: NightshadeTokens.spaceSm,
              children: stats,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            progress,
          ],
        ),
      );
    }

    return _HeaderShell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: identity),
              for (final s in stats) ...[
                const SizedBox(width: NightshadeTokens.space2xl),
                s,
              ],
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          progress,
        ],
      ),
    );
  }
}

/// Per-target frame-count + progress bar. Mirrors the visual treatment
/// rendered by [TargetHeaderCard] on the Builder tab — same provider,
/// same numbers, same colour ramp.
class _TargetProgress extends ConsumerWidget {
  final NightshadeColors colors;
  final String targetNodeId;

  const _TargetProgress({
    required this.colors,
    required this.targetNodeId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isActive = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused ||
        executionState == SequenceExecutionState.stopping;
    if (!isActive) return const SizedBox.shrink();

    final stats = ref.watch(targetExecutionProgressProvider(targetNodeId));
    if (!stats.hasPlannedFrames) return const SizedBox.shrink();

    final completedMins = (stats.completedIntegrationSecs / 60).round();
    final totalMins = (stats.totalIntegrationSecs / 60).round();
    final progressState = executionState == SequenceExecutionState.paused
        ? NightshadeProgressState.paused
        : NightshadeProgressState.normal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text(
                '${stats.completedFrames}/${stats.totalFrames} frames',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '•',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${completedMins}m / ${totalMins}m',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${(stats.fraction * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        NightshadeProgressBar(
          value: stats.fraction,
          style: NightshadeProgressStyle.thin,
          state: progressState,
        ),
      ],
    );
  }
}

class _HeaderShell extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _HeaderShell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.space2xl,
        vertical: NightshadeTokens.spaceLg,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: child,
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _HeaderStat({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: valueColor ?? colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
