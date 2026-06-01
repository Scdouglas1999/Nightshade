// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

extension _CenterPanel on _PolarAlignmentScreenState {
  Widget _buildCenterPanel(
    NightshadeColors colors,
    PolarAlignmentState state,
    PolarAlignmentConfig config,
  ) {
    final detectionAsync = ref.watch(plateSolverDetectionProvider);
    final showSolverBanner = state.phase == PolarAlignPhase.idle &&
        detectionAsync.maybeWhen(
          data: (d) => !d.hasAnySolver,
          orElse: () => false,
        );

    return Container(
      color: colors.background,
      child: Column(
        children: [
          // Progress indicator
          if (state.phase == PolarAlignPhase.measuring ||
              state.phase == PolarAlignPhase.adjusting)
            _buildProgressSteps(colors, state),

          if (showSolverBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: PlateSolverRequiredBanner(
                contextMessage:
                    'Polar alignment plate-solves each capture to measure '
                    'mount error. Install and configure ASTAP (or '
                    'Astrometry.net) before starting.',
              ),
            ),

          // Main content area — scroll + width cap so idle copy never wraps
          // one character per line in a narrow center column.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth < 480
                              ? constraints.maxWidth
                              : 560,
                          minWidth: constraints.maxWidth < 400
                              ? constraints.maxWidth
                              : 400,
                        ),
                        child: state.phase == PolarAlignPhase.idle
                            ? _buildSetupInstructions(colors)
                            : state.phase == PolarAlignPhase.measuring
                                ? _buildMeasuringStatus(colors, state)
                                : state.phase == PolarAlignPhase.adjusting
                                    ? _buildAdjustmentInstructions(
                                        colors, state, config)
                                    : state.phase == PolarAlignPhase.complete
                                        ? _buildCompleteStatus(colors, state)
                                        : _buildErrorStatus(colors, state),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSteps(
      NightshadeColors colors, PolarAlignmentState state) {
    final point = state.currentPoint;
    final phase = state.phase;

    return Container(
      key: PolarAlignmentTutorialKeys.progress,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ProgressStep(
            colors: colors,
            number: 1,
            label: 'Capture 1',
            isActive: phase == PolarAlignPhase.measuring && point == 1,
            isComplete: point > 1 || phase == PolarAlignPhase.adjusting,
          ),
          _ProgressConnector(colors: colors, isComplete: point > 1),
          _ProgressStep(
            colors: colors,
            number: 2,
            label: 'Capture 2',
            isActive: phase == PolarAlignPhase.measuring && point == 2,
            isComplete: point > 2 || phase == PolarAlignPhase.adjusting,
          ),
          _ProgressConnector(colors: colors, isComplete: point > 2),
          _ProgressStep(
            colors: colors,
            number: 3,
            label: 'Capture 3',
            isActive: phase == PolarAlignPhase.measuring && point == 3,
            isComplete: phase == PolarAlignPhase.adjusting,
          ),
          _ProgressConnector(
              colors: colors, isComplete: phase == PolarAlignPhase.adjusting),
          _ProgressStep(
            colors: colors,
            number: 4,
            label: 'Adjust',
            isActive: phase == PolarAlignPhase.adjusting,
            isComplete: phase == PolarAlignPhase.complete,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupInstructions(NightshadeColors colors) {
    final isAllSky = ref.watch(polarAlignmentUiStateProvider).mode ==
        PolarAlignmentMode.allSky;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAllSky ? LucideIcons.globe : LucideIcons.compass,
            size: 64,
            color: colors.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            isAllSky
                ? 'All-Sky Polar Alignment'
                : 'Three-Point Polar Alignment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isAllSky
                ? 'Align from any part of the sky — no need to point near the '
                    'celestial pole. Nightshade plate-solves a live frame and '
                    'shows azimuth/altitude error on the target reticle while '
                    'you adjust the mount.'
                : 'This wizard helps you precisely align your mount to the '
                    'celestial pole. It captures three images at different '
                    'positions, plate-solves each one, and calculates polar '
                    'alignment error.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          if (isAllSky) ...[
            _InstructionStep(
              colors: colors,
              number: 1,
              text: 'Point at any bright star field (not necessarily the pole)',
            ),
            _InstructionStep(
              colors: colors,
              number: 2,
              text: 'Ensure camera and mount are connected',
            ),
            _InstructionStep(
              colors: colors,
              number: 3,
              text: 'Configure exposure settings on the left and click Start',
            ),
            _InstructionStep(
              colors: colors,
              number: 4,
              text:
                  'Follow the live reticle on the right while adjusting azimuth and altitude',
            ),
          ] else ...[
            _InstructionStep(
              colors: colors,
              number: 1,
              text:
                  'Roughly align your mount to the pole (within a few degrees)',
            ),
            _InstructionStep(
              colors: colors,
              number: 2,
              text: 'Point the telescope near the celestial pole',
            ),
            _InstructionStep(
              colors: colors,
              number: 3,
              text: 'Ensure camera and mount are connected',
            ),
            _InstructionStep(
              colors: colors,
              number: 4,
              text: 'Configure settings on the left and click Start',
            ),
          ],
        ],
      ),
    );
  }
}
