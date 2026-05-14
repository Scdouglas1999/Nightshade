part of '../connections_tab.dart';

class _TelescopeCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _TelescopeCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(activeProfileProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: profileAsync.when(
        data: (DbEquipmentProfile? profile) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colors.accent.withValues(alpha: 0.2),
                                colors.accent.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.accent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Icon(
                            LucideIcons.scan,
                            size: 20,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.name ?? 'No active profile',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                profile?.description ??
                                    'Select a profile to use its equipment assignments',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (profile == null)
                      Text(
                        'No profile selected. Open the Profiles tab to activate one.',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ProfileDeviceLine(
                            icon: LucideIcons.camera,
                            label: 'Camera',
                            value: profile.cameraId ?? 'Not assigned',
                            colors: colors,
                          ),
                          const SizedBox(height: 6),
                          _ProfileDeviceLine(
                            icon: LucideIcons.move3d,
                            label: 'Mount',
                            value: profile.mountId ?? 'Not assigned',
                            colors: colors,
                          ),
                          const SizedBox(height: 6),
                          _ProfileDeviceLine(
                            icon: LucideIcons.focus,
                            label: 'Focuser',
                            value: profile.focuserId ?? 'Not assigned',
                            colors: colors,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              _OpticsSummaryCard(profile: profile, colors: colors),
            ],
          );
        },
        // Shimmer placeholder keeps the connections layout in place while
        // the active profile loads instead of collapsing to a spinner.
        loading: () => Row(
          children: [
            Expanded(
              child: ShimmerLoading(
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: ShimmerLoading(
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        error: (error, stack) => Center(
          child: Text(
            'Could not load the active profile.',
            style: TextStyle(color: colors.error),
          ),
        ),
      ),
    );
  }
}

class _ProfileDeviceLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _ProfileDeviceLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _OpticsSummaryCard extends StatelessWidget {
  final DbEquipmentProfile? profile;
  final NightshadeColors colors;

  const _OpticsSummaryCard({required this.profile, required this.colors});

  @override
  Widget build(BuildContext context) {
    final focalLength = profile?.focalLength ?? 0;
    final aperture = profile?.aperture ?? 0;
    final focalRatio = profile?.focalRatio;

    String formatValue(double value, {String suffix = ''}) {
      if (value <= 0) return '--';
      return '${value.toStringAsFixed(0)}$suffix';
    }

    final ratioText = focalRatio != null && focalRatio > 0
        ? 'f/${focalRatio.toStringAsFixed(1)}'
        : '--';

    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _SpecRow(
            label: 'Focal Length',
            value: formatValue(focalLength, suffix: 'mm'),
            colors: colors,
          ),
          const SizedBox(height: 8),
          _SpecRow(
            label: 'f-ratio',
            value: ratioText,
            colors: colors,
          ),
          const SizedBox(height: 8),
          _SpecRow(
            label: 'Aperture',
            value: formatValue(aperture, suffix: 'mm'),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SpecRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
