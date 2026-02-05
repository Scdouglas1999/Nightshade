import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Full-screen welcome widget shown on true first launch.
/// Provides three options: Quick Start Tour, Explore on My Own, or Skip All Tutorials.
class WelcomeFlow extends ConsumerStatefulWidget {
  /// Callback invoked when the user completes the welcome flow.
  final VoidCallback onComplete;

  const WelcomeFlow({
    super.key,
    required this.onComplete,
  });

  @override
  ConsumerState<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends ConsumerState<WelcomeFlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

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
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
      ),
    );

    // Start animation after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleQuickStartTour() async {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);

    // Start the firstLight tutorial (Quick Start)
    tutorialNotifier.startTutorial(TutorialCategory.firstLight);
    tutorialNotifier.markInitialTourSeen();

    await _animateOut();
    widget.onComplete();
  }

  Future<void> _handleExploreOnMyOwn() async {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);

    // Mark as seen but keep tutorials enabled for contextual tips
    tutorialNotifier.markInitialTourSeen();

    await _animateOut();
    widget.onComplete();
  }

  Future<void> _handleSkipAllTutorials() async {
    final tutorialNotifier = ref.read(tutorialProvider.notifier);

    // Disable all tutorials and mark as seen
    tutorialNotifier.setTutorialsEnabled(false);
    tutorialNotifier.markInitialTourSeen();

    await _animateOut();
    widget.onComplete();
  }

  Future<void> _animateOut() async {
    await _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          color: colors.background,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with telescope icon
                      _WelcomeHeader(colors: colors),
                      const SizedBox(height: 40),

                      // Quick Start Tour option
                      _WelcomeOption(
                        icon: LucideIcons.star,
                        title: 'Quick Start Tour',
                        subtitle: 'Recommended',
                        description:
                            'Connect your camera and capture your first image in about 3 minutes.',
                        buttonText: 'Start Tour',
                        buttonIcon: LucideIcons.arrowRight,
                        isPrimary: true,
                        colors: colors,
                        onPressed: _handleQuickStartTour,
                      ),
                      const SizedBox(height: 16),

                      // Explore on My Own option
                      _WelcomeOption(
                        icon: LucideIcons.compass,
                        title: 'Explore on My Own',
                        description:
                            'Jump right in. Contextual tips will appear as you discover new features.',
                        buttonText: "Let's Go",
                        buttonIcon: LucideIcons.arrowRight,
                        isPrimary: false,
                        colors: colors,
                        onPressed: _handleExploreOnMyOwn,
                      ),
                      const SizedBox(height: 16),

                      // Skip All Tutorials option
                      _WelcomeOption(
                        icon: LucideIcons.zap,
                        title: "I've Used Nightshade Before",
                        description:
                            'Skip all tutorials and dive straight in.',
                        buttonText: 'Skip',
                        buttonIcon: LucideIcons.arrowRight,
                        isPrimary: false,
                        colors: colors,
                        onPressed: _handleSkipAllTutorials,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _WelcomeHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Telescope icon container
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              LucideIcons.scan,
              size: 40,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Welcome text
        Text(
          'Welcome to Nightshade',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),

        // Subtitle
        Text(
          'Your Astrophotography Suite',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _WelcomeOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String description;
  final String buttonText;
  final IconData buttonIcon;
  final bool isPrimary;
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _WelcomeOption({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.description,
    required this.buttonText,
    required this.buttonIcon,
    required this.isPrimary,
    required this.colors,
    required this.onPressed,
  });

  @override
  State<_WelcomeOption> createState() => _WelcomeOptionState();
}

class _WelcomeOptionState extends State<_WelcomeOption> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isPrimary = widget.isPrimary;

    final borderColor = isPrimary
        ? colors.primary.withValues(alpha: _isHovered ? 0.8 : 0.5)
        : colors.border.withValues(alpha: _isHovered ? 0.8 : 1.0);

    final backgroundColor = isPrimary
        ? colors.primary.withValues(alpha: _isHovered ? 0.12 : 0.08)
        : colors.surfaceAlt.withValues(alpha: _isHovered ? 1.0 : 0.8);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isPrimary ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? colors.primary.withValues(alpha: 0.2)
                          : colors.surfaceHover,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: isPrimary ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row with optional subtitle
                        Row(
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Description
                        Text(
                          widget.description,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Button
                  _WelcomeButton(
                    text: widget.buttonText,
                    icon: widget.buttonIcon,
                    isPrimary: isPrimary,
                    colors: colors,
                    onPressed: widget.onPressed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool isPrimary;
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _WelcomeButton({
    required this.text,
    required this.icon,
    required this.isPrimary,
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeButton(
      onPressed: onPressed,
      label: text,
      icon: icon,
      variant: isPrimary ? ButtonVariant.primary : ButtonVariant.outline,
    );
  }
}
