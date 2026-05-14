part of '../connections_tab.dart';

class _CameraDeviceCard extends ConsumerStatefulWidget {
  final CameraStateSnapshot cameraState;
  final NightshadeColors colors;

  const _CameraDeviceCard({
    required this.cameraState,
    required this.colors,
  });

  @override
  ConsumerState<_CameraDeviceCard> createState() => _CameraDeviceCardState();
}

class _CameraDeviceCardState extends ConsumerState<_CameraDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.cameraState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified cameras (grouped by physical device)
    final unifiedCameras = ref.watch(unifiedCamerasProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      if (widget.cameraState.temperature != null) {
        statusDetails.add(
            'Sensor: ${widget.cameraState.temperature!.toStringAsFixed(1)}°C');
      }
      if (widget.cameraState.coolerPower != null) {
        statusDetails.add(
            'Cooler: ${widget.cameraState.coolerPower!.toStringAsFixed(0)}%');
      }
    } else {
      statusDetails.addAll(['Sensor: ---', 'Cooling: ---']);
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.camera,
      title: 'Camera',
      subtitle: _getDeviceDisplayName(widget.cameraState.deviceName,
          widget.cameraState.deviceId, 'Main imaging camera'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.cameraState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: _getStatusLabel(),
      statusDetails: statusDetails,
      accentColor: widget.colors.primary,
      colors: widget.colors,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedCameras,
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

  String _getStatusLabel() {
    if (widget.cameraState.isExposing) return 'Exposing';
    if (widget.cameraState.isCooling) return 'Cooling';
    if (_isConnected) return 'Ready';
    return 'Idle';
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;
    final deviceId = _selectedDevice!.activeDeviceId;
    final deviceName = _selectedDevice!.displayName;

    // Fujifilm warranty disclaimer check
    if (isFujifilmDevice(deviceId, deviceName)) {
      final accepted = await showFujifilmDisclaimerIfNeeded(context);
      if (!accepted) return;
    }

    await connectDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      connectFn: ref.read(deviceServiceProvider).connectCamera,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.camera,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: ref.read(deviceServiceProvider).disconnectCamera,
        deviceType: 'camera',
      );
}
