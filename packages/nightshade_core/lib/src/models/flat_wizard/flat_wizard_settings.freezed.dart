// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flat_wizard_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

FlatWizardGlobalSettings _$FlatWizardGlobalSettingsFromJson(
    Map<String, dynamic> json) {
  return _FlatWizardGlobalSettings.fromJson(json);
}

/// @nodoc
mixin _$FlatWizardGlobalSettings {
  /// Target histogram percentage (0-100), default 50%
  double get histogramTarget => throw _privateConstructorUsedError;

  /// Tolerance as percentage of target (1-25), default 10%
  double get tolerancePercent => throw _privateConstructorUsedError;

  /// Minimum exposure in seconds
  double get minExposure => throw _privateConstructorUsedError;

  /// Maximum exposure in seconds
  double get maxExposure => throw _privateConstructorUsedError;

  /// Number of frames to capture per filter
  int get frameCount => throw _privateConstructorUsedError;

  /// Default gain for flats
  int get gain => throw _privateConstructorUsedError;

  /// Default binning for flats
  int get binning => throw _privateConstructorUsedError;

  /// Save path for flat frames
  String? get savePath => throw _privateConstructorUsedError;

  /// Create date subfolder
  bool get createDateSubfolder => throw _privateConstructorUsedError;

  /// Create filter subfolders
  bool get createFilterSubfolders =>
      throw _privateConstructorUsedError; // AUDIT-FIX-5B (audit-handoff §4.3): magic-number defaults promoted from
// hardcoded constants in flat_wizard_service.dart.
  /// Per-frame download timeout (seconds). Was hardcoded
  /// `_imageDownloadTimeout = Duration(seconds: 60)`. Increase for very
  /// large sensors or slow USB hubs.
  int get imageDownloadTimeoutSeconds => throw _privateConstructorUsedError;

  /// Max binary-search iterations for the calibration solver. Was a
  /// `int maxIterations = 8` default parameter in the service. Fewer
  /// iterations exits faster on stubborn filters but risks missing the
  /// target ADU; more iterations is slower but more accurate.
  int get maxIterations => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FlatWizardGlobalSettingsCopyWith<FlatWizardGlobalSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlatWizardGlobalSettingsCopyWith<$Res> {
  factory $FlatWizardGlobalSettingsCopyWith(FlatWizardGlobalSettings value,
          $Res Function(FlatWizardGlobalSettings) then) =
      _$FlatWizardGlobalSettingsCopyWithImpl<$Res, FlatWizardGlobalSettings>;
  @useResult
  $Res call(
      {double histogramTarget,
      double tolerancePercent,
      double minExposure,
      double maxExposure,
      int frameCount,
      int gain,
      int binning,
      String? savePath,
      bool createDateSubfolder,
      bool createFilterSubfolders,
      int imageDownloadTimeoutSeconds,
      int maxIterations});
}

/// @nodoc
class _$FlatWizardGlobalSettingsCopyWithImpl<$Res,
        $Val extends FlatWizardGlobalSettings>
    implements $FlatWizardGlobalSettingsCopyWith<$Res> {
  _$FlatWizardGlobalSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? histogramTarget = null,
    Object? tolerancePercent = null,
    Object? minExposure = null,
    Object? maxExposure = null,
    Object? frameCount = null,
    Object? gain = null,
    Object? binning = null,
    Object? savePath = freezed,
    Object? createDateSubfolder = null,
    Object? createFilterSubfolders = null,
    Object? imageDownloadTimeoutSeconds = null,
    Object? maxIterations = null,
  }) {
    return _then(_value.copyWith(
      histogramTarget: null == histogramTarget
          ? _value.histogramTarget
          : histogramTarget // ignore: cast_nullable_to_non_nullable
              as double,
      tolerancePercent: null == tolerancePercent
          ? _value.tolerancePercent
          : tolerancePercent // ignore: cast_nullable_to_non_nullable
              as double,
      minExposure: null == minExposure
          ? _value.minExposure
          : minExposure // ignore: cast_nullable_to_non_nullable
              as double,
      maxExposure: null == maxExposure
          ? _value.maxExposure
          : maxExposure // ignore: cast_nullable_to_non_nullable
              as double,
      frameCount: null == frameCount
          ? _value.frameCount
          : frameCount // ignore: cast_nullable_to_non_nullable
              as int,
      gain: null == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as int,
      savePath: freezed == savePath
          ? _value.savePath
          : savePath // ignore: cast_nullable_to_non_nullable
              as String?,
      createDateSubfolder: null == createDateSubfolder
          ? _value.createDateSubfolder
          : createDateSubfolder // ignore: cast_nullable_to_non_nullable
              as bool,
      createFilterSubfolders: null == createFilterSubfolders
          ? _value.createFilterSubfolders
          : createFilterSubfolders // ignore: cast_nullable_to_non_nullable
              as bool,
      imageDownloadTimeoutSeconds: null == imageDownloadTimeoutSeconds
          ? _value.imageDownloadTimeoutSeconds
          : imageDownloadTimeoutSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      maxIterations: null == maxIterations
          ? _value.maxIterations
          : maxIterations // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FlatWizardGlobalSettingsImplCopyWith<$Res>
    implements $FlatWizardGlobalSettingsCopyWith<$Res> {
  factory _$$FlatWizardGlobalSettingsImplCopyWith(
          _$FlatWizardGlobalSettingsImpl value,
          $Res Function(_$FlatWizardGlobalSettingsImpl) then) =
      __$$FlatWizardGlobalSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double histogramTarget,
      double tolerancePercent,
      double minExposure,
      double maxExposure,
      int frameCount,
      int gain,
      int binning,
      String? savePath,
      bool createDateSubfolder,
      bool createFilterSubfolders,
      int imageDownloadTimeoutSeconds,
      int maxIterations});
}

/// @nodoc
class __$$FlatWizardGlobalSettingsImplCopyWithImpl<$Res>
    extends _$FlatWizardGlobalSettingsCopyWithImpl<$Res,
        _$FlatWizardGlobalSettingsImpl>
    implements _$$FlatWizardGlobalSettingsImplCopyWith<$Res> {
  __$$FlatWizardGlobalSettingsImplCopyWithImpl(
      _$FlatWizardGlobalSettingsImpl _value,
      $Res Function(_$FlatWizardGlobalSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? histogramTarget = null,
    Object? tolerancePercent = null,
    Object? minExposure = null,
    Object? maxExposure = null,
    Object? frameCount = null,
    Object? gain = null,
    Object? binning = null,
    Object? savePath = freezed,
    Object? createDateSubfolder = null,
    Object? createFilterSubfolders = null,
    Object? imageDownloadTimeoutSeconds = null,
    Object? maxIterations = null,
  }) {
    return _then(_$FlatWizardGlobalSettingsImpl(
      histogramTarget: null == histogramTarget
          ? _value.histogramTarget
          : histogramTarget // ignore: cast_nullable_to_non_nullable
              as double,
      tolerancePercent: null == tolerancePercent
          ? _value.tolerancePercent
          : tolerancePercent // ignore: cast_nullable_to_non_nullable
              as double,
      minExposure: null == minExposure
          ? _value.minExposure
          : minExposure // ignore: cast_nullable_to_non_nullable
              as double,
      maxExposure: null == maxExposure
          ? _value.maxExposure
          : maxExposure // ignore: cast_nullable_to_non_nullable
              as double,
      frameCount: null == frameCount
          ? _value.frameCount
          : frameCount // ignore: cast_nullable_to_non_nullable
              as int,
      gain: null == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as int,
      savePath: freezed == savePath
          ? _value.savePath
          : savePath // ignore: cast_nullable_to_non_nullable
              as String?,
      createDateSubfolder: null == createDateSubfolder
          ? _value.createDateSubfolder
          : createDateSubfolder // ignore: cast_nullable_to_non_nullable
              as bool,
      createFilterSubfolders: null == createFilterSubfolders
          ? _value.createFilterSubfolders
          : createFilterSubfolders // ignore: cast_nullable_to_non_nullable
              as bool,
      imageDownloadTimeoutSeconds: null == imageDownloadTimeoutSeconds
          ? _value.imageDownloadTimeoutSeconds
          : imageDownloadTimeoutSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      maxIterations: null == maxIterations
          ? _value.maxIterations
          : maxIterations // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FlatWizardGlobalSettingsImpl implements _FlatWizardGlobalSettings {
  const _$FlatWizardGlobalSettingsImpl(
      {this.histogramTarget = 50.0,
      this.tolerancePercent = 10.0,
      this.minExposure = 0.001,
      this.maxExposure = 30.0,
      this.frameCount = 30,
      this.gain = 0,
      this.binning = 1,
      this.savePath,
      this.createDateSubfolder = true,
      this.createFilterSubfolders = true,
      this.imageDownloadTimeoutSeconds = 60,
      this.maxIterations = 8});

  factory _$FlatWizardGlobalSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlatWizardGlobalSettingsImplFromJson(json);

  /// Target histogram percentage (0-100), default 50%
  @override
  @JsonKey()
  final double histogramTarget;

  /// Tolerance as percentage of target (1-25), default 10%
  @override
  @JsonKey()
  final double tolerancePercent;

  /// Minimum exposure in seconds
  @override
  @JsonKey()
  final double minExposure;

  /// Maximum exposure in seconds
  @override
  @JsonKey()
  final double maxExposure;

  /// Number of frames to capture per filter
  @override
  @JsonKey()
  final int frameCount;

  /// Default gain for flats
  @override
  @JsonKey()
  final int gain;

  /// Default binning for flats
  @override
  @JsonKey()
  final int binning;

  /// Save path for flat frames
  @override
  final String? savePath;

  /// Create date subfolder
  @override
  @JsonKey()
  final bool createDateSubfolder;

  /// Create filter subfolders
  @override
  @JsonKey()
  final bool createFilterSubfolders;
// AUDIT-FIX-5B (audit-handoff §4.3): magic-number defaults promoted from
// hardcoded constants in flat_wizard_service.dart.
  /// Per-frame download timeout (seconds). Was hardcoded
  /// `_imageDownloadTimeout = Duration(seconds: 60)`. Increase for very
  /// large sensors or slow USB hubs.
  @override
  @JsonKey()
  final int imageDownloadTimeoutSeconds;

  /// Max binary-search iterations for the calibration solver. Was a
  /// `int maxIterations = 8` default parameter in the service. Fewer
  /// iterations exits faster on stubborn filters but risks missing the
  /// target ADU; more iterations is slower but more accurate.
  @override
  @JsonKey()
  final int maxIterations;

  @override
  String toString() {
    return 'FlatWizardGlobalSettings(histogramTarget: $histogramTarget, tolerancePercent: $tolerancePercent, minExposure: $minExposure, maxExposure: $maxExposure, frameCount: $frameCount, gain: $gain, binning: $binning, savePath: $savePath, createDateSubfolder: $createDateSubfolder, createFilterSubfolders: $createFilterSubfolders, imageDownloadTimeoutSeconds: $imageDownloadTimeoutSeconds, maxIterations: $maxIterations)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlatWizardGlobalSettingsImpl &&
            (identical(other.histogramTarget, histogramTarget) ||
                other.histogramTarget == histogramTarget) &&
            (identical(other.tolerancePercent, tolerancePercent) ||
                other.tolerancePercent == tolerancePercent) &&
            (identical(other.minExposure, minExposure) ||
                other.minExposure == minExposure) &&
            (identical(other.maxExposure, maxExposure) ||
                other.maxExposure == maxExposure) &&
            (identical(other.frameCount, frameCount) ||
                other.frameCount == frameCount) &&
            (identical(other.gain, gain) || other.gain == gain) &&
            (identical(other.binning, binning) || other.binning == binning) &&
            (identical(other.savePath, savePath) ||
                other.savePath == savePath) &&
            (identical(other.createDateSubfolder, createDateSubfolder) ||
                other.createDateSubfolder == createDateSubfolder) &&
            (identical(other.createFilterSubfolders, createFilterSubfolders) ||
                other.createFilterSubfolders == createFilterSubfolders) &&
            (identical(other.imageDownloadTimeoutSeconds,
                    imageDownloadTimeoutSeconds) ||
                other.imageDownloadTimeoutSeconds ==
                    imageDownloadTimeoutSeconds) &&
            (identical(other.maxIterations, maxIterations) ||
                other.maxIterations == maxIterations));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      histogramTarget,
      tolerancePercent,
      minExposure,
      maxExposure,
      frameCount,
      gain,
      binning,
      savePath,
      createDateSubfolder,
      createFilterSubfolders,
      imageDownloadTimeoutSeconds,
      maxIterations);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FlatWizardGlobalSettingsImplCopyWith<_$FlatWizardGlobalSettingsImpl>
      get copyWith => __$$FlatWizardGlobalSettingsImplCopyWithImpl<
          _$FlatWizardGlobalSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FlatWizardGlobalSettingsImplToJson(
      this,
    );
  }
}

abstract class _FlatWizardGlobalSettings implements FlatWizardGlobalSettings {
  const factory _FlatWizardGlobalSettings(
      {final double histogramTarget,
      final double tolerancePercent,
      final double minExposure,
      final double maxExposure,
      final int frameCount,
      final int gain,
      final int binning,
      final String? savePath,
      final bool createDateSubfolder,
      final bool createFilterSubfolders,
      final int imageDownloadTimeoutSeconds,
      final int maxIterations}) = _$FlatWizardGlobalSettingsImpl;

  factory _FlatWizardGlobalSettings.fromJson(Map<String, dynamic> json) =
      _$FlatWizardGlobalSettingsImpl.fromJson;

  @override

  /// Target histogram percentage (0-100), default 50%
  double get histogramTarget;
  @override

  /// Tolerance as percentage of target (1-25), default 10%
  double get tolerancePercent;
  @override

  /// Minimum exposure in seconds
  double get minExposure;
  @override

  /// Maximum exposure in seconds
  double get maxExposure;
  @override

  /// Number of frames to capture per filter
  int get frameCount;
  @override

  /// Default gain for flats
  int get gain;
  @override

  /// Default binning for flats
  int get binning;
  @override

  /// Save path for flat frames
  String? get savePath;
  @override

  /// Create date subfolder
  bool get createDateSubfolder;
  @override

  /// Create filter subfolders
  bool get createFilterSubfolders;
  @override // AUDIT-FIX-5B (audit-handoff §4.3): magic-number defaults promoted from
// hardcoded constants in flat_wizard_service.dart.
  /// Per-frame download timeout (seconds). Was hardcoded
  /// `_imageDownloadTimeout = Duration(seconds: 60)`. Increase for very
  /// large sensors or slow USB hubs.
  int get imageDownloadTimeoutSeconds;
  @override

  /// Max binary-search iterations for the calibration solver. Was a
  /// `int maxIterations = 8` default parameter in the service. Fewer
  /// iterations exits faster on stubborn filters but risks missing the
  /// target ADU; more iterations is slower but more accurate.
  int get maxIterations;
  @override
  @JsonKey(ignore: true)
  _$$FlatWizardGlobalSettingsImplCopyWith<_$FlatWizardGlobalSettingsImpl>
      get copyWith => throw _privateConstructorUsedError;
}

FlatFilterSettings _$FlatFilterSettingsFromJson(Map<String, dynamic> json) {
  return _FlatFilterSettings.fromJson(json);
}

/// @nodoc
mixin _$FlatFilterSettings {
  String get filterName => throw _privateConstructorUsedError;

  /// Filter position in wheel (0-indexed)
  int get filterPosition => throw _privateConstructorUsedError;

  /// Whether this filter is enabled for capture
  bool get enabled => throw _privateConstructorUsedError;

  /// Override histogram target (null = use global)
  double? get histogramTargetOverride => throw _privateConstructorUsedError;

  /// Override tolerance (null = use global)
  double? get toleranceOverride => throw _privateConstructorUsedError;

  /// Override min exposure (null = use global)
  double? get minExposureOverride => throw _privateConstructorUsedError;

  /// Override max exposure (null = use global)
  double? get maxExposureOverride => throw _privateConstructorUsedError;

  /// Override frame count (null = use global)
  int? get frameCountOverride => throw _privateConstructorUsedError;

  /// Suggested exposure from history (informational)
  double? get suggestedExposure => throw _privateConstructorUsedError;

  /// Current calibrated exposure (set after tuning)
  double? get calibratedExposure => throw _privateConstructorUsedError;

  /// Frames captured so far
  int get capturedCount => throw _privateConstructorUsedError;

  /// Current measured ADU
  double? get currentAdu => throw _privateConstructorUsedError;

  /// Calibration status
  FilterCalibrationStatus get status => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FlatFilterSettingsCopyWith<FlatFilterSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlatFilterSettingsCopyWith<$Res> {
  factory $FlatFilterSettingsCopyWith(
          FlatFilterSettings value, $Res Function(FlatFilterSettings) then) =
      _$FlatFilterSettingsCopyWithImpl<$Res, FlatFilterSettings>;
  @useResult
  $Res call(
      {String filterName,
      int filterPosition,
      bool enabled,
      double? histogramTargetOverride,
      double? toleranceOverride,
      double? minExposureOverride,
      double? maxExposureOverride,
      int? frameCountOverride,
      double? suggestedExposure,
      double? calibratedExposure,
      int capturedCount,
      double? currentAdu,
      FilterCalibrationStatus status});
}

/// @nodoc
class _$FlatFilterSettingsCopyWithImpl<$Res, $Val extends FlatFilterSettings>
    implements $FlatFilterSettingsCopyWith<$Res> {
  _$FlatFilterSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? filterName = null,
    Object? filterPosition = null,
    Object? enabled = null,
    Object? histogramTargetOverride = freezed,
    Object? toleranceOverride = freezed,
    Object? minExposureOverride = freezed,
    Object? maxExposureOverride = freezed,
    Object? frameCountOverride = freezed,
    Object? suggestedExposure = freezed,
    Object? calibratedExposure = freezed,
    Object? capturedCount = null,
    Object? currentAdu = freezed,
    Object? status = null,
  }) {
    return _then(_value.copyWith(
      filterName: null == filterName
          ? _value.filterName
          : filterName // ignore: cast_nullable_to_non_nullable
              as String,
      filterPosition: null == filterPosition
          ? _value.filterPosition
          : filterPosition // ignore: cast_nullable_to_non_nullable
              as int,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      histogramTargetOverride: freezed == histogramTargetOverride
          ? _value.histogramTargetOverride
          : histogramTargetOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      toleranceOverride: freezed == toleranceOverride
          ? _value.toleranceOverride
          : toleranceOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      minExposureOverride: freezed == minExposureOverride
          ? _value.minExposureOverride
          : minExposureOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      maxExposureOverride: freezed == maxExposureOverride
          ? _value.maxExposureOverride
          : maxExposureOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      frameCountOverride: freezed == frameCountOverride
          ? _value.frameCountOverride
          : frameCountOverride // ignore: cast_nullable_to_non_nullable
              as int?,
      suggestedExposure: freezed == suggestedExposure
          ? _value.suggestedExposure
          : suggestedExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      calibratedExposure: freezed == calibratedExposure
          ? _value.calibratedExposure
          : calibratedExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      capturedCount: null == capturedCount
          ? _value.capturedCount
          : capturedCount // ignore: cast_nullable_to_non_nullable
              as int,
      currentAdu: freezed == currentAdu
          ? _value.currentAdu
          : currentAdu // ignore: cast_nullable_to_non_nullable
              as double?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FilterCalibrationStatus,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FlatFilterSettingsImplCopyWith<$Res>
    implements $FlatFilterSettingsCopyWith<$Res> {
  factory _$$FlatFilterSettingsImplCopyWith(_$FlatFilterSettingsImpl value,
          $Res Function(_$FlatFilterSettingsImpl) then) =
      __$$FlatFilterSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String filterName,
      int filterPosition,
      bool enabled,
      double? histogramTargetOverride,
      double? toleranceOverride,
      double? minExposureOverride,
      double? maxExposureOverride,
      int? frameCountOverride,
      double? suggestedExposure,
      double? calibratedExposure,
      int capturedCount,
      double? currentAdu,
      FilterCalibrationStatus status});
}

/// @nodoc
class __$$FlatFilterSettingsImplCopyWithImpl<$Res>
    extends _$FlatFilterSettingsCopyWithImpl<$Res, _$FlatFilterSettingsImpl>
    implements _$$FlatFilterSettingsImplCopyWith<$Res> {
  __$$FlatFilterSettingsImplCopyWithImpl(_$FlatFilterSettingsImpl _value,
      $Res Function(_$FlatFilterSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? filterName = null,
    Object? filterPosition = null,
    Object? enabled = null,
    Object? histogramTargetOverride = freezed,
    Object? toleranceOverride = freezed,
    Object? minExposureOverride = freezed,
    Object? maxExposureOverride = freezed,
    Object? frameCountOverride = freezed,
    Object? suggestedExposure = freezed,
    Object? calibratedExposure = freezed,
    Object? capturedCount = null,
    Object? currentAdu = freezed,
    Object? status = null,
  }) {
    return _then(_$FlatFilterSettingsImpl(
      filterName: null == filterName
          ? _value.filterName
          : filterName // ignore: cast_nullable_to_non_nullable
              as String,
      filterPosition: null == filterPosition
          ? _value.filterPosition
          : filterPosition // ignore: cast_nullable_to_non_nullable
              as int,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      histogramTargetOverride: freezed == histogramTargetOverride
          ? _value.histogramTargetOverride
          : histogramTargetOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      toleranceOverride: freezed == toleranceOverride
          ? _value.toleranceOverride
          : toleranceOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      minExposureOverride: freezed == minExposureOverride
          ? _value.minExposureOverride
          : minExposureOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      maxExposureOverride: freezed == maxExposureOverride
          ? _value.maxExposureOverride
          : maxExposureOverride // ignore: cast_nullable_to_non_nullable
              as double?,
      frameCountOverride: freezed == frameCountOverride
          ? _value.frameCountOverride
          : frameCountOverride // ignore: cast_nullable_to_non_nullable
              as int?,
      suggestedExposure: freezed == suggestedExposure
          ? _value.suggestedExposure
          : suggestedExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      calibratedExposure: freezed == calibratedExposure
          ? _value.calibratedExposure
          : calibratedExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      capturedCount: null == capturedCount
          ? _value.capturedCount
          : capturedCount // ignore: cast_nullable_to_non_nullable
              as int,
      currentAdu: freezed == currentAdu
          ? _value.currentAdu
          : currentAdu // ignore: cast_nullable_to_non_nullable
              as double?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FilterCalibrationStatus,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FlatFilterSettingsImpl implements _FlatFilterSettings {
  const _$FlatFilterSettingsImpl(
      {required this.filterName,
      required this.filterPosition,
      this.enabled = true,
      this.histogramTargetOverride,
      this.toleranceOverride,
      this.minExposureOverride,
      this.maxExposureOverride,
      this.frameCountOverride,
      this.suggestedExposure,
      this.calibratedExposure,
      this.capturedCount = 0,
      this.currentAdu,
      this.status = FilterCalibrationStatus.pending});

  factory _$FlatFilterSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlatFilterSettingsImplFromJson(json);

  @override
  final String filterName;

  /// Filter position in wheel (0-indexed)
  @override
  final int filterPosition;

  /// Whether this filter is enabled for capture
  @override
  @JsonKey()
  final bool enabled;

  /// Override histogram target (null = use global)
  @override
  final double? histogramTargetOverride;

  /// Override tolerance (null = use global)
  @override
  final double? toleranceOverride;

  /// Override min exposure (null = use global)
  @override
  final double? minExposureOverride;

  /// Override max exposure (null = use global)
  @override
  final double? maxExposureOverride;

  /// Override frame count (null = use global)
  @override
  final int? frameCountOverride;

  /// Suggested exposure from history (informational)
  @override
  final double? suggestedExposure;

  /// Current calibrated exposure (set after tuning)
  @override
  final double? calibratedExposure;

  /// Frames captured so far
  @override
  @JsonKey()
  final int capturedCount;

  /// Current measured ADU
  @override
  final double? currentAdu;

  /// Calibration status
  @override
  @JsonKey()
  final FilterCalibrationStatus status;

  @override
  String toString() {
    return 'FlatFilterSettings(filterName: $filterName, filterPosition: $filterPosition, enabled: $enabled, histogramTargetOverride: $histogramTargetOverride, toleranceOverride: $toleranceOverride, minExposureOverride: $minExposureOverride, maxExposureOverride: $maxExposureOverride, frameCountOverride: $frameCountOverride, suggestedExposure: $suggestedExposure, calibratedExposure: $calibratedExposure, capturedCount: $capturedCount, currentAdu: $currentAdu, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlatFilterSettingsImpl &&
            (identical(other.filterName, filterName) ||
                other.filterName == filterName) &&
            (identical(other.filterPosition, filterPosition) ||
                other.filterPosition == filterPosition) &&
            (identical(other.enabled, enabled) || other.enabled == enabled) &&
            (identical(
                    other.histogramTargetOverride, histogramTargetOverride) ||
                other.histogramTargetOverride == histogramTargetOverride) &&
            (identical(other.toleranceOverride, toleranceOverride) ||
                other.toleranceOverride == toleranceOverride) &&
            (identical(other.minExposureOverride, minExposureOverride) ||
                other.minExposureOverride == minExposureOverride) &&
            (identical(other.maxExposureOverride, maxExposureOverride) ||
                other.maxExposureOverride == maxExposureOverride) &&
            (identical(other.frameCountOverride, frameCountOverride) ||
                other.frameCountOverride == frameCountOverride) &&
            (identical(other.suggestedExposure, suggestedExposure) ||
                other.suggestedExposure == suggestedExposure) &&
            (identical(other.calibratedExposure, calibratedExposure) ||
                other.calibratedExposure == calibratedExposure) &&
            (identical(other.capturedCount, capturedCount) ||
                other.capturedCount == capturedCount) &&
            (identical(other.currentAdu, currentAdu) ||
                other.currentAdu == currentAdu) &&
            (identical(other.status, status) || other.status == status));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      filterName,
      filterPosition,
      enabled,
      histogramTargetOverride,
      toleranceOverride,
      minExposureOverride,
      maxExposureOverride,
      frameCountOverride,
      suggestedExposure,
      calibratedExposure,
      capturedCount,
      currentAdu,
      status);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FlatFilterSettingsImplCopyWith<_$FlatFilterSettingsImpl> get copyWith =>
      __$$FlatFilterSettingsImplCopyWithImpl<_$FlatFilterSettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FlatFilterSettingsImplToJson(
      this,
    );
  }
}

abstract class _FlatFilterSettings implements FlatFilterSettings {
  const factory _FlatFilterSettings(
      {required final String filterName,
      required final int filterPosition,
      final bool enabled,
      final double? histogramTargetOverride,
      final double? toleranceOverride,
      final double? minExposureOverride,
      final double? maxExposureOverride,
      final int? frameCountOverride,
      final double? suggestedExposure,
      final double? calibratedExposure,
      final int capturedCount,
      final double? currentAdu,
      final FilterCalibrationStatus status}) = _$FlatFilterSettingsImpl;

  factory _FlatFilterSettings.fromJson(Map<String, dynamic> json) =
      _$FlatFilterSettingsImpl.fromJson;

  @override
  String get filterName;
  @override

  /// Filter position in wheel (0-indexed)
  int get filterPosition;
  @override

  /// Whether this filter is enabled for capture
  bool get enabled;
  @override

  /// Override histogram target (null = use global)
  double? get histogramTargetOverride;
  @override

  /// Override tolerance (null = use global)
  double? get toleranceOverride;
  @override

  /// Override min exposure (null = use global)
  double? get minExposureOverride;
  @override

  /// Override max exposure (null = use global)
  double? get maxExposureOverride;
  @override

  /// Override frame count (null = use global)
  int? get frameCountOverride;
  @override

  /// Suggested exposure from history (informational)
  double? get suggestedExposure;
  @override

  /// Current calibrated exposure (set after tuning)
  double? get calibratedExposure;
  @override

  /// Frames captured so far
  int get capturedCount;
  @override

  /// Current measured ADU
  double? get currentAdu;
  @override

  /// Calibration status
  FilterCalibrationStatus get status;
  @override
  @JsonKey(ignore: true)
  _$$FlatFilterSettingsImplCopyWith<_$FlatFilterSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

FlatFilterPreset _$FlatFilterPresetFromJson(Map<String, dynamic> json) {
  return _FlatFilterPreset.fromJson(json);
}

/// @nodoc
mixin _$FlatFilterPreset {
  String get name => throw _privateConstructorUsedError;
  List<String> get filterNames => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FlatFilterPresetCopyWith<FlatFilterPreset> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlatFilterPresetCopyWith<$Res> {
  factory $FlatFilterPresetCopyWith(
          FlatFilterPreset value, $Res Function(FlatFilterPreset) then) =
      _$FlatFilterPresetCopyWithImpl<$Res, FlatFilterPreset>;
  @useResult
  $Res call({String name, List<String> filterNames});
}

/// @nodoc
class _$FlatFilterPresetCopyWithImpl<$Res, $Val extends FlatFilterPreset>
    implements $FlatFilterPresetCopyWith<$Res> {
  _$FlatFilterPresetCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? filterNames = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      filterNames: null == filterNames
          ? _value.filterNames
          : filterNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FlatFilterPresetImplCopyWith<$Res>
    implements $FlatFilterPresetCopyWith<$Res> {
  factory _$$FlatFilterPresetImplCopyWith(_$FlatFilterPresetImpl value,
          $Res Function(_$FlatFilterPresetImpl) then) =
      __$$FlatFilterPresetImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, List<String> filterNames});
}

/// @nodoc
class __$$FlatFilterPresetImplCopyWithImpl<$Res>
    extends _$FlatFilterPresetCopyWithImpl<$Res, _$FlatFilterPresetImpl>
    implements _$$FlatFilterPresetImplCopyWith<$Res> {
  __$$FlatFilterPresetImplCopyWithImpl(_$FlatFilterPresetImpl _value,
      $Res Function(_$FlatFilterPresetImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? filterNames = null,
  }) {
    return _then(_$FlatFilterPresetImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      filterNames: null == filterNames
          ? _value._filterNames
          : filterNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FlatFilterPresetImpl implements _FlatFilterPreset {
  const _$FlatFilterPresetImpl(
      {required this.name, required final List<String> filterNames})
      : _filterNames = filterNames;

  factory _$FlatFilterPresetImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlatFilterPresetImplFromJson(json);

  @override
  final String name;
  final List<String> _filterNames;
  @override
  List<String> get filterNames {
    if (_filterNames is EqualUnmodifiableListView) return _filterNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_filterNames);
  }

  @override
  String toString() {
    return 'FlatFilterPreset(name: $name, filterNames: $filterNames)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlatFilterPresetImpl &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._filterNames, _filterNames));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, name, const DeepCollectionEquality().hash(_filterNames));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FlatFilterPresetImplCopyWith<_$FlatFilterPresetImpl> get copyWith =>
      __$$FlatFilterPresetImplCopyWithImpl<_$FlatFilterPresetImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FlatFilterPresetImplToJson(
      this,
    );
  }
}

abstract class _FlatFilterPreset implements FlatFilterPreset {
  const factory _FlatFilterPreset(
      {required final String name,
      required final List<String> filterNames}) = _$FlatFilterPresetImpl;

  factory _FlatFilterPreset.fromJson(Map<String, dynamic> json) =
      _$FlatFilterPresetImpl.fromJson;

  @override
  String get name;
  @override
  List<String> get filterNames;
  @override
  @JsonKey(ignore: true)
  _$$FlatFilterPresetImplCopyWith<_$FlatFilterPresetImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
