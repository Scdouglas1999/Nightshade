// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

/// Metrics with no persisted backing source render this instead of a fake
/// number — the imaging pipeline does not currently track them.
const String _kNotTracked = 'Not tracked';
const String _kLoading = 'Loading…';
const String _kUnavailable = 'Unavailable';

class _EquipmentStatsTab extends ConsumerWidget {
  const _EquipmentStatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final imagesAsync = ref.watch(allDbImagesProvider);
    // autofocusCount is aggregated per-session, not per-frame. Keep its
    // loading/error state distinct from a genuine count of zero.
    final sessionsAsync = ref.watch(allSessionsProvider);

    return imagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load equipment stats',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
                    color: colors.error),
              ),
              const SizedBox(height: 12),
              NightshadeButton(
                label: 'Retry',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => ref.invalidate(allDbImagesProvider),
              ),
            ],
          ),
        ),
      ),
      data: (images) {
        final lights =
            images.where((i) => i.frameType.toLowerCase() == 'light').toList();
        // Accepted lights are the usable integration/quality population;
        // total camera exposures and temperature still cover every frame.
        final acceptedLights = lights
            .where((i) => i.frameType.toLowerCase() == 'light' && i.isAccepted)
            .toList();
        final totalExposures = images.length;
        final acceptedIntegration = acceptedLights.fold<double>(
          0,
          (sum, image) =>
              image.exposureDuration.isFinite && image.exposureDuration > 0
                  ? sum + image.exposureDuration
                  : sum,
        );
        final temps = images
            .map((i) => i.sensorTemp)
            .whereType<double>()
            .where((value) => value.isFinite);
        final hfrs = acceptedLights
            .map((i) => i.hfr)
            .whereType<double>()
            .where((value) => value.isFinite && value >= 0);
        final rmss = acceptedLights
            .map((i) => i.guidingRmsTotal)
            .whereType<double>()
            .where((value) => value.isFinite && value >= 0);
        final autofocusRuns = sessionsAsync.when(
          loading: () => _kLoading,
          error: (_, __) => _kUnavailable,
          data: (sessions) => '${sessions.fold<int>(
            0,
            (sum, session) => sum + session.autofocusCount,
          )}',
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessionsAsync.hasError) ...[
                NightshadeCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(LucideIcons.alertTriangle,
                            size: 16, color: colors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Session-based equipment totals are unavailable.',
                            style: NightshadeTypography.caption
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(allSessionsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ResponsiveCardGrid(children: [
                _EquipmentStatCard(
                  title: 'Camera',
                  stats: [
                    _Stat(label: 'Total Exposures', value: '$totalExposures'),
                    _Stat(
                      label: 'Accepted Integration',
                      value: _formatIntegration(acceptedIntegration),
                    ),
                    _Stat(
                      label: 'Avg Temperature',
                      value: _formatAvg(
                          temps, (v) => '${v.toStringAsFixed(1)} °C'),
                    ),
                  ],
                ),
                const _EquipmentStatCard(
                  title: 'Mount',
                  stats: [
                    _Stat(label: 'Total Slews', value: _kNotTracked),
                    _Stat(label: 'Total Tracking Time', value: _kNotTracked),
                    _Stat(label: 'Meridian Flips', value: _kNotTracked),
                  ],
                ),
                _EquipmentStatCard(
                  title: 'Focuser',
                  stats: [
                    _Stat(label: 'Autofocus Runs', value: autofocusRuns),
                    _Stat(
                      label: 'Avg HFR Achieved',
                      value: _formatAvg(hfrs, (v) => v.toStringAsFixed(2)),
                    ),
                    const _Stat(label: 'Total Movements', value: _kNotTracked),
                  ],
                ),
                _EquipmentStatCard(
                  title: 'Guider',
                  stats: [
                    const _Stat(label: 'Total Guide Time', value: _kNotTracked),
                    _Stat(
                      label: 'Avg RMS',
                      value:
                          _formatAvg(rmss, (v) => '${v.toStringAsFixed(2)}"'),
                    ),
                    const _Stat(label: 'Star Lost Events', value: _kNotTracked),
                  ],
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  /// Format a summed exposure time (seconds) as `Hh Mm`, or a clear empty
  /// marker when no frames have been captured yet.
  static String _formatIntegration(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return 'No data';
    final rounded = seconds.round();
    final h = rounded ~/ 3600;
    final m = (rounded % 3600) ~/ 60;
    final s = rounded % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return s > 0 ? '${m}m ${s}s' : '${m}m';
    return '${s}s';
  }

  /// Mean of the available samples via [format], or an empty marker when the
  /// backing column exists but no frame recorded a value.
  static String _formatAvg(
    Iterable<double> values,
    String Function(double) format,
  ) {
    final list = values.toList();
    if (list.isEmpty) return 'No data';
    final mean = list.reduce((a, b) => a + b) / list.length;
    return format(mean);
  }
}

class _Stat {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});
}

class _EquipmentStatCard extends StatelessWidget {
  final String title;
  final List<_Stat> stats;

  const _EquipmentStatCard({required this.title, required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: NightshadeTypography.h5.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...stats.map((stat) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          stat.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          stat.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: NightshadeTypography.labelSm.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder used while session history loads. Rendering a list of
/// card-sized shimmer rows (rather than a centred spinner) preserves the
/// final layout so the page doesn't pop when the real data arrives.
