part of '../status_bar.dart';

class _SequenceIndicator extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final NightshadeLocalizations l10n;

  const _SequenceIndicator({required this.colors, required this.l10n});

  @override
  ConsumerState<_SequenceIndicator> createState() => _SequenceIndicatorState();
}

class _SequenceIndicatorState extends ConsumerState<_SequenceIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // NOT started here. This indicator is in the status bar on EVERY screen;
    // repeating unconditionally repainted the bar at ~60Hz forever (a large
    // chunk of the app's idle CPU) to produce no visible change when no
    // sequence is running. The pulse is started/stopped in build() based on the
    // actual execution state.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    // Only pulse while a sequence is actually running; otherwise hold the
    // controller still so the status bar isn't repainted every frame at idle.
    final isRunning = executionState == SequenceExecutionState.running;
    if (isRunning) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    final progress = ref.watch(sequenceProgressProvider);
    final statusText = _statusText(executionState);
    final indicatorColor = _indicatorColor(executionState);
    final progressPercent = progress.totalExposures > 0
        ? (progress.progressPercent * 100).round()
        : null;
    final displayText = progressPercent != null &&
            executionState != SequenceExecutionState.idle &&
            executionState != SequenceExecutionState.completed &&
            executionState != SequenceExecutionState.failed
        ? '$statusText $progressPercent%'
        : statusText;
    final tooltipLines = <String>[
      statusText,
      if ((progress.currentTarget ?? '').isNotEmpty)
        widget.l10n.text(
          'statusSequenceTarget',
          params: {'name': progress.currentTarget!},
        ),
      if ((progress.currentNodeName ?? '').isNotEmpty)
        widget.l10n.text(
          'statusSequenceStep',
          params: {'name': progress.currentNodeName!},
        ),
      if ((progress.message ?? '').isNotEmpty) progress.message!,
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusInline8,
          border: Border.all(
            color: widget.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final isRunning =
                    executionState == SequenceExecutionState.running;
                final opacity =
                    isRunning ? (0.45 + (_pulseController.value * 0.55)) : 1.0;
                return Opacity(opacity: opacity, child: child);
              },
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: indicatorColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayText,
              style: NightshadeTypography.labelQuiet
                  .copyWith(color: widget.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Color _indicatorColor(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.idle:
        return widget.colors.textMuted;
      case SequenceExecutionState.running:
        return widget.colors.success;
      case SequenceExecutionState.paused:
        return widget.colors.warning;
      case SequenceExecutionState.stopping:
        return widget.colors.error;
      case SequenceExecutionState.completed:
        return widget.colors.primary;
      case SequenceExecutionState.failed:
        return widget.colors.error;
      case SequenceExecutionState.recovering:
        // Recovery is its own visible state. Use the error
        // colour so the status bar dot is unmistakeably "something is
        // wrong, the sequence is fighting through it" — same colour as
        // the recovery banner for consistency.
        return widget.colors.error;
      case SequenceExecutionState.stopFailed:
        // Native stop failed — hardware may still be imaging. Error colour.
        return widget.colors.error;
      case SequenceExecutionState.cleanupFailed:
        // Hardware stopped; session save failed and needs a retry.
        return widget.colors.warning;
      case SequenceExecutionState.finalizing:
        // Run ended, durable cleanup wrapping up — calm, transient.
        return widget.colors.info;
    }
  }

  String _statusText(SequenceExecutionState state) {
    final l10n = widget.l10n;
    switch (state) {
      case SequenceExecutionState.idle:
        return l10n.text('idle');
      case SequenceExecutionState.running:
        return l10n.text('sequenceRunning');
      case SequenceExecutionState.paused:
        return l10n.text('sequencePaused');
      case SequenceExecutionState.stopping:
        return l10n.text('statusSequenceStopping');
      case SequenceExecutionState.completed:
        return l10n.text('statusSequenceCompleted');
      case SequenceExecutionState.failed:
        return l10n.text('statusSequenceFailed');
      case SequenceExecutionState.recovering:
        return l10n.text('statusSequenceRecovering');
      case SequenceExecutionState.stopFailed:
        return l10n.text('statusSequenceStopFailed');
      case SequenceExecutionState.cleanupFailed:
        return l10n.text('statusSequenceCleanupFailed');
      case SequenceExecutionState.finalizing:
        return l10n.text('statusSequenceFinalizing');
    }
  }
}
