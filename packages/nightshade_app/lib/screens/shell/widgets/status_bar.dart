import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/device_format_utils.dart';
import '../../../widgets/equipment_status_indicator.dart';
import '../../../widgets/operation_status_bar.dart';
import '../../../widgets/remote_connection_indicator.dart';
import '../../sequencer/widgets/run_dashboard/recovery_banner.dart';

part 'status_bar/sequence_indicator.dart';
part 'status_bar/pill_widgets.dart';
part 'status_bar/web_dashboard_button.dart';
part 'status_bar/session_sharing.dart';
part 'status_bar/temperature_and_time.dart';

class _SavePathStatus {
  final String path;
  final bool exists;

  const _SavePathStatus({
    required this.path,
    required this.exists,
  });
}

final _savePathStatusProvider = FutureProvider<_SavePathStatus>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  final savePath = settings.imageOutputPath.trim();

  if (savePath.isEmpty) {
    return const _SavePathStatus(path: '', exists: false);
  }

  bool exists;
  try {
    exists = await Directory(savePath).exists();
  } catch (_) {
    exists = false;
  }
  return _SavePathStatus(path: savePath, exists: exists);
});

class StatusBar extends ConsumerStatefulWidget {
  /// When true, uses a horizontally scrollable strip and hides desktop-only
  /// actions (web dashboard, share session) to fit phone widths.
  final bool compact;

  const StatusBar({super.key, this.compact = false});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar>
    with WidgetsBindingObserver {
  // Per-second tick driving the clock chip. Suspended when the app is
  // backgrounded — a hidden status bar doesn't need to rebuild 60 times/min.
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_timer == null || !_timer!.isActive) {
        // Resync immediately so the clock doesn't show a stale time.
        _now = DateTime.now();
        _startTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final savePathStatus = ref.watch(_savePathStatusProvider).valueOrNull ??
        const _SavePathStatus(path: '', exists: false);

    // Watch equipment state
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final focuserState = ref.watch(focuserStateProvider);

    final cameraConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final mountConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final guiderConnected =
        guiderState.connectionState == DeviceConnectionState.connected;
    final focuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;
    final savePath = savePathStatus.path;
    final savePathExists = savePathStatus.exists;
    final savePathLabel =
        savePath.isEmpty ? 'No save path' : _formatPathLabel(savePath);
    final savePathTooltip = savePath.isEmpty
        ? 'No image output path configured'
        : savePathExists
            ? 'Images save to $savePath'
            : 'Configured output path is missing: $savePath';

    final leading = <Widget>[
      const SizedBox(width: 12),
      _SequenceIndicator(colors: colors),
      const SizedBox(width: 12),
      _divider(colors),
      const SizedBox(width: 8),
      const EquipmentStatusIndicator(),
      const SizedBox(width: 8),
      _divider(colors),
      const SizedBox(width: 12),
      _StatusPillButton(
        icon: LucideIcons.camera,
        label: 'Camera',
        value: cameraConnected
            ? _getDeviceDisplayName(
                cameraState.deviceName, cameraState.deviceId, 'Connected')
            : 'Disconnected',
        isConnected: cameraConnected,
        colors: colors,
        compact: widget.compact,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: LucideIcons.move3d,
        label: 'Mount',
        value: mountConnected
            ? _getDeviceDisplayName(
                mountState.deviceName, mountState.deviceId, 'Connected')
            : 'Disconnected',
        isConnected: mountConnected,
        colors: colors,
        compact: widget.compact,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: LucideIcons.crosshair,
        label: 'Guider',
        value: guiderConnected
            ? (guiderState.isGuiding ? 'Guiding' : 'Ready')
            : 'Idle',
        isConnected: guiderConnected,
        colors: colors,
        compact: widget.compact,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: LucideIcons.focus,
        label: 'Focus',
        value: focuserConnected
            ? (focuserState.position?.toString() ?? 'Ready')
            : '---',
        isConnected: focuserConnected,
        colors: colors,
        compact: widget.compact,
      ),
      const SizedBox(width: 4),
      _TempCompIndicator(colors: colors),
      const SizedBox(width: 8),
      SequencerStatusLed(showLabel: !widget.compact),
      const OperationStatusBar(),
    ];

    final trailing = <Widget>[
      // On phone, the remote-connection state lives here as a small ambient
      // dot (tap opens the connection sheet) instead of a dedicated top strip,
      // reclaiming the cover-screen's scarce height. Desktop keeps the full
      // indicator in the TitleBar, so the dot is phone-only here.
      if (widget.compact) ...[
        const RemoteConnectionIndicator(dot: true),
        const SizedBox(width: 6),
        _divider(colors),
        const SizedBox(width: 8),
      ],
      _InfoChip(
        icon: LucideIcons.thermometer,
        value: cameraConnected && cameraState.temperature != null
            ? '${cameraState.temperature!.toStringAsFixed(1)}\u00B0C'
            : '---',
        colors: colors,
      ),
      const SizedBox(width: 12),
      if (!widget.compact)
        _InfoChip(
          icon: savePathExists ? LucideIcons.folderOpen : LucideIcons.folderX,
          value: savePathLabel,
          tooltip: savePathTooltip,
          colors: colors,
        ),
      if (!widget.compact) const SizedBox(width: 12),
      if (!widget.compact) ...[
        _divider(colors),
        const SizedBox(width: 8),
        _WebDashboardButton(colors: colors),
        const SizedBox(width: 4),
        _ShareSessionButton(colors: colors),
        const SizedBox(width: 8),
        _divider(colors),
        const SizedBox(width: 12),
      ],
      _TimeDisplay(now: _now, colors: colors),
      const SizedBox(width: 12),
    ];

    return Container(
      height: widget.compact
          ? ShellChromeMetrics.statusBarHeightCompact
          : ShellChromeMetrics.statusBarHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(
            color: colors.border,
            width: 1,
          ),
        ),
      ),
      child: widget.compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [...leading, ...trailing],
              ),
            )
          : Row(
              children: [
                ...leading,
                const Spacer(),
                ...trailing,
              ],
            ),
    );
  }

  String _formatPathLabel(String path) {
    final normalized = p.normalize(path);
    final baseName = p.basename(normalized);
    return baseName.isNotEmpty ? baseName : normalized;
  }

  Widget _divider(NightshadeColors colors) {
    return Container(
      width: 1,
      height: ShellChromeMetrics.statusBarDividerHeight,
      color: colors.border.withValues(alpha: 0.5),
    );
  }
}
