part of '../weather_screen.dart';

/// What the Safety Status card says, given the live verdict AND whether the
/// operator has weather safety switched on at all.
///
/// Audit 2026-07-29: the provider reports [WeatherSafetyStatus.safe] when
/// monitoring is OFF, because there is no verdict to act on. Rendering that as
/// "Conditions safe for imaging" told the operator the sky was being watched
/// when nothing was checking it, so monitoring-off has its own wording.
@visibleForTesting
String weatherSafetyStatusText({
  required WeatherSafetyStatus status,
  required bool monitoring,
  DateTime? snoozeUntil,
  DateTime? now,
}) {
  if (!monitoring) {
    return 'Not monitoring — weather safety is off, conditions are not '
        'being checked';
  }
  switch (status) {
    case WeatherSafetyStatus.safe:
      return 'Conditions safe for imaging';
    case WeatherSafetyStatus.unsafe:
      return 'Unsafe conditions detected';
    case WeatherSafetyStatus.snoozed:
      if (snoozeUntil != null) {
        final remaining = snoozeUntil.difference(now ?? DateTime.now());
        return 'Alerts snoozed for ${remaining.inMinutes} more minutes; '
            'safety unknown';
      }
      return 'Alerts snoozed';
  }
}

/// How an auto-park / auto-resume policy is reported.
///
/// A toggle that is on but cannot fire (its prerequisites are off) is neither
/// "Enabled" nor "Disabled" — say so instead of showing a green promise the rig
/// will not keep.
@visibleForTesting
String weatherPolicyArmedLabel({
  required bool armed,
  required bool toggledOn,
}) {
  if (armed) return 'Enabled';
  return toggledOn ? 'On, not armed' : 'Disabled';
}

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
    // With the master switch off nothing is evaluated, and the provider reports
    // `safe` only because it has no verdict to give. Rendering that as a green
    // "conditions safe for imaging" shield tells the operator the sky is being
    // watched when it is not, so monitoring-off gets its own neutral state.
    final monitoring = safetyState.monitoringEnabled;
    final statusColor = !monitoring
        ? colors.textMuted
        : status == WeatherSafetyStatus.safe
            ? colors.success
            : status == WeatherSafetyStatus.snoozed
                ? colors.warning
                : colors.error;

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: _weatherCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: NightshadeDecorations.tintedBadge(
                  statusColor,
                  borderRadius: NightshadeTokens.borderRadiusInline8,
                ),
                child: Icon(
                  !monitoring
                      ? NightshadeIcons.shieldOff
                      : isSafe
                          ? NightshadeIcons.shieldOk
                          : NightshadeIcons.shieldAlert,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety Status',
                      style: NightshadeTypography.h5
                          .copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      weatherSafetyStatusText(
                        status: status,
                        monitoring: monitoring,
                        snoozeUntil: snoozeUntil,
                      ),
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
}

/// Weather settings quick access card
class _WeatherSettingsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _WeatherSettingsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherSettingsProvider);
    // The auto-park / auto-resume toggles are only half of the truth: each also
    // needs the weather-safety master switch (and auto-park needs the Sequencer
    // "Park on unsafe weather" policy). Report the composed, armed value so this
    // panel cannot promise protection the rig does not have.
    final safetyState = ref.watch(weatherSafetyProvider);
    final monitoring = safetyState.monitoringEnabled;

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: _weatherCardPadding(context),
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
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingRow(
            label: 'Weather Safety',
            value: monitoring ? 'Monitoring' : 'Off — not monitoring',
            colors: colors,
            valueColor: monitoring ? colors.success : colors.warning,
          ),
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
            value: weatherPolicyArmedLabel(
              armed: safetyState.autoParkArmed,
              toggledOn: settings.autoParkEnabled,
            ),
            colors: colors,
            valueColor: _armedColor(
              colors,
              armed: safetyState.autoParkArmed,
              toggledOn: settings.autoParkEnabled,
            ),
          ),
          _SettingRow(
            label: 'Auto-Resume',
            value: weatherPolicyArmedLabel(
              armed: safetyState.autoResumeArmed,
              toggledOn: settings.autoResumeEnabled,
            ),
            colors: colors,
            valueColor: _armedColor(
              colors,
              armed: safetyState.autoResumeArmed,
              toggledOn: settings.autoResumeEnabled,
            ),
            isLast: true,
          ),
          if (!monitoring) ...[
            const SizedBox(height: 12),
            Text(
              'Weather safety is switched off, so none of the above is in '
              'effect. Turn it on in Settings → Automation & Safety → Weather '
              'Safety.',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
          ] else if (settings.autoParkEnabled &&
              !safetyState.autoParkArmed) ...[
            const SizedBox(height: 12),
            Text(
              'Auto-park also needs Settings → Automation & Safety → Sequencer '
              '→ "Park on unsafe weather", which is currently off.',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.warning),
            ),
          ],
        ],
      ),
    );
  }

  static Color _armedColor(
    NightshadeColors colors, {
    required bool armed,
    required bool toggledOn,
  }) {
    if (armed) return colors.success;
    return toggledOn ? colors.warning : colors.textMuted;
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
              style: NightshadeTypography.labelSm
                  .copyWith(color: valueColor ?? colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
