import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Small overlay card on the canvas showing the target's name, catalog id,
/// coordinates, and optional magnitude / size.
class FramingTargetInfoOverlay extends StatelessWidget {
  final NightshadeColors colors;
  final FramingTarget target;

  const FramingTargetInfoOverlay({
    super.key,
    required this.colors,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            target.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (target.catalogId != null && target.catalogId != target.name)
            Text(
              target.catalogId!,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${target.raFormatted}  ${target.decFormatted}',
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (target.magnitude != null || target.sizeArcmin != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (target.magnitude != null)
                    'Mag ${target.magnitude!.toStringAsFixed(1)}',
                  if (target.sizeArcmin != null)
                    "${target.sizeArcmin!.toStringAsFixed(0)}'",
                ].join('  '),
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Warning card used in the equipment section when the active profile is
/// incomplete (no profile / no focal length / no camera specs). Includes an
/// optional call-to-action button.
class FramingEquipmentWarningCard extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FramingEquipmentWarningCard({
    super.key,
    required this.colors,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: colors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.warning,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.arrowRight,
                        size: 12, color: colors.warning),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label/value row used in the equipment summary and similar info blocks.
class FramingInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const FramingInfoRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Coordinate row used in the coordinates panel; supports tinted value text
/// for "good" (high altitude) or "bad" (low / below horizon) state.
class FramingCoordRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isGood;
  final bool isBad;

  const FramingCoordRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.isGood = false,
    this.isBad = false,
  });

  @override
  Widget build(BuildContext context) {
    Color valueColor = colors.textPrimary;
    if (isGood) valueColor = colors.success;
    if (isBad) valueColor = colors.error;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
