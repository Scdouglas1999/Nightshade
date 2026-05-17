part of '../connections_tab.dart';

class _FilterWheelDeviceCard extends ConsumerStatefulWidget {
  final FilterWheelState filterWheelState;
  final NightshadeColors colors;

  const _FilterWheelDeviceCard({
    required this.filterWheelState,
    required this.colors,
  });

  @override
  ConsumerState<_FilterWheelDeviceCard> createState() =>
      _FilterWheelDeviceCardState();
}

class _FilterWheelDeviceCardState extends ConsumerState<_FilterWheelDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.filterWheelState.connectionState ==
      DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified filter wheels (grouped by physical device)
    final unifiedFilterWheels = ref.watch(unifiedFilterWheelsProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      final filterName = widget.filterWheelState.currentFilterName ?? 'Unknown';
      statusDetails.add('Filter: $filterName');
    } else {
      statusDetails.add('Filter: ---');
    }

    // Why: surfaces filterWheelCapabilitiesProvider as a one-line summary
    // (slot count + editability flags) so the user can verify the wheel
    // discovered the expected number of positions without opening profile
    // settings. Silent when not connected or capabilities not loaded.
    if (_isConnected && widget.filterWheelState.deviceId != null) {
      final capsAsync = ref.watch(
          filterWheelCapabilitiesProvider(widget.filterWheelState.deviceId!));
      final caps = capsAsync.valueOrNull;
      if (caps != null) {
        final badges = <String>[];
        if (caps.positionCount > 0) {
          badges.add('${caps.positionCount} slots');
        }
        if (caps.canSetFilterNames) badges.add('names editable');
        if (caps.canSetFocusOffsets) badges.add('offsets editable');
        if (badges.isNotEmpty) {
          statusDetails.add(badges.join(' · '));
        }
      }
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.circle,
      title: 'Filter Wheel',
      subtitle: _getDeviceDisplayName(widget.filterWheelState.deviceName,
          widget.filterWheelState.deviceId, 'Electronic filter wheel'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.filterWheelState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: _isConnected ? 'Ready' : 'Idle',
      statusDetails: statusDetails,
      accentColor: widget.colors.warning,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedFilterWheels,
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
      connectFn: ref.read(deviceServiceProvider).connectFilterWheel,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.filterWheel,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: ref.read(deviceServiceProvider).disconnectFilterWheel,
        deviceType: 'filter wheel',
      );
}
