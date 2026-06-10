import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../session_review/auto_integration_service.dart';
import '../../localization/nightshade_localizations.dart';
import '../../utils/sequence_mutator_helper.dart';
import '../../widgets/animated_tab_bar_view.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/sequencer_keys.dart';
import 'widgets/batch_operations_toolbar.dart';
import 'widgets/delete_node_confirmation.dart';
import 'widgets/sequence_toolbar.dart';
import 'widgets/node_palette.dart';
import 'widgets/snippet_palette.dart';
import 'widgets/sequence_tree.dart';
import 'widgets/node_properties_panel.dart';
import 'widgets/notes_panel.dart';
import 'widgets/sequence_progress_bar.dart';
import 'widgets/session_report_dialog.dart';
import 'widgets/equipment_telemetry_strip.dart';
import 'widgets/mobile_playback_bar.dart';
import 'widgets/target_queue_panel.dart';
import 'tabs/history_tab.dart';
import 'tabs/sequence_library_tab.dart';
import 'tabs/templates_tab.dart';

part 'sequencer_screen_parts/tab_bar.dart';
part 'sequencer_screen_parts/builder_layout.dart';
part 'sequencer_screen_parts/toolbox_panel.dart';
part 'sequencer_screen_parts/node_palette.dart';
part 'sequencer_screen_parts/snippet_palette.dart';
part 'sequencer_screen_parts/collapsible_panel.dart';
part 'sequencer_screen_parts/narrow_layout.dart';
part 'sequencer_screen_parts/mobile_layout.dart';

/// Currently selected sequencer tab
final sequencerTabProvider = StateProvider<int>((ref) => 0);

/// Which panel is currently expanded in the sequencer
/// null = both panels at default sizes (when space permits)
/// 'toolbox' = toolbox expanded, properties collapsed
/// 'properties' = properties expanded, toolbox collapsed
final sequencerExpandedPanelProvider = StateProvider<String?>((ref) => null);

/// Whether the toolbox panel is collapsed (icon-only mode)
final sequencerToolboxCollapsedProvider = StateProvider<bool>((ref) => false);

/// Whether the properties panel is collapsed (icon-only mode)
final sequencerPropertiesCollapsedProvider =
    StateProvider<bool>((ref) => false);

/// Whether the snippet palette is visible in the toolbox panel
final snippetPaletteVisibleProvider = StateProvider<bool>((ref) => false);

// Note: confirm-then-delete now lives in
// `widgets/delete_node_confirmation.dart`. The Delete-key handler below
// routes through that helper so the keyboard path can't drift from the
// tree's trash-icon and right-click "Delete" paths — every
// user-initiated delete must share one policy.

class SequencerScreen extends ConsumerStatefulWidget {
  const SequencerScreen({super.key});

