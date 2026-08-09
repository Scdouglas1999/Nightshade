import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'science_ladder_model.dart';

void showScienceRungSheet(
  BuildContext context,
  ScienceRungSpec spec,
  RungState state, {
  String? prerequisite,
  VoidCallback? onCta,
  String? unlockLabel,
  VoidCallback? onUnlock,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _ScienceRungSheet(
      spec: spec,
      state: state,
      prerequisite: prerequisite,
      onCta: onCta,
      unlockLabel: unlockLabel,
      onUnlock: onUnlock,
    ),
  );
}

class _ScienceRungSheet extends ConsumerWidget {
  final ScienceRungSpec spec;
  final RungState state;
  final String? prerequisite;
  final VoidCallback? onCta;

  /// Where the operator has to go to satisfy [prerequisite], for a locked rung.
  ///
  /// Without it the locked sheet named a precondition and offered only "Got
  /// it": it told the user what to do and then made them close it and go find
  /// the control themselves.
  final String? unlockLabel;
  final VoidCallback? onUnlock;

  const _ScienceRungSheet({
    required this.spec,
    required this.state,
    this.prerequisite,
    this.onCta,
    this.unlockLabel,
    this.onUnlock,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return NightshadeDialog(
      title: spec.title,
      icon: _iconFor(spec.rung),
      width: 480,
      actions: _actions(context, ref, colors),
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
        return [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Got it',
            variant: ButtonVariant.ghost,
          ),
          if (onUnlock != null && unlockLabel != null)
            NightshadeButton(
              onPressed: () {
                Navigator.of(context).pop();
                onUnlock!.call();
              },
              label: unlockLabel!,
              icon: LucideIcons.arrowRight,
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
