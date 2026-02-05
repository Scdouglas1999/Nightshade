import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';

// ============================================================================
// Device Type Enum
// ============================================================================

/// Device types supported by the ConnectedDeviceCard
enum ConnectedDeviceType {
  camera,
  mount,
  focuser,
  filterWheel,
  guider,
  rotator,
}

extension ConnectedDeviceTypeExtension on ConnectedDeviceType {
  String get displayName {
    switch (this) {
      case ConnectedDeviceType.camera:
        return 'CAMERA';
      case ConnectedDeviceType.mount:
        return 'MOUNT';
      case ConnectedDeviceType.focuser:
        return 'FOCUSER';
      case ConnectedDeviceType.filterWheel:
        return 'FILTER WHEEL';
      case ConnectedDeviceType.guider:
        return 'GUIDER';
      case ConnectedDeviceType.rotator:
        return 'ROTATOR';
    }
  }

  IconData get icon {
    switch (this) {
      case ConnectedDeviceType.camera:
        return LucideIcons.camera;
      case ConnectedDeviceType.mount:
        return LucideIcons.compass;
      case ConnectedDeviceType.focuser:
        return LucideIcons.focus;
      case ConnectedDeviceType.filterWheel:
        return LucideIcons.circle;
      case ConnectedDeviceType.guider:
        return LucideIcons.crosshair;
      case ConnectedDeviceType.rotator:
        return LucideIcons.rotateCw;
    }
  }

  Color accentColor(NightshadeColors colors) {
    switch (this) {
      case ConnectedDeviceType.camera:
        return colors.primary;
      case ConnectedDeviceType.mount:
        return colors.warning;
      case ConnectedDeviceType.focuser:
        return colors.success;
      case ConnectedDeviceType.filterWheel:
        return colors.warning;
      case ConnectedDeviceType.guider:
        return colors.info;
      case ConnectedDeviceType.rotator:
        return colors.accent;
    }
  }
}

// ============================================================================
// Device ID Formatting Helpers
// ============================================================================

/// Format a device ID into a user-friendly display name
String _formatDeviceId(String id) {
  final lowerId = id.toLowerCase();

  // Handle native device IDs: native:vendor:index or native:vendor_type:index
  if (lowerId.startsWith('native:')) {
    final parts = id.substring(7).split(':');
    if (parts.isNotEmpty) {
      final devicePart = parts[0];
      final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

      // Handle vendor_type format (e.g., zwo_eaf)
      if (devicePart.contains('_')) {
        final subParts = devicePart.split('_');
        final vendor = _capitalizeVendor(subParts[0]);
        final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
        return '$vendor $type';
      }

      // Simple vendor format
      final vendor = _capitalizeVendor(devicePart);
      if (index != null) {
        return '$vendor #${index + 1}';
      }
      return vendor;
    }
  }

  // Handle ASCOM device IDs: ascom:ASCOM.Vendor.Type
  if (lowerId.startsWith('ascom:')) {
    final ascomId = id.substring(6);
    final parts = ascomId.split('.');
    if (parts.length >= 2) {
      final vendorPart = parts.length > 1 ? parts[1] : parts[0];
      return _formatAscomVendor(vendorPart);
    }
  }

  // Handle Alpaca device IDs
  if (lowerId.startsWith('alpaca:')) {
    final alpacaPart = id.substring(7);
    return 'Alpaca: $alpacaPart';
  }

  // Handle PHD2
  if (lowerId.contains('phd2') || lowerId.contains('phd 2')) {
    return 'PHD2';
  }

  // Fallback: try to clean up the ID
  return _cleanupId(id);
}

/// Capitalize vendor names properly
String _capitalizeVendor(String vendor) {
  const knownVendors = {
    'zwo': 'ZWO',
    'asi': 'ZWO ASI',
    'qhy': 'QHY',
    'playerone': 'PlayerOne',
    'svbony': 'SVBony',
    'atik': 'Atik',
    'fli': 'FLI',
    'moravian': 'Moravian',
    'touptek': 'Touptek',
    'pegasus': 'Pegasus',
    'pegasusastro': 'Pegasus Astro',
    'ioptron': 'iOptron',
    'skywatcher': 'Sky-Watcher',
    'celestron': 'Celestron',
    'meade': 'Meade',
    'losmandy': 'Losmandy',
    'moonlite': 'MoonLite',
    'optec': 'Optec',
    'lacerta': 'Lacerta',
    'esatto': 'Esatto',
    'primaluce': 'PrimaLuce',
  };

  final lower = vendor.toLowerCase();
  if (knownVendors.containsKey(lower)) {
    return knownVendors[lower]!;
  }

  if (vendor.isEmpty) return vendor;
  return vendor[0].toUpperCase() + vendor.substring(1);
}

