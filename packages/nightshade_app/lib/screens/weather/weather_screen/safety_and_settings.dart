part of '../weather_screen.dart';

/// Weather safety status card with snooze controls
class _WeatherSafetyCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _WeatherSafetyCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyState = ref.watch(weatherSafetyProvider);
    final isSafe = safetyState.isSafe;
    final status = safetyState.status;
    final snoozeUntil = safetyState.snoozeUntil;

    return Container(
      padding: _weatherCardPadding(context),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusInline8,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: NightshadeDecorations.tintedBadge(
                  isSafe ? colors.success : colors.error,
                  borderRadius: NightshadeTokens.borderRadiusInline8,
                ),
                child: Icon(
                  isSafe ? NightshadeIcons.shieldOk : NightshadeIcons.shieldAlert,
                  size: 16,
                  color: isSafe ? colors.success : colors.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety Status',
                      style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      _getStatusText(status, snoozeUntil),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status == WeatherSafetyStatus.unsafe ||
              status == WeatherSafetyStatus.snoozed) ...[
            const SizedBox(height: 16),
            if (status == WeatherSafetyStatus.snoozed)
              NightshadeButton(
                label: 'Cancel Snooze',
                icon: NightshadeIcons.notificationsOff,
                variant: ButtonVariant.outline,
                onPressed: () {
                  ref.read(weatherSafetyProvider.notifier).cancelSnooze();
                },
              )
            else
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: 'Snooze 15m',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        ref
                            .read(weatherSafetyProvider.notifier)
                            .snooze(const Duration(minutes: 15));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Snooze 30m',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        ref
                            .read(weatherSafetyProvider.notifier)
                            .snooze(const Duration(minutes: 30));
                      },
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  String _getStatusText(WeatherSafetyStatus status, DateTime? snoozeUntil) {
    switch (status) {
      case WeatherSafetyStatus.safe:
        return 'Conditions safe for imaging';
      case WeatherSafetyStatus.unsafe:
        return 'Unsafe conditions detected';
      case WeatherSafetyStatus.snoozed:
        if (snoozeUntil != null) {
          final remaining = snoozeUntil.difference(DateTime.now());
          final minutes = remaining.inMinutes;
          return 'Snoozed for $minutes more minutes';
        }
        return 'Alerts snoozed';
    }
  }
}

/// Weather settings quick access card
class _WeatherSettingsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _WeatherSettingsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherSettingsProvider);

    return Container(
      padding: _weatherCardPadding(context),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusInline8,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius: NightshadeTokens.borderRadiusInline8,
                ),
                child: Icon(
                  NightshadeIcons.sliders,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Current Settings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingRow(
            key: WeatherTutorialKeys.alertRadius,
            label: 'Alert Radius',
            value: '${settings.triggerDistanceKm.toInt()} km',
            colors: colors,
          ),
          _SettingRow(
            label: 'Density Threshold',
            value: '${settings.cloudDensityThreshold.toInt()}%',
            colors: colors,
          ),
          _SettingRow(
            label: 'Lead Time',
            value: '${settings.leadTimeMinutes} min',
            colors: colors,
          ),
          _SettingRow(
            label: 'Auto-Park',
            value: settings.autoParkEnabled ? 'Enabled' : 'Disabled',
            colors: colors,
            valueColor:
                settings.autoParkEnabled ? colors.success : colors.textMuted,
          ),
          _SettingRow(
            label: 'Auto-Resume',
            value: settings.autoResumeEnabled ? 'Enabled' : 'Disabled',
            colors: colors,
            valueColor:
                settings.autoResumeEnabled ? colors.success : colors.textMuted,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

/// Single setting row display
class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;
  final bool isLast;

  const _SettingRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: NightshadeTypography.labelSm.copyWith(color: valueColor ?? colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
