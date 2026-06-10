import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Non-intrusive status banner that surfaces the live meridian-flip countdown
/// in the imaging-tab banner stack.
///
/// The flip is **always** performed automatically — by the Rust `meridian_flip`
/// trigger (an always-on watchdog) or, during a running sequence, by the
/// in-sequence flip node. This banner is therefore *status only*: it never
/// offers a manual-action button (that would contradict "automatic watchdog")
/// and it auto-hides whenever a flip is not armed, so it stays quiet on every
/// idle night.
///
/// Visual language mirrors [MeridianFlipProgressDialog] (rotate/flip iconography,
/// `colors.warning` as the flip-imminent accent) and renders exclusively through
/// the design system — no hardcoded colors, no ad-hoc styles.
///
/// State comes from [meridianCountdownProvider] (a read-only projection); this
/// widget never mutates flip state.
///
/// The 15-second wall-clock tick lives HERE, not in the provider: a
/// [Timer.periodic] created in [initState] and cancelled in [dispose] invalidates
/// the (timer-free) provider each tick so the remaining-time readout counts down.
/// Owning the timer in the widget means it is cancelled synchronously when the
/// tree is torn down, so it never leaks past disposal (an autoDispose periodic
/// stream did, tripping the widget-test pending-timer assertion).
/// Session-scoped record of the severity at which the operator dismissed the
/// meridian-flip banner. The banner stays hidden while the live severity is at
/// or below this level, and re-appears the moment the flip escalates to a more
/// urgent tone (info → warning → imminent) — so dismissing the calm "flip in
/// 5h" status can never suppress the attention-grade "imminent" one. Holds the
/// dismissed [NightshadeAlertSeverity.index]; `null` means "not dismissed". It
/// resets to `null` whenever the flip disarms so a fresh arm cycle shows again,
/// and is deliberately NOT persisted (a new night starts clean).
final meridianBannerDismissedSeverityProvider =
    StateProvider<int?>((ref) => null);

class MeridianFlipCountdownBanner extends ConsumerStatefulWidget {
  const MeridianFlipCountdownBanner({super.key});

  /// HA-based countdown switches from the calm `info` tone to an attention
  /// `warning` tone once the flip is this close — late enough to stay quiet for
  /// most of the night, early enough that the operator notices before the mount
  /// starts moving.
  static const Duration kWarningThreshold = Duration(minutes: 10);

  @override
  ConsumerState<MeridianFlipCountdownBanner> createState() =>
      _MeridianFlipCountdownBannerState();
}

