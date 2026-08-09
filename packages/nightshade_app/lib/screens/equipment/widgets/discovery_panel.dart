import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../mixins/device_connection_mixin.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/troubleshooter/connection_troubleshooter_dialog.dart';
import '../dialogs/fujifilm_disclaimer_dialog.dart';

part 'discovery_panel/device_row_item.dart';

/// Action for assigning a device to a profile
class AssignAction {
  final int profileId;
  final DeviceType deviceType;

  const AssignAction({
    required this.profileId,
    required this.deviceType,
  });
}

/// Provider to track when the last scan occurred
// autoDispose: the "last scan: N seconds ago" label is only meaningful while
// the Equipment screen is mounted. Resetting on screen teardown avoids
// stale "last scan: 6 hours ago" strings from a previous session.
final lastScanTimeProvider =
    StateProvider.autoDispose<DateTime?>((ref) => null);

/// A collapsible panel at the bottom of the equipment screen for discovering devices.
/// Shows available backends, discovered devices grouped by type, and connection controls.
class DiscoveryPanel extends ConsumerStatefulWidget {
  /// Optional callback when a device is assigned to a profile
  final ValueChanged<(DeviceInfo, int)>? onAssignDevice;

  const DiscoveryPanel({super.key, this.onAssignDevice});

  @override
  ConsumerState<DiscoveryPanel> createState() => _DiscoveryPanelState();

  /// Derives the troubleshooter inputs from the backend the user actually tried
  /// to connect and shows [ConnectionTroubleshooterDialog], resolving to `true`
  /// when the user asked to retry.
  ///
  /// Exposed for testing so the connect-failure → troubleshooter orchestration
  /// can be exercised directly without standing up the full discovery panel and
  /// its device-state providers. The caller is responsible for the `mounted`
  /// guards around the (async) dialog.
  /// Resolves the namespaced [DriverType] for the backend the user actually
  /// tried to connect, so the troubleshooter playbook is protocol-aware.
  ///
  /// `availableBackends` may not contain the resolved key in pathological
  /// cases, so we fall back to the backend identity itself rather than
  /// guessing. This is the authoritative resolution for the discovery surface
  /// (more accurate than deriving the driver from the device-id prefix), and it
  /// is shared by both the inline connect path and the test-only
  /// [showConnectionTroubleshooter] entry point.
  @visibleForTesting
  static DriverType resolveDriverType(UnifiedDevice device) {
    final backend = device.selectedBackend ?? device.recommendedBackend;
    final info = device.availableBackends[backend];
    return info?.driverType ?? backend;
  }

  @visibleForTesting
  static Future<bool> showConnectionTroubleshooter(
    BuildContext context,
    UnifiedDevice device,
    Object error,
  ) {
    return ConnectionTroubleshooterDialog.show(
      context,
      deviceType: device.type,
      driverType: resolveDriverType(device),
      rawError: error.toString(),
    );
  }
}

