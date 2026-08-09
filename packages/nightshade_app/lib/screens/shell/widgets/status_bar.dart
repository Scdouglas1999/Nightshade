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

import '../../../localization/nightshade_localizations.dart';
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

/// What the shell actually knows about the configured capture directory.
///
/// [unknown] is a first-class answer: settings may still be loading, or the
/// existence probe may have failed (a remote host that did not answer). It must
/// never be collapsed into [missing] — "your output path is gone" is an alarm,
/// and raising it because a check has not finished yet is a lie.
enum SavePathExistence { unknown, present, missing }

@visibleForTesting
class SavePathStatus {
  final String path;
  final SavePathExistence existence;

  const SavePathStatus({
    required this.path,
    required this.existence,
  });
}

final _savePathStatusProvider = FutureProvider<SavePathStatus>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  final savePath = settings.imageOutputPath.trim();

  if (savePath.isEmpty) {
    // Genuinely nothing configured — that IS the finding, not an unknown.
    return const SavePathStatus(
      path: '',
      existence: SavePathExistence.missing,
    );
  }

  final backend = ref.watch(backendProvider);
  try {
    final exists = await configuredSavePathExists(backend, savePath);
    return SavePathStatus(
      path: savePath,
      existence: exists ? SavePathExistence.present : SavePathExistence.missing,
    );
  } catch (_) {
    // The probe itself failed (remote host unreachable, permission error). We
    // do not know whether the directory is there.
    return SavePathStatus(
      path: savePath,
      existence: SavePathExistence.unknown,
    );
  }
});

/// How confident the save-path chip is allowed to look.
enum SavePathTone {
  /// Verified: the configured directory is there.
  ok,

  /// Not assessed (probe unfinished or failed). Neutral — never an alarm.
  unknown,

  /// Known bad: nothing configured, or the configured directory is gone.
  alarm,
}

/// The save-path chip's rendering, derived from what is actually known.
@visibleForTesting
class SavePathChip {
  final String label;
  final String tooltip;
  final SavePathTone tone;

  const SavePathChip({
    required this.label,
    required this.tooltip,
    required this.tone,
  });
}

/// Maps the async save-path probe onto chip text.
///
/// Pure and directly testable. The previous code did
/// `status.valueOrNull ?? const _SavePathStatus(path: '', exists: false)`, so
/// every moment before the probe resolved — and every re-run of it, e.g. after a
/// settings or backend change — the bar claimed "No save path" / "No image
/// output path configured" with the folder-X alarm icon, on a rig whose path was
/// configured and fine. On a remote backend that window is a full network
/// round-trip, and a probe that threw was reported as "path is missing".
@visibleForTesting
SavePathChip savePathChipFor(
  AsyncValue<SavePathStatus> status,
  String Function(String path) formatLabel,
  NightshadeLocalizations l10n,
) {
  final value = status.valueOrNull;
  if (value == null) {
    // Not assessed yet (or the provider itself failed): say so.
    return SavePathChip(
      label: status.hasError
          ? l10n.text('statusSavePathUnreadable')
          : l10n.text('statusSavePathChecking'),
      tooltip: status.hasError
          ? l10n.text('statusSavePathUnreadableTooltip')
          : l10n.text('statusSavePathCheckingTooltip'),
      tone: SavePathTone.unknown,
    );
  }
  if (value.path.isEmpty) {
    return SavePathChip(
      label: l10n.text('statusNoSavePath'),
      tooltip: l10n.text('statusNoSavePathTooltip'),
      tone: SavePathTone.alarm,
    );
  }
  final label = formatLabel(value.path);
  switch (value.existence) {
    case SavePathExistence.present:
      return SavePathChip(
        label: label,
        tooltip: l10n.text(
          'statusSavePathOkTooltip',
          params: {'path': value.path},
        ),
        tone: SavePathTone.ok,
      );
    case SavePathExistence.missing:
      return SavePathChip(
        label: label,
        tooltip: l10n.text(
          'statusSavePathMissingTooltip',
          params: {'path': value.path},
        ),
        tone: SavePathTone.alarm,
      );
    case SavePathExistence.unknown:
      return SavePathChip(
        label: label,
        tooltip: l10n.text(
          'statusSavePathUnknownTooltip',
          params: {'path': value.path},
        ),
        tone: SavePathTone.unknown,
      );
  }
}

/// Checks the configured capture directory on the machine that performs the
/// capture. A remote controller cannot infer host-path validity from its own
/// filesystem.
Future<bool> configuredSavePathExists(
  NightshadeBackend backend,
  String savePath,
) async {
  if (backend is NetworkBackend) {
    final validation = await backend.validateRemoteDirectory(
      savePath,
      mustExist: true,
      mustBeWritable: false,
    );
    return validation['valid'] == true;
  }
  return Directory(savePath).exists();
}

class StatusBar extends ConsumerStatefulWidget {
  /// When true, uses a horizontally scrollable strip and hides desktop-only
  /// actions (web dashboard, share session) to fit phone widths.
  final bool compact;

