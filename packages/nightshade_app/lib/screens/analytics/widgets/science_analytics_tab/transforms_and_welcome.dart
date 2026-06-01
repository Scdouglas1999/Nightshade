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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Photometric Transforms',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const _ScienceInfoButton(title: 'Photometric Transforms'),
              ],
            ),
            const SizedBox(height: 8),
            transformsAsync.when(
              data: (transforms) => _buildTransformContent(context, transforms),
              loading: () => SizedBox(
                height: 60,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              error: (error, _) => Text(
                'Failed to load transforms: $error',
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No transform coefficients computed yet. Use the Calibrate button '
          'to run the photometric calibration wizard on a standard star field.',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in transforms) ...[
          _TransformRow(colors: colors, transform: t),
          if (t != transforms.last) const SizedBox(height: 6),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: NightshadeDecorations.statusChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(4),
                  bordered: false,
                ),
                child: Text(
                  transform.filterName,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: NightshadeDecorations.statusChip(
                  qualityColor,
                  borderRadius: BorderRadius.circular(4),
                  bordered: false,
                ),
                child: Text(
                  quality,
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                ageLabel,
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _CoefficientChip(
                colors: colors,
                label: 'ZP',
                value: transform.zeroPoint.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'k',
                value: transform.extinctionCoefficient.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'T',
                value: transform.colorTerm.toStringAsFixed(3),
              ),
              const SizedBox(width: 6),
              _CoefficientChip(
                colors: colors,
                label: 'RMS',
                value: '${transform.rmsResidual.toStringAsFixed(3)} mag',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${transform.matchedStarCount} stars matched  |  '
            'Catalog: ${transform.catalogSource}',
            style: TextStyle(color: colors.textMuted, fontSize: 10),
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
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// First-run welcome strip that hand-walks new users through the science
/// differentiators (live photometric calibration, transparency monitoring,
/// the image grader, the markdown report, and FITS keyword writeback) the
/// first time they land on the Science tab.
///
/// Dismissal is persisted via `dismissedTourPromptsProvider`, so power users
/// only ever see this card once across all launches of the app. We keep the
/// surface intentionally compact — four bullet rows plus a "Got it" button —
/// to avoid masking the live data below.
class _ScienceWelcomeCard extends ConsumerWidget {
  static const String _screenId = 'science_welcome_v1';

  const _ScienceWelcomeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dismissedTourPromptsProvider);
    if (dismissed.contains(_screenId)) {
      return const SizedBox.shrink();
    }
    final colors = NightshadeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: NightshadeDecorations.emphasisSurface(
          colors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Welcome to Nightshade Science',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(LucideIcons.x,
                      size: 14, color: colors.textSecondary),
                  tooltip: 'Dismiss',
                  onPressed: () => ref
                      .read(dismissedTourPromptsProvider.notifier)
                      .dismissPrompt(_screenId),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _bullet(
              colors,
              LucideIcons.gauge,
              'Live photometric calibration:',
              'every plate-solved frame is matched to Gaia DR3, so you get '
                  'a zero point, limiting magnitude, and atmospheric '
                  'transparency in seconds — no external pipeline needed.',
            ),
            _bullet(
              colors,
              LucideIcons.sliders,
              'Image grader:',
              'set HFR / FWHM / star-count / RMS thresholds and reject sub-par '
                  'frames in one click. Rejections persist back to the '
                  'database so stacking tools see them.',
            ),
            _bullet(
              colors,
              LucideIcons.fileText,
              'Export report:',
              'one tap produces a markdown science report — session '
                  'summary, photometry snapshot, transparency, top issues — '
                  'ready to drop into a logbook.',
            ),
            _bullet(
              colors,
              LucideIcons.archive,
              'FITS keyword writeback:',
              'MAGZP, TRANSPAR, and friends are stamped straight into your '
                  'FITS files so PixInsight, AstroPixelProcessor, and Siril '
                  'can read Nightshade\'s measurements directly.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => ref
                    .read(dismissedTourPromptsProvider.notifier)
                    .dismissPrompt(_screenId),
                icon: const Icon(LucideIcons.check, size: 13),
                label: const Text('Got it',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(
    NightshadeColors colors,
    IconData icon,
    String lead,
    String body,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: colors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$lead ',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
