import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;
import '../../../services/mount_command_service.dart';
import '../../../utils/device_format_utils.dart';
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
  dome,
  weather,
  safetyMonitor,
  coverCalibrator,
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
      case ConnectedDeviceType.dome:
        return 'DOME';
      case ConnectedDeviceType.weather:
        return 'WEATHER';
      case ConnectedDeviceType.safetyMonitor:
        return 'SAFETY MONITOR';
      case ConnectedDeviceType.coverCalibrator:
        return 'COVER CALIBRATOR';
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
      case ConnectedDeviceType.dome:
        return LucideIcons.home;
      case ConnectedDeviceType.weather:
        return LucideIcons.cloudSun;
      case ConnectedDeviceType.safetyMonitor:
        return LucideIcons.shieldCheck;
      case ConnectedDeviceType.coverCalibrator:
        return LucideIcons.lamp;
    }
  }

  /// Accent color for the card header icon — one accent per device category.
  ///
  /// Mapping (per audit §4.22):
  ///   - imaging chain (capture)            -> `colors.primary`  (indigo)
  ///       - camera
  ///   - sky pointing / mechanical          -> `colors.warning`  (amber)
  ///       - mount
  ///       - rotator
  ///       - dome
  ///   - opto-mechanical adjusters          -> `colors.accent`   (violet)
  ///       - focuser
  ///       - filterWheel
  ///       - coverCalibrator
  ///   - measurement / telemetry            -> `colors.info`     (blue)
  ///       - guider
  ///       - weather
  ///   - life-safety / interlocks           -> `colors.success`  (green)
  ///       - safetyMonitor
  ///
  /// Status colors (success/warning/error) are reserved for the connection
  /// state border and badge — they are not used as device accents here so the
  /// border color is unambiguous.
  Color accentColor(NightshadeColors colors) {
    switch (this) {
      // Imaging chain
      case ConnectedDeviceType.camera:
        return colors.primary;
      // Sky pointing & mechanical positioners
      case ConnectedDeviceType.mount:
      case ConnectedDeviceType.rotator:
      case ConnectedDeviceType.dome:
        return colors.warning;
      // Opto-mechanical adjusters in the optical path
      case ConnectedDeviceType.focuser:
      case ConnectedDeviceType.filterWheel:
      case ConnectedDeviceType.coverCalibrator:
        return colors.accent;
      // Measurement / telemetry
      case ConnectedDeviceType.guider:
      case ConnectedDeviceType.weather:
        return colors.info;
      // Life-safety / interlocks
      case ConnectedDeviceType.safetyMonitor:
        return colors.success;
    }
  }
}

