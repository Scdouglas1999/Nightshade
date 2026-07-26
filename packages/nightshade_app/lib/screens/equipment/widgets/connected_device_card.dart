import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../services/mount_command_service.dart';
import '../../../utils/authority_bound_dialog.dart';
import '../../../utils/cooled_camera_guard.dart';
import '../../../utils/device_format_utils.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/troubleshooter/connection_troubleshooter_dialog.dart';
import '../utils/device_error_subtitle.dart';

part 'connected_device_card/status_and_display.dart';
part 'connected_device_card/actions_and_telemetry.dart';
part 'connected_device_card/command_handlers.dart';
part 'connected_device_card/dialogs_and_settings.dart';
part 'connected_device_card/helper_widgets.dart';

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

/// Narrow adapters keep the equipment card on the canonical weather-safety
/// state machine while allowing the quick-action surface to be tested without
/// constructing its long-lived polling timers.
final equipmentSafetySnoozeStatusProvider = Provider<WeatherSafetyStatus>(
  (ref) => ref.watch(weatherSafetyProvider).status,
);

final equipmentSafetySnoozeActionProvider =
    Provider<void Function(Duration)>((ref) {
  return (duration) =>
      ref.read(weatherSafetyProvider.notifier).snooze(duration);
});

final equipmentSafetyCancelSnoozeActionProvider = Provider<VoidCallback>(
  (ref) => ref.read(weatherSafetyProvider.notifier).cancelSnooze,
);

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
  ///   - imaging chain (capture)            -> `colors.primary`  (cyan-blue)
  ///       - camera
  ///   - sky pointing / mechanical          -> `colors.warning`  (amber)
  ///       - mount
  ///       - rotator
  ///       - dome
  ///   - opto-mechanical adjusters          -> `colors.accent`   (light cyan)
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
  /// Maps the card's local device-type enum to the canonical core
  /// [DeviceType] consumed by the connection troubleshooter (so its
  /// classifier produces hardware-aware copy: "camera" vs "mount", etc.).
  DeviceType get coreDeviceType {
    switch (this) {
      case ConnectedDeviceType.camera:
        return DeviceType.camera;
      case ConnectedDeviceType.mount:
        return DeviceType.mount;
      case ConnectedDeviceType.focuser:
        return DeviceType.focuser;
      case ConnectedDeviceType.filterWheel:
        return DeviceType.filterWheel;
      case ConnectedDeviceType.guider:
        return DeviceType.guider;
      case ConnectedDeviceType.rotator:
        return DeviceType.rotator;
      case ConnectedDeviceType.dome:
        return DeviceType.dome;
      case ConnectedDeviceType.weather:
        return DeviceType.weather;
      case ConnectedDeviceType.safetyMonitor:
        return DeviceType.safetyMonitor;
      case ConnectedDeviceType.coverCalibrator:
        return DeviceType.coverCalibrator;
    }
  }

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

  const ConnectedDeviceCard({
    super.key,
    required this.type,
    this.onDisconnect,
    this.onSettings,
  });

  @override
  ConsumerState<ConnectedDeviceCard> createState() =>
      _ConnectedDeviceCardState();
}

