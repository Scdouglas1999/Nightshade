import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../services/sequence_action_service.dart';
import '../utils/snackbar_helper.dart';

/// Mobile-optimized sequence control bar
class SequenceControls extends ConsumerWidget {
  const SequenceControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sequenceExecutionStateProvider);
    final colors = NightshadeColors.of(context);

    final surfaceColor = colors.surface;
    final borderColor = colors.border;
    final primaryColor = colors.primary;
    final warningColor = colors.warning;
    final successColor = colors.success;
    final errorColor = colors.error;

    // Keep controls reachable in retryable stop/cleanup failure states. This
    // surface previously disappeared outside running/paused, which could
    // strand a mobile operator without the Stop retry exposed elsewhere.
    if (!state.isBusy) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pause/Resume button
          Expanded(
            child: _ControlButton(
              icon: state.canResume ? Icons.play_arrow : Icons.pause,
              label: state.canResume ? 'Resume' : 'Pause',
              color: state.canResume ? successColor : warningColor,
              enabled: state.canPause || state.canResume,
              onPressed: () async {
                final service = ref.read(sequenceActionServiceProvider);
                final result = state.canResume
                    ? await service.resume()
                    : await service.pause();
                if (!context.mounted) return;
                context.showCommandActionResult(result);
              },
            ),
          ),

          const SizedBox(width: 12),

          // Stop button
          Expanded(
            child: _ControlButton(
              icon: Icons.stop,
              label: 'Stop',
              color: errorColor,
              enabled: state.canStop,
              onPressed: () async {
                final confirmed = await _confirmStop(context);
                if (!confirmed || !context.mounted) return;
                final result =
                    await ref.read(sequenceActionServiceProvider).stop();
                if (!context.mounted) return;
                context.showCommandActionResult(result);
              },
            ),
          ),

          const SizedBox(width: 12),

          // Skip button
          Expanded(
            child: _ControlButton(
              icon: Icons.skip_next,
              label: 'Skip',
              color: primaryColor,
              enabled: state.canSkip,
              onPressed: () async {
                final result =
                    await ref.read(sequenceActionServiceProvider).skip();
                if (!context.mounted) return;
                context.showCommandActionResult(result);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmStop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop Sequence?'),
        content:
            const Text('This will stop the current sequence. Are you sure?'),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          NightshadeButton(
            label: 'Stop',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return confirmed == true;
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
    final colors = NightshadeColors.of(context);
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.65) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: enabled ? colors.background : colors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? colors.background : colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
