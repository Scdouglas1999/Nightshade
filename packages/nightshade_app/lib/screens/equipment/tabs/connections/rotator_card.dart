part of '../connections_tab.dart';

class _RotatorDeviceCard extends ConsumerStatefulWidget {
  final RotatorState rotatorState;
  final NightshadeColors colors;

  const _RotatorDeviceCard({
    required this.rotatorState,
    required this.colors,
  });

  @override
  ConsumerState<_RotatorDeviceCard> createState() => _RotatorDeviceCardState();
}

class _RotatorDeviceCardState extends ConsumerState<_RotatorDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.rotatorState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified rotators (grouped by physical device)
    final unifiedRotators = ref.watch(unifiedRotatorsProvider);

    final statusDetails = <String>[];
    if (_isConnected && widget.rotatorState.position != null) {
      statusDetails.add(
          'Position: ${widget.rotatorState.position!.toStringAsFixed(1)}°');
      if (widget.rotatorState.mechanicalPosition != null) {
        statusDetails.add(
            'Mechanical: ${widget.rotatorState.mechanicalPosition!.toStringAsFixed(1)}°');
      }
    } else {
      statusDetails.add('Position: ---');
    }

    // Why: surfaces rotatorCapabilitiesProvider so the user can see at a
    // glance whether the rotator supports absolute moves / halts / sync —
    // the differentiating capabilities a sequencer step might require.
    if (_isConnected && widget.rotatorState.deviceId != null) {
      final capsAsync = ref
          .watch(rotatorCapabilitiesProvider(widget.rotatorState.deviceId!));
      final caps = capsAsync.valueOrNull;
      if (caps != null) {
        final badges = <String>[];
        if (caps.canMoveAbsolute) badges.add('absolute');
        if (caps.canReverse) badges.add('reversible');
        if (caps.canHalt) badges.add('halt');
        if (caps.canSync) badges.add('sync');
        if (badges.isNotEmpty) {
          statusDetails.add(badges.join(' · '));
        }
      }
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.rotateCw,
      title: 'Rotator',
      subtitle: _getDeviceDisplayName(widget.rotatorState.deviceName,
          widget.rotatorState.deviceId, 'Field rotator'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.rotatorState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: widget.rotatorState.isMoving
          ? 'Moving'
          : (_isConnected ? 'Ready' : 'Idle'),
      statusDetails: statusDetails,
      accentColor: widget.colors.accent,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedRotators,
      selectedDevice: _selectedDevice,
      onDeviceSelected: (device) => setState(() => _selectedDevice = device),
      onBackendSelected: _handleBackendSelected,
      onConnect: _handleConnect,
      onDisconnect: _handleDisconnect,
    );
  }

  void _handleBackendSelected(DriverType backend) {
    if (_selectedDevice == null) return;
    setState(() {
      _selectedDevice = _selectedDevice!.withSelectedBackend(backend);
    });
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;
    final deviceId = _selectedDevice!.activeDeviceId;
    final deviceName = _selectedDevice!.displayName;

    await connectDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      connectFn: ref.read(rotatorStateProvider.notifier).connect,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.rotator,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: () async =>
            ref.read(rotatorStateProvider.notifier).disconnect(),
        deviceType: 'rotator',
      );
}
