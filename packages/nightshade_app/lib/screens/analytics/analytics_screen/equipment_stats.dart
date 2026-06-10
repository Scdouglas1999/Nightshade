// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _EquipmentStatsTab extends StatelessWidget {
  const _EquipmentStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Access colors to ensure theme extension is available
    NightshadeColors.of(context);

    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: ResponsiveCardGrid(
        children: [
          _EquipmentStatCard(
            title: 'Camera',
            stats: [
              _Stat(label: 'Total Exposures', value: '---'),
              _Stat(label: 'Total Integration', value: '---'),
              _Stat(label: 'Avg Temperature', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Mount',
            stats: [
              _Stat(label: 'Total Slews', value: '---'),
              _Stat(label: 'Total Tracking Time', value: '---'),
              _Stat(label: 'Meridian Flips', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Focuser',
            stats: [
              _Stat(label: 'Autofocus Runs', value: '---'),
              _Stat(label: 'Avg HFR Achieved', value: '---'),
              _Stat(label: 'Total Movements', value: '---'),
            ],
          ),
          _EquipmentStatCard(
            title: 'Guider',
            stats: [
              _Stat(label: 'Total Guide Time', value: '---'),
              _Stat(label: 'Avg RMS', value: '---'),
              _Stat(label: 'Star Lost Events', value: '---'),
            ],
          ),
        ],
      ),
    );
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        stat.label,
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary),
                      ),
                      Text(
                        stat.value,
                        style: NightshadeTypography.labelSm.copyWith(
                          color: colors.textPrimary,
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
