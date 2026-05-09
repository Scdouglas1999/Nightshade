import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A bottom sheet that shows available tours with completion status.
/// Used from Settings and contextual prompts.
class TourSelectionSheet extends ConsumerWidget {
  const TourSelectionSheet({super.key});

  /// Shows the tour selection sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TourSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final tutorialState = ref.watch(tutorialProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          top: BorderSide(color: colors.border),
          left: BorderSide(color: colors.border),
          right: BorderSide(color: colors.border),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _SheetHeader(colors: colors),

            // Tour list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Workflow Tours Section
                    _SectionHeader(title: 'Workflow Tours', colors: colors),
                    _TourListItem(
                      category: TutorialCategory.firstLight,
                      title: 'Quick Start',
                      description: 'Connect and capture your first image',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () =>
                          _startTour(context, ref, TutorialCategory.firstLight),
                    ),
                    _TourListItem(
                      category: TutorialCategory.equipmentSetup,
                      title: 'Equipment Setup',
                      description: 'Profiles, drivers, and connections',
                      durationMinutes: 2,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.equipmentSetup),
                    ),
                    _TourListItem(
                      category: TutorialCategory.targetPlanning,
                      title: 'Target Planning',
                      description: 'Find and frame celestial objects',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.targetPlanning),
                    ),
                    _TourListItem(
                      category: TutorialCategory.automatedImaging,
                      title: 'Automated Imaging',
                      description: 'Build and run imaging sequences',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.automatedImaging),
                    ),
                    _TourListItem(
                      category: TutorialCategory.calibrationFrames,
                      title: 'Calibration Frames',
                      description: 'Capture flats with the Flat Wizard',
                      durationMinutes: 2,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.calibrationFrames),
                    ),
                    _TourListItem(
                      category: TutorialCategory.advancedFeatures,
                      title: 'Advanced Features',
                      description: 'Analytics, weather, and settings',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.advancedFeatures),
                    ),

                    // Screen Tours Section
                    const SizedBox(height: 8),
                    _SectionHeader(title: 'Screen Tours', colors: colors),
                    _TourListItem(
                      category: TutorialCategory.dashboardTour,
                      title: 'Dashboard',
                      description: 'Customize widgets and monitor your session',
                      durationMinutes: 5,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.dashboardTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.equipmentTour,
                      title: 'Equipment',
                      description: 'Manage profiles and connect devices',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.equipmentTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.imagingTour,
                      title: 'Imaging',
                      description: 'Camera controls and image capture',
                      durationMinutes: 6,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.imagingTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.guidingTour,
                      title: 'Guiding',
                      description: 'PHD2 integration and tracking',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.guidingTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.sequencerTour,
                      title: 'Sequencer',
                      description: 'Build automated imaging sequences',
                      durationMinutes: 5,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.sequencerTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.planetariumTour,
                      title: 'Planetarium',
                      description: 'Interactive sky chart and object search',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.planetariumTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.framingTour,
                      title: 'Framing',
                      description: 'Compose shots and plan mosaics',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.framingTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.analyticsTour,
                      title: 'Analytics',
                      description: 'Session history and performance tracking',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.analyticsTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.flatWizardTour,
                      title: 'Flat Wizard',
                      description: 'Automated flat frame capture',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.flatWizardTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.weatherTour,
                      title: 'Weather',
                      description: 'Forecast and cloud tracking',
                      durationMinutes: 3,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.weatherTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.settingsTour,
                      title: 'Settings',
                      description: 'Configure Nightshade preferences',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.settingsTour),
                    ),
                    _TourListItem(
                      category: TutorialCategory.polarAlignmentTour,
                      title: 'Polar Alignment',
                      description: 'Plate-solving polar alignment wizard',
                      durationMinutes: 4,
                      tutorialState: tutorialState,
                      colors: colors,
                      onStart: () => _startTour(
                          context, ref, TutorialCategory.polarAlignmentTour),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startTour(
      BuildContext context, WidgetRef ref, TutorialCategory category) {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);
    tutorialNotifier.startTutorial(category);
    Navigator.of(context).pop();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final NightshadeColors colors;

  const _SectionHeader({
    required this.title,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _SheetHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          // Drag handle indicator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Available Tours',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Close button with 48px touch target
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(LucideIcons.x, color: colors.textMuted),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}

class _TourListItem extends StatelessWidget {
  final TutorialCategory category;
  final String title;
  final String description;
  final int durationMinutes;
  final TutorialProgress tutorialState;
  final NightshadeColors colors;
  final VoidCallback onStart;

  const _TourListItem({
    required this.category,
    required this.title,
    required this.description,
    required this.durationMinutes,
    required this.tutorialState,
    required this.colors,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final status = _getTourStatus();
    final progress = _getTourProgress();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onStart,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status icon
                _StatusIcon(status: status, colors: colors),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Duration or progress indicator
                _StatusBadge(
                  status: status,
                  progress: progress,
                  durationMinutes: durationMinutes,
                  colors: colors,
                ),
                const SizedBox(width: 12),

                // Action button
                _ActionButton(
                  status: status,
                  colors: colors,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _TourStatus _getTourStatus() {
    final steps = TutorialDefinitions.getStepsForCategory(category);
    final completedCount = steps
        .where(
          (step) => tutorialState.completedSteps.contains(step.id),
        )
        .length;

    if (completedCount == 0) {
      return _TourStatus.notStarted;
    } else if (completedCount >= steps.length) {
      return _TourStatus.completed;
    } else {
      return _TourStatus.inProgress;
    }
  }

  String _getTourProgress() {
    final steps = TutorialDefinitions.getStepsForCategory(category);
    final completedCount = steps
        .where(
          (step) => tutorialState.completedSteps.contains(step.id),
        )
        .length;
    return '$completedCount/${steps.length}';
  }
}

enum _TourStatus {
  notStarted,
  inProgress,
  completed,
}

class _StatusIcon extends StatelessWidget {
  final _TourStatus status;
  final NightshadeColors colors;

  const _StatusIcon({
    required this.status,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    Color backgroundColor;

    switch (status) {
      case _TourStatus.completed:
        icon = LucideIcons.check;
        color = colors.success;
        backgroundColor = colors.success.withValues(alpha: 0.15);
        break;
      case _TourStatus.inProgress:
        icon = LucideIcons.clock;
        color = colors.warning;
        backgroundColor = colors.warning.withValues(alpha: 0.15);
        break;
      case _TourStatus.notStarted:
        icon = LucideIcons.circle;
        color = colors.textMuted;
        backgroundColor = colors.surfaceHover;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _TourStatus status;
  final String progress;
  final int durationMinutes;
  final NightshadeColors colors;

  const _StatusBadge({
    required this.status,
    required this.progress,
    required this.durationMinutes,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    Color textColor;

    switch (status) {
      case _TourStatus.completed:
        text = 'Completed';
        textColor = colors.success;
        break;
      case _TourStatus.inProgress:
        text = progress;
        textColor = colors.warning;
        break;
      case _TourStatus.notStarted:
        text = '~$durationMinutes min';
        textColor = colors.textMuted;
        break;
    }

    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final _TourStatus status;
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.status,
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    bool isPrimary;

    switch (status) {
      case _TourStatus.completed:
        text = 'Restart';
        isPrimary = false;
        break;
      case _TourStatus.inProgress:
        text = 'Resume';
        isPrimary = true;
        break;
      case _TourStatus.notStarted:
        text = 'Start';
        isPrimary = false;
        break;
    }

    return NightshadeButton(
      onPressed: onPressed,
      label: text,
      icon: LucideIcons.arrowRight,
      variant: isPrimary ? ButtonVariant.primary : ButtonVariant.outline,
      size: ButtonSize.small,
    );
  }
}
