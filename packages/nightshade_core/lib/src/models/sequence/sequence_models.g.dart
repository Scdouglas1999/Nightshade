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

_$BrightnessTierPreferencesImpl _$$BrightnessTierPreferencesImplFromJson(
        Map<String, dynamic> json) =>
    _$BrightnessTierPreferencesImpl(
      faintMinScore: (json['faint_min_score'] as num?)?.toDouble() ?? 70.0,
      mediumMinScore: (json['medium_min_score'] as num?)?.toDouble() ?? 50.0,
      brightMinScore: (json['bright_min_score'] as num?)?.toDouble() ?? 30.0,
    );

Map<String, dynamic> _$$BrightnessTierPreferencesImplToJson(
        _$BrightnessTierPreferencesImpl instance) =>
    <String, dynamic>{
      'faint_min_score': instance.faintMinScore,
      'medium_min_score': instance.mediumMinScore,
      'bright_min_score': instance.brightMinScore,
    };

_$ConditionsScoreWeightsImpl _$$ConditionsScoreWeightsImplFromJson(
        Map<String, dynamic> json) =>
    _$ConditionsScoreWeightsImpl(
      transparencyWeight:
          (json['transparency_weight'] as num?)?.toDouble() ?? 0.40,
      seeingWeight: (json['seeing_weight'] as num?)?.toDouble() ?? 0.25,
      cloudWeight: (json['cloud_weight'] as num?)?.toDouble() ?? 0.25,
      windWeight: (json['wind_weight'] as num?)?.toDouble() ?? 0.10,
    );

Map<String, dynamic> _$$ConditionsScoreWeightsImplToJson(
        _$ConditionsScoreWeightsImpl instance) =>
    <String, dynamic>{
      'transparency_weight': instance.transparencyWeight,
      'seeing_weight': instance.seeingWeight,
      'cloud_weight': instance.cloudWeight,
      'wind_weight': instance.windWeight,
    };

_$ConditionsScoreImpl _$$ConditionsScoreImplFromJson(
        Map<String, dynamic> json) =>
    _$ConditionsScoreImpl(
      score: (json['score'] as num).toDouble(),
      transparencyScore: (json['transparency_score'] as num?)?.toDouble(),
      seeingScore: (json['seeing_score'] as num?)?.toDouble(),
      cloudScore: (json['cloud_score'] as num?)?.toDouble(),
      windScore: (json['wind_score'] as num?)?.toDouble(),
      weights: json['weights'] == null
          ? const ConditionsScoreWeights()
          : ConditionsScoreWeights.fromJson(
              json['weights'] as Map<String, dynamic>),
      generatedAt: const UnixSecsDateTimeConverter()
          .fromJson((json['generated_unix_secs'] as num).toInt()),
    );

Map<String, dynamic> _$$ConditionsScoreImplToJson(
        _$ConditionsScoreImpl instance) =>
    <String, dynamic>{
      'score': instance.score,
      'transparency_score': instance.transparencyScore,
      'seeing_score': instance.seeingScore,
      'cloud_score': instance.cloudScore,
      'wind_score': instance.windScore,
      'weights': instance.weights.toJson(),
      'generated_unix_secs':
          const UnixSecsDateTimeConverter().toJson(instance.generatedAt),
    };

_$AdaptiveSwapRuntimeStateImpl _$$AdaptiveSwapRuntimeStateImplFromJson(
        Map<String, dynamic> json) =>
    _$AdaptiveSwapRuntimeStateImpl(
      currentTargetId: json['current_target_id'] as String?,
      currentTier: json['current_tier'] as String?,
      lastDecisionKind: json['last_decision_kind'] as String?,
      lastDecisionReason: json['last_decision_reason'] as String?,
      lastSwapAt: const NullableUnixSecsDateTimeConverter()
          .fromJson((json['last_swap_unix_secs'] as num?)?.toInt()),
      lastSwapFromTargetId: json['last_swap_from_target_id'] as String?,
      lastSwapToTargetId: json['last_swap_to_target_id'] as String?,
      lastObservedScore: (json['last_observed_score'] as num?)?.toDouble(),
      configuredThreshold: (json['configured_threshold'] as num?)?.toDouble(),
      configuredHysteresisSecs:
          (json['configured_hysteresis_secs'] as num?)?.toDouble() ?? 180.0,
    );

