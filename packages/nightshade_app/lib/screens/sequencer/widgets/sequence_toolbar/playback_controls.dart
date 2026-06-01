part of '../sequence_toolbar.dart';

class _PlaybackControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool isIdle;
  final bool isRunning;
  final bool isPaused;
  final SequenceExecutionState executionState;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onSkip;
  final VoidCallback onReset;

  const _PlaybackControls({
    required this.colors,
    required this.isIdle,
    required this.isRunning,
    required this.isPaused,
    required this.executionState,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSkip,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // Reset is enabled when sequence is idle, completed, or failed (not running/paused)
    final canReset = executionState == SequenceExecutionState.idle ||
        executionState == SequenceExecutionState.completed ||
        executionState == SequenceExecutionState.failed;

    return Row(
      children: [
        // Play/Pause button
        if (isIdle || isPaused)
          _PlayButton(
            colors: colors,
            onPressed: isIdle ? onStart : onResume,
            label: isIdle ? 'Start' : 'Resume',
          )
        else
          _PauseButton(colors: colors, onPressed: onPause),

        const SizedBox(width: 8),

        // Stop button
        _ControlButton(
          icon: LucideIcons.square,
          tooltip: 'Stop',
          colors: colors,
          onPressed: (isRunning || isPaused) ? onStop : null,
        ),

        const SizedBox(width: 8),

        // Skip button
        _ControlButton(
          icon: LucideIcons.skipForward,
          tooltip: 'Skip to Next',
          colors: colors,
          onPressed: isRunning ? onSkip : null,
        ),

        const SizedBox(width: 8),

        // Reset button - resets execution state without modifying sequence config
        _ControlButton(
          icon: LucideIcons.rotateCcw,
          tooltip: 'Reset Sequence',
          colors: colors,
          onPressed: canReset ? onReset : null,
        ),
      ],
    );
  }
}

class _PlayButton extends StatefulWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;
  final String label;

  const _PlayButton({
    required this.colors,
    required this.onPressed,
    required this.label,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: NightshadeDecorations.filledButton(
            widget.colors.success,
            isHovered: _isHovered,
            isDisabled: false,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.play,
                size: 16,
                color: onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseButton extends StatefulWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _PauseButton({
    required this.colors,
    required this.onPressed,
  });

  @override
  State<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends State<_PauseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.warning.withValues(alpha: 0.2)
                : widget.colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.colors.warning.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.pause,
                size: 16,
                color: widget.colors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                'Pause',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _isHovered && !isDisabled
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: isDisabled
                  ? widget.colors.textMuted
                  : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
