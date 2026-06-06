part of '../period_analysis_panel.dart';

class _ResultColumn extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final String detail;

  const _ResultColumn({
    required this.colors,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BlsStat extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _BlsStat({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: NightshadeTypography.fontSize10),
        ),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