class _DiscoveryPanelState extends ConsumerState<DiscoveryPanel>
    with
        SingleTickerProviderStateMixin,
        DeviceConnectionMixin,
        WidgetsBindingObserver {
  bool _isExpanded = false;
  bool _isScanning = false;
  // True while the Rust-side manual hot-plug rescan is running. Kept
  // separate from `_isScanning` (the full Dart-side unified discovery)
  // because the two actions have different latencies and we don't want
  // the "Rescanning..." spinner blocking the much longer "Scan All".
  bool _isRescanning = false;
  int _operationGeneration = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  // 30s tick refreshes the "Last scan: N seconds ago" label. Suspended when
  // the app is backgrounded so a hidden equipment tab doesn't tick (§4.33).
  Timer? _lastScanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _operationGeneration++;
        if (mounted && (_isScanning || _isRescanning)) {
          setState(() {
            _isScanning = false;
            _isRescanning = false;
          });
        }
      },
    );
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );
    _startLastScanTimer();
  }

  void _startLastScanTimer() {
    _lastScanTimer?.cancel();
    _lastScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastScanTimer == null || !_lastScanTimer!.isActive) {
        if (mounted) setState(() {});
        _startLastScanTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lastScanTimer?.cancel();
      _lastScanTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operationGeneration++;
    _backendSubscription?.close();
    _expandController.dispose();
    _lastScanTimer?.cancel();
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

  Future<void> _scanForDevices() async {
    if (_isScanning || _isRescanning) return;
    final authority = ref.read(backendProvider);
    final generation = ++_operationGeneration;
    setState(() => _isScanning = true);
    try {
      // discoverAll clears stale grouped results before scanning.
      await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
      if (_isCurrentOperation(generation, authority, scanning: true)) {
        final completedAt =
            ref.read(unifiedDiscoveryProvider).lastDiscoveryCompletedAt;
        ref.read(lastScanTimeProvider.notifier).state =
            completedAt ?? DateTime.now();
      }
    } catch (e) {
      if (mounted &&
          _isCurrentOperation(generation, authority, scanning: true)) {
        context.showErrorSnackBar('Equipment scan failed: $e');
      }
    } finally {
      if (_isCurrentOperation(generation, authority, scanning: true)) {
        setState(() => _isScanning = false);
      }
    }
  }

  /// Trigger the host-side hot-plug diff pass.
  ///
  /// This is the lightweight cousin of `_scanForDevices`. The Rust bridge
  /// has a hybrid hot-plug architecture (`bridge/src/hotplug.rs`):
  ///   * Kernel-event listener (WM_DEVICECHANGE / libusb hotplug) for
  ///     sub-second USB arrival latency.
  ///   * 30 s slow poll catching ASCOM-registry / serial-port changes.
  /// Pressing Rescan forces an off-cadence diff cycle for users who plug
  /// in a device the kernel didn't surface (quirky hub, ASCOM driver
  /// install, etc.). Arrival / removal events flow over the equipment
  /// event stream and trigger the unified discovery provider to refresh
  /// without a full backend scan.
  ///
  /// Routed through [DeviceBackend.rescanDevices] rather than calling the
  /// `bridge_api` FFI directly so it reaches the backend that actually owns
  /// the hardware buses. On a remote client (phone) a direct FFI call would
  /// rescan the phone's empty local backend and falsely report success; the
  /// backend op POSTs to the HOST instead. On the desktop host the same op
  /// resolves to the FfiBackend and drives the local hot-plug pass unchanged.
  Future<void> _rescanEquipment() async {
    if (_isRescanning || _isScanning) return;
    final authority = ref.read(backendProvider);
    final backend = ref.read(deviceBackendProvider);
    final generation = ++_operationGeneration;
    setState(() => _isRescanning = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await backend.rescanDevices();
      if (mounted &&
          _isCurrentOperation(generation, authority, rescanning: true) &&
          identical(ref.read(deviceBackendProvider), backend)) {
        context.showSuccessSnackBar('Equipment rescan complete');
      }
    } catch (e) {
      // Surface failures loudly — errors are a feature.
      if (_isCurrentOperation(generation, authority, rescanning: true)) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Rescan failed: $e')),
        );
      }
    } finally {
      if (_isCurrentOperation(generation, authority, rescanning: true)) {
        setState(() => _isRescanning = false);
      }
    }
  }

  bool _isCurrentOperation(
    int generation,
    NightshadeBackend authority, {
    bool scanning = false,
    bool rescanning = false,
  }) =>
      mounted &&
      generation == _operationGeneration &&
      identical(ref.read(backendProvider), authority) &&
      (!scanning || _isScanning) &&
      (!rescanning || _isRescanning);

  String _formatLastScanTime(DateTime? lastScan) {
    if (lastScan == null) return 'Never scanned';

    final now = DateTime.now();
    final difference = now.difference(lastScan);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    } else {
      return 'Over a day ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final discoveryState = ref.watch(unifiedDiscoveryProvider);
    final lastScanTime = ref.watch(lastScanTimeProvider);
    final groupedDevices = discoveryState.groupedDevices;
    final isDiscovering = discoveryState.isDiscovering || _isScanning;
    final discoveryCompletedAt = discoveryState.lastDiscoveryCompletedAt;

    // Count discovered devices by type
    final cameras =
        groupedDevices.where((d) => d.type == DeviceType.camera).toList();
    final mounts =
        groupedDevices.where((d) => d.type == DeviceType.mount).toList();
    final focusers =
        groupedDevices.where((d) => d.type == DeviceType.focuser).toList();
    final filterWheels =
        groupedDevices.where((d) => d.type == DeviceType.filterWheel).toList();
    final guiders =
        groupedDevices.where((d) => d.type == DeviceType.guider).toList();
    final rotators =
        groupedDevices.where((d) => d.type == DeviceType.rotator).toList();
    final domes =
        groupedDevices.where((d) => d.type == DeviceType.dome).toList();
    final weatherStations =
        groupedDevices.where((d) => d.type == DeviceType.weather).toList();
    final safetyMonitors = groupedDevices
        .where((d) => d.type == DeviceType.safetyMonitor)
        .toList();
    final coverCalibrators = groupedDevices
        .where((d) => d.type == DeviceType.coverCalibrator)
        .toList();
    // Switches (power boxes, dew-heater controllers) were the only first-class
    // device type with NO discovery section, so the profile editor was the sole
    // way to reach one — even though the backend runs a Switch discovery pass and
    // reports it identically to cover calibrators, which DID get an empty state.
    final switches =
        groupedDevices.where((d) => d.type == DeviceType.switch_).toList();

    final totalDevices = groupedDevices.length;
    final lastScanText = _formatLastScanTime(
      lastScanTime ?? discoveryCompletedAt,
    );

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar - always visible
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < BreakpointTokens.breakpointPhone;

                  final summary = Text(
                    '$totalDevices device${totalDevices == 1 ? '' : 's'} found  \u2022  Last scan: $lastScanText',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  );

                  final scanButton = NightshadeButton(
                    label: compact
                        ? ''
                        : (isDiscovering ? 'Scanning...' : 'Scan All'),
                    icon: LucideIcons.search,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    isLoading: isDiscovering,
                    onPressed: (isDiscovering || _isRescanning)
                        ? null
                        : _scanForDevices,
                  );

                  // "Rescan equipment" — triggers the Rust hot-plug diff
                  // pass for USB/native/ASCOM devices. Distinct from
                  // "Scan All" (which runs the full Dart-side unified
                  // discovery including Alpaca broadcast and INDI polls).
                  // Lives next to Scan All as an icon-only button so the
                  // header stays compact on phone widths.
                  final rescanButton = IconButton(
                    onPressed: (_isRescanning || isDiscovering)
                        ? null
                        : _rescanEquipment,
                    icon: _isRescanning
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: colors.textSecondary,
                            ),
                          )
                        : Icon(
                            LucideIcons.refreshCw,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                    tooltip: _isRescanning
                        ? 'Rescanning equipment...'
                        : 'Rescan equipment (USB / native / ASCOM)',
                    style: IconButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );

                  final expandControl = InkWell(
                    onTap: _toggleExpanded,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius:
                            BorderRadius.circular(NightshadeTokens.radiusMd),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!compact) ...[
                            Text(
                              _isExpanded ? 'Collapse' : 'Expand',
                              style: NightshadeTypography.labelQuiet
                                  .copyWith(color: colors.textSecondary),
                            ),
                            const SizedBox(width: 4),
                          ],
                          AnimatedRotation(
                            turns: _isExpanded ? 0 : 0.5,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              LucideIcons.chevronDown,
                              size: 14,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.radar,
                              size: 18,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'DISCOVERY',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            rescanButton,
                            const SizedBox(width: 4),
                            scanButton,
                            const SizedBox(width: 8),
                            expandControl,
                          ],
                        ),
                        const SizedBox(height: 6),
                        summary,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Icon(
                        LucideIcons.radar,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'DISCOVERY',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: summary),
                      const SizedBox(width: 12),
                      rescanButton,
                      const SizedBox(width: 4),
                      scanButton,
                      const SizedBox(width: 8),
                      expandControl,
                    ],
                  );
                },
              ),
            ),
          ),

          // Expanded content. Flexible(loose): under a tight parent (phone
          // column with the readiness checklist expanded) this section takes
          // the remaining height and scrolls inside, instead of insisting on
          // its intrinsic size and overflowing the panel by hundreds of px.
          Flexible(
            child: SizeTransition(
              sizeFactor: _expandAnimation,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                constraints: const BoxConstraints(maxHeight: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Server configuration hint
                      if (!Platform.isWindows) _buildINDIServerHint(colors),

                      // Device lists by type (always show, even if empty for that type)
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'CAMERAS',
                        DeviceType.camera,
                        LucideIcons.camera,
                        cameras,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'MOUNTS',
                        DeviceType.mount,
                        LucideIcons.compass,
                        mounts,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'FOCUSERS',
                        DeviceType.focuser,
                        LucideIcons.focus,
                        focusers,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'FILTER WHEELS',
                        DeviceType.filterWheel,
                        LucideIcons.disc,
                        filterWheels,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'GUIDERS',
                        DeviceType.guider,
                        LucideIcons.crosshair,
                        guiders,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'ROTATORS',
                        DeviceType.rotator,
                        LucideIcons.rotateCw,
                        rotators,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'DOMES',
                        DeviceType.dome,
                        LucideIcons.home,
                        domes,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'WEATHER',
                        DeviceType.weather,
                        LucideIcons.cloud,
                        weatherStations,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'SAFETY MONITORS',
                        DeviceType.safetyMonitor,
                        LucideIcons.shieldAlert,
                        safetyMonitors,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'COVER / CALIBRATORS',
                        DeviceType.coverCalibrator,
                        LucideIcons.sunMedium,
                        coverCalibrators,
                      ),
                      const SizedBox(height: 12),
                      _buildDeviceGroupSection(
                        context,
                        colors,
                        'SWITCHES',
                        DeviceType.switch_,
                        LucideIcons.toggleRight,
                        switches,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGroupSection(
    BuildContext context,
    NightshadeColors colors,
    String title,
    DeviceType deviceType,
    IconData icon,
    List<UnifiedDevice> devices,
  ) {
    // Zero-result classes get the SAME chrome as every other class. They used
    // to collapse to one italic "No switches found" line: no count, no clue
    // which backends had been asked, and no route to adding one — while the
    // log recorded "Discovery complete for Switch: 0 devices, 0 backend
    // errors". The section that says nothing was found is exactly where the
    // reason for that belongs.
    final isEmpty = devices.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: isEmpty ? 4 : 12,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                // Expanded rather than a bare Text + Spacer: the empty-class
                // variant adds a rescan IconButton to this row, and on a 360dp
                // phone the longest class names ("Cover Calibrators") plus the
                // count plus that button overflowed the header by 24px. Taking
                // the slack here lets the title ellipsize instead, and the
                // rendered layout is unchanged wherever it already fitted.
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${devices.length} found',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textMuted,
                  ),
                ),
                if (isEmpty)
                  IconButton(
                    onPressed: _scanForDevices,
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    tooltip: 'Scan for ${title.toLowerCase()}',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: colors.textMuted,
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
              ],
            ),
          ),
          // Divider
          Divider(height: 1, color: colors.border.withValues(alpha: 0.5)),
          if (isEmpty)
            _buildEmptyClassBody(context, colors, title)
          else
            // Device list
            ...devices.map((device) => _DeviceRowItem(
                  device: device,
                  deviceType: deviceType,
                  onConnect: () => _connectDevice(device),
                  onDisconnect: () => _disconnectDevice(device.type),
                  onAssignDevice: widget.onAssignDevice,
                )),
        ],
      ),
    );
  }

  /// What a zero-result class says: which backends were actually asked, which
  /// of them failed, and where to configure a remote server — the three things
  /// the operator needs and the bare "No switches found" line withheld.
  Widget _buildEmptyClassBody(
    BuildContext context,
    NightshadeColors colors,
    String title,
  ) {
    final discoveryState = ref.watch(unifiedDiscoveryProvider);
    final searched = discoveryState.backendStates.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final failed = discoveryState.errorBackends.toSet();

    final String detail;
    if (searched.isEmpty) {
      detail = 'Not searched yet — run a scan.';
    } else {
      final names = searched.map((b) {
        final label = b.displayName;
        return failed.contains(b) ? '$label (failed)' : label;
      }).join(', ');
      detail = 'Searched: $names';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: failed.isEmpty ? colors.textMuted : colors.warning,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Devices on another machine are reached over Alpaca or INDI — set '
            'the server address in Settings → Connection.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildINDIServerHint(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: NightshadeDecorations.emphasisSurface(
          colors.info,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 16, color: colors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Configure INDI servers in Settings to discover remote devices.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectDevice(UnifiedDevice device) async {
    final deviceService = ref.read(deviceServiceProvider);
    final deviceId = device.activeDeviceId;

    // Fujifilm warranty disclaimer check — must clear before we attempt the
    // connection, so it stays out of the shared mixin connect path.
    if (device.type == DeviceType.camera &&
        isFujifilmDevice(deviceId, device.displayName)) {
      final accepted = await showFujifilmDisclaimerIfNeeded(context);
      if (!accepted) return;
    }

    // Route through the shared [DeviceConnectionMixin.connectDevice] so the
    // guided troubleshooter recovery (bounded single retry, raw error carried
    // verbatim into the dialog's "Technical details") is the one canonical
    // connect path for the equipment surfaces — not a fork duplicated here.
    //
    // We pass the backend-resolved [DriverType] (more accurate than the mixin's
    // device-id-prefix fallback) and the device type so the opt-in
    // troubleshooter branch fires. The per-type connect dispatch lives in
    // [connectFn]; the success toast lives in [onConnected] so it only fires on
    // a genuinely successful connection.
    await connectDevice(
      deviceId: deviceId,
      deviceName: device.displayName,
      deviceType: device.type,
      driverType: DiscoveryPanel.resolveDriverType(device),
      connectFn: (id) => _dispatchConnect(deviceService, device.type, id),
      onConnected: () async {
        if (mounted) {
          context.showSuccessSnackBar('Connected to ${device.displayName}');
        }
      },
    );
  }

  /// Per-device-type connect dispatch shared by the discovery connect path.
  /// Throws for unsupported types so the mixin surfaces the failure through the
  /// troubleshooter rather than silently no-op'ing (errors-are-a-feature).
  Future<void> _dispatchConnect(
    DeviceService deviceService,
    DeviceType type,
    String deviceId,
  ) {
    switch (type) {
      case DeviceType.camera:
        return deviceService.connectCamera(deviceId);
      case DeviceType.mount:
        return deviceService.connectMount(deviceId);
      case DeviceType.focuser:
        return deviceService.connectFocuser(deviceId);
      case DeviceType.filterWheel:
        return deviceService.connectFilterWheel(deviceId);
      case DeviceType.guider:
        return deviceService.connectGuider(deviceId);
      case DeviceType.rotator:
        return deviceService.connectRotator(deviceId);
      case DeviceType.dome:
        return deviceService.connectDome(deviceId);
      case DeviceType.weather:
        return deviceService.connectWeather(deviceId);
      case DeviceType.safetyMonitor:
        return deviceService.connectSafetyMonitor(deviceId);
      case DeviceType.coverCalibrator:
        return deviceService.connectCoverCalibrator(deviceId);
      case DeviceType.switch_:
        return deviceService.connectSwitch(deviceId);
    }
  }

  Future<void> _disconnectDevice(DeviceType deviceType) async {
    final deviceService = ref.read(deviceServiceProvider);

    try {
      switch (deviceType) {
        case DeviceType.camera:
          await deviceService.disconnectCamera();
          break;
        case DeviceType.mount:
          await deviceService.disconnectMount();
          break;
        case DeviceType.focuser:
          await deviceService.disconnectFocuser();
          break;
        case DeviceType.filterWheel:
          await deviceService.disconnectFilterWheel();
          break;
        case DeviceType.guider:
          await deviceService.disconnectGuider();
          break;
        case DeviceType.rotator:
          await deviceService.disconnectRotator();
          break;
        case DeviceType.dome:
          await deviceService.disconnectDome();
          break;
        case DeviceType.weather:
          await deviceService.disconnectWeather();
          break;
        case DeviceType.safetyMonitor:
          await deviceService.disconnectSafetyMonitor();
          break;
        case DeviceType.coverCalibrator:
          await deviceService.disconnectCoverCalibrator();
          break;
        case DeviceType.switch_:
          await deviceService.disconnectSwitch();
          break;
      }
      if (mounted) {
        context.showSuccessSnackBar(
            'Disconnected ${deviceType.displayName.toLowerCase()}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to disconnect: $e');
      }
    }
  }
}
