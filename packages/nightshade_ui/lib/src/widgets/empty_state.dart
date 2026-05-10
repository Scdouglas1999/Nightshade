import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';

/// Centered "no data" / "nothing selected" placeholder used across screens
/// (diagnostics, science analytics) when a tab has nothing to render but
/// must still occupy its slot in an [IndexedStack] or scroll view.
///
/// Keeping a single shared widget prevents the science analytics tab from
/// stacking nine separate per-card "no data" placeholders when no session
/// and no standalone data are available.
class EmptyState extends StatelessWidget {
  /// Icon shown above the title.
  final IconData icon;

  /// Primary line, sized to read like a heading.
  final String title;

  /// Optional secondary line with explanatory copy. Wraps and centers.
  final String? body;

  /// Optional action rendered below the body (e.g. a primary button to
  /// jump into the relevant flow).
  final Widget? action;

  /// Padding around the centered column. Defaults to a generous 24px so
  /// the widget reads as a full-tab placeholder rather than an inline note.
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                style: TextStyle(fontSize: 12, color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
