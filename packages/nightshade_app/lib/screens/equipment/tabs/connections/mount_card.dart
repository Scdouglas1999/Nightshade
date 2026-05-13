part of '../connections_tab.dart';

class _MountDeviceCard extends ConsumerStatefulWidget {
  final MountState mountState;
  final NightshadeColors colors;

  const _MountDeviceCard({
    required this.mountState,
    required this.colors,
  });

  @override
  ConsumerState<_MountDeviceCard> createState() => _MountDeviceCardState();
}

class _MountDeviceCardState extends ConsumerState<_MountDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.mountState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified mounts (grouped by physical device)
    final unifiedMounts = ref.watch(unifiedMountsProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      final ra = widget.mountState.ra?.toStringAsFixed(2) ?? '---';
      final dec = widget.mountState.dec?.toStringAsFixed(2) ?? '---';
      statusDetails.add('RA: $ra  Dec: $dec');
      if (widget.mountState.isTracking) {
        statusDetails.add('Tracking');
      }
    } else {
      statusDetails.add('RA: ---  Dec: ---');
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.compass,
      title: 'Mount',
      subtitle: _getDeviceDisplayName(widget.mountState.deviceName,
          widget.mountState.deviceId, 'Telescope mount'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.mountState.connectionState == DeviceConnectionState.connecting,
      statusLabel: widget.mountState.isSlewing
          ? 'Slewing'
          : (_isConnected ? 'Ready' : 'Idle'),
      statusDetails: statusDetails,
      accentColor: widget.colors.warning,
      colors: widget.colors,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedMounts,
      selectedDevice: _selectedDevice,
      onDeviceSelected: (device) => setState(() => _selectedDevice = device),
      onBackendSelected: _handleBackendSelected,
      onConnect: _handleConnect,
      onDisconnect: _handleDisconnect,
    );
  }

  void _handleBackendSelected(DriverType backend) {
    if (_selectedDevice == null) return;
    // Update the selected device with the new backend
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
      connectFn: ref.read(deviceServiceProvider).connectMount,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.mount,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: ref.read(deviceServiceProvider).disconnectMount,
        deviceType: 'mount',
      );
}
