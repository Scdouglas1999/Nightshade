import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/settings_keys.dart';
import '../../../widgets/first_light/first_light_flow_dialog.dart';
import 'settings_widgets.dart';

class HelpTutorialsSettings extends ConsumerWidget {
  final bool isMobile;

  const HelpTutorialsSettings(
      {super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final tutorialState = ref.watch(tutorialProvider);
    final notifier = ref.read(tutorialProvider.notifier);

    return SettingsPage(
      key: SettingsTutorialKeys.help,
      title: 'Help & Tutorials',
      description: 'Guided tours and learning resources',
      children: [
        // Onboarding & First-Light IA (C13): this is the single replay hub
        // for the guided first-run flows. Each flow auto-launches at most
        // once on the single startup spine; every one of them is replayable
        // here on demand. "Capture your first light" and "Re-run equipment
        // setup" are new replay entry points (Flow A previously had none).
        SettingsSection(
          title: 'Guided Flows',
          children: [
            SettingRow(
              icon: LucideIcons.sparkles,
              iconColor: colors.primary,
              title: 'First Night Walkthrough',
              subtitle: '7-step guided wizard for your first imaging session — '
                  'connect, polar align, focus, frame, guide, sequence.',
              trailing: NightshadeButton(
                label: 'Start',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                icon: LucideIcons.play,
                // Re-open the wizard via its dedicated route. We restart
                // the in-memory step index first so a user who clicks
                // "Start" gets the welcome step, not their resumed
                // mid-tutorial position — the explicit Start action means
                // "show me from the beginning". (Resume is the auto-open
                // behavior, not what they asked for here.)
                onPressed: () {
                  ref.read(firstNightWizardProvider.notifier).restart();
                  context.go('/tutorial/first-night');
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.aperture,
              iconColor: colors.primary,
              title: 'Capture your first light',
              subtitle:
                  'Run the one-click first-light flow again — short exposure, '
                  'auto-stretch, plate-solve, and label the field. Make sure a '
                  'camera is connected first.',
              trailing: NightshadeButton(
                label: 'Start',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                icon: LucideIcons.play,
                // The first-light flow is camera-driven and self-contained:
                // FirstLightFlowDialog opens over the current screen,
                // resetting its controller on dismissal so a replay starts
                // from a clean intro panel. No route change needed.
                onPressed: () => FirstLightFlowDialog.show(context),
              ),
            ),
            SettingRow(
              icon: LucideIcons.wrench,
              iconColor: colors.primary,
              title: 'Re-run equipment setup',
              subtitle:
                  'Walk back through the equipment onboarding wizard to scan '
                  'for gear, pick devices, and rebuild a profile from scratch.',
              trailing: NightshadeButton(
                label: 'Re-run',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                icon: LucideIcons.refreshCw,
                // Clear the in-progress draft so the spine starts on the
                // welcome step rather than resuming a stale half-finished
                // draft, then route to the onboarding spine. The gate
                // provider (shouldRunEquipmentOnboardingProvider) is not
                // touched — re-running setup with profiles already present
                // is an explicit user action, not an auto-launch, so the
                // gate stays satisfied and won't auto-fire on next launch.
                onPressed: () async {
                  await ref.read(onboardingDraftProvider.notifier).reset();
                  if (!context.mounted) return;
                  context.go('/onboarding');
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.listChecks,
              iconColor: colors.primary,
              title: 'Open setup guide',
              subtitle:
                  'Reopen the progressive first-light setup coach — it tracks '
                  'your remaining steps and links straight to each setting.',
              trailing: NightshadeButton(
                label: 'Open',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                icon: LucideIcons.refreshCw,
                // Reset the coach's persistence row (status -> pending) and
                // invalidate the status provider. FirstLaunchCoachLauncher
                // (mounted at the app-shell level) watches that provider and
                // re-mounts the coach panel immediately — no restart needed.
                // This mirrors the "Re-run onboarding tour" reactive contract.
                onPressed: () async {
                  await ref.read(firstLaunchCoachDaoProvider).reset();
                  if (context.mounted) {
                    ref.invalidate(firstLaunchCoachStatusProvider);
                  }
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.compass,
              iconColor: colors.primary,
              title: 'Re-run onboarding tour',
              subtitle:
                  'Replay the first-launch spotlight tour that highlights '
                  'where Equipment, Sequencer, Scheduler, and Plate Solving '
                  'live in the app.',
              trailing: NightshadeButton(
                label: 'Re-run',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                icon: LucideIcons.refreshCw,
                // Reset the DAO row + in-memory pointer. The first-launch
                // tour overlay is replay-only now (no longer on the startup
                // spine): resetting flips firstLaunchTourStatusProvider back
                // to pending, and OnboardingTourReplayLauncher (mounted at the
                // app-shell level) watches that provider and re-mounts the
                // overlay immediately — no restart needed.
                onPressed: () async {
                  await ref.read(onboardingTourProvider.notifier).reset();
                },
              ),
              isLast: false,
            ),
            SettingRow(
              icon: LucideIcons.archive,
              iconColor: colors.warning,
              title: 'Generate Diagnostic Dump',
              subtitle:
                  'Package logs, settings, profile metadata, and system details for support.',
              trailing: NightshadeButton(
                label: 'Open',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                icon: LucideIcons.archive,
                onPressed: () => context.go('/diagnostics/dump'),
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Tutorial Tours',
          children: [
            // The "Quick Start Tour" (TutorialCategory.firstLight step tour)
            // was removed here: it is superseded by the real, camera-driven
            // first-light flow surfaced as "Capture your first light" in the
            // Guided Flows section above. Keeping both would offer two
            // different things under near-identical names.
            _TutorialRow(
              icon: LucideIcons.boxes,
              title: 'Equipment Setup',
              category: TutorialCategory.equipmentSetup,
              completedSteps: notifier
                  .getCompletedStepsCount(TutorialCategory.equipmentSetup),
              totalSteps:
                  notifier.getTotalStepsCount(TutorialCategory.equipmentSetup),
              isCompleted: notifier
                  .isCategoryCompletedSync(TutorialCategory.equipmentSetup),
              hasProgress:
                  notifier.hasCategoryProgress(TutorialCategory.equipmentSetup),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.equipmentSetup),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.equipmentSetup),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.equipmentSetup),
            ),
            _TutorialRow(
              icon: LucideIcons.compass,
              title: 'Target Planning',
              category: TutorialCategory.targetPlanning,
              completedSteps: notifier
                  .getCompletedStepsCount(TutorialCategory.targetPlanning),
              totalSteps:
                  notifier.getTotalStepsCount(TutorialCategory.targetPlanning),
              isCompleted: notifier
                  .isCategoryCompletedSync(TutorialCategory.targetPlanning),
              hasProgress:
                  notifier.hasCategoryProgress(TutorialCategory.targetPlanning),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.targetPlanning),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.targetPlanning),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.targetPlanning),
            ),
            _TutorialRow(
              icon: LucideIcons.listOrdered,
              title: 'Automated Imaging',
              category: TutorialCategory.automatedImaging,
              completedSteps: notifier
                  .getCompletedStepsCount(TutorialCategory.automatedImaging),
              totalSteps: notifier
                  .getTotalStepsCount(TutorialCategory.automatedImaging),
              isCompleted: notifier
                  .isCategoryCompletedSync(TutorialCategory.automatedImaging),
              hasProgress: notifier
                  .hasCategoryProgress(TutorialCategory.automatedImaging),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.automatedImaging),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.automatedImaging),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.automatedImaging),
            ),
            _TutorialRow(
              icon: LucideIcons.sun,
              title: 'Calibration Frames',
              category: TutorialCategory.calibrationFrames,
              completedSteps: notifier
                  .getCompletedStepsCount(TutorialCategory.calibrationFrames),
              totalSteps: notifier
                  .getTotalStepsCount(TutorialCategory.calibrationFrames),
              isCompleted: notifier
                  .isCategoryCompletedSync(TutorialCategory.calibrationFrames),
              hasProgress: notifier
                  .hasCategoryProgress(TutorialCategory.calibrationFrames),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.calibrationFrames),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.calibrationFrames),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.calibrationFrames),
            ),
            _TutorialRow(
              icon: LucideIcons.barChart3,
              title: 'Advanced Features',
              category: TutorialCategory.advancedFeatures,
              completedSteps: notifier
                  .getCompletedStepsCount(TutorialCategory.advancedFeatures),
              totalSteps: notifier
                  .getTotalStepsCount(TutorialCategory.advancedFeatures),
              isCompleted: notifier
                  .isCategoryCompletedSync(TutorialCategory.advancedFeatures),
              hasProgress: notifier
                  .hasCategoryProgress(TutorialCategory.advancedFeatures),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.advancedFeatures),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.advancedFeatures),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.advancedFeatures),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Reset Progress',
          children: [
            SettingRow(
              icon: LucideIcons.refreshCw,
              iconColor: colors.error,
              title: 'Reset All Progress',
              subtitle: 'Clear all tutorial progress and start fresh',
              trailing: NightshadeButton(
                label: 'Reset',
                variant: ButtonVariant.destructive,
                size: ButtonSize.small,
                onPressed: () => _showResetConfirmation(context, ref),
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Settings',
          children: [
            SettingRow(
              icon: LucideIcons.toggleRight,
              title: 'Enable tutorials',
              subtitle: 'Show tutorial prompts and guided tours',
              trailing: SettingsSwitch(
                value: tutorialState.tutorialsEnabled,
                onChanged: (value) {
                  notifier.setTutorialsEnabled(value);
                },
              ),
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = NightshadeColors.of(ctx);
        return AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: NightshadeDecorations.tintedBadge(
                colors.error,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.alertTriangle,
                  color: colors.error, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Reset Tutorial Progress?',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          'This will clear all tutorial progress and you will see the welcome tour again. This action cannot be undone.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(ctx),
          ),
          NightshadeButton(
            label: 'Reset',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(tutorialProvider.notifier).resetProgress();
            },
          ),
        ],
      );
      },
    );
  }
}

