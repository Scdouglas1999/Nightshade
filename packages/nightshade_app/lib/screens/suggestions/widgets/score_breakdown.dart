import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Configuration for a single score component in the breakdown display.
class _ScoreComponentConfig {
  final String key;
  final String label;
  final IconData icon;
  final String tooltip;

  const _ScoreComponentConfig({
    required this.key,
    required this.label,
    required this.icon,
    required this.tooltip,
  });
}

/// An expandable widget that displays a detailed breakdown of target scoring
/// with horizontal bar charts for each score component.
///
/// Each score component (altitude, moon distance, transit proximity, darkness,
/// airmass) is displayed as a labeled horizontal bar with color coding based
/// on the score value:
/// - Score > 70: Green (success)
/// - Score 40-70: Yellow/amber (warning)
/// - Score < 40: Red (error)
class ScoreBreakdown extends StatefulWidget {
  /// The scores map with keys: "altitude", "moonDistance", "transitProximity",
  /// "darkness", "airmass". Each score should be 0-100.
  final Map<String, double> scores;

  /// Whether the section should be initially expanded.
  final bool initiallyExpanded;

  const ScoreBreakdown({
    super.key,
    required this.scores,
    this.initiallyExpanded = false,
  });

  @override
  State<ScoreBreakdown> createState() => _ScoreBreakdownState();
}

class _ScoreBreakdownState extends State<ScoreBreakdown>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotationAnimation;
  late bool _isExpanded;

  /// Configuration for all score components with their display properties.
  static const List<_ScoreComponentConfig> _coreScoreComponents = [
    _ScoreComponentConfig(
      key: 'altitude',
      label: 'Altitude',
      icon: Icons.terrain_outlined,
      tooltip: 'Higher altitude = better seeing and less atmosphere',
    ),
    _ScoreComponentConfig(
      key: 'moonDistance',
      label: 'Moon Distance',
      icon: Icons.nightlight_outlined,
      tooltip: 'Distance from the moon affects sky brightness',
    ),
    _ScoreComponentConfig(
      key: 'transitProximity',
      label: 'Transit',
      icon: Icons.vertical_align_top_outlined,
      tooltip: 'Whether meridian transit occurs during the night',
    ),
    _ScoreComponentConfig(
      key: 'darkness',
      label: 'Imaging Window',
      icon: Icons.dark_mode_outlined,
      tooltip: 'Hours above minimum altitude during the night',
    ),
    _ScoreComponentConfig(
      key: 'airmass',
      label: 'Airmass',
      icon: Icons.layers_outlined,
      tooltip: 'Lower airmass means less atmospheric distortion',
    ),
  ];

  static const _framingFitComponent = _ScoreComponentConfig(
    key: 'framingFit',
    label: 'Framing Fit',
    icon: Icons.crop_free_outlined,
    tooltip: 'How well the target size matches your field of view',
  );

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _expandController = AnimationController(
      duration: NightshadeTokens.durationSmooth,
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: NightshadeTokens.curveStandard,
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: _expandController,
        curve: NightshadeTokens.curveStandard,
      ),
    );

    if (_isExpanded) {
      _expandController.value = 1.0;
    }
  }

  @override
  void dispose() {
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

  /// Returns the appropriate color based on the score value.
  Color _getScoreColor(NightshadeColors colors, double score) {
    if (score > 70) {
      return colors.success;
    } else if (score >= 40) {
      return colors.warning;
    } else {
      return colors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with toggle
        InkWell(
          onTap: _toggleExpanded,
          borderRadius: NightshadeTokens.borderRadiusSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: NightshadeTokens.spaceXs,
              horizontal: NightshadeTokens.spaceSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: NightshadeTokens.iconSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: NightshadeTokens.spaceXs),
                Text(
                  'Score Details',
                  style: NightshadeTypography.labelSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceXs),
                RotationTransition(
                  turns: _rotationAnimation,
                  child: Icon(
                    Icons.expand_more,
                    size: NightshadeTokens.iconSm,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable content
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1.0,
          child: FadeTransition(
            opacity: _expandAnimation,
            child: Padding(
              padding: const EdgeInsets.only(
                top: NightshadeTokens.spaceSm,
                left: NightshadeTokens.spaceSm,
                right: NightshadeTokens.spaceSm,
              ),
              child: _buildScoreList(colors),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreList(NightshadeColors colors) {
    final components = [
      ..._coreScoreComponents,
      if (widget.scores.containsKey('framingFit')) _framingFitComponent,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: components.map((config) {
        final score = widget.scores[config.key] ?? 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
          child: _ScoreRow(
            label: config.label,
            icon: config.icon,
            tooltip: config.tooltip,
            score: score,
            color: _getScoreColor(colors, score),
            colors: colors,
          ),
        );
      }).toList(),
    );
  }
}

/// A single row in the score breakdown showing icon, label, bar, and value.
class _ScoreRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String tooltip;
  final double score;
  final Color color;
  final NightshadeColors colors;

  const _ScoreRow({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.score,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeTooltip(
      message: tooltip,
      position: NightshadeTooltipPosition.top,
      child: Row(
        children: [
          // Icon
          Icon(
            icon,
            size: NightshadeTokens.iconSm,
            color: colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),

          // Label with fixed width for alignment
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: NightshadeTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),

          // Bar takes remaining space
          Expanded(
            child: _ScoreBar(
              score: score,
              color: color,
              backgroundColor: colors.surfaceAlt,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),

          // Numeric value
          SizedBox(
            width: 32,
            child: Text(
              score.round().toString(),
              style: NightshadeTypography.monoSm.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// An animated horizontal bar that fills proportionally to the score.
class _ScoreBar extends StatelessWidget {
  final double score;
  final Color color;
  final Color backgroundColor;

  const _ScoreBar({
    required this.score,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedScore = (score / 100.0).clamp(0.0, 1.0);

    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: NightshadeTokens.borderRadiusFull,
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: NightshadeTokens.durationNormal,
                curve: NightshadeTokens.curvePrecise,
                width: constraints.maxWidth * normalizedScore,
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _lightenColor(color, 0.1),
                      color,
                    ],
                  ),
                  borderRadius: NightshadeTokens.borderRadiusFull,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Creates a slightly lighter shade of the given color.
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }
}
