part of '../status_bar.dart';

class _SequenceIndicator extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _SequenceIndicator({required this.colors});

  @override
  ConsumerState<_SequenceIndicator> createState() => _SequenceIndicatorState();
}

class _SequenceIndicatorState extends ConsumerState<_SequenceIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
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
        'Target: ${progress.currentTarget}',
      if ((progress.currentNodeName ?? '').isNotEmpty)
        'Step: ${progress.currentNodeName}',
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
    }
  }

  String _statusText(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.idle:
        return 'Idle';
      case SequenceExecutionState.running:
        return 'Running';
      case SequenceExecutionState.paused:
        return 'Paused';
      case SequenceExecutionState.stopping:
        return 'Stopping';
      case SequenceExecutionState.completed:
        return 'Completed';
      case SequenceExecutionState.failed:
        return 'Failed';
      case SequenceExecutionState.recovering:
        return 'Recovering';
    }
  }
}