class _TutorialRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final TutorialCategory category;
  final int completedSteps;
  final int totalSteps;
  final bool isCompleted;
  final bool hasProgress;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final bool isLast;

  const _TutorialRow({
    required this.icon,
    required this.title,
    required this.category,
    required this.completedSteps,
    required this.totalSteps,
    required this.isCompleted,
    required this.hasProgress,
    required this.onStart,
    required this.onResume,
    required this.onRestart,
    this.isLast = false,
    });

  String get _statusText {
    if (isCompleted) {
      return 'Completed';
    } else if (hasProgress) {
      return '$completedSteps/$totalSteps steps';
    } else {
      return 'Not started';
    }
  }

  String get _buttonText {
    if (isCompleted) {
      return 'Restart';
    } else if (hasProgress) {
      return 'Resume';
    } else {
      return 'Start';
    }
  }

  VoidCallback get _buttonAction {
    if (isCompleted) {
      return onRestart;
    } else if (hasProgress) {
      return onResume;
    } else {
      return onStart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Semantics(
      label: '$title tutorial, $_statusText',
      button: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom:
                      BorderSide(color: colors.border.withValues(alpha: 0.5)),
                ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: isCompleted
                  ? NightshadeDecorations.tintedBadge(
                      colors.success,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
              child: Icon(
                icon,
                size: 16,
                color: isCompleted ? colors.success : colors.textSecondary,
              ),
            ),
            const SizedBox(width: 14),

            // Title and status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isCompleted)
                        Icon(
                          LucideIcons.checkCircle2,
                          size: 12,
                          color: colors.success,
                        )
                      else if (hasProgress)
                        Icon(
                          LucideIcons.clock,
                          size: 12,
                          color: colors.warning,
                        )
                      else
                        Icon(
                          LucideIcons.circle,
                          size: 12,
                          color: colors.textMuted,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        _statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: isCompleted
                              ? colors.success
                              : hasProgress
                                  ? colors.warning
                                  : colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action button
            NightshadeButton(
              label: _buttonText,
              variant:
                  isCompleted ? ButtonVariant.outline : ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: _buttonAction,
            ),
          ],
        ),
      ),
    );
  }
}
