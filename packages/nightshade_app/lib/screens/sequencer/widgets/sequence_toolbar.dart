import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../../../models/command_action_result.dart';
import '../../../services/sequence_action_service.dart';
import '../../../utils/count_label.dart';
import '../../../utils/exported_file_reveal.dart';
import '../../../utils/sequence_mutator_helper.dart';
import '../../../utils/snackbar_helper.dart';
import 'preflight_validation_dialog.dart';
import 'run_dashboard/run_dashboard_providers.dart';
import 'run_dashboard/sequence_status_visuals.dart';
import 'equipment_status_widget.dart';
import 'flat_wizard_dialog.dart';
import 'mosaic_wizard_dialog.dart';
import 'quick_start_wizard_dialog.dart';
import 'smart_night_dialog.dart';
import 'trigger_configuration_dialog.dart';
import '../import_sequence_dialog.dart';

part 'sequence_toolbar/actions_and_estimate.dart';
part 'sequence_toolbar/playback_controls.dart';
part 'sequence_toolbar/icon_and_status.dart';

class SequenceToolbar extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const SequenceToolbar({super.key, required this.colors});

  @override
  ConsumerState<SequenceToolbar> createState() => _SequenceToolbarState();
}

class _SequenceToolbarState extends ConsumerState<SequenceToolbar> {
  /// Width of the bar's bottom divider. Named because the bar's own height has
  /// to account for it — see the `height:` comment in [build].
  static const double _bottomBorderWidth = 1.0;

  bool _fileActionRunning = false;

