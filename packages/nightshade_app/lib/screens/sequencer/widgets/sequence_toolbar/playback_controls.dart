part of '../sequence_toolbar.dart';

class _PlaybackControls extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState executionState;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onSkip;
  final VoidCallback onReset;

  const _PlaybackControls({
    required this.colors,
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
    final state = executionState;

    return Row(
      children: [
        // Primary transport button, driven by the centralized state
        // capabilities so every surface agrees:
        //   * running                     -> Pause
        //   * paused                      -> Resume
        //   * idle / completed / failed   -> a FUNCTIONAL Start (completed/
        //     failed re-arm the same sequence — never a dead Pause or a silent
        //     exact-idle no-op)
        //   * stopping / recovering / stopFailed / cleanupFailed -> a disabled
        //     Start, so the operator's action funnels to the (enabled) Stop.
        if (state.canPause)
          _PauseButton(colors: colors, onPressed: onPause)
        else
          _PlayButton(
            colors: colors,
            onPressed:
                state.canResume ? onResume : (state.canStart ? onStart : null),
            label: state.canResume ? 'Resume' : 'Start',
          ),

        const SizedBox(width: 8),

        // Stop button — enabled wherever a stop is meaningful, including a
        // retry from stopFailed / cleanupFailed.
        _ControlButton(
          icon: LucideIcons.square,
          tooltip: 'Stop',
          colors: colors,
          onPressed: state.canStop ? onStop : null,
        ),

        const SizedBox(width: 8),

        // Skip button — the backend skip advances the node pointer, valid in
        // both running and paused states.
        _ControlButton(
          icon: LucideIcons.skipForward,
          tooltip: 'Skip to Next',
          colors: colors,
          onPressed: state.canSkip ? onSkip : null,
        ),

        const SizedBox(width: 8),

        // Reset — resets execution state without modifying the sequence config.
        // Only from a settled state (idle / completed / failed).
        _ControlButton(
          icon: LucideIcons.rotateCcw,
          tooltip: 'Reset Sequence',
          colors: colors,
          onPressed: state.canReset ? onReset : null,
        ),
      ],
    );
  }
}

class _PlayButton extends StatefulWidget {
  final NightshadeColors colors;

  /// Null renders a disabled Start (used for the transient / needs-attention
  /// states where Start is not admissible but the button holds its place so
  /// the row layout stays stable and the Stop button reads clearly).
  final VoidCallback? onPressed;
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
    final isDisabled = widget.onPressed == null;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final foreground = isDisabled ? widget.colors.textMuted : onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: NightshadeDecorations.filledButton(
            widget.colors.success,
            isHovered: _isHovered && !isDisabled,
            isDisabled: isDisabled,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.play,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: NightshadeTypography.labelStrong
                    .copyWith(color: foreground),
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
                style: NightshadeTypography.labelStrong
                    .copyWith(color: widget.colors.warning),
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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
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
