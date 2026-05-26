import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../models/command_action_result.dart';
import '../../../services/sequence_action_service.dart';
import '../../../utils/sequence_mutator_helper.dart';
import '../../../utils/snackbar_helper.dart';
import 'conversational_builder_dialog.dart';
import 'preflight_validation_dialog.dart';
import 'equipment_status_widget.dart';
import 'quick_start_wizard_dialog.dart';
import 'smart_night_dialog.dart';
import 'trigger_configuration_dialog.dart';
import '../import_sequence_dialog.dart';

class SequenceToolbar extends ConsumerWidget {
  final NightshadeColors colors;

  const SequenceToolbar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final sequence = ref.watch(currentSequenceProvider);
    // Trust-patch §B: every action that *replaces* or *mutates* the
    // sequence must be disabled while the executor owns the tree. Save
    // and "Slew to Target" are NOT edits — they stay enabled even while
    // running so the user can still write a checkpoint or chase the
    // current target.
    final canEdit = ref.watch(canEditSequenceProvider);
    final isTablet = Responsive.isTablet(context);
    final actionService = ref.read(sequenceActionServiceProvider);

    final isIdle = executionState == SequenceExecutionState.idle;
    final isRunning = executionState == SequenceExecutionState.running;
    final isPaused = executionState == SequenceExecutionState.paused;

    Future<void> runSequenceAction(
      Future<CommandActionResult> Function() action,
    ) async {
      final result = await action();
      if (!context.mounted) return;
      context.showCommandActionResult(result);
    }

