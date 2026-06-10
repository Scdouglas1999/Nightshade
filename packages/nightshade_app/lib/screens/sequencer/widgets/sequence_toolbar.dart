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

part 'sequence_toolbar/actions_and_estimate.dart';
part 'sequence_toolbar/playback_controls.dart';
part 'sequence_toolbar/icon_and_status.dart';

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
    // Phone is a device-class fact (short side < 600), so a phone in landscape
    // — where the ~430 px height is at a premium — still takes the compact
    // chrome instead of the desktop 64 px bar. isTablet keeps the medium size.
    final isPhone = Responsive.isPhone(context);
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
      height: isPhone
          ? 48
          : isTablet
              ? 56
              : 64,
      padding: EdgeInsets.symmetric(
          horizontal: isPhone
              ? 8
              : isTablet
                  ? 12
                  : 20),
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
                    child:
                        Text('"${e.currentSequenceName}" has unsaved changes. '
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

          // Phone tier: the dedicated MobilePlaybackBar already owns the
          // play/stop/skip controls AND the time estimate, so rendering them
          // again here just overflows the row. On phone we collapse the
          // toolbar to the file/edit overflow menu + status badge only.
          //
          // Detect "phone" by the device's SHORTER side (not this row's
          // width) so a phone held in landscape — where this strip is wide
          // but the mobile builder is in use below it — still collapses.
          final mq = MediaQuery.sizeOf(context);
          final shortSide = mq.width < mq.height ? mq.width : mq.height;
          final isPhone = shortSide < BreakpointTokens.breakpointPhone;

          return Row(
            children: [
              if (!isPhone)
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
              if (sequence != null && !isPhone) ...[
                // The estimate box is given a bounded width so it can never
                // grow into — and paint over — the equipment-status icons and
                // the run-status badge to its right. `Flexible` lets it shrink
                // when the row is crowded; the box itself ellipsises its own
                // text (see `_SequenceTimeEstimate`) instead of overflowing.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _SequenceTimeEstimate(
                          colors: colors, sequence: sequence),
                    ),
                  ),
                ),
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
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
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
                                fontSize: NightshadeTypography.fontSize11,
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
