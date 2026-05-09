import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import 'settings_widgets.dart';

class WeatherSafetySettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const WeatherSafetySettings({
    super.key,
    required this.colors,
    this.isMobile = false,
  });

  @override
  ConsumerState<WeatherSafetySettings> createState() =>
      _WeatherSafetySettingsState();
}

class _WeatherSafetySettingsState extends ConsumerState<WeatherSafetySettings> {
  final _humidityController = TextEditingController();
  final _windController = TextEditingController();
  final _cloudController = TextEditingController();
  final _distanceController = TextEditingController();
  final _leadTimeController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _humidityController.dispose();
    _windController.dispose();
    _cloudController.dispose();
    _distanceController.dispose();
    _leadTimeController.dispose();
    super.dispose();
  }

  void _initControllers(WeatherSettings settings) {
    if (_initialized) {
      return;
    }
    _humidityController.text = settings.maxHumidityPercent.toStringAsFixed(0);
    _windController.text = settings.maxWindSpeedKph.toStringAsFixed(0);
    _cloudController.text = settings.maxCloudCoverPercent.toStringAsFixed(0);
    _distanceController.text = settings.triggerDistanceKm.toStringAsFixed(0);
    _leadTimeController.text = settings.leadTimeMinutes.toString();
    _initialized = true;
  }

  Future<void> _updateSettings({
    double? triggerDistanceKm,
    int? leadTimeMinutes,
    bool? weatherSafetyEnabled,
    double? maxHumidityPercent,
    double? maxWindSpeedKph,
    double? maxCloudCoverPercent,
    bool? autoParkEnabled,
    bool? autoResumeEnabled,
  }) {
    return ref.read(databaseProvider).weatherSettingsDao.updateSettings(
          triggerDistanceKm: triggerDistanceKm,
          leadTimeMinutes: leadTimeMinutes,
          weatherSafetyEnabled: weatherSafetyEnabled,
          maxHumidityPercent: maxHumidityPercent,
          maxWindSpeedKph: maxWindSpeedKph,
          maxCloudCoverPercent: maxCloudCoverPercent,
          autoParkEnabled: autoParkEnabled,
          autoResumeEnabled: autoResumeEnabled,
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(weatherSettingsProvider);
    final l10n = context.l10n;
    _initControllers(settings);

    return SettingsPage(
      title: l10n.text('weatherSafetyTitle'),
      description: l10n.text('weatherSafetyDescription'),
      colors: widget.colors,
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        SettingsSection(
          title: l10n.text('weatherSafetyActions'),
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.shield,
              title: l10n.text('weatherSafetyEnable'),
              subtitle: l10n.text('weatherSafetyEnableDesc'),
              trailing: SettingsSwitch(
                value: settings.weatherSafetyEnabled,
                onChanged: (value) =>
                    _updateSettings(weatherSafetyEnabled: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.mapPin,
              title: l10n.text('weatherSafetyAutoPark'),
              subtitle: l10n.text('weatherSafetyAutoParkDesc'),
              trailing: SettingsSwitch(
                value: settings.autoParkEnabled,
                onChanged: (value) => _updateSettings(autoParkEnabled: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.play,
              title: l10n.text('weatherSafetyAutoResume'),
              subtitle: l10n.text('weatherSafetyAutoResumeDesc'),
              trailing: SettingsSwitch(
                value: settings.autoResumeEnabled,
                onChanged: (value) => _updateSettings(autoResumeEnabled: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: l10n.text('weatherSafetyHardware'),
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.droplets,
              title: l10n.text('weatherSafetyMaxHumidity'),
              subtitle: l10n.text('weatherSafetyMaxHumidityDesc'),
              trailing: SettingsNumberInput(
                controller: _humidityController,
                suffix: '%',
                min: 0,
                max: 100,
                decimals: 0,
                onChanged: (value) =>
                    _updateSettings(maxHumidityPercent: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.wind,
              title: l10n.text('weatherSafetyMaxWind'),
              subtitle: l10n.text('weatherSafetyMaxWindDesc'),
              trailing: SettingsNumberInput(
                controller: _windController,
                suffix: 'km/h',
                min: 0,
                max: 150,
                decimals: 0,
                onChanged: (value) => _updateSettings(maxWindSpeedKph: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.cloud,
              title: l10n.text('weatherSafetyMaxCloud'),
              subtitle: l10n.text('weatherSafetyMaxCloudDesc'),
              trailing: SettingsNumberInput(
                controller: _cloudController,
                suffix: '%',
                min: 0,
                max: 100,
                decimals: 0,
                onChanged: (value) =>
                    _updateSettings(maxCloudCoverPercent: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: l10n.text('weatherSafetyAlertTiming'),
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.radar,
              title: l10n.text('weatherSafetyAlertDistance'),
              subtitle: l10n.text('weatherSafetyAlertDistanceDesc'),
              trailing: SettingsNumberInput(
                controller: _distanceController,
                suffix: 'km',
                min: 1,
                max: 500,
                decimals: 0,
                onChanged: (value) => _updateSettings(triggerDistanceKm: value),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.timerReset,
              title: l10n.text('weatherSafetyLeadTime'),
              subtitle: l10n.text('weatherSafetyLeadTimeDesc'),
              trailing: SettingsNumberInput(
                controller: _leadTimeController,
                suffix: 'min',
                min: 1,
                max: 180,
                decimals: 0,
                onChanged: (value) =>
                    _updateSettings(leadTimeMinutes: value.toInt()),
                colors: widget.colors,
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }
}