  const StatusBar({super.key, this.compact = false});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  // Keep the per-second clock tick inside [_TimeDisplay] so the rest of the
  // status bar remains idle.

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
    // The desktop bar's density is chosen from its own width, not the window's,
    // so an embedded or split view gets the same treatment.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, double availableWidth) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    // Below the desktop breakpoint the full-width pills do not fit: the leading
    // group scrolled, which on a desktop mouse is close to undiscoverable, and
    // the viewport edge sliced a label mid-word ("Mount Dis") so the bar simply
    // read as broken. Shedding the static label words buys back ~50 px a pill,
    // which is enough for the whole strip to fit at 800 px.
    final dense =
        !widget.compact && availableWidth < BreakpointTokens.breakpointDesktop;
    final savePathChip = savePathChipFor(
      ref.watch(_savePathStatusProvider),
      _formatPathLabel,
      l10n,
    );

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
    final leading = <Widget>[
      const SizedBox(width: 12),
      _SequenceIndicator(colors: colors, l10n: l10n),
      const SizedBox(width: 12),
      _divider(colors),
      const SizedBox(width: 8),
      const EquipmentStatusIndicator(),
      const SizedBox(width: 8),
      _divider(colors),
      const SizedBox(width: 12),
      _StatusPillButton(
        icon: NightshadeIcons.camera,
        label: l10n.text('statusCamera'),
        value: cameraConnected
            ? _getDeviceDisplayName(
                cameraState.deviceName,
                cameraState.deviceId,
                l10n.text('statusConnected'),
              )
            : l10n.text('disconnected'),
        isConnected: cameraConnected,
        colors: colors,
        compact: widget.compact,
        dense: dense,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: LucideIcons.move3d,
        label: l10n.text('mount'),
        value: mountConnected
            ? _getDeviceDisplayName(
                mountState.deviceName,
                mountState.deviceId,
                l10n.text('statusConnected'),
              )
            : l10n.text('disconnected'),
        isConnected: mountConnected,
        colors: colors,
        compact: widget.compact,
        dense: dense,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: NightshadeIcons.crosshair,
        label: l10n.text('statusGuider'),
        // "Idle" here meant "no guider" — the same word the app uses for a
        // connected, ready guider that simply isn't guiding. At a glance the bar
        // said the guider was present and calm when there was no guider at all.
        // Match the Camera/Mount pills and name the actual state.
        value: guiderConnected
            ? (guiderState.isGuiding
                ? l10n.text('guiding')
                : l10n.text('statusReady'))
            : l10n.text('disconnected'),
        isConnected: guiderConnected,
        colors: colors,
        compact: widget.compact,
        dense: dense,
      ),
      const SizedBox(width: 8),
      _StatusPillButton(
        icon: NightshadeIcons.focuser,
        label: l10n.text('focus'),
        value: focuserConnected
            ? (focuserState.position?.toString() ?? l10n.text('statusReady'))
            : '---',
        isConnected: focuserConnected,
        colors: colors,
        compact: widget.compact,
        dense: dense,
      ),
      const SizedBox(width: 4),
      _TempCompIndicator(colors: colors, l10n: l10n),
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
        icon: NightshadeIcons.temperature,
        value: cameraConnected && cameraState.temperature != null
            ? '${cameraState.temperature!.toStringAsFixed(1)}\u00B0C'
            : '---',
        colors: colors,
      ),
      const SizedBox(width: 12),
      if (!widget.compact)
        _InfoChip(
          // The folder-X alarm is reserved for a path we KNOW is unusable.
          // "Not checked yet" / "could not verify" gets the neutral search
          // folder, so an unfinished probe never reads as a broken rig.
          icon: switch (savePathChip.tone) {
            SavePathTone.ok => NightshadeIcons.folderOpen,
            SavePathTone.alarm => LucideIcons.folderX,
            SavePathTone.unknown => LucideIcons.folderSearch,
          },
          value: savePathChip.label,
          tooltip: savePathChip.tooltip,
          colors: colors,
        ),
      if (!widget.compact) const SizedBox(width: 12),
      if (!widget.compact) ...[
        _divider(colors),
        const SizedBox(width: 8),
        _WebDashboardButton(colors: colors, l10n: l10n),
        const SizedBox(width: 4),
        _ShareSessionButton(colors: colors),
        const SizedBox(width: 8),
        _divider(colors),
        const SizedBox(width: 12),
      ],
      _TimeDisplay(colors: colors),
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
          // Desktop: the device pills take the slack and scroll when there is
          // none; the readouts on the right are never sacrificed. A bare
          // Row + Spacer silently CLIPPED the trailing group at narrow window
          // widths — at 1000x700 the clock and LST readouts were gone entirely
          // and at 800x600 the save-path chip was cut mid-word ("No s"), with
          // no ellipsis and no way to reach either.
          : Row(
              children: [
                // Expanded, not Flexible: a SingleChildScrollView shrink-wraps
                // under a loose constraint, which would let the readouts drift
                // left off the right edge. A tight fit makes the pill group take
                // all the slack — the job the old Spacer did — and scroll only
                // once the slack runs out.
                Expanded(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      _setPillsOverflow(
                        notification.metrics.maxScrollExtent > 0,
                      );
                      return false;
                    },
                    // Even after the labels are shed, a narrow bar with a long
                    // profile name can still hold more pills than fit. Scrolling
                    // alone is silent — the bar simply ended and looked complete,
                    // so a disconnected mount was indistinguishable from no mount
                    // at all. The fade says "there is more this way"; it appears
                    // only while the group actually overflows.
                    child: _pillsOverflow
                        ? ShaderMask(
                            shaderCallback: _fadeRightEdge,
                            blendMode: BlendMode.dstIn,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: leading),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: leading),
                          ),
                  ),
                ),
                ...trailing,
              ],
            ),
    );
  }

  /// True while the pill group has content past its right edge.
  bool _pillsOverflow = false;

  void _setPillsOverflow(bool value) {
    if (_pillsOverflow == value) return;
    // The notification arrives during layout; defer so this is not a setState
    // inside a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pillsOverflow == value) return;
      setState(() => _pillsOverflow = value);
    });
  }

  /// Alpha ramp that dissolves the last 24 px of the pill group.
  ///
  /// Only the alpha channel is consumed by [ShaderMask], so these colors are
  /// mask values rather than interface colors.
  static Shader _fadeRightEdge(Rect bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0.0, 0.92, 1.0],
      ).createShader(bounds);

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
