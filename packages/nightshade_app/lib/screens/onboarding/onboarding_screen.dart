import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/utils/confirm_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
import 'steps/site_step.dart';
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
/// Key on the phone footer's full-width primary-action region (the 48 px tall
/// tap surface). Exposed so responsive widget tests can assert the touch-target
/// floor on the reachable area rather than the button's intrinsic content box.
const Key phonePrimaryActionKey = Key('onboarding.phone.primaryAction');

/// Key on the wizard's inline notice band — the strip that carries validation
/// warnings and save results. Exposed so tests can assert both that the message
/// is shown and that it does not intersect the footer.
const Key onboardingNoticeKey = Key('onboarding.notice');

/// A message the wizard shell needs to tell the user, rendered in the layout
/// flow directly above the footer.
///
/// These used to be [SnackBar]s. A Material snackbar docks to the bottom of the
/// [Scaffold] — exactly where the wizard footer lives — so it covered Back /
/// Next / Save profile *and* swallowed taps on them: the wizard said "you must
/// fix this" while removing the controls needed to act on it. A notice in the
/// Column cannot overlap the footer at any window size, and it stays put until
/// the user resolves it instead of expiring after three seconds.
class _WizardNotice {
  const _WizardNotice(
    this.message,
    this.severity, {
    this.fromValidation = false,
  });

  final String message;
  final NightshadeAlertSeverity severity;

  /// True when this message states why the current step is blocked, as opposed
  /// to reporting an event that already happened ("Profile created", "Could not
  /// save profile: …"). Only the former goes stale: it describes a condition
  /// the user is actively fixing, so it has to be re-derived from the draft on
  /// every build rather than left on screen as a snapshot of a past click.
  final bool fromValidation;
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepInputCooldown = Duration(milliseconds: 350);

  bool _saving = false;
  bool _transitioning = false;

  /// True while the "Leave setup?" confirmation is on screen, so a repeated
  /// back gesture cannot stack a second copy of it.
  bool _leavePromptOpen = false;

  /// The current inline notice, or null when there is nothing to say.
  _WizardNotice? _notice;

  void _showNotice(
    String message,
    NightshadeAlertSeverity severity, {
    bool fromValidation = false,
  }) {
    if (!mounted) return;
    setState(() => _notice =
        _WizardNotice(message, severity, fromValidation: fromValidation));
  }

  void _clearNotice() {
    if (_notice == null) return;
    setState(() => _notice = null);
  }

  /// The notice as it applies to the draft being rendered *now*.
  ///
  /// A validation notice names one specific blocking condition. The moment the
  /// user corrects it the stored message becomes a false statement — the band
  /// kept insisting "Focal length must be between 1 and 50000 mm." while the
  /// field read 600 and the step was ready to advance, so the wizard was
  /// telling the user to fix something already fixed. Re-deriving it here keeps
  /// the band honest: it disappears when the step validates, and re-words
  /// itself when a *different* field becomes the blocker.
  ///
  /// Non-validation notices (a completed save, a failed save) report events
  /// rather than conditions, so they are passed through untouched.
  _WizardNotice? _resolveNotice(OnboardingDraft draft) {
    final current = _notice;
    if (current == null || !current.fromValidation) return current;
    final reason = _validate(draft);
    if (reason == null) return null;
    if (reason == current.message) return current;
    return _WizardNotice(
      reason,
      NightshadeAlertSeverity.warning,
      fromValidation: true,
    );
  }

