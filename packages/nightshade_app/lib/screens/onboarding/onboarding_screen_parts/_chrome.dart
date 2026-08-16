// Notice band, headers, footers, step sidebar and step body chrome.
part of '../onboarding_screen.dart';

/// The wizard's inline message strip, shared by both layouts.
///
/// Occupies zero height when there is no notice, so the footer's position is
/// unchanged in the common case. When a notice is present it takes real space in
/// the Column above the footer, which is what guarantees the two can never
/// overlap.
///
/// Height is capped with an internal scroll so a long message (an exception
/// string from a failed save) shrinks the step body instead of squeezing the
/// Column into an overflow.
class _NoticeBand extends StatelessWidget {
  const _NoticeBand({required this.notice, required this.onDismiss});

  final _WizardNotice? notice;
  final VoidCallback onDismiss;

  static const double _maxHeight = 112;

  @override
  Widget build(BuildContext context) {
    final current = notice;
    if (current == null) return const SizedBox.shrink();
    return Padding(
      key: onboardingNoticeKey,
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: SingleChildScrollView(
          child: NightshadeAlert(
            message: current.message,
            severity: current.severity,
            compact: true,
            onDismiss: onDismiss,
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
            borderRadius: NightshadeTokens.borderRadiusLg,
          ),
          child: Icon(NightshadeIcons.sparkle, color: colors.primary, size: 20),
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

/// Compact phone header: icon + title, an inline "Skip onboarding" icon button
/// (the full label would crowd a 360 px row), and a step progress bar. Replaces
/// the wide layout's sidebar, which doesn't fit a phone column.
class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({
    required this.currentStep,
    required this.onExit,
    this.compact = false,
  });

  final OnboardingStep currentStep;
  final VoidCallback? onExit;

  /// Landscape-phone tier: slim the icon chip and tighten the gap between the
  /// title row and progress bar so the header costs less vertical space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final stepNumber = currentStep.order + 1;
    final total = OnboardingStepOrder.total;
    final progress = stepNumber / total;
    final chipSize = compact ? 30.0 : 36.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: chipSize,
              height: chipSize,
              decoration: NightshadeDecorations.iconChip(
                colors.primary,
                borderRadius: NightshadeTokens.borderRadiusLg,
              ),
              child: Icon(
                NightshadeIcons.sparkle,
                color: colors.primary,
                size: compact ? 16 : 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set up your rig',
                    style: (compact
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Step $stepNumber of $total — ${_StepSidebar.labelFor(currentStep)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onExit,
              tooltip: 'Skip onboarding',
              iconSize: 20,
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              icon: Icon(LucideIcons.logOut, color: colors.textSecondary),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 10),
        ClipRRect(
          borderRadius: NightshadeTokens.borderRadiusFull,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
          ),
        ),
      ],
    );
  }
}

/// Phone footer: primary action spans the full width on its own row (always
/// reachable, ≥48 px), with Back / Skip / "Capture first light" wrapped beneath
/// it so nothing overflows a narrow column.
class _PhoneFooter extends StatelessWidget {
  const _PhoneFooter({
    required this.currentStep,
    required this.isSaving,
    required this.onBack,
    required this.onSkipStep,
    required this.onNext,
    required this.onFirstLight,
    this.compact = false,
  });

  final OnboardingStep currentStep;
  final bool isSaving;
  final VoidCallback? onBack;
  final VoidCallback? onSkipStep;
  final VoidCallback? onNext;
  final VoidCallback? onFirstLight;

  /// Landscape-phone tier: lay the secondary actions BESIDE the primary in one
  /// row (the portrait layout stacks them beneath it) to reclaim vertical space
  /// on the ~410 px tall viewport.
  final bool compact;

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
      primaryIcon = NightshadeIcons.check;
      primaryLabel = 'Save profile';
    } else {
      primaryIcon = NightshadeIcons.arrowRight;
      primaryLabel = 'Next';
    }

    final secondary = <Widget>[
      if (onBack != null)
        NightshadeButton(
          icon: NightshadeIcons.arrowLeft,
          label: 'Back',
          variant: ButtonVariant.outline,
          onPressed: onBack,
        ),
      if (onSkipStep != null)
        NightshadeButton(
          label: 'Skip this step',
          variant: ButtonVariant.ghost,
          onPressed: onSkipStep,
        ),
      if (isNextSteps && onFirstLight != null)
        NightshadeButton(
          icon: NightshadeIcons.sparkle,
          label: 'Capture first light',
          variant: ButtonVariant.outline,
          onPressed: isSaving ? null : onFirstLight,
        ),
    ];

    final primaryAction = SizedBox(
      key: phonePrimaryActionKey,
      height: 48,
      child: NightshadeButton(
        icon: primaryIcon,
        label: primaryLabel,
        variant: ButtonVariant.primary,
        size: ButtonSize.large,
        isLoading: isSaving,
        onPressed: onNext,
      ),
    );

