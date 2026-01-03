import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

// Import mobile-specific widgets
import 'sequence_progress_card.dart';
import 'sequence_controls.dart';

/// Overlay widget that displays mobile sequence progress and controls
/// only when a sequence is running on mobile devices
class MobileSequenceOverlay extends ConsumerWidget {
  const MobileSequenceOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);

    // Don't show overlay if sequence is idle
    if (executionState == SequenceExecutionState.idle) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),

            // Progress card
            const IgnorePointer(
              ignoring: true,
              child: SequenceProgressCard(),
            ),

            // Control buttons
            const SequenceControls(),

            // Bottom padding for safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}
