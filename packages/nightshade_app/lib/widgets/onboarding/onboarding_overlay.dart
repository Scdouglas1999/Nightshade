import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        OnboardingTourNotifier,
        onboardingTourProvider,
        onboardingTourCoreStepCount;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../tutorial_overlay.dart' show TutorialKeys;
import 'onboarding_cutout_painter.dart';
import 'onboarding_steps.dart';
import 'onboarding_tooltip_card.dart';

/// First-launch onboarding tour overlay.
///
/// Renders a full-screen dim scrim with a transparent cutout around the
/// current step's target widget, plus a tooltip card explaining what the
/// region does. The overlay is mounted by [OnboardingTourLauncher] at the
/// app shell level so it sits above every screen and stays visible across
/// navigation. It only mounts when the persistence layer says the user
/// hasn't completed or skipped the tour — the launcher handles that gate.
///
/// Skip semantics: clicking Skip or pressing Escape calls
/// [OnboardingTourNotifier.skip], which persists a "dismissed" row distinct
/// from "completed". Tapping the scrim does NOT — it is absorbed (see the
/// scrim's own note). Why distinct: so
/// a future "rerun on major version bump" feature can still target
/// users who skipped the tour but never explicitly finished it, without
/// re-prompting users who saw the full flow.
class OnboardingOverlay extends ConsumerStatefulWidget {
  /// Override step list for testing. Production code always passes null
  /// to use the built-in [_buildSteps] result.
  final List<OnboardingStep>? stepsOverride;

  const OnboardingOverlay({super.key, this.stepsOverride});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  final FocusNode _focusNode = FocusNode();
  _TerminalAction? _terminalAction;

