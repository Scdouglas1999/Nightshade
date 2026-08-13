import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// Note: dismissedTourPromptsProvider is now imported from nightshade_core
// with database persistence for tracking dismissed prompts across app restarts.

/// Key on the prompt card itself. Exposed so tests can assert that the card's
/// rect does not intersect the content it is anchored over.
const Key contextualTourPromptCardKey = Key('contextualTourPrompt.card');

/// A small, non-intrusive tooltip that appears when user first visits certain screens.
/// Offers to start a contextual tour relevant to the current screen.
class ContextualTourPrompt extends ConsumerStatefulWidget {
  /// Unique identifier for this screen (used to track dismissal).
  final String screenId;

  /// The tutorial category to offer when user accepts.
  final TutorialCategory tourCategory;

  /// Custom title for the prompt (defaults to "New to [Screen]?").
  final String? title;

  /// Custom description (defaults to "Take a quick [duration]-minute tour.").
  final String? description;

  /// Estimated tour duration in minutes.
  final int durationMinutes;

  /// Position of the prompt relative to the anchor.
  final Alignment alignment;

  /// Offset from the alignment position.
  final Offset offset;

  /// The child widget this prompt is attached to.
  final Widget child;

  /// Whether to hold a band of the child's height clear for the card.
  ///
  /// Off, because a coach mark is transient chrome and every other overlay in
  /// this app floats. Reserving the band instead cost each of the seven nudged
  /// screens ~16% of its height on a fresh install: the Sequencer workspace
  /// stopped 147px short with the node palette cut through a card, the
  /// planetarium's sky lost a ~150px strip of flat background, and in Settings
  /// the whole ADVANCED group sat off-screen until a coach mark that never
  /// mentions settings was dismissed. The band snapped back the instant the
  /// card went away, which is what proved it was the cause.
  ///
  /// A host whose bottom-right corner carries live, non-scrollable controls can
  /// still opt in — the trade it makes is losing that band while the nudge is up.
  final bool reserveSpaceForCard;

  const ContextualTourPrompt({
    super.key,
    required this.screenId,
    required this.tourCategory,
    this.title,
    this.description,
    this.durationMinutes = 3,
    this.alignment = Alignment.bottomRight,
    this.offset = const Offset(-16, -16),
    this.reserveSpaceForCard = false,
    required this.child,
  });

  @override
  ConsumerState<ContextualTourPrompt> createState() =>
      _ContextualTourPromptState();
}

