part of '../connections_tab.dart';

/// Equipment card for weather-station devices.
///
/// Wires the previously unconsumed `unifiedWeatherProvider` +
/// `weatherStateProvider` so users can connect their weather sensor from the
/// Equipment screen.
class _WeatherDeviceCard extends ConsumerStatefulWidget {
  final WeatherState weatherState;
  final NightshadeColors colors;

  const _WeatherDeviceCard({
    required this.weatherState,
    required this.colors,
  });

  @override
  ConsumerState<_WeatherDeviceCard> createState() =>
      _WeatherDeviceCardState();
}

class _WeatherDeviceCardState extends ConsumerState<_WeatherDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.weatherState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    final unifiedWeather = ref.watch(unifiedWeatherProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      if (widget.weatherState.temperature != null) {
        statusDetails.add(
            'Temp: ${widget.weatherState.temperature!.toStringAsFixed(1)}°C');
      }
      if (widget.weatherState.humidity != null) {
        statusDetails.add(
            'RH: ${widget.weatherState.humidity!.toStringAsFixed(0)}%');
      }
      if (widget.weatherState.cloudCover != null) {
        statusDetails.add(
            'Clouds: ${widget.weatherState.cloudCover!.toStringAsFixed(0)}%');
      }
      if (widget.weatherState.windSpeed != null) {
        statusDetails.add(
            'Wind: ${widget.weatherState.windSpeed!.toStringAsFixed(1)} m/s');
      }
      if (statusDetails.isEmpty) {
        statusDetails.add('Awaiting telemetry');
      }
    } else {
      statusDetails.add('Sensors: ---');
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.cloud,
      title: 'Weather',
      subtitle: _getDeviceDisplayName(widget.weatherState.deviceName,
          widget.weatherState.deviceId, 'Weather station'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.weatherState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: _isConnected ? 'Reporting' : 'Idle',
      statusDetails: statusDetails,
      accentColor: widget.colors.warning,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedWeather,
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
      connectFn: ref.read(weatherStateProvider.notifier).connect,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.weather,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: () async =>
            ref.read(weatherStateProvider.notifier).disconnect(),
        deviceType: 'weather station',
      );
}
