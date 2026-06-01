part of '../node_progress_panels.dart';

class _ProgressPanelContainer extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final Color? accentColor;

  const _ProgressPanelContainer({
    required this.colors,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? colors.info;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.emphasisSurface(
        accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Progress panel for cooling/warming operations
class _CoolingProgressPanel extends StatelessWidget {
  final NightshadeColors colors;
  final double progressPercent;
  final String detail;
  final bool isWarming;

  const _CoolingProgressPanel({
    required this.colors,
    required this.progressPercent,
    required this.detail,
    required this.isWarming,
  });

  @override
  Widget build(BuildContext context) {
    // Parse detail string: "Cooling: 15.2Â°C â†’ -10.0Â°C (85% power)"
    // or "At target: -10.3Â°C (45% power)"
    final tempMatch = RegExp(r'(-?\d+\.?\d*)Â°C').allMatches(detail);
    final powerMatch = RegExp(r'(\d+\.?\d*)% power').firstMatch(detail);

    double? currentTemp;
    double? targetTemp;
    double? power;

    if (tempMatch.isNotEmpty) {
      final temps = tempMatch
          .map((m) => double.tryParse(m.group(1) ?? ''))
          .whereType<double>()
          .toList();
      if (temps.isNotEmpty) currentTemp = temps[0];
      if (temps.length > 1) targetTemp = temps[1];
    }
    if (powerMatch != null) {
      power = double.tryParse(powerMatch.group(1) ?? '');
    }

    return _ProgressPanelContainer(
      colors: colors,
      accentColor: isWarming ? colors.warning : colors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                isWarming ? Icons.thermostat : Icons.ac_unit,
                size: 16,
                color: isWarming ? colors.warning : colors.info,
              ),
              const SizedBox(width: 8),
              Text(
                isWarming ? 'Warming Camera' : 'Cooling Camera',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Temperature display
          Row(
            children: [
              // Current temp
              _TempDisplay(
                colors: colors,
                label: 'Current',
                temp: currentTemp,
                isTarget: false,
              ),
              const SizedBox(width: 16),
              // Arrow
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: colors.textMuted,
              ),
              const SizedBox(width: 16),
              // Target temp
              _TempDisplay(
                colors: colors,
                label: 'Target',
                temp: targetTemp ?? currentTemp,
                isTarget: true,
              ),
              const Spacer(),
              // Power gauge
              if (power != null) _PowerGauge(colors: colors, power: power),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          _AnimatedProgressBar(
            colors: colors,
            progress: progressPercent / 100.0,
            color: isWarming ? colors.warning : colors.info,
          ),
        ],
      ),
    );
  }
}

class _TempDisplay extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double? temp;
  final bool isTarget;

  const _TempDisplay({
    required this.colors,
    required this.label,
    this.temp,
    required this.isTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
          ),
        ),
        Text(
          temp != null ? '${temp!.toStringAsFixed(1)}Â°C' : '--Â°C',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isTarget ? colors.info : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PowerGauge extends StatelessWidget {
  final NightshadeColors colors;
  final double power;

  const _PowerGauge({required this.colors, required this.power});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Power',
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 40,
              height: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: power / 100.0,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    power > 80
                        ? colors.error
                        : power > 50
                            ? colors.warning
                            : colors.success,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${power.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
