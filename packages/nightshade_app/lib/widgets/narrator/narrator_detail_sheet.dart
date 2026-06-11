import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'narrator_card.dart';
import 'narrator_explainers.dart';

/// Opens the Night Narrator detail sheet for [event] as a modal bottom sheet.
///
/// Shows the full headline and body, an enlarged evidence visualization, a
/// "why this matters" explainer (from [narratorExplainers]), and an optional
/// action button (from [narratorActions]) that deep-links to Diagnostics,
/// science Analytics, or grader settings. When no explainer/action exists for
/// the event type the respective block is simply omitted.
Future<void> showNarratorDetailSheet(
  BuildContext context,
  NarratorEvent event,
) {
  final colors = NightshadeColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NightshadeTokens.radiusLg),
      ),
    ),
    builder: (sheetContext) => _NarratorDetailSheet(event: event),
  );
}

class _NarratorDetailSheet extends StatelessWidget {
  final NarratorEvent event;

  const _NarratorDetailSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final accent = NarratorVisuals.accentFor(event.severity, colors);
    final icon = NarratorVisuals.iconFor(event.category);
    final explainer = narratorExplainerFor(event.eventType);
    final action = narratorActionFor(event.eventType);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NightshadeTokens.spaceLg,
          NightshadeTokens.spaceMd,
          NightshadeTokens.spaceLg,
          NightshadeTokens.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle.
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceLg),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Category + severity chip row.
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  _categoryLabel(event.category),
                  style: NightshadeTypography.labelStrongSm.copyWith(
                    color: accent,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                if (event.pinned)
                  Text(
                    'PINNED',
                    style: NightshadeTypography.labelQuiet.copyWith(
                      color: colors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),

            // Headline.
            Text(
              event.headline,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize14,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),

            // Body.
            if (event.body != null && event.body!.isNotEmpty) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                event.body!,
                style: NightshadeTypography.body.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],

            // Enlarged evidence viz.
            if (event.evidence != null) ...[
              const SizedBox(height: NightshadeTokens.spaceLg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                  border:
                      Border.all(color: colors.border.withValues(alpha: 0.6)),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: NarratorEvidenceViz(
                    evidence: event.evidence!,
                    accent: accent,
                    emphasized: event.severity == NarratorSeverity.celebrate,
                    large: true,
                  ),
                ),
              ),
            ],

            // "Why this matters" explainer.
            if (explainer != null) ...[
              const SizedBox(height: NightshadeTokens.spaceLg),
              Text(
                'WHY THIS MATTERS',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                explainer,
                style: NightshadeTypography.body.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],

            // Action button.
            if (action != null) ...[
              const SizedBox(height: NightshadeTokens.spaceLg),
              SizedBox(
                width: double.infinity,
                child: NightshadeButton(
                  label: action.label,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(action.route);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _categoryLabel(NarratorCategory category) {
    return switch (category) {
      NarratorCategory.discovery => 'DISCOVERY',
      NarratorCategory.milestone => 'MILESTONE',
      NarratorCategory.conditions => 'CONDITIONS',
      NarratorCategory.equipment => 'EQUIPMENT',
      NarratorCategory.quality => 'QUALITY',
    };
  }
}
