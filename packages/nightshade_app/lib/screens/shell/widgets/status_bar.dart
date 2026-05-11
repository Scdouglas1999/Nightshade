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
  const StatusBar({super.key});

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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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

    return Container(
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surface,
            colors.surface.withValues(alpha: 0.95),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          top: BorderSide(
            color: colors.border,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),

          // Sequence status indicator
          _SequenceIndicator(colors: colors),

          const SizedBox(width: 16),

          Container(
            width: 1,
            height: 20,
            color: colors.border.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 8),

          // Profile-based equipment status indicator with dropdown
          const EquipmentStatusIndicator(),

          const SizedBox(width: 8),

          Container(
            width: 1,
            height: 20,
            color: colors.border.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 16),

          // Equipment status pills (DYNAMIC)
          _StatusPillButton(
            icon: LucideIcons.camera,
            label: 'Camera',
            value: cameraConnected
                ? _getDeviceDisplayName(
                    cameraState.deviceName, cameraState.deviceId, 'Connected')
                : 'Disconnected',
            isConnected: cameraConnected,
            colors: colors,
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
          ),
          const SizedBox(width: 4),
          _TempCompIndicator(colors: colors),

          // Operation progress indicator (when operations are active)
          const OperationStatusBar(),

          const Spacer(),

          // Temperature / weather
          _InfoChip(
            icon: LucideIcons.thermometer,
            value: cameraConnected && cameraState.temperature != null
                ? '${cameraState.temperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          const SizedBox(width: 12),

          // Image output path
          _InfoChip(
            icon: savePathExists ? LucideIcons.folderOpen : LucideIcons.folderX,
            value: savePathLabel,
            tooltip: savePathTooltip,
            colors: colors,
          ),
          const SizedBox(width: 12),

          Container(
            width: 1,
            height: 20,
            color: colors.border.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 8),

          // Web Dashboard button
          _WebDashboardButton(colors: colors),

          const SizedBox(width: 4),

          // Share Session button
          _ShareSessionButton(colors: colors),

          const SizedBox(width: 8),

          Container(
            width: 1,
            height: 20,
            color: colors.border.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 12),

          // Time display
          _TimeDisplay(now: _now, colors: colors),

          const SizedBox(width: 16),
        ],
      ),
    );
  }

  String _formatPathLabel(String path) {
    final normalized = p.normalize(path);
    final baseName = p.basename(normalized);
    return baseName.isNotEmpty ? baseName : normalized;
  }
}

class _SequenceIndicator extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _SequenceIndicator({required this.colors});

  @override
  ConsumerState<_SequenceIndicator> createState() => _SequenceIndicatorState();
}

class _SequenceIndicatorState extends ConsumerState<_SequenceIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final statusText = _statusText(executionState);
    final indicatorColor = _indicatorColor(executionState);
    final progressPercent = progress.totalExposures > 0
        ? (progress.progressPercent * 100).round()
        : null;
    final displayText = progressPercent != null &&
            executionState != SequenceExecutionState.idle &&
            executionState != SequenceExecutionState.completed &&
            executionState != SequenceExecutionState.failed
        ? '$statusText $progressPercent%'
        : statusText;
    final tooltipLines = <String>[
      statusText,
      if ((progress.currentTarget ?? '').isNotEmpty)
        'Target: ${progress.currentTarget}',
      if ((progress.currentNodeName ?? '').isNotEmpty)
        'Step: ${progress.currentNodeName}',
      if ((progress.message ?? '').isNotEmpty) progress.message!,
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final isRunning =
                    executionState == SequenceExecutionState.running;
                final opacity =
                    isRunning ? (0.45 + (_pulseController.value * 0.55)) : 1.0;
                return Opacity(opacity: opacity, child: child);
              },
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: indicatorColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: widget.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _indicatorColor(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.idle:
        return widget.colors.textMuted;
      case SequenceExecutionState.running:
        return widget.colors.success;
      case SequenceExecutionState.paused:
        return widget.colors.warning;
      case SequenceExecutionState.stopping:
        return widget.colors.error;
      case SequenceExecutionState.completed:
        return widget.colors.primary;
      case SequenceExecutionState.failed:
        return widget.colors.error;
    }
  }

  String _statusText(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.idle:
        return 'Idle';
      case SequenceExecutionState.running:
        return 'Running';
      case SequenceExecutionState.paused:
        return 'Paused';
      case SequenceExecutionState.stopping:
        return 'Stopping';
      case SequenceExecutionState.completed:
        return 'Completed';
      case SequenceExecutionState.failed:
        return 'Failed';
    }
  }
}

