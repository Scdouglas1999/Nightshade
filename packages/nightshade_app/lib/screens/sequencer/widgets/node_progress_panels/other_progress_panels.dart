part of '../node_progress_panels.dart';

class _SlewProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final bool isCentering;

  const _SlewProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    required this.isCentering,
  });

  @override
  Widget build(BuildContext context) {
    // Parse detail for separation info in centering
    final sepMatch = RegExp(r'(\d+\.?\d*)"?').firstMatch(detail);
    final separation = double.tryParse(sepMatch?.group(1) ?? '');

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCentering ? Icons.gps_fixed : Icons.navigation,
                size: 16,
                color: colors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCentering ? 'Centering Target' : 'Slewing to Target',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (separation != null && isCentering)
                Text(
                  '${separation.toStringAsFixed(1)}" remaining',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: colors.warning,
          ),
        ],
      ),
    );
  }
}

/// Progress panel for filter change operations
class _FilterProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;

  const _FilterProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return _ProgressPanelContainer(
      colors: colors,
      accentColor: colors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt, size: 16, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail.isNotEmpty ? detail : 'Changing Filter',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: colors.accent,
          ),
        ],
      ),
    );
  }
}

/// Default progress panel for nodes without specific visualization
class _DefaultProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;

  const _DefaultProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isError = detail.toLowerCase().startsWith('error');
    final accentColor = isError ? colors.error : colors.info;

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (isError)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.error_outline,
                        size: 14,
                        color: colors.error,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      detail,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: isError ? colors.error : colors.textPrimary,
                        fontWeight:
                            isError ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isError)
            _AnimatedProgressBar(
              colors: colors,
              progress: progressPercent / 100.0,
              color: accentColor,
            ),
        ],
      ),
    );
  }
}
