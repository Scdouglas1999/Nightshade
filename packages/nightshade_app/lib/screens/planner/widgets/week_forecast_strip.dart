import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// "This Week" planner tab content — a ranked, at-a-glance forecast strip of
/// the upcoming nights for the active campaign's still-incomplete targets.
///
/// Renders one [NightshadeCard] per [NightForecast] in a horizontally
/// scrollable row, ordered chronologically. Each card shows the weekday/date,
/// a clarity score visual mapped to the semantic status colors, the clear-vs-
/// total dark hours, and the one or two targets that are most up that night.
/// The single best-scoring night ([WeekForecast.bestNight]) is highlighted via
/// the card's selected accent.
///
/// Fail-closed is structural: the widget never fabricates a clear night.
///   * A provider error surfaces as a [NightshadeAlert] (the forecast feed /
///     site configuration failed — the operator must see why).
///   * A [WeekForecast] that is not [WeekForecast.available] renders only a
///     warning banner with the honest reason and *no* night cards.
///   * A per-night [NightForecast] that is not [NightForecast.forecastAvailable]
///     renders a muted "No forecast" card rather than an implied clear sky.
class WeekForecastStrip extends ConsumerWidget {
  const WeekForecastStrip({super.key});

  /// Fixed card width — wide enough for the date header, score bar, hours, and
  /// up to two target names without truncating the common case, narrow enough
  /// that several nights are visible at once in the horizontal scroller.
  static const double _cardWidth = 168;

  /// Height of the loading skeleton / card row. Cards size to content, but the
  /// skeleton needs an explicit extent inside the bounded scroller. Sized to
  /// comfortably fit the tallest card body (the per-night "No forecast" card,
  /// whose centered icon + two-line reason is taller than the score-bar layout)
  /// plus the scroller's vertical padding, so no card body overflows.
  static const double _stripHeight = 216;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final forecastAsync = ref.watch(weekForecastProvider);

    return forecastAsync.when(
      loading: () => const _ForecastSkeletonStrip(),
      error: (error, _) => Padding(
        padding: NightshadeTokens.screenPadding,
        child: NightshadeAlert(
          severity: NightshadeAlertSeverity.error,
          title: 'Forecast unavailable',
          message: error.toString(),
          action: NightshadeButton(
            label: 'Retry',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => ref.invalidate(weekForecastProvider),
          ),
        ),
      ),
      data: (week) {
        if (!week.available) {
          // Whole-lookahead failure — show the honest reason, no night cards.
          // This is the fail-closed contract: never render fabricated nights.
          return Padding(
            padding: NightshadeTokens.screenPadding,
            child: Align(
              alignment: Alignment.topLeft,
              child: NightshadeInlineBanner(
                severity: NightshadeAlertSeverity.warning,
                message: week.unavailableReason ?? 'Forecast unavailable',
              ),
            ),
          );
        }

        if (week.nights.isEmpty) {
          // Available but with nothing to rank (no incomplete targets / empty
          // lookahead). Honest empty state rather than a blank strip.
          return EmptyState(
            icon: LucideIcons.cloudMoon,
            title: 'Nothing to forecast yet',
            body: 'Add targets with integration goals to see the best upcoming '
                'nights for your campaign.',
          );
        }

        final best = week.bestNight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NightshadeTokens.spaceLg,
                NightshadeTokens.spaceLg,
                NightshadeTokens.spaceLg,
                0,
              ),
              child: const SectionHeader(
                title: 'This Week',
                subtitle: 'Best nights for your campaign targets',
              ),
            ),
            SizedBox(
              height: _stripHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: NightshadeTokens.screenPadding,
                itemCount: week.nights.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: NightshadeTokens.spaceMd),
                itemBuilder: (context, index) {
                  final night = week.nights[index];
                  return _NightCard(
                    night: night,
                    // Identity match: the best night is the exact instance
                    // returned by bestNight, so reference equality is safe and
                    // avoids highlighting a tied-but-different night.
                    isBest: best != null && identical(night, best),
                    colors: colors,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One night's forecast card.
class _NightCard extends StatelessWidget {
  const _NightCard({
    required this.night,
    required this.isBest,
    required this.colors,
  });

  final NightForecast night;
  final bool isBest;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: WeekForecastStrip._cardWidth,
      child: NightshadeCard(
        isSelected: isBest,
        padding: NightshadeTokens.cardPadding,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Per-night unavailability is honest: a muted "No forecast" card, never a
    // fabricated clear night.
    if (!night.forecastAvailable) {
      return _unavailableBody();
    }

    // A night with no astronomical darkness (e.g. high-latitude summer) is a
    // real, available result — there is simply nothing to image.
    final hasDarkness = night.darkHours > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: NightshadeTokens.spaceMd),
        if (!hasDarkness)
          _noDarknessBody()
        else ...[
          _scoreBar(),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _darkHoursRow(),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Expanded(child: _targets()),
        ],
      ],
    );
  }

