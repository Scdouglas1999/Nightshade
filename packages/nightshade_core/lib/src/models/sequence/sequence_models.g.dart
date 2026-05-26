// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sequence_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MosaicPanelInfoImpl _$$MosaicPanelInfoImplFromJson(
        Map<String, dynamic> json) =>
    _$MosaicPanelInfoImpl(
      mosaicName: json['mosaic_name'] as String,
      panelIndex: (json['panel_index'] as num).toInt(),
      totalPanels: (json['total_panels'] as num).toInt(),
      row: (json['row'] as num).toInt(),
      column: (json['column'] as num).toInt(),
    );

Map<String, dynamic> _$$MosaicPanelInfoImplToJson(
        _$MosaicPanelInfoImpl instance) =>
    <String, dynamic>{
      'mosaic_name': instance.mosaicName,
      'panel_index': instance.panelIndex,
      'total_panels': instance.totalPanels,
      'row': instance.row,
      'column': instance.column,
    };