  Future<void> _runTerminalAction(
    _TerminalAction action,
    Future<void> Function() operation,
  ) async {
    if (_terminalAction != null) return;
    setState(() => _terminalAction = action);
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save tour progress. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _terminalAction = null);
    }
  }

  void _skip() {
    final notifier = ref.read(onboardingTourProvider.notifier);
    unawaited(_runTerminalAction(_TerminalAction.skip, notifier.skip));
  }

  void _complete() {
    final notifier = ref.read(onboardingTourProvider.notifier);
    unawaited(_runTerminalAction(_TerminalAction.complete, notifier.complete));
  }

  @override
  void initState() {
    super.initState();
    // Request focus next frame so keyboard shortcuts (Escape) work as
    // soon as the overlay paints. Doing it inline would race the route
    // transition and lose focus to whatever the navigator just pushed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
      // Trigger one more rebuild after the first frame so any side-nav
      // entries that animated in have their GlobalKeys mounted. Without
      // this, the first step's target rect can resolve to null on the
      // initial paint when the user lands on a cold app launch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Build the canonical 7-step onboarding tour (welcome + 5 navigation
  /// stops + completion card). The optional defect-map step is appended
  /// by the notifier when the user unlocks it.
  List<OnboardingStep> _buildSteps() {
    return [
      OnboardingStep(
        id: 'welcome',
        title: 'Welcome to Nightshade',
        body: 'Nightshade is your imaging assistant. Three things to set up '
            'first: equipment, a profile, and a sequence. The next few '
            'steps will show you where each lives.',
        targetKey: () => null,
      ),
      OnboardingStep(
        id: 'equipment',
        title: 'Connect your gear',
        // Scoped to what the support matrix in README.md actually claims.
        // This used to promise "12 vendor SDKs natively, so most drivers work
        // without any setup" — two falsehoods in the first thing a new user
        // reads: the count drifts with the bindings, and the native paths are
        // *gated* on vendor libraries the installer deliberately does not
        // redistribute. A first-nighter who trusted "no setup" would find the
        // native camera path unable to load its SDK, in the dark.
        body: 'Connect your camera, mount, and filter wheel here. ASCOM '
            '(Windows), INDI, and Alpaca work against drivers you already '
            'have. Native vendor paths (ZWO, QHY, Player One, SVBony, Atik, '
            'FLI, Moravian, Touptek) need that vendor\'s own library '
            'installed — Nightshade does not ship it.',
        targetKey: () => TutorialKeys.navEquipment,
      ),
      OnboardingStep(
        id: 'profiles',
        title: 'Save it as a profile',
        body: 'A profile saves your full equipment + framing + filter offset '
            'setup so you can switch between scopes in one click. Profiles '
            'live inside the Equipment screen.',
        targetKey: () => TutorialKeys.navEquipment,
      ),
      OnboardingStep(
        id: 'sequencer',
        // Version stamps go stale silently: this said "v2.6.0 ships sample
        // sequences" to users running 6.x. Point at where the templates live
        // instead — that stays true across releases.
        title: 'Build a sequence',
        body: 'Build automated imaging sequences here. The Templates tab has '
            'ready-made starting points for narrowband, LRGB, mosaics, and '
            'lunar work — load one and customize.',
        targetKey: () => TutorialKeys.navSequencer,
      ),
      OnboardingStep(
        id: 'scheduler',
        // Names the SCREEN, not a tab. The previous copy pointed at a "Target
        // Queue tab" that no longer exists: `plannerTabTargetQueue` is still in
        // translations.dart but is referenced by no code, because Target Queue
        // and This Week were unified into Schedule. A tour that names a tab the
        // user cannot find is worse than a vaguer one that stays true — the
        // same reason the sequencer step above points at Templates generally.
        title: 'Let the scheduler pick targets',
        body: 'Plan Tonight ranks what is worth imaging and when, using each '
            "target's altitude through the night and the time you actually "
            'have before dawn.',
        targetKey: () => TutorialKeys.navPlanner,
      ),
      OnboardingStep(
        id: 'plate_solving',
        title: 'Set up plate solving',
        body: 'Plate solving needs ASTAP or Astrometry.net installed. Set it '
            'up under Settings → Plate Solving — Nightshade auto-detects '
            'standard install paths.',
        targetKey: () => TutorialKeys.navSettings,
      ),
      OnboardingStep(
        id: 'completion',
        title: "You're set",
        body: 'Run the tour again any time from Settings → Help & Tutorials. '
            'Defect maps are also worth a look if you have hot pixels — '
            'see the optional step below.',
        targetKey: () => null,
      ),
      // Optional: only included in the tour after the user clicks "Show
      // me about defect maps" on the completion card. The notifier sets
      // [defectMapStepUnlocked] which expands totalSteps to include this
      // entry.
      OnboardingStep(
        id: 'defect_maps',
        title: 'Defect maps and calibration',
        body: "Open the Imaging screen's Image Calibration section to build "
            'a defect map. Nightshade flags hot, cold, and stuck pixels '
            'from a stack of bias frames so they get masked at capture '
            'time instead of polluting your stack.',
        targetKey: () => TutorialKeys.navImaging,
      ),
    ];
  }

  Rect? _resolveTargetRect(GlobalKey? key) {
    if (key?.currentContext == null) return null;
    final box = key!.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
        topLeft.dx, topLeft.dy, box.size.width, box.size.height);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final notifier = ref.read(onboardingTourProvider.notifier);
    if (_terminalAction != null) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _skip();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (notifier.isLastStep) {
        _complete();
      } else {
        notifier.next();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      notifier.back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final notifier = ref.watch(onboardingTourProvider.notifier);
    // Watch the int state so the overlay rebuilds when the step changes.
    ref.watch(onboardingTourProvider);

    final allSteps = widget.stepsOverride ?? _buildSteps();
    // Without the optional defect-map step, only the first
    // onboardingTourCoreStepCount steps participate. With it unlocked,
    // the final element joins the tour.
    final activeSteps = notifier.defectMapStepUnlocked
        ? allSteps
        : allSteps.sublist(0, onboardingTourCoreStepCount);

    if (notifier.currentStepIndex >= activeSteps.length) {
      // Defensive: if the notifier somehow points past the end, just
      // dismiss. Errors are a feature, but a tour misalignment shouldn't
      // wedge the app — write skip so the user isn't stuck.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _skip();
        }
      });
      return const SizedBox.shrink();
    }

    final step = activeSteps[notifier.currentStepIndex];
    final targetRect = _resolveTargetRect(step.targetKey());
    final screenSize = MediaQuery.sizeOf(context);

    final isWelcome = notifier.currentStepIndex == 0;
    // The completion card is the last core step (index 6) when the
    // optional defect-map step hasn't been unlocked. Once it's unlocked,
    // the completion card sits one step earlier and the defect-map step
    // takes over the "Done" role at the very end.
    final isCompletionCard =
        notifier.currentStepIndex == onboardingTourCoreStepCount - 1 &&
            !notifier.defectMapStepUnlocked;
    final isOptionalDefectStep = notifier.defectMapStepUnlocked &&
        notifier.currentStepIndex == notifier.totalSteps - 1;
    final showDoneButton = isCompletionCard || isOptionalDefectStep;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Semantics(
        label: 'Nightshade onboarding tour, step '
            '${notifier.currentStepIndex + 1} of ${notifier.totalSteps}',
        hint: 'Press Enter for next step, Backspace for previous, '
            'Escape to skip',
        child: Stack(
          children: [
            // The dim scrim + cutout. The GestureDetector ABSORBS taps on the
            // dim area — it does not treat them as a Skip.
            //
            // It used to skip, and that combination cost the operator a click
            // AND the tour: "Reset All Progress" re-arms this tour, so the
            // first click after confirming the reset (the nav rail, in the
            // live drive) landed on a scrim the operator had not asked for.
            // The click did nothing, the tour vanished before the next
            // screenshot, and a second identical click was needed to navigate
            // — leaving no trace of why. A modal that stays on screen explains
            // itself; Escape and the explicit Skip button still leave it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(
                  painter: OnboardingCutoutPainter(
                    targetRect: targetRect,
                    padding: step.padding,
                    cornerRadius: 10,
                    dimColor: colors.background.withValues(alpha: 0.82),
                    borderColor: colors.primary.withValues(alpha: 0.8),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            OnboardingTooltipCard(
              title: step.title,
              body: step.body,
              currentIndex: notifier.currentStepIndex,
              totalSteps: notifier.totalSteps,
              targetRect: targetRect,
              screenSize: screenSize,
              primaryLabel: isWelcome ? 'Show me around' : 'Next',
              isBusy: _terminalAction != null,
              isSkipping: _terminalAction == _TerminalAction.skip,
              isCompleting: _terminalAction == _TerminalAction.complete,
              // Welcome card uses its secondary button for skip and hides
              // the ghost Skip; every other step shows the ghost so the
              // user can opt out at any time.
              onSkip: isWelcome ? null : _skip,
              onBack: notifier.isFirstStep ? null : () => notifier.back(),
              onNext: showDoneButton ? null : () => notifier.next(),
              onDone: showDoneButton ? _complete : null,
              secondaryLabel: isWelcome
                  ? "Skip — I know what I'm doing"
                  : isCompletionCard
                      ? 'Show me about defect maps'
                      : null,
              onSecondary: isWelcome
                  ? _skip
                  : isCompletionCard
                      ? () => notifier.unlockDefectMapStep()
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

enum _TerminalAction { skip, complete }
