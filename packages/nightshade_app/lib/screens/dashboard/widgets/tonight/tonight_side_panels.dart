// The c5 column beside the first-light checklist (06 §Tonight, first-run
// state): the moon, the weather and last night.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart' hide TwilightTimes;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../../localization/nightshade_localizations.dart';
import '../../../sequencer/widgets/run_dashboard/weather_safety_card.dart'
    show RunDashboardSafetyBadge, runDashboardSafetyBadge;
import '../standby/moon_card.dart' show MoonPainter;
import 'tonight_night.dart';

/// The phase disc's diameter (06 §Tonight: 56 px).
const double _discSize = 56;

/// Phase disc plus Illuminated / Moonset / Moonrise.
class TonightMoonPanel extends ConsumerWidget {
  const TonightMoonPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final night = ref.watch(tonightNightProvider);
    final illumination = night?.moonIllumination;

    return NightshadePanel(
      head: PanelHead(icon: LucideIcons.moon, label: l10n.text('tnMoon')),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: _discSize,
            height: _discSize,
            child: CustomPaint(
              painter: MoonPainter(
                illumination: (illumination ?? 0) * 100,
                // Waxing between new and full: the moon that sets AFTER the sun
                // is the one lit on its western limb.
                waxing: _isWaxing(night),
                litColor: colors.textPrimary,
                darkColor: colors.well,
                borderColor: colors.border,
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceLg),
          Expanded(
            child: ReadoutRow(
              gap: NightshadeTokens.spaceXl,
              children: <Readout>[
                Readout(
                  value: illumination == null
                      ? null
                      : '${(illumination * 100).round()}',
                  unit: '%',
                  label: l10n.text('tnIlluminated'),
                ),
                Readout(
                  value: night?.moonSet == null
                      ? null
                      : tonightClock(night!.moonSet!),
                  label: l10n.text('tnMoonset'),
                ),
                Readout(
                  value: night?.moonRise == null
                      ? null
                      : tonightClock(night!.moonRise!),
                  label: l10n.text('tnMoonrise'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A moon that sets after it rises on the same night is waxing.
  ///
  /// Not an ephemeris — the disc only needs to know which limb to light, and
  /// this is the one signal the night's own times already carry.
  static bool _isWaxing(TonightNight? night) {
    final rise = night?.moonRise;
    final set = night?.moonSet;
    if (rise == null || set == null) return true;
    return set.isAfter(rise);
  }
}

/// Whether the mount will be parked for you, and the way to change that.
class TonightWeatherPanel extends ConsumerWidget {
  const TonightWeatherPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final safety = ref.watch(weatherSafetyProvider);

    final badge = runDashboardSafetyBadge(
      status: safety.status,
      monitoringEnabled: safety.monitoringEnabled,
      dataSource: safety.dataSource,
    );

    final (String label, ChipTone tone) = switch (badge) {
      RunDashboardSafetyBadge.safe => (l10n.text('tnSafe'), ChipTone.success),
      RunDashboardSafetyBadge.unsafe => (l10n.text('tnUnsafe'), ChipTone.error),
      RunDashboardSafetyBadge.snoozed => (
          l10n.text('tnSnoozed'),
          ChipTone.warning,
        ),
      RunDashboardSafetyBadge.notMonitored => (
          l10n.text('tnNotMonitored'),
          ChipTone.neutral,
        ),
      RunDashboardSafetyBadge.noData => (
          l10n.text('tnNoWeatherData'),
          ChipTone.warning,
        ),
    };

    return NightshadePanel(
      head: PanelHead(
        icon: LucideIcons.cloudSun,
        label: l10n.text('tnWeather'),
        trailing: <Widget>[NightshadeChip(label: label, tone: tone)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            safety.monitoringEnabled
                ? l10n.text('tnWeatherOnBody')
                : l10n.text('tnWeatherOffBody'),
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          NightshadeButton(
            label: l10n.text('tnOpenWeather'),
            variant: ButtonVariant.secondary,
            size: ButtonSize.small,
            onPressed: () => context.go('/weather'),
          ),
        ],
      ),
    );
  }
}

/// Last night's run, or the promise of one.
class TonightLastNightPanel extends ConsumerWidget {
  const TonightLastNightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    // `watchAllRuns()` orders by startedAt desc, so the head is the newest run.
    final lastRun = ref.watch(sequenceRunsProvider).maybeWhen(
          data: (runs) => runs.isEmpty ? null : runs.first,
          orElse: () => null,
        );
    // Only claim "Last night" when the run genuinely was last night; a
    // weeks-old run under that header reads as a stale-data bug.
    final recent = lastRun != null &&
        DateTime.now().difference(lastRun.startedAt) <
            const Duration(hours: 24);

    return NightshadePanel(
      head: PanelHead(
        icon: LucideIcons.history,
        label: l10n.text(recent ? 'tnLastNight' : 'tnLastRun'),
      ),
      child: lastRun == null
          ? Text(
              l10n.text('tnNoRunsYet'),
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  lastRun.sequenceName,
                  style: NightshadeTypography.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                ReadoutRow(
                  gap: NightshadeTokens.spaceXl,
                  children: <Readout>[
                    Readout(
                      value: tonightClock(lastRun.startedAt.toLocal()),
                      label: l10n.text('tnStarted'),
                      size: ReadoutSize.sm,
                    ),
                    Readout(
                      value: lastRun.status,
                      label: l10n.text('tnOutcome'),
                      size: ReadoutSize.sm,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