  Future<void> _runTransition(Future<void> Function() action) async {
    if (_saving || _transitioning) return;
    setState(() => _transitioning = true);
    try {
      await action();
    } finally {
      // Keep the button disabled through the visual hand-off to the next step.
      // Without this short cooldown, the second click of a desktop double-click
      // lands on the new step's button at the same coordinates and validates or
      // advances a screen the user never intentionally acted on.
      await Future<void>.delayed(_stepInputCooldown);
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _onNext() => _runTransition(_advance);

  Future<void> _advance() async {
    final draft = ref.read(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);

    _clearNotice();
    final validationError = _validate(draft);
    if (validationError != null) {
      // Surfaced in the notice band above the footer, never as a snackbar: a
      // snackbar covers and intercepts the very buttons the user needs to act
      // on the message.
      _showNotice(
        validationError,
        NightshadeAlertSeverity.warning,
        fromValidation: true,
      );
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
      await _finishToInternal('/dashboard');
      return;
    }

    await notifier.next();
  }

  Future<void> _onBack() => _runTransition(_goBack);

  Future<void> _goBack() async {
    _clearNotice();
    await ref.read(onboardingDraftProvider.notifier).back();
  }

  Future<void> _onSkipStep() => _runTransition(_skipStep);

  Future<void> _skipStep() async {
    // Optional step: clear any partial selection and move forward.
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final draft = ref.read(onboardingDraftProvider);
    _clearNotice();
    // Skipping is not an escape from an invalid entry — a rejected coordinate
    // has to be corrected or cleared, otherwise the user leaves believing the
    // site they typed was either saved or discarded when neither is true.
    final blocked = _validate(draft);
    if (blocked != null) {
      _showNotice(
        blocked,
        NightshadeAlertSeverity.warning,
        fromValidation: true,
      );
      return;
    }
    switch (draft.currentStep) {
      case OnboardingStep.focuser:
        await notifier.setFocuser(id: '');
        break;
      case OnboardingStep.filterWheel:
        await notifier.setFilterWheel(id: '');
        break;
      case OnboardingStep.guider:
        // A green PHD2 Test (or a native guider pick) already wrote the guider
        // into the draft; a plain Skip would silently drop it. Confirm before
        // removing a configured guider — Keep advances with it intact.
        if ((draft.guiderId ?? '').isNotEmpty) {
          final remove = await _confirmRemoveGuider();
          if (!mounted) return;
          if (remove) await notifier.setGuider(id: '');
        } else {
          await notifier.setGuider(id: '');
        }
        break;
      default:
        break;
    }
    await notifier.next();
  }

  /// Confirm dropping an already-configured guider when the user taps "Skip
  /// this step". Returns true to remove it, false (the default) to keep it.
  Future<bool> _confirmRemoveGuider() async {
    final colors = NightshadeColors.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Remove guider?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Skipping removes your configured guider. Keep it instead?',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            label: 'Remove',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: 'Keep',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Android system back / desktop Escape, routed to the wizard's own back
  /// affordance.
  ///
  /// This route is presented ABOVE the app shell, so the shell's back
  /// dispatcher never sees it and there is nothing beneath it to pop — an
  /// unhandled gesture finished the activity and dropped a first-run user on
  /// the launcher from step 2 of 13. The wizard already renders a Back button
  /// whenever a previous step exists; back means that. Where it does not (the
  /// welcome step, and the terminal step whose profile is already created),
  /// leaving is a decision the user makes rather than one a stray edge swipe
  /// makes for them.
  Future<void> _handleSystemBack() async {
    if (_saving || _transitioning || _leavePromptOpen) return;
    if (!ref.read(onboardingDraftProvider.notifier).isLoaded) return;

    final step = ref.read(onboardingDraftProvider).currentStep;
    if (step != OnboardingStep.welcome && step != OnboardingStep.nextSteps) {
      await _onBack();
      return;
    }

    _leavePromptOpen = true;
    try {
      final leave = await ConfirmDialog.show(
        context: context,
        title: 'Leave setup?',
        message: step == OnboardingStep.nextSteps
            ? 'Your equipment profile is saved. You can revisit these next '
                'steps any time from Equipment.'
            : 'Your progress is kept — you can pick setup back up from the '
                'Equipment screen whenever you like.',
        confirmLabel: 'Leave setup',
        cancelLabel: 'Keep setting up',
      );
      if (!mounted || !leave) return;
      if (step == OnboardingStep.nextSteps) {
        await _finishTo('/dashboard');
      } else {
        await _onExitWizard();
      }
    } finally {
      if (mounted) _leavePromptOpen = false;
    }
  }

  Future<void> _onExitWizard() => _runTransition(_exitWizard);

  Future<void> _exitWizard() async {
    // "Skip onboarding" from any step: mark dismissed in tutorial_progress
    // and route to the dashboard. The draft is preserved so the user can
    // pick up where they left off via the Equipment screen.
    _clearNotice();
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
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final notifier = ref.read(onboardingDraftProvider.notifier);
      await notifier.complete();
      await notifier.next();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = const _WizardNotice(
          'Profile created. Welcome to Nightshade.',
          NightshadeAlertSeverity.success,
        );
      });
    } catch (e) {
      if (!mounted) return;
      // Inline, not a snackbar: a failure banner that covers "Save profile" is
      // a dead end — the user is told it failed and cannot retry.
      setState(() {
        _saving = false;
        _notice = _WizardNotice(
          'Could not save profile: $e',
          NightshadeAlertSeverity.error,
        );
      });
    }
  }

