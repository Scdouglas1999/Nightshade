import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact "remote-vs-local + latency" chip for the dashboard command bar.
///
/// Reads the graded [connectionQualityProvider] so it shares one source of
/// truth with the rest of the app instead of re-subscribing to the backend's
/// raw latency/state streams. In local FFI mode it renders a quiet "Local"
/// chip (no latency — nothing remote to measure); in a network session it shows
/// the live link state, the host, and the WebSocket round-trip, color-graded by
/// [ConnectionQuality.latencyGrade].
class ConnectionQualityChip extends ConsumerWidget {
  final NightshadeColors colors;

  /// Icon-and-latency only — drops the text label and host for tight layouts
  /// (the compact command bar).
  final bool compact;

  const ConnectionQualityChip({
    super.key,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The provider seeds a value, but fail closed if Riverpod itself cannot
    // produce one. A quality failure must never be presented as local control.
    final quality = ref.watch(connectionQualityProvider).valueOrNull ??
        ConnectionQuality.unavailable;

    final color = _color(quality);
    final icon = _icon(quality);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 14, color: color),
          if (!compact) ...[
            const SizedBox(width: 6),
            Text(
              _label(quality),
              style: NightshadeTypography.labelStrongSm.copyWith(color: color),
            ),
            if (quality.mode == ConnectionMode.remote &&
                quality.remoteHost != null) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  quality.remoteHost!,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: NightshadeTypography.captionSm.copyWith(
                    color: color.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ],
          // Latency only reads true while the link is actually up; a stale
          // round-trip beside an "Offline" chip would mislead.
          if (quality.liveness == ConnectionLiveness.connected &&
              quality.latencyMs != null) ...[
            SizedBox(width: compact ? 4 : 6),
            Text(
              '${quality.latencyMs} ms',
              style: NightshadeTypography.withTabular(
                NightshadeTypography.monoXs.copyWith(
                  color: _latencyColor(quality),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _label(ConnectionQuality q) {
    if (q.mode == ConnectionMode.local) return 'Local';
    switch (q.liveness) {
      case ConnectionLiveness.connected:
        return q.isRemoteHost ? 'Remote' : 'LAN';
      case ConnectionLiveness.connecting:
        return 'Connecting';
      case ConnectionLiveness.reconnecting:
        return 'Reconnecting';
      case ConnectionLiveness.offline:
        return 'Offline';
      case ConnectionLiveness.error:
        return 'Error';
      case ConnectionLiveness.local:
        return 'Local';
    }
  }

  IconData _icon(ConnectionQuality q) {
    if (q.mode == ConnectionMode.local) return LucideIcons.monitor;
    switch (q.liveness) {
      case ConnectionLiveness.connected:
        return LucideIcons.wifi;
      case ConnectionLiveness.connecting:
      case ConnectionLiveness.reconnecting:
        return LucideIcons.refreshCw;
      case ConnectionLiveness.offline:
        return LucideIcons.serverOff;
      case ConnectionLiveness.error:
        return LucideIcons.alertTriangle;
      case ConnectionLiveness.local:
        return LucideIcons.monitor;
    }
  }

  Color _color(ConnectionQuality q) {
    if (q.mode == ConnectionMode.local) return colors.textSecondary;
    switch (q.liveness) {
      case ConnectionLiveness.connected:
        return colors.success;
      case ConnectionLiveness.connecting:
      case ConnectionLiveness.reconnecting:
        return colors.warning;
      case ConnectionLiveness.offline:
      case ConnectionLiveness.error:
        return colors.error;
      case ConnectionLiveness.local:
        return colors.textSecondary;
    }
  }

  /// Color the latency readout by its grade, independent of the link color, so
  /// a connected-but-laggy session reads green-link / amber-latency.
  Color _latencyColor(ConnectionQuality q) {
    switch (q.latencyGrade) {
      case ConnectionLatencyGrade.good:
        return colors.success;
      case ConnectionLatencyGrade.fair:
        return colors.warning;
      case ConnectionLatencyGrade.poor:
        return colors.error;
      case null:
        return colors.textMuted;
    }
  }
}
