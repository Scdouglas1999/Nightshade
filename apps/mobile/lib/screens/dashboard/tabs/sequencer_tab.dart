import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart'
    show RunDashboardWeatherSafetyCard;
import 'package:nightshade_app/screens/sequencer/mobile_sequence_editor.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/error_snackbar.dart';

/// Sequencer tab — phone-native run controller AND authoring surface.
///
///   * Top: [MobileSequenceEditor] — touch-friendly node list with
///     long-press-to-reorder, swipe-to-delete, tap-to-edit, and a FAB
///     for adding nodes. Replaces the legacy read-only `_NodeList` view
///     (audit phone sequencer authoring parity).
///   * Mid: [SequencerRecoveryActionsBanner] — exposed only while the
///     executor is in `recovering`; surfaces the three operator actions
///     (Try Now / Skip Node / Abort) the desktop dashboard provides
///     (audit recovery actions on mobile).
///   * Bottom 1/3: sticky strip with current target, ETA, and start/stop.
///
/// All work flows through the existing `sequenceExecutorProvider`,
/// `currentSequenceProvider`, and `recoveryControlProvider` so behaviour
/// stays identical to the desktop sequencer.
class SequencerTab extends ConsumerWidget {
  const SequencerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final execState = ref.watch(sequenceExecutionStateProvider);

    return Column(
      children: [
        // Sticky header — current sequence name + load button.
        _Header(sequence: sequence),
        // [weather/safety surface] Collapsed-by-default
        // expansion tile so the operator can glance at the current
        // weather-safety state without losing editor real-estate. The
        // tile collapses to a single ~48dp row; expanded it shows the
        // full RunDashboardWeatherSafetyCard which reads the existing
        // `weatherSafetyProvider` and never re-evaluates conditions on
        // its own. [end]
        const _WeatherSafetyExpansion(),
        Expanded(
          child: sequence == null
              ? const _NoSequenceState()
              : const MobileSequenceEditor(),
        ),
        // Mid: recovery action surface (only renders when recovering).
        const SequencerRecoveryActionsBanner(),
        // Bottom strip — "current target + ETA" + start/stop controls.
        // Keeping it sticky means the user can run/halt from any scroll
        // position, which matches the desktop sequence-controls bar.
        _StickyFooter(
          sequence: sequence,
          progress: progress,
          execState: execState,
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  final Sequence? sequence;
  const _Header({required this.sequence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sequence?.name ?? 'No sequence loaded',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (sequence != null)
                  Text(
                    '${sequence!.totalExposures} frames • '
                    '${_formatHms(sequence!.totalIntegrationSecs)}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          NightshadeButton(
            label: 'Load',
            icon: LucideIcons.folderOpen,
            size: ButtonSize.medium,
            variant: ButtonVariant.outline,
            onPressed: () => _showLoadPicker(context, ref),
          ),
        ],
      ),
    );
  }
}

Future<void> _showLoadPicker(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(sequenceRepositoryProvider);
  List<Sequence> all;
  try {
    all = await repo.loadAllSequences();
  } catch (e) {
    if (context.mounted) {
      // [error parsing] — prefer the typed envelope so the
      // operator sees the server-supplied reason (e.g. "Could not
      // load sequences: pairing_required") instead of an opaque
      // "Exception: 401 status code".
      showApiErrorWithPrefix(context, 'Could not load sequences', e);
    }
    return;
  }
  // Sort by modifiedAt desc so "Recent" reads as a natural prefix.
  all.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final dialogSize = AdaptiveDialogConstraints.dialogSize(
        dialogCtx,
        designWidth: 360,
        designHeight: 480,
      );
      return NightshadeDialog(
        title: 'Load sequence',
        icon: LucideIcons.folderOpen,
        width: dialogSize.width,
        height: dialogSize.height,
        child: all.isEmpty
            ? const EmptyState(
                icon: LucideIcons.fileX,
                title: 'No saved sequences',
                body: 'Create one on the desktop and it will appear here.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: all.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Theme.of(dialogCtx).dividerColor),
                itemBuilder: (_, i) {
                  final s = all[i];
                  return ListTile(
                    minVerticalPadding: 12,
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.totalExposures} frames • '
                      '${_formatHms(s.totalIntegrationSecs)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .loadSequence(s);
                      Navigator.of(dialogCtx).pop();
                    },
                  );
                },
              ),
      );
    },
  );
}

