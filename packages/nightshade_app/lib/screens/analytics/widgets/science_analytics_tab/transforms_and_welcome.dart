part of '../science_analytics_tab.dart';

// =============================================================================
// Photometric Transforms Card
// =============================================================================

class _PhotometricTransformsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _PhotometricTransformsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transformsAsync = ref.watch(activeProfileTransformsProvider);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Photometric Transforms',
                    style: NightshadeTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const _ScienceInfoButton(title: 'Photometric Transforms'),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            transformsAsync.when(
              data: (transforms) => _buildTransformContent(context, transforms),
              loading: () => SizedBox(
                height: 60,
                child: Center(
                  child: SizedBox(
                    width: NightshadeTokens.iconMd,
                    height: NightshadeTokens.iconMd,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              error: (error, _) => Text(
                'Failed to load transforms: $error',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.error,
                ),
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: () => _openCalibrationWizard(context),
                icon: LucideIcons.beaker,
                label: 'Calibrate',
                variant: ButtonVariant.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransformContent(
      BuildContext context, List<PhotometricTransformRow> transforms) {
    if (transforms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceSm),
        child: Text(
          'No transform coefficients computed yet. Use the Calibrate button '
          'to run the photometric calibration wizard on a standard star field.',
          style: NightshadeTypography.caption.copyWith(
            color: colors.textMuted,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in transforms) ...[
          _TransformRow(colors: colors, transform: t),
          if (t != transforms.last)
            const SizedBox(height: NightshadeTokens.spaceXs + 2),
        ],
      ],
    );
  }

  void _openCalibrationWizard(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PhotometricCalibrationWizard(),
    );
  }
}

class _TransformRow extends StatelessWidget {
  final NightshadeColors colors;
  final PhotometricTransformRow transform;

  const _TransformRow({
    required this.colors,
    required this.transform,
  });

  @override
  Widget build(BuildContext context) {
    final quality = _qualityLabel(transform.rmsResidual);
    final qualityColor = _qualityColor(transform.rmsResidual, colors);
    final age = DateTime.now().difference(transform.dateComputed);
    final ageLabel = age.inDays == 0
        ? 'Today'
        : age.inDays == 1
            ? '1 day ago'
            : '${age.inDays} days ago';

    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NightshadeTokens.spaceXs + 2,
                  vertical: 2,
                ),
                decoration: NightshadeDecorations.statusChip(
                  colors.primary,
                  borderRadius: NightshadeTokens.borderRadiusSm,
                  bordered: false,
                ),
                child: Text(
                  transform.filterName,
                  style: NightshadeTypography.labelStrongSm.copyWith(
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NightshadeTokens.spaceXs + 2,
                  vertical: 2,
                ),
                decoration: NightshadeDecorations.statusChip(
                  qualityColor,
                  borderRadius: NightshadeTokens.borderRadiusSm,
                  bordered: false,
                ),
                child: Text(
                  quality,
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: NightshadeTypography.fontSize10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                ageLabel,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: NightshadeTypography.fontSize10,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs + 2),
          Row(
            children: [
              _CoefficientChip(
                colors: colors,
                label: 'ZP',
                value: transform.zeroPoint.toStringAsFixed(3),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs + 2),
              _CoefficientChip(
                colors: colors,
                label: 'k',
                value: transform.extinctionCoefficient.toStringAsFixed(3),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs + 2),
              _CoefficientChip(
                colors: colors,
                label: 'T',
                value: transform.colorTerm.toStringAsFixed(3),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs + 2),
              _CoefficientChip(
                colors: colors,
                label: 'RMS',
                value: '${transform.rmsResidual.toStringAsFixed(3)} mag',
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            '${transform.matchedStarCount} stars matched  |  '
            'Catalog: ${transform.catalogSource}',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize10,
            ),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(double rms) {
    if (rms <= 0.03) return 'Excellent';
    if (rms <= 0.05) return 'Good';
    if (rms <= 0.10) return 'Acceptable';
    return 'Poor';
  }

  Color _qualityColor(double rms, NightshadeColors colors) {
    if (rms <= 0.03) return colors.success;
    if (rms <= 0.05) return colors.info;
    if (rms <= 0.10) return colors.warning;
    return colors.error;
  }
}

class _CoefficientChip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _CoefficientChip({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: NightshadeTypography.labelQuiet.copyWith(
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