/// Format ASCOM vendor string by adding spaces before capitals/numbers
String _formatAscomVendor(String vendor) {
  final spaced = vendor.replaceAllMapped(
    RegExp(r'([a-z])([A-Z0-9])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  return spaced;
}

/// Clean up an unrecognized ID for display
String _cleanupId(String id) {
  var cleaned = id;
  for (final prefix in ['native:', 'ascom:', 'alpaca:', 'ASCOM.']) {
    if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
      cleaned = cleaned.substring(prefix.length);
    }
  }

  cleaned = cleaned.replaceAll('_', ' ').replaceAll('.', ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\s*:\s*\d+$'), '');

  if (cleaned.isNotEmpty) {
    cleaned = cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  return cleaned.isEmpty ? id : cleaned;
}

/// Get display name for a device, preferring deviceName, falling back to formatted deviceId
String _getDeviceDisplayName(String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return _formatDeviceId(deviceId);
  }
  return fallback;
}

// ============================================================================
// Connected Device Card Widget
// ============================================================================

/// A card widget for displaying connected device status, metrics, and quick actions.
///
/// This widget provides a consistent interface for all device types with:
/// - Device icon and connection status badge
/// - Primary metrics specific to each device type
/// - Quick action buttons for common operations
/// - Expandable section for additional telemetry
class ConnectedDeviceCard extends ConsumerStatefulWidget {
  final ConnectedDeviceType type;
  final VoidCallback? onDisconnect;
  final VoidCallback? onSettings;
  final ValueChanged<String>? onNameChanged;

  const ConnectedDeviceCard({
    super.key,
    required this.type,
    this.onDisconnect,
    this.onSettings,
    this.onNameChanged,
  });

  @override
  ConsumerState<ConnectedDeviceCard> createState() => _ConnectedDeviceCardState();
}

class _ConnectedDeviceCardState extends ConsumerState<ConnectedDeviceCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final connectionState = _getConnectionState();
    final borderColor = _getBorderColor(connectionState, colors);
    final accentColor = widget.type.accentColor(colors);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: IntrinsicWidth(
        child: GestureDetector(
          onTap: _toggleExpanded,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                _buildHeader(colors, accentColor, connectionState),

                const SizedBox(height: 16),

                // Primary Metrics Row
                _buildMetricsRow(colors),

                const SizedBox(height: 12),

                // Quick Actions Row
                _buildActionsRow(colors),

                // Expanded Content
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  child: _buildExpandedContent(colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DeviceConnectionState _getConnectionState() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return ref.watch(cameraStateProvider).connectionState;
      case ConnectedDeviceType.mount:
        return ref.watch(mountStateProvider).connectionState;
      case ConnectedDeviceType.focuser:
        return ref.watch(focuserStateProvider).connectionState;
      case ConnectedDeviceType.filterWheel:
        return ref.watch(filterWheelStateProvider).connectionState;
      case ConnectedDeviceType.guider:
        return ref.watch(guiderStateProvider).connectionState;
      case ConnectedDeviceType.rotator:
        return ref.watch(rotatorStateProvider).connectionState;
    }
  }

  Color _getBorderColor(DeviceConnectionState state, NightshadeColors colors) {
    switch (state) {
      case DeviceConnectionState.connected:
        return colors.success;
      case DeviceConnectionState.connecting:
        return colors.warning;
      case DeviceConnectionState.error:
        return colors.error;
      case DeviceConnectionState.disconnected:
        return colors.border;
    }
  }

  Widget _buildHeader(NightshadeColors colors, Color accentColor, DeviceConnectionState state) {
    final deviceName = _getDeviceName();

    return Row(
      children: [
        // Icon with gradient background
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: 0.2),
                accentColor.withValues(alpha: 0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.type.icon,
            size: 18,
            color: state == DeviceConnectionState.connected ? colors.success : accentColor,
          ),
        ),

        const SizedBox(width: 12),

        // Device type and name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.type.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                deviceName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Connection badge
        _buildConnectionBadge(state, colors),
      ],
    );
  }

  String _getDeviceName() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Camera');
      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Mount');
      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Focuser');
      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Filter Wheel');
      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Guider');
      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Rotator');
    }
  }

  Widget _buildConnectionBadge(DeviceConnectionState state, NightshadeColors colors) {
    final (color, icon, text) = switch (state) {
      DeviceConnectionState.connected => (colors.success, LucideIcons.check, 'Connected'),
      DeviceConnectionState.connecting => (colors.warning, LucideIcons.loader, 'Connecting'),
      DeviceConnectionState.error => (colors.error, LucideIcons.x, 'Error'),
      DeviceConnectionState.disconnected => (colors.textMuted, LucideIcons.circle, 'Disconnected'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          if (state == DeviceConnectionState.connecting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(NightshadeColors colors) {
    final metrics = _getMetrics();

    return Row(
      children: metrics.map((metric) {
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<_DeviceMetric> _getMetrics() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}C'
                : '---',
            label: 'Sensor Temp',
          ),
          _DeviceMetric(
            value: state.coolerPower != null
                ? '${state.coolerPower!.toStringAsFixed(0)}%'
                : '---',
            label: 'Cooler',
          ),
          _DeviceMetric(
            value: state.isExposing ? 'Exposing' : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _DeviceMetric(
            value: state.ra != null
                ? 'RA ${state.ra!.toStringAsFixed(2)}'
                : 'RA ---',
            label: 'Position',
          ),
          _DeviceMetric(
            value: state.isTracking ? 'On' : 'Off',
            label: 'Tracking',
          ),
          _DeviceMetric(
            value: state.isSlewing
                ? 'Slewing'
                : state.isParked
                    ? 'Parked'
                    : 'Ready',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return [
          _DeviceMetric(
            value: state.position?.toString() ?? '---',
            label: 'Position',
          ),
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}C'
                : '---',
            label: 'Temp',
          ),
          _DeviceMetric(
            value: state.isMoving ? 'Moving' : 'Ready',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _DeviceMetric(
            value: state.currentFilterName ?? 'Unknown',
            label: 'Filter',
          ),
          _DeviceMetric(
            value: '#${state.currentPosition ?? "?"}',
            label: 'Position',
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _DeviceMetric(
            value: state.rmsTotal != null
                ? '${state.rmsTotal!.toStringAsFixed(2)}"'
                : '---',
            label: 'RMS Total',
          ),
          _DeviceMetric(
            value: state.rmsRa != null
                ? 'RA: ${state.rmsRa!.toStringAsFixed(2)}"'
                : '---',
            label: 'RA/Dec RMS',
          ),
          _DeviceMetric(
            value: state.isGuiding ? 'Guiding' : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return [
          _DeviceMetric(
            value: state.position != null
                ? state.position!.toStringAsFixed(1)
                : '---',
            label: 'Angle',
          ),
          _DeviceMetric(
            value: state.isMoving ? 'Moving' : 'Ready',
            label: 'Status',
          ),
        ];
    }
  }

  Widget _buildActionsRow(NightshadeColors colors) {
    return Row(
      children: [
        // Device-specific quick actions
        ..._buildDeviceActions(colors),

        const Spacer(),

        // Settings button
        IconButton(
          onPressed: widget.onSettings ?? () => _showSettingsDialog(context),
          icon: const Icon(LucideIcons.settings2, size: 16),
          tooltip: 'Settings',
          style: IconButton.styleFrom(
            foregroundColor: colors.textMuted,
          ),
        ),

        // Disconnect button
        IconButton(
          onPressed: widget.onDisconnect ?? () => _handleDisconnect(),
          icon: const Icon(LucideIcons.unplug, size: 16),
          tooltip: 'Disconnect',
          style: IconButton.styleFrom(
            foregroundColor: colors.textMuted,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDeviceActions(NightshadeColors colors) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _ActionButton(
            label: 'Cool to ${state.targetTemp.toStringAsFixed(0)}C',
            onTap: () => _handleCoolCamera(state.targetTemp),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Warm Up',
            onTap: _handleWarmCamera,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _ActionButton(
            label: state.isParked ? 'Unpark' : 'Park',
            onTap: () => _handleTogglePark(),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isTracking ? 'Stop Tracking' : 'Track',
            onTap: () => _handleToggleTracking(state.isTracking),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.focuser:
        return [
          _ActionButton(
            label: 'Move to...',
            onTap: () => _showMoveDialog(context),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _FilterDropdown(
            filterNames: state.filterNames,
            currentPosition: state.currentPosition,
            onFilterSelected: _handleFilterChange,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _ActionButton(
            label: state.isGuiding ? 'Stop' : 'Start Guiding',
            onTap: () => _handleToggleGuiding(state.isGuiding),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.rotator:
        return [
          _ActionButton(
            label: 'Rotate to...',
            onTap: () => _showRotateDialog(context),
            colors: colors,
          ),
        ];
    }
  }

  Widget _buildExpandedContent(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Additional Info',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ..._buildExpandedTelemetry(colors),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditNameDialog(context),
                    icon: Icon(LucideIcons.pencil, size: 14, color: colors.textSecondary),
                    label: Text(
                      'Edit Name',
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExpandedTelemetry(NightshadeColors colors) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(label: 'Gain', value: state.gain?.toString() ?? '---', colors: colors),
          _TelemetryRow(label: 'Offset', value: state.offset?.toString() ?? '---', colors: colors),
          _TelemetryRow(label: 'Binning', value: state.binning ?? '---', colors: colors),
          _TelemetryRow(label: 'Cooling', value: state.isCooling ? 'Active' : 'Off', colors: colors),
          _TelemetryRow(
            label: 'Target Temp',
            value: '${state.targetTemp.toStringAsFixed(1)}C',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(
            label: 'RA',
            value: state.ra?.toStringAsFixed(4) ?? '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dec',
            value: state.dec?.toStringAsFixed(4) ?? '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Altitude',
            value: state.altitude != null ? state.altitude!.toStringAsFixed(2) : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Azimuth',
            value: state.azimuth != null ? state.azimuth!.toStringAsFixed(2) : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Side of Pier',
            value: state.sideOfPier ?? 'Unknown',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Tracking Rate',
            value: state.trackingRate.name.toUpperCase(),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(
            label: 'Max Position',
            value: state.maxPosition?.toString() ?? '---',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(
            label: 'Filters',
            value: state.filterNames.join(', '),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(
            label: 'RA RMS',
            value: state.rmsRa != null ? '${state.rmsRa!.toStringAsFixed(3)}"' : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dec RMS',
            value: state.rmsDec != null ? '${state.rmsDec!.toStringAsFixed(3)}"' : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Calibrating',
            value: state.isCalibrating ? 'Yes' : 'No',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return [
          _TelemetryRow(label: 'Device ID', value: state.deviceId ?? 'Unknown', colors: colors),
          _TelemetryRow(
            label: 'Mechanical Position',
            value: state.mechanicalPosition != null
                ? state.mechanicalPosition!.toStringAsFixed(2)
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Reversed',
            value: state.isReversed ? 'Yes' : 'No',
            colors: colors,
          ),
        ];
    }
  }

  // ============================================================================
  // Action Handlers
  // ============================================================================

  Future<void> _handleDisconnect() async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      switch (widget.type) {
        case ConnectedDeviceType.camera:
          await deviceService.disconnectCamera();
          break;
        case ConnectedDeviceType.mount:
          await deviceService.disconnectMount();
          break;
        case ConnectedDeviceType.focuser:
          await deviceService.disconnectFocuser();
          break;
        case ConnectedDeviceType.filterWheel:
          await deviceService.disconnectFilterWheel();
          break;
        case ConnectedDeviceType.guider:
          await deviceService.disconnectGuider();
          break;
        case ConnectedDeviceType.rotator:
          await deviceService.disconnectRotator();
          break;
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to disconnect: $e');
      }
    }
  }

  Future<void> _handleCoolCamera(double targetTemp) async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.setCameraCooling(enabled: true, targetTemp: targetTemp);
      if (mounted) {
        context.showSuccessSnackBar('Cooling to ${targetTemp.toStringAsFixed(0)}C');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to start cooling: $e');
      }
    }
  }

  Future<void> _handleWarmCamera() async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.setCameraCooling(enabled: false);
      if (mounted) {
        context.showSuccessSnackBar('Warming up camera');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to warm up: $e');
      }
    }
  }

  Future<void> _handleTogglePark() async {
    final mountService = ref.read(mountCommandServiceProvider);
    await mountService.togglePark(context);
  }

  Future<void> _handleToggleTracking(bool currentlyTracking) async {
    final mountService = ref.read(mountCommandServiceProvider);
    await mountService.setTracking(context, !currentlyTracking);
  }

  Future<void> _handleFilterChange(int position) async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.setFilterWheelPosition(position);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to change filter: $e');
      }
    }
  }

  Future<void> _handleToggleGuiding(bool currentlyGuiding) async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      if (currentlyGuiding) {
        await deviceService.stopGuiding();
        if (mounted) {
          context.showSuccessSnackBar('Guiding stopped');
        }
      } else {
        await deviceService.startGuiding();
        if (mounted) {
          context.showSuccessSnackBar('Guiding started');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Guiding operation failed: $e');
      }
    }
  }

  // ============================================================================
  // Dialogs
  // ============================================================================

  void _showSettingsDialog(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          '${widget.type.displayName} Settings',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Device settings will be available here in a future update.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final focuserState = ref.read(focuserStateProvider);
    final controller = TextEditingController(
      text: focuserState.position?.toString() ?? '0',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Move Focuser',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter target position (0 - ${focuserState.maxPosition ?? 50000}):',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Position',
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final position = int.tryParse(controller.text);
              if (position != null) {
                Navigator.pop(context, position);
              }
            },
            label: 'Move',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final deviceService = ref.read(deviceServiceProvider);
      try {
        await deviceService.moveFocuserTo(result);
        if (mounted) {
          context.showSuccessSnackBar('Moving focuser to $result');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to move focuser: $e');
        }
      }
    }
  }

  void _showRotateDialog(BuildContext context) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final rotatorState = ref.read(rotatorStateProvider);
    final controller = TextEditingController(
      text: rotatorState.position?.toStringAsFixed(1) ?? '0.0',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Rotate To Angle',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter target angle (0 - 360 degrees):',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Angle',
                suffixText: 'degrees',
                suffixStyle: TextStyle(color: colors.textMuted),
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final angle = double.tryParse(controller.text);
              if (angle != null && angle >= 0 && angle <= 360) {
                Navigator.pop(context, angle);
              }
            },
            label: 'Rotate',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final backend = ref.read(backendProvider);
      final rotatorState = ref.read(rotatorStateProvider);
      if (rotatorState.deviceId != null) {
        try {
          await backend.rotatorMoveTo(rotatorState.deviceId!, result);
          if (mounted) {
            context.showSuccessSnackBar('Rotating to ${result.toStringAsFixed(1)} degrees');
          }
        } catch (e) {
          if (mounted) {
            context.showErrorSnackBar('Failed to rotate: $e');
          }
        }
      }
    }
  }

  void _showEditNameDialog(BuildContext context) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final currentName = _getDeviceName();
    final controller = TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Edit Device Name',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter device name',
            hintStyle: TextStyle(color: colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            label: 'Save',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      widget.onNameChanged?.call(result);
      context.showSuccessSnackBar('Device name updated');
    }
  }
}

// ============================================================================
// Helper Widgets
// ============================================================================

class _DeviceMetric {
  final String value;
  final String label;

  _DeviceMetric({required this.value, required this.label});
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        side: BorderSide(color: colors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final List<String> filterNames;
  final int? currentPosition;
  final ValueChanged<int> onFilterSelected;
  final NightshadeColors colors;

  const _FilterDropdown({
    required this.filterNames,
    required this.currentPosition,
    required this.onFilterSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (filterNames.isEmpty) {
      return _ActionButton(
        label: 'No filters',
        onTap: () {},
        colors: colors,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: currentPosition,
          isDense: true,
          dropdownColor: colors.surface,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
          icon: Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          items: filterNames.asMap().entries.map((entry) {
            return DropdownMenuItem<int>(
              value: entry.key,
              child: Text(
                entry.value,
                style: TextStyle(color: colors.textPrimary),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              onFilterSelected(value);
            }
          },
        ),
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TelemetryRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
