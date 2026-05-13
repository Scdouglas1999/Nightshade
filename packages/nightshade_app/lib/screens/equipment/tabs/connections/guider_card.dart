part of '../connections_tab.dart';

class _GuiderDeviceCard extends ConsumerStatefulWidget {
  final GuiderState guiderState;
  final NightshadeColors colors;

  const _GuiderDeviceCard({
    required this.guiderState,
    required this.colors,
  });

  @override
  ConsumerState<_GuiderDeviceCard> createState() => _GuiderDeviceCardState();
}

class _GuiderDeviceCardState extends ConsumerState<_GuiderDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.guiderState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified guiders (grouped by physical device)
    final unifiedGuiders = ref.watch(unifiedGuidersProvider);

    final statusDetails = <String>[];
    if (_isConnected && widget.guiderState.rmsTotal != null) {
      statusDetails
          .add('RMS: ${widget.guiderState.rmsTotal!.toStringAsFixed(2)}"');
    } else {
      statusDetails.add('RMS: ---');
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.crosshair,
      title: 'Guider',
      subtitle: _getDeviceDisplayName(widget.guiderState.deviceName,
          widget.guiderState.deviceId, 'Autoguiding camera'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.guiderState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: _getStatusLabel(),
      statusDetails: statusDetails,
      accentColor: widget.colors.info,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedGuiders,
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

  String _getStatusLabel() {
    if (widget.guiderState.isCalibrating) return 'Calibrating';
    if (widget.guiderState.isGuiding) return 'Guiding';
    if (_isConnected) return 'Ready';
    return 'Idle';
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;
    final deviceId = _selectedDevice!.activeDeviceId;
    final deviceName = _selectedDevice!.displayName;

    await connectDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      connectFn: ref.read(deviceServiceProvider).connectGuider,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.guider,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: ref.read(deviceServiceProvider).disconnectGuider,
        deviceType: 'guider',
      );
}
