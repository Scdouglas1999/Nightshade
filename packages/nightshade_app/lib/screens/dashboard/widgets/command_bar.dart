import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
// nightshade_core also exports a (scheduler) TwilightTimes; the night-context
// chip uses the planetarium one returned by twilightTimesProvider, so hide the
// core symbol to keep the name unambiguous in this file.
import 'package:nightshade_core/nightshade_core.dart' hide TwilightTimes;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../localization/nightshade_localizations.dart';
import 'connection_quality_chip.dart';
import 'dashboard_header_actions.dart';
import 'glance_mode_toggle.dart';

/// Command Bar: Fixed header with session status, quick stats, clock, and controls.
///
/// This is the central nervous system status display showing:
/// - Session status indicator (Idle/Capturing with target name)
/// - Quick stats strip: Temp | Focus | HFR | RMS
/// - Clock/LST widget
/// - Edit mode toggle and controls
class DashboardCommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;

  const DashboardCommandBar({
    super.key,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent =
        ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading =
        ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing =
        sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Single compact threshold drives every hide/shrink decision below.
        // Splitting it into per-element widths produced inconsistent layouts
        // where dividers vanished before the items they were dividing.
        final isCompact = width < _commandBarCompactWidth;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 16,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusLg,
            border: Border.all(color: colors.border),
            boxShadow: NightshadeTokens.elevationLevel1,
          ),
          child: Row(
            children: [
              // Session Status - always show but constrain width
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isCompact ? 120 : 180),
                  child: _SessionStatusIndicator(
                    colors: colors,
                    pulseController: pulseController,
                    isCapturing: isCapturing,
                    targetName: targetName,
                  ),
                ),
              ),

              if (!isCompact) ...[
                const SizedBox(width: 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _QuickStatsStrip(colors: colors),
                ),
                // Night-context chip (darkness countdown + moon). Self-hides
                // — including its own leading divider — when there's no
                // location/twilight data to show.
                _NightContextChip(colors: colors),
                const SizedBox(width: 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
                const SizedBox(width: 16),
                DashboardClockWidget(colors: colors),
                const SizedBox(width: 16),
                // Remote-vs-local + latency chip. Reads the graded
                // connectionQualityProvider; quiet "Local" pill in FFI mode,
                // live link state + latency in a network session.
                ConnectionQualityChip(colors: colors),
                const SizedBox(width: 12),
                // Glance-mode toggle (large secondary-status type for
                // across-the-room reading).
                GlanceModeToggle(colors: colors),
                const SizedBox(width: 12),
              ] else
                const Spacer(),

              // Edit Controls
              DashboardHeaderActions(
                isEditing: isEditing,
                onToggleEdit: onToggleEdit,
                onManageWidgets: onManageWidgets,
                onResetLayout: onResetLayout,
                compact: isCompact,
              ),
            ],
          ),
        );
      },
    );
  }
}

// Compact-mode cutoff: below this width the bar drops stats, clock, and
// dividers together rather than peeling them off one by one across multiple
// thresholds. 900 keeps room for full content on a 1024 px laptop after a
// reasonable side rail.
const double _commandBarCompactWidth = 900.0;

/// Which darkness phase the night-context chip should describe, paired with the
/// l10n key used to format its label.
enum NightContextKind {
  /// Before astronomical dusk — counting down to full darkness.
  beforeDark,

  /// Between astronomical dusk and dawn — counting down remaining darkness.
  duringDark,

  /// After dawn / daytime — show the upcoming sunset clock time instead.
  afterDark,
}

/// Resolved night-context fact: the l10n key + the already-formatted `{time}`
/// substitution. Returns null when there isn't enough twilight data to say
/// anything (e.g. no observing location set), so the chip can self-hide.
class NightContextFact {
  final NightContextKind kind;
  final String l10nKey;
  final String time;

  const NightContextFact({
    required this.kind,
    required this.l10nKey,
    required this.time,
  });
}