class _MeridianFlipCountdownBannerState
    extends ConsumerState<MeridianFlipCountdownBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Recompute the projection on a fixed cadence so the numeric countdown ticks
    // down even when no upstream input changes. Cancelled synchronously in
    // [dispose] (see the class doc) — no leaked timer.
    _ticker = Timer.periodic(kMeridianCountdownTick, (_) {
      if (mounted) {
        ref.invalidate(meridianCountdownProvider);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reset the operator's dismissal whenever the flip disarms, so a fresh arm
    // cycle (a new night, or the next flip after this one completes) surfaces
    // the banner again instead of staying silenced forever.
    ref.listen<MeridianCountdownState>(meridianCountdownProvider, (prev, next) {
      if (!next.isArmed &&
          ref.read(meridianBannerDismissedSeverityProvider) != null) {
        ref.read(meridianBannerDismissedSeverityProvider.notifier).state = null;
      }
    });

    // The projection is synchronous and always present; when nothing is armed it
    // resolves to a not-armed state and [_MeridianFlipCountdownView] renders
    // nothing. The banner is ambient status, never a blocker.
    final state = ref.watch(meridianCountdownProvider);
    final dismissedSeverityIndex =
        ref.watch(meridianBannerDismissedSeverityProvider);
    return _MeridianFlipCountdownView(
      state: state,
      dismissedSeverityIndex: dismissedSeverityIndex,
      onDismiss: (severityIndex) => ref
          .read(meridianBannerDismissedSeverityProvider.notifier)
          .state = severityIndex,
    );
  }
}

/// Stateless render of a resolved [MeridianCountdownState]. Split out so the
/// presentation logic is unit-testable in isolation and the [ConsumerWidget]
/// stays a thin provider adapter.
class _MeridianFlipCountdownView extends StatelessWidget {
  const _MeridianFlipCountdownView({
    required this.state,
    required this.dismissedSeverityIndex,
    required this.onDismiss,
  });

  final MeridianCountdownState state;

  /// The [NightshadeAlertSeverity.index] the operator last dismissed at, or
  /// `null` if not dismissed. The banner hides while the live severity is at or
  /// below this; an escalation above it re-surfaces the banner.
  final int? dismissedSeverityIndex;

  /// Invoked with the current severity index when the operator dismisses.
  final void Function(int severityIndex) onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final spec = _resolveSpec(state);

    // Not armed and nothing worth surfacing -> render nothing. This is the
    // common idle case (mount disconnected, flip disabled, parked, etc.); the
    // banner must not editorialize about a disabled feature.
    if (spec == null) {
      return const SizedBox.shrink();
    }

    // Dismissed at this severity or a more urgent one: stay hidden until the
    // flip escalates beyond what was dismissed (so silencing the calm "in 5h"
    // status never swallows the attention-grade "imminent" banner).
    if (dismissedSeverityIndex != null &&
        spec.severity.index <= dismissedSeverityIndex!) {
      return const SizedBox.shrink();
    }

    final accent = switch (spec.severity) {
      NightshadeAlertSeverity.info => colors.info,
      NightshadeAlertSeverity.success => colors.success,
      NightshadeAlertSeverity.warning => colors.warning,
      NightshadeAlertSeverity.error => colors.error,
    };

    // Decoration recipe is identical to NightshadeAlert (severity tint @ 0.06
    // over surfaceAlt, border @ 0.35, radiusMd) so the banner is visually
    // indistinguishable from the design-system alert — we only compose a richer
    // body so the live countdown can use tabular telemetry figures. The two
    // alpha constants below are the exact values NightshadeAlert._getColors
    // uses; mirroring them keeps the banner on the same surface as every other
    // alert in the app.
    const alertTintAlpha = 0.06;
    const alertBorderAlpha = 0.35;
    final background = Color.alphaBlend(
      accent.withValues(alpha: alertTintAlpha),
      colors.surfaceAlt,
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(
          color: accent.withValues(alpha: alertBorderAlpha),
        ),
      ),
      padding: NightshadeTokens.paddingLg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(spec.icon, size: NightshadeTokens.iconMd, color: accent),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                spec.title,
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  spec.subtitle,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (spec.showPierChip && state.sideOfPier != null) ...[
            const SizedBox(width: NightshadeTokens.spaceMd),
            _PierSideChip(sideOfPier: state.sideOfPier!),
          ],
          const SizedBox(width: NightshadeTokens.spaceSm),
          // Dismiss the ambient status. This is NOT a manual flip action (the
          // flip stays fully automatic) — it only silences the banner, and an
          // escalation re-surfaces it.
          _DismissButton(
            color: colors.textMuted,
            onTap: () => onDismiss(spec.severity.index),
          ),
        ],
      ),
    );
  }
}

/// Compact close affordance for the ambient meridian-flip banner. A bordered
/// `InkResponse` rather than a full-padding [IconButton] so it reads as a quiet
/// "dismiss this status" control, not a primary action.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Dismiss',
      child: InkResponse(
        onTap: onTap,
        radius: NightshadeTokens.iconMd,
        containedInkWell: true,
        child: Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceXs),
          child: Icon(NightshadeIcons.close,
              size: NightshadeTokens.iconSm, color: color),
        ),
      ),
    );
  }
}

