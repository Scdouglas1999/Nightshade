import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class HelpTutorialsSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const HelpTutorialsSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutorialState = ref.watch(tutorialProvider);
    final notifier = ref.read(tutorialProvider.notifier);

    return SettingsPage(
      key: SettingsTutorialKeys.help,
      title: 'Help & Tutorials',
      description: 'Guided tours and learning resources',
      colors: colors,
      children: [
        SettingsSection(
          title: 'First-Night Walkthrough',
          colors: colors,
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
              colors: colors,
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
                // Reset the DAO row + in-memory pointer; the launcher in
                // app.dart watches firstLaunchTourStatusProvider and will
                // re-mount the overlay as soon as the status flips back
                // to pending. No route change needed — the overlay sits
                // above the current screen.
                onPressed: () async {
                  await ref.read(onboardingTourProvider.notifier).reset();
                },
              ),
              isLast: false,
              colors: colors,
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
              colors: colors,
            ),
          ],
        ),
        SettingsSection(
          title: 'Tutorial Tours',
          colors: colors,
          children: [
            _TutorialRow(
              icon: LucideIcons.sparkles,
              title: 'Quick Start Tour',
              category: TutorialCategory.firstLight,
              completedSteps:
                  notifier.getCompletedStepsCount(TutorialCategory.firstLight),
              totalSteps:
                  notifier.getTotalStepsCount(TutorialCategory.firstLight),
              isCompleted:
                  notifier.isCategoryCompletedSync(TutorialCategory.firstLight),
              hasProgress:
                  notifier.hasCategoryProgress(TutorialCategory.firstLight),
              onStart: () =>
                  notifier.startTutorial(TutorialCategory.firstLight),
              onResume: () =>
                  notifier.resumeTutorial(TutorialCategory.firstLight),
              onRestart: () =>
                  notifier.restartTutorial(TutorialCategory.firstLight),
              colors: colors,
            ),
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
              colors: colors,
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
              colors: colors,
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
              colors: colors,
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
              colors: colors,
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
              colors: colors,
            ),
          ],
        ),
        SettingsSection(
          title: 'Reset Progress',
          colors: colors,
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
              colors: colors,
            ),
          ],
        ),
        SettingsSection(
          title: 'Settings',
          colors: colors,
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
                colors: colors,
              ),
              isLast: true,
              colors: colors,
            ),
          ],
        ),
      ],
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
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
      ),
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
  final NightshadeColors colors;

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
    required this.colors,
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
              decoration: BoxDecoration(
                color: isCompleted
                    ? colors.success.withValues(alpha: 0.1)
                    : colors.surfaceAlt,
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