class _ConnectedDeviceCardState extends ConsumerState<ConnectedDeviceCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _deviceCommandInFlight = false;
  bool _mountCommandInFlight = false;
  bool _domeCommandInFlight = false;
  bool _coverCalibratorCommandInFlight = false;
  int _commandRevision = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        _commandRevision++;
        if (mounted &&
            (_deviceCommandInFlight ||
                _mountCommandInFlight ||
                _domeCommandInFlight ||
                _coverCalibratorCommandInFlight)) {
          setState(() {
            _deviceCommandInFlight = false;
            _mountCommandInFlight = false;
            _domeCommandInFlight = false;
            _coverCalibratorCommandInFlight = false;
          });
        }
      },
    );
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
    _backendSubscription?.close();
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

  bool get _anyCommandInFlight =>
      _deviceCommandInFlight ||
      _mountCommandInFlight ||
      _domeCommandInFlight ||
      _coverCalibratorCommandInFlight;

  int? _beginDeviceCommand() {
    if (_anyCommandInFlight) return null;
    final revision = ++_commandRevision;
    setState(() => _deviceCommandInFlight = true);
    return revision;
  }

  int? _beginMountCommand() {
    if (_anyCommandInFlight) return null;
    final revision = ++_commandRevision;
    setState(() => _mountCommandInFlight = true);
    return revision;
  }

  int? _beginDomeCommand() {
    if (_anyCommandInFlight) return null;
    final revision = ++_commandRevision;
    setState(() => _domeCommandInFlight = true);
    return revision;
  }

  int? _beginCoverCalibratorCommand() {
    if (_anyCommandInFlight) return null;
    final revision = ++_commandRevision;
    setState(() => _coverCalibratorCommandInFlight = true);
    return revision;
  }

  void _finishDeviceCommand(int revision, NightshadeBackend backend) {
    if (!mounted ||
        revision != _commandRevision ||
        !identical(ref.read(backendProvider), backend)) {
      return;
    }
    setState(() => _deviceCommandInFlight = false);
  }

  void _finishMountCommand(int revision, NightshadeBackend backend) {
    if (!mounted ||
        revision != _commandRevision ||
        !identical(ref.read(backendProvider), backend)) {
      return;
    }
    setState(() => _mountCommandInFlight = false);
  }

  void _finishDomeCommand(int revision, NightshadeBackend backend) {
    if (!mounted ||
        revision != _commandRevision ||
        !identical(ref.read(backendProvider), backend)) {
      return;
    }
    setState(() => _domeCommandInFlight = false);
  }

  void _finishCoverCalibratorCommand(
    int revision,
    NightshadeBackend backend,
  ) {
    if (!mounted ||
        revision != _commandRevision ||
        !identical(ref.read(backendProvider), backend)) {
      return;
    }
    setState(() => _coverCalibratorCommandInFlight = false);
  }

  /// Presents a device dialog that belongs to exactly one imaging host.
  ///
  /// Equipment IDs and capability snapshots are host-owned. If the user
  /// changes rigs while a dialog is open, remove that route before it can
  /// dispatch the old device state through the new host's providers.
  Future<T?> _showEquipmentDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    final authority = ref.read(backendProvider);
    BuildContext? dialogContext;
    var authorityChanged = false;
    final subscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(next, authority)) return;
        authorityChanged = true;
        final routeContext = dialogContext;
        if (routeContext != null && routeContext.mounted) {
          closeAuthorityBoundDialog(routeContext);
        }
      },
    );

    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (routeContext) {
          dialogContext = routeContext;
          if (authorityChanged ||
              !identical(ref.read(backendProvider), authority)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (routeContext.mounted) {
                closeAuthorityBoundDialog(routeContext);
              }
            });
          }
          return builder(routeContext);
        },
      );
    } finally {
      subscription.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final connectionState = _getConnectionState();
    final borderColor = _getBorderColor(connectionState, colors);
    final accentColor = widget.type.accentColor(colors);

    // On desktop/tablet a fixed tile width keeps the Wrap layout tidy
    // (audit §4.21): 320 px fits the longest action labels (e.g. "Stop
    // Tracking") without wrap and keeps two columns at 720+ px. On a phone
    // (`width < 600`) the dashboard lays cards out one-per-row full-width, so
    // the card stretches to the column instead of pinning to 320 and
    // overflowing a 360 px viewport.
    final cardWidth = Responsive.isPhone(context) ? double.infinity : 320.0;

    // On a phone (especially landscape, ~410 px tall) the desktop card padding
    // and inter-section gaps crowd device cards off-screen; tighten them so
    // more cards fit without clipping.
    final isPhone = Responsive.isPhone(context);
    final cardPad = isPhone ? 14.0 : 20.0;
    final sectionGap = isPhone ? 12.0 : 16.0;

    return SizedBox(
      width: cardWidth,
      child: GestureDetector(
        onTap: _toggleExpanded,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(cardPad),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              _buildHeader(colors, accentColor, connectionState),

              // Troubleshooter-backed error subtitle + Diagnose
              // affordance, shown only when the device is in an error state.
              _buildErrorSubtitle(colors, connectionState),

              SizedBox(height: sectionGap),

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
}