/// Format a positive [Duration] as a compact "1h 23m" / "12m" countdown.
String _formatCountdown(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// Format a [DateTime] as a zero-padded local HH:MM clock string.
String _formatClock(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Pure resolver for the night-context chip. Given the day's twilight times and
/// the current (possibly simulated) time, decide the single most relevant
/// darkness fact:
///   * before astronomical dusk  → "Dark in {countdown}"
///   * during astronomical night → "Dark {countdown} left" (until astro dawn)
///   * after dawn / daytime       → "Sunset {HH:MM}"
///
/// Returns null when the necessary twilight field is missing (no location), so
/// the caller renders nothing.
NightContextFact? resolveNightContext(TwilightTimes twilight, DateTime now) {
  final dusk = twilight.astronomicalDusk;
  final dawn = twilight.astronomicalDawn;

  // Before dusk: count down to darkness.
  if (dusk != null && dusk.isAfter(now)) {
    return NightContextFact(
      kind: NightContextKind.beforeDark,
      l10nKey: 'darkIn',
      time: _formatCountdown(dusk.difference(now)),
    );
  }

  // During darkness (past dusk, before dawn): count down remaining dark time.
  if (dusk != null && !dusk.isAfter(now) && dawn != null && dawn.isAfter(now)) {
    return NightContextFact(
      kind: NightContextKind.duringDark,
      l10nKey: 'darkLeft',
      time: _formatCountdown(dawn.difference(now)),
    );
  }

  // After dawn / daytime: show the next sunset clock time.
  final sunset = twilight.sunset;
  if (sunset != null) {
    return NightContextFact(
      kind: NightContextKind.afterDark,
      l10nKey: 'sunsetAt',
      time: _formatClock(sunset),
    );
  }

  return null;
}

/// RMS guiding-quality grade used to color the command-bar RMS stat.
enum RmsGrade { good, fair, poor }

/// Grade a total guiding RMS (arcseconds): < 1.0" good, 1.0–2.0" fair,
/// > 2.0" poor. Only meaningful while actually guiding — callers pass null
/// otherwise and get null back (no color grade applied).
RmsGrade? gradeRms(double? rmsArcsec) {
  if (rmsArcsec == null) return null;
  if (rmsArcsec < 1.0) return RmsGrade.good;
  if (rmsArcsec <= 2.0) return RmsGrade.fair;
  return RmsGrade.poor;
}

/// Resolve the session-status label/color from the live sequence-engine state,
/// falling back to manual Capturing/Idle when the sequencer is idle.
class _SessionStatusView {
  final String label;
  final Color color;

  const _SessionStatusView({required this.label, required this.color});
}

_SessionStatusView _resolveSessionStatus({
  required SequenceExecutionState seqState,
  required bool isCapturing,
  required NightshadeColors colors,
  required NightshadeLocalizations l10n,
}) {
  switch (seqState) {
    case SequenceExecutionState.running:
      return _SessionStatusView(
        label: l10n.text('sequenceRunning'),
        color: colors.success,
      );
    case SequenceExecutionState.paused:
      return _SessionStatusView(
        label: l10n.text('sequencePaused'),
        color: colors.warning,
      );
    case SequenceExecutionState.stopping:
      return _SessionStatusView(
        label: l10n.text('sequenceStopping'),
        color: colors.warning,
      );
    case SequenceExecutionState.recovering:
      // Recovering is an active, attention-worthy state — surface it like a
      // running/recovering sequence rather than collapsing to manual capture.
      return _SessionStatusView(
        label: l10n.text('sequenceRunning'),
        color: colors.warning,
      );
    case SequenceExecutionState.idle:
    case SequenceExecutionState.completed:
    case SequenceExecutionState.failed:
      // Sequencer not driving a run — fall back to the manual capture state.
      return _SessionStatusView(
        label: isCapturing ? l10n.text('capturing') : l10n.text('idle'),
        color: isCapturing ? colors.success : colors.textSecondary,
      );
  }
}

/// Session status indicator showing capture state and current target.
class _SessionStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isCapturing;
  final String targetName;

  const _SessionStatusIndicator({
    required this.colors,
    required this.pulseController,
    required this.isCapturing,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final seqState = ref.watch(sequenceExecutionStateProvider);
    final status = _resolveSessionStatus(
      seqState: seqState,
      isCapturing: isCapturing,
      colors: colors,
      l10n: l10n,
    );
    // The dot glows (vs. a dim idle pulse) whenever there's something live:
    // an active sequence or a manual capture.
    final isLive = status.color != colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLive
                    ? status.color
                        .withValues(alpha: 0.4 + pulseController.value * 0.4)
                    : colors.textMuted
                        .withValues(alpha: 0.4 + pulseController.value * 0.3),
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status.label,
                style: NightshadeTypography.labelStrong.copyWith(
                  color: status.color,
                ),
              ),
              Text(
                targetName,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick stats strip showing Temp | Focus | HFR | RMS in the command bar.
class _QuickStatsStrip extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsStrip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Camera temperature
    final cameraConnected =
        ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final cameraTemp =
        ref.watch(cameraStateProvider.select((s) => s.temperature));

    // Focuser position
    final focuserConnected =
        ref.watch(focuserStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final focuserPosition =
        ref.watch(focuserStateProvider.select((s) => s.position));

    // HFR from last image
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));

    // Guiding RMS
    final guiderConnected =
        ref.watch(guiderStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final guiderIsGuiding =
        ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    // Format values
    final tempValue = cameraConnected && cameraTemp != null
        ? '${cameraTemp.toStringAsFixed(1)}°C'
        : '---';
    final focusValue = focuserConnected && focuserPosition != null
        ? focuserPosition.toString()
        : '---';
    final hfrValue = hfr != null ? hfr.toStringAsFixed(2) : '---';
    final isGuiding = guiderConnected && guiderIsGuiding && guiderRms != null;
    final rmsValue = isGuiding ? '${guiderRms.toStringAsFixed(2)}"' : '---';

    // RMS gets a quality color grade — but only while actually guiding (a
    // live number to grade). When idle it falls through to the dimmed "---".
    final rmsGrade = isGuiding ? gradeRms(guiderRms) : null;
    final Color? rmsColor = switch (rmsGrade) {
      RmsGrade.good => colors.success,
      RmsGrade.fair => colors.warning,
      RmsGrade.poor => colors.error,
      null => null,
    };

    // Use FittedBox to scale down gracefully on narrower layouts
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CommandBarStat(
            icon: LucideIcons.thermometer,
            label: l10n.text('temp'),
            value: tempValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.focus,
            label: l10n.text('focus'),
            value: focusValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.target,
            label: l10n.text('hfr'),
            value: hfrValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.activity,
            label: l10n.text('rms'),
            value: rmsValue,
            colors: colors,
            valueColor: rmsColor,
          ),
        ],
      ),
    );
  }
}

