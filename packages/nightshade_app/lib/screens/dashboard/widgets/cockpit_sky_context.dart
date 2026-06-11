import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../sequencer/widgets/run_dashboard/run_dashboard_format.dart';
import '../../sequencer/widgets/run_dashboard/run_dashboard_providers.dart';

/// Cockpit "Sky Context" panel — where the target sits in the sky right now,
/// plus the moon and darkness window that frame the night.
///
/// Active target: altitude (color-graded against the effective horizon like
/// `cockpit_now_imaging`), azimuth, airmass, time-to-transit / time-to-set,
/// moon illumination + phase, and time remaining until astronomical dawn.
///
/// Idle: a slim single row that still earns its place — tonight's astro-dark
/// window and the moon illumination.
///
/// Reads [runDashboardActiveTargetProvider] / [runDashboardSkyStatsProvider]
/// for target geometry and the planetarium [twilightTimesProvider],
/// [moonInfoProvider], [observationTimeProvider] for the night frame. Never
/// throws on nulls — every readout degrades to `—`.
class CockpitSkyContext extends ConsumerWidget {
  const CockpitSkyContext({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final target = ref.watch(runDashboardActiveTargetProvider);

    final twilight = ref.watch(twilightTimesProvider);
    final moon = ref.watch(moonInfoProvider);

    if (target == null) {
      return _Shell(
        colors: colors,
        child: Row(
          children: [
            Icon(LucideIcons.orbit, size: 15, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                _idleSummary(twilight, moon),
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12_5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Watched only on the active-target path: the idle row doesn't use `now`,
    // so it shouldn't rebuild on the planetarium clock's 1 s tick.
    final now = ref.watch(observationTimeProvider.select((s) => s.time));
    final sky = ref.watch(runDashboardSkyStatsProvider);
    final altText =
        sky != null ? '${sky.altitudeDeg.toStringAsFixed(1)}°' : '—';
    final altColor =
        sky == null ? colors.textMuted : _altitudeColor(sky, colors);
    final azText = sky != null ? '${sky.azimuthDeg.toStringAsFixed(0)}°' : '—';
    final airmassText = sky != null ? _airmass(sky.altitudeDeg) : '—';

    final darkRemaining = _darknessRemaining(twilight, now);

    return _Shell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.orbit, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'SKY CONTEXT',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: NightshadeTokens.spaceLg,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              _StatTile(
                colors: colors,
                icon: LucideIcons.mountain,
                label: 'Altitude',
                value: altText,
                valueColor: altColor,
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.compass,
                label: 'Azimuth',
                value: azText,
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.layers,
                label: 'Airmass',
                value: airmassText,
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.timer,
                label: 'To meridian',
                value: formatDuration(sky?.timeToTransit),
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.sunset,
                label: 'To set',
                value: formatDuration(sky?.timeToSet),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: NightshadeTokens.spaceLg,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              _StatTile(
                colors: colors,
                icon: LucideIcons.moonStar,
                label: moon.phaseName,
                value: '${moon.illumination.toStringAsFixed(0)}%',
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.moon,
                label: 'Astro dark left',
                value: formatDuration(darkRemaining),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Idle summary: astro-dark window + moon illumination.
  String _idleSummary(TwilightTimes twilight, MoonTimes moon) {
    final dusk = twilight.astronomicalDusk;
    final dawn = twilight.astronomicalDawn;
    final window = (dusk != null && dawn != null)
        ? 'astro dark ${formatTimeOfDay(dusk)}→${formatTimeOfDay(dawn)}'
        : 'astro dark unavailable';
    return 'No target — $window · Moon ${moon.illumination.toStringAsFixed(0)}%';
  }
}

/// Airmass via the secant approximation: sec(zenith) = 1/cos(z). Returns `—`
/// when the target is at or below ~3° (where plane-parallel airmass blows up
/// and is meaningless anyway).
String _airmass(double altitudeDeg) {
  if (altitudeDeg <= 3.0) return '—';
  final zenithRad = (90.0 - altitudeDeg) * math.pi / 180.0;
  final airmass = 1.0 / math.cos(zenithRad);
  return airmass.toStringAsFixed(2);
}

/// Time remaining until astronomical dawn, or `null` when dawn is unknown or
/// already past (so the readout shows `—`).
Duration? _darknessRemaining(TwilightTimes twilight, DateTime now) {
  final dawn = twilight.astronomicalDawn;
  if (dawn == null) return null;
  if (!dawn.isAfter(now)) return null;
  return dawn.difference(now);
}

/// Grade altitude against the effective horizon, matching `cockpit_now_imaging`:
/// below the horizon is error, within a 15°-clamped margin is warning, above is
/// success.
Color _altitudeColor(RunDashboardSkyStats sky, NightshadeColors colors) {
  final horizon = sky.horizonDeg;
  if (sky.altitudeDeg <= horizon) return colors.error;
  final margin =
      (90.0 - horizon) * 0.25 < 15.0 ? (90.0 - horizon) * 0.25 : 15.0;
  if (sky.altitudeDeg < horizon + margin) return colors.warning;
  return colors.success;
}

/// Compact label-over-value stat tile with tabular figures.
class _StatTile extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize9_5,
                color: colors.textMuted,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            TextStyle(
              fontSize: NightshadeTypography.fontSize15,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Self-chromed container matching the cockpit card styling.
class _Shell extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _Shell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: child,
    );
  }
}