class _ContextualTourPromptState extends ConsumerState<ContextualTourPrompt>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isVisible = false;
  bool _isStartingTour = false;
  final _overlayKey = GlobalKey();
  Timer? _showDelayTimer;

  /// Measured size of the prompt card, used to reserve the band it covers.
  Size? _promptSize;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    // Check if prompt should be shown after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkAndShowPrompt());
    });
  }

  @override
  void dispose() {
    _showDelayTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowPrompt() async {
    if (!mounted) return;

    // Wait for the persisted dismissals to load before deciding. Reading them
    // synchronously here is what made a dismissed prompt reappear on every
    // launch: the set is empty until its database read completes.
    await ref.read(dismissedTourPromptsProvider.notifier).ready;
    if (!mounted) return;

    final tutorialState = ref.read(tutorialProvider);
    final dismissedPrompts = ref.read(dismissedTourPromptsProvider);

    // Don't show if:
    // 1. Tutorials are disabled
    // 2. This screen's prompt was already dismissed
    // 3. A tutorial is currently active
    // 4. The relevant tour is already completed
    // 5. The full-screen coach-mark tour is on screen — a per-screen nudge
    //    popping into the corner of a spotlighted walkthrough is two guided
    //    flows competing for the same user at the same moment.
    // 6. The first-night walkthrough is running on the same screen.
    if (!tutorialState.tutorialsEnabled ||
        dismissedPrompts.contains(widget.screenId) ||
        tutorialState.activeCategory != null ||
        _coachMarkTourOnScreen ||
        ref.read(guidedFlowActiveProvider) ||
        _isTourCompleted(tutorialState)) {
      return;
    }

    // Add a small delay before showing. Owned so we can cancel on dispose.
    _showDelayTimer?.cancel();
    _showDelayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isVisible) {
        setState(() => _isVisible = true);
        _animController.forward();
      }
    });
  }

  /// True while [OnboardingTourReplayLauncher] has the full-screen coach-mark
  /// overlay mounted (its gate is this same `pending` status).
  bool get _coachMarkTourOnScreen =>
      ref.read(firstLaunchTourStatusProvider).valueOrNull ==
      FirstLaunchTourStatus.pending;

  /// Take the card off screen without recording a dismissal.
  ///
  /// Distinct from [_dismissPrompt]: the user did not decline this tour, some
  /// other guided flow simply took over the screen, so the offer must survive
  /// to the next visit rather than being spent.
  void _hideForCompetingFlow() {
    _showDelayTimer?.cancel();
    if (!_isVisible) return;
    _animController.reverse().then((_) {
      if (mounted) setState(() => _isVisible = false);
    });
  }

  bool _isTourCompleted(TutorialProgress state) {
    final steps = TutorialDefinitions.getStepsForCategory(widget.tourCategory);
    final completedCount = steps
        .where(
          (step) => state.completedSteps.contains(step.id),
        )
        .length;
    return completedCount >= steps.length;
  }

  void _dismissPrompt() {
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() => _isVisible = false);
        // Remember that this prompt was dismissed (persisted to database)
        unawaited(
          ref
              .read(dismissedTourPromptsProvider.notifier)
              .dismissPrompt(widget.screenId)
              .catchError((Object _) {
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not save the tour prompt preference.',
                  ),
                ),
              );
            }
          }),
        );
      }
    });
  }

  Future<void> _startTour() async {
    if (_isStartingTour) return;
    setState(() => _isStartingTour = true);
    try {
      await ref
          .read(tutorialProvider.notifier)
          .startTutorial(widget.tourCategory);
      // The provider listener dismisses the prompt after the authoritative
      // state becomes active.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not start the tour. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingTour = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for changes that might require hiding the prompt
    ref.listen<TutorialProgress>(tutorialProvider, (previous, current) {
      if (current.activeCategory != null && _isVisible) {
        _dismissPrompt();
      }
    });

    // The coach-mark tour can be started from Settings while this nudge is
    // already on screen. Get out of its way, but keep the offer — the user
    // declined nothing.
    ref.listen<AsyncValue<FirstLaunchTourStatus>>(firstLaunchTourStatusProvider,
        (previous, current) {
      if (current.valueOrNull == FirstLaunchTourStatus.pending) {
        _hideForCompetingFlow();
      }
    });

    // Same for the first-night walkthrough, which can be opened from Settings
    // over a screen already showing this nudge.
    ref.listen<bool>(guidedFlowActiveProvider, (previous, current) {
      if (current) _hideForCompetingFlow();
    });

    // LayoutBuilder because the reserved band has to be capped against the
    // height actually available, which only the parent's constraints know.
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        key: _overlayKey,
        clipBehavior: Clip.none,
        children: [
          // The card floats over the child unless the host opted into the band;
          // see [ContextualTourPrompt.reserveSpaceForCard] for why holding the
          // band was worse than the overlap it prevented.
          Padding(
            padding: _reservedInset(constraints.maxHeight),
            child: widget.child,
          ),
          if (_isVisible) _buildPrompt(context),
        ],
      ),
    );
  }

  /// The largest share of the host's height this nudge may reserve.
  ///
  /// Without a cap the band is whatever the card measures, and the card's height
  /// is driven by how far its copy wraps — so on a short viewport it can exceed
  /// the viewport itself. It did: squeezed to 64px (a landscape phone whose
  /// shell has handed most of the height to the keyboard) the card measured
  /// 203px, the child was laid out at zero height, and EVERY control on the
  /// screen — including the settings search field — stopped hit-testing. A
  /// dismissible suggestion must never be able to take the screen away.
  static const double _maxReservedFraction = 0.4;

  /// Space held clear for the prompt card on the edge it is anchored to,
  /// clamped so content always keeps the majority of [availableHeight].
  EdgeInsets _reservedInset(double availableHeight) {
    if (!widget.reserveSpaceForCard || !_isVisible) return EdgeInsets.zero;
    final height = _promptSize?.height;
    if (height == null) return EdgeInsets.zero;
    // The card is offset from the edge by the alignment offset; leave a small
    // gap between it and the content it used to overlap.
    final wanted = height + widget.offset.dy.abs() + 8;
    // All-or-nothing, not a partial band. Reserving *some* of what the card
    // needs is the worst of both worlds: the card still overlaps content AND
    // the content is squeezed. Over the cap, drop the reservation entirely and
    // let the card float, exactly as it did before the band existed.
    final fits = !availableHeight.isFinite ||
        wanted <= availableHeight * _maxReservedFraction;
    final band = fits ? wanted : 0.0;
    return switch (widget.alignment) {
      Alignment.topLeft || Alignment.topRight => EdgeInsets.only(top: band),
      _ => EdgeInsets.only(bottom: band),
    };
  }

  Widget _buildPrompt(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Positioned(
      left: widget.alignment == Alignment.bottomLeft ||
              widget.alignment == Alignment.topLeft
          ? widget.offset.dx
          : null,
      right: widget.alignment == Alignment.bottomRight ||
              widget.alignment == Alignment.topRight
          ? -widget.offset.dx
          : null,
      top: widget.alignment == Alignment.topLeft ||
              widget.alignment == Alignment.topRight
          ? widget.offset.dy
          : null,
      bottom: widget.alignment == Alignment.bottomLeft ||
              widget.alignment == Alignment.bottomRight
          ? -widget.offset.dy
          : null,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: _MeasureSize(
            onChange: (size) {
              if (!mounted || _promptSize == size) return;
              setState(() => _promptSize = size);
            },
            child: _PromptCard(
              title: widget.title ?? 'New to this screen?',
              description: widget.description ??
                  'Take a quick ${widget.durationMinutes}-minute tour.',
              colors: colors,
              onDismiss: _dismissPrompt,
              onStartTour: _startTour,
              isStartingTour: _isStartingTour,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's laid-out size, so the prompt can reserve exactly the
/// band the card occupies instead of guessing a constant that drifts whenever
/// the copy or the type ramp changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  _RenderMeasureSize createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final current = size;
    if (_reported == current) return;
    _reported = current;
    // Reporting during layout would mutate the tree mid-pass; defer a frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => onChange(current));
  }
}

class _PromptCard extends StatelessWidget {
  final String title;
  final String description;
  final NightshadeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback onStartTour;
  final bool isStartingTour;

  const _PromptCard({
    required this.title,
    required this.description,
    required this.colors,
    required this.onDismiss,
    required this.onStartTour,
    required this.isStartingTour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: contextualTourPromptCardKey,
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: NightshadeTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    onPressed: isStartingTour ? null : onDismiss,
                    label: 'Maybe Later',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  onPressed: isStartingTour ? null : onStartTour,
                  label: 'Start Tour',
                  icon: LucideIcons.arrowRight,
                  size: ButtonSize.small,
                  isLoading: isStartingTour,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A variant that positions itself as an overlay at a specific global position.
/// Useful for attaching prompts near specific UI elements.
class ContextualTourPromptOverlay extends ConsumerStatefulWidget {
  /// Unique identifier for this screen (used to track dismissal).
  final String screenId;

  /// The tutorial category to offer when user accepts.
  final TutorialCategory tourCategory;

  /// Custom title for the prompt.
  final String? title;

  /// Custom description.
  final String? description;

  /// Estimated tour duration in minutes.
  final int durationMinutes;

  /// GlobalKey of the target widget to position near.
  final GlobalKey? targetKey;

  /// Preferred position relative to the target.
  final TooltipPosition preferredPosition;

  const ContextualTourPromptOverlay({
    super.key,
    required this.screenId,
    required this.tourCategory,
    this.title,
    this.description,
    this.durationMinutes = 3,
    this.targetKey,
    this.preferredPosition = TooltipPosition.bottom,
  });

  @override
  ConsumerState<ContextualTourPromptOverlay> createState() =>
      _ContextualTourPromptOverlayState();
}

class _ContextualTourPromptOverlayState
    extends ConsumerState<ContextualTourPromptOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  OverlayEntry? _overlayEntry;
  bool _hasShown = false;
  bool _isStartingTour = false;
  Timer? _showDelayTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkAndShowPrompt());
    });
  }

  @override
  void dispose() {
    _showDelayTimer?.cancel();
    _removeOverlay();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowPrompt() async {
    if (!mounted || _hasShown) return;

    // See the sibling widget: the dismissal set loads asynchronously, so a
    // synchronous read here always reports nothing dismissed.
    await ref.read(dismissedTourPromptsProvider.notifier).ready;
    if (!mounted || _hasShown) return;

    final tutorialState = ref.read(tutorialProvider);
    final dismissedPrompts = ref.read(dismissedTourPromptsProvider);

    if (!tutorialState.tutorialsEnabled ||
        dismissedPrompts.contains(widget.screenId) ||
        tutorialState.activeCategory != null ||
        _isTourCompleted(tutorialState)) {
      return;
    }

    _hasShown = true;
    // Owned so we can cancel on dispose.
    _showDelayTimer?.cancel();
    _showDelayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _showOverlay();
      }
    });
  }

  bool _isTourCompleted(TutorialProgress state) {
    final steps = TutorialDefinitions.getStepsForCategory(widget.tourCategory);
    final completedCount = steps
        .where(
          (step) => state.completedSteps.contains(step.id),
        )
        .length;
    return completedCount >= steps.length;
  }

  void _showOverlay() {
    _removeOverlay();

    final colors = NightshadeColors.of(context);
    Rect? targetRect;

    if (widget.targetKey?.currentContext != null) {
      final renderBox =
          widget.targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        targetRect = Rect.fromLTWH(
          position.dx,
          position.dy,
          renderBox.size.width,
          renderBox.size.height,
        );
      }
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _OverlayPrompt(
        targetRect: targetRect,
        preferredPosition: widget.preferredPosition,
        title: widget.title ?? 'New to this screen?',
        description: widget.description ??
            'Take a quick ${widget.durationMinutes}-minute tour.',
        colors: colors,
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
        onDismiss: _dismissPrompt,
        onStartTour: _startTour,
        isStartingTour: _isStartingTour,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _animController.forward();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _dismissPrompt() {
    _animController.reverse().then((_) {
      _removeOverlay();
      // Remember that this prompt was dismissed (persisted to database)
      unawaited(
        ref
            .read(dismissedTourPromptsProvider.notifier)
            .dismissPrompt(widget.screenId)
            .catchError((Object _) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Could not save the tour prompt preference.'),
              ),
            );
          }
        }),
      );
    });
  }

  Future<void> _startTour() async {
    if (_isStartingTour) return;
    _isStartingTour = true;
    _overlayEntry?.markNeedsBuild();
    try {
      await ref
          .read(tutorialProvider.notifier)
          .startTutorial(widget.tourCategory);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not start the tour. Please try again.'),
          ),
        );
      }
    } finally {
      _isStartingTour = false;
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for changes that might require hiding the prompt
    ref.listen<TutorialProgress>(tutorialProvider, (previous, current) {
      if (current.activeCategory != null && _overlayEntry != null) {
        _dismissPrompt();
      }
    });

    return const SizedBox.shrink();
  }
}

