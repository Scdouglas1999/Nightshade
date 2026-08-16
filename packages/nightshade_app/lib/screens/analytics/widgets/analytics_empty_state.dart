import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The one empty state every Analytics tab uses.
///
/// Left to themselves the five tabs drift into four different structures —
/// centred vs left-aligned, icon vs star glyph vs nothing at all, sentences
/// with full stops and sentences without — and none of them offers the reader
/// anything to do. A tab with nothing to show is the most common thing a new
/// user sees, so it is the worst place for the app to look like five different
/// products.
///
/// The contract, enforced below: an icon, a short title with no terminal
/// punctuation, exactly one sentence ending in a full stop, and one action.
class AnalyticsEmptyState extends StatelessWidget {
  final IconData icon;

  /// Short noun phrase naming what is missing. A trailing full stop is
  /// stripped, so a translation that carries one still reads as a label.
  final String title;

  /// One sentence saying how the tab gets filled. A missing terminal stop is
  /// supplied here rather than in each caller — one punctuation rule, in one
  /// place, is the whole point of this widget.
  final String body;

  final String actionLabel;

  /// What the action does. Defaults to sending the reader to Imaging, which is
  /// where every one of these tabs gets its data from.
  final VoidCallback? onAction;

  const AnalyticsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel = 'Go to Imaging',
    this.onAction,
  });

  /// The title as a label: never punctuated like a sentence.
  String get _label =>
      title.endsWith('.') ? title.substring(0, title.length - 1) : title;

  /// The body as a sentence: always punctuated like one.
  String get _sentence =>
      RegExp(r'[.!?]$').hasMatch(body.trimRight()) ? body : '$body.';

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: colors.textMuted),
            const SizedBox(height: NightshadeTokens.spaceMd),
            Text(
              _label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize14,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              _sentence,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            TextButton(
              onPressed:
                  onAction ?? () => GoRouter.maybeOf(context)?.go('/imaging'),
              child: Text(
                actionLabel,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
