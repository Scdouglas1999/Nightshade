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
// File split: the helper widgets and painters that compose the side panels
// live in `polar_alignment_screen_parts/`. The PolarAlignmentScreen widget
// and its private state class stay in this file because the state class is
// the orchestrator -- it owns the pulse animation, hosts every build_*
// helper for the run/finish/reset flows, and reaches into a wide surface of
// providers in a way that doesn't extract cleanly into a notifier without
// significant churn.
// ---------------------------------------------------------------------------

part 'polar_alignment_screen_parts/_status_and_settings.dart';
part 'polar_alignment_screen_parts/_progress_widgets.dart';
part 'polar_alignment_screen_parts/_error_visualization.dart';


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

  Widget _buildHeader(NightshadeColors colors, bool isRunning) {
    final ui = ref.watch(polarAlignmentUiStateProvider);
    final uiNotifier = ref.read(polarAlignmentUiStateProvider.notifier);

    final modeSelector = PolarAlignmentSegmentedButton<PolarAlignmentMode>(
      segments: const [
        ButtonSegment(
          value: PolarAlignmentMode.threePoint,
          label: Text('TPPA'),
          icon: Icon(LucideIcons.target, size: 14),
        ),
        ButtonSegment(
          value: PolarAlignmentMode.allSky,
          label: Text('All-Sky'),
          icon: Icon(LucideIcons.globe, size: 14),
        ),
      ],
      selected: {ui.mode},
      showSelectedIcon: false,
      onSelectionChanged:
          isRunning ? null : (selection) => uiNotifier.setMode(selection.first),
    );

    final historyButton = NightshadeButton(
      label: 'History',
      icon: LucideIcons.history,
      variant:
          ui.showHistoryPanel ? ButtonVariant.primary : ButtonVariant.ghost,
      size: ButtonSize.small,
      onPressed: () => uiNotifier.toggleHistoryPanel(),
    );

    final backButton = IconButton(
      icon: Icon(LucideIcons.arrowLeft, color: colors.textPrimary),
      onPressed: isRunning
          ? null
          : () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/imaging');
              }
            },
      tooltip: isRunning ? 'Stop alignment first' : 'Back',
    );

    final titleBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.compass, color: colors.primary, size: 24),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Polar Alignment',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                ui.mode.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useCompactHeader = constraints.maxWidth < 960;

          if (!useCompactHeader) {
            return SizedBox(
              height: 48,
              child: Row(
                children: [
                  backButton,
                  const SizedBox(width: 8),
                  titleBlock,
                  const SizedBox(width: 16),
                  modeSelector,
                  const Spacer(),
                  historyButton,
                  const SizedBox(width: 12),
                  _buildEquipmentIndicators(colors),
                ],
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    backButton,
                    Expanded(child: titleBlock),
                    historyButton,
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: modeSelector),
                  const SizedBox(width: 8),
                  _buildEquipmentIndicators(colors),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEquipmentIndicators(NightshadeColors colors) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);

    return Row(
      children: [
        _StatusChip(
          icon: LucideIcons.camera,
          label: 'Camera',
          isConnected:
              cameraState.connectionState == DeviceConnectionState.connected,
          colors: colors,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          icon: LucideIcons.move,
          label: 'Mount',
          isConnected:
              mountState.connectionState == DeviceConnectionState.connected,
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildLeftPanel(
    NightshadeColors colors,
    PolarAlignmentState state,
    PolarAlignmentConfig config,
    bool isRunning,
  ) {
    final ui = ref.watch(polarAlignmentUiStateProvider);

    return Container(
      color: colors.surface,
      child: Column(
        children: [
          // Configuration section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Essential settings - always visible
                  _buildSectionHeader(
                      colors, 'Essential', LucideIcons.settings),
                  const SizedBox(height: 12),
                  _buildEssentialSettings(colors, config, isRunning),

                  const SizedBox(height: 16),

                  // Common settings - collapsible
                  _buildCommonSettings(colors, config, isRunning),

                  const SizedBox(height: 8),

                  // Advanced settings - collapsible
                  _buildAdvancedSettings(colors, config, isRunning),

                  if (state.phase == PolarAlignPhase.adjusting) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                        colors, 'Adjustment Tips', LucideIcons.lightbulb),
                    const SizedBox(height: 12),
                    _buildAdjustmentTips(colors),
                    if (state.currentError != null) ...[
                      const SizedBox(height: 16),
                      _buildAdjustmentGuidance(colors, state.currentError!),
                    ],
                  ],

                  // History panel (shown when toggled)
                  if (ui.showHistoryPanel) ...[
                    const SizedBox(height: 24),
                    _buildHistoryPanel(colors),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      NightshadeColors colors, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEssentialSettings(
    NightshadeColors colors,
    PolarAlignmentConfig config,
    bool isRunning,
  ) {
    final configNotifier = ref.read(polarAlignmentConfigProvider.notifier);

    return Column(
      children: [
        // Hemisphere
        _SettingRow(
          label: 'Hemisphere',
          tooltip:
              'Northern or Southern hemisphere determines celestial pole position',
          colors: colors,
          child: PolarAlignmentSegmentedButton<bool>(
            buttonKey: PolarAlignmentTutorialKeys.hemisphere,
            segments: const [
              ButtonSegment(value: true, label: Text('North')),
              ButtonSegment(value: false, label: Text('South')),
            ],
            selected: {config.isNorth},
            onSelectionChanged:
                isRunning ? null : (v) => configNotifier.setIsNorth(v.first),
          ),
        ),
        const SizedBox(height: 12),

        // Exposure time
        _SettingRow(
          label: 'Exposure',
          tooltip:
              'Longer exposures capture more stars but slow down iterations',
          colors: colors,
          child: Row(
            key: PolarAlignmentTutorialKeys.exposure,
            children: [
              Expanded(
                child: Slider(
                  value: config.exposureTime,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  onChanged: isRunning
                      ? null
                      : (v) => configNotifier.setExposureTime(v),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${config.exposureTime.toInt()}s',
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommonSettings(
    NightshadeColors colors,
    PolarAlignmentConfig config,
    bool isRunning,
  ) {
    final configNotifier = ref.read(polarAlignmentConfigProvider.notifier);
    final ui = ref.watch(polarAlignmentUiStateProvider);
    final uiNotifier = ref.read(polarAlignmentUiStateProvider.notifier);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: ui.showCommonSettings,
        onExpansionChanged: uiNotifier.setShowCommonSettings,
        title: Row(
          children: [
            Icon(LucideIcons.sliders, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Common',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        children: [
          // Binning
          _SettingRow(
            label: 'Binning',
            tooltip: 'Higher binning = faster plate solves, lower resolution',
            colors: colors,
            child: PolarAlignmentSegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1x1')),
                ButtonSegment(value: 2, label: Text('2x2')),
                ButtonSegment(value: 4, label: Text('4x4')),
              ],
              selected: {config.binning},
              onSelectionChanged:
                  isRunning ? null : (v) => configNotifier.setBinning(v.first),
            ),
          ),
          const SizedBox(height: 12),

          // Step size
          _SettingRow(
            label: 'Step Size',
            tooltip:
                'Distance between measurement points. Larger = more accurate but may hit mount limits',
            colors: colors,
            child: Row(
              key: PolarAlignmentTutorialKeys.stepSize,
              children: [
                Expanded(
                  child: Slider(
                    value: config.stepSize,
                    min: 10,
                    max: 45,
                    divisions: 7,
                    onChanged:
                        isRunning ? null : (v) => configNotifier.setStepSize(v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${config.stepSize.toInt()}°',
                    style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Direction
          _SettingRow(
            label: 'Direction',
            tooltip:
                'Which way to rotate for measurements. Use West if near Eastern meridian limit',
            colors: colors,
            child: PolarAlignmentSegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('East')),
                ButtonSegment(value: false, label: Text('West')),
              ],
              selected: {config.rotateEast},
              onSelectionChanged: isRunning
                  ? null
                  : (v) => configNotifier.setRotateEast(v.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSettings(
    NightshadeColors colors,
    PolarAlignmentConfig config,
    bool isRunning,
  ) {
    final configNotifier = ref.read(polarAlignmentConfigProvider.notifier);
    final ui = ref.watch(polarAlignmentUiStateProvider);
    final uiNotifier = ref.read(polarAlignmentUiStateProvider.notifier);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: ui.showAdvancedSettings,
        onExpansionChanged: uiNotifier.setShowAdvancedSettings,
        title: Row(
          children: [
            Icon(LucideIcons.settings2, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Advanced',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        children: [
          // Manual rotation toggle
          _SettingRow(
            label: 'Manual Rotation',
            tooltip: 'Enable for star trackers without GoTo capability',
            colors: colors,
            child: NightshadeSwitch(
              value: config.manualRotation,
              onChanged:
                  isRunning ? null : (v) => configNotifier.setManualRotation(v),
            ),
          ),
          const SizedBox(height: 12),

          // Solve timeout
          _SettingRow(
            label: 'Solve Timeout',
            tooltip: 'Maximum time to wait for plate solve',
            colors: colors,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: config.solveTimeout,
                    min: 10,
                    max: 120,
                    divisions: 11,
                    onChanged: isRunning
                        ? null
                        : (v) => configNotifier.setSolveTimeout(v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${config.solveTimeout.toInt()}s',
                    style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Start position
          _SettingRow(
            label: 'Start From',
            tooltip: 'Use current telescope position or slew near pole first',
            colors: colors,
            child: PolarAlignmentSegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Current')),
                ButtonSegment(value: false, label: Text('Pole')),
              ],
              selected: {config.startFromCurrent},
              onSelectionChanged: isRunning
                  ? null
                  : (v) => configNotifier.setStartFromCurrent(v.first),
            ),
          ),
          const SizedBox(height: 12),

          // Auto-complete threshold
          _SettingRow(
            label: 'Auto-Complete',
            tooltip:
                'Automatically finish when error stays below this value for 3 seconds',
            colors: colors,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: config.autoCompleteThreshold,
                    min: 10,
                    max: 120,
                    divisions: 11,
                    onChanged: isRunning
                        ? null
                        : (v) => configNotifier.setAutoCompleteThreshold(v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${config.autoCompleteThreshold.toInt()}"',
                    style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentTips(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TipItem(colors: colors, text: 'Make small adjustments'),
          _TipItem(colors: colors, text: 'Watch the error decrease'),
          _TipItem(colors: colors, text: 'Target < 1 arcmin for best results'),
          _TipItem(colors: colors, text: 'Click Done when satisfied'),
        ],
      ),
    );
  }

  /// Task 4.2: Adjustment magnitude guidance widget
  Widget _buildAdjustmentGuidance(
      NightshadeColors colors, PolarAlignmentError error) {
    // Calculate magnitude categories based on total error in arcseconds
    final totalArcsec = error.totalError;

    // Determine adjustment magnitude
    String magnitudeText;
    String adjustmentHint;
    Color magnitudeColor;
    IconData magnitudeIcon;

    if (totalArcsec < 10) {
      magnitudeText = 'Micro adjustments';
      adjustmentHint = 'Barely touch the knobs';
      magnitudeColor = colors.success;
      magnitudeIcon = LucideIcons.checkCircle;
    } else if (totalArcsec < 30) {
      magnitudeText = '1/8 turn';
      adjustmentHint = 'Very small movements';
      magnitudeColor = colors.success;
      magnitudeIcon = LucideIcons.arrowRight;
    } else if (totalArcsec < 60) {
      magnitudeText = '1/4 turn';
      adjustmentHint = 'Small, careful movements';
      magnitudeColor = colors.info;
      magnitudeIcon = LucideIcons.arrowRight;
    } else if (totalArcsec < 120) {
      magnitudeText = '1/2 turn';
      adjustmentHint = 'Medium adjustments';
      magnitudeColor = colors.warning;
      magnitudeIcon = LucideIcons.alertCircle;
    } else {
      magnitudeText = 'Large adjustments';
      adjustmentHint = 'Significant correction needed';
      magnitudeColor = colors.error;
      magnitudeIcon = LucideIcons.alertTriangle;
    }

    // Direction indicators
    final azDirection = error.azimuthError > 0 ? 'Right' : 'Left';
    final altDirection = error.altitudeError > 0 ? 'Down' : 'Up';
    final azMagnitude = error.azimuthError.abs();
    final altMagnitude = error.altitudeError.abs();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.emphasisSurface(
        magnitudeColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(magnitudeIcon, size: 16, color: magnitudeColor),
              const SizedBox(width: 8),
              Text(
                magnitudeText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: magnitudeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            adjustmentHint,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Azimuth direction
          if (azMagnitude > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    error.azimuthError > 0
                        ? LucideIcons.arrowRight
                        : LucideIcons.arrowLeft,
                    size: 12,
                    color: _getErrorMagnitudeColor(colors, azMagnitude),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Azimuth: $azDirection ${azMagnitude.toStringAsFixed(0)}"',
                    style: TextStyle(
                      fontSize: 11,
                      color: _getErrorMagnitudeColor(colors, azMagnitude),
                    ),
                  ),
                ],
              ),
            ),
          // Altitude direction
          if (altMagnitude > 1)
            Row(
              children: [
                Icon(
                  error.altitudeError > 0
                      ? LucideIcons.arrowDown
                      : LucideIcons.arrowUp,
                  size: 12,
                  color: _getErrorMagnitudeColor(colors, altMagnitude),
                ),
                const SizedBox(width: 6),
                Text(
                  'Altitude: $altDirection ${altMagnitude.toStringAsFixed(0)}"',
                  style: TextStyle(
                    fontSize: 11,
                    color: _getErrorMagnitudeColor(colors, altMagnitude),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getErrorMagnitudeColor(NightshadeColors colors, double arcsec) {
    if (arcsec < 10) return colors.success;
    if (arcsec < 30) return colors.info;
    if (arcsec < 60) return colors.warning;
    return colors.error;
  }

  /// Task 4.6: History panel widget
  ///
  /// Why: uses the streaming history provider (`polarAlignmentHistoryStreamProvider`)
  /// so new alignment runs appear in the panel immediately after the run
  /// completes — previously the panel was on a one-shot Future and stale until
  /// the screen was rebuilt.
  Widget _buildHistoryPanel(NightshadeColors colors) {
    final profileId = ref.watch(activeEquipmentProfileProvider)?.id;
    final historyAsync =
        ref.watch(polarAlignmentHistoryStreamProvider(profileId));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.history, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Alignment History',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No alignment history yet',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: history.take(5).map((entry) {
                  final improvementPercent = entry.initialTotalError > 0
                      ? ((entry.initialTotalError - entry.finalTotalError) /
                              entry.initialTotalError *
                              100)
                          .clamp(0.0, 100.0)
                      : 0.0;

                  final dateStr = _formatDate(entry.completedAt);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          entry.autoCompleted
                              ? LucideIcons.target
                              : LucideIcons.check,
                          size: 14,
                          color: entry.finalTotalError < 60
                              ? colors.success
                              : colors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Final: ${entry.finalTotalError.toStringAsFixed(0)}"',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: NightshadeDecorations.tintedBadge(
                            improvementPercent > 50
                                ? colors.success
                                : colors.info,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${improvementPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: improvementPercent > 50
                                  ? colors.success
                                  : colors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load history: $error',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

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

  Widget _buildMeasuringStatus(
      NightshadeColors colors, PolarAlignmentState state) {
    final point = state.currentPoint;
    final status = state.statusMessage;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main image area
          Expanded(
            flex: 2,
            child: Container(
              key: PolarAlignmentTutorialKeys.imageView,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Stack(
                children: [
                  // Image display
                  if (state.hasImage)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          state.imageData!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Waiting for image...',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Solve coordinates overlay
                  if (state.solvedRa != null && state.solvedDec != null)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.background.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.checkCircle,
                                    size: 12, color: colors.success),
                                const SizedBox(width: 6),
                                Text(
                                  'Plate Solved',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.success,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'RA: ${_formatRA(state.solvedRa!)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'Dec: ${_formatDec(state.solvedDec!)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Progress panel
          SizedBox(
            width: 180,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MeasurementProgressItem(
                    colors: colors,
                    label: 'Point 1',
                    isActive: point == 1,
                    isComplete: point > 1,
                  ),
                  const SizedBox(height: 8),
                  _MeasurementProgressItem(
                    colors: colors,
                    label: 'Point 2',
                    isActive: point == 2,
                    isComplete: point > 2,
                  ),
                  const SizedBox(height: 8),
                  _MeasurementProgressItem(
                    colors: colors,
                    label: 'Point 3',
                    isActive: point == 3,
                    isComplete: point > 3,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Task 4.4: Solve progress indicator with timer
                  if (status.toLowerCase().contains('solv'))
                    _SolveProgressIndicator(colors: colors, status: status)
                  else
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),

                  const Spacer(),
                  // Mount activity indicator
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Capturing Point $point',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRA(double degrees) {
    final hours = degrees / 15.0;
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    final s = (((hours - h) * 60 - m) * 60).toStringAsFixed(1);
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s}s';
  }

  String _formatDec(double degrees) {
    final sign = degrees >= 0 ? '+' : '-';
    final abs = degrees.abs();
    final d = abs.floor();
    final m = ((abs - d) * 60).floor();
    final s = (((abs - d) * 60 - m) * 60).toStringAsFixed(0);
    return '$sign${d.toString().padLeft(2, '0')}° ${m.toString().padLeft(2, '0')}\' $s"';
  }

  Widget _buildAdjustmentInstructions(
    NightshadeColors colors,
    PolarAlignmentState state,
    PolarAlignmentConfig config,
  ) {
    final error = state.currentError;

    // Direction text - use Left/Right/Up/Down as per UX design
    final azDir =
        error != null ? (error.azimuthError > 0 ? 'Right' : 'Left') : '--';
    final altDir =
        error != null ? (error.altitudeError > 0 ? 'Down' : 'Up') : '--';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main image area with bullseye overlay
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Stack(
                children: [
                  // Live image
                  if (state.hasImage)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          state.imageData!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Capturing adjustment image...',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Bullseye overlay
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BullseyeOverlayPainter(
                        colors: colors,
                        azimuthError: error?.azimuthError,
                        altitudeError: error?.altitudeError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Direction panel
          SizedBox(
            width: 200,
            child: Container(
              key: PolarAlignmentTutorialKeys.adjustment,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adjust Mount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Azimuth direction
                  Text(
                    'Azimuth',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (error != null)
                    Text(
                      '$azDir ${error.azimuthError.abs().toStringAsFixed(1)}"',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: error.azimuthError.abs() < 30
                            ? colors.success
                            : error.azimuthError.abs() < 60
                                ? colors.warning
                                : colors.error,
                      ),
                    )
                  else
                    Text(
                      '--',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.textMuted,
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Altitude direction
                  Text(
                    'Altitude',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (error != null)
                    Text(
                      '$altDir ${error.altitudeError.abs().toStringAsFixed(1)}"',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: error.altitudeError.abs() < 30
                            ? colors.success
                            : error.altitudeError.abs() < 60
                                ? colors.warning
                                : colors.error,
                      ),
                    )
                  else
                    Text(
                      '--',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.textMuted,
                      ),
                    ),

                  const SizedBox(height: 24),
                  Divider(color: colors.border),
                  const SizedBox(height: 16),

                  // Total error
                  Text(
                    'Total Error',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (error != null)
                    Text(
                      '${error.totalError.toStringAsFixed(1)}"',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: error.totalError < 30
                            ? colors.success
                            : error.totalError < 60
                                ? colors.warning
                                : colors.error,
                      ),
                    )
                  else
                    Text(
                      '--',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colors.textMuted,
                      ),
                    ),

                  const Spacer(),

                  // Progress toward threshold
                  Text(
                    'Threshold: ${config.autoCompleteThreshold.toStringAsFixed(0)}"',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: error != null
                          ? (1.0 - (error.totalError / 120.0)).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: colors.surfaceAlt,
                      color: error != null
                          ? (error.totalError < 30
                              ? colors.success
                              : error.totalError < 60
                                  ? colors.warning
                                  : colors.error)
                          : colors.textMuted,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Auto-complete indicator
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.target,
                          size: 14,
                          color: error != null &&
                                  error.totalError <
                                      config.autoCompleteThreshold
                              ? colors.success
                              : colors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error != null &&
                                    error.totalError <
                                        config.autoCompleteThreshold
                                ? 'Below threshold!'
                                : 'Adjust to threshold',
                            style: TextStyle(
                              fontSize: 11,
                              color: error != null &&
                                      error.totalError <
                                          config.autoCompleteThreshold
                                  ? colors.success
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Task 4.3: Before/After Summary Card
  Widget _buildCompleteStatus(
      NightshadeColors colors, PolarAlignmentState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.checkCircle,
          size: 64,
          color: colors.success,
        ),
        const SizedBox(height: 16),
        Text(
          'Alignment Complete',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (state.currentError != null)
          Text(
            'Final error: ${state.currentError!.totalError.toStringAsFixed(1)} arcseconds',
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        const SizedBox(height: 24),
        // Before/After summary card
        if (state.initialError != null && state.currentError != null)
          _buildCompletionSummary(colors, state),
      ],
    );
  }

  /// Task 4.3: Completion summary widget showing before/after
  Widget _buildCompletionSummary(
      NightshadeColors colors, PolarAlignmentState state) {
    final initial = state.initialError!;
    final current = state.currentError!;
    final improvementPercent = state.improvementPercent ?? 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentMax = constraints.maxWidth;
        final cardWidth =
            parentMax.isFinite ? (parentMax * 0.92).clamp(280.0, 400.0) : 400.0;

        return Container(
          width: cardWidth,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.trendingDown,
                      size: 18, color: colors.success),
                  const SizedBox(width: 8),
                  Text(
                    'Alignment Summary',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Before/After comparison
              Row(
                children: [
                  // Before
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: NightshadeDecorations.tintedBadge(
                        colors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Before',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colors.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${initial.totalError.toStringAsFixed(0)}"',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Az: ${initial.azimuthError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: 10, color: colors.textMuted),
                          ),
                          Text(
                            'Alt: ${initial.altitudeError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: 10, color: colors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      LucideIcons.arrowRight,
                      size: 20,
                      color: colors.textMuted,
                    ),
                  ),

                  // After
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: NightshadeDecorations.tintedBadge(
                        colors.success,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'After',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colors.success,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${current.totalError.toStringAsFixed(0)}"',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Az: ${current.azimuthError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: 10, color: colors.textMuted),
                          ),
                          Text(
                            'Alt: ${current.altitudeError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: 10, color: colors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Improvement progress bar
              Text(
                'Improvement',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: improvementPercent / 100.0,
                        backgroundColor: colors.surfaceAlt,
                        color: improvementPercent > 75
                            ? colors.success
                            : improvementPercent > 50
                                ? colors.info
                                : colors.warning,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: NightshadeDecorations.tintedBadge(
                      colors.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+${improvementPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorStatus(NightshadeColors colors, PolarAlignmentState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.alertCircle,
          size: 64,
          color: colors.error,
        ),
        const SizedBox(height: 16),
        Text(
          'Error Occurred',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.errorMessage ?? state.statusMessage,
          style: TextStyle(
            fontSize: 13,
            color: colors.error,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRightPanel(
    NightshadeColors colors,
    PolarAlignmentState state,
    PolarAlignmentConfig config,
  ) {
    final errorHistory = ref.watch(polarAlignmentErrorHistoryProvider);
    final isAllSky = ref.watch(polarAlignmentUiStateProvider).mode ==
        PolarAlignmentMode.allSky;

    return Container(
      key: PolarAlignmentTutorialKeys.errorDisplay,
      color: colors.surface,
      child: Column(
        children: [
          // Error visualization
          //
          // All-Sky mode shows the Sharpcap-style target reticle with a live
          // moving marker; TPPA mode keeps the legacy bar/dial visualization.
          Expanded(
            child: isAllSky
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AllSkyTargetReticle(
                        azimuthErrorArcsec:
                            state.currentError?.azimuthError ?? 0.0,
                        altitudeErrorArcsec:
                            state.currentError?.altitudeError ?? 0.0,
                        acceptanceThresholdArcsec: config.autoCompleteThreshold,
                        waitingForFirstFrame:
                            state.phase == PolarAlignPhase.adjusting &&
                                state.currentError == null,
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      _PolarErrorVisualization(
                        colors: colors,
                        error: state.currentError,
                        phase: state.phase,
                        pulseAnimation: _pulseController,
                      ),
                      if (state.phase == PolarAlignPhase.idle)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 24,
                          child: Text(
                            'After you start, this bullseye shows live '
                            'azimuth and altitude error while you adjust the '
                            'mount. Rings mark 30", 60", and 120" error zones.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),

          // Task 4.5: Error trend sparkline chart (only in adjustment phase)
          if (state.phase == PolarAlignPhase.adjusting &&
              errorHistory.length > 2)
            Container(
              height: 100,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.trendingDown,
                          size: 12, color: colors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Error Trend',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ErrorTrendChart(
                      colors: colors,
                      errors: errorHistory,
                      threshold: config.autoCompleteThreshold,
                    ),
                  ),
                ],
              ),
            ),

          // Error values
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: _buildErrorValues(colors, state.currentError),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorValues(
      NightshadeColors colors, PolarAlignmentError? error) {
    if (error == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ErrorValue(colors: colors, label: 'Azimuth', value: '--'),
          _ErrorValue(colors: colors, label: 'Altitude', value: '--'),
          _ErrorValue(
              colors: colors, label: 'Total', value: '--', isPrimary: true),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ErrorValue(
          colors: colors,
          label: 'Azimuth',
          value: '${error.azimuthError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.azimuthError.abs()),
        ),
        _ErrorValue(
          colors: colors,
          label: 'Altitude',
          value: '${error.altitudeError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.altitudeError.abs()),
        ),
        _ErrorValue(
          colors: colors,
          label: 'Total',
          value: '${error.totalError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.totalError),
          isPrimary: true,
        ),
      ],
    );
  }

  Color _getErrorColor(NightshadeColors colors, double error) {
    if (error < 30) return colors.success;
    if (error < 60) return colors.info;
    if (error < 120) return colors.warning;
    return colors.error;
  }

  Widget _buildFooter(
    NightshadeColors colors,
    PolarAlignmentState state,
    bool isRunning,
  ) {
    // Check equipment connection state for disabling Start button
    final cameraConnected = ref.watch(cameraStateProvider
        .select((s) => s.connectionState == DeviceConnectionState.connected));
    final mountConnected = ref.watch(mountStateProvider
        .select((s) => s.connectionState == DeviceConnectionState.connected));
    final equipmentReady = cameraConnected && mountConnected;

    // Build tooltip message for disabled state
    String? disabledReason;
    if (!cameraConnected && !mountConnected) {
      disabledReason = 'Camera and mount not connected';
    } else if (!cameraConnected) {
      disabledReason = 'Camera not connected';
    } else if (!mountConnected) {
      disabledReason = 'Mount not connected';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Status
          Expanded(
            child: Row(
              children: [
                if (isRunning)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    state.statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Action buttons
          if (state.phase == PolarAlignPhase.idle)
            Tooltip(
              message: disabledReason ?? '',
              child: NightshadeButton(
                key: PolarAlignmentTutorialKeys.startBtn,
                label: 'Start Alignment',
                icon: LucideIcons.play,
                variant: ButtonVariant.primary,
                onPressed: equipmentReady ? _startAlignment : null,
              ),
            )
          else if (state.phase == PolarAlignPhase.measuring)
            NightshadeButton(
              label: 'Stop',
              icon: LucideIcons.square,
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: _stopAlignment,
            )
          else if (state.phase == PolarAlignPhase.adjusting)
            Row(
              children: [
                NightshadeButton(
                  label: 'Stop',
                  icon: LucideIcons.square,
                  variant: ButtonVariant.destructive,
                  size: ButtonSize.small,
                  onPressed: _stopAlignment,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Done',
                  icon: LucideIcons.check,
                  variant: ButtonVariant.primary,
                  onPressed: _completeAlignment,
                ),
              ],
            )
          else if (state.phase == PolarAlignPhase.complete ||
              state.phase == PolarAlignPhase.error)
            Row(
              children: [
                NightshadeButton(
                  label: 'Restart',
                  icon: LucideIcons.rotateCcw,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: _resetAlignment,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Done',
                  icon: LucideIcons.check,
                  variant: ButtonVariant.primary,
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/imaging');
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

