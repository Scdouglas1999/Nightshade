// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radar_frame.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RadarFrameImpl _$$RadarFrameImplFromJson(Map<String, dynamic> json) =>
    _$RadarFrameImpl(
      timestamp: DateTime.parse(json['timestamp'] as String),
      tileUrlTemplate: json['tileUrlTemplate'] as String,
      north: (json['north'] as num).toDouble(),
      south: (json['south'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isForecast: json['isForecast'] as bool? ?? false,
      tileType: $enumDecodeNullable(_$RadarTileTypeEnumMap, json['tileType']) ??
          RadarTileType.xyz,
      wmsLayers: json['wmsLayers'] as String?,
      wmsAdditionalOptions:
          (json['wmsAdditionalOptions'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$$RadarFrameImplToJson(_$RadarFrameImpl instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp.toIso8601String(),
      'tileUrlTemplate': instance.tileUrlTemplate,
      'north': instance.north,
      'south': instance.south,
      'east': instance.east,
      'west': instance.west,
      'opacity': instance.opacity,
      'isForecast': instance.isForecast,
      'tileType': _$RadarTileTypeEnumMap[instance.tileType]!,
      'wmsLayers': instance.wmsLayers,
      'wmsAdditionalOptions': instance.wmsAdditionalOptions,
    };

const _$RadarTileTypeEnumMap = {
  RadarTileType.xyz: 'xyz',
  RadarTileType.wms: 'wms',
};