    return Container(
      height: isTablet ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final notifier = ref.read(currentSequenceProvider.notifier);

          // Build the list of secondary actions once. Each entry knows how
          // to render itself inline (icon button) or as a PopupMenuItem so
          // the overflow path can't drift from the inline path
          // (audit §4.8).
          void openWizard() => showDialog(
                context: context,
                builder: (_) => const QuickStartWizardDialog(),
              );

          // Wave 6 — Smart Night auto-builder. One-click "Plan tonight"
          // entry point. Always reachable while the sequencer is idle so
          // a user with a fully-connected rig can go from "I want to
          // image something" to "press Run" in 6 clicks.
          void openSmartNight() => showDialog(
                context: context,
                builder: (_) => const SmartNightDialog(),
              );

          // Wave 8 — Conversational sequence builder. Free-text → LLM →
          // Sequence. The dialog itself handles the "no provider
          // configured" empty state and the privacy disclosure.
          void openConversationalBuilder() => showDialog(
                context: context,
                builder: (_) => const ConversationalBuilderDialog(),
              );

          List<ExposureTriggerConfig> currentExposureTriggers() {
            final exposureNodes =
                sequence?.nodes.values.whereType<ExposureNode>();
            final exposureNode = exposureNodes == null || exposureNodes.isEmpty
                ? null
                : exposureNodes.first;
            if (exposureNode == null) return const [];
            return exposureNode.triggers
                .map(ExposureTriggerConfig.fromNativeJson)
                .toList(growable: false);
          }

          Future<void> openExposureTriggers() async {
            final result = await showDialog<List<ExposureTriggerConfig>>(
              context: context,
              builder: (_) => TriggerConfigurationDialog(
                initialTriggers: currentExposureTriggers(),
              ),
            );
            if (result == null) return;

            final nativeTriggers =
                result.map((trigger) => trigger.toNativeJson()).toList();
            final current = ref.read(currentSequenceProvider);
            if (current == null) return;
            final notifier = ref.read(currentSequenceProvider.notifier);
            for (final node in current.nodes.values.whereType<ExposureNode>()) {
              notifier.updateNode(node.copyWith(triggers: nativeTriggers));
            }
            // The trigger update is in-memory only — `updateNode` mutates
            // the editor state but doesn't write to disk. The toolbar's
            // own Save action exports to a file via a picker dialog, so
            // we can't silently persist here. Tell the user the truth:
            // applied to the editor, not yet saved. Auto-save (when on)
            // will pick it up on its next tick; otherwise the next Save
            // Sequence press persists it.
            if (context.mounted) {
              context.showInfoSnackBar(
                'Exposure triggers applied — save sequence to persist.',
              );
            }
          }

          Future<void> createNewSequence() async {
            final editor = ref.read(currentSequenceProvider.notifier);
            try {
              editor.createSequence();
            } on UnsavedChangesException catch (e) {
              // The editor has unsaved edits; ask the user before
              // throwing them away to start a new sequence. Matches the
              // Open / Import flows above so all three "clobber"
              // entry-points behave identically (audit §B).
              if (!context.mounted) return;
              final discard = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Discard unsaved changes?'),
                  content: ConstrainedBox(
                    constraints: AdaptiveDialogConstraints.hybrid(
                      ctx,
                      designMaxWidth: 440,
                    ),
                    child: Text(
                        '"${e.currentSequenceName}" has unsaved changes. '
                        'Discard them and start a new sequence?'),
                  ),
                  actions: [
                    NightshadeButton(
                      label: 'Cancel',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    NightshadeButton(
                      label: 'Discard',
                      variant: ButtonVariant.destructive,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              );
              if (discard != true) return;
              editor.createSequence(discardUnsaved: true);
            }
          }

          Future<void> openSequenceFile() async {
            try {
              final fileService = ref.read(sequenceFileServiceProvider);
              final imported = await fileService.importSequence();
              if (imported != null) {
                final editor = ref.read(currentSequenceProvider.notifier);
                try {
                  editor.loadSequence(imported);
                } on UnsavedChangesException catch (e) {
                  // The editor has unsaved edits; ask the user before
                  // clobbering them with the freshly loaded sequence.
                  if (!context.mounted) return;
                  final discard = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Discard unsaved changes?'),
                      content: ConstrainedBox(
                        constraints: AdaptiveDialogConstraints.hybrid(
                          ctx,
                          designMaxWidth: 440,
                        ),
                        child: Text(
                            '"${e.currentSequenceName}" has unsaved changes. '
                            'Open the loaded sequence anyway?'),
                      ),
                      actions: [
                        NightshadeButton(
                          label: 'Cancel',
                          variant: ButtonVariant.ghost,
                          size: ButtonSize.small,
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                        NightshadeButton(
                          label: 'Discard and open',
                          variant: ButtonVariant.primary,
                          size: ButtonSize.small,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  );
                  if (discard != true) return;
                  editor.loadSequence(imported, discardUnsaved: true);
                }
                if (context.mounted) {
                  context.showSuccessSnackBar(
                      'Sequence "${imported.name}" loaded');
                }
              }
            } on SnippetDeserializationException catch (e) {
              // Imported file contained a nodeType the editor does not
              // know about — never silently drop it onto the tree.
              if (context.mounted) {
                context.showErrorSnackBar(
                  'Could not load sequence: ${e.message}',
                  duration: const Duration(seconds: 6),
                );
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar('Failed to load sequence: $e');
              }
            }
          }

          Future<void> saveSequenceFile() async {
            final current = ref.read(currentSequenceProvider);
            if (current == null) {
              if (context.mounted) {
                context.showWarningSnackBar('No sequence to save');
              }
              return;
            }
            final fileService = ref.read(sequenceFileServiceProvider);
            try {
              await fileService.exportSequence(current);
              if (context.mounted) {
                context.showSuccessSnackBar('Sequence "${current.name}" saved');
              }
            } on SequenceValidationFailedException catch (e) {
              // Trust-patch §B: validation errors deserve a structured
              // dialog, not a one-line "Failed to save: ..." snackbar.
              // The user gets the per-issue list with severity icons,
              // category badges, descriptions and resolution hints, plus
              // a "Force Save anyway" escape hatch that re-invokes
              // exportSequence with forceExport: true.
              if (!context.mounted) return;
              final forceSave = await showValidationIssueDialog(
                context,
                issues: e.issues,
                operationName: 'Save Sequence',
                forceLabel: 'Force save anyway',
              );
              if (!forceSave) return;
              if (!context.mounted) return;
              try {
                await fileService.exportSequence(current, forceExport: true);
                if (context.mounted) {
                  context.showSuccessSnackBar(
                      'Sequence "${current.name}" saved (forced)');
                }
              } catch (err) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to save sequence: $err');
                }
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar('Failed to save sequence: $e');
              }
            }
          }

          Future<void> slewToTarget() async {
            if (sequence == null || sequence.targetHeaders.isEmpty) return;
            final targetGroup = sequence.targetHeaders.first;
            try {
              final deviceService = ref.read(deviceServiceProvider);
              await deviceService.slewMountToCoordinates(
                targetGroup.raHours,
                targetGroup.decDegrees,
              );
              if (context.mounted) {
                context
                    .showInfoSnackBar('Slewing to ${targetGroup.targetName}');
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar('Failed to slew: $e');
              }
            }
          }

          // §B: every action below that ends up mutating the sequence
          // tree must respect canEditSequenceProvider. "Save Sequence"
          // and "Slew to Target" are read-only/runtime operations and
          // stay enabled. "Polar Alignment" navigates to another screen
          // and is also not an edit. The disabled-button visual is
          // already wired through _ToolbarIconButton / overflow popup
          // when `onPressed == null`.
          final lockedTooltipSuffix =
              canEdit ? '' : ' (locked while sequence is running)';
          final actions = <_ToolbarAction>[
            const _ToolbarAction.divider(),
            _ToolbarAction(
              icon: LucideIcons.filePlus,
              label: 'New Sequence$lockedTooltipSuffix',
              onPressed: canEdit ? createNewSequence : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.wand2,
              label: 'Quick-Start Wizard$lockedTooltipSuffix',
              onPressed: canEdit ? openWizard : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.sparkles,
              label: 'Plan Tonight (Smart Night)$lockedTooltipSuffix',
              onPressed: canEdit ? openSmartNight : null,
            ),
            // Wave 8 — Conversational AI Builder. Sits next to Smart
            // Night because both are "I want a sequence, fast" entry
            // points; the wand icon distinguishes the LLM-driven path
            // from the deterministic Smart Night wizard.
            _ToolbarAction(
              icon: LucideIcons.wand2,
              label: 'Conversational Builder (AI)$lockedTooltipSuffix',
              onPressed: canEdit ? openConversationalBuilder : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.folderOpen,
              label: 'Open Sequence$lockedTooltipSuffix',
              onPressed: canEdit ? openSequenceFile : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.fileInput,
              label: 'Import from NINA / SGP$lockedTooltipSuffix',
              onPressed:
                  canEdit ? () => ImportSequenceFlow.run(context, ref) : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.save,
              label: 'Save Sequence',
              onPressed: saveSequenceFile,
            ),
            const _ToolbarAction.divider(),
            _ToolbarAction(
              icon: LucideIcons.compass,
              label: 'Polar Alignment',
              onPressed: () => context.push('/polar-alignment'),
            ),
            _ToolbarAction(
              icon: LucideIcons.bellRing,
              label: 'Exposure Triggers$lockedTooltipSuffix',
              onPressed: canEdit ? openExposureTriggers : null,
            ),
            const _ToolbarAction.divider(),
            if (sequence != null && sequence.targetHeaders.isNotEmpty)
              _ToolbarAction(
                icon: LucideIcons.navigation,
                label: 'Slew to Target',
                onPressed: slewToTarget,
              ),
            _ToolbarAction(
              icon: LucideIcons.undo2,
              label: 'Undo (Ctrl+Z)$lockedTooltipSuffix',
              onPressed: (canEdit && notifier.canUndo) ? notifier.undo : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.redo2,
              label: 'Redo (Ctrl+Y)$lockedTooltipSuffix',
              onPressed: (canEdit && notifier.canRedo) ? notifier.redo : null,
            ),
          ];

          // §4.8: single overflow threshold. Below it, everything that
          // isn't the playback controls / time estimate / status badge
          // funnels into a single overflow menu so nothing disappears.
          final isCompact =
              constraints.maxWidth < BreakpointTokens.breakpointDesktop;

          return Row(
            children: [
              _PlaybackControls(
                colors: colors,
                isIdle: isIdle,
                isRunning: isRunning,
                isPaused: isPaused,
                executionState: executionState,
                onStart: () {
                  showDialog(
                    context: context,
                    builder: (context) => PreFlightValidationDialog(
                      onStartSequence: () {
                        runSequenceAction(actionService.start);
                      },
                    ),
                  );
                },
                onPause: () => runSequenceAction(actionService.pause),
                onResume: () => runSequenceAction(actionService.resume),
                onStop: () => runSequenceAction(actionService.stop),
                onSkip: () => runSequenceAction(actionService.skip),
                onReset: actionService.reset,
              ),
              if (!isCompact) ...[
                for (final a in actions) ...[
                  if (a.isDivider) ...[
                    const SizedBox(width: 24),
                    _Divider(colors: colors),
                    const SizedBox(width: 24),
                  ] else ...[
                    _ToolbarIconButton(
                      icon: a.icon!,
                      tooltip: a.label!,
                      colors: colors,
                      onPressed: a.onPressed,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ] else ...[
                const SizedBox(width: 12),
                _ToolbarOverflowMenu(colors: colors, actions: actions),
              ],
              const Spacer(),
              if (sequence != null) ...[
                _SequenceTimeEstimate(colors: colors, sequence: sequence),
                const SizedBox(width: 16),
              ],
              if (!isCompact)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: EquipmentStatusWidget(colors: colors),
                ),
              if (!isCompact)
                Consumer(
                  builder: (context, ref, child) {
                    final settingsAsync = ref.watch(appSettingsProvider);
                    final isSimulation =
                        settingsAsync.valueOrNull?.useSimulationMode ?? false;
                    if (!isSimulation) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: NightshadeDecorations.kpiBadge(
                          colors.warning,
                          borderRadius: BorderRadius.circular(4),
                          shape: BoxShape.rectangle,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.testTube,
                                size: 14, color: colors.warning),
                            const SizedBox(width: 6),
                            Text(
                              'SIMULATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.warning,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              _StatusBadge(
                colors: colors,
                executionState: executionState,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A single toolbar action. `isDivider == true` represents a visual
/// separator between groups (inline) or the start of a new section in
/// the overflow menu. Keeping both renderings driven by the same data
/// is what audit §4.8 asks for so a hidden button never silently
/// disappears.
class _ToolbarAction {
  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isDivider;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : isDivider = false;

  const _ToolbarAction.divider()
      : icon = null,
        label = null,
        onPressed = null,
        isDivider = true;
}

/// Single overflow popup that subsumes every secondary action below the
/// compact breakpoint. PopupMenuItems are disabled-but-visible when an
/// action's `onPressed` is null, matching inline behaviour (audit §4.8).
class _ToolbarOverflowMenu extends StatelessWidget {
  final NightshadeColors colors;
  final List<_ToolbarAction> actions;

  const _ToolbarOverflowMenu({required this.colors, required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      icon: Icon(
        LucideIcons.moreHorizontal,
        size: 18,
        color: colors.textSecondary,
      ),
      onSelected: (index) {
        final action = actions[index];
        action.onPressed?.call();
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<int>>[];
        for (var i = 0; i < actions.length; i++) {
          final a = actions[i];
          if (a.isDivider) {
            if (items.isNotEmpty) {
              items.add(const PopupMenuDivider());
            }
            continue;
          }
          items.add(
            PopupMenuItem<int>(
              value: i,
              enabled: a.onPressed != null,
              child: Row(
                children: [
                  Icon(
                    a.icon,
                    size: 16,
                    color: a.onPressed == null
                        ? colors.textMuted
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    a.label!,
                    style: TextStyle(
                      fontSize: 13,
                      color: a.onPressed == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return items;
      },
    );
  }
}

/// Displays both pure integration time and overhead-aware total estimate
class _SequenceTimeEstimate extends StatelessWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SequenceTimeEstimate({
    required this.colors,
    required this.sequence,
  });

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final estimate = sequence.estimateWithOverhead();

    return Tooltip(
      message: estimate.overheadSecs > 0
          ? 'Integration: ${_formatDuration(estimate.estimatedSecs)}\n'
              'Overhead: ${_formatDuration(estimate.overheadSecs)} '
              '(slews, AF, dithers, downloads, etc.)\n'
              'Estimated total: ${_formatDuration(estimate.totalEstimatedSecs)}'
          : 'Integration time: ${_formatDuration(estimate.estimatedSecs)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.camera, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              '${sequence.totalExposures} frames',
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              _formatDuration(estimate.estimatedSecs),
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (estimate.overheadSecs > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 16,
                color: colors.border,
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
              const SizedBox(width: 4),
              Text(
                '~${_formatDuration(estimate.totalEstimatedSecs)}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                  fontStyle: FontStyle.italic,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final NightshadeColors colors;
  final bool isIdle;
  final bool isRunning;
  final bool isPaused;
  final SequenceExecutionState executionState;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onSkip;
  final VoidCallback onReset;

  const _PlaybackControls({
    required this.colors,
    required this.isIdle,
    required this.isRunning,
    required this.isPaused,
    required this.executionState,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSkip,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // Reset is enabled when sequence is idle, completed, or failed (not running/paused)
    final canReset = executionState == SequenceExecutionState.idle ||
        executionState == SequenceExecutionState.completed ||
        executionState == SequenceExecutionState.failed;

    return Row(
      children: [
        // Play/Pause button
        if (isIdle || isPaused)
          _PlayButton(
            colors: colors,
            onPressed: isIdle ? onStart : onResume,
            label: isIdle ? 'Start' : 'Resume',
          )
        else
          _PauseButton(colors: colors, onPressed: onPause),

        const SizedBox(width: 8),

        // Stop button
        _ControlButton(
          icon: LucideIcons.square,
          tooltip: 'Stop',
          colors: colors,
          onPressed: (isRunning || isPaused) ? onStop : null,
        ),

        const SizedBox(width: 8),

        // Skip button
        _ControlButton(
          icon: LucideIcons.skipForward,
          tooltip: 'Skip to Next',
          colors: colors,
          onPressed: isRunning ? onSkip : null,
        ),

        const SizedBox(width: 8),

        // Reset button - resets execution state without modifying sequence config
        _ControlButton(
          icon: LucideIcons.rotateCcw,
          tooltip: 'Reset Sequence',
          colors: colors,
          onPressed: canReset ? onReset : null,
        ),
      ],
    );
  }
}

class _PlayButton extends StatefulWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;
  final String label;

  const _PlayButton({
    required this.colors,
    required this.onPressed,
    required this.label,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: NightshadeDecorations.filledButton(
            widget.colors.success,
            isHovered: _isHovered,
            isDisabled: false,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.play,
                size: 16,
                color: onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseButton extends StatefulWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _PauseButton({
    required this.colors,
    required this.onPressed,
  });

  @override
  State<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends State<_PauseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.warning.withValues(alpha: 0.2)
                : widget.colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.colors.warning.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.pause,
                size: 16,
                color: widget.colors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                'Pause',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _isHovered && !isDisabled
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: isDisabled
                  ? widget.colors.textMuted
                  : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isHovered && !isDisabled
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: isDisabled
                  ? widget.colors.textMuted
                  : _isHovered
                      ? widget.colors.textPrimary
                      : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final NightshadeColors colors;

  const _Divider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: colors.border,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState executionState;

  const _StatusBadge({
    required this.colors,
    required this.executionState,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String label;
    IconData icon;

    switch (executionState) {
      case SequenceExecutionState.idle:
        badgeColor = colors.textMuted;
        label = 'Idle';
        icon = LucideIcons.circleOff;
        break;
      case SequenceExecutionState.running:
        badgeColor = colors.success;
        label = 'Running';
        icon = LucideIcons.activity;
        break;
      case SequenceExecutionState.paused:
        badgeColor = colors.warning;
        label = 'Paused';
        icon = LucideIcons.pauseCircle;
        break;
      case SequenceExecutionState.stopping:
        badgeColor = colors.warning;
        label = 'Stopping';
        icon = LucideIcons.loader;
        break;
      case SequenceExecutionState.completed:
        badgeColor = colors.info;
        label = 'Completed';
        icon = LucideIcons.checkCircle;
        break;
      case SequenceExecutionState.failed:
        badgeColor = colors.error;
        label = 'Failed';
        icon = LucideIcons.xCircle;
        break;
      case SequenceExecutionState.recovering:
        // Wave 4 — Recovery is a distinct visible state; toolbar reads
        // "Recovering" with the loop-arrow icon so the operator can see
        // at a glance that the sequence is mid-recovery and not just
        // running normally.
        badgeColor = colors.error;
        label = 'Recovering';
        icon = LucideIcons.rotateCw;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: NightshadeDecorations.emphasisSurface(
        badgeColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (executionState == SequenceExecutionState.running)
            StatusDot(color: badgeColor)
          else
            Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
