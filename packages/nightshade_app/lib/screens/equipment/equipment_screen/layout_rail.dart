// Part of ../equipment_screen.dart -- extracted for maintainability.
//
// Dashboard header, main responsive layout, status rail, and readiness summary.
part of '../equipment_screen.dart';

// ============================================================================
// Dashboard Header Widget
// ============================================================================

class _DashboardHeader extends StatelessWidget {
  final String? profileName;
  final VoidCallback onSettings;
  final VoidCallback? onProfileTap;

  const _DashboardHeader({
    required this.profileName,
    required this.onSettings,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = onProfileTap != null;
    final horizontalPadding = isMobile ? 12.0 : 20.0;

    Widget profileTitle;
    if (profileName != null) {
      profileTitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.layers, size: 16, color: colors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              profileName!,
              overflow: TextOverflow.ellipsis,
              style:
                  NightshadeTypography.h4.copyWith(color: colors.textPrimary),
            ),
          ),
          if (isMobile) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: colors.textMuted),
          ],
        ],
      );
    } else {
      profileTitle = Text(
        'Select a profile',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize16,
          color: colors.textMuted,
        ),
      );
    }

    if (onProfileTap != null) {
      profileTitle = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onProfileTap,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: profileTitle,
            ),
          ),
        ),
      );
    }

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: profileTitle),
          const SizedBox(width: 8),
          // Wave 4 Recovery Mode — sequencer status LED. Always visible so
          // an operator scanning the Equipment screen knows at a glance
          // whether a sequence is running, paused, or recovering. Pulses
          // red in recovering state.
          const SequencerStatusLed(showLabel: true),
          const SizedBox(width: 12),
          // Connection status summary
          _ConnectionStatusSummary(),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(LucideIcons.settings, size: 18),
            tooltip: 'Equipment Settings',
            color: colors.textMuted,
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Polar alignment entry (Equipment discoverability)
// ============================================================================

