import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/operation_status_bar.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

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
        // Extract vendor part (after ASCOM. prefix)
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
    final knownVendors = {
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

    // Default: capitalize first letter
    if (vendor.isEmpty) return vendor;
    return vendor[0].toUpperCase() + vendor.substring(1);
  }

  /// Format ASCOM vendor string by adding spaces before capitals/numbers
  String _formatAscomVendor(String vendor) {
    // Insert spaces before capital letters and numbers
    final spaced = vendor.replaceAllMapped(
      RegExp(r'([a-z])([A-Z0-9])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    return spaced;
  }

  /// Clean up an unrecognized ID for display
  String _cleanupId(String id) {
    // Remove common prefixes
    var cleaned = id;
    for (final prefix in ['native:', 'ascom:', 'alpaca:', 'ASCOM.']) {
      if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
        cleaned = cleaned.substring(prefix.length);
      }
    }

    // Replace underscores and dots with spaces
    cleaned = cleaned.replaceAll('_', ' ').replaceAll('.', ' ');

    // Remove trailing numbers that look like indices
    cleaned = cleaned.replaceAll(RegExp(r'\s*:\s*\d+$'), '');

    // Capitalize words
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    
    // Watch equipment state
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    
    final cameraConnected = cameraState.connectionState == DeviceConnectionState.connected;
    final mountConnected = mountState.connectionState == DeviceConnectionState.connected;
    final guiderConnected = guiderState.connectionState == DeviceConnectionState.connected;
    final focuserConnected = focuserState.connectionState == DeviceConnectionState.connected;

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

          const SizedBox(width: 16),

          // Equipment status pills (DYNAMIC)
          _StatusPillButton(
            icon: LucideIcons.camera,
            label: 'Camera',
            value: cameraConnected
                ? _getDeviceDisplayName(cameraState.deviceName, cameraState.deviceId, 'Connected')
                : 'Disconnected',
            isConnected: cameraConnected,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _StatusPillButton(
            icon: LucideIcons.move3d,
            label: 'Mount',
            value: mountConnected
                ? _getDeviceDisplayName(mountState.deviceName, mountState.deviceId, 'Connected')
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

          // Operation progress indicator (when operations are active)
          const OperationStatusBar(),

          const Spacer(),

          // Temperature / weather
          _InfoChip(
            icon: LucideIcons.thermometer,
            value: cameraConnected && cameraState.temperature != null 
                ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
                : '---',
            colors: colors,
          ),
          const SizedBox(width: 12),

          // Disk space
          _InfoChip(
            icon: LucideIcons.hardDrive,
            value: '256 GB',
            colors: colors,
          ),
          const SizedBox(width: 12),

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
}

class _SequenceIndicator extends StatefulWidget {
  final NightshadeColors colors;

  const _SequenceIndicator({required this.colors});

  @override
  State<_SequenceIndicator> createState() => _SequenceIndicatorState();
}

class _SequenceIndicatorState extends State<_SequenceIndicator>
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
    // Idle state - no animation
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.colors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Idle',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _isHovered
              ? widget.colors.surfaceAlt
              : Colors.transparent,
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
            const SizedBox(width: 4),
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
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final NightshadeColors colors;

  const _InfoChip({
    required this.icon,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
