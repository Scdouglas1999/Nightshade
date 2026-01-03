import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Mobile-optimized sequence control bar
class SequenceControls extends ConsumerStatefulWidget {
  const SequenceControls({super.key});

  @override
  ConsumerState<SequenceControls> createState() => _SequenceControlsState();
}

class _SequenceControlsState extends ConsumerState<SequenceControls> {
  bool _pauseResumeLoading = false;
  bool _stopLoading = false;
  bool _skipLoading = false;
  String? _errorMessage;

  Future<void> _handlePauseResume() async {
    setState(() {
      _pauseResumeLoading = true;
      _errorMessage = null;
    });

    try {
      final executor = ref.read(sequenceExecutorProvider);
      final currentState = ref.read(sequenceExecutionStateProvider);

      if (currentState == SequenceExecutionState.running) {
        await executor.pause();
      } else if (currentState == SequenceExecutionState.paused) {
        await executor.resume();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        // Show error snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pauseResumeLoading = false;
        });
      }
    }
  }

  Future<void> _handleStop() async {
    // Confirm stop action
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).extension<NightshadeColors>();
        final surfaceColor = colors?.surface ?? Theme.of(context).cardColor;
        final textColor = colors?.textPrimary ?? Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

        return AlertDialog(
          backgroundColor: surfaceColor,
          title: Text(
            'Stop Sequence?',
            style: TextStyle(color: textColor),
          ),
          content: Text(
            'Are you sure you want to stop the sequence? This action cannot be undone.',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _stopLoading = true;
      _errorMessage = null;
    });

    try {
      final executor = ref.read(sequenceExecutorProvider);
      await executor.stop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping sequence: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _stopLoading = false;
        });
      }
    }
  }

  Future<void> _handleSkip() async {
    setState(() {
      _skipLoading = true;
      _errorMessage = null;
    });

    try {
      final executor = ref.read(sequenceExecutorProvider);
      await executor.skip();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Skipped current item'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error skipping: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _skipLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              enabled: canControl && !_pauseResumeLoading && !_stopLoading,
              loading: _pauseResumeLoading,
              onPressed: _handlePauseResume,
            ),
          ),

          const SizedBox(width: 12),

          // Stop button
          Expanded(
            child: _ControlButton(
              icon: Icons.stop,
              label: 'Stop',
              color: Colors.red,
              enabled: canControl && !_stopLoading && !_pauseResumeLoading,
              loading: _stopLoading,
              onPressed: _handleStop,
            ),
          ),

          const SizedBox(width: 12),

          // Skip button
          Expanded(
            child: _ControlButton(
              icon: Icons.skip_next,
              label: 'Skip',
              color: primaryColor,
              enabled: isRunning && !_skipLoading && !_pauseResumeLoading && !_stopLoading,
              loading: _skipLoading,
              onPressed: _handleSkip,
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
  final bool loading;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.loading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? color : Colors.grey.shade300,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: enabled ? 2 : 0,
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
}
