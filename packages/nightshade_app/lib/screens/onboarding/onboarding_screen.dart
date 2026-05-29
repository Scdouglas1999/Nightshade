import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';
import 'steps/camera_defaults_step.dart';
import 'steps/camera_step.dart';
import 'steps/capture_dir_step.dart';
import 'steps/driver_step.dart';
import 'steps/filter_wheel_step.dart';
import 'steps/focuser_step.dart';
import 'steps/guider_step.dart';
import 'steps/mount_step.dart';
import 'steps/next_steps_step.dart';
import 'steps/optical_train_step.dart';
import 'steps/summary_step.dart';
import 'steps/welcome_step.dart';

/// First-run equipment onboarding wizard.
///
/// Orchestrates the [OnboardingStep] flow, validates each step before
/// advancing, and commits the final draft as a new equipment profile.
///
/// Why a full-screen scaffold instead of a modal dialog: the steps
/// (especially device discovery and the optical-train calculator) need
/// real screen real estate, and a new user shouldn't see the dashboard
/// background bleed through behind a partially-translucent dialog.
/// Returning users reach the dashboard by pressing "Skip onboarding".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _saving = false;

  Future<void> _onNext() async {
    final draft = ref.read(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);

    final validationError = _validate(draft);
    if (validationError != null) {
      // Surface the requirement via a snackbar — keeps the inline
      // step body uncluttered while still being obvious.
      context.showWarningSnackBar(validationError);
      return;
    }

    if (draft.currentStep == OnboardingStep.summary) {
      await _createProfileAndAdvance();
      return;
    }

    if (draft.currentStep == OnboardingStep.nextSteps) {
      // Primary action on the terminal step: retire the wizard and land on
      // the dashboard. The secondary "Capture first light" path is handled by
      // [_finishToFirstLight].
      await _finishTo('/dashboard');
      return;
    }

    await notifier.next();
  }

  Future<void> _onBack() async {
    await ref.read(onboardingDraftProvider.notifier).back();
  }

  Future<void> _onSkipStep() async {
    // Optional step: clear any partial selection and move forward.
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final step = ref.read(onboardingDraftProvider).currentStep;
    switch (step) {
      case OnboardingStep.focuser:
        await notifier.setFocuser(id: '');
        break;
      case OnboardingStep.filterWheel:
        await notifier.setFilterWheel(id: '');
        break;
      case OnboardingStep.guider:
        await notifier.setGuider(id: '');
        break;
      default:
        break;
    }
    await notifier.next();
  }

  Future<void> _onExitWizard() async {
    // "Skip onboarding" from any step: mark dismissed in tutorial_progress
    // and route to the dashboard. The draft is preserved so the user can
    // pick up where they left off via the Equipment screen.
    await ref.read(onboardingDraftProvider.notifier).skip();
    if (!mounted) return;
    context.go('/dashboard');
  }

  /// Summary step "Save profile": create the equipment profile, then advance
  /// to the terminal `nextSteps` step WITHOUT navigating away. The rig now
  /// exists and is active; the wizard stays open so the user sees the
  /// "what's next" guidance. Retiring onboarding (marking the tutorial
  /// complete, wiping the draft, flipping the gate) is deferred until the user
  /// leaves the next-steps step via [finishNextSteps].
  Future<void> _createProfileAndAdvance() async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(onboardingDraftProvider.notifier);
      await notifier.complete();
      await notifier.next();
      if (!mounted) return;
      context.showSuccessSnackBar('Profile created. Welcome to Nightshade.');
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not save profile: $e');
      setState(() => _saving = false);
    }
  }

  /// Leave the terminal `nextSteps` step toward [location]. Retires the wizard
  /// first ([finishNextSteps] is idempotent), then navigates. Used by the
  /// footer "Go to dashboard" / "Capture first light" actions and by the
  /// in-body next-step cards.
  Future<void> _finishTo(String location) async {
    setState(() => _saving = true);
    try {
      await ref.read(onboardingDraftProvider.notifier).finishNextSteps();
      if (!mounted) return;
      context.go(location);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not finish setup: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _finishToFirstLight() => _finishTo('/imaging?firstLight=1');

  /// Validate that the user has provided the data this step requires.
  /// Returns null if OK, or a human-readable message that we surface in
  /// the snackbar. We deliberately do not block on optional steps.
  String? _validate(OnboardingDraft draft) {
    switch (draft.currentStep) {
      case OnboardingStep.welcome:
        return null;
      case OnboardingStep.drivers:
        if (draft.selectedDrivers.isEmpty) {
          return 'Pick at least one driver to scan.';
        }
        return null;
      case OnboardingStep.camera:
        if (draft.cameraId == null) {
          return 'Pick a camera or skip from the side nav if you want to come back later.';
        }
        return null;
      case OnboardingStep.mount:
        if (draft.mountId == null) {
          return 'Pick a mount before continuing.';
        }
        return null;
      case OnboardingStep.focuser:
      case OnboardingStep.filterWheel:
      case OnboardingStep.guider:
        return null;
      case OnboardingStep.opticalTrain:
        if (draft.focalLengthMm == null || draft.focalLengthMm! <= 0) {
          return 'Focal length is required.';
        }
        if (draft.apertureMm == null || draft.apertureMm! <= 0) {
          return 'Aperture is required.';
        }
        if (draft.pixelSizeMicrons == null || draft.pixelSizeMicrons! <= 0) {
          return 'Pixel size is required.';
        }
        if (draft.reducerFactor <= 0) {
          return 'Reducer factor must be greater than zero.';
        }
        return null;
      case OnboardingStep.cameraDefaults:
        // Always valid: the preset (or the camera step's pixel size) pre-fills
        // sensible gain/offset/binning/cooling defaults, and every field is
        // individually editable. There is nothing here the user must supply.
        return null;
      case OnboardingStep.captureDir:
        if (draft.captureDirectory == null ||
            draft.captureDirectory!.trim().isEmpty) {
          return 'Pick a capture folder.';
        }
        return null;
      case OnboardingStep.summary:
        if ((draft.profileName ?? '').trim().isEmpty) {
          return 'Give your profile a name.';
        }
        return null;
      case OnboardingStep.nextSteps:
        // Terminal step: the profile already exists. Leaving it is always
        // allowed (either to the dashboard or to first light).
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.watch(onboardingDraftProvider.notifier);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: notifier.isLoaded
            ? _buildWizard(context, theme, colors, draft)
            : Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
      ),
    );
  }

  Widget _buildWizard(BuildContext context, ThemeData theme,
      NightshadeColors colors, OnboardingDraft draft) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth(context, 1080),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _Header(
                currentStep: draft.currentStep,
                onExit: _saving ? null : _onExitWizard,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepSidebar(currentStep: draft.currentStep),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius:
                              BorderRadius.circular(NightshadeTokens.radiusLg),
                          border: Border.all(color: colors.border),
                        ),
                        child: _StepBody(
                          currentStep: draft.currentStep,
                          onFinishTo: _finishTo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Footer(
                currentStep: draft.currentStep,
                isSaving: _saving,
                onBack: draft.currentStep == OnboardingStep.welcome ||
                        // On the terminal step the profile is already created;
                        // there is nothing to go "back" to that wouldn't
                        // re-open the create flow, so Back is suppressed.
                        draft.currentStep == OnboardingStep.nextSteps ||
                        _saving
                    ? null
                    : _onBack,
                onSkipStep: draft.currentStep.isOptional && !_saving
                    ? _onSkipStep
                    : null,
                onNext: _saving ? null : _onNext,
                onFirstLight:
                    draft.currentStep == OnboardingStep.nextSteps && !_saving
                        ? _finishToFirstLight
                        : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.currentStep, required this.onExit});

  final OnboardingStep currentStep;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: NightshadeDecorations.iconChip(
            colors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(LucideIcons.sparkles, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set up your rig',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Step ${currentStep.order + 1} of ${OnboardingStepOrder.total}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onExit,
          icon: Icon(LucideIcons.logOut, size: 14, color: colors.textSecondary),
          label: Text(
            'Skip onboarding',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _StepSidebar extends StatelessWidget {
  const _StepSidebar({required this.currentStep});
  final OnboardingStep currentStep;

  static const _stepLabels = <OnboardingStep, String>{
    OnboardingStep.welcome: 'Welcome',
    OnboardingStep.drivers: 'Drivers',
    OnboardingStep.camera: 'Camera',
    OnboardingStep.mount: 'Mount',
    OnboardingStep.focuser: 'Focuser',
    OnboardingStep.filterWheel: 'Filter wheel',
    OnboardingStep.guider: 'Guider',
    OnboardingStep.opticalTrain: 'Optical train',
    OnboardingStep.cameraDefaults: 'Camera defaults',
    OnboardingStep.captureDir: 'Capture folder',
    OnboardingStep.summary: 'Review & save',
    OnboardingStep.nextSteps: "What's next",
  };

  static const _stepIcons = <OnboardingStep, IconData>{
    OnboardingStep.welcome: LucideIcons.heart,
    OnboardingStep.drivers: LucideIcons.plug,
    OnboardingStep.camera: LucideIcons.camera,
    OnboardingStep.mount: LucideIcons.compass,
    OnboardingStep.focuser: LucideIcons.focus,
    OnboardingStep.filterWheel: LucideIcons.disc,
    OnboardingStep.guider: LucideIcons.crosshair,
    OnboardingStep.opticalTrain: LucideIcons.ruler,
    OnboardingStep.cameraDefaults: LucideIcons.sliders,
    OnboardingStep.captureDir: LucideIcons.folder,
    OnboardingStep.summary: LucideIcons.clipboardCheck,
    OnboardingStep.nextSteps: LucideIcons.rocket,
  };

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final currentIdx = currentStep.order;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: ListView(
        children: OnboardingStep.values.map((step) {
          final idx = step.order;
          final isActive = step == currentStep;
          final isCompleted = idx < currentIdx;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive || isCompleted
                        ? colors.primary
                        : colors.surfaceAlt,
                    border: Border.all(
                      color: isActive
                          ? colors.primary
                          : isCompleted
                              ? colors.primary
                              : colors.border,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? Icon(LucideIcons.check,
                            size: 12,
                            color: Theme.of(context).colorScheme.onPrimary)
                        : Icon(
                            _stepIcons[step] ?? LucideIcons.circle,
                            size: 12,
                            color: isActive
                                ? Theme.of(context).colorScheme.onPrimary
                                : colors.textMuted,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _stepLabels[step] ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isActive ? colors.textPrimary : colors.textSecondary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (step.isOptional)
                  Tooltip(
                    message: 'Optional step',
                    child: Icon(
                      LucideIcons.minus,
                      size: 10,
                      color: colors.textMuted,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({required this.currentStep, required this.onFinishTo});

  final OnboardingStep currentStep;

  /// Routes a terminal next-step card to its destination after retiring the
  /// wizard. Forwarded from [_OnboardingScreenState._finishTo] so the in-body
  /// "what's next" cards and the footer share one finalize path.
  final ValueChanged<String> onFinishTo;

  @override
  Widget build(BuildContext context) {
    // Each step is its own widget. We keep this dispatch flat (rather
    // than a giant switch in the parent) so a step can own its
    // controllers and lifecycle without disturbing the wizard shell.
    switch (currentStep) {
      case OnboardingStep.welcome:
        return const OnboardingWelcomeStep();
      case OnboardingStep.drivers:
        return const OnboardingDriverStep();
      case OnboardingStep.camera:
        return const OnboardingCameraStep();
      case OnboardingStep.mount:
        return const OnboardingMountStep();
      case OnboardingStep.focuser:
        return const OnboardingFocuserStep();
      case OnboardingStep.filterWheel:
        return const OnboardingFilterWheelStep();
      case OnboardingStep.guider:
        return const OnboardingGuiderStep();
      case OnboardingStep.opticalTrain:
        return const OnboardingOpticalTrainStep();
      case OnboardingStep.cameraDefaults:
        return const OnboardingCameraDefaultsStep();
      case OnboardingStep.captureDir:
        return const OnboardingCaptureDirStep();
      case OnboardingStep.summary:
        return const OnboardingSummaryStep();
      case OnboardingStep.nextSteps:
        return OnboardingNextStepsStep(onNavigate: onFinishTo);
    }
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.currentStep,
    required this.isSaving,
    required this.onBack,
    required this.onSkipStep,
    required this.onNext,
    required this.onFirstLight,
  });

  final OnboardingStep currentStep;
  final bool isSaving;
  final VoidCallback? onBack;
  final VoidCallback? onSkipStep;
  final VoidCallback? onNext;

  /// Secondary "Capture first light" action, present only on the terminal
  /// `nextSteps` step. Null elsewhere.
  final VoidCallback? onFirstLight;

  @override
  Widget build(BuildContext context) {
    final isSummary = currentStep == OnboardingStep.summary;
    final isNextSteps = currentStep == OnboardingStep.nextSteps;

    final IconData primaryIcon;
    final String primaryLabel;
    if (isNextSteps) {
      primaryIcon = LucideIcons.layoutDashboard;
      primaryLabel = 'Go to dashboard';
    } else if (isSummary) {
      primaryIcon = LucideIcons.check;
      primaryLabel = 'Save profile';
    } else {
      primaryIcon = LucideIcons.arrowRight;
      primaryLabel = 'Next';
    }

    return Row(
      children: [
        NightshadeButton(
          icon: LucideIcons.arrowLeft,
          label: 'Back',
          variant: ButtonVariant.outline,
          onPressed: onBack,
        ),
        const Spacer(),
        if (onSkipStep != null) ...[
          NightshadeButton(
            label: 'Skip this step',
            variant: ButtonVariant.ghost,
            onPressed: onSkipStep,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
        ],
        if (isNextSteps && onFirstLight != null) ...[
          NightshadeButton(
            icon: LucideIcons.sparkles,
            label: 'Capture first light',
            variant: ButtonVariant.outline,
            onPressed: isSaving ? null : onFirstLight,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
        ],
        NightshadeButton(
          icon: primaryIcon,
          label: primaryLabel,
          variant: ButtonVariant.primary,
          isLoading: isSaving,
          onPressed: onNext,
        ),
      ],
    );
  }
}
