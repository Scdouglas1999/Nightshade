import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        FirstNightWizardStep,
        FirstNightWizardState,
        firstNightWizardProvider,
        FirstNightWizardNotifier,
        // Alias for the model-layer `FirstNightWizard` (hidden from the
        // barrel because it collides with this widget class of the same
        // name). Defined in `src/legacy_aliases.dart`.
        FirstNightWizardModel;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import 'tutorial_step_widget.dart';

/// First-night wizard — a 7-step modal walkthrough for new users.
///
/// This wizard is replay-only: it is reached solely from Settings → Help &
/// Tutorials (the single replay hub for walkthroughs). It is NO LONGER
/// auto-launched at startup. After the onboarding consolidation, the startup
/// spine is the single equipment-onboarding wizard, gated by
/// `EquipmentOnboardingLauncher` in `app.dart` — not this widget. Removing the
/// (former) "auto-opens on first launch" behavior is intentional and does not
/// break startup; do not re-wire this wizard into bootstrap.
///
/// The wizard's progress is persisted to `tutorial_progress` so closing the
/// dialog mid-way and re-opening it from Settings resumes at the same step.
///
/// Why a ConsumerStatefulWidget instead of a stateless dialog: the
/// wizard waits for the saved-progress load before painting any step, so
/// a freshly-launched app doesn't flash step 0 before jumping to the
/// resumed step. That requires watching the provider through riverpod.
class FirstNightWizard extends ConsumerStatefulWidget {
  const FirstNightWizard({super.key});

  /// Show the wizard as a modal dialog over the current navigator. Returns
  /// when the user closes the dialog (either via Done, Skip Forever, or
  /// the close button). Callers don't need to handle the return value —
  /// all persistence happens inside the notifier.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FirstNightWizard(),
    );
  }

  @override
  ConsumerState<FirstNightWizard> createState() => _FirstNightWizardState();
}

class _FirstNightWizardState extends ConsumerState<FirstNightWizard> {
  // Cache the steps once per dialog open. The core getter validates the
  // seven-step length invariant on every read; doing it once per dialog
  // is sufficient and avoids re-running that check on every rebuild.
  late final List<FirstNightWizardStep> _steps =
      FirstNightWizardModel.steps;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firstNightWizardProvider);
    final notifier = ref.read(firstNightWizardProvider.notifier);
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;

    // Until the saved index has loaded from the DAO, show a small spinner
    // dialog. We intentionally do NOT render step 0 here — that would
    // flash the welcome step for a frame before jumping to (say) step 5
    // for a returning resumer.
    if (!state.isLoaded) {
      return NightshadeDialog(
        title: l10n.text('firstNightWizardTitle'),
        icon: NightshadeIcons.sparkle,
        width: 600,
        height: 400,
        showCloseButton: false,
        child: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    final currentStep = _steps[state.currentStepIndex];

    return NightshadeDialog(
      title: l10n.text('firstNightWizardTitle'),
      icon: NightshadeIcons.sparkle,
      width: 640,
      height: 560,
      // The close button is the "soft close" — same effect as
      // [_handleShowOnNextLaunch], i.e. wipe progress so the wizard
      // reopens next launch. That's the least-surprising default: if the
      // user X's out, they didn't say "never again", they said "not now".
      onClose: () {
        notifier.showOnNextLaunch();
        Navigator.of(context).pop();
      },
      actions: _buildActions(context, state, notifier),
      child: TutorialStepWidget(
        step: currentStep,
        currentIndex: state.currentStepIndex,
        totalSteps: _steps.length,
        onShowMe: () => _handleShowMe(context, currentStep, notifier),
      ),
    );
  }

  /// Build the footer button row. Layout shifts by step position:
  /// - First step: [Skip Forever] [Show on Next Launch] [Next]
  /// - Middle steps: [Skip Forever] [Back] [Next]
  /// - Last step: [Skip Forever] [Back] [Done]
  /// The Skip Forever ghost button is always visible so the user can opt
  /// out at any time; we don't trap them in the wizard.
  List<Widget> _buildActions(
    BuildContext context,
    FirstNightWizardState state,
    FirstNightWizardNotifier notifier,
  ) {
    final l10n = context.l10n;
    return [
      NightshadeButton(
        label: l10n.text('firstNightWizardSkipForever'),
        variant: ButtonVariant.ghost,
        size: ButtonSize.small,
        onPressed: () => _handleSkipForever(context, notifier),
      ),
      const SizedBox(width: 8),
      if (notifier.isFirstStep)
        NightshadeButton(
          label: l10n.text('firstNightWizardShowNextLaunch'),
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => _handleShowOnNextLaunch(context, notifier),
        )
      else
        NightshadeButton(
          label: l10n.text('commonBack'),
          icon: NightshadeIcons.chevronLeft,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => notifier.back(),
        ),
      const SizedBox(width: 8),
      if (notifier.isLastStep)
        NightshadeButton(
          label: l10n.text('commonDone'),
          icon: NightshadeIcons.check,
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: () => _handleDone(context, notifier),
        )
      else
        NightshadeButton(
          label: l10n.text('commonNext'),
          icon: NightshadeIcons.chevronRight,
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: () => notifier.next(),
        ),
    ];
  }

  /// "Show me" deep-link handler. Saves progress (so we resume here when
  /// the wizard is reopened), closes the wizard, then navigates. We
  /// intentionally don't leave the wizard open behind the screen — modal
  /// dialogs over deep-content screens get visually confusing fast.
  void _handleShowMe(
    BuildContext context,
    FirstNightWizardStep step,
    FirstNightWizardNotifier notifier,
  ) {
    if (!step.hasDeepLink) return;
    // Persist that the user is "on" this step so re-opening Settings →
    // Help resumes here.
    notifier.goToStep(step.order);
    Navigator.of(context).pop();
    // Use post-frame to let the dialog pop animation finish before the
    // route change — otherwise the navigator collapse and the go_router
    // push race and the new screen appears half-transitioned.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go(step.deepLinkRoute);
      }
    });
  }

  void _handleSkipForever(
    BuildContext context,
    FirstNightWizardNotifier notifier,
  ) {
    notifier.dismissForever();
    Navigator.of(context).pop();
  }

  void _handleShowOnNextLaunch(
    BuildContext context,
    FirstNightWizardNotifier notifier,
  ) {
    notifier.showOnNextLaunch();
    Navigator.of(context).pop();
  }

  void _handleDone(
    BuildContext context,
    FirstNightWizardNotifier notifier,
  ) {
    notifier.complete();
    Navigator.of(context).pop();
  }
}
