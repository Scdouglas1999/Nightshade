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
              state.isSweeping ? 'Connecting…' : 'Connect All result',
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: NightshadeDecorations.statusChip(
        colors.success,
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
              color: colors.success,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$connectedCount connected',
            style: NightshadeTypography.labelStrongSm
                .copyWith(color: colors.success),
          ),
        ],
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

  const _DeviceDashboard({
    this.profile,
    required this.onConnectAll,
    required this.onEditProfile,
  });

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

    // Build list of connected device cards
    final connectedCards = <Widget>[];

    if (cameraState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.cameraCard,
        type: ConnectedDeviceType.camera,
      ));
    }

    if (mountState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(ConnectedDeviceCard(
        key: EquipmentTutorialKeys.mountCard,
        type: ConnectedDeviceType.mount,
      ));
    }

    if (focuserState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.focuser,
      ));
    }

    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.filterWheel,
      ));
    }

    if (guiderState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.guider,
      ));
    }

    if (rotatorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.rotator,
      ));
    }

    if (domeState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.dome,
      ));
    }

    if (weatherState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.weather,
      ));
    }

    if (safetyMonitorState.connectionState == DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.safetyMonitor,
      ));
    }

    if (coverCalibratorState.connectionState ==
        DeviceConnectionState.connected) {
      connectedCards.add(const ConnectedDeviceCard(
        type: ConnectedDeviceType.coverCalibrator,
      ));
    }

    // No profile selected state
    if (profile == null) {
      return _EquipmentEmptyState(
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
      );
    }

    // Desktop/tablet: a responsive grid of fixed-width tiles.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: connectedCards,
      ),
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

  const _EquipmentEmptyState({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  constraints.hasBoundedHeight ? constraints.maxHeight - 48 : 0,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
