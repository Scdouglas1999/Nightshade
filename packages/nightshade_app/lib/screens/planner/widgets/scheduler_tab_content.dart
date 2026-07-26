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
  Future<void> _configSaveTail = Future<void>.value();
  bool _configSaveErrorVisible = false;
  bool _schedulerActionBusy = false;
  int _schedulerActionGeneration = 0;
  int _remotePollTicks = 0;
  Object? _configAuthority;
  SchedulerConfig? _confirmedConfig;
  SchedulerConfig? _requestedConfig;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _editingTargetId = 0; // 0 means no editor open

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        // A command admitted for the previous host must not keep the
        // replacement host's controls disabled or surface its eventual error.
        _schedulerActionGeneration++;
        _configSaveErrorVisible = false;
        if (mounted && _schedulerActionBusy) {
          setState(() => _schedulerActionBusy = false);
        }
      },
    );
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _remotePollTicks++;
      if (_remotePollTicks % 3 == 0 &&
          ref.read(backendProvider) is NetworkBackend) {
        ref.invalidate(schedulerRemoteSnapshotProvider);
      }
      setState(() {});
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
    _backendSubscription?.close();
    _schedulerActionGeneration++;
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onStart() async {
    await _runSchedulerAction('start');
  }

  Future<void> _onPause() async {
    await _runSchedulerAction('pause');
  }

  Future<void> _onResume() async {
    await _runSchedulerAction('resume');
  }

  Future<void> _onStop() async {
    await _runSchedulerAction('stop');
  }

  Future<void> _onForceReeval() async {
    await _runSchedulerAction('evaluate');
  }

  Future<void> _runSchedulerAction(String action) async {
    if (_schedulerActionBusy) return;
    final backend = ref.read(backendProvider);
    final generation = ++_schedulerActionGeneration;
    setState(() => _schedulerActionBusy = true);
    try {
      if (backend is NetworkBackend) {
        await backend.controlScheduler(action);
      } else {
        // Pause and Stop must remain available for an already-running engine
        // even if an unrelated settings refresh is failing. Operations that
        // evaluate/dispatch wait for the cold-start authority gate.
        final engine = switch (action) {
          'pause' || 'stop' => ref.read(schedulerEngineProvider),
          _ => await ref.read(schedulerEngineReadyProvider.future),
        };
        switch (action) {
          case 'start':
            await engine.start();
          case 'pause':
            await engine.pause();
          case 'resume':
            await engine.resume();
          case 'stop':
            await engine.stop();
          case 'evaluate':
            await engine.evaluateNow(reason: 'manual force re-evaluation');
        }
      }
      if (_isCurrentSchedulerAction(backend, generation)) {
        ref.invalidate(schedulerRemoteSnapshotProvider);
        ref.invalidate(schedulerPreviewDecisionProvider);
      }
    } catch (error) {
      if (!mounted) return;
      if (generation == _schedulerActionGeneration &&
          identical(ref.read(backendProvider), backend)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scheduler action failed: $error')),
        );
      }
    } finally {
      if (_isCurrentSchedulerAction(backend, generation)) {
        setState(() => _schedulerActionBusy = false);
      }
    }
  }

  bool _isCurrentSchedulerAction(
    NightshadeBackend backend,
    int generation,
  ) {
    return mounted &&
        generation == _schedulerActionGeneration &&
        identical(ref.read(backendProvider), backend);
  }

  void _onWeightsChanged(SchedulerWeights weights) {
    _applySchedulerConfig(_baseConfig.copyWith(weights: weights));
  }

  void _onMinAltitudeChanged(double minAlt) {
    _applySchedulerConfig(
      _baseConfig.copyWith(minAltitudeDegrees: minAlt),
    );
  }

  void _onHysteresisChanged(double ratio) {
    _applySchedulerConfig(_baseConfig.copyWith(hysteresisRatio: ratio));
  }

  SchedulerConfig get _baseConfig =>
      _requestedConfig ?? _confirmedConfig ?? SchedulerConfig.defaults;

  void _applySchedulerConfig(SchedulerConfig config) {
    final backend = ref.read(backendProvider);
    final localStore = backend is NetworkBackend
        ? null
        : ref.read(schedulerConfigStoreProvider);
    final localEngine =
        backend is NetworkBackend ? null : ref.read(schedulerEngineProvider);
    setState(() => _requestedConfig = config);

    // Local changes are reflected immediately while their durable writes are
    // serialized. Remote changes remain optimistic in this widget until the
    // host confirms the same full config.
    if (backend is! NetworkBackend) {
      ref.read(schedulerConfigUserDirtyProvider.notifier).state = true;
      localEngine!.updateConfig(config);
    }

    _configSaveTail = _configSaveTail.then((_) async {
      try {
        SchedulerConfig confirmed;
        if (backend is NetworkBackend) {
          final response = await backend.updateSchedulerConfig(
            config.toStorageJson().cast<String, dynamic>(),
          );
          confirmed = SchedulerRemoteSnapshot.fromJson(response).config;
        } else {
          await localStore!.save(config);
          confirmed = config;
        }
        if (!mounted || !identical(ref.read(backendProvider), backend)) return;
        setState(() {
          _confirmedConfig = confirmed;
          if (_requestedConfig == config) _requestedConfig = null;
        });
        if (backend is NetworkBackend) {
          ref.invalidate(schedulerRemoteSnapshotProvider);
        }
        _configSaveErrorVisible = false;
      } catch (error) {
        if (mounted && identical(ref.read(backendProvider), backend)) {
          if (_requestedConfig == config) {
            final rollback = _confirmedConfig ?? SchedulerConfig.defaults;
            if (backend is! NetworkBackend) {
              localEngine!.updateConfig(rollback);
            }
            setState(() => _requestedConfig = null);
          }
          if (backend is NetworkBackend) {
            ref.invalidate(schedulerRemoteSnapshotProvider);
          }
        }
        if (mounted &&
            identical(ref.read(backendProvider), backend) &&
            !_configSaveErrorVisible) {
          _configSaveErrorVisible = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save scheduler settings: $error'),
            ),
          );
        }
      }
    });
  }

  void _openEditor(int targetId) {
    setState(() => _editingTargetId = targetId);
  }

  void _closeEditor() {
    setState(() => _editingTargetId = 0);
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    late final SchedulerStatus status;
    late final SchedulerDecision? decision;
    late final SchedulerConfig authoritativeConfig;

    if (backend is NetworkBackend) {
      final remoteAsync = ref.watch(schedulerRemoteSnapshotProvider);
      final remote = remoteAsync.valueOrNull;
      if (remote == null) {
        return remoteAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load scheduler state: $error'),
                const SizedBox(height: NightshadeTokens.spaceMd),
                NightshadeButton(
                  label: 'Retry',
                  icon: LucideIcons.refreshCw,
                  onPressed: () =>
                      ref.invalidate(schedulerRemoteSnapshotProvider),
                ),
              ],
            ),
          ),
          data: (_) => const SizedBox.shrink(),
        );
      }
      status = remote.status;
      decision = remote.decision;
      authoritativeConfig = remote.config;
    } else {
      final readyAsync = ref.watch(schedulerEngineReadyProvider);
      final readyEngine = readyAsync.valueOrNull;
      if (readyEngine == null) {
        return readyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load scheduler configuration: $error'),
                const SizedBox(height: NightshadeTokens.spaceMd),
                NightshadeButton(
                  label: 'Retry',
                  icon: LucideIcons.refreshCw,
                  onPressed: () {
                    ref.invalidate(appSettingsProvider);
                    ref.invalidate(schedulerPersistedConfigProvider);
                    ref.invalidate(schedulerEngineReadyProvider);
                  },
                ),
              ],
            ),
          ),
          data: (_) => const SizedBox.shrink(),
        );
      }
      status = ref.watch(schedulerStatusProvider);
      final liveDecision = ref.watch(currentSchedulerDecisionProvider);
      final previewDecision = ref.watch(schedulerPreviewDecisionProvider);
      decision = status.state == SchedulerState.idle
          ? previewDecision.valueOrNull ?? liveDecision
          : liveDecision ?? previewDecision.valueOrNull;
      authoritativeConfig = readyEngine.config;
      // Mount local data-change listeners only on the process that owns the
      // scheduler. A remote client must never spin up a second autopilot.
      ref.watch(schedulerAutoReevalProvider);
    }

    if (!identical(_configAuthority, backend)) {
      _configAuthority = backend;
      _confirmedConfig = authoritativeConfig;
      _requestedConfig = null;
      _configSaveTail = Future<void>.value();
    } else if (_requestedConfig == null) {
      _confirmedConfig = authoritativeConfig;
    }
    final config = _requestedConfig ?? authoritativeConfig;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        if (isMobile) {
          return _buildMobile(context, status, decision, config);
        }
        return _buildDesktop(context, status, decision, config);
      },
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    SchedulerStatus status,
    SchedulerDecision? decision,
    SchedulerConfig config,
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
                        config: config,
                        controlsBusy: _schedulerActionBusy,
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
    SchedulerConfig config,
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
                config: config,
                controlsBusy: _schedulerActionBusy,
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