class _NoSequenceState extends StatelessWidget {
  const _NoSequenceState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: LucideIcons.play,
      title: 'No sequence loaded',
      body: 'Tap "Load" above to pick a saved sequence from the library.',
    );
  }
}

// _NodeList / _NodeRow / _NodeTile have moved to MobileSequenceEditor in
// packages/nightshade_app/lib/screens/sequencer/mobile_sequence_editor.dart
// so the touch-friendly authoring surface and the visual mapping live in
// one place (audit phone sequencer authoring parity).

class _StickyFooter extends ConsumerWidget {
  final Sequence? sequence;
  final SequenceProgress progress;
  final SequenceExecutionState execState;
  const _StickyFooter({
    required this.sequence,
    required this.progress,
    required this.execState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final size = MediaQuery.sizeOf(context);
    // Bottom strip occupies the lower third of the screen. We sit above
    // the bottom nav, so we cap height to keep the node list usable.
    final maxHeight = (size.height / 3).clamp(160.0, 260.0);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.target, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.currentTarget ?? sequence?.name ?? 'No target',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _ExecBadge(state: execState),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Frames',
                    value:
                        '${progress.completedExposures}/'
                        '${progress.totalExposures}',
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Elapsed',
                    value: _formatHms(progress.elapsedSecs),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'ETA',
                    value: progress.estimatedRemainingSecs != null
                        ? _formatHms(progress.estimatedRemainingSecs!)
                        : '—',
                    colors: colors,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Trigger status — show running triggers (HFR/guiding/etc.) if
            // any. The executor surfaces them as currentNodeName when a
            // trigger fires, so we render whichever message is freshest.
            if (progress.message != null && progress.message!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  progress.message!,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            _ControlButtons(sequence: sequence, execState: execState),
          ],
        ),
      ),
    );
  }
}

