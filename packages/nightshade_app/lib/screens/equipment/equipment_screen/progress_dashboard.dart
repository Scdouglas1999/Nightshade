// Part of ../equipment_screen.dart -- extracted for maintainability.
//
// Connect-all progress UI, connection summary, and device dashboard.
part of '../equipment_screen.dart';

/// Renders one chip per device-type tracked by
/// [deviceConnectionProgressProvider]. Each chip shows the device icon, a
/// status indicator (idle/connecting/connected/failed), and a tooltip with
/// the backend error message when the connect attempt failed.
///
/// The strip hides itself completely when no sweep has been run yet (the
/// provider state is empty). After a sweep completes the chips remain
/// visible until [DeviceConnectionProgressNotifier.clear] is called, so the
/// user can review what failed without having to re-run "Connect All".
class _ConnectAllProgressStrip extends ConsumerWidget {
  const _ConnectAllProgressStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(deviceConnectionProgressProvider);

    if (state.byDeviceType.isEmpty) {
      return const SizedBox.shrink();
    }

    // Stable canonical ordering matching the connectAllFromProfile dispatch
    // order so chips don't jitter between rebuilds.
    const order = <String>[
      'camera',
      'mount',
      'focuser',
      'filter wheel',
      'guider',
      'rotator',
      'dome',
      'weather station',
      'safety monitor',
      'cover calibrator',
    ];

    final entries = <DeviceConnectProgress>[
      for (final type in order)
        if (state.byDeviceType.containsKey(type)) state.byDeviceType[type]!,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              state.isSweeping ? 'Connecting…' : '${state.source} result',
              style: NightshadeTypography.labelStrongSm
                  .copyWith(color: colors.textSecondary),
            ),
          ),
          for (final event in entries)
            _ConnectAllProgressChip(event: event, colors: colors),
          if (!state.isSweeping)
            NightshadeButton(
              label: 'Clear',
              size: ButtonSize.small,
              variant: ButtonVariant.ghost,
              onPressed: () =>
                  ref.read(deviceConnectionProgressProvider.notifier).clear(),
            ),
        ],
      ),
    );
  }
}

class _ConnectAllProgressChip extends StatelessWidget {
  final DeviceConnectProgress event;
  final NightshadeColors colors;

  const _ConnectAllProgressChip({
    required this.event,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _statusVisuals(event.status, colors);
    final iconForType = _iconForDeviceType(event.deviceType);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForType, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            event.deviceType,
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: 6),
          if (event.status == DeviceConnectProgressStatus.connecting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: NightshadeTypography.labelStrongSm.copyWith(color: color),
          ),
        ],
      ),
    );

    if (event.status == DeviceConnectProgressStatus.failed &&
        event.errorMessage != null) {
      return Tooltip(
        message: event.errorMessage!,
        waitDuration: const Duration(milliseconds: 200),
        child: chip,
      );
    }
    return chip;
  }

  static (IconData, Color, String) _statusVisuals(
      DeviceConnectProgressStatus status, NightshadeColors colors) {
    switch (status) {
      case DeviceConnectProgressStatus.connecting:
        return (LucideIcons.loader, colors.warning, 'Connecting');
      case DeviceConnectProgressStatus.connected:
        return (LucideIcons.checkCircle, colors.success, 'Connected');
      case DeviceConnectProgressStatus.failed:
        return (LucideIcons.xCircle, colors.error, 'Failed');
    }
  }

  static IconData _iconForDeviceType(String deviceType) {
    switch (deviceType) {
      case 'camera':
        return LucideIcons.camera;
      case 'mount':
        return LucideIcons.compass;
      case 'focuser':
        return LucideIcons.focus;
      case 'filter wheel':
        return LucideIcons.circle;
      case 'guider':
        return LucideIcons.crosshair;
      case 'rotator':
        return LucideIcons.rotateCw;
      case 'dome':
        return LucideIcons.home;
      case 'weather station':
        return LucideIcons.cloudSun;
      case 'safety monitor':
        return LucideIcons.shieldCheck;
      case 'cover calibrator':
        return LucideIcons.lamp;
      default:
        return LucideIcons.circle;
    }
  }
}

// ============================================================================
// Connection Status Summary Widget
// ============================================================================

