// Part of ../sub_cull_rail.dart -- extracted for maintainability.
//
// Cull toolbar, selection pill and lasso painter.
part of '../sub_cull_rail.dart';

class _CullToolbar extends StatelessWidget {
  final bool blink;
  final bool selectMode;
  final int selectedCount;
  final double hfrThreshold;

  /// Render-time verdict on the curve-driven cull. The toolbar renders the
  /// quantified action only when this is offerable.
  final CullRecommendationOffer offer;

  /// Live accepted-sub count, quoted in the stale explanation so the user can
  /// see *why* the analysis no longer applies.
  final int acceptedCount;
  final VoidCallback onToggleBlink;
  final VoidCallback onToggleSelect;
  final ValueChanged<double> onHfrChanged;
  final VoidCallback onBulkCull;
  final VoidCallback? onRejectSelected;
  final VoidCallback? onClearSelection;
  final VoidCallback? onCullToRecommended;

  const _CullToolbar({
    required this.blink,
    required this.selectMode,
    required this.selectedCount,
    required this.hfrThreshold,
    required this.offer,
    required this.acceptedCount,
    required this.onToggleBlink,
    required this.onToggleSelect,
    required this.onHfrChanged,
    required this.onBulkCull,
    required this.onRejectSelected,
    required this.onClearSelection,
    required this.onCullToRecommended,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final keepN = offer.keepN;
    final gainPct = offer.gainPct;

    return Wrap(
      spacing: NightshadeTokens.spaceMd,
      runSpacing: NightshadeTokens.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NightshadeButton(
          label: blink ? 'Stop blink' : 'Blink mode',
          icon: NightshadeIcons.play,
          variant: blink ? ButtonVariant.primary : ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onToggleBlink,
        ),
        NightshadeButton(
          label: selectMode ? 'Done selecting' : 'Select / lasso',
          icon: NightshadeIcons.crosshair,
          variant: selectMode ? ButtonVariant.primary : ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onToggleSelect,
        ),
        if (selectMode) ...[
          _SelectionPill(count: selectedCount, colors: colors),
          NightshadeButton(
            label: 'Reject selected',
            icon: NightshadeIcons.error,
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: onRejectSelected,
          ),
          NightshadeButton(
            label: 'Clear',
            icon: NightshadeIcons.close,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: onClearSelection,
          ),
        ],
        if (onCullToRecommended != null)
          Tooltip(
            message:
                'Drop to the optimizer-recommended best $keepN subs (+${gainPct.toStringAsFixed(0)}% SNR)',
            child: NightshadeButton(
              label: 'Keep best $keepN (+${gainPct.toStringAsFixed(0)}%)',
              icon: NightshadeIcons.success,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onCullToRecommended,
            ),
          )
        else if (offer.status == CullOfferStatus.stale)
          Tooltip(
            message: 'The optimizer ran over ${offer.populationSize} '
                '${offer.populationSize == 1 ? 'sub' : 'subs'}; '
                '$acceptedCount ${acceptedCount == 1 ? 'is' : 'are'} accepted '
                'now, so its keep-set no longer maps to them. Re-integrate to '
                'recompute the curve over the current selection.',
            child: const NightshadeChip(
              label: 'Cull analysis out of date',
              icon: NightshadeIcons.warning,
            ),
          )
        else if (offer.status == CullOfferStatus.alreadyOptimal)
          Tooltip(
            // Two different states share this status and they must not share a
            // sentence. "Keeps everything" is only true when keepN covers the
            // population; when the optimizer picked a SMALLER keep-set that
            // simply predicts no gain, saying it "would keep all N" misreports
            // what the optimizer actually recommended.
            message: keepN >= offer.populationSize
                ? 'The optimizer would keep all $acceptedCount accepted '
                    '${acceptedCount == 1 ? 'sub' : 'subs'} — there is '
                    'nothing to cull.'
                : 'The optimizer would keep $keepN of $acceptedCount, but '
                    'predicts no SNR gain from dropping the rest '
                    '(${gainPct.toStringAsFixed(0)}%), so the full stack is '
                    'the better one.',
            child: const NightshadeChip(
              label: 'Keep-set already optimal',
              icon: NightshadeIcons.success,
            ),
          ),
        if (!selectMode)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cull HFR >',
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textSecondary),
              ),
              SizedBox(
                width: 160,
                child: Slider(
                  value: hfrThreshold.clamp(1.0, 8.0),
                  min: 1.0,
                  max: 8.0,
                  divisions: 28,
                  activeColor: colors.primary,
                  label: hfrThreshold.toStringAsFixed(1),
                  onChanged: onHfrChanged,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  hfrThreshold.toStringAsFixed(1),
                  style: NightshadeTypography.mono
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        if (!selectMode)
          NightshadeButton(
            label: 'Reject HFR above',
            icon: NightshadeIcons.error,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onBulkCull,
          ),
      ],
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final int count;
  final NightshadeColors colors;
  const _SelectionPill({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.primary
            .withValues(alpha: NightshadeTokens.opacityStatusFill),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
        border: Border.all(color: colors.primary),
      ),
      child: Text(
        '$count selected',
        style: NightshadeTypography.labelSm.copyWith(color: colors.primary),
      ),
    );
  }
}

class _LassoPainter extends CustomPainter {
  final Rect rect;
  final Color color;

  _LassoPainter({required this.rect, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color.withValues(alpha: NightshadeTokens.opacityStatusFill)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(_LassoPainter old) =>
      old.rect != rect || old.color != color;
}