class _ExecBadge extends StatelessWidget {
  final SequenceExecutionState state;
  const _ExecBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (label, color) = switch (state) {
      SequenceExecutionState.idle => ('Idle', colors.textMuted),
      SequenceExecutionState.running => ('Running', colors.success),
      SequenceExecutionState.paused => ('Paused', colors.warning),
      SequenceExecutionState.stopping => ('Stopping', colors.warning),
      SequenceExecutionState.completed => ('Done', colors.success),
      SequenceExecutionState.failed => ('Failed', colors.error),
      // executor is mid-recovery (auto-retry after a recoverable
      // failure such as guide-star lost or weather unsafe). Use the
      // warning palette so the user sees something is wrong but the run
      // isn't dead yet.
      SequenceExecutionState.recovering => ('Recovering', colors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  const _Stat({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: colors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _ControlButtons extends ConsumerStatefulWidget {
  final Sequence? sequence;
  final SequenceExecutionState execState;
  const _ControlButtons({required this.sequence, required this.execState});

  @override
  ConsumerState<_ControlButtons> createState() => _ControlButtonsState();
}

class _ControlButtonsState extends ConsumerState<_ControlButtons> {
  bool _busy = false;

  Future<void> _start() async {
    if (widget.sequence == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).start();
    } catch (e) {
      if (mounted) {
        // [error parsing] — typed envelope, severity-tinted snack.
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).stop();
    } catch (e) {
      if (mounted) {
        // [error parsing] — typed envelope, severity-tinted snack.
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).pause();
    } catch (e) {
      if (mounted) {
        // [error parsing] — typed envelope, severity-tinted snack.
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).resume();
    } catch (e) {
      if (mounted) {
        // [error parsing] — typed envelope, severity-tinted snack.
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.execState == SequenceExecutionState.running;
    final isPaused = widget.execState == SequenceExecutionState.paused;
    final canStart =
        widget.sequence != null &&
        !isRunning &&
        !isPaused &&
        widget.execState != SequenceExecutionState.stopping;

    return Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: isPaused ? 'Resume' : (isRunning ? 'Pause' : 'Start'),
            icon: isPaused
                ? LucideIcons.play
                : (isRunning ? LucideIcons.pause : LucideIcons.play),
            size: ButtonSize.large,
            isLoading: _busy,
            variant: ButtonVariant.primary,
            onPressed: _busy
                ? null
                : (canStart
                      ? _start
                      : (isRunning ? _pause : (isPaused ? _resume : null))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HoldToStopButton(
            enabled: !_busy && (isRunning || isPaused),
            onConfirmed: _stop,
          ),
        ),
      ],
    );
  }
}

/// Wraps a destructive Stop button in a [HoldToConfirmButton] so a
/// thumb-slip during a multi-hour overnight imaging session can't abort
/// the run with a single tap. The user must hold for 1.5s; a circular
/// progress ring tracks the hold.
class _HoldToStopButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onConfirmed;

  const _HoldToStopButton({required this.enabled, required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Visual mirrors the destructive variant of NightshadeButton (filled
    // error background, onError foreground, large size). Rendered as a
    // passive Container so the HoldToConfirmButton GestureDetector has
    // exclusive ownership of touch input — no inner onTap to race with
    // the long-press recognizer.
    final stopVisual = Container(
      height: 44,
      decoration: BoxDecoration(
        color: enabled ? colors.error : colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: enabled ? colors.error : colors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg + 2,
        vertical: NightshadeTokens.spaceMd + 2,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.square,
            size: NightshadeTokens.iconSm,
            color: enabled
                ? Theme.of(context).colorScheme.onError
                : colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm - 2),
          Flexible(
            child: Text(
              'Stop',
              style: NightshadeTypography.button.copyWith(
                color: enabled
                    ? Theme.of(context).colorScheme.onError
                    : colors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );

    return HoldToConfirmButton(
      enabled: enabled,
      onConfirmed: onConfirmed,
      holdColor: Theme.of(context).colorScheme.onError,
      confirmText: 'Hold to stop',
      semanticsLabel: 'Press and hold to stop the sequence',
      child: stopVisual,
    );
  }
}

/// Compact wrapper around [RunDashboardWeatherSafetyCard] for the mobile
/// sequencer tab. The underlying card was sized for the desktop run
/// dashboard column; on a phone we collapse it behind an [ExpansionTile]
/// so it doesn't crowd the editor. The status pill still reads via the
/// header label (Safe/Unsafe/Snoozed) because the card itself is the
/// authority on that state — we only mirror the label here for the
/// collapsed surface, the colour is rendered by the card on expand.
class _WeatherSafetyExpansion extends ConsumerWidget {
  const _WeatherSafetyExpansion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final safety = ref.watch(weatherSafetyProvider);
    final (label, tint, icon) = switch (safety.status) {
      WeatherSafetyStatus.safe => ('Safe', colors.success, LucideIcons.check),
      WeatherSafetyStatus.unsafe => (
        'Unsafe',
        colors.error,
        LucideIcons.alertTriangle,
      ),
      WeatherSafetyStatus.snoozed => (
        'Snoozed',
        colors.warning,
        LucideIcons.bellOff,
      ),
    };
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Theme(
        // Strip the default ExpansionTile divider so the header reads as
        // part of the sticky header strip rather than a floating tile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(LucideIcons.shield, size: 18, color: colors.primary),
          title: Text(
            'Weather safety',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tint),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: tint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: colors.textSecondary,
              ),
            ],
          ),
          children: const [RunDashboardWeatherSafetyCard()],
        ),
      ),
    );
  }
}

String _formatHms(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) return '—';
  final secs = seconds.round();
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}
