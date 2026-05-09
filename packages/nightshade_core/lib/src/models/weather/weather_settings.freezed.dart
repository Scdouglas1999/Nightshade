// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'weather_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WeatherSettings _$WeatherSettingsFromJson(Map<String, dynamic> json) {
  return _WeatherSettings.fromJson(json);
}

/// @nodoc
mixin _$WeatherSettings {
  /// Distance threshold for alerts in kilometers
  double get triggerDistanceKm => throw _privateConstructorUsedError;

  /// Cloud density threshold for warnings (0-100 percent)
  double get cloudDensityThreshold => throw _privateConstructorUsedError;

  /// Lead time for alerts in minutes
  int get leadTimeMinutes => throw _privateConstructorUsedError;

  /// Enable weather safety monitoring
  bool get weatherSafetyEnabled => throw _privateConstructorUsedError;

  /// Maximum safe humidity before weather safety pauses imaging
  double get maxHumidityPercent => throw _privateConstructorUsedError;

  /// Maximum safe wind speed before weather safety pauses imaging
  double get maxWindSpeedKph => throw _privateConstructorUsedError;

  /// Maximum safe cloud cover before weather safety pauses imaging
  double get maxCloudCoverPercent => throw _privateConstructorUsedError;

  /// Automatically park mount when weather threatens
  bool get autoParkEnabled => throw _privateConstructorUsedError;

  /// Automatically resume imaging when weather clears
  bool get autoResumeEnabled => throw _privateConstructorUsedError;

  /// Preferred radar data provider
  RadarProviderType get preferredProvider => throw _privateConstructorUsedError;

  /// How often to refresh radar data in seconds
  int get refreshIntervalSeconds => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WeatherSettingsCopyWith<WeatherSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WeatherSettingsCopyWith<$Res> {
  factory $WeatherSettingsCopyWith(
          WeatherSettings value, $Res Function(WeatherSettings) then) =
      _$WeatherSettingsCopyWithImpl<$Res, WeatherSettings>;
  @useResult
  $Res call(
      {double triggerDistanceKm,
      double cloudDensityThreshold,
      int leadTimeMinutes,
      bool weatherSafetyEnabled,
      double maxHumidityPercent,
      double maxWindSpeedKph,
      double maxCloudCoverPercent,
      bool autoParkEnabled,
      bool autoResumeEnabled,
      RadarProviderType preferredProvider,
      int refreshIntervalSeconds});
}

/// @nodoc
class _$WeatherSettingsCopyWithImpl<$Res, $Val extends WeatherSettings>
    implements $WeatherSettingsCopyWith<$Res> {
  _$WeatherSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? triggerDistanceKm = null,
    Object? cloudDensityThreshold = null,
    Object? leadTimeMinutes = null,
    Object? weatherSafetyEnabled = null,
    Object? maxHumidityPercent = null,
    Object? maxWindSpeedKph = null,
    Object? maxCloudCoverPercent = null,
    Object? autoParkEnabled = null,
    Object? autoResumeEnabled = null,
    Object? preferredProvider = null,
    Object? refreshIntervalSeconds = null,
  }) {
    return _then(_value.copyWith(
      triggerDistanceKm: null == triggerDistanceKm
          ? _value.triggerDistanceKm
          : triggerDistanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      cloudDensityThreshold: null == cloudDensityThreshold
          ? _value.cloudDensityThreshold
          : cloudDensityThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      leadTimeMinutes: null == leadTimeMinutes
          ? _value.leadTimeMinutes
          : leadTimeMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      weatherSafetyEnabled: null == weatherSafetyEnabled
          ? _value.weatherSafetyEnabled
          : weatherSafetyEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      maxHumidityPercent: null == maxHumidityPercent
          ? _value.maxHumidityPercent
          : maxHumidityPercent // ignore: cast_nullable_to_non_nullable
              as double,
      maxWindSpeedKph: null == maxWindSpeedKph
          ? _value.maxWindSpeedKph
          : maxWindSpeedKph // ignore: cast_nullable_to_non_nullable
              as double,
      maxCloudCoverPercent: null == maxCloudCoverPercent
          ? _value.maxCloudCoverPercent
          : maxCloudCoverPercent // ignore: cast_nullable_to_non_nullable
              as double,
      autoParkEnabled: null == autoParkEnabled
          ? _value.autoParkEnabled
          : autoParkEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      autoResumeEnabled: null == autoResumeEnabled
          ? _value.autoResumeEnabled
          : autoResumeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      preferredProvider: null == preferredProvider
          ? _value.preferredProvider
          : preferredProvider // ignore: cast_nullable_to_non_nullable
              as RadarProviderType,
      refreshIntervalSeconds: null == refreshIntervalSeconds
          ? _value.refreshIntervalSeconds
          : refreshIntervalSeconds // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WeatherSettingsImplCopyWith<$Res>
    implements $WeatherSettingsCopyWith<$Res> {
  factory _$$WeatherSettingsImplCopyWith(_$WeatherSettingsImpl value,
          $Res Function(_$WeatherSettingsImpl) then) =
      __$$WeatherSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double triggerDistanceKm,
      double cloudDensityThreshold,
      int leadTimeMinutes,
      bool weatherSafetyEnabled,
      double maxHumidityPercent,
      double maxWindSpeedKph,
      double maxCloudCoverPercent,
      bool autoParkEnabled,
      bool autoResumeEnabled,
      RadarProviderType preferredProvider,
      int refreshIntervalSeconds});
}

/// @nodoc
class __$$WeatherSettingsImplCopyWithImpl<$Res>
    extends _$WeatherSettingsCopyWithImpl<$Res, _$WeatherSettingsImpl>
    implements _$$WeatherSettingsImplCopyWith<$Res> {
  __$$WeatherSettingsImplCopyWithImpl(
      _$WeatherSettingsImpl _value, $Res Function(_$WeatherSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? triggerDistanceKm = null,
    Object? cloudDensityThreshold = null,
    Object? leadTimeMinutes = null,
    Object? weatherSafetyEnabled = null,
    Object? maxHumidityPercent = null,
    Object? maxWindSpeedKph = null,
    Object? maxCloudCoverPercent = null,
    Object? autoParkEnabled = null,
    Object? autoResumeEnabled = null,
    Object? preferredProvider = null,
    Object? refreshIntervalSeconds = null,
  }) {
    return _then(_$WeatherSettingsImpl(
      triggerDistanceKm: null == triggerDistanceKm
          ? _value.triggerDistanceKm
          : triggerDistanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      cloudDensityThreshold: null == cloudDensityThreshold
          ? _value.cloudDensityThreshold
          : cloudDensityThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      leadTimeMinutes: null == leadTimeMinutes
          ? _value.leadTimeMinutes
          : leadTimeMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      weatherSafetyEnabled: null == weatherSafetyEnabled
          ? _value.weatherSafetyEnabled
          : weatherSafetyEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      maxHumidityPercent: null == maxHumidityPercent
          ? _value.maxHumidityPercent
          : maxHumidityPercent // ignore: cast_nullable_to_non_nullable
              as double,
      maxWindSpeedKph: null == maxWindSpeedKph
          ? _value.maxWindSpeedKph
          : maxWindSpeedKph // ignore: cast_nullable_to_non_nullable
              as double,
      maxCloudCoverPercent: null == maxCloudCoverPercent
          ? _value.maxCloudCoverPercent
          : maxCloudCoverPercent // ignore: cast_nullable_to_non_nullable
              as double,
      autoParkEnabled: null == autoParkEnabled
          ? _value.autoParkEnabled
          : autoParkEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      autoResumeEnabled: null == autoResumeEnabled
          ? _value.autoResumeEnabled
          : autoResumeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      preferredProvider: null == preferredProvider
          ? _value.preferredProvider
          : preferredProvider // ignore: cast_nullable_to_non_nullable
              as RadarProviderType,
      refreshIntervalSeconds: null == refreshIntervalSeconds
          ? _value.refreshIntervalSeconds
          : refreshIntervalSeconds // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WeatherSettingsImpl implements _WeatherSettings {
  const _$WeatherSettingsImpl(
      {this.triggerDistanceKm = 30.0,
      this.cloudDensityThreshold = 60.0,
      this.leadTimeMinutes = 15,
      this.weatherSafetyEnabled = true,
      this.maxHumidityPercent = 90.0,
      this.maxWindSpeedKph = 30.0,
      this.maxCloudCoverPercent = 80.0,
      this.autoParkEnabled = true,
      this.autoResumeEnabled = false,
      this.preferredProvider = RadarProviderType.auto,
      this.refreshIntervalSeconds = 300});

  factory _$WeatherSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$WeatherSettingsImplFromJson(json);

  /// Distance threshold for alerts in kilometers
  @override
  @JsonKey()
  final double triggerDistanceKm;

  /// Cloud density threshold for warnings (0-100 percent)
  @override
  @JsonKey()
  final double cloudDensityThreshold;

  /// Lead time for alerts in minutes
  @override
  @JsonKey()
  final int leadTimeMinutes;

  /// Enable weather safety monitoring
  @override
  @JsonKey()
  final bool weatherSafetyEnabled;

  /// Maximum safe humidity before weather safety pauses imaging
  @override
  @JsonKey()
  final double maxHumidityPercent;

  /// Maximum safe wind speed before weather safety pauses imaging
  @override
  @JsonKey()
  final double maxWindSpeedKph;

  /// Maximum safe cloud cover before weather safety pauses imaging
  @override
  @JsonKey()
  final double maxCloudCoverPercent;

  /// Automatically park mount when weather threatens
  @override
  @JsonKey()
  final bool autoParkEnabled;

  /// Automatically resume imaging when weather clears
  @override
  @JsonKey()
  final bool autoResumeEnabled;

  /// Preferred radar data provider
  @override
  @JsonKey()
  final RadarProviderType preferredProvider;

  /// How often to refresh radar data in seconds
  @override
  @JsonKey()
  final int refreshIntervalSeconds;

  @override
  String toString() {
    return 'WeatherSettings(triggerDistanceKm: $triggerDistanceKm, cloudDensityThreshold: $cloudDensityThreshold, leadTimeMinutes: $leadTimeMinutes, weatherSafetyEnabled: $weatherSafetyEnabled, maxHumidityPercent: $maxHumidityPercent, maxWindSpeedKph: $maxWindSpeedKph, maxCloudCoverPercent: $maxCloudCoverPercent, autoParkEnabled: $autoParkEnabled, autoResumeEnabled: $autoResumeEnabled, preferredProvider: $preferredProvider, refreshIntervalSeconds: $refreshIntervalSeconds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WeatherSettingsImpl &&
            (identical(other.triggerDistanceKm, triggerDistanceKm) ||
                other.triggerDistanceKm == triggerDistanceKm) &&
            (identical(other.cloudDensityThreshold, cloudDensityThreshold) ||
                other.cloudDensityThreshold == cloudDensityThreshold) &&
            (identical(other.leadTimeMinutes, leadTimeMinutes) ||
                other.leadTimeMinutes == leadTimeMinutes) &&
            (identical(other.weatherSafetyEnabled, weatherSafetyEnabled) ||
                other.weatherSafetyEnabled == weatherSafetyEnabled) &&
            (identical(other.maxHumidityPercent, maxHumidityPercent) ||
                other.maxHumidityPercent == maxHumidityPercent) &&
            (identical(other.maxWindSpeedKph, maxWindSpeedKph) ||
                other.maxWindSpeedKph == maxWindSpeedKph) &&
            (identical(other.maxCloudCoverPercent, maxCloudCoverPercent) ||
                other.maxCloudCoverPercent == maxCloudCoverPercent) &&
            (identical(other.autoParkEnabled, autoParkEnabled) ||
                other.autoParkEnabled == autoParkEnabled) &&
            (identical(other.autoResumeEnabled, autoResumeEnabled) ||
                other.autoResumeEnabled == autoResumeEnabled) &&
            (identical(other.preferredProvider, preferredProvider) ||
                other.preferredProvider == preferredProvider) &&
            (identical(other.refreshIntervalSeconds, refreshIntervalSeconds) ||
                other.refreshIntervalSeconds == refreshIntervalSeconds));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      triggerDistanceKm,
      cloudDensityThreshold,
      leadTimeMinutes,
      weatherSafetyEnabled,
      maxHumidityPercent,
      maxWindSpeedKph,
      maxCloudCoverPercent,
      autoParkEnabled,
      autoResumeEnabled,
      preferredProvider,
      refreshIntervalSeconds);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WeatherSettingsImplCopyWith<_$WeatherSettingsImpl> get copyWith =>
      __$$WeatherSettingsImplCopyWithImpl<_$WeatherSettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WeatherSettingsImplToJson(
      this,
    );
  }
}

abstract class _WeatherSettings implements WeatherSettings {
  const factory _WeatherSettings(
      {final double triggerDistanceKm,
      final double cloudDensityThreshold,
      final int leadTimeMinutes,
      final bool weatherSafetyEnabled,
      final double maxHumidityPercent,
      final double maxWindSpeedKph,
      final double maxCloudCoverPercent,
      final bool autoParkEnabled,
      final bool autoResumeEnabled,
      final RadarProviderType preferredProvider,
      final int refreshIntervalSeconds}) = _$WeatherSettingsImpl;

  factory _WeatherSettings.fromJson(Map<String, dynamic> json) =
      _$WeatherSettingsImpl.fromJson;

  @override

  /// Distance threshold for alerts in kilometers
  double get triggerDistanceKm;
  @override

  /// Cloud density threshold for warnings (0-100 percent)
  double get cloudDensityThreshold;
  @override

  /// Lead time for alerts in minutes
  int get leadTimeMinutes;
  @override

  /// Enable weather safety monitoring
  bool get weatherSafetyEnabled;
  @override

  /// Maximum safe humidity before weather safety pauses imaging
  double get maxHumidityPercent;
  @override

  /// Maximum safe wind speed before weather safety pauses imaging
  double get maxWindSpeedKph;
  @override

  /// Maximum safe cloud cover before weather safety pauses imaging
  double get maxCloudCoverPercent;
  @override

  /// Automatically park mount when weather threatens
  bool get autoParkEnabled;
  @override

  /// Automatically resume imaging when weather clears
  bool get autoResumeEnabled;
  @override

  /// Preferred radar data provider
  RadarProviderType get preferredProvider;
  @override

  /// How often to refresh radar data in seconds
  int get refreshIntervalSeconds;
  @override
  @JsonKey(ignore: true)
  _$$WeatherSettingsImplCopyWith<_$WeatherSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
