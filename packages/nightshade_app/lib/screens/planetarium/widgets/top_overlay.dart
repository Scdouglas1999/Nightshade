import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:intl/intl.dart';
import '../../../utils/coordinate_format_utils.dart';
import '../../sequencer/widgets/run_dashboard/recovery_banner.dart';

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wave 4 Recovery Mode — surface the live recovery banner at the
        // top of the planetarium screen so a user watching the sky chart
        // still sees recovery state. Empty SizedBox when not recovering.
        const RunDashboardRecoveryBanner(),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 900;
            final isVeryCompact = constraints.maxWidth < 720;
            final horizontalPadding =
                isVeryCompact ? 12.0 : (isCompact ? 16.0 : 20.0);
            final chipSpacing = isVeryCompact ? 6.0 : (isCompact ? 8.0 : 12.0);
            final toggleSpacing = isVeryCompact ? 2.0 : 4.0;
            final timeFormat =
                isCompact ? DateFormat('HH:mm') : DateFormat('HH:mm:ss');

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: isCompact ? 8 : 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (!isVeryCompact) ...[
                            OverlayChip(
                              icon: NightshadeIcons.location,
                              label: locationLabel,
                              colors: colors,
                              compact: isCompact,
                            ),
                            SizedBox(width: chipSpacing),
                          ],
                          OverlayChip(
                            icon: NightshadeIcons.clock,
                            label: timeFormat.format(time.time),
                            colors: colors,
                            compact: isCompact,
                          ),
                          SizedBox(width: chipSpacing),
                          OverlayChip(
                            icon: NightshadeIcons.star,
                            label: 'LST ${_formatHours(lst)}',
                            colors: colors,
                            compact: isCompact,
                          ),
                          SizedBox(width: chipSpacing),
                          SequencerStatusLed(showLabel: !isCompact),
                          if (!time.isRealTime) ...[
                            SizedBox(width: chipSpacing),
                            TimeControlButton(
                              icon: NightshadeIcons.play,
                              onTap: () => ref
                                  .read(observationTimeProvider.notifier)
                                  .setRealTime(true),
                              colors: colors,
                              compact: isCompact,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: chipSpacing),
                  OverlayToggle(
                    icon: NightshadeIcons.grid,
                    tooltip: 'Coordinate grid',
                    isActive: renderConfig.showCoordinateGrid,
                    onTap: ref.read(skyRenderConfigProvider.notifier).toggleGrid,
                  ),
                  SizedBox(width: toggleSpacing),
                  OverlayToggle(
                    icon: NightshadeIcons.activity,
                    tooltip: 'Constellation lines',
                    isActive: renderConfig.showConstellationLines,
                    onTap: ref
                        .read(skyRenderConfigProvider.notifier)
                        .toggleConstellationLines,
                  ),
                  SizedBox(width: toggleSpacing),
                  if (!isVeryCompact) ...[
                    OverlayToggle(
                      icon: NightshadeIcons.tag,
                      tooltip: 'Constellation labels',
                      isActive: renderConfig.showConstellationLabels,
                      onTap: ref
                          .read(skyRenderConfigProvider.notifier)
                          .toggleConstellationLabels,
                    ),
                    SizedBox(width: toggleSpacing),
                  ],
                  OverlayToggle(
                    icon: NightshadeIcons.circle,
                    tooltip: 'Horizon',
                    isActive: renderConfig.showHorizon,
                    onTap:
                        ref.read(skyRenderConfigProvider.notifier).toggleHorizon,
                  ),
                ],
              ),
            );
          },
        ),
      ],
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
  final bool compact;

  const OverlayChip({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 12, color: colors.textSecondary),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact
                  ? NightshadeTypography.fontSize10
                  : NightshadeTypography.fontSize11,
              color: colors.textSecondary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class OverlayToggle extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const OverlayToggle({
    super.key,
    required this.icon,
    required this.tooltip,
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
    final colors = NightshadeColors.of(context);
    final touchSize = AdaptiveSizing.of(context).minTouchTarget;
    final iconSize = touchSize <= 36 ? 14.0 : 16.0;

    return NightshadeTooltip(
      message: widget.tooltip,
      position: NightshadeTooltipPosition.bottom,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: touchSize,
            height: touchSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? colors.primary.withValues(alpha: 0.2)
                  : _isHovered
                      ? colors.surfaceOverlay.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: widget.isActive
                  ? Border.all(color: colors.primary.withValues(alpha: 0.4))
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: iconSize,
              color: widget.isActive ? colors.primary : colors.textSecondary,
            ),
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
  final bool compact;

  const TimeControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(compact ? 4 : 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Icon(icon, size: compact ? 12 : 14, color: colors.primary),
      ),
    );
  }
}