    // Landscape: one row — secondary actions on the left, primary on the right
    // (still ≥48 px tall). This trades the portrait two-row stack for a single
    // row so the short viewport keeps more height for the step body.
    if (compact) {
      return Row(
        children: [
          for (final action in secondary) ...[
            action,
            const SizedBox(width: NightshadeTokens.spaceSm),
          ],
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160),
            child: primaryAction,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: double.infinity, child: primaryAction),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: NightshadeTokens.spaceMd,
            runSpacing: NightshadeTokens.spaceSm,
            children: secondary,
          ),
        ],
      ],
    );
  }
}

class _StepSidebar extends ConsumerWidget {
  const _StepSidebar({required this.currentStep, required this.draft});
  final OnboardingStep currentStep;

  /// The live draft, so a passed step is ticked only when it captured a value.
  final OnboardingDraft draft;

  /// Human-readable label for [step], shared with the phone header.
  static String labelFor(OnboardingStep step) => _stepLabels[step] ?? '';

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
    OnboardingStep.site: 'Observing site',
    OnboardingStep.summary: 'Review & save',
    OnboardingStep.nextSteps: "What's next",
  };

  static const _stepIcons = <OnboardingStep, IconData>{
    OnboardingStep.welcome: LucideIcons.heart,
    OnboardingStep.drivers: NightshadeIcons.connected,
    OnboardingStep.camera: NightshadeIcons.camera,
    OnboardingStep.mount: NightshadeIcons.compass,
    OnboardingStep.focuser: NightshadeIcons.focuser,
    OnboardingStep.filterWheel: NightshadeIcons.filterWheel,
    OnboardingStep.guider: NightshadeIcons.crosshair,
    OnboardingStep.opticalTrain: LucideIcons.ruler,
    OnboardingStep.cameraDefaults: NightshadeIcons.sliders,
    OnboardingStep.captureDir: NightshadeIcons.folder,
    OnboardingStep.site: LucideIcons.mapPin,
    OnboardingStep.summary: LucideIcons.clipboardCheck,
    OnboardingStep.nextSteps: LucideIcons.rocket,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final currentIdx = currentStep.order;

    // The observing site is a global observer setting, so it is the only step
    // whose value lives outside the draft. Null island (0,0) is the "not set"
    // sentinel, exactly as the Review screen reads it.
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final siteConfigured = settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0);

    return SizedBox(
      width: 220,
      child: NightshadeCard(
        variant: CardVariant.subtle,
        borderRadius: NightshadeTokens.radiusLg,
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: OnboardingStep.values.map((step) {
            final idx = step.order;
            final isActive = step == currentStep;
            final isPassed = idx < currentIdx;
            // A tick claims the step configured something. Steps the user
            // walked past without supplying a value (a skipped focuser, a
            // guider whose test failed) get a dash instead — the same answer
            // the Review screen gives.
            final isCompleted = isPassed &&
                draft.producedValueFor(step, siteConfigured: siteConfigured);
            final isSkipped = isPassed && !isCompleted;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Tooltip(
                    message: isCompleted
                        ? 'Configured'
                        : isSkipped
                            ? 'Skipped — nothing was set'
                            : isActive
                                ? 'Current step'
                                : 'Not reached yet',
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive || isCompleted
                            ? colors.primary
                            : colors.surfaceAlt,
                        border: Border.all(
                          color: isActive || isCompleted
                              ? colors.primary
                              : colors.border,
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(NightshadeIcons.check,
                                size: 12,
                                color: Theme.of(context).colorScheme.onPrimary)
                            : Icon(
                                isSkipped
                                    ? NightshadeIcons.remove
                                    : (_stepIcons[step] ??
                                        NightshadeIcons.circle),
                                size: 12,
                                color: isActive
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : colors.textMuted,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _stepLabels[step] ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isActive
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Only ahead of the cursor: once a step is behind you the
                  // leading indicator already says configured vs skipped, and
                  // a second dash on the same row just reads as noise.
                  if (step.isOptional && !isPassed)
                    Tooltip(
                      message: 'Optional step',
                      child: Icon(
                        NightshadeIcons.remove,
                        size: 10,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
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
      case OnboardingStep.site:
        return const OnboardingSiteStep();
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
      primaryIcon = NightshadeIcons.check;
      primaryLabel = 'Save profile';
    } else {
      primaryIcon = NightshadeIcons.arrowRight;
      primaryLabel = 'Next';
    }

    return Row(
      children: [
        // On step 1 of 13 `onBack` is null. Drawing the button anyway
        // publishes a plain `button: Back` with no disabled state that does
        // nothing when clicked, and the phone footer above omits it, so the two
        // footers would disagree. A control that cannot act must not be on
        // screen claiming it can.
        if (onBack != null)
          NightshadeButton(
            icon: NightshadeIcons.arrowLeft,
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
            icon: NightshadeIcons.sparkle,
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
