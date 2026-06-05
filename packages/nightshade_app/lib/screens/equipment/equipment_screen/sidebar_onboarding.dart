// Part of ../equipment_screen.dart -- extracted for maintainability.
//
// Collapsible sidebar, first-time onboarding, setup steps, and mismatch banner.
part of '../equipment_screen.dart';

// ============================================================================
// Collapsible Sidebar Widget
// ============================================================================

class _CollapsibleSidebar extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsibleSidebar({
    required this.isCollapsed,
    required this.onToggle,
    required this.child,
  });

  @override
  State<_CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<_CollapsibleSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;
  double _currentExpandedWidth = _sidebarExpandedWidth;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _updateAnimation();
    if (!widget.isCollapsed) {
      _animationController.value = 1.0;
    }
  }

  void _updateAnimation() {
    _widthAnimation = Tween<double>(
      begin: _sidebarCollapsedWidth,
      end: _currentExpandedWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_CollapsibleSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCollapsed != widget.isCollapsed) {
      if (widget.isCollapsed) {
        _animationController.reverse();
      } else {
        _updateAnimation();
        _animationController.forward();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        final width = _widthAnimation.value;
        final isEffectivelyCollapsed = width < _sidebarCollapsedWidth + 20;

        if (isEffectivelyCollapsed) {
          // Collapsed state - show icon button strip
          return Container(
            width: _sidebarCollapsedWidth,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                right: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Show Profiles',
                  child: IconButton(
                    icon: Icon(
                      LucideIcons.layers,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    onPressed: widget.onToggle,
                  ),
                ),
              ],
            ),
          );
        }

        // Expanded state - show resizable panel with content
        return SizedBox(
          width: width,
          child: ResizablePanel(
            initialWidth: width,
            minWidth: _sidebarMinWidth,
            maxWidth: _sidebarMaxWidth,
            side: ResizeSide.right,
            onWidthChanged: (newWidth) {
              setState(() {
                _currentExpandedWidth = newWidth;
                _updateAnimation();
              });
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ============================================================================
// First-Time User Onboarding
// ============================================================================

class _FirstTimeOnboarding extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onStartSetup;
  final VoidCallback onManualSetup;

  const _FirstTimeOnboarding({
    required this.colors,
    required this.onStartSetup,
    required this.onManualSetup,
  });

  @override
  Widget build(BuildContext context) {
    // Tighter padding on a phone, and the whole panel scrolls so the welcome
    // steps + both CTAs never overflow a short phone viewport (e.g. 360x640 or
    // a phone in landscape, where the content is taller than the screen).
    final isPhone = Responsive.isPhone(context);
    final pad = isPhone ? 24.0 : 48.0;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: EdgeInsets.all(pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.moon,
              size: NightshadeTokens.iconXl,
              color: colors.primary,
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            Text(
              'Welcome to Nightshade',
              style: NightshadeTypography.h2.copyWith(
                color: colors.textPrimary,
              ),
            ),

            const SizedBox(height: NightshadeTokens.spaceSm),

            Text(
              "Let's set up your first equipment profile",
              style: NightshadeTypography.body.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 40),

            // Setup steps
            NightshadeCard(
              variant: CardVariant.standard,
              borderRadius: NightshadeTokens.radiusInline8,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _SetupStep(
                    number: '1',
                    text: "We'll scan for connected equipment",
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  _SetupStep(
                    number: '2',
                    text: 'Select the devices you want to use',
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  _SetupStep(
                    number: '3',
                    text: 'Save as a profile for one-click connection',
                    colors: colors,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label: 'Start Setup',
                icon: LucideIcons.arrowRight,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
                onPressed: onStartSetup,
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: onManualSetup,
                label: "I'll do it manually",
                variant: ButtonVariant.outline,
                size: ButtonSize.medium,
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final String number;
  final String text;
  final NightshadeColors colors;

  const _SetupStep({
    required this.number,
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: NightshadeDecorations.kpiBadge(
            colors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: NightshadeTypography.labelStrong.copyWith(color: colors.primary),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMismatchBanner extends ConsumerWidget {
  const _ProfileMismatchBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) return const SizedBox.shrink();

    // The per-device mismatch derivation is owned by the canonical
    // `profileConnectionStatusProvider` (single source of truth). The banner's
    // stricter rule — flag a slot only when both sides have a non-empty id and
    // they differ after PHD2-canonical collapse — lives in
    // `ProfileDeviceConnection.isMismatch`, so the same PHD2 guider recorded
    // under any representation is never reported as a mismatch here.
    final status = ref.watch(profileConnectionStatusProvider(activeProfile));
    final mismatches = status.mismatchedDeviceNames;

    if (mismatches.isEmpty) return const SizedBox.shrink();

    // Session-dismiss: hide when the user has dismissed *this exact* mismatch
    // set. Re-keying by the sorted device list means a newly-introduced
    // mismatch re-surfaces the banner rather than staying silently hidden.
    final signature = (mismatches.toList()..sort()).join('|');
    final dismissedSignature = ref.watch(dismissedMismatchSignatureProvider);
    if (dismissedSignature == signature) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
      color: colors.warning.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: colors.warning, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Device Mismatch: The connected ${mismatches.join(", ")} '
              '${mismatches.length == 1 ? 'does' : 'do'} not match the '
              'assignments in the active profile "${activeProfile.name}".',
              style: NightshadeTypography.labelSm.copyWith(color: colors.warning),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => ref
                .read(dismissedMismatchSignatureProvider.notifier)
                .state = signature,
            icon: const Icon(LucideIcons.x, size: 14),
            color: colors.warning,
            tooltip: 'Dismiss for this session',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
