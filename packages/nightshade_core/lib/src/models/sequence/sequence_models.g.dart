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

_$AdaptiveExposureConfigImpl _$$AdaptiveExposureConfigImplFromJson(
        Map<String, dynamic> json) =>
    _$AdaptiveExposureConfigImpl(
      targetSnr: (json['target_snr'] as num?)?.toDouble() ?? 30.0,
      referenceSkyBrightnessMag:
          (json['reference_sky_brightness_mag'] as num?)?.toDouble() ?? 21.5,
      minExposureSecs: (json['min_exposure_secs'] as num?)?.toDouble() ?? 5.0,
      maxExposureSecs: (json['max_exposure_secs'] as num?)?.toDouble() ?? 600.0,
      perFilterEnabled:
          (json['per_filter_enabled'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, e as bool),
              ) ??
              const <String, bool>{},
      perFilterMinSecs:
          (json['per_filter_min_secs'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, (e as num).toDouble()),
              ) ??
              const <String, double>{},
      perFilterMaxSecs:
          (json['per_filter_max_secs'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, (e as num).toDouble()),
              ) ??
              const <String, double>{},
      enabled: json['enabled'] as bool? ?? true,
    );

Map<String, dynamic> _$$AdaptiveExposureConfigImplToJson(
        _$AdaptiveExposureConfigImpl instance) =>
    <String, dynamic>{
      'target_snr': instance.targetSnr,
      'reference_sky_brightness_mag': instance.referenceSkyBrightnessMag,
      'min_exposure_secs': instance.minExposureSecs,
      'max_exposure_secs': instance.maxExposureSecs,
      'per_filter_enabled': instance.perFilterEnabled,
      'per_filter_min_secs': instance.perFilterMinSecs,
      'per_filter_max_secs': instance.perFilterMaxSecs,
      'enabled': instance.enabled,
    };
