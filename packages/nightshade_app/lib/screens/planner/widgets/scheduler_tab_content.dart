import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../scheduler/widgets/integration_goals_editor.dart';
import '../../scheduler/widgets/target_constraints_editor.dart';
import '../../scheduler/widgets/target_score_row.dart';

/// Body of the RoboTarget-class dynamic scheduler — hoisted out of the
/// former standalone Scheduler screen when the Scheduler became a tab under
/// Plan Tonight (§UX consolidation). The `/planner?tab=scheduler` tab mounts
/// this widget; the legacy `/scheduler` route now redirects here.
///
/// Layout (desktop):
///   left  : current decision panel (Start/Pause/Stop, target name,
///           reasoning bullet list, countdown to next eval, weights).
///   right : scrollable target-queue table.
///   bottom (modal): per-target editor opened by tapping a row, mounts
///           the integration-goals + constraints editors.
part 'scheduler_tab_content/decision_panel.dart';
part 'scheduler_tab_content/config_expansion.dart';
part 'scheduler_tab_content/queue_table.dart';
part 'scheduler_tab_content/target_editor_overlay.dart';
part 'scheduler_tab_content/empty_state.dart';

class SchedulerTabContent extends ConsumerStatefulWidget {
  const SchedulerTabContent({super.key});

  @override
  ConsumerState<SchedulerTabContent> createState() =>
      _SchedulerTabContentState();
}

class _SchedulerTabContentState extends ConsumerState<SchedulerTabContent>
    with WidgetsBindingObserver {
  // Drives the countdown text to next-evaluation; rebuilds once per second
  // when running. Suspended when the app is backgrounded so a hidden
  // scheduler tab doesn't repaint every second (§4.33).
  Timer? _countdownTimer;
  int _editingTargetId = 0; // 0 means no editor open

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_countdownTimer == null || !_countdownTimer!.isActive) {
        _startCountdownTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onStart() async {
    await ref.read(schedulerEngineProvider).start();
  }

  Future<void> _onPause() async {
    await ref.read(schedulerEngineProvider).pause();
  }

  Future<void> _onResume() async {
    await ref.read(schedulerEngineProvider).resume();
  }

  Future<void> _onStop() async {
    await ref.read(schedulerEngineProvider).stop();
  }

  Future<void> _onForceReeval() async {
    await ref
        .read(schedulerEngineProvider)
        .evaluateNow(reason: 'manual force re-evaluation');
  }

  void _onWeightsChanged(SchedulerWeights weights) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(weights: weights));
  }

  void _onMinAltitudeChanged(double minAlt) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(minAltitudeDegrees: minAlt));
  }

  void _onHysteresisChanged(double ratio) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(hysteresisRatio: ratio));
  }

  void _openEditor(int targetId) {
    setState(() => _editingTargetId = targetId);
  }

  void _closeEditor() {
    setState(() => _editingTargetId = 0);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(schedulerStatusProvider);
    final decision = ref.watch(currentSchedulerDecisionProvider);
    final engine = ref.watch(schedulerEngineProvider);
    // Mount the auto-reevaluation listeners for the duration the screen is
    // alive. The provider is side-effect-only; we ignore its return value.
    ref.watch(schedulerAutoReevalProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        if (isMobile) {
          return _buildMobile(context, status, decision, engine);
        }
        return _buildDesktop(context, status, decision, engine);
      },
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    SchedulerStatus status,
    SchedulerDecision? decision,
    SchedulerEngine engine,
  ) {
    return Stack(
      children: [
        Padding(
          padding: NightshadeTokens.screenPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = clampPanelWidth(
                constraints.maxWidth,
                fraction: 0.28,
                min: 280,
                max: 380,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: panelWidth,
                    child: SingleChildScrollView(
                      child: _DecisionPanel(
                        status: status,
                        decision: decision,
                        config: engine.config,
                        onStart: _onStart,
                        onPause: _onPause,
                        onResume: _onResume,
                        onStop: _onStop,
                        onForceReeval: _onForceReeval,
                        onWeightsChanged: _onWeightsChanged,
                        onMinAltitudeChanged: _onMinAltitudeChanged,
                        onHysteresisChanged: _onHysteresisChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceLg),
                  Expanded(
                    child: _QueueTable(
                      decision: decision,
                      currentTargetId: status.currentTargetId,
                      onRowTap: _openEditor,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_editingTargetId != 0)
          _TargetEditorOverlay(
            targetId: _editingTargetId,
            decision: decision,
            onClose: _closeEditor,
          ),
      ],
    );
  }

  Widget _buildMobile(
    BuildContext context,
    SchedulerStatus status,
    SchedulerDecision? decision,
    SchedulerEngine engine,
  ) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: NightshadeTokens.screenPaddingCompact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DecisionPanel(
                status: status,
                decision: decision,
                config: engine.config,
                onStart: _onStart,
                onPause: _onPause,
                onResume: _onResume,
                onStop: _onStop,
                onForceReeval: _onForceReeval,
                onWeightsChanged: _onWeightsChanged,
                onMinAltitudeChanged: _onMinAltitudeChanged,
                onHysteresisChanged: _onHysteresisChanged,
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              _QueueTable(
                decision: decision,
                currentTargetId: status.currentTargetId,
                onRowTap: _openEditor,
              ),
            ],
          ),
        ),
        if (_editingTargetId != 0)
          _TargetEditorOverlay(
            targetId: _editingTargetId,
            decision: decision,
            onClose: _closeEditor,
          ),
      ],
    );
  }
}
