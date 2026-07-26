import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/plate_solver_required_banner.dart';
import '../../widgets/tutorial_keys/polar_alignment_keys.dart';
import 'polar_alignment_body_layout.dart';
import 'widgets/all_sky_target_reticle.dart';
import 'widgets/polar_alignment_segmented_button.dart';
// ---------------------------------------------------------------------------
// File split: the PolarAlignmentScreen state keeps lifecycle and alignment
// actions. Panel builders, helper widgets, and painters live in focused library
// parts so the private provider-facing implementation remains encapsulated.
// ---------------------------------------------------------------------------

part 'polar_alignment_screen_parts/_status_and_settings.dart';
part 'polar_alignment_screen_parts/_progress_widgets.dart';
part 'polar_alignment_screen_parts/_error_visualization.dart';
part 'polar_alignment_screen_parts/_screen_shell.dart';
part 'polar_alignment_screen_parts/_configuration_panel.dart';
part 'polar_alignment_screen_parts/_history_panel.dart';
part 'polar_alignment_screen_parts/_center_panel.dart';
part 'polar_alignment_screen_parts/_measurement_panel.dart';
part 'polar_alignment_screen_parts/_completion_panel.dart';
part 'polar_alignment_screen_parts/_right_panel.dart';

class PolarAlignmentScreen extends ConsumerStatefulWidget {
  const PolarAlignmentScreen({super.key});

  @override
  ConsumerState<PolarAlignmentScreen> createState() =>
      _PolarAlignmentScreenState();
}

class _PolarAlignmentScreenState extends ConsumerState<PolarAlignmentScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startAlignment() async {
    // Validate equipment is connected before starting
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      ref.read(polarAlignmentStateProvider.notifier).reset();
      context.showErrorSnackBar(
        'Camera not connected. Please connect a camera before starting polar alignment.',
      );
      return;
    }

    if (mountState.connectionState != DeviceConnectionState.connected) {
      ref.read(polarAlignmentStateProvider.notifier).reset();
      context.showErrorSnackBar(
        'Mount not connected. Please connect a mount before starting polar alignment.',
      );
      return;
    }

    // Check the user's actual solver selection before either alignment mode
    // starts capturing or moving equipment. It is not enough for a different
    // solver to be installed when the selected one is unusable.
    try {
      await ref.read(plateSolveServiceProvider).ensureSolverAvailable();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar(
        'Plate solver not ready. Check Plate Solving settings: $e',
      );
      return;
    }

    final mode = ref.read(polarAlignmentUiStateProvider).mode;
    final config = ref.read(polarAlignmentConfigProvider);
    if (mode == PolarAlignmentMode.allSky) {
      // All-sky routine: route through the single guarded state machine, which
      // transitions into the adjusting phase and calls the bridge
      // `apiStartAllSkyPolarAlignment` entry point. The backend raises a
      // structured "Plate solver required — install ASTAP" error when no solver
      // is configured; surface it directly.
      try {
        await ref
            .read(polarAlignmentStateProvider.notifier)
            .startAllSkyAlignment(config);
      } catch (e) {
        if (!mounted) return;
        context.showErrorSnackBar('All-sky polar alignment failed: $e');
      }
      return;
    }

    // TPPA: startAlignment now fails the awaited command on invalid config or
    // when a run is already active — surface it instead of letting it throw
    // uncaught. The error phase already reflects the reason on-screen.
    try {
      await ref.read(polarAlignmentControllerProvider).start();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not start polar alignment: $e');
    }
  }

  Future<void> _stopAlignment() async {
    try {
      await ref.read(polarAlignmentControllerProvider).stop();
    } catch (e) {
      if (!mounted) return;
      // Stop failed/timed out: the run stays blocked and visibly in error.
      context.showErrorSnackBar('Could not stop polar alignment: $e');
    }
  }

  Future<void> _completeAlignment() async {
    try {
      await ref.read(polarAlignmentControllerProvider).complete();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not complete polar alignment: $e');
    }
  }

  void _resetAlignment() {
    final controller = ref.read(polarAlignmentControllerProvider);
    controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    // Pulse animation only ticks while alignment is running; otherwise it
    // burns a frame/sec for a status indicator that isn't visible.
    ref.listen<PolarAlignmentState>(polarAlignmentStateProvider, (prev, next) {
      final wasRunning = prev?.isRunning ?? false;
      if (next.isRunning && !wasRunning) {
        _pulseController.repeat(reverse: true);
      } else if (!next.isRunning && wasRunning) {
        _pulseController.stop();
      }
    });

    // Surface config persistence failures truthfully — settings that failed to
    // save must not look persisted.
    ref.listen<String?>(polarAlignmentConfigSaveErrorProvider, (prev, next) {
      if (next != null && next != prev && mounted) {
        context.showErrorSnackBar(next);
      }
    });

    final colors = NightshadeColors.of(context);
    final state = ref.watch(polarAlignmentStateProvider);
    final config = ref.watch(polarAlignmentConfigProvider);

    final isRunning = state.isRunning;

    return ContextualTourPrompt(
      screenId: 'polar_alignment',
      tourCategory: TutorialCategory.polarAlignmentTour,
      title: 'Polar Alignment Tour',
      description: 'Learn how to polar align your mount for accurate tracking.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            // Header bar
            _buildHeader(colors, isRunning),

            // Main content — responsive layout avoids squeezing the guide
            // column when embedded beside the app shell or on smaller displays.
            Expanded(
              child: PolarAlignmentBodyLayout(
                leftPanel: _buildLeftPanel(colors, state, config, isRunning),
                centerPanel: _buildCenterPanel(colors, state, config),
                rightPanel: _buildRightPanel(colors, state, config),
              ),
            ),

            // Footer with actions
            _buildFooter(colors, state, isRunning),
          ],
        ),
      ),
    );
  }
}