class _ConnectionStatusSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final domeState = ref.watch(domeStateProvider);
    final weatherState = ref.watch(weatherStateProvider);
    final safetyMonitorState = ref.watch(safetyMonitorStateProvider);
    final switchState = ref.watch(switchStateProvider);
    final coverCalibratorState = ref.watch(coverCalibratorStateProvider);

    final connectionStates = [
      cameraState.connectionState,
      mountState.connectionState,
      focuserState.connectionState,
      filterWheelState.connectionState,
      guiderState.connectionState,
      rotatorState.connectionState,
      domeState.connectionState,
      weatherState.connectionState,
      safetyMonitorState.connectionState,
      switchState.connectionState,
      coverCalibratorState.connectionState,
    ];

    final connectedCount = connectionStates
        .where((state) => state == DeviceConnectionState.connected)
        .length;

    if (connectedCount == 0) {
      return const SizedBox.shrink();
    }

    // How many of those connections are NOT the profile's devices. Without this
    // the header read a green "9 connected" while the persistent bottom status
    // bar read "My Equipment 4/4" — two numbers, one screen, no explanation, and
    // the five extra devices silently vanished on the next launch.
    final sessionOnly = ref.watch(sessionOnlyConnectedSlotsProvider).length;
    final barColor = sessionOnly > 0 ? colors.warning : colors.success;

    return Tooltip(
      message: sessionOnly > 0
          ? '$connectedCount device(s) connected, of which $sessionOnly are not '
              'saved to the active profile and will not reconnect on the next '
              'launch.'
          : '$connectedCount device(s) connected, all saved to the active '
              'profile.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: NightshadeDecorations.statusChip(
          barColor,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: barColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              sessionOnly > 0
                  ? '$connectedCount connected · $sessionOnly unsaved'
                  : '$connectedCount connected',
              style: NightshadeTypography.labelStrongSm.copyWith(
                color: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Device Dashboard Widget
// ============================================================================

class _DeviceDashboard extends ConsumerWidget {
  final EquipmentProfileModel? profile;

  /// Invoked when the empty-state primary CTA is pressed. Required so the
  /// "Connect Devices" button is discoverable directly from the empty state
  /// itself rather than only from the (potentially collapsed) sidebar.
  /// See audit §4.6.
  final void Function(EquipmentProfileModel) onConnectAll;

  /// Invoked when the empty-state secondary CTA is pressed in the
  /// "no devices assigned" branch. Routes to the profile editor so the user
  /// can attach equipment without hunting through the sidebar menu.
  final void Function(EquipmentProfileModel) onEditProfile;

  /// Optional chrome rendered above the cards INSIDE this dashboard's scroll
  /// view (phone layout). Pinning these panels as Column siblings starved and
  /// clipped the card list, so they scroll with the cards instead. Rendered in
  /// the empty states too, otherwise the readiness checklist and the Polar
  /// Alignment / Flat Wizard shortcuts would vanish whenever nothing is
  /// connected — which is exactly when an operator needs them.
  final Widget? header;

  /// Chrome rendered BELOW the cards, inside the same scroll view. Used for the
  /// Discovery scanner on viewports too short to pin it (see
  /// [_EquipmentMainColumn._cardsAndDiscovery]).
  final Widget? footer;

  const _DeviceDashboard({
    this.profile,
    required this.onConnectAll,
    required this.onEditProfile,
    this.header,
    this.footer,
  });

  /// A scroll view hands its child UNBOUNDED height, which would trip the
  /// `Flexible` inside DiscoveryPanel's own column. Bounding the footer keeps
  /// that resolvable while still letting it size to its content.
  Widget? get _boundedFooter => footer == null
      ? null
      : ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500),
          child: footer!,
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    // Watch device connection states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final domeState = ref.watch(domeStateProvider);
    final weatherState = ref.watch(weatherStateProvider);
    final safetyMonitorState = ref.watch(safetyMonitorStateProvider);
    final coverCalibratorState = ref.watch(coverCalibratorStateProvider);
    final switchState = ref.watch(switchStateProvider);

    // Which connected slots are NOT the profile's devices. Resolved here, where
    // the profile is already in scope, and handed to each card as a plain flag —
    // a single card must not depend on the profiles provider (on a remote backend
    // that starts a periodic host poll).
    final sessionOnlySlots = ref.watch(sessionOnlyConnectedSlotsProvider);
    bool adHoc(ProfileDeviceSlot slot) => sessionOnlySlots.contains(slot);

    // Build list of connected device cards
    final connectedCards = <Widget>[];

    if (cameraState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.cameraCard,
        type: ConnectedDeviceType.camera,
        sessionOnly: adHoc(ProfileDeviceSlot.camera),
      ));
    }

    if (mountState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.mountCard,
        type: ConnectedDeviceType.mount,
        sessionOnly: adHoc(ProfileDeviceSlot.mount),
      ));
    }

    if (focuserState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.focuser,
        sessionOnly: adHoc(ProfileDeviceSlot.focuser),
      ));
    }

    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.filterWheel,
        sessionOnly: adHoc(ProfileDeviceSlot.filterWheel),
      ));
    }

    if (guiderState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.guider,
        sessionOnly: adHoc(ProfileDeviceSlot.guider),
      ));
    }

    if (rotatorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.rotator,
        sessionOnly: adHoc(ProfileDeviceSlot.rotator),
      ));
    }

    if (domeState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.dome,
        sessionOnly: adHoc(ProfileDeviceSlot.dome),
      ));
    }

    if (weatherState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.weather,
        sessionOnly: adHoc(ProfileDeviceSlot.weather),
      ));
    }

    if (safetyMonitorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.safetyMonitor,
        sessionOnly: adHoc(ProfileDeviceSlot.safetyMonitor),
      ));
    }

    if (coverCalibratorState.connectionState ==
        DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        type: ConnectedDeviceType.coverCalibrator,
        sessionOnly: adHoc(ProfileDeviceSlot.coverCalibrator),
      ));
    }

    // Switch / power box has no ConnectedDeviceType, so render its per-channel
    // control card directly (dew heaters, outlets). Works remotely via the
    // switch-channel fix.
    if (switchState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const SwitchControlCard());
    }

    // No profile selected state.
    //
    // REMOTE (slave) mode: cards come from per-device state providers, not the
    // profile's slots, so a connected device must render even before the host's
    // profile hydrates (or if the host has devices but no active profile). Only
    // fall through to the "select a profile" empty-state when there is genuinely
    // nothing connected. Local/host keeps the original null-profile prompt.
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    if (profile == null && (!isRemoteMode || connectedCards.isEmpty)) {
      return _EquipmentEmptyState(
        header: header,
        footer: _boundedFooter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.layoutGrid, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Select a profile to view devices',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize16,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // No devices connected state - show prompt to connect
    if (connectedCards.isEmpty) {
      // Check if the profile has any devices assigned (profile is guaranteed non-null here)
      final p = profile!;
      final hasDevicesAssigned =
          (p.cameraId != null && p.cameraId!.isNotEmpty) ||
              (p.mountId != null && p.mountId!.isNotEmpty) ||
              (p.focuserId != null && p.focuserId!.isNotEmpty) ||
              (p.filterWheelId != null && p.filterWheelId!.isNotEmpty) ||
              (p.guiderId != null && p.guiderId!.isNotEmpty) ||
              (p.rotatorId != null && p.rotatorId!.isNotEmpty) ||
              (p.domeId != null && p.domeId!.isNotEmpty) ||
              (p.weatherId != null && p.weatherId!.isNotEmpty) ||
              (p.coverCalibratorId != null && p.coverCalibratorId!.isNotEmpty);

      // Audit §4.6: surface a primary CTA in the empty state itself.
      // Previously the copy advised the user to find "Connect All" in the
      // sidebar — which lives inside the per-profile menu and is undiscoverable
      // when the sidebar is collapsed.
      if (hasDevicesAssigned) {
        // Profile has devices but none connected
        return _EquipmentEmptyState(
          header: header,
          footer: _boundedFooter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.unplug, size: 48, color: colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No devices connected',
                style:
                    NightshadeTypography.h4.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect the equipment assigned to this profile.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              NightshadeButton(
                label: 'Connect Devices',
                icon: LucideIcons.plug,
                variant: ButtonVariant.primary,
                onPressed: () => onConnectAll(p),
              ),
            ],
          ),
        );
      } else {
        // Profile has no devices assigned
        return _EquipmentEmptyState(
          header: header,
          footer: _boundedFooter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plusCircle, size: 48, color: colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No devices assigned',
                style:
                    NightshadeTypography.h4.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Add equipment to this profile to begin, or discover devices below.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              NightshadeButton(
                label: 'Edit Profile',
                icon: LucideIcons.pencil,
                variant: ButtonVariant.primary,
                onPressed: () => onEditProfile(p),
              ),
            ],
          ),
        );
      }
    }

    // Phone: a single full-width column so the cards never get pinched and
    // each card's action rows have the whole viewport to lay out in.
    if (Responsive.isPhone(context)) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header sits OUTSIDE the card padding so the health / readiness
            // bars keep their full-bleed edge-to-edge rules.
            if (header != null) header!,
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < connectedCards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    connectedCards[i],
                  ],
                ],
              ),
            ),
            if (_boundedFooter != null) _boundedFooter!,
          ],
        ),
      );
    }

    // Desktop/tablet: a responsive grid of fixed-width tiles.
    //
    // The header is honoured here too. The caller's "mobile" test is wider than
    // [Responsive.isPhone] (it also covers any viewport narrower than the
    // tablet breakpoint), so a tablet-width window takes the no-rail layout and
    // passes a header while landing in THIS branch. Dropping it there would
    // silently lose System Health, the readiness checklist and both wizard
    // shortcuts on exactly those widths.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header!,
          Padding(
            padding: const EdgeInsets.all(20),
            child: _EqualHeightCardGrid(cards: connectedCards),
          ),
          if (_boundedFooter != null) _boundedFooter!,
        ],
      ),
    );
  }
}

