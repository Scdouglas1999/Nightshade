import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:intl/intl.dart';
import '../planetarium_screen.dart';
import 'sidebar_shared_widgets.dart';

class TonightTab extends ConsumerWidget {
  final NightshadeColors colors;

  const TonightTab({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moonInfo = ref.watch(moonInfoProvider);
    final bestTargets = ref.watch(bestTargetsProvider);
    final location = ref.watch(observerLocationProvider);
    final settingsAsync = ref.watch(appSettingsProvider);

    // Check if using default location (no location set in settings)
    final settings = settingsAsync.valueOrNull;
    final isDefaultLocation = settings == null ||
        (settings.latitude == 0.0 && settings.longitude == 0.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location indicator
          _LocationIndicator(
            colors: colors,
            isDefaultLocation: isDefaultLocation,
            location: location,
          ),

          const SizedBox(height: 16),

          // Twilight card - Evening
          InfoCard(
            title: 'Evening Twilight',
            icon: LucideIcons.sunset,
            color: colors.warning,
            colors: colors,
            child: Column(
              children: [
                if (twilight.sunset != null)
                  TwilightRow(
                    label: 'Sunset',
                    time:
                        DateFormat('HH:mm').format(twilight.sunset!.toLocal()),
                    colors: colors,
                  ),
                if (twilight.civilDusk != null)
                  TwilightRow(
                    label: 'Civil Dusk',
                    time: DateFormat('HH:mm')
                        .format(twilight.civilDusk!.toLocal()),
                    colors: colors,
                  ),
                if (twilight.nauticalDusk != null)
                  TwilightRow(
                    label: 'Nautical Dusk',
                    time: DateFormat('HH:mm')
                        .format(twilight.nauticalDusk!.toLocal()),
                    colors: colors,
                  ),
                if (twilight.astronomicalDusk != null)
                  TwilightRow(
                    label: 'Astro Dusk',
                    time: DateFormat('HH:mm')
                        .format(twilight.astronomicalDusk!.toLocal()),
                    isPrimary: true,
                    colors: colors,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Darkness duration card
          if (twilight.astronomicalDusk != null &&
              twilight.astronomicalDawn != null)
            DarknessCard(
              twilight: twilight,
              colors: colors,
            ),

          const SizedBox(height: 16),

          // Morning Twilight card
          InfoCard(
            title: 'Morning Twilight',
            icon: LucideIcons.sunrise,
            color: const Color(0xFFFF9F45),
            colors: colors,
            child: Column(
              children: [
                if (twilight.astronomicalDawn != null)
                  TwilightRow(
                    label: 'Astro Dawn',
                    time: DateFormat('HH:mm')
                        .format(twilight.astronomicalDawn!.toLocal()),
                    isPrimary: true,
                    colors: colors,
                  ),
                if (twilight.nauticalDawn != null)
                  TwilightRow(
                    label: 'Nautical Dawn',
                    time: DateFormat('HH:mm')
                        .format(twilight.nauticalDawn!.toLocal()),
                    colors: colors,
                  ),
                if (twilight.civilDawn != null)
                  TwilightRow(
                    label: 'Civil Dawn',
                    time: DateFormat('HH:mm')
                        .format(twilight.civilDawn!.toLocal()),
                    colors: colors,
                  ),
                if (twilight.sunrise != null)
                  TwilightRow(
                    label: 'Sunrise',
                    time:
                        DateFormat('HH:mm').format(twilight.sunrise!.toLocal()),
                    colors: colors,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Moon card
          InfoCard(
            title: 'Moon',
            icon: LucideIcons.moon,
            color: colors.info,
            colors: colors,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Phase',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    Text(
                      moonInfo.phaseName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Illumination',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    Text(
                      '${moonInfo.illumination.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: moonInfo.illumination < 25
                            ? colors.success
                            : moonInfo.illumination > 75
                                ? colors.error
                                : colors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (moonInfo.moonrise != null)
                  TwilightRow(
                    label: 'Moonrise',
                    time: DateFormat('HH:mm')
                        .format(moonInfo.moonrise!.toLocal()),
                    colors: colors,
                  ),
                if (moonInfo.moonset != null)
                  TwilightRow(
                    label: 'Moonset',
                    time:
                        DateFormat('HH:mm').format(moonInfo.moonset!.toLocal()),
                    colors: colors,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Best targets tonight header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Best Targets Tonight',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Tooltip(
                message: 'Objects sorted by transit altitude (>30\u00b0)',
                child: Icon(
                  LucideIcons.helpCircle,
                  size: 14,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          bestTargets.when(
            data: (targets) {
              if (targets.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(LucideIcons.cloudOff,
                          size: 32, color: colors.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        'No targets above 30\u00b0 tonight',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textMuted,
                        ),
                      ),
                      if (isDefaultLocation) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Try setting your actual location',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                children: targets.take(5).map((item) {
                  final (dso, visibility) = item;
                  final (displayName, catalogTag) = getDsoDisplayInfo(dso);
                  return TargetCard(
                    name: displayName,
                    catalog: catalogTag,
                    type: dsoTypeName(dso.type),
                    altitude:
                        '${visibility.transitAltitude?.toStringAsFixed(0) ?? '-'}\u00b0',
                    transit: visibility.transitTime != null
                        ? DateFormat('HH:mm').format(visibility.transitTime!)
                        : '-',
                    colors: colors,
                    onTap: () {
                      ref
                          .read(selectedObjectProvider.notifier)
                          .selectObject(dso);
                      ref
                          .read(skyViewStateProvider.notifier)
                          .lookAt(dso.coordinates);
                    },
                  );
                }).toList(),
              );
            },
            loading: () => Container(
              padding: const EdgeInsets.all(24),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle, size: 16, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Error loading targets',
                      style: TextStyle(fontSize: 12, color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Satellite passes section
          _SatellitePassesSection(colors: colors),
        ],
      ),
    );
  }
}

class _SatellitePassesSection extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _SatellitePassesSection({required this.colors});

  @override
  ConsumerState<_SatellitePassesSection> createState() =>
      _SatellitePassesSectionState();
}

class _SatellitePassesSectionState
    extends ConsumerState<_SatellitePassesSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final showSatellites = ref.watch(showSatellitesProvider);
    final passState = ref.watch(passPredictionProvider);
    final upcomingPasses = ref.watch(upcomingPassesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 14,
                    color: widget.colors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Satellite Passes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (!showSatellites)
              NightshadeButton(
                onPressed: () {
                  ref.read(showSatellitesProvider.notifier).state = true;
                  ref.read(skyRenderConfigProvider.notifier).toggleSatellites();
                  ref.read(passPredictionProvider.notifier).computePasses();
                  setState(() => _isExpanded = true);
                },
                label: 'Enable',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
          ],
        ),
        if (_isExpanded && showSatellites) ...[
          const SizedBox(height: 8),
          if (passState.isComputing)
            Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (passState.error != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                passState.error!,
                style: TextStyle(fontSize: 11, color: widget.colors.error),
              ),
            )
          else if (upcomingPasses.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.border),
              ),
              child: Column(
                children: [
                  Icon(LucideIcons.satellite,
                      size: 24, color: widget.colors.textMuted),
                  const SizedBox(height: 6),
                  Text(
                    'No upcoming passes',
                    style:
                        TextStyle(fontSize: 12, color: widget.colors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      ref.read(passPredictionProvider.notifier).computePasses();
                    },
                    child: Text(
                      'Compute Passes',
                      style:
                          TextStyle(fontSize: 11, color: widget.colors.accent),
                    ),
                  ),
                ],
              ),
            )
          else
            ...upcomingPasses.take(10).map((pass) => _SatellitePassCard(
                  pass: pass,
                  colors: widget.colors,
                )),
        ] else if (_isExpanded && !showSatellites) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Text(
              'Enable satellite tracking to see pass predictions.',
              style: TextStyle(fontSize: 12, color: widget.colors.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}

class _SatellitePassCard extends StatelessWidget {
  final SatellitePass pass;
  final NightshadeColors colors;

  const _SatellitePassCard({
    required this.pass,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final isIss = pass.name.contains('ISS') || pass.name.contains('ZARYA');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pass.isBrightPass
              ? const Color(0xFFFFD740).withValues(alpha: 0.3)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isIss)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD740).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'ISS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFD740),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  isIss ? 'International Space Station' : pass.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Max ${pass.maxElevation.toStringAsFixed(0)}\u00b0',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: pass.isBrightPass
                      ? const Color(0xFFFFD740)
                      : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _PassTimeLabel(
                label: 'Rise',
                time: timeFormat.format(pass.riseTime.toLocal()),
                az: '${pass.riseAzimuth.toStringAsFixed(0)}\u00b0',
                colors: colors,
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.arrowRight, size: 10, color: colors.textMuted),
              const SizedBox(width: 8),
              _PassTimeLabel(
                label: 'Max',
                time: timeFormat.format(pass.maxElevationTime.toLocal()),
                az: '${pass.maxElevationAzimuth.toStringAsFixed(0)}\u00b0',
                colors: colors,
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.arrowRight, size: 10, color: colors.textMuted),
              const SizedBox(width: 8),
              _PassTimeLabel(
                label: 'Set',
                time: timeFormat.format(pass.setTime.toLocal()),
                az: '${pass.setAzimuth.toStringAsFixed(0)}\u00b0',
                colors: colors,
              ),
              const Spacer(),
              Text(
                '${pass.duration.inMinutes}m',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassTimeLabel extends StatelessWidget {
  final String label;
  final String time;
  final String az;
  final NightshadeColors colors;

  const _PassTimeLabel({
    required this.label,
    required this.time,
    required this.az,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9, color: colors.textMuted),
        ),
        Text(
          time,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        Text(
          az,
          style: TextStyle(fontSize: 9, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _LocationIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final bool isDefaultLocation;
  final PlanetariumObserver location;

  const _LocationIndicator({
    required this.colors,
    required this.isDefaultLocation,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDefaultLocation
            ? colors.warning.withValues(alpha: 0.1)
            : colors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDefaultLocation
              ? colors.warning.withValues(alpha: 0.3)
              : colors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.mapPin,
            size: 14,
            color: isDefaultLocation ? colors.warning : colors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDefaultLocation
                      ? 'Using default location'
                      : location.locationName ?? 'Custom Location',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDefaultLocation ? colors.warning : colors.success,
                  ),
                ),
                Text(
                  '${location.latitude.toStringAsFixed(2)}\u00b0N, ${location.longitude.abs().toStringAsFixed(2)}\u00b0${location.longitude >= 0 ? 'E' : 'W'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDefaultLocation
                        ? colors.warning.withValues(alpha: 0.8)
                        : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isDefaultLocation)
            GestureDetector(
              onTap: () {
                try {
                  context.goNamed('settings');
                } catch (e) {
                  // Router might not be available, ignore
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Set Location',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colors.warning,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
