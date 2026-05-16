import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// Note: dismissedTourPromptsProvider is now imported from nightshade_core
// with database persistence for tracking dismissed prompts across app restarts.

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

  const ContextualTourPrompt({
    super.key,
    required this.screenId,
    required this.tourCategory,
    this.title,
    this.description,
    this.durationMinutes = 3,
    this.alignment = Alignment.bottomRight,
    this.offset = const Offset(-16, -16),
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
  final _overlayKey = GlobalKey();
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

    // Check if prompt should be shown after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowPrompt();
    });
  }

  @override
  void dispose() {
    _showDelayTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _checkAndShowPrompt() {
    if (!mounted) return;

    final tutorialState = ref.read(tutorialProvider);
    final dismissedPrompts = ref.read(dismissedTourPromptsProvider);

    // Don't show if:
    // 1. Tutorials are disabled
    // 2. This screen's prompt was already dismissed
    // 3. A tutorial is currently active
    // 4. The relevant tour is already completed
    if (!tutorialState.tutorialsEnabled ||
        dismissedPrompts.contains(widget.screenId) ||
        tutorialState.activeCategory != null ||
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
        ref
            .read(dismissedTourPromptsProvider.notifier)
            .dismissPrompt(widget.screenId);
      }
    });
  }

  void _startTour() {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);
    tutorialNotifier.startTutorial(widget.tourCategory);
    _dismissPrompt();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for changes that might require hiding the prompt
    ref.listen<TutorialProgress>(tutorialProvider, (previous, current) {
      if (current.activeCategory != null && _isVisible) {
        _dismissPrompt();
      }
    });

    return Stack(
      key: _overlayKey,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_isVisible) _buildPrompt(context),
      ],
    );
  }

  Widget _buildPrompt(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

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
          child: _PromptCard(
            title: widget.title ?? 'New to this screen?',
            description: widget.description ??
                'Take a quick ${widget.durationMinutes}-minute tour.',
            colors: colors,
            onDismiss: _dismissPrompt,
            onStartTour: _startTour,
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final String title;
  final String description;
  final NightshadeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback onStartTour;

  const _PromptCard({
    required this.title,
    required this.description,
    required this.colors,
    required this.onDismiss,
    required this.onStartTour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.lightbulb,
                      size: 16,
                      color: colors.info,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              description,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                // Maybe Later button - 48px touch target
                Expanded(
                  child: NightshadeButton(
                    onPressed: onDismiss,
                    label: 'Maybe Later',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.medium,
                  ),
                ),
                const SizedBox(width: 8),

                // Start Tour button - 48px touch target
                NightshadeButton(
                  onPressed: onStartTour,
                  label: 'Start Tour',
                  icon: LucideIcons.arrowRight,
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
      _checkAndShowPrompt();
    });
  }

  @override
  void dispose() {
    _showDelayTimer?.cancel();
    _removeOverlay();
    _animController.dispose();
    super.dispose();
  }

  void _checkAndShowPrompt() {
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

    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
      ref
          .read(dismissedTourPromptsProvider.notifier)
          .dismissPrompt(widget.screenId);
    });
  }

  void _startTour() {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);
    tutorialNotifier.startTutorial(widget.tourCategory);
    _dismissPrompt();
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
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    const promptWidth = 280.0;
    const promptHeight = 160.0;
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

      // Clamp to screen bounds
      if (left != null) {
        left = left.clamp(padding, screenSize.width - promptWidth - padding);
      }
      if (top != null) {
        top = top.clamp(padding, screenSize.height - promptHeight - padding);
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
            ),
          ),
        ),
      ),
    );
  }
}
