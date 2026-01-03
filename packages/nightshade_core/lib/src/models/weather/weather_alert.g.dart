// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_alert.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WeatherAlertImpl _$$WeatherAlertImplFromJson(Map<String, dynamic> json) =>
    _$WeatherAlertImpl(
      level: $enumDecode(_$AlertLevelEnumMap, json['level']),
      message: json['message'] as String,
      eta: json['eta'] == null ? null : DateTime.parse(json['eta'] as String),
      cloudDensityPercent: (json['cloudDensityPercent'] as num).toDouble(),
      distanceKm: (json['distanceKm'] as num).toDouble(),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
    );

Map<String, dynamic> _$$WeatherAlertImplToJson(_$WeatherAlertImpl instance) =>
    <String, dynamic>{
      'level': _$AlertLevelEnumMap[instance.level]!,
      'message': instance.message,
      'eta': instance.eta?.toIso8601String(),
      'cloudDensityPercent': instance.cloudDensityPercent,
      'distanceKm': instance.distanceKm,
      'generatedAt': instance.generatedAt.toIso8601String(),
    };

const _$AlertLevelEnumMap = {
  AlertLevel.clear: 'clear',
  AlertLevel.watch: 'watch',
  AlertLevel.warning: 'warning',
  AlertLevel.critical: 'critical',
};
