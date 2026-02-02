import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/sequence_action_service.dart';
import 'preflight_validation_dialog.dart';

/// Compact playback control bar for mobile devices.
/// Shows playback controls and current status in a single horizontal row.
class MobilePlaybackBar extends ConsumerWidget {
  final NightshadeColors colors;

  const MobilePlaybackBar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final sequence = ref.watch(currentSequenceProvider);

    final isIdle = executionState == SequenceExecutionState.idle;
    final isRunning = executionState == SequenceExecutionState.running;
    final isPaused = executionState == SequenceExecutionState.paused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // At very narrow widths (< 360px), hide info chips to prevent overflow
          final isVeryNarrow = constraints.maxWidth < 360;
          // At narrow widths (< 400px), use smaller spacing
          final isNarrow = constraints.maxWidth < 400;
          final buttonSpacing = isNarrow ? 4.0 : 8.0;

          return Row(
            children: [
              // Play/Pause button
              _MobilePlaybackButton(
                colors: colors,
                icon: isRunning ? LucideIcons.pause : LucideIcons.play,
                label: isRunning ? 'Pause' : (isPaused ? 'Resume' : 'Start'),
                isActive: isRunning,
                isCompact: isNarrow,
                onPressed: () {
                  if (isIdle) {
                    showDialog(
                      context: context,
                      builder: (context) => PreFlightValidationDialog(
                        onStartSequence: () {
                          ref.read(sequenceActionServiceProvider).start();
                        },
                      ),
                    );
                  } else if (isRunning) {
                    ref.read(sequenceActionServiceProvider).pause(context);
                  } else if (isPaused) {
                    ref.read(sequenceActionServiceProvider).resume(context);
                  }
                },
              ),

              SizedBox(width: buttonSpacing),

              // Stop button
              _MobilePlaybackButton(
                colors: colors,
                icon: LucideIcons.square,
                label: 'Stop',
                isEnabled: isRunning || isPaused,
                isCompact: isNarrow,
                onPressed: () {
                  ref.read(sequenceActionServiceProvider).stop(context);
                },
              ),

              SizedBox(width: buttonSpacing),

              // Skip button
              _MobilePlaybackButton(
                colors: colors,
                icon: LucideIcons.skipForward,
                label: 'Skip',
                isEnabled: isRunning,
                isCompact: isNarrow,
                onPressed: () {
                  ref.read(sequenceActionServiceProvider).skip(context);
                },
              ),

              const Spacer(),

              // Status indicator and info (hidden at very narrow widths)
              if (sequence != null && !isVeryNarrow) ...[
                // Frames count
                _InfoChip(
                  colors: colors,
                  icon: LucideIcons.camera,
                  value: '${sequence.totalExposures}',
                  isCompact: isNarrow,
                ),
                SizedBox(width: isNarrow ? 4 : 8),
                // Duration
                _InfoChip(
                  colors: colors,
                  icon: LucideIcons.clock,
                  value: _formatDuration(sequence.totalIntegrationSecs),
                  isCompact: isNarrow,
                ),
                SizedBox(width: isNarrow ? 4 : 8),
              ],

              // Status badge
              _StatusBadge(colors: colors, state: executionState, isCompact: isVeryNarrow),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

class _MobilePlaybackButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isEnabled;
  final bool isCompact;
  final VoidCallback onPressed;

  const _MobilePlaybackButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isEnabled = true,
    this.isCompact = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = isEnabled;
    // Ensure minimum touch target of 44px even when visually compact
    final buttonSize = isCompact ? 40.0 : 44.0;

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: effectiveEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.success.withValues(alpha: 0.15)
                  : effectiveEnabled
                      ? colors.surfaceAlt
                      : colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? colors.success.withValues(alpha: 0.5)
                    : colors.border,
              ),
            ),
            child: Icon(
              icon,
              size: isCompact ? 16 : 18,
              color: isActive
                  ? colors.success
                  : effectiveEnabled
                      ? colors.textPrimary
                      : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String value;
  final bool isCompact;

  const _InfoChip({
    required this.colors,
    required this.icon,
    required this.value,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = isCompact ? 6.0 : 8.0;
    final iconSize = isCompact ? 10.0 : 12.0;
    final fontSize = isCompact ? 10.0 : 11.0;
    final spacing = isCompact ? 3.0 : 4.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: colors.textMuted),
          SizedBox(width: spacing),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState state;
  final bool isCompact;

  const _StatusBadge({
    required this.colors,
    required this.state,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData icon;

    switch (state) {
      case SequenceExecutionState.idle:
        badgeColor = colors.textMuted;
        icon = LucideIcons.circleOff;
        break;
      case SequenceExecutionState.running:
        badgeColor = colors.success;
        icon = LucideIcons.activity;
        break;
      case SequenceExecutionState.paused:
        badgeColor = colors.warning;
        icon = LucideIcons.pauseCircle;
        break;
      case SequenceExecutionState.stopping:
        badgeColor = colors.warning;
        icon = LucideIcons.loader;
        break;
      case SequenceExecutionState.completed:
        badgeColor = colors.info;
        icon = LucideIcons.checkCircle;
        break;
      case SequenceExecutionState.failed:
        badgeColor = colors.error;
        icon = LucideIcons.xCircle;
        break;
    }

    final badgeSize = isCompact ? 28.0 : 32.0;
    final iconSize = isCompact ? 12.0 : 14.0;

    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: state == SequenceExecutionState.running
          ? _PulsingIcon(color: badgeColor, icon: icon, size: iconSize)
          : Icon(icon, size: iconSize, color: badgeColor),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final Color color;
  final IconData icon;
  final double size;

  const _PulsingIcon({required this.color, required this.icon, this.size = 14});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Icon(
          widget.icon,
          size: widget.size,
          color: widget.color.withValues(alpha: 0.5 + _controller.value * 0.5),
        );
      },
    );
  }
}
