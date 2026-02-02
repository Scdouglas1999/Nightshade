import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/sequence_action_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'preflight_validation_dialog.dart';
import 'equipment_status_widget.dart';

class SequenceToolbar extends ConsumerWidget {
  final NightshadeColors colors;

  const SequenceToolbar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final sequence = ref.watch(currentSequenceProvider);
    
    final isIdle = executionState == SequenceExecutionState.idle;
    final isRunning = executionState == SequenceExecutionState.running;
    final isPaused = executionState == SequenceExecutionState.paused;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Playback controls
          _PlaybackControls(
            colors: colors,
            isIdle: isIdle,
            isRunning: isRunning,
            isPaused: isPaused,
            executionState: executionState,
            onStart: () {
              // Show pre-flight validation dialog before starting
              showDialog(
                context: context,
                builder: (context) => PreFlightValidationDialog(
                  onStartSequence: () {
                    ref.read(sequenceActionServiceProvider).start();
                  },
                ),
              );
            },
            onPause: () => ref.read(sequenceActionServiceProvider).pause(context),
            onResume: () => ref.read(sequenceActionServiceProvider).resume(context),
            onStop: () => ref.read(sequenceActionServiceProvider).stop(context),
            onSkip: () => ref.read(sequenceActionServiceProvider).skip(context),
            onReset: () => ref.read(sequenceActionServiceProvider).reset(),
          ),

          const SizedBox(width: 24),
          _Divider(colors: colors),
          const SizedBox(width: 24),

          // File operations
          _ToolbarIconButton(
            icon: LucideIcons.filePlus,
            tooltip: 'New Sequence',
            colors: colors,
            onPressed: () {
              ref.read(currentSequenceProvider.notifier).createSequence();
            },
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: LucideIcons.folderOpen,
            tooltip: 'Open Sequence',
            colors: colors,
            onPressed: () async {
              try {
                final fileService = ref.read(sequenceFileServiceProvider);
                final importedSequence = await fileService.importSequence();
                
                if (importedSequence != null) {
                  ref.read(currentSequenceProvider.notifier).loadSequence(importedSequence);

                  if (context.mounted) {
                    context.showSuccessSnackBar('Sequence "${importedSequence.name}" loaded');
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to load sequence: $e');
                }
              }
            },
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: LucideIcons.save,
            tooltip: 'Save Sequence',
            colors: colors,
            onPressed: () async {
              final currentSequence = ref.read(currentSequenceProvider);
              if (currentSequence == null) {
                if (context.mounted) {
                  context.showWarningSnackBar('No sequence to save');
                }
                return;
              }

              try {
                final fileService = ref.read(sequenceFileServiceProvider);
                await fileService.exportSequence(currentSequence);

                if (context.mounted) {
                  context.showSuccessSnackBar('Sequence "${currentSequence.name}" saved');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to save sequence: $e');
                }
              }
            },
          ),

          const SizedBox(width: 24),
          _Divider(colors: colors),
          const SizedBox(width: 24),

          // Polar Alignment
          _ToolbarIconButton(
            icon: LucideIcons.compass,
            tooltip: 'Polar Alignment',
            colors: colors,
            onPressed: () {
              context.push('/polar-alignment');
            },
          ),

          const SizedBox(width: 24),
          _Divider(colors: colors),
          const SizedBox(width: 24),

          // Slew to Target (if sequence has a target)
          if (sequence != null && sequence.targetHeaders.isNotEmpty) ...[
            _ToolbarIconButton(
              icon: LucideIcons.navigation,
              tooltip: 'Slew to Target',
              colors: colors,
              onPressed: () async {
                final targetGroup = sequence.targetHeaders.first;
                try {
                  final deviceService = ref.read(deviceServiceProvider);
                  await deviceService.slewMountToCoordinates(
                    targetGroup.raHours,
                    targetGroup.decDegrees,
                  );

                  if (context.mounted) {
                    context.showInfoSnackBar('Slewing to ${targetGroup.targetName}');
                  }
                } catch (e) {
                  if (context.mounted) {
                    context.showErrorSnackBar('Failed to slew: $e');
                  }
                }
              },
            ),
            const SizedBox(width: 4),
          ],

          // Undo/Redo
          _ToolbarIconButton(
            icon: LucideIcons.undo2,
            tooltip: 'Undo (Ctrl+Z)',
            colors: colors,
            onPressed: ref.read(currentSequenceProvider.notifier).canUndo
                ? () => ref.read(currentSequenceProvider.notifier).undo()
                : null,
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: LucideIcons.redo2,
            tooltip: 'Redo (Ctrl+Y)',
            colors: colors,
            onPressed: ref.read(currentSequenceProvider.notifier).canRedo
                ? () => ref.read(currentSequenceProvider.notifier).redo()
                : null,
          ),

          const Spacer(),

          // Sequence info
          if (sequence != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.camera, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${sequence.totalExposures} frames',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    _formatDuration(sequence.totalIntegrationSecs),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Equipment status indicators
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: EquipmentStatusWidget(colors: colors),
          ),

          // Simulation mode indicator
          Consumer(
            builder: (context, ref, child) {
              final settingsAsync = ref.watch(appSettingsProvider);
              final isSimulation = settingsAsync.valueOrNull?.useSimulationMode ?? false;
              if (!isSimulation) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.testTube, size: 14, color: colors.warning),
                      const SizedBox(width: 6),
                      Text(
                        'SIMULATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.warning,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Status badge
          _StatusBadge(
            colors: colors,
            executionState: executionState,
          ),
        ],
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

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.colors.success,
                    Color.lerp(widget.colors.success, widget.colors.primary, 0.3)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: widget.colors.success.withValues(alpha: 
                      _isHovered ? 0.5 : 0.2 + _pulseController.value * 0.1,
                    ),
                    blurRadius: _isHovered ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.play,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
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
        cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
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

class _ToolbarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isHovered && !isDisabled
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: isDisabled
                  ? widget.colors.textMuted
                  : _isHovered
                      ? widget.colors.textPrimary
                      : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final NightshadeColors colors;

  const _Divider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: colors.border,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState executionState;

  const _StatusBadge({
    required this.colors,
    required this.executionState,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String label;
    IconData icon;

    switch (executionState) {
      case SequenceExecutionState.idle:
        badgeColor = colors.textMuted;
        label = 'Idle';
        icon = LucideIcons.circleOff;
        break;
      case SequenceExecutionState.running:
        badgeColor = colors.success;
        label = 'Running';
        icon = LucideIcons.activity;
        break;
      case SequenceExecutionState.paused:
        badgeColor = colors.warning;
        label = 'Paused';
        icon = LucideIcons.pauseCircle;
        break;
      case SequenceExecutionState.stopping:
        badgeColor = colors.warning;
        label = 'Stopping';
        icon = LucideIcons.loader;
        break;
      case SequenceExecutionState.completed:
        badgeColor = colors.info;
        label = 'Completed';
        icon = LucideIcons.checkCircle;
        break;
      case SequenceExecutionState.failed:
        badgeColor = colors.error;
        label = 'Failed';
        icon = LucideIcons.xCircle;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (executionState == SequenceExecutionState.running)
            _PulsingDot(color: badgeColor)
          else
            Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
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
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5 * (1 - _controller.value)),
                blurRadius: 4 + _controller.value * 4,
                spreadRadius: _controller.value * 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

