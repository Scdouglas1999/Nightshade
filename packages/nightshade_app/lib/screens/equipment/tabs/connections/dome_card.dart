part of '../connections_tab.dart';

/// Equipment card for dome devices.
///
/// Wires the previously unconsumed `unifiedDomesProvider` +
/// `domeStateProvider` so users can connect their dome from the Equipment
/// screen. Mirrors the focuser/rotator card pattern.
class _DomeDeviceCard extends ConsumerStatefulWidget {
  final DomeState domeState;
  final NightshadeColors colors;

  const _DomeDeviceCard({
    required this.domeState,
    required this.colors,
  });

  @override
  ConsumerState<_DomeDeviceCard> createState() => _DomeDeviceCardState();
}

class _DomeDeviceCardState extends ConsumerState<_DomeDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.domeState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    final unifiedDomes = ref.watch(unifiedDomesProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      if (widget.domeState.azimuth != null) {
        statusDetails
            .add('Az: ${widget.domeState.azimuth!.toStringAsFixed(1)}°');
      } else {
        statusDetails.add('Az: ---');
      }
      statusDetails
          .add('Shutter: ${widget.domeState.shutterStatus.name}');
      if (widget.domeState.isSlaved) {
        statusDetails.add('Slaved to mount');
      }
      if (widget.domeState.isParked) {
        statusDetails.add('Parked');
      }
    } else {
      statusDetails.add('Az: ---');
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.warehouse,
      title: 'Dome',
      subtitle: _getDeviceDisplayName(widget.domeState.deviceName,
          widget.domeState.deviceId, 'Observatory dome'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.domeState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: widget.domeState.isSlewing
          ? 'Slewing'
          : (_isConnected ? 'Ready' : 'Idle'),
      statusDetails: statusDetails,
      accentColor: widget.colors.info,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedDomes,
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
      connectFn: ref.read(domeStateProvider.notifier).connect,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.dome,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: () async =>
            ref.read(domeStateProvider.notifier).disconnect(),
        deviceType: 'dome',
      );
}
