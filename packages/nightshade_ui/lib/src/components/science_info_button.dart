import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../dialogs/nightshade_dialog.dart';
import 'nightshade_button.dart';

void showScienceInfoDialog(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (context) {
      final colors = NightshadeColors.of(context);
      return NightshadeDialog(
        title: title,
        icon: LucideIcons.info,
        width: 520,
        height: 420,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Got it',
            variant: ButtonVariant.ghost,
          ),
        ],
        child: Text(
          body.trim(),
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textSecondary,
            height: 1.6,
          ),
        ),
      );
    },
  );
}

class ScienceInfoButton extends StatelessWidget {
  final String title;
  final String body;

  const ScienceInfoButton({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // An icon-only help control publishes no text of its own, so without an
    // explicit role, name and enabled state it reached assistive tech as an
    // anonymous disabled panel — the explanation of the numbers on screen was
    // available to a mouse and to nothing else.
    return Semantics(
      button: true,
      enabled: true,
      label: 'What is this? $title',
      child: Tooltip(
        message: 'What is this?',
        child: InkWell(
          onTap: () => showScienceInfoDialog(context, title, body),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            alignment: Alignment.center,
            child: Icon(
              LucideIcons.info,
              size: NightshadeTokens.iconXs,
              color: colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
