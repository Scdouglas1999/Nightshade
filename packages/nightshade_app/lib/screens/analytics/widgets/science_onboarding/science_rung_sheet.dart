import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'science_ladder_model.dart';

void showScienceRungSheet(
  BuildContext context,
  ScienceRungSpec spec,
  RungState state, {
  String? prerequisite,
  VoidCallback? onCta,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _ScienceRungSheet(
      spec: spec,
      state: state,
      prerequisite: prerequisite,
      onCta: onCta,
    ),
  );
}

class _ScienceRungSheet extends ConsumerWidget {
  final ScienceRungSpec spec;
  final RungState state;
  final String? prerequisite;
  final VoidCallback? onCta;

  const _ScienceRungSheet({
    required this.spec,
    required this.state,
    this.prerequisite,
    this.onCta,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return NightshadeDialog(
      title: spec.title,
      icon: _iconFor(spec.rung),
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            spec.blurb,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          if (state == RungState.locked && prerequisite != null) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            Container(
              padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
              decoration: NightshadeDecorations.emphasisSurface(
                colors.textMuted,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.lock,
                    size: NightshadeTokens.iconXs,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      prerequisite!,
                      style: NightshadeTypography.caption.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: _actions(context, ref, colors),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
  ) {
    switch (state) {
      case RungState.ready:
        return [
          NightshadeButton(
            onPressed: () {
              Navigator.of(context).pop();
              onCta?.call();
            },
            label: spec.ctaLabel,
          ),
        ];
      case RungState.locked:
        if (spec.rung == ScienceRung.track) {
          return [
            NightshadeButton(
              onPressed: () {
                ref
                    .read(scienceSettingsProvider.notifier)
                    .setFeatureEnabled(ScienceFeature.photometry, true);
                Navigator.of(context).pop();
              },
              label: 'Turn on live photometry',
              icon: LucideIcons.activity,
            ),
          ];
        }
        return [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Got it',
            variant: ButtonVariant.ghost,
          ),
        ];
      case RungState.done:
        return [
          NightshadeButton(
            onPressed: () {
              Navigator.of(context).pop();
              onCta?.call();
            },
            label: 'Jump to it',
            variant: ButtonVariant.outline,
            icon: LucideIcons.arrowRight,
          ),
        ];
    }
  }

  IconData _iconFor(ScienceRung rung) {
    return switch (rung) {
      ScienceRung.measure => LucideIcons.target,
      ScienceRung.track => LucideIcons.activity,
      ScienceRung.curve => LucideIcons.lineChart,
      ScienceRung.period => LucideIcons.timer,
      ScienceRung.contribute => LucideIcons.share2,
    };
  }
}
