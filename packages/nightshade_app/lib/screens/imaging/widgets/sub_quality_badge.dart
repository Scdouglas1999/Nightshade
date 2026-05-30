import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact per-sub quality badge for the live preview.
///
/// Surfaces the three quality metrics that matter at the eyepiece while a
/// sub is on screen — HFR, eccentricity, and star count — alongside an
/// ACCEPT/REJECT verdict computed from the *same* [FrameGradeRules] engine
/// the persisted auto-grader uses, so the live badge and the on-disk grade
/// never disagree.
///
/// Why a distinct widget from [ImageStatsOverlay]: that overlay is a generic
/// raw-stats readout (median/mean/etc.) painted on an ad-hoc black scrim.
/// This badge is quality-focused, opinionated, and styled to match the other
/// top-right preview badges ([RawPreviewStatusBadge] / the calibrated badge):
/// a translucent [NightshadeColors.surface] pill with a 1px border, not a
/// black overlay. Keeping it separate also keeps ownership clean — the host
/// (C6) positions this badge independently of the stats overlay.
///
/// Reads:
/// * [lastImageStatsProvider] — the HFR / star-count snapshot of the most
///   recently captured frame. When `null` (no frame yet) the badge renders
///   nothing rather than fabricating zeros — an honest empty state.
/// * [scienceSettingsProvider] — resolved into [FrameGradeRules]; the verdict
///   chip only appears when the rules actually grade something
///   ([FrameGradeRules.hasActiveRules]).
/// * [guideStatsProvider] — live total RMS in **arcseconds**
///   ([Phd2GuideStats.rmsTotal] is PHD2's calibrated arcsecond residual; see
///   its field docs and the `GuideHealthCard` arcsecond readout), fed into
///   [FrameGradeRules.gradeStats] against [FrameGradeRules.maxGuidingRmsTotalArcsec]
///   so a guiding excursion can reject a sub exactly as the auto-grader would.
///   Units match end to end: the threshold, the live value, and the rendered
///   `"` glyph in the reject reason are all arcseconds.
///
/// [eccentricity] is injected by the host because [ImageStats] does not carry
/// it; C6 pulls it from the per-frame science row by `currentFrameImageId` and
/// passes `null` when no science measurement exists for the frame, which the
/// badge renders as `ECC —` (and which causes the eccentricity rule, if any,
/// to be skipped — matching [FrameGradeRules.gradeStats] semantics).
class SubQualityBadge extends ConsumerWidget {
  /// Per-frame eccentricity from the science row, or `null` when unavailable.
  final double? eccentricity;

  const SubQualityBadge({super.key, this.eccentricity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(lastImageStatsProvider);

    // Honest empty state: no captured frame yet means nothing to grade.
    if (stats == null) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);
    final rules = ref.watch(
      scienceSettingsProvider.select(
        (async) => async.valueOrNull?.resolvedFrameGradeRules(),
      ),
    );
    // Live guiding RMS (arcseconds) only matters for the verdict; select the
    // single field so the badge does not rebuild on every unrelated guide-stat
    // tick. This is the same arcsecond value GuideHealthCard renders, compared
    // against the arcsecond maxGuidingRmsTotalArcsec threshold.
    final guidingRmsTotal = ref.watch(
      guideStatsProvider.select((s) => s.rmsTotal),
    );

    final hfrText = stats.hfr != null ? stats.hfr!.toStringAsFixed(2) : '—';
    final eccText =
        eccentricity != null ? eccentricity!.toStringAsFixed(2) : '—';
    final starText = stats.starCount != null ? '${stats.starCount}' : '—';

    // PHD2 reports 0.0 as its "no data yet" sentinel for rolling RMS; treat
    // that as "no guiding telemetry" so we never reject a frame on a phantom
    // perfect-zero RMS before the guider has produced a sample.
    final liveRms = guidingRmsTotal > 0 ? guidingRmsTotal : null;

    final hasRules = rules != null && rules.hasActiveRules;
    final rejectReason = hasRules
        ? rules.gradeStats(
            stats,
            guidingRmsTotal: liveRms,
            eccentricity: eccentricity,
          )
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: NightshadeTokens.opacityStrong),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: NightshadeTokens.paddingSm,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetricChip(label: 'HFR', value: hfrText, colors: colors),
            const SizedBox(width: NightshadeTokens.spaceMd),
            _MetricChip(label: 'ECC', value: eccText, colors: colors),
            const SizedBox(width: NightshadeTokens.spaceMd),
            _MetricChip(
              label: null,
              value: starText,
              trailingGlyph: '★',
              colors: colors,
            ),
            if (hasRules) ...[
              const SizedBox(width: NightshadeTokens.spaceMd),
              _VerdictChip(reason: rejectReason, colors: colors),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single telemetry metric: an optional muted label followed by a
/// tabular-figures mono value so digit changes between subs don't jitter the
/// layout. The star-count chip uses [trailingGlyph] ('★') instead of a label.
class _MetricChip extends StatelessWidget {
  final String? label;
  final String value;
  final String? trailingGlyph;
  final NightshadeColors colors;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.colors,
    this.trailingGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = NightshadeTypography.withTabular(
      NightshadeTypography.monoSm,
    ).copyWith(color: colors.textPrimary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: NightshadeTypography.labelQuiet.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
        ],
        Text(value, style: valueStyle),
        if (trailingGlyph != null) ...[
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            trailingGlyph!,
            style: NightshadeTypography.monoSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// ACCEPT / REJECT verdict pill. Green dot + check for accept, red dot + x for
/// reject; the reject variant wraps in a [NightshadeTooltip] exposing the
/// human-readable rejection reason from [FrameGradeRules.gradeStats].
class _VerdictChip extends StatelessWidget {
  /// `null` when the frame passes every active rule (ACCEPT); otherwise the
  /// rejection reason string.
  final String? reason;
  final NightshadeColors colors;

  const _VerdictChip({required this.reason, required this.colors});

  @override
  Widget build(BuildContext context) {
    final accepted = reason == null;
    final statusColor = accepted ? colors.success : colors.error;
    final label = accepted ? 'ACCEPT' : 'REJECT';
    final glyph = accepted ? LucideIcons.check : LucideIcons.x;

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: NightshadeTokens.opacityStatusFill),
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(
          color: statusColor.withValues(
            alpha: NightshadeTokens.opacityEmphasisBorder,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceSm,
          vertical: NightshadeTokens.spaceXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(
              color: statusColor,
              variant: accepted
                  ? StatusDotVariant.static
                  : StatusDotVariant.attention,
            ),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Icon(glyph, size: NightshadeTokens.iconXs, color: statusColor),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              label,
              style: NightshadeTypography.labelSm.copyWith(color: statusColor),
            ),
          ],
        ),
      ),
    );

    if (accepted) return pill;

    return NightshadeTooltip(message: reason!, child: pill);
  }
}
