import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Read-only weather/safety snapshot for the Run dashboard.
///
/// Surfaces the same `weatherSafetyProvider` state already evaluated by the
/// sequencer's safety subsystem — never re-evaluates conditions on its own.
class RunDashboardWeatherSafetyCard extends ConsumerWidget {
  const RunDashboardWeatherSafetyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final safety = ref.watch(weatherSafetyProvider);

    final (statusText, statusColor, statusIcon) = switch (safety.status) {
      WeatherSafetyStatus.safe => ('Safe', colors.success, LucideIcons.check),
      WeatherSafetyStatus.unsafe => (
          'Unsafe',
          colors.error,
          LucideIcons.alertTriangle
        ),
      WeatherSafetyStatus.snoozed => (
          'Snoozed',
          colors.warning,
          LucideIcons.bellOff
        ),
    };

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shield, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  'SAFETY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              // Use Flexible around the pill so a narrow column doesn't
              // overflow when the status label is long ("Snoozed" + icon
              // pushes past the cell width on a 280px viewport).
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusXs),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                            letterSpacing: 0.4,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _SourceRow(
            colors: colors,
            label: 'Data',
            value: _sourceLabel(safety.dataSource),
          ),
          if (safety.failModeWarning != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Container(
              padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusXs),
                border: Border.all(
                    color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 12, color: colors.warning),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      safety.failModeWarning!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (safety.actions.reason != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              safety.actions.reason!,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (safety.snoozeUntil != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            _SourceRow(
              colors: colors,
              label: 'Snooze until',
              value: safety.snoozeUntil!.toLocal().toString().substring(11, 19),
            ),
          ],
        ],
      ),
    );
  }

  String _sourceLabel(SafetyDataSource src) {
    switch (src) {
      case SafetyDataSource.weatherApi:
        return 'Weather API';
      case SafetyDataSource.hardwareWeather:
        return 'Hardware sensor';
      case SafetyDataSource.safetyMonitor:
        return 'Safety monitor';
      case SafetyDataSource.combined:
        return 'Combined';
      case SafetyDataSource.unavailable:
        return 'Unavailable';
    }
  }
}

class _SourceRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _SourceRow({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