class _StatusPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isConnected;
  final NightshadeColors colors;

  const _StatusPillButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.isConnected,
    required this.colors,
  });

  @override
  State<_StatusPillButton> createState() => _StatusPillButtonState();
}

class _StatusPillButtonState extends State<_StatusPillButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${widget.label}: ${widget.value}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: widget.isConnected
                    ? widget.colors.success
                    : widget.colors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.colors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  widget.value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isConnected
                      ? widget.colors.success
                      : widget.colors.textMuted.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? tooltip;
  final NightshadeColors colors;

  const _InfoChip({
    required this.icon,
    required this.value,
    this.tooltip,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return child;
    }

    return Tooltip(message: tooltip!, child: child);
  }
}

class _WebDashboardButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _WebDashboardButton({required this.colors});

  @override
  ConsumerState<_WebDashboardButton> createState() =>
      _WebDashboardButtonState();
}

class _WebDashboardButtonState extends ConsumerState<_WebDashboardButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webServerStateProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: webState.isRunning
            ? webState.dashboardAvailable
                ? 'Open local dashboard (${webState.localUrl})'
                : 'Remote access API is running, but the dashboard files are unavailable'
            : 'Remote access is not running',
        child: InkWell(
          onTap: webState.isRunning && webState.dashboardAvailable
              ? () {
                  launchUrl(
                    Uri.parse(webState.localUrl),
                    mode: LaunchMode.externalApplication,
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered && webState.isRunning
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.globe,
                  size: 12,
                  color: webState.isRunning && webState.dashboardAvailable
                      ? widget.colors.primary
                      : widget.colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 11,
                    color: webState.isRunning && webState.dashboardAvailable
                        ? widget.colors.textSecondary
                        : widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareSessionButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _ShareSessionButton({required this.colors});

  @override
  ConsumerState<_ShareSessionButton> createState() =>
      _ShareSessionButtonState();
}

class _ShareSessionButtonState extends ConsumerState<_ShareSessionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webServerStateProvider);
    final hasViewers = webState.activeViewers > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: webState.isRunning
            ? webState.bindLocalOnly
                ? 'Remote access is limited to this machine'
                : webState.requiresAuthentication
                    ? 'Remote access details and pairing'
                    : 'Remote access details'
            : 'Remote access is not running',
        child: InkWell(
          onTap: webState.isRunning
              ? () => _showShareDialog(context, webState)
              : null,
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered && webState.isRunning
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.share2,
                  size: 12,
                  color: hasViewers
                      ? widget.colors.success
                      : webState.isRunning
                          ? widget.colors.textSecondary
                          : widget.colors.textMuted,
                ),
                if (hasViewers) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: widget.colors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${webState.activeViewers}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.success,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showShareDialog(BuildContext context, WebServerState webState) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      builder: (context) => _ShareSessionDialog(
        webState: webState,
        colors: colors,
      ),
    );
  }
}

class _ShareSessionDialog extends ConsumerWidget {
  final WebServerState webState;
  final NightshadeColors colors;