  @override
  ConsumerState<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends ConsumerState<SequencerScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(sequencerTabProvider.notifier).state = _tabController.index;
      }
    });

    // Sync provider -> controller via a listen hook rather than peeking at
    // the provider during build(). The build-time animateTo() worked most
    // of the time but fired under window-resize storms / hot-reload,
    // causing flicker (audit §4.3).
    ref.listenManual<int>(sequencerTabProvider, (prev, next) {
      if (!mounted) return;
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    });

    // Auto-open the end-of-session report dialog (Feature A) when the
    // execution state transitions out of running/paused into one of the
    // terminal states. We snapshot the bound session id BEFORE the state
    // notifier may clear it so a freshly-completed session still resolves.
    ref.listenManual<SequenceExecutionState>(sequenceExecutionStateProvider,
        (prev, next) {
      if (!mounted) return;
      if (prev == null) return;
      final wasActive = prev == SequenceExecutionState.running ||
          prev == SequenceExecutionState.paused;
      final isTerminal = next == SequenceExecutionState.completed ||
          next == SequenceExecutionState.failed;
      // Treat "idle after running" as a stop/abort terminal transition so
      // the report still opens for stopped runs — the executor sets state
      // to idle on Stop/Stopped events.
      final stoppedTerminal = wasActive && next == SequenceExecutionState.idle;
      if (!isTerminal && !stoppedTerminal) return;
      final sessionId = ref.read(sessionStateProvider).dbSessionId;
      if (sessionId == null) return;
      // Snapshot the run id BEFORE the executor clears its state, so
      // the post-session prompt and the notes service can attach the
      // freshly-created note to the run that just ended.
      final runId = ref.read(currentRunIdProvider);
      // Schedule the open after the current frame so the executor finishes
      // its state-update path before we push a new route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SessionReportDialog.show(context, sessionId);
        // Wave 6 Agent 5 — fire the auto-prompt for a journal note
        // when the setting allows it (default true). We use the
        // sequencer screen as the host because (a) it owns the
        // execution-state listener that knows a run just ended and
        // (b) the report dialog opens above this same Navigator so
        // the prompt comes back into focus when the user closes the
        // report. The prompt itself is opt-out — "Don't ask again"
        // sets `notes.prompt_after_run = false`.
        _maybeShowNotesAutoPrompt(runId);
        // "Wake up to a finished image": when the opt-in auto-integrate
        // setting is enabled, kick the post-session integration in the
        // background. Fire-and-forget — the service never throws, and the
        // produced master lands in the Session Review Masters tab.
        _maybeAutoIntegrate(sessionId);
      });
    });

    // Create a default sequence if none exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sequence = ref.read(currentSequenceProvider);
      if (sequence == null) {
        ref.read(currentSequenceProvider.notifier).createSequence();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Wave 6 Agent 5 — open the post-run notes prompt when:
  ///   * The `notes.prompt_after_run` setting is true (or unset; default).
  ///   * The current sequence has a TargetHeaderNode whose name we can
  ///     attach the note to. We pick the first TargetHeader walking the
  ///     tree from the root; for sequences with no target header, we
  ///     skip the prompt rather than guess.
  ///
  /// The body is pre-filled with the run's wall-clock + frame counts so
  /// the operator can edit-and-save in one click or type a paragraph.
  Future<void> _maybeShowNotesAutoPrompt(int? runId) async {
    if (!mounted) return;
    final enabled =
        await ref.read(promptForNotesAfterRunProvider.future).catchError(
              (_) => true,
            );
    if (!enabled) return;
    if (!mounted) return;
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;
    TargetHeaderNode? primaryTarget;
    for (final node in sequence.nodes.values) {
      if (node is TargetHeaderNode) {
        primaryTarget = node;
        break;
      }
    }
    if (primaryTarget == null) return;
    final liveStats = ref.read(liveSequenceStatsProvider);
    final body = liveStats == null
        ? '_How did this run go?_'
        : buildAutoPromptNoteBody(
            sequenceName: sequence.name,
            wallClock: Duration(
                milliseconds: (liveStats.wallClockSecs * 1000).round()),
            framesCaptured: liveStats.framesCaptured,
            framesRejected: liveStats.framesRejected,
            triggerFires: liveStats.triggerFires,
            autofocusRuns: liveStats.autofocusRuns,
            meridianFlips: liveStats.meridianFlips,
          );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => NotesQuickPromptDialog(
        targetId: primaryTarget!.targetName,
        sequenceRunId: runId,
        prefilledBody: body,
        prefilledTitle: 'Run on ${DateTime.now().toLocal()}',
      ),
    );
  }

  /// Opt-in post-session auto-integration ("wake up to a finished image").
  ///
  /// Runs the batch integration / multi-night accumulation for the completed
  /// session in the background when the setting is enabled, then toasts the
  /// result. The service is exception-safe so a failed auto-run is reported,
  /// never thrown.
  Future<void> _maybeAutoIntegrate(int sessionId) async {
    final result = await ref
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);
    if (!result.ran || !mounted) return;
    NightshadeToastHelper.show(
      context: context,
      message: result.message,
      severity: NightshadeAlertSeverity.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;
    // Tab sync runs via ref.listenManual in initState (audit §4.3). The
    // current value is still read for the shortcut bindings below that
    // gate behaviour to the Builder tab.
    final currentTab = ref.watch(sequencerTabProvider);

    return ContextualTourPrompt(
      screenId: 'sequencer',
      tourCategory: TutorialCategory.sequencerTour,
      title: context.l10n.text('sequencerTourTitle'),
      description: context.l10n.text('sequencerTourDescription'),
      durationMinutes: 4,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOut,
        ),
        child: CallbackShortcuts(
          bindings: {
            // Trust-patch §B: undo/redo/delete/duplicate/paste are
            // mutations and MUST no-op while the sequence is running.
            // Cutting Ctrl+Z is the load-bearing change here: a stray
            // Ctrl+Z mid-run used to roll back Dart state while Rust
            // kept executing the old tree (split-brain). Ctrl+C
            // (clipboard copy) and Escape (clear multi-select) are
            // NOT mutations and stay enabled.
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
              if (currentTab != 0) return;
              if (!ref.read(canEditSequenceProvider)) return;
              ref.read(currentSequenceProvider.notifier).undo();
            },
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
              if (currentTab != 0) return;
              if (!ref.read(canEditSequenceProvider)) return;
              ref.read(currentSequenceProvider.notifier).redo();
            },
            const SingleActivator(LogicalKeyboardKey.delete): () {
              if (currentTab != 0) return;
              if (!ref.read(canEditSequenceProvider)) return;
              final multiSelected = ref.read(multiSelectedNodeIdsProvider);
              if (multiSelected.isNotEmpty) {
                ref
                    .read(multiSelectedNodeIdsProvider.notifier)
                    .deleteSelected();
              } else {
                final selectedId = ref.read(selectedNodeIdProvider);
                if (selectedId != null) {
                  // Why: a Delete keystroke on a container with children
                  // would silently nuke the subtree. Route through the
                  // same confirmation helper the tree's trash button uses
                  // so the keyboard path has parity.
                  confirmAndDeleteSequenceNode(
                    context: context,
                    ref: ref,
                    nodeId: selectedId,
                  );
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
              if (currentTab != 0) return;
              if (!ref.read(canEditSequenceProvider)) return;
              final selectedId = ref.read(selectedNodeIdProvider);
              if (selectedId != null) {
                ref
                    .read(currentSequenceProvider.notifier)
                    .duplicateNode(selectedId);
              }
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (currentTab == 0) {
                final multiSelected = ref.read(multiSelectedNodeIdsProvider);
                if (multiSelected.isNotEmpty) {
                  ref.read(multiSelectedNodeIdsProvider.notifier).clear();
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
              // Ctrl+C is a clipboard read — not an edit. Stays enabled
              // during a run so users can copy a node into a snippet
              // even while the executor is busy.
              if (currentTab == 0) {
                final multiSelected = ref.read(multiSelectedNodeIdsProvider);
                if (multiSelected.isNotEmpty) {
                  ref
                      .read(multiSelectedNodeIdsProvider.notifier)
                      .copySelected();
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
              if (currentTab != 0) return;
              if (!ref.read(canEditSequenceProvider)) return;
              final clipboard = ref.read(nodeCopyClipboardProvider);
              if (clipboard != null && clipboard.isNotEmpty) {
                ref
                    .read(multiSelectedNodeIdsProvider.notifier)
                    .pasteFromClipboard();
              }
            },
            const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () {
              _tabController.animateTo(0);
            },
            const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () {
              _tabController.animateTo(1);
            },
            const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () {
              _tabController.animateTo(2);
            },
            const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () {
              _tabController.animateTo(3);
            },
            // Ctrl+T (or Cmd+T on Mac) to toggle snippet palette visibility
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              if (currentTab == 0) {
                final current = ref.read(snippetPaletteVisibleProvider);
                ref.read(snippetPaletteVisibleProvider.notifier).state =
                    !current;
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                // Tab bar
                _SequencerTabBar(
                  colors: colors,
                  controller: _tabController,
                  isRunning: isRunning,
                ),

                // Progress bar (when running)
                if (isRunning)
                  SequenceProgressBar(
                      key: SequencerTutorialKeys.progressBar, colors: colors),

                // Tab content
                Expanded(
                  child: AnimatedTabBarView(
                    controller: _tabController,
                    children: [
                      // Builder tab
                      _BuilderContent(colors: colors),
                      // Templates tab — merged library. Bundled read-only
                      // sample sequences (audit §8.3.5) now live inside this
                      // tab as a "Starters" section above the saved/built-in
                      // templates, so the standalone Samples tab is gone.
                      const TemplatesTab(),
                      // Saved sequence catalog (host DB / remote list-full).
                      const SequenceLibraryTab(),
                      // History tab
                      const HistoryTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
