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

part 'onboarding_screen_parts/_chrome.dart';

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
                    _StepSidebar(currentStep: draft.currentStep, draft: draft),
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