/// Resolved presentation for a given countdown state, or `null` to render
/// nothing. Pure function so the render rules are exhaustively testable.
_BannerSpec? _resolveSpec(MeridianCountdownState state) {
  // === Not armed ===
  // Keep it quiet by default: a disabled/disconnected flip is not worth a
  // banner on the imaging tab. The honest explanation already lives in the
  // sequence editor's watchdog badge and the meridian-flip settings.
  if (!state.isArmed) {
    return null;
  }

  // === Armed, tracking-limit method (no numeric countdown) ===
  // minutesBeforeLimit / onTrackingLimitHit decisions live entirely in the Rust
  // trigger evaluator. We must not fabricate a countdown; surface an honest
  // "monitored by the sequencer" info banner instead.
  if (state.timeToFlip == null) {
    return const _BannerSpec(
      severity: NightshadeAlertSeverity.info,
      icon: LucideIcons.flipHorizontal2,
      title: _BannerTitle(text: 'Meridian flip armed'),
      subtitle: 'Monitored by the sequencer — no action needed.',
      showPierChip: true,
    );
  }

  // === Armed, flip imminent (countdown at or past zero) ===
  final remaining = state.timeToFlip!;
  if (remaining <= Duration.zero) {
    return _BannerSpec(
      severity: NightshadeAlertSeverity.warning,
      icon: LucideIcons.flipHorizontal2,
      title: const _BannerTitle(text: 'Meridian flip imminent'),
      subtitle: state.isSequencerOwned
          ? 'Handled automatically by the running sequence.'
          : 'Automatic — the meridian-flip watchdog is running it now. '
              'No action needed.',
      showPierChip: true,
    );
  }

  // === Armed, live numeric countdown ===
  final isWarning = remaining < MeridianFlipCountdownBanner.kWarningThreshold;
  return _BannerSpec(
    severity: isWarning
        ? NightshadeAlertSeverity.warning
        : NightshadeAlertSeverity.info,
    icon: LucideIcons.flipHorizontal2,
    title: _BannerTitle(
      text: 'Meridian flip in ',
      // Tabular telemetry figures so the ticking countdown never shifts layout.
      trailing: formatTimeToFlip(remaining),
    ),
    subtitle: state.isSequencerOwned
        ? 'Handled automatically by the running sequence.'
        : 'Automatic — the meridian-flip watchdog will run this for you. No action needed.',
    showPierChip: true,
  );
}

/// Formats a countdown duration as a compact `H​h M​m` / `M​m` label.
///
/// Rounds *up* to whole minutes so the readout never claims less time than is
/// actually left — showing "2m" when 2m05s remain would be a small lie the
/// operator could act on. Because of the round-up, any strictly-positive
/// duration reads at least "1m"; a value at or below zero is handled by the
/// caller's "imminent" branch and reads "now".
///
/// Public + pure so the formatting is unit-tested directly.
String formatTimeToFlip(Duration remaining) {
  if (remaining <= Duration.zero) {
    return 'now';
  }
  // Round up to the next whole minute.
  final totalMinutes = (remaining.inSeconds + 59) ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '${minutes}m';
  }
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

/// Banner title: a leading label plus an optional tabular-figure value. The
/// value uses [NightshadeTypography.telemetryMd] (tabular) so the live countdown
/// ticks in place without nudging the rest of the row.
class _BannerTitle extends StatelessWidget {
  const _BannerTitle({required this.text, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final labelStyle =
        NightshadeTypography.label.copyWith(color: colors.textPrimary);

    if (trailing == null) {
      return Text(text, style: labelStyle);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(text, style: labelStyle)),
        Text(
          trailing!,
          style: NightshadeTypography.telemetryMd.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Small trailing chip showing the mount-reported side of pier, hinting at flip
/// direction. Matches the `_InfoChip` styling from [MeridianFlipProgressDialog].
class _PierSideChip extends StatelessWidget {
  const _PierSideChip({required this.sideOfPier});

  final String sideOfPier;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(NightshadeIcons.move,
              size: NightshadeTokens.iconXs, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            'Pier ${_pierLabel(sideOfPier)}',
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Normalizes the driver-reported side-of-pier string to a clean, capitalized
  /// label. Unknown / unexpected values pass through verbatim rather than being
  /// silently dropped — the operator should see exactly what the mount reports.
  String _pierLabel(String raw) {
    final v = raw.trim();
    switch (v.toLowerCase()) {
      case 'east':
      case 'pierside_east':
        return 'East';
      case 'west':
      case 'pierside_west':
        return 'West';
      default:
        return v.isEmpty ? 'Unknown' : v;
    }
  }
}

/// Internal presentation descriptor produced by [_resolveSpec].
class _BannerSpec {
  const _BannerSpec({
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.showPierChip,
  });

  final NightshadeAlertSeverity severity;
  final IconData icon;
  final _BannerTitle title;
  final String subtitle;
  final bool showPierChip;
}
