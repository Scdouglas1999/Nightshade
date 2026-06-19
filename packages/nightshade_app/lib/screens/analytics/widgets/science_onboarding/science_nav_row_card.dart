import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceNavRowCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const ScienceNavRowCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: NightshadeTokens.minTouchTarget,
        ),
        child: Row(
          children: [
            Icon(icon, size: NightshadeTokens.iconSm, color: iconColor),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Text(
                label,
                style: NightshadeTypography.bodySm.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: NightshadeTokens.iconXs,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