  /// Weekday + day-of-month header, with a "best" marker on the highlighted
  /// night so the selection reads clearly even at a glance.
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _weekdayDate(night.nightDateLocal),
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
        ),
        if (isBest) ...[
          const SizedBox(width: NightshadeTokens.spaceXs),
          Icon(
            LucideIcons.star,
            size: NightshadeTokens.iconXs,
            color: colors.accent,
          ),
        ],
      ],
    );
  }

  Widget _unavailableBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.cloudOff,
                  size: NightshadeTokens.iconLg,
                  color: colors.textMuted,
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  'No forecast',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textMuted),
                ),
                if (night.unavailableReason != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  Text(
                    night.unavailableReason!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _noDarknessBody() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.sun,
              size: NightshadeTokens.iconLg,
              color: colors.textMuted,
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'No astronomical darkness',
              textAlign: TextAlign.center,
              style:
                  NightshadeTypography.bodySm.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// Clarity score visual: a [StatusDot] in the score's semantic color plus a
  /// filled track whose fill fraction is the score and whose color maps
  /// 0..1 → error/warning/success. Alpha overlays only — no hardcoded colors.
  Widget _scoreBar() {
    final score = night.score;
    final scoreColor = _scoreColor(score, colors);
    return Row(
      children: [
        StatusDot(color: scoreColor),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: ClipRRect(
            borderRadius: NightshadeTokens.borderRadiusFull,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: NightshadeTokens.spaceSm,
                      color: scoreColor.withValues(
                        alpha: NightshadeTokens.opacityStatusFill,
                      ),
                    ),
                    Container(
                      height: NightshadeTokens.spaceSm,
                      width: constraints.maxWidth * score.clamp(0.0, 1.0),
                      color: scoreColor,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Clear vs total dark hours, e.g. "5.1 / 7.0h clear", in mono so the figures
  /// line up across cards.
  Widget _darkHoursRow() {
    final clear = night.clearDarkHours.toStringAsFixed(1);
    final dark = night.darkHours.toStringAsFixed(1);
    return Row(
      children: [
        Icon(
          LucideIcons.moon,
          size: NightshadeTokens.iconXs,
          color: colors.textSecondary,
        ),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Flexible(
          child: Text(
            '$clear / ${dark}h clear',
            style: NightshadeTypography.monoSm
                .copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// The top one-or-two targets that are up this night.
  Widget _targets() {
    if (night.bestTargets.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No targets up',
          style:
              NightshadeTypography.captionSm.copyWith(color: colors.textMuted),
        ),
      );
    }

    final shown = night.bestTargets.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final target in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
            child: Row(
              children: [
                Icon(
                  LucideIcons.target,
                  size: NightshadeTokens.iconXs,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: NightshadeTokens.spaceXs),
                Expanded(
                  child: Text(
                    target.targetName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Maps a 0..1 clarity score to a semantic status color:
  /// clear → success, mid → warning, cloudy → error.
  static Color _scoreColor(double score, NightshadeColors colors) {
    if (score >= 0.66) return colors.success;
    if (score >= 0.33) return colors.warning;
    return colors.error;
  }

  /// Formats a local night date as e.g. "Fri 30".
  static String _weekdayDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // DateTime.weekday is 1 (Mon) .. 7 (Sun).
    final name = weekdays[(date.weekday - 1) % 7];
    return '$name ${date.day}';
  }
}

/// Horizontal row of shimmering skeleton cards shown while the forecast loads.
class _ForecastSkeletonStrip extends StatelessWidget {
  const _ForecastSkeletonStrip();

  static const int _skeletonCount = 5;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return ShimmerLoading(
      child: SizedBox(
        height: WeekForecastStrip._stripHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: NightshadeTokens.screenPadding,
          itemCount: _skeletonCount,
          separatorBuilder: (_, __) =>
              const SizedBox(width: NightshadeTokens.spaceMd),
          itemBuilder: (_, __) => Container(
            width: WeekForecastStrip._cardWidth,
            padding: NightshadeTokens.cardPadding,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusMd,
              border: Border.all(color: colors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 80, height: 14),
                SizedBox(height: NightshadeTokens.spaceMd),
                SkeletonText(height: 8),
                SizedBox(height: NightshadeTokens.spaceSm),
                SkeletonText(width: 110, height: 11),
                SizedBox(height: NightshadeTokens.spaceMd),
                SkeletonText(width: 120, height: 11),
                SizedBox(height: NightshadeTokens.spaceXs),
                SkeletonText(width: 90, height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