  /// Leave the terminal `nextSteps` step toward [location]. Retires the wizard
  /// first ([finishNextSteps] is idempotent), then navigates. Used by the
  /// footer "Go to dashboard" / "Capture first light" actions and by the
  /// in-body next-step cards.
  Future<void> _finishTo(String location) =>
      _runTransition(() => _finishToInternal(location));

  Future<void> _finishToInternal(String location) async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await ref.read(onboardingDraftProvider.notifier).finishNextSteps();
      if (!mounted) return;
      context.go(location);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = _WizardNotice(
          'Could not finish setup: $e',
          NightshadeAlertSeverity.error,
        );
      });
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
          return 'Pick a camera to continue, or use "Skip onboarding" to set it up later.';
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
        // Bounds, not just "> 0": focal length 999999999 with aperture 0.0001
        // was accepted and rendered f/9999999990000.00, and focal length reaches
        // the FITS FOCALLEN card, plate-solve field-of-view and image scale.
        return OpticalTrainLimits.validate(
          focalLengthMm: draft.focalLengthMm,
          apertureMm: draft.apertureMm,
          pixelSizeMicrons: draft.pixelSizeMicrons,
          reducerFactor: draft.reducerFactor,
        );
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
      case OnboardingStep.site:
        // Optional in the sense that a blank site is allowed — every
        // location-driven surface handles "not set". A *rejected* coordinate is
        // not: advancing past a red out-of-range error used to leave whatever
        // partial value had already been committed on record as the user's
        // observing site. The step publishes its own blocking reason because the
        // in-progress field text never reaches the draft or settings.
        return ref.read(onboardingSiteEntryErrorProvider);
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
    // The site step's blocking reason lives outside the draft (the in-progress
    // field text never reaches it), so watch it too — otherwise a corrected
    // coordinate would leave the site step's notice stranded on screen.
    ref.watch(onboardingSiteEntryErrorProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleSystemBack());
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: notifier.isLoaded
              ? _buildWizard(context, theme, colors, draft)
              : Center(
                  child: CircularProgressIndicator(color: colors.primary),
                ),
        ),
      ),
    );
  }

  Widget _buildWizard(BuildContext context, ThemeData theme,
      NightshadeColors colors, OnboardingDraft draft) {
    // Drive the layout from the wizard's OWN width (not the raw window) so it
    // reflows correctly when embedded and on every phone/tablet/desktop size —
    // but ALSO treat a real phone held in landscape as a phone. A landscape
    // phone reports a tablet-ish width (~930) yet only ~410 px of height, where
    // the wide layout's step sidebar + bordered body + horizontal footer is
    // both mis-classified and far too tall. Device-class (orientation-stable
    // short edge) catches that; the width check still handles a narrow embed on
    // desktop.
    final isPhoneDevice = Responsive.isPhone(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final busy = _saving || _transitioning;
        final isPhone = isPhoneDevice ||
            constraints.maxWidth < BreakpointTokens.breakpointPhone;

        final onBack = draft.currentStep == OnboardingStep.welcome ||
                // On the terminal step the profile is already created; there is
                // nothing to go "back" to that wouldn't re-open the create
                // flow, so Back is suppressed.
                draft.currentStep == OnboardingStep.nextSteps ||
                busy
            ? null
            : _onBack;
        final onSkipStep =
            draft.currentStep.isOptional && !busy ? _onSkipStep : null;
        final onFirstLight =
            draft.currentStep == OnboardingStep.nextSteps && !busy
                ? _finishToFirstLight
                : null;

        return isPhone
            ? _buildPhoneWizard(
                context,
                theme,
                colors,
                draft,
                onBack: onBack,
                onSkipStep: onSkipStep,
                onFirstLight: onFirstLight,
              )
            : _buildWideWizard(
                context,
                theme,
                colors,
                draft,
                onBack: onBack,
                onSkipStep: onSkipStep,
                onFirstLight: onFirstLight,
              );
      },
    );
  }

  /// Tablet/desktop layout: step sidebar + bordered body + horizontal footer.
  /// Unchanged from the original wizard so wide layouts do not regress.
  Widget _buildWideWizard(
    BuildContext context,
    ThemeData theme,
    NightshadeColors colors,
    OnboardingDraft draft, {
    required VoidCallback? onBack,
    required VoidCallback? onSkipStep,
    required VoidCallback? onFirstLight,
  }) {
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
                onExit: (_saving || _transitioning) ? null : _onExitWizard,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepSidebar(currentStep: draft.currentStep),
                    const SizedBox(width: 16),
                    Expanded(
                      child: NightshadeCard(
                        backgroundColor: colors.background,
                        borderRadius: NightshadeTokens.radiusLg,
                        padding: const EdgeInsets.all(20),
                        child: _StepBody(
                          currentStep: draft.currentStep,
                          onFinishTo: _finishTo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The notice sits between the body and the footer, in the layout
              // flow: it displaces the footer rather than covering it.
              _NoticeBand(
                  notice: _resolveNotice(draft), onDismiss: _clearNotice),
              const SizedBox(height: 16),
              _Footer(
                currentStep: draft.currentStep,
                isSaving: _saving,
                onBack: onBack,
                onSkipStep: onSkipStep,
                onNext: (_saving || _transitioning) ? null : _onNext,
                onFirstLight: onFirstLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phone layout (portrait + landscape): no sidebar — a compact header with a
  /// step progress bar, the step body filling the remaining height in a single
  /// reflowed column, and a stacked footer whose primary action is full-width
  /// and always reachable.
  ///
  /// The body stays inside a bounded region (not a scroll view) so steps that
  /// rely on a finite height — e.g. the device picker's `Expanded` device list —
  /// keep working; each step body scrolls its own content where needed.
  Widget _buildPhoneWizard(
    BuildContext context,
    ThemeData theme,
    NightshadeColors colors,
    OnboardingDraft draft, {
    required VoidCallback? onBack,
    required VoidCallback? onSkipStep,
    required VoidCallback? onFirstLight,
  }) {
    // A phone in landscape is only ~410 px tall. Tighten the chrome (less outer
    // padding, slimmer header, single-row footer) so the step body keeps the
    // height it needs and nothing clips. Portrait keeps the roomier spacing.
    final compact = Responsive.isPhoneLandscape(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneHeader(
            currentStep: draft.currentStep,
            onExit: (_saving || _transitioning) ? null : _onExitWizard,
            compact: compact,
          ),
          SizedBox(height: compact ? 8 : 12),
          Expanded(
            child: _StepBody(
              currentStep: draft.currentStep,
              onFinishTo: _finishTo,
            ),
          ),
          _NoticeBand(notice: _resolveNotice(draft), onDismiss: _clearNotice),
          SizedBox(height: compact ? 8 : 12),
          _PhoneFooter(
            currentStep: draft.currentStep,
            isSaving: _saving,
            onBack: onBack,
            onSkipStep: onSkipStep,
            onNext: (_saving || _transitioning) ? null : _onNext,
            onFirstLight: onFirstLight,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

/// The wizard's inline message strip, shared by both layouts.
///
/// Occupies zero height when there is no notice, so the footer's position is
/// unchanged in the common case. When a notice is present it takes real space in
/// the Column above the footer, which is what guarantees the two can never
/// overlap — the previous snackbar was painted over the footer and also ate its
/// taps.
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

class _StepSidebar extends StatelessWidget {
  const _StepSidebar({required this.currentStep});
  final OnboardingStep currentStep;

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
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final currentIdx = currentStep.order;

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
                          ? Icon(NightshadeIcons.check,
                              size: 12,
                              color: Theme.of(context).colorScheme.onPrimary)
                          : Icon(
                              _stepIcons[step] ?? NightshadeIcons.circle,
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
                        color: isActive
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (step.isOptional)
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
