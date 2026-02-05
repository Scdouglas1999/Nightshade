// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auto_stretch_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AutoStretchSettings _$AutoStretchSettingsFromJson(Map<String, dynamic> json) {
  return _AutoStretchSettings.fromJson(json);
}

/// @nodoc
mixin _$AutoStretchSettings {
  /// Whether auto-stretch is enabled for image display.
  bool get enabled => throw _privateConstructorUsedError;

  /// The stretch method to use.
  AutoStretchMethod get method => throw _privateConstructorUsedError;

  /// Shadow clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more shadows.
  /// Typical range: -4.0 to -1.0. Default -2.8 is standard for STF.
  double get shadowClip => throw _privateConstructorUsedError;

  /// Highlight clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more highlights.
  /// Typical range: -1.0 to 0.0. Default -0.5 protects highlights.
  double get highlightClip => throw _privateConstructorUsedError;

  /// Target median level for the stretched image (0.0 to 1.0).
  /// Higher values produce brighter midtones.
  /// Default 0.25 places the median in the lower quarter for natural appearance.
  double get targetMedian => throw _privateConstructorUsedError;

  /// Whether to link RGB channels during stretch calculation.
  /// When true, uses the same stretch parameters for all channels to preserve
  /// color balance. When false, each channel is stretched independently.
  bool get linkedChannels => throw _privateConstructorUsedError;

  /// Gamma value for gamma correction method.
  /// Only used when [method] is [AutoStretchMethod.gamma].
  /// Standard display gamma is 2.2. Lower values brighten, higher values darken.
  double get gammaValue => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AutoStretchSettingsCopyWith<AutoStretchSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AutoStretchSettingsCopyWith<$Res> {
  factory $AutoStretchSettingsCopyWith(
          AutoStretchSettings value, $Res Function(AutoStretchSettings) then) =
      _$AutoStretchSettingsCopyWithImpl<$Res, AutoStretchSettings>;
  @useResult
  $Res call(
      {bool enabled,
      AutoStretchMethod method,
      double shadowClip,
      double highlightClip,
      double targetMedian,
      bool linkedChannels,
      double gammaValue});
}

/// @nodoc
class _$AutoStretchSettingsCopyWithImpl<$Res, $Val extends AutoStretchSettings>
    implements $AutoStretchSettingsCopyWith<$Res> {
  _$AutoStretchSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabled = null,
    Object? method = null,
    Object? shadowClip = null,
    Object? highlightClip = null,
    Object? targetMedian = null,
    Object? linkedChannels = null,
    Object? gammaValue = null,
  }) {
    return _then(_value.copyWith(
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      method: null == method
          ? _value.method
          : method // ignore: cast_nullable_to_non_nullable
              as AutoStretchMethod,
      shadowClip: null == shadowClip
          ? _value.shadowClip
          : shadowClip // ignore: cast_nullable_to_non_nullable
              as double,
      highlightClip: null == highlightClip
          ? _value.highlightClip
          : highlightClip // ignore: cast_nullable_to_non_nullable
              as double,
      targetMedian: null == targetMedian
          ? _value.targetMedian
          : targetMedian // ignore: cast_nullable_to_non_nullable
              as double,
      linkedChannels: null == linkedChannels
          ? _value.linkedChannels
          : linkedChannels // ignore: cast_nullable_to_non_nullable
              as bool,
      gammaValue: null == gammaValue
          ? _value.gammaValue
          : gammaValue // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AutoStretchSettingsImplCopyWith<$Res>
    implements $AutoStretchSettingsCopyWith<$Res> {
  factory _$$AutoStretchSettingsImplCopyWith(_$AutoStretchSettingsImpl value,
          $Res Function(_$AutoStretchSettingsImpl) then) =
      __$$AutoStretchSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool enabled,
      AutoStretchMethod method,
      double shadowClip,
      double highlightClip,
      double targetMedian,
      bool linkedChannels,
      double gammaValue});
}

/// @nodoc
class __$$AutoStretchSettingsImplCopyWithImpl<$Res>
    extends _$AutoStretchSettingsCopyWithImpl<$Res, _$AutoStretchSettingsImpl>
    implements _$$AutoStretchSettingsImplCopyWith<$Res> {
  __$$AutoStretchSettingsImplCopyWithImpl(_$AutoStretchSettingsImpl _value,
      $Res Function(_$AutoStretchSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabled = null,
    Object? method = null,
    Object? shadowClip = null,
    Object? highlightClip = null,
    Object? targetMedian = null,
    Object? linkedChannels = null,
    Object? gammaValue = null,
  }) {
    return _then(_$AutoStretchSettingsImpl(
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      method: null == method
          ? _value.method
          : method // ignore: cast_nullable_to_non_nullable
              as AutoStretchMethod,
      shadowClip: null == shadowClip
          ? _value.shadowClip
          : shadowClip // ignore: cast_nullable_to_non_nullable
              as double,
      highlightClip: null == highlightClip
          ? _value.highlightClip
          : highlightClip // ignore: cast_nullable_to_non_nullable
              as double,
      targetMedian: null == targetMedian
          ? _value.targetMedian
          : targetMedian // ignore: cast_nullable_to_non_nullable
              as double,
      linkedChannels: null == linkedChannels
          ? _value.linkedChannels
          : linkedChannels // ignore: cast_nullable_to_non_nullable
              as bool,
      gammaValue: null == gammaValue
          ? _value.gammaValue
          : gammaValue // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AutoStretchSettingsImpl extends _AutoStretchSettings {
  const _$AutoStretchSettingsImpl(
      {this.enabled = false,
      this.method = AutoStretchMethod.stf,
      this.shadowClip = -2.8,
      this.highlightClip = -0.5,
      this.targetMedian = 0.25,
      this.linkedChannels = true,
      this.gammaValue = 2.2})
      : super._();

  factory _$AutoStretchSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$AutoStretchSettingsImplFromJson(json);

  /// Whether auto-stretch is enabled for image display.
  @override
  @JsonKey()
  final bool enabled;

  /// The stretch method to use.
  @override
  @JsonKey()
  final AutoStretchMethod method;

  /// Shadow clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more shadows.
  /// Typical range: -4.0 to -1.0. Default -2.8 is standard for STF.
  @override
  @JsonKey()
  final double shadowClip;

  /// Highlight clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more highlights.
  /// Typical range: -1.0 to 0.0. Default -0.5 protects highlights.
  @override
  @JsonKey()
  final double highlightClip;

  /// Target median level for the stretched image (0.0 to 1.0).
  /// Higher values produce brighter midtones.
  /// Default 0.25 places the median in the lower quarter for natural appearance.
  @override
  @JsonKey()
  final double targetMedian;

  /// Whether to link RGB channels during stretch calculation.
  /// When true, uses the same stretch parameters for all channels to preserve
  /// color balance. When false, each channel is stretched independently.
  @override
  @JsonKey()
  final bool linkedChannels;

  /// Gamma value for gamma correction method.
  /// Only used when [method] is [AutoStretchMethod.gamma].
  /// Standard display gamma is 2.2. Lower values brighten, higher values darken.
  @override
  @JsonKey()
  final double gammaValue;

  @override
  String toString() {
    return 'AutoStretchSettings(enabled: $enabled, method: $method, shadowClip: $shadowClip, highlightClip: $highlightClip, targetMedian: $targetMedian, linkedChannels: $linkedChannels, gammaValue: $gammaValue)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AutoStretchSettingsImpl &&
            (identical(other.enabled, enabled) || other.enabled == enabled) &&
            (identical(other.method, method) || other.method == method) &&
            (identical(other.shadowClip, shadowClip) ||
                other.shadowClip == shadowClip) &&
            (identical(other.highlightClip, highlightClip) ||
                other.highlightClip == highlightClip) &&
            (identical(other.targetMedian, targetMedian) ||
                other.targetMedian == targetMedian) &&
            (identical(other.linkedChannels, linkedChannels) ||
                other.linkedChannels == linkedChannels) &&
            (identical(other.gammaValue, gammaValue) ||
                other.gammaValue == gammaValue));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, enabled, method, shadowClip,
      highlightClip, targetMedian, linkedChannels, gammaValue);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AutoStretchSettingsImplCopyWith<_$AutoStretchSettingsImpl> get copyWith =>
      __$$AutoStretchSettingsImplCopyWithImpl<_$AutoStretchSettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AutoStretchSettingsImplToJson(
      this,
    );
  }
}

abstract class _AutoStretchSettings extends AutoStretchSettings {
  const factory _AutoStretchSettings(
      {final bool enabled,
      final AutoStretchMethod method,
      final double shadowClip,
      final double highlightClip,
      final double targetMedian,
      final bool linkedChannels,
      final double gammaValue}) = _$AutoStretchSettingsImpl;
  const _AutoStretchSettings._() : super._();

  factory _AutoStretchSettings.fromJson(Map<String, dynamic> json) =
      _$AutoStretchSettingsImpl.fromJson;

  @override

  /// Whether auto-stretch is enabled for image display.
  bool get enabled;
  @override

  /// The stretch method to use.
  AutoStretchMethod get method;
  @override

  /// Shadow clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more shadows.
  /// Typical range: -4.0 to -1.0. Default -2.8 is standard for STF.
  double get shadowClip;
  @override

  /// Highlight clipping parameter (in standard deviations from median).
  /// Lower (more negative) values clip more highlights.
  /// Typical range: -1.0 to 0.0. Default -0.5 protects highlights.
  double get highlightClip;
  @override

  /// Target median level for the stretched image (0.0 to 1.0).
  /// Higher values produce brighter midtones.
  /// Default 0.25 places the median in the lower quarter for natural appearance.
  double get targetMedian;
  @override

  /// Whether to link RGB channels during stretch calculation.
  /// When true, uses the same stretch parameters for all channels to preserve
  /// color balance. When false, each channel is stretched independently.
  bool get linkedChannels;
  @override

  /// Gamma value for gamma correction method.
  /// Only used when [method] is [AutoStretchMethod.gamma].
  /// Standard display gamma is 2.2. Lower values brighten, higher values darken.
  double get gammaValue;
  @override
  @JsonKey(ignore: true)
  _$$AutoStretchSettingsImplCopyWith<_$AutoStretchSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