class _CommandBarStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  /// Optional explicit color override for the value text (e.g. RMS quality
  /// grade). Ignored for placeholder "---" values, which always dim.
  final Color? valueColor;

  const _CommandBarStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    // Dim placeholder ("---") stats so live numbers pop: the value falls back
    // to textMuted (matching the always-muted icon) when there's no reading,
    // instead of full-strength textPrimary.
    final hasValue = value != '---';
    final valueTextColor =
        hasValue ? (valueColor ?? colors.textPrimary) : colors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                fontWeight: FontWeight.w600,
                color: valueTextColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize9,
                  color: colors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Night-context chip for the wide command bar: the most relevant darkness
/// fact (countdown to dark / dark remaining / next sunset) plus a compact moon
/// illumination readout. Owns its own leading divider so it disappears wholly
/// — divider included — when there's no location/twilight data.
class _NightContextChip extends ConsumerWidget {
  final NightshadeColors colors;

  const _NightContextChip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final twilight = ref.watch(twilightTimesProvider);
    final now = ref.watch(observationTimeProvider.select((s) => s.time));

    final fact = resolveNightContext(twilight, now);
    // With no location set the twilight fields are null and resolveNightContext
    // returns null — render nothing at all (the chip self-hides).
    if (fact == null) return const SizedBox.shrink();

    final moonInfo = ref.watch(moonInfoProvider);
    final moonValue = '${moonInfo.illumination.toStringAsFixed(0)}%';

    // duringDark uses moonStar so the darkness fact stays visually distinct
    // from the plain-moon illumination readout right beside it.
    final darknessIcon = switch (fact.kind) {
      NightContextKind.beforeDark => LucideIcons.sunset,
      NightContextKind.duringDark => LucideIcons.moonStar,
      NightContextKind.afterDark => LucideIcons.sunset,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 24),
        Container(width: 1, height: 32, color: colors.border),
        const SizedBox(width: 24),
        Icon(darknessIcon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Text(
          l10n.text(fact.l10nKey, params: {'time': fact.time}),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        Icon(LucideIcons.moon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Text(
          moonValue,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Compact command bar for narrow screens (<768px).
///
/// Mobile-optimized header showing:
/// - Row 1: Session status + Edit button
/// - Row 2 (optional): Compact quick stats (Temp | HFR | RMS) when capturing
class CompactDashboardCommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;

  const CompactDashboardCommandBar({
    super.key,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent =
        ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading =
        ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing =
        sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    // Quick stats for mobile (only when capturing or has data)
    final cameraConnected =
        ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final cameraTemp =
        ref.watch(cameraStateProvider.select((s) => s.temperature));
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));
    final guiderIsGuiding =
        ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    final l10n = context.l10n;
    final showStats = isCapturing || cameraConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Status + Edit
          Row(
            children: [
              // Status dot
              AnimatedBuilder(
                animation: pulseController,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCapturing
                          ? colors.success.withValues(
                              alpha: 0.4 + pulseController.value * 0.4)
                          : colors.textMuted.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Status and target name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isCapturing ? l10n.text('capturing') : l10n.text('idle'),
                      style: NightshadeTypography.labelSm.copyWith(
                        color:
                            isCapturing ? colors.success : colors.textSecondary,
                      ),
                    ),
                    if (isCapturing)
                      Text(
                        targetName,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Compact connection chip (icon + latency only).
              ConnectionQualityChip(colors: colors, compact: true),
              const SizedBox(width: 8),
              // Glance-mode toggle.
              GlanceModeToggle(colors: colors, compact: true),
              const SizedBox(width: 8),
              // Edit button
              NightshadeButton(
                label: isEditing ? 'Done' : 'Edit',
                icon:
                    isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
                variant:
                    isEditing ? ButtonVariant.primary : ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: onToggleEdit,
              ),
            ],
          ),

          // Row 2: Compact quick stats (shown when capturing or has data)
          if (showStats) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
              // Use FittedBox to scale down stats on very narrow screens
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _MobileStatChip(
                      label: l10n.text('temp'),
                      value: cameraConnected && cameraTemp != null
                          ? '${cameraTemp.toStringAsFixed(0)}°'
                          : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: l10n.text('hfr'),
                      value: hfr != null ? hfr.toStringAsFixed(2) : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: l10n.text('rms'),
                      value: guiderIsGuiding && guiderRms != null
                          ? '${guiderRms.toStringAsFixed(1)}"'
                          : '---',
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact stat display for mobile command bar.
class _MobileStatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MobileStatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
