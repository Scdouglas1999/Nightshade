// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WeatherSettingsImpl _$$WeatherSettingsImplFromJson(
        Map<String, dynamic> json) =>
    _$WeatherSettingsImpl(
      triggerDistanceKm:
          (json['triggerDistanceKm'] as num?)?.toDouble() ?? 30.0,
      cloudDensityThreshold:
          (json['cloudDensityThreshold'] as num?)?.toDouble() ?? 60.0,
      leadTimeMinutes: (json['leadTimeMinutes'] as num?)?.toInt() ?? 15,
      weatherSafetyEnabled: json['weatherSafetyEnabled'] as bool? ?? true,
      autoParkEnabled: json['autoParkEnabled'] as bool? ?? true,
      autoResumeEnabled: json['autoResumeEnabled'] as bool? ?? false,
      preferredProvider: $enumDecodeNullable(
              _$RadarProviderTypeEnumMap, json['preferredProvider']) ??
          RadarProviderType.auto,
      refreshIntervalSeconds:
          (json['refreshIntervalSeconds'] as num?)?.toInt() ?? 300,
    );

Map<String, dynamic> _$$WeatherSettingsImplToJson(
        _$WeatherSettingsImpl instance) =>
    <String, dynamic>{
      'triggerDistanceKm': instance.triggerDistanceKm,
      'cloudDensityThreshold': instance.cloudDensityThreshold,
      'leadTimeMinutes': instance.leadTimeMinutes,
      'weatherSafetyEnabled': instance.weatherSafetyEnabled,
      'autoParkEnabled': instance.autoParkEnabled,
      'autoResumeEnabled': instance.autoResumeEnabled,
      'preferredProvider':
          _$RadarProviderTypeEnumMap[instance.preferredProvider]!,
      'refreshIntervalSeconds': instance.refreshIntervalSeconds,
    };

const _$RadarProviderTypeEnumMap = {
  RadarProviderType.auto: 'auto',
  RadarProviderType.goesSatellite: 'goesSatellite',
  RadarProviderType.noaa: 'noaa',
  RadarProviderType.rainviewer: 'rainviewer',
  RadarProviderType.openmeteo: 'openmeteo',
};