/// Compact shortcut so pre-flight hints that mention Equipment can point
/// somewhere real. Shown when the active profile has a mount assigned.
class _PolarAlignmentShortcut extends ConsumerWidget {
  const _PolarAlignmentShortcut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final hasMount = profile?.mountId != null && profile!.mountId!.isNotEmpty;
    if (!hasMount) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(LucideIcons.compass, color: colors.warning, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Polar Alignment',
                      style: NightshadeTypography.labelStrong
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Three-point or all-sky alignment with plate solving.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              NightshadeButton(
                label: 'Open',
                icon: LucideIcons.arrowRight,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => context.push('/polar-alignment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Main column (shared by desktop + mobile)
// ============================================================================

class _EquipmentMainColumn extends StatelessWidget {
  final EquipmentProfileModel? selectedProfile;

  /// When true (desktop), wide layouts move System Health + Ready-to-image into
  /// a right-hand status rail. When false, or when the available width is below
  /// [_railBreakpoint], they stack above the cards as collapsed bars instead.
  final bool allowRail;
  final VoidCallback onSettings;
  final VoidCallback? onProfileTap;
  final void Function(EquipmentProfileModel) onConnectAll;
  final void Function(EquipmentProfileModel) onEditProfile;

  const _EquipmentMainColumn({
    required this.selectedProfile,
    required this.allowRail,
    required this.onSettings,
    required this.onConnectAll,
    required this.onEditProfile,
    this.onProfileTap,
  });

  /// The always-present top chrome: recovery banner, header, dismissable
  /// mismatch banner, and the connect-all progress strip.
  Widget _topChrome() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RunDashboardRecoveryBanner(),
        _DashboardHeader(
          profileName: selectedProfile?.name,
          onSettings: onSettings,
          onProfileTap: onProfileTap,
        ),
        const _ProfileMismatchBanner(),
        const _ConnectAllProgressStrip(),
      ],
    );
  }

  /// The device dashboard (dominant scroll area) plus the Discovery scanner
  /// pinned to the bottom. Shared by both the rail and stacked layouts so the
  /// cards always own the vertical space between the chrome and the scanner.
  Widget _cardsAndDiscovery() {
    return Column(
      children: [
        Expanded(
          child: _DeviceDashboard(
            profile: selectedProfile,
            onConnectAll: onConnectAll,
            onEditProfile: onEditProfile,
          ),
        ),
        const DiscoveryPanel(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = allowRail && constraints.maxWidth >= _railBreakpoint;

        if (showRail) {
          // Wide desktop: cards in the center, supporting panels in the rail.
          return Column(
            children: [
              _topChrome(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _cardsAndDiscovery()),
                    const _EquipmentStatusRail(),
                  ],
                ),
              ),
            ],
          );
        }

        // Narrow / mobile: no rail. Health + readiness collapse to thin bars
        // (collapsed by default) stacked above the cards so they stop eating
        // vertical space until tapped.
        return Column(
          children: [
            _topChrome(),
            const EquipmentHealthPanel(),
            const _ReadinessSummaryBar(),
            const _PolarAlignmentShortcut(),
            Expanded(child: _cardsAndDiscovery()),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Status Rail (desktop, wide screens)
// ============================================================================

/// Right-hand rail holding the supporting panels that previously stacked on top
/// of the device cards: System Health, Ready-to-image, and the Polar Alignment
/// shortcut. Collapses to a thin icon strip (mirroring the left profile
/// sidebar) so an operator who wants every pixel for cards can tuck it away.
class _EquipmentStatusRail extends ConsumerWidget {
  const _EquipmentStatusRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final collapsed = ref.watch(equipmentStatusRailCollapsedProvider);

    if (collapsed) {
      return Container(
        width: _statusRailCollapsedWidth,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(left: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Tooltip(
              message: 'Show status panels',
              child: IconButton(
                icon: Icon(LucideIcons.panelRightOpen,
                    size: 18, color: colors.textSecondary),
                onPressed: () => ref
                    .read(equipmentStatusRailCollapsedProvider.notifier)
                    .state = false,
              ),
            ),
            const SizedBox(height: 4),
            Icon(LucideIcons.heartPulse, size: 16, color: colors.textMuted),
            const SizedBox(height: 12),
            Icon(LucideIcons.listChecks, size: 16, color: colors.textMuted),
          ],
        ),
      );
    }

    return Container(
      width: _statusRailWidth,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rail header with collapse control.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(LucideIcons.activity, size: 16, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Hide status panels',
                  child: IconButton(
                    icon: Icon(LucideIcons.panelRightClose,
                        size: 18, color: colors.textMuted),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ref
                        .read(equipmentStatusRailCollapsedProvider.notifier)
                        .state = true,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          // Scrollable body: the supporting panels, in priority order.
          const Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EquipmentHealthPanel(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: EquipmentReadinessPanel(),
                  ),
                  _PolarAlignmentShortcut(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Readiness summary bar (narrow / mobile collapsed presentation)
// ============================================================================

/// Whether the narrow-layout readiness bar is expanded. Defaults to collapsed
/// so the checklist stops consuming vertical space above the cards until the
/// operator opens it.
final _readinessBarExpandedProvider = StateProvider<bool>((ref) => false);

/// One-line, tappable summary of the readiness report for narrow / mobile
/// layouts. Mirrors [EquipmentHealthPanel]'s collapsed-header pattern: a header
/// row showing the overall state and an outstanding-item count, expanding to
/// the full [EquipmentReadinessPanel] on tap.
class _ReadinessSummaryBar extends ConsumerWidget {
  const _ReadinessSummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final report = ref.watch(readinessReportProvider);
    final expanded = ref.watch(_readinessBarExpandedProvider);
    final outstanding = report.blockedItems.length + report.cautionItems.length;

    final (dotColor, label) = switch (report.overall) {
      ReadinessLevel.ready => (colors.success, 'Ready to image'),
      ReadinessLevel.caution => (colors.warning, 'Ready to image'),
      ReadinessLevel.blocked => (colors.error, 'Not ready'),
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => ref
                .read(_readinessBarExpandedProvider.notifier)
                .state = !expanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(LucideIcons.listChecks,
                      size: 16, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: dotColor),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (outstanding > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: NightshadeDecorations.tintedBadge(
                        dotColor,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline8),
                      ),
                      child: Text(
                        '$outstanding ${outstanding == 1 ? 'item' : 'items'}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
                          fontWeight: FontWeight.w600,
                          color: dotColor,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: EquipmentReadinessPanel(),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DEV-P1-5: Connect-All per-device progress strip
// ============================================================================