Map<String, dynamic> _$$AdaptiveSwapRuntimeStateImplToJson(
        _$AdaptiveSwapRuntimeStateImpl instance) =>
    <String, dynamic>{
      'current_target_id': instance.currentTargetId,
      'current_tier': instance.currentTier,
      'last_decision_kind': instance.lastDecisionKind,
      'last_decision_reason': instance.lastDecisionReason,
      'last_swap_unix_secs':
          const NullableUnixSecsDateTimeConverter().toJson(instance.lastSwapAt),
      'last_swap_from_target_id': instance.lastSwapFromTargetId,
      'last_swap_to_target_id': instance.lastSwapToTargetId,
      'last_observed_score': instance.lastObservedScore,
      'configured_threshold': instance.configuredThreshold,
      'configured_hysteresis_secs': instance.configuredHysteresisSecs,
    };

_$AdaptiveSwapSnapshotImpl _$$AdaptiveSwapSnapshotImplFromJson(
        Map<String, dynamic> json) =>
    _$AdaptiveSwapSnapshotImpl(
      score: json['score'] == null
          ? null
          : ConditionsScore.fromJson(json['score'] as Map<String, dynamic>),
      state: json['state'] == null
          ? const AdaptiveSwapRuntimeState()
          : AdaptiveSwapRuntimeState.fromJson(
              json['state'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$AdaptiveSwapSnapshotImplToJson(
        _$AdaptiveSwapSnapshotImpl instance) =>
    <String, dynamic>{
      'score': instance.score?.toJson(),
      'state': instance.state.toJson(),
    };

_$FilterPlanImpl _$$FilterPlanImplFromJson(Map<String, dynamic> json) =>
    _$FilterPlanImpl(
      filterName: json['filter_name'] as String? ?? '',
      filterIndex: (json['filter_index'] as num?)?.toInt(),
      count: (json['count'] as num?)?.toInt() ?? 10,
      durationSecs: (json['duration_secs'] as num?)?.toDouble() ?? 60.0,
      gain: (json['gain'] as num?)?.toInt(),
      offset: (json['offset'] as num?)?.toInt(),
      binning: json['binning'] == null
          ? BinningMode.one
          : const BinningModeJsonConverter()
              .fromJson(json['binning'] as String?),
      ditherEvery: (json['dither_every'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$FilterPlanImplToJson(_$FilterPlanImpl instance) =>
    <String, dynamic>{
      'filter_name': instance.filterName,
      'filter_index': instance.filterIndex,
      'count': instance.count,
      'duration_secs': instance.durationSecs,
      'gain': instance.gain,
      'offset': instance.offset,
      'binning': const BinningModeJsonConverter().toJson(instance.binning),
      'dither_every': instance.ditherEvery,
    };

_$PhotometryQualityGatesImpl _$$PhotometryQualityGatesImplFromJson(
        Map<String, dynamic> json) =>
    _$PhotometryQualityGatesImpl(
      minSnr: (json['min_snr'] as num?)?.toDouble() ?? 50.0,
      maxFwhmArcsec: (json['max_fwhm_arcsec'] as num?)?.toDouble() ?? 5.0,
      requireAllRefsVisible: json['require_all_refs_visible'] as bool? ?? true,
      maxAirmass: (json['max_airmass'] as num?)?.toDouble() ?? 2.5,
    );

Map<String, dynamic> _$$PhotometryQualityGatesImplToJson(
        _$PhotometryQualityGatesImpl instance) =>
    <String, dynamic>{
      'min_snr': instance.minSnr,
      'max_fwhm_arcsec': instance.maxFwhmArcsec,
      'require_all_refs_visible': instance.requireAllRefsVisible,
      'max_airmass': instance.maxAirmass,
    };

_$TransparencyBackupPlanImpl _$$TransparencyBackupPlanImplFromJson(
        Map<String, dynamic> json) =>
    _$TransparencyBackupPlanImpl(
      backupFilter: json['backup_filter'] as String?,
      backupTargetId: json['backup_target_id'] as String?,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$$TransparencyBackupPlanImplToJson(
        _$TransparencyBackupPlanImpl instance) =>
    <String, dynamic>{
      'backup_filter': instance.backupFilter,
      'backup_target_id': instance.backupTargetId,
      'description': instance.description,
    };