class _OverlayPrompt extends StatelessWidget {
  final Rect? targetRect;
  final TooltipPosition preferredPosition;
  final String title;
  final String description;
  final NightshadeColors colors;
  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final VoidCallback onDismiss;
  final VoidCallback onStartTour;
  final bool isStartingTour;

  const _OverlayPrompt({
    this.targetRect,
    required this.preferredPosition,
    required this.title,
    required this.description,
    required this.colors,
    required this.fadeAnimation,
    required this.slideAnimation,
    required this.onDismiss,
    required this.onStartTour,
    required this.isStartingTour,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    const promptWidth = 240.0;
    const promptHeight = 140.0;
    const padding = 16.0;

    double? left, top, right, bottom;

    if (targetRect == null) {
      // Default to bottom-right corner
      right = padding;
      bottom = padding;
    } else {
      switch (preferredPosition) {
        case TooltipPosition.bottom:
          left = (targetRect!.left + targetRect!.right - promptWidth) / 2;
          top = targetRect!.bottom + padding;
          break;
        case TooltipPosition.top:
          left = (targetRect!.left + targetRect!.right - promptWidth) / 2;
          bottom = screenSize.height - targetRect!.top + padding;
          break;
        case TooltipPosition.left:
          right = screenSize.width - targetRect!.left + padding;
          top = targetRect!.top;
          break;
        case TooltipPosition.right:
          left = targetRect!.right + padding;
          top = targetRect!.top;
          break;
        case TooltipPosition.center:
          left = (screenSize.width - promptWidth) / 2;
          top = (screenSize.height - promptHeight) / 2;
          break;
      }

      // Clamp to screen bounds. The far edge is floored at the near one so a
      // viewport too small to hold the prompt plus both margins pins it to the
      // near edge (and clips) instead of inverting the clamp and throwing —
      // this prompt is mounted over most screens, so a throw here blanks them.
      if (left != null) {
        final maxLeft = math.max(
          padding,
          screenSize.width - promptWidth - padding,
        );
        left = left.clamp(padding, maxLeft);
      }
      if (top != null) {
        final maxTop = math.max(
          padding,
          screenSize.height - promptHeight - padding,
        );
        top = top.clamp(padding, maxTop);
      }
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(
          position: slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: _PromptCard(
              title: title,
              description: description,
              colors: colors,
              onDismiss: onDismiss,
              onStartTour: onStartTour,
              isStartingTour: isStartingTour,
            ),
          ),
        ),
      ),
    );
  }
}