/// Get display name for a device, preferring deviceName, falling back to formatted deviceId
String _getDeviceDisplayName(
    String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return formatDeviceId(deviceId);
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
  ConsumerState<ConnectedDeviceCard> createState() =>
      _ConnectedDeviceCardState();
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

    // Fixed tile width keeps the Wrap layout in equipment_screen tidy
    // (audit §4.21). 320 px fits the longest action labels (e.g. "Stop
    // Tracking") without wrap and keeps two columns at 720+ px.
    return SizedBox(
      width: 320,
      child: GestureDetector(
        onTap: _toggleExpanded,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
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
      case ConnectedDeviceType.dome:
        return ref.watch(domeStateProvider).connectionState;
      case ConnectedDeviceType.weather:
        return ref.watch(weatherStateProvider).connectionState;
      case ConnectedDeviceType.safetyMonitor:
        return ref.watch(safetyMonitorStateProvider).connectionState;
      case ConnectedDeviceType.coverCalibrator:
        return ref.watch(coverCalibratorStateProvider).connectionState;
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

  Widget _buildHeader(
      NightshadeColors colors, Color accentColor, DeviceConnectionState state) {
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
            color: state == DeviceConnectionState.connected
                ? colors.success
                : accentColor,
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
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Camera');
      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Mount');
      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Focuser');
      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Filter Wheel');
      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Guider');
      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Rotator');
      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return _getDeviceDisplayName(state.deviceName, state.deviceId, 'Dome');
      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Weather Station');
      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Safety Monitor');
      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return _getDeviceDisplayName(
            state.deviceName, state.deviceId, 'Cover Calibrator');
    }
  }

  Widget _buildConnectionBadge(
      DeviceConnectionState state, NightshadeColors colors) {
    final (color, icon, text) = switch (state) {
      DeviceConnectionState.connected => (
          colors.success,
          LucideIcons.check,
          'Connected'
        ),
      DeviceConnectionState.connecting => (
          colors.warning,
          LucideIcons.loader,
          'Connecting'
        ),
      DeviceConnectionState.error => (colors.error, LucideIcons.x, 'Error'),
      DeviceConnectionState.disconnected => (
          colors.textMuted,
          LucideIcons.circle,
          'Disconnected'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
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
                  color: metric.valueColor ?? colors.textPrimary,
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

  /// Format RA hours (0-24) as HH:MM:SS
  String _formatRA(double raHours) {
    final h = raHours.floor();
    final remainder = (raHours - h) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Format Dec degrees (-90 to +90) as +/-DD:MM:SS
  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final abs = decDegrees.abs();
    final d = abs.floor();
    final remainder = (abs - d) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60).round();
    return '$sign${d.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
            value: state.ra != null ? _formatRA(state.ra!) : '---',
            label: 'RA',
          ),
          _DeviceMetric(
            value: state.dec != null ? _formatDec(state.dec!) : '---',
            label: 'Dec',
          ),
          _DeviceMetric(
            value: state.isSlewing
                ? 'Slewing'
                : state.isParked
                    ? 'Parked'
                    : state.isTracking
                        ? 'Tracking'
                        : 'Idle',
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
            value: state.currentPosition != null
                ? '#${state.currentPosition! + 1}'
                : '#?',
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

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _DeviceMetric(
            value: state.azimuth != null
                ? '${state.azimuth!.toStringAsFixed(1)}\u00B0'
                : '---',
            label: 'Azimuth',
          ),
          _DeviceMetric(
            value: _shutterStatusLabel(state.shutterStatus),
            label: 'Shutter',
          ),
          _DeviceMetric(
            value: state.isSlewing
                ? 'Slewing'
                : state.isParked
                    ? 'Parked'
                    : state.isSlaved
                        ? 'Slaved'
                        : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        final weatherColors = Theme.of(context).extension<NightshadeColors>()!;
        final hasRain = state.rainRate != null && state.rainRate! > 0;
        return [
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            label: 'Temp',
          ),
          _DeviceMetric(
            value: state.humidity != null
                ? '${state.humidity!.toStringAsFixed(0)}%'
                : '---',
            label: 'Humidity',
          ),
          _DeviceMetric(
            value: hasRain
                ? 'Rain!'
                : state.dewPoint != null
                    ? '${state.dewPoint!.toStringAsFixed(1)}\u00B0C'
                    : '---',
            label: hasRain ? 'Alert' : 'Dew Point',
            valueColor: hasRain ? weatherColors.error : null,
          ),
        ];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        final colors = Theme.of(context).extension<NightshadeColors>()!;
        return [
          _DeviceMetric(
            value: state.isSafe ? 'SAFE' : 'UNSAFE',
            label: 'Status',
            valueColor: state.isSafe ? colors.success : colors.error,
          ),
          _DeviceMetric(
            value: state.lastChecked != null
                ? _formatTimeAgo(state.lastChecked!)
                : '---',
            label: 'Last Checked',
          ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          if (state.hasCover)
            _DeviceMetric(
              value: _coverStatusLabel(state.coverStatus),
              label: 'Cover',
            ),
          if (state.hasCalibrator) ...[
            _DeviceMetric(
              value: state.isCalibratorOn ? 'ON' : 'OFF',
              label: 'Light',
            ),
            _DeviceMetric(
              value: state.isCalibratorOn
                  ? '${state.brightness}/${state.maxBrightness}'
                  : '---',
              label: 'Brightness',
            ),
          ],
          if (!state.hasCover && !state.hasCalibrator)
            _DeviceMetric(
              value: 'Connected',
              label: 'Status',
            ),
        ];
    }
  }

  String _shutterStatusLabel(ShutterStatus status) {
    switch (status) {
      case ShutterStatus.open:
        return 'Open';
      case ShutterStatus.closed:
        return 'Closed';
      case ShutterStatus.opening:
        return 'Opening';
      case ShutterStatus.closing:
        return 'Closing';
      case ShutterStatus.error:
        return 'Error';
      case ShutterStatus.unknown:
        return 'Unknown';
    }
  }

  String _coverStatusLabel(CoverStatus status) {
    switch (status) {
      case CoverStatus.open:
        return 'Open';
      case CoverStatus.closed:
        return 'Closed';
      case CoverStatus.moving:
        return 'Moving';
      case CoverStatus.notPresent:
        return 'N/A';
      case CoverStatus.unknown:
        return 'Unknown';
      case CoverStatus.error:
        return 'Error';
    }
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Widget _buildActionsRow(NightshadeColors colors) {
    final settingsAction = _resolveSettingsAction();

    return Row(
      children: [
        // Device-specific quick actions
        ..._buildDeviceActions(colors),

        const Spacer(),

        // Settings button — only shown for device types that have real
        // settings reachable from this card (or when an external onSettings
        // callback has been injected by the parent). Device types without
        // settings have no gear icon at all so we never ship a non-functional
        // control. See docs/plans/2026-05-09-v250-audit-fixes.md §4.1.
        if (settingsAction != null)
          IconButton(
            onPressed: settingsAction,
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

  /// Returns the settings action for the current device type, or `null` if
  /// this device type has no real settings to expose from the card.
  ///
  /// Wiring matrix (audit §4.6 follow-up; W0-EQ left TODOs that W1B-UI-EQ
  /// addressed here):
  ///
  /// | Device          | Gear visible? | Action                                    |
  /// |-----------------|---------------|-------------------------------------------|
  /// | camera          | yes           | local cooling-target dialog               |
  /// | filterWheel     | yes (if      | injected `widget.onSettings`              |
  /// |                 | injected)     | (parent opens ProfileEditorDialog where   |
  /// |                 |               | per-filter offsets are edited)            |
  /// | mount           | no            | no slew-rate / park-position widget yet   |
  /// | focuser         | no            | no step-size / max-position widget yet    |
  /// | rotator         | no            | no sky-PA preset widget yet               |
  /// | dome            | no            | no park/home/follow-mount widget yet      |
  /// | coverCalibrator | no            | no brightness / cover-state widget yet    |
  /// | guider          | no            | no per-card settings (config in Imaging)  |
  /// | weather         | no            | read-only telemetry                       |
  /// | safetyMonitor   | no            | read-only                                 |
  ///
  /// Per CLAUDE.md ("no stubs / no placeholders"), unwired gears stay hidden
  /// — we never display a settings affordance that does nothing or that opens
  /// an empty dialog. When a real device-specific settings widget for one of
  /// the unwired entries is added under
  /// `packages/nightshade_app/lib/screens/equipment/widgets/`, route to it
  /// from this switch.
  ///
  /// An externally-injected `widget.onSettings` always wins, allowing the
  /// equipment screen (which knows the active profile) to wire filter-wheel
  /// offsets editing without making the card itself profile-aware.
  VoidCallback? _resolveSettingsAction() {
    final injected = widget.onSettings;
    if (injected != null) {
      return injected;
    }
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return () {
          final targetTemp = ref.read(cameraStateProvider).targetTemp;
          _showCoolingTempDialog(targetTemp);
        };
      // Hidden: no device-specific settings widget exists yet. Adding a
      // route here without an implementation would ship a stub.
      case ConnectedDeviceType.filterWheel:
      case ConnectedDeviceType.mount:
      case ConnectedDeviceType.focuser:
      case ConnectedDeviceType.rotator:
      case ConnectedDeviceType.dome:
      case ConnectedDeviceType.coverCalibrator:
      // Read-only / no per-card settings.
      case ConnectedDeviceType.guider:
      case ConnectedDeviceType.weather:
      case ConnectedDeviceType.safetyMonitor:
        return null;
    }
  }

  List<Widget> _buildDeviceActions(NightshadeColors colors) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _ActionButton(
            label: 'Cool to ${state.targetTemp.toStringAsFixed(0)}C',
            onTap: () => _handleCoolCamera(state.targetTemp),
            onLongPress: () => _showCoolingTempDialog(state.targetTemp),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isWarming ? 'Cancel Warm' : 'Warm Up',
            onTap: state.isWarming ? _handleCancelWarm : _handleWarmCamera,
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
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Home',
            onTap: () => _handleFindHome(),
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

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _ActionButton(
            label: state.shutterStatus == ShutterStatus.open
                ? 'Close Shutter'
                : 'Open Shutter',
            onTap: () => _handleDomeShutter(state.shutterStatus),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isParked ? 'Unpark' : 'Park',
            onTap: () => _handleDomePark(state.isParked),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.weather:
        return [];

      case ConnectedDeviceType.safetyMonitor:
        return [];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          if (state.hasCover)
            _ActionButton(
              label: state.isCoverOpen ? 'Close Cover' : 'Open Cover',
              onTap: () => _handleCoverToggle(state.isCoverOpen),
              colors: colors,
            ),
          if (state.hasCover && state.hasCalibrator) const SizedBox(width: 8),
          if (state.hasCalibrator)
            _ActionButton(
              label: state.isCalibratorOn ? 'Light Off' : 'Light On',
              onTap: () => _handleCalibratorToggle(state),
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
                  child: NightshadeButton(
                    onPressed: () => _showEditNameDialog(context),
                    icon: LucideIcons.pencil,
                    label: 'Edit Name',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
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
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
              label: 'Gain',
              value: state.gain?.toString() ?? '---',
              colors: colors),
          _TelemetryRow(
              label: 'Offset',
              value: state.offset?.toString() ?? '---',
              colors: colors),
          _TelemetryRow(
              label: 'Binning', value: state.binning ?? '---', colors: colors),
          _TelemetryRow(
              label: 'Cooling',
              value: state.isCooling ? 'Active' : 'Off',
              colors: colors),
          _TelemetryRow(
            label: 'Target Temp',
            value: '${state.targetTemp.toStringAsFixed(1)}C',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
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
            value: state.altitude != null
                ? state.altitude!.toStringAsFixed(2)
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Azimuth',
            value: state.azimuth != null
                ? state.azimuth!.toStringAsFixed(2)
                : '---',
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
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Max Position',
            value: state.maxPosition?.toString() ?? '---',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Filters',
            value: state.filterNames.join(', '),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'RA RMS',
            value: state.rmsRa != null
                ? '${state.rmsRa!.toStringAsFixed(3)}"'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dec RMS',
            value: state.rmsDec != null
                ? '${state.rmsDec!.toStringAsFixed(3)}"'
                : '---',
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
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
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

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Azimuth',
            value: state.azimuth != null
                ? '${state.azimuth!.toStringAsFixed(2)}\u00B0'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Shutter',
            value: _shutterStatusLabel(state.shutterStatus),
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Parked',
            value: state.isParked ? 'Yes' : 'No',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'At Home',
            value: state.isAtHome ? 'Yes' : 'No',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Slaved',
            value: state.isSlaved ? 'Yes' : 'No',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Temperature',
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Humidity',
            value: state.humidity != null
                ? '${state.humidity!.toStringAsFixed(1)}%'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dew Point',
            value: state.dewPoint != null
                ? '${state.dewPoint!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Pressure',
            value: state.pressure != null
                ? '${state.pressure!.toStringAsFixed(1)} hPa'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Wind Speed',
            value: state.windSpeed != null
                ? '${state.windSpeed!.toStringAsFixed(1)} km/h'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Wind Direction',
            value: state.windDirection != null
                ? '${state.windDirection!.toStringAsFixed(0)}\u00B0'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Cloud Cover',
            value: state.cloudCover != null
                ? '${state.cloudCover!.toStringAsFixed(0)}%'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Sky Quality',
            value: state.skyQuality != null
                ? '${state.skyQuality!.toStringAsFixed(2)} mag/arcsec\u00B2'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Sky Temp',
            value: state.skyTemperature != null
                ? '${state.skyTemperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Rain Rate',
            value: state.rainRate != null
                ? '${state.rainRate!.toStringAsFixed(1)} mm/h'
                : '---',
            colors: colors,
          ),
          if (state.lastUpdated != null)
            _TelemetryRow(
              label: 'Last Updated',
              value: _formatTimeAgo(state.lastUpdated!),
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Is Safe',
            value: state.isSafe ? 'Yes' : 'No',
            colors: colors,
          ),
          if (state.lastChecked != null)
            _TelemetryRow(
              label: 'Last Checked',
              value: _formatTimeAgo(state.lastChecked!),
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Cover Status',
            value: _coverStatusLabel(state.coverStatus),
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Calibrator',
            value: state.isCalibratorOn ? 'On' : 'Off',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Brightness',
            value: '${state.brightness} / ${state.maxBrightness}',
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
        case ConnectedDeviceType.dome:
          await deviceService.disconnectDome();
          break;
        case ConnectedDeviceType.weather:
          await deviceService.disconnectWeather();
          break;
        case ConnectedDeviceType.safetyMonitor:
          await deviceService.disconnectSafetyMonitor();
          break;
        case ConnectedDeviceType.coverCalibrator:
          await deviceService.disconnectCoverCalibrator();
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
    // Cancel any in-progress warm-up before cooling
    deviceService.cancelWarmCamera();
    try {
      await deviceService.setCameraCooling(
          enabled: true, targetTemp: targetTemp);
      if (mounted) {
        context.showSuccessSnackBar(
            'Cooling to ${targetTemp.toStringAsFixed(0)}C');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to start cooling: $e');
      }
    }
  }

  Future<void> _showCoolingTempDialog(double currentTemp) async {
    final controller =
        TextEditingController(text: currentTemp.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<NightshadeColors>()!;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text('Set Cooling Target',
              style: TextStyle(color: colors.textPrimary)),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Target Temperature (C)',
              labelStyle: TextStyle(color: colors.textMuted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            style: TextStyle(color: colors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
            ),
            TextButton(
              onPressed: () {
                final temp = double.tryParse(controller.text);
                if (temp != null) Navigator.of(ctx).pop(temp);
              },
              child: Text('Set', style: TextStyle(color: colors.primary)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null) {
      ref.read(cameraStateProvider.notifier).setTargetTemp(result);
    }
  }

  Future<void> _handleWarmCamera() async {
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await deviceService.warmCamera();
      if (mounted) {
        context.showSuccessSnackBar('Gradually warming camera (2°C/min)');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to warm up: $e');
      }
    }
  }

  void _handleCancelWarm() {
    final deviceService = ref.read(deviceServiceProvider);
    deviceService.cancelWarmCamera();
    if (mounted) {
      context.showSuccessSnackBar('Warm-up cancelled');
    }
  }

  Future<void> _handleTogglePark() async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.togglePark();
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  Future<void> _handleFindHome() async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.findHome();
    if (!mounted) return;
    context.showCommandActionResult(result);
  }

  Future<void> _handleToggleTracking(bool currentlyTracking) async {
    final mountService = ref.read(mountCommandServiceProvider);
    final result = await mountService.setTracking(!currentlyTracking);
    if (!mounted) return;
    context.showCommandActionResult(result);
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
  // Dome Action Handlers
  // ============================================================================

  Future<void> _handleDomeShutter(ShutterStatus currentStatus) async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      if (currentStatus == ShutterStatus.open) {
        await bridge_api.apiDomeCloseShutter(deviceId: domeState.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Closing dome shutter');
        }
      } else {
        await bridge_api.apiDomeOpenShutter(deviceId: domeState.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Opening dome shutter');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome shutter operation failed: $e');
      }
    }
  }

  Future<void> _handleDomePark(bool isParked) async {
    final domeState = ref.read(domeStateProvider);
    if (domeState.deviceId == null) return;
    try {
      if (!isParked) {
        await bridge_api.apiDomePark(deviceId: domeState.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Parking dome');
        }
      } else {
        // There's no explicit unpark for domes -- slew to home position
        // which effectively unparks. This is the standard ASCOM behavior.
        if (mounted) {
          context.showInfoSnackBar('Slew dome to unpark');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Dome park operation failed: $e');
      }
    }
  }

  // ============================================================================
  // Cover Calibrator Action Handlers
  // ============================================================================

  Future<void> _handleCoverToggle(bool isOpen) async {
    final coverState = ref.read(coverCalibratorStateProvider);
    if (coverState.deviceId == null) return;
    try {
      if (isOpen) {
        await bridge_api.apiCoverCalibratorCloseCover(
            deviceId: coverState.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Closing cover');
        }
      } else {
        await bridge_api.apiCoverCalibratorOpenCover(
            deviceId: coverState.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Opening cover');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Cover operation failed: $e');
      }
    }
  }

  Future<void> _handleCalibratorToggle(CoverCalibratorState state) async {
    if (state.deviceId == null) return;
    try {
      if (state.isCalibratorOn) {
        await bridge_api.apiCoverCalibratorCalibratorOff(
            deviceId: state.deviceId!);
        if (mounted) {
          context.showSuccessSnackBar('Calibrator light off');
        }
      } else {
        // Turn on at current brightness, or max if brightness is 0
        final brightness =
            state.brightness > 0 ? state.brightness : state.maxBrightness;
        await bridge_api.apiCoverCalibratorCalibratorOn(
            deviceId: state.deviceId!, brightness: brightness);
        if (mounted) {
          context.showSuccessSnackBar(
              'Calibrator light on at brightness $brightness');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Calibrator operation failed: $e');
      }
    }
  }

  // ============================================================================
  // Dialogs
  // ============================================================================

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

    if (result != null && context.mounted) {
      final deviceService = ref.read(deviceServiceProvider);
      try {
        await deviceService.moveFocuserTo(result);
        if (!context.mounted) return;
        context.showSuccessSnackBar('Moving focuser to $result');
      } catch (e) {
        if (!context.mounted) return;
        context.showErrorSnackBar('Failed to move focuser: $e');
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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

    if (result != null && context.mounted) {
      final backend = ref.read(backendProvider);
      final rotatorState = ref.read(rotatorStateProvider);
      if (rotatorState.deviceId != null) {
        try {
          await backend.rotatorMoveTo(rotatorState.deviceId!, result);
          if (!context.mounted) return;
          context.showSuccessSnackBar(
              'Rotating to ${result.toStringAsFixed(1)} degrees');
        } catch (e) {
          if (!context.mounted) return;
          context.showErrorSnackBar('Failed to rotate: $e');
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

    if (result != null && context.mounted) {
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
  final Color? valueColor;

  _DeviceMetric({required this.value, required this.label, this.valueColor});
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final NightshadeColors colors;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.onLongPress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onTap == null ? null : onLongPress,
      child: NightshadeButton(
        onPressed: onTap,
        label: label,
        variant: ButtonVariant.outline,
        size: ButtonSize.small,
      ),
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
        onTap: null,
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
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
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
