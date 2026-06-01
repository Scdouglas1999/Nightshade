import 'dart:async';
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

    final mode = ref.read(polarAlignmentUiStateProvider).mode;
    if (mode == PolarAlignmentMode.allSky) {
      // All-sky routine: route through the polar alignment service which
      // calls the bridge `apiStartAllSkyPolarAlignment` entry point. The
      // backend raises a structured "Plate solver required — install
      // ASTAP" error when no solver is configured; surface it directly.
      final service = ref.read(polarAlignmentServiceProvider);
      final config = ref.read(polarAlignmentConfigProvider);
      try {
        // Eagerly transition the state into the adjusting phase so the
        // reticle widget begins rendering before the first solve lands.
        ref
            .read(polarAlignmentStateProvider.notifier)
            .startAllSkyAlignment(config);
        await service.allSky(config: config);
      } catch (e) {
        if (!mounted) return;
        context.showErrorSnackBar('All-sky polar alignment failed: $e');
        ref.read(polarAlignmentStateProvider.notifier).reset();
      }
      return;
    }

    final controller = ref.read(polarAlignmentControllerProvider);
    await controller.start();
  }

  Future<void> _stopAlignment() async {
    final controller = ref.read(polarAlignmentControllerProvider);
    await controller.stop();
  }

  Future<void> _completeAlignment() async {
    final controller = ref.read(polarAlignmentControllerProvider);
    await controller.complete();
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
