import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:intl/intl.dart';
import '../../../utils/coordinate_format_utils.dart';

class TopOverlay extends ConsumerWidget {
  final NightshadeColors colors;

  const TopOverlay({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(observerLocationProvider);
    final time = ref.watch(observationTimeProvider);
    final lst = ref.watch(localSiderealTimeProvider);
    final renderConfig = ref.watch(skyRenderConfigProvider);
    final settingsAsync = ref.watch(appSettingsProvider);

    // Get location name from settings if available
    String locationLabel;
    final settings = settingsAsync.valueOrNull;
    if (settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0)) {
      locationLabel = CoordinateFormatUtils.formatLatLon(
          settings.latitude, settings.longitude);
    } else {
      locationLabel = location.locationName ??
          CoordinateFormatUtils.formatLatLon(
              location.latitude, location.longitude);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          OverlayChip(
            icon: LucideIcons.mapPin,
            label: locationLabel,
            colors: colors,
          ),
          const SizedBox(width: 12),
          OverlayChip(
            icon: LucideIcons.clock,
            label: DateFormat('HH:mm:ss').format(time.time),
            colors: colors,
          ),
          const SizedBox(width: 12),
          OverlayChip(
            icon: LucideIcons.star,
            label: 'LST ${_formatHours(lst)}',
            colors: colors,
          ),
          if (!time.isRealTime) ...[
            const SizedBox(width: 12),
            TimeControlButton(
              icon: LucideIcons.play,
              onTap: () =>
                  ref.read(observationTimeProvider.notifier).setRealTime(true),
              colors: colors,
            ),
          ],
          const Spacer(),
          OverlayToggle(
            icon: LucideIcons.grid,
            isActive: renderConfig.showCoordinateGrid,
            onTap: ref.read(skyRenderConfigProvider.notifier).toggleGrid,
          ),
          const SizedBox(width: 4),
          OverlayToggle(
            icon: LucideIcons.activity,
            isActive: renderConfig.showConstellationLines,
            onTap: ref
                .read(skyRenderConfigProvider.notifier)
                .toggleConstellationLines,
          ),
          const SizedBox(width: 4),
          OverlayToggle(
            icon: LucideIcons.tag,
            isActive: renderConfig.showConstellationLabels,
            onTap: ref
                .read(skyRenderConfigProvider.notifier)
                .toggleConstellationLabels,
          ),
          const SizedBox(width: 4),
          OverlayToggle(
            icon: LucideIcons.circle,
            isActive: renderConfig.showHorizon,
            onTap: ref.read(skyRenderConfigProvider.notifier).toggleHorizon,
          ),
        ],
      ),
    );
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

class OverlayChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const OverlayChip({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class OverlayToggle extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const OverlayToggle({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<OverlayToggle> createState() => _OverlayToggleState();
}

class _OverlayToggleState extends State<OverlayToggle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.isActive
                ? Colors.white.withValues(alpha: 0.2)
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: widget.isActive ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class TimeControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const TimeControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: colors.primary),
      ),
    );
  }
}