  const _ShareSessionDialog({
    required this.webState,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentState = ref.watch(webServerStateProvider);
    final networkUrl = currentState.networkUrl;
    final hasLanAccess = networkUrl.isNotEmpty;
    final viewerLabel =
        currentState.requiresAuthentication ? 'authenticated viewer' : 'viewer';

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: [
          Icon(LucideIcons.share2, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            'Remote Access',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentState.bindLocalOnly
                  ? 'Remote access is currently limited to this machine.'
                  : currentState.requiresAuthentication
                      ? 'Local access works immediately on this machine. Remote browsers on your LAN must pair before they can control the app.'
                      : 'Remote access is available on your local network.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _UrlCard(
              label: 'Local dashboard',
              url: currentState.localUrl,
              colors: colors,
            ),
            if (hasLanAccess) ...[
              const SizedBox(height: 12),
              _UrlCard(
                label: currentState.requiresAuthentication
                    ? 'LAN endpoint (paired devices only)'
                    : 'LAN endpoint',
                url: networkUrl,
                colors: colors,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentState.activeViewers > 0
                    ? colors.success.withValues(alpha: 0.08)
                    : colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: currentState.activeViewers > 0
                      ? colors.success.withValues(alpha: 0.3)
                      : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.users,
                    size: 14,
                    color: currentState.activeViewers > 0
                        ? colors.success
                        : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentState.activeViewers > 0
                        ? '${currentState.activeViewers} $viewerLabel${currentState.activeViewers == 1 ? '' : 's'} connected'
                        : 'No viewers connected',
                    style: TextStyle(
                      fontSize: 13,
                      color: currentState.activeViewers > 0
                          ? colors.success
                          : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (currentState.lastError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 14,
                      color: colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentState.lastError,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _UrlCard extends StatelessWidget {
  final String label;
  final String url;
  final NightshadeColors colors;

  const _UrlCard({
    required this.label,
    required this.url,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.link, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  url,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Link copied to clipboard'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: colors.surfaceAlt,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.copy,
                        size: 12,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small indicator showing temp comp status next to focus pill.
/// Only visible when the focuser is connected and has temperature data.
class _TempCompIndicator extends ConsumerWidget {
  final NightshadeColors colors;

  const _TempCompIndicator({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focuserState = ref.watch(focuserStateProvider);
    final focuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;

    // Only show when focuser is connected and reports temperature
    if (!focuserConnected || focuserState.temperature == null) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final tempCompEnabled = settings?.tempCompensation ?? false;

    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) return const SizedBox.shrink();

    final profileId = activeProfile.id.toString();
    final focusService = ref.watch(focusModelServiceProvider);
    final profileData = focusService.getProfileData(profileId);
    final model = profileData?.temperatureModel;
    final hasReliableModel = model != null && model.isReliable;

    // Determine state
    Color indicatorColor;
    String tooltip;

    if (!tempCompEnabled) {
      indicatorColor = colors.textMuted;
      tooltip = 'Temp compensation disabled';
    } else if (!hasReliableModel) {
      indicatorColor = colors.warning;
      tooltip = model == null
          ? 'Temp comp enabled - no model data'
          : 'Temp comp enabled - model not yet reliable (R\u00B2=${model.rSquared.toStringAsFixed(2)})';
    } else {
      final prediction = focusService.predictFocusPosition(
        profileId: profileId,
        currentTemperature: focuserState.temperature!,
      );
      indicatorColor = colors.success;
      tooltip = prediction != null
          ? 'Temp comp active: ${model.slope.toStringAsFixed(1)} steps/\u00B0C, predicted ${prediction.position}'
          : 'Temp comp active: ${model.slope.toStringAsFixed(1)} steps/\u00B0C';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: indicatorColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.thermometerSun, size: 10, color: indicatorColor),
            const SizedBox(width: 3),
            Text(
              'TC',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: indicatorColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDisplay extends ConsumerWidget {
  final DateTime now;
  final NightshadeColors colors;

  const _TimeDisplay({
    required this.now,
    required this.colors,
  });

  String _formatLST(double lstHours) {
    final h = lstHours.floor();
    final m = ((lstHours - h) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lst = ref.watch(localSiderealTimeProvider);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Icon(
          LucideIcons.clock,
          size: 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'LST ${_formatLST(lst)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