  Future<void> _runFileAction(Future<void> Function() action) async {
    if (_fileActionRunning) return;
    setState(() => _fileActionRunning = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _fileActionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
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

    Future<void> runSequenceAction(
      Future<CommandActionResult> Function() action,
    ) async {
      final result = await action();
      if (!context.mounted) return;
      context.showCommandActionResult(result);
    }

    return Container(
      // The phone tier is sized to the touch minimum PLUS the divider it
      // draws, not to the touch minimum flat.
      //
      // `Container` folds `decoration.padding` into the child's padding, and
      // `BoxDecoration.padding` is the border's own dimensions — so the 1 dp
      // bottom border below took a dp out of the action row, not out of the
      // bar. A flat `height: 48` therefore left the row 47 dp, and the
      // overflow menu's IconButton (which correctly asks for a 48 dp tap
      // target) was squeezed to 48.0x47.0: one dp under Android's rule, from
      // a number that looked exactly right at the call site. The tablet and
      // desktop tiers lose the same dp but start far enough above 48 that
      // their rows stay legal, so they keep their established heights.
      height: isPhone
          ? NightshadeTokens.minTouchTarget + _bottomBorderWidth
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
        border: Border(
          bottom: BorderSide(color: colors.border, width: _bottomBorderWidth),
        ),
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

          void openFlatWizard() => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const FlatWizardDialog(),
              );

          // Mosaic planner. This dialog (visual planner + grid/overlap/filter
          // controls + "Create mosaic project") had NO production call site at
          // all — it was reachable only from its own tests, so the suite
          // reported the whole surface as covered while no user could open it.
          // Seeded from the framed target when there is one, so opening it after
          // framing something lands on that object rather than at 0h/0deg.
          void openMosaicWizard() {
            final framedTarget = ref.read(framingProvider).target;
            showDialog<void>(
              context: context,
              builder: (_) => MosaicWizardDialog(
                initialRa: framedTarget?.raHours,
                initialDec: framedTarget?.decDegrees,
              ),
            );
          }

          // Smart Night auto-builder. One-click "Plan Tonight"
          // entry point. Always reachable while the sequencer is idle so
          // a user with a fully-connected rig can go from "I want to
          // image something" to "press Run" in 6 clicks. Funnels through the
          // canonical launcher so this matches every other "Plan Tonight"
          // affordance in the app.
          void openSmartNight() => showSmartNightDialog(context);

          // Triggers live ON exposure nodes. A sequence with none has nowhere
          // to store them, and the old flow let the user build a "abort if
          // guiding RMS > 2"" trigger, press Save, get a success snackbar and
          // keep nothing — the loop below simply had no nodes to write to.
          final exposureNodes =
              sequence?.nodes.values.whereType<ExposureNode>().toList() ??
                  const <ExposureNode>[];

          List<ExposureTriggerConfig> currentExposureTriggers() {
            if (exposureNodes.isEmpty) return const [];
            return exposureNodes.first.triggers
                .map(ExposureTriggerConfig.fromNativeJson)
                .toList(growable: false);
          }

          Future<void> openExposureTriggers() async {
            if (exposureNodes.isEmpty) {
              // Belt and braces: the toolbar button is disabled in this
              // state, but the overflow menu and any future caller must not
              // be able to open a dialog whose Save is a no-op.
              context.showErrorSnackBar(
                'Add an exposure node first — triggers are stored on the '
                'exposure that runs them.',
              );
              return;
            }
            final result = await showDialog<List<ExposureTriggerConfig>>(
              context: context,
              builder: (_) => TriggerConfigurationDialog(
                initialTriggers: currentExposureTriggers(),
                appliesTo: exposureNodes.length == 1
                    ? 'Applies to the exposure node '
                        '"${exposureNodes.single.name}".'
                    : 'Applies to all ${exposureNodes.length} exposure nodes '
                        'in this sequence.',
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
            // the editor state but doesn't write to disk. The toolbar's own
            // file action EXPORTS a .nsq through a picker; it does not
            // persist into the library, so pointing the user at it would be
            // a lie. Auto-save (when on) picks this up on its next tick;
            // otherwise "Save Current" in the Sequences tab is what persists.
            if (context.mounted) {
              // Name the count so "applied" is checkable against what the
              // user expected, not a bare claim of success.
              context.showInfoSnackBar(
                'Exposure triggers applied to '
                '${countLabel(exposureNodes.length, 'exposure node')} — '
                'use "Save Current" in the Sequences tab to persist.',
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
            final authority = ref.read(backendProvider);
            final editorSnapshot = ref.read(currentSequenceProvider);

            bool requireCurrentContext() {
              if (!context.mounted) return false;
              if (identical(ref.read(backendProvider), authority)) return true;
              context.showWarningSnackBar(
                'The imaging host changed while the file dialog was open. '
                'Open the sequence again for the current host.',
              );
              return false;
            }

            bool requireUnchangedEditor() {
              if (ref.read(currentSequenceProvider) == editorSnapshot) {
                return true;
              }
              context.showWarningSnackBar(
                'The sequence editor changed while the file dialog was open. '
                'Open the file again if you still want to replace it.',
              );
              return false;
            }

            try {
              final fileService = ref.read(sequenceFileServiceProvider);
              final imported = await fileService.importSequence();
              if (imported != null) {
                if (!requireCurrentContext() || !requireUnchangedEditor()) {
                  return;
                }
                if (!ref.read(canEditSequenceProvider)) {
                  if (!context.mounted) return;
                  context.showWarningSnackBar(
                    'Stop the active sequence before opening another file.',
                  );
                  return;
                }
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
                  if (!requireCurrentContext() || !requireUnchangedEditor()) {
                    return;
                  }
                  if (!ref.read(canEditSequenceProvider)) {
                    if (!context.mounted) return;
                    context.showWarningSnackBar(
                      'Stop the active sequence before opening another file.',
                    );
                    return;
                  }
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
              if (requireCurrentContext() && context.mounted) {
                context.showErrorSnackBar(
                  'Could not load sequence: ${e.message}',
                  duration: const Duration(seconds: 6),
                );
              }
            } catch (e) {
              if (requireCurrentContext() && context.mounted) {
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
              final savedPath = await fileService.exportSequence(current);
              if (savedPath != null && context.mounted) {
                await revealExportedFile(
                  context,
                  savedPath,
                  subject: 'Nightshade sequence: ${current.name}',
                  desktopMessage: 'Sequence "${current.name}" exported',
                );
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
                operationName: 'Export Sequence File',
                forceLabel: 'Force save anyway',
              );
              if (!forceSave) return;
              if (!context.mounted) return;
              try {
                final savedPath = await fileService.exportSequence(
                  current,
                  forceExport: true,
                );
                if (savedPath != null && context.mounted) {
                  await revealExportedFile(
                    context,
                    savedPath,
                    subject: 'Nightshade sequence: ${current.name}',
                    desktopMessage:
                        'Sequence "${current.name}" exported (forced)',
                  );
                }
              } catch (err) {
                if (context.mounted) {
                  context.showErrorSnackBar(
                    'Failed to export sequence file: $err',
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar(
                  'Failed to export sequence file: $e',
                );
              }
            }
          }

          Future<void> slewToTarget() async {
            if (sequence == null || sequence.targetHeaders.isEmpty) return;
            final targetGroup = ref.read(runDashboardActiveTargetProvider);
            if (targetGroup == null) return;
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
          // tree must respect canEditSequenceProvider. "Export Sequence File"
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
              icon: LucideIcons.sun,
              label: sequence == null
                  ? 'Calibrate Flat Exposures (create or open a sequence first)'
                  : 'Calibrate Flat Exposures$lockedTooltipSuffix',
              onPressed: canEdit && sequence != null ? openFlatWizard : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.grid,
              label: 'Plan Mosaic$lockedTooltipSuffix',
              onPressed: canEdit ? openMosaicWizard : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.sparkles,
              label: 'Plan Tonight$lockedTooltipSuffix',
              onPressed: canEdit ? openSmartNight : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.folderOpen,
              label: 'Open Sequence$lockedTooltipSuffix',
              onPressed: canEdit && !_fileActionRunning
                  ? () => _runFileAction(openSequenceFile)
                  : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.fileInput,
              label: 'Import from NINA / SGP$lockedTooltipSuffix',
              onPressed: canEdit && !_fileActionRunning
                  ? () => _runFileAction(
                        () async {
                          await ImportSequenceFlow.run(context, ref);
                        },
                      )
                  : null,
            ),
            _ToolbarAction(
              icon: LucideIcons.save,
              // This writes a .nsq FILE through the OS chooser; saving into
              // the app's library is the Sequences tab's "Save Current". Two
              // actions both called "Save" was a real ambiguity - the name now
              // says which one this is.
              label: sequence == null
                  ? 'Export Sequence File… (create or open a sequence first)'
                  : 'Export Sequence File…',
              onPressed: sequence != null && !_fileActionRunning
                  ? () => _runFileAction(saveSequenceFile)
                  : null,
            ),
            const _ToolbarAction.divider(),
            _ToolbarAction(
              icon: LucideIcons.compass,
              label: 'Polar Alignment',
              onPressed: () => context.push('/polar-alignment'),
            ),
            _ToolbarAction(
              icon: LucideIcons.bellRing,
              label: exposureNodes.isEmpty
                  ? 'Exposure Triggers (add an exposure node first)'
                  : 'Exposure Triggers$lockedTooltipSuffix',
              onPressed: canEdit && exposureNodes.isNotEmpty
                  ? openExposureTriggers
                  : null,
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
                  // Awaited end to end so the reset's busy/error feedback flows
                  // through the same snackbar path as every other action, and a
                  // stop-failed / cleanup-failed reset surfaces instead of being
                  // fire-and-forgotten.
                  onReset: () => runSequenceAction(actionService.reset),
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
                    final isSimulation = effectiveSimulationMode(
                      settingsAsync.valueOrNull?.useSimulationMode ?? false,
                    );
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