/// Lays the fixed-width device cards out in rows whose members share a height.
///
/// The dashboard used a plain `Wrap` (spacing + runSpacing only, no cross-axis
/// stretch), so every card sized to its own content. Cards whose action buttons
/// wrap to a second line then hung below their row-mates: measured on a 2560 px
/// window with nine devices connected, row 1 shared top y=133 with bottoms at 328
/// except the Mount at 364 (36 px lower), and row 2 shared top y=382 with bottoms
/// at 577 except the Dome at 649 (72 px lower). The result was a visibly ragged
/// grid.
///
/// Chunking into explicit rows and wrapping each in [IntrinsicHeight] with a
/// stretching [Row] makes each run share its tallest card's height, which is what
/// `Wrap` cannot express. Row count is derived from the same fixed tile width the
/// cards use, so the packing matches what `Wrap` produced.
class _EqualHeightCardGrid extends StatelessWidget {
  final List<Widget> cards;

  const _EqualHeightCardGrid({required this.cards});

  /// Must match `ConnectedDeviceCard`'s desktop tile width.
  static const double _cardWidth = 320.0;
  static const double _spacing = 16.0;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.hasBoundedWidth ? constraints.maxWidth : _cardWidth;
        final perRow = ((available + _spacing) / (_cardWidth + _spacing))
            .floor()
            .clamp(1, cards.length);

