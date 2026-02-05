import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'altitude_plot.dart';

/// A card widget displaying a single target suggestion with scoring,
/// visibility info, altitude plot, warnings, and action buttons.
class SuggestionCard extends ConsumerWidget {
  /// The target suggestion to display.
  final TargetSuggestion suggestion;

  /// Callback when "View in Framing" is pressed.
  final VoidCallback? onViewInFraming;

  /// Callback when "Add to Sequence" is pressed.
  final VoidCallback? onAddToSequence;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    this.onViewInFraming,
    this.onAddToSequence,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use compact layout for narrow cards (mobile or small grid cells)
        final isCompact = constraints.maxWidth < 320;

        return NightshadeCard(
          enableHover: true,
          borderRadius: NightshadeTokens.radiusMd,
          child: Padding(
            padding: EdgeInsets.all(isCompact
                ? NightshadeTokens.spaceMd
                : NightshadeTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: target name, catalog ID, object type icon, score badge
                _buildHeader(colors, isCompact),

                SizedBox(height: isCompact ? NightshadeTokens.spaceXs : NightshadeTokens.spaceSm),

                // Object details row (type, magnitude, size, constellation)
                _buildObjectDetails(colors),

                SizedBox(height: isCompact ? NightshadeTokens.spaceXs : NightshadeTokens.spaceSm),

                // Altitude plot (if we have location) - expands to fill available space
                if (settings != null &&
                    !(settings.latitude == 0 && settings.longitude == 0))
                  Expanded(
                    child: _buildAltitudePlot(colors, settings.latitude, settings.longitude),
                  )
                else
                  const Spacer(),

                SizedBox(height: isCompact ? NightshadeTokens.spaceXs : NightshadeTokens.spaceSm),

                // Quick stats row: altitude, moon distance, transit time, airmass
                _buildQuickStats(colors, isCompact),

                SizedBox(height: isCompact ? NightshadeTokens.spaceXs : NightshadeTokens.spaceSm),

                // Data progress bar
                _buildDataProgress(colors),

                // Warning chips (if warnings exist)
                if (suggestion.warnings.isNotEmpty) ...[
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  _buildWarnings(colors),
                ],

                SizedBox(height: isCompact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd),

                // Action buttons row
                _buildActions(colors, isCompact),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the header row with target name, catalog ID, type icon, and score badge.
  Widget _buildHeader(NightshadeColors colors, bool isCompact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Object type icon
        Container(
          width: isCompact ? 28 : 36,
          height: isCompact ? 28 : 36,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
          ),
          child: Icon(
            _getObjectTypeIcon(),
            size: isCompact ? 14 : 18,
            color: colors.primary,
          ),
        ),
        SizedBox(width: isCompact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd),
        // Target name and catalog ID
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.targetName,
                style: TextStyle(
                  fontSize: isCompact ? 13 : 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (suggestion.catalogId != null &&
                  suggestion.catalogId!.isNotEmpty &&
                  suggestion.catalogId != suggestion.targetName) ...[
                const SizedBox(height: 2),
                Text(
                  suggestion.catalogId!,
                  style: TextStyle(
                    fontSize: isCompact ? 10 : 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        // Score badge
        _buildScoreBadge(colors, isCompact),
      ],
    );
  }

  /// Builds object details row showing type, magnitude, size, and constellation.
  Widget _buildObjectDetails(NightshadeColors colors) {
    final details = <Widget>[];

    // Object type
    if (suggestion.objectType != null && suggestion.objectType!.isNotEmpty) {
      details.add(_buildDetailChip(colors, suggestion.objectType!));
    }

    // Magnitude
    if (suggestion.magnitude != null) {
      details.add(_buildDetailChip(
        colors,
        'Mag ${suggestion.magnitude!.toStringAsFixed(1)}',
        icon: LucideIcons.sun,
      ));
    }

    // Size
    if (suggestion.sizeArcmin != null && suggestion.sizeArcmin! > 0) {
      details.add(_buildDetailChip(
        colors,
        _formatSize(suggestion.sizeArcmin!),
        icon: LucideIcons.maximize2,
      ));
    }

    // Constellation
    if (suggestion.constellation != null && suggestion.constellation!.isNotEmpty) {
      details.add(_buildDetailChip(
        colors,
        suggestion.constellation!,
        icon: LucideIcons.star,
      ));
    }

    if (details.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: NightshadeTokens.spaceXs,
      runSpacing: NightshadeTokens.spaceXs,
      children: details,
    );
  }

  Widget _buildDetailChip(NightshadeColors colors, String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: colors.textMuted),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(double arcmin) {
    if (arcmin >= 60) {
      return '${(arcmin / 60).toStringAsFixed(1)}°';
    }
    return "${arcmin.toStringAsFixed(1)}'";
  }

  /// Builds the altitude plot showing visibility over the night.
  Widget _buildAltitudePlot(NightshadeColors colors, double latitude, double longitude) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      ),
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use the available height, with a minimum
          final plotHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight - NightshadeTokens.spaceSm * 2
              : 60.0;
          return AltitudePlot(
            raHours: suggestion.raHours,
            decDegrees: suggestion.decDegrees,
            latitude: latitude,
            longitude: longitude,
            visibility: suggestion.visibility,
            height: plotHeight.clamp(40.0, 200.0),
          );
        },
      ),
    );
  }

  /// Builds the circular score badge with color-coded background.
  Widget _buildScoreBadge(NightshadeColors colors, bool isCompact) {
    final score = suggestion.totalScore.round();
    final scoreColor = _getScoreColor(colors, score);
    final size = isCompact ? 38.0 : 44.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scoreColor.withValues(alpha: 0.15),
        border: Border.all(
          color: scoreColor.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            fontSize: isCompact ? 12 : 14,
            fontWeight: FontWeight.bold,
            color: scoreColor,
          ),
        ),
      ),
    );
  }

  /// Returns the appropriate color for the score value.
  Color _getScoreColor(NightshadeColors colors, int score) {
    if (score >= 70) {
      return colors.success;
    } else if (score >= 40) {
      return colors.warning;
    } else {
      return colors.error;
    }
  }

  /// Builds the quick stats row showing altitude, moon distance, transit, and airmass.
  Widget _buildQuickStats(NightshadeColors colors, bool isCompact) {
    final visibility = suggestion.visibility;

    return Wrap(
      spacing: isCompact ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg,
      runSpacing: NightshadeTokens.spaceXs,
      children: [
        // Current altitude
        _buildStatItem(
          colors,
          LucideIcons.mountain,
          '${visibility.currentAltitude.round()}°',
          'Alt',
          isCompact,
        ),
        // Moon distance
        _buildStatItem(
          colors,
          LucideIcons.moon,
          '${visibility.moonDistance.round()}°',
          'Moon',
          isCompact,
        ),
        // Transit time
        _buildStatItem(
          colors,
          LucideIcons.clock,
          _formatTransitTime(visibility),
          'Transit',
          isCompact,
        ),
        // Airmass
        _buildStatItem(
          colors,
          LucideIcons.wind,
          visibility.airmass < 10 ? visibility.airmass.toStringAsFixed(2) : '>10',
          'Airmass',
          isCompact,
        ),
      ],
    );
  }

  /// Builds a single stat item with icon and value.
  Widget _buildStatItem(
    NightshadeColors colors,
    IconData icon,
    String value,
    String label,
    bool isCompact,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: isCompact ? 10 : 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 8 : 9,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Formats the transit time as HH:MM or "Now" if near transit.
  String _formatTransitTime(TargetVisibilityInfo visibility) {
    if (visibility.transitTime == null) {
      if (visibility.isCircumpolar) {
        return 'Circ.';
      }
      if (visibility.neverRises) {
        return 'N/A';
      }
      return '--:--';
    }

    final now = DateTime.now();
    final transitTime = visibility.transitTime!;
    final difference = transitTime.difference(now);

    // Consider "near transit" if within 15 minutes
    if (difference.inMinutes.abs() <= 15) {
      return 'Now';
    }

    return _formatTime(transitTime);
  }

  /// Formats a DateTime as HH:MM.
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Builds the data progress bar with label.
  Widget _buildDataProgress(NightshadeColors colors) {
    final progress = suggestion.dataProgress;
    final progressPercent = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Data collected',
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
            Text(
              '$progressPercent%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: colors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(colors.primary),
            minHeight: 3,
          ),
        ),
      ],
    );
  }

  /// Builds warning chips for each warning.
  Widget _buildWarnings(NightshadeColors colors) {
    // Only show first 2 warnings to save space
    final warningsToShow = suggestion.warnings.take(2).toList();

    return Wrap(
      spacing: NightshadeTokens.spaceXs,
      runSpacing: NightshadeTokens.spaceXs,
      children: warningsToShow.map((warning) {
        return _buildWarningChip(colors, warning);
      }).toList(),
    );
  }

  /// Builds a single warning chip with appropriate color based on severity.
  Widget _buildWarningChip(NightshadeColors colors, TargetWarning warning) {
    final chipColor = _getWarningColor(colors, warning.severity);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getWarningIcon(warning.type),
            size: 10,
            color: chipColor,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              warning.message,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: chipColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the appropriate color for the warning severity.
  Color _getWarningColor(NightshadeColors colors, WarningSeverity severity) {
    switch (severity) {
      case WarningSeverity.info:
        return colors.info;
      case WarningSeverity.caution:
        return colors.warning;
      case WarningSeverity.warning:
        return const Color(0xFFFF8C00); // Dark orange
      case WarningSeverity.critical:
        return colors.error;
    }
  }

  /// Returns the appropriate icon for the warning type.
  IconData _getWarningIcon(WarningType type) {
    switch (type) {
      case WarningType.lowAltitude:
        return LucideIcons.arrowDown;
      case WarningType.highAirmass:
        return LucideIcons.wind;
      case WarningType.moonProximity:
        return LucideIcons.moon;
      case WarningType.settingSoon:
        return LucideIcons.sunset;
      case WarningType.notYetRisen:
        return LucideIcons.sunrise;
      case WarningType.belowHorizon:
        return LucideIcons.arrowDownCircle;
      case WarningType.twilight:
        return LucideIcons.sun;
    }
  }

  /// Builds the action buttons row.
  Widget _buildActions(NightshadeColors colors, bool isCompact) {
    if (isCompact) {
      // Stack buttons vertically on very narrow cards
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeButton(
            label: 'Framing',
            icon: LucideIcons.frame,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onViewInFraming,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          NightshadeButton(
            label: 'Add to Sequence',
            icon: LucideIcons.listPlus,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: onAddToSequence,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: 'Framing',
            icon: LucideIcons.frame,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onViewInFraming,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: NightshadeButton(
            label: 'Add to Sequence',
            icon: LucideIcons.listPlus,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: onAddToSequence,
          ),
        ),
      ],
    );
  }

  /// Determines the object type icon based on the object type or target name.
  IconData _getObjectTypeIcon() {
    final type = (suggestion.objectType ?? '').toLowerCase();
    final name = suggestion.targetName.toLowerCase();

    // Check object type first
    if (type.contains('galaxy')) return LucideIcons.circle;
    if (type.contains('planetary nebula')) return LucideIcons.circuitBoard;
    if (type.contains('nebula') || type.contains('emission') || type.contains('hii')) {
      return LucideIcons.cloud;
    }
    if (type.contains('globular')) return LucideIcons.target;
    if (type.contains('cluster') || type.contains('open')) return LucideIcons.sparkles;
    if (type.contains('star') || type.contains('double')) return LucideIcons.star;
    if (type.contains('supernova')) return LucideIcons.zap;

    // Fallback to name heuristics
    if (name.contains('galaxy')) return LucideIcons.circle;
    if (name.contains('nebula')) return LucideIcons.cloud;
    if (name.contains('cluster')) return LucideIcons.sparkles;

    // Default icon for DSOs
    return LucideIcons.scan;
  }
}
