import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../services/sequence_action_service.dart';

/// Mobile-optimized sequence control bar
class SequenceControls extends ConsumerWidget {
  const SequenceControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sequenceExecutionStateProvider);
    final colors = Theme.of(context).extension<NightshadeColors>();

    final surfaceColor = colors?.surface ?? Theme.of(context).cardColor;
    final borderColor = colors?.border ?? Colors.grey.shade300;
    final primaryColor = colors?.primary ?? Theme.of(context).colorScheme.primary;

    // Don't show controls if sequence is idle or completed
    if (state == SequenceExecutionState.idle || state == SequenceExecutionState.completed) {
      return const SizedBox.shrink();
    }

    final isRunning = state == SequenceExecutionState.running;
    final isPaused = state == SequenceExecutionState.paused;
    final canControl = isRunning || isPaused;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pause/Resume button
          Expanded(
            child: _ControlButton(
              icon: isPaused ? Icons.play_arrow : Icons.pause,
              label: isPaused ? 'Resume' : 'Pause',
              color: isPaused ? Colors.green : Colors.orange,
              enabled: canControl,
              onPressed: () {
                if (isPaused) {
                  ref.read(sequenceActionServiceProvider).resume(context);
                } else {
                  ref.read(sequenceActionServiceProvider).pause(context);
                }
              },
            ),
          ),

          const SizedBox(width: 12),

          // Stop button
          Expanded(
            child: _ControlButton(
              icon: Icons.stop,
              label: 'Stop',
              color: Colors.red,
              enabled: canControl,
              onPressed: () => ref.read(sequenceActionServiceProvider).stop(context, requireConfirmation: true),
            ),
          ),

          const SizedBox(width: 12),

          // Skip button
          Expanded(
            child: _ControlButton(
              icon: Icons.skip_next,
              label: 'Skip',
              color: primaryColor,
              enabled: isRunning,
              onPressed: () => ref.read(sequenceActionServiceProvider).skip(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.65) : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: enabled ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
