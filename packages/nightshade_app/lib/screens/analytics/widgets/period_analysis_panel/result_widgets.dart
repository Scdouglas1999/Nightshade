part of '../period_analysis_panel.dart';

class _ResultColumn extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final String detail;
  final _Verdict? verdict;

  const _ResultColumn({
    required this.colors,
    required this.label,
    required this.value,
    required this.detail,
    this.verdict,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize10,
            ),
            textAlign: TextAlign.center,
          ),
          if (verdict != null) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            _VerdictChip(colors: colors, verdict: verdict!),
          ],
        ],
      ),
    );
  }
}

enum _Verdict { significant, strong, noteworthy }

class _VerdictChip extends StatelessWidget {
  final NightshadeColors colors;
  final _Verdict verdict;

  const _VerdictChip({required this.colors, required this.verdict});

  @override
  Widget build(BuildContext context) {
    final (label, color, filled) = switch (verdict) {
      _Verdict.strong => ('Strong', colors.success, true),
      _Verdict.significant => ('Significant', colors.success, false),
      _Verdict.noteworthy => ('Noteworthy', colors.warning, false),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 2,
      ),
      decoration: filled
          ? BoxDecoration(
              color: color,
              borderRadius: NightshadeTokens.borderRadiusLg,
            )
          : NightshadeDecorations.statusChip(
              color,
              borderRadius: NightshadeTokens.borderRadiusLg,
            ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? colors.surface : color,
          fontSize: NightshadeTypography.fontSize10,
          fontWeight: FontWeight.w600,
        ),
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
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize10),
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
