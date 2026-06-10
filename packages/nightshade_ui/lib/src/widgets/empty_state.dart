import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Centered "no data" / "nothing selected" placeholder used across screens
/// (diagnostics, science analytics) when a tab has nothing to render but
/// must still occupy its slot in an [IndexedStack] or scroll view.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final double _iconSize;
  final TextStyle _titleStyle;
  final double _iconTitleGap;
  final double _bodyGap;
  final double _actionGap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.all(24),
  }) : _iconSize = NightshadeTokens.iconXl,
       _titleStyle = NightshadeTypography.h5,
       _iconTitleGap = NightshadeTokens.spaceLg,
       _bodyGap = NightshadeTokens.spaceSm,
       _actionGap = NightshadeTokens.spaceLg;

  /// Tighter variant for side panels and embedded slots (32px icon).
  const EmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  }) : _iconSize = NightshadeTokens.iconXl,
       _titleStyle = NightshadeTypography.h6,
       _iconTitleGap = NightshadeTokens.spaceMd,
       _bodyGap = NightshadeTokens.spaceXs,
       _actionGap = NightshadeTokens.spaceMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: _iconSize, color: colors.textMuted),
              SizedBox(height: _iconTitleGap),
              Text(
                title,
                style: _titleStyle.copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              if (body != null) ...[
                SizedBox(height: _bodyGap),
                Text(
                  body!,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[SizedBox(height: _actionGap), action!],
            ],
          ),
        ),
      ),
    );
  }
}