        final rows = <Widget>[];
        for (var start = 0; start < cards.length; start += perRow) {
          final end = (start + perRow).clamp(0, cards.length);
          final rowCards = cards.sublist(start, end);
          if (rows.isNotEmpty) {
            rows.add(const SizedBox(height: _spacing));
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (var i = 0; i < rowCards.length; i++) ...[
                    if (i > 0) const SizedBox(width: _spacing),
                    // Bound the tile width explicitly. `Wrap` handed its
                    // children a loose maxWidth; a `Row` hands out UNBOUNDED
                    // width, which a card that does not pin its own width
                    // (SwitchControlCard) cannot lay out. ConnectedDeviceCard
                    // already pins the same 320, so this is a no-op for it.
                    SizedBox(width: _cardWidth, child: rowCards[i]),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// A centered empty-state that scrolls when the dashboard region is shorter
/// than its content. On a phone the device dashboard sits in an `Expanded`
/// beneath the health + readiness bars, so on a short viewport the icon +
/// copy + CTA can be taller than the available height; the scroll view keeps
/// it from overflowing while staying vertically centered when there is room.
class _EquipmentEmptyState extends StatelessWidget {
  final Widget child;

  /// Same phone-layout header as [_DeviceDashboard.header]; kept above the
  /// centered empty-state copy so the readiness checklist and wizard shortcuts
  /// stay reachable while no device is connected.
  final Widget? header;

  /// Same phone-layout footer as [_DeviceDashboard.footer]. With no devices
  /// connected the Discovery scanner is the ONLY way forward, so it must not
  /// disappear on the short viewports that unpin it.
  final Widget? footer;

  const _EquipmentEmptyState({required this.child, this.header, this.footer});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) header!,
              Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // The header has already consumed part of the viewport, so
                    // only the REMAINDER should be reserved for centering —
                    // otherwise the empty state pushes itself off the bottom.
                    minHeight: constraints.hasBoundedHeight && header == null
                        ? constraints.maxHeight - 48
                        : 0,
                  ),
                  child: Center(child: child),
                ),
              ),
              if (footer != null) footer!,
            ],
          ),
        );
      },
    );
  }
}
