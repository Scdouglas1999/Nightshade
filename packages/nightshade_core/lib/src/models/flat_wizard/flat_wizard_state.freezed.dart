// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flat_wizard_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AduMeasurement _$AduMeasurementFromJson(Map<String, dynamic> json) {
  return _AduMeasurement.fromJson(json);
}

/// @nodoc
mixin _$AduMeasurement {
  double get exposure => throw _privateConstructorUsedError;
  double get adu => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AduMeasurementCopyWith<AduMeasurement> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AduMeasurementCopyWith<$Res> {
  factory $AduMeasurementCopyWith(
          AduMeasurement value, $Res Function(AduMeasurement) then) =
      _$AduMeasurementCopyWithImpl<$Res, AduMeasurement>;
  @useResult
  $Res call({double exposure, double adu, DateTime timestamp});
}

/// @nodoc
class _$AduMeasurementCopyWithImpl<$Res, $Val extends AduMeasurement>
    implements $AduMeasurementCopyWith<$Res> {
  _$AduMeasurementCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exposure = null,
    Object? adu = null,
    Object? timestamp = null,
  }) {
    return _then(_value.copyWith(
      exposure: null == exposure
          ? _value.exposure
          : exposure // ignore: cast_nullable_to_non_nullable
              as double,
      adu: null == adu
          ? _value.adu
          : adu // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AduMeasurementImplCopyWith<$Res>
    implements $AduMeasurementCopyWith<$Res> {
  factory _$$AduMeasurementImplCopyWith(_$AduMeasurementImpl value,
          $Res Function(_$AduMeasurementImpl) then) =
      __$$AduMeasurementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double exposure, double adu, DateTime timestamp});
}

/// @nodoc
class __$$AduMeasurementImplCopyWithImpl<$Res>
    extends _$AduMeasurementCopyWithImpl<$Res, _$AduMeasurementImpl>
    implements _$$AduMeasurementImplCopyWith<$Res> {
  __$$AduMeasurementImplCopyWithImpl(
      _$AduMeasurementImpl _value, $Res Function(_$AduMeasurementImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exposure = null,
    Object? adu = null,
    Object? timestamp = null,
  }) {
    return _then(_$AduMeasurementImpl(
      exposure: null == exposure
          ? _value.exposure
          : exposure // ignore: cast_nullable_to_non_nullable
              as double,
      adu: null == adu
          ? _value.adu
          : adu // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AduMeasurementImpl implements _AduMeasurement {
  const _$AduMeasurementImpl(
      {required this.exposure, required this.adu, required this.timestamp});

  factory _$AduMeasurementImpl.fromJson(Map<String, dynamic> json) =>
      _$$AduMeasurementImplFromJson(json);

  @override
  final double exposure;
  @override
  final double adu;
  @override
  final DateTime timestamp;

  @override
  String toString() {
    return 'AduMeasurement(exposure: $exposure, adu: $adu, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AduMeasurementImpl &&
            (identical(other.exposure, exposure) ||
                other.exposure == exposure) &&
            (identical(other.adu, adu) || other.adu == adu) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, exposure, adu, timestamp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AduMeasurementImplCopyWith<_$AduMeasurementImpl> get copyWith =>
      __$$AduMeasurementImplCopyWithImpl<_$AduMeasurementImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AduMeasurementImplToJson(
      this,
    );
  }
}

abstract class _AduMeasurement implements AduMeasurement {
  const factory _AduMeasurement(
      {required final double exposure,
      required final double adu,
      required final DateTime timestamp}) = _$AduMeasurementImpl;

  factory _AduMeasurement.fromJson(Map<String, dynamic> json) =
      _$AduMeasurementImpl.fromJson;

  @override
  double get exposure;
  @override
  double get adu;
  @override
  DateTime get timestamp;
  @override
  @JsonKey(ignore: true)
  _$$AduMeasurementImplCopyWith<_$AduMeasurementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SkyBrightnessMeasurement _$SkyBrightnessMeasurementFromJson(
    Map<String, dynamic> json) {
  return _SkyBrightnessMeasurement.fromJson(json);
}

/// @nodoc
mixin _$SkyBrightnessMeasurement {
  double get adu => throw _privateConstructorUsedError;
  double get exposureUsed => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SkyBrightnessMeasurementCopyWith<SkyBrightnessMeasurement> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SkyBrightnessMeasurementCopyWith<$Res> {
  factory $SkyBrightnessMeasurementCopyWith(SkyBrightnessMeasurement value,
          $Res Function(SkyBrightnessMeasurement) then) =
      _$SkyBrightnessMeasurementCopyWithImpl<$Res, SkyBrightnessMeasurement>;
  @useResult
  $Res call({double adu, double exposureUsed, DateTime timestamp});
}

/// @nodoc
class _$SkyBrightnessMeasurementCopyWithImpl<$Res,
        $Val extends SkyBrightnessMeasurement>
    implements $SkyBrightnessMeasurementCopyWith<$Res> {
  _$SkyBrightnessMeasurementCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? adu = null,
    Object? exposureUsed = null,
    Object? timestamp = null,
  }) {
    return _then(_value.copyWith(
      adu: null == adu
          ? _value.adu
          : adu // ignore: cast_nullable_to_non_nullable
              as double,
      exposureUsed: null == exposureUsed
          ? _value.exposureUsed
          : exposureUsed // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SkyBrightnessMeasurementImplCopyWith<$Res>
    implements $SkyBrightnessMeasurementCopyWith<$Res> {
  factory _$$SkyBrightnessMeasurementImplCopyWith(
          _$SkyBrightnessMeasurementImpl value,
          $Res Function(_$SkyBrightnessMeasurementImpl) then) =
      __$$SkyBrightnessMeasurementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double adu, double exposureUsed, DateTime timestamp});
}

/// @nodoc
class __$$SkyBrightnessMeasurementImplCopyWithImpl<$Res>
    extends _$SkyBrightnessMeasurementCopyWithImpl<$Res,
        _$SkyBrightnessMeasurementImpl>
    implements _$$SkyBrightnessMeasurementImplCopyWith<$Res> {
  __$$SkyBrightnessMeasurementImplCopyWithImpl(
      _$SkyBrightnessMeasurementImpl _value,
      $Res Function(_$SkyBrightnessMeasurementImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? adu = null,
    Object? exposureUsed = null,
    Object? timestamp = null,
  }) {
    return _then(_$SkyBrightnessMeasurementImpl(
      adu: null == adu
          ? _value.adu
          : adu // ignore: cast_nullable_to_non_nullable
              as double,
      exposureUsed: null == exposureUsed
          ? _value.exposureUsed
          : exposureUsed // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SkyBrightnessMeasurementImpl implements _SkyBrightnessMeasurement {
  const _$SkyBrightnessMeasurementImpl(
      {required this.adu, required this.exposureUsed, required this.timestamp});

  factory _$SkyBrightnessMeasurementImpl.fromJson(Map<String, dynamic> json) =>
      _$$SkyBrightnessMeasurementImplFromJson(json);

  @override
  final double adu;
  @override
  final double exposureUsed;
  @override
  final DateTime timestamp;

  @override
  String toString() {
    return 'SkyBrightnessMeasurement(adu: $adu, exposureUsed: $exposureUsed, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SkyBrightnessMeasurementImpl &&
            (identical(other.adu, adu) || other.adu == adu) &&
            (identical(other.exposureUsed, exposureUsed) ||
                other.exposureUsed == exposureUsed) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, adu, exposureUsed, timestamp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SkyBrightnessMeasurementImplCopyWith<_$SkyBrightnessMeasurementImpl>
      get copyWith => __$$SkyBrightnessMeasurementImplCopyWithImpl<
          _$SkyBrightnessMeasurementImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SkyBrightnessMeasurementImplToJson(
      this,
    );
  }
}

abstract class _SkyBrightnessMeasurement implements SkyBrightnessMeasurement {
  const factory _SkyBrightnessMeasurement(
      {required final double adu,
      required final double exposureUsed,
      required final DateTime timestamp}) = _$SkyBrightnessMeasurementImpl;

  factory _SkyBrightnessMeasurement.fromJson(Map<String, dynamic> json) =
      _$SkyBrightnessMeasurementImpl.fromJson;

  @override
  double get adu;
  @override
  double get exposureUsed;
  @override
  DateTime get timestamp;
  @override
  @JsonKey(ignore: true)
  _$$SkyBrightnessMeasurementImplCopyWith<_$SkyBrightnessMeasurementImpl>
      get copyWith => throw _privateConstructorUsedError;
}

FlatWizardState _$FlatWizardStateFromJson(Map<String, dynamic> json) {
  return _FlatWizardState.fromJson(json);
}

/// @nodoc
mixin _$FlatWizardState {
  /// Current operating mode
  FlatWizardMode get mode => throw _privateConstructorUsedError;

  /// Global settings
  FlatWizardGlobalSettings get globalSettings =>
      throw _privateConstructorUsedError;

  /// Per-filter settings
  List<FlatFilterSettings> get filterSettings =>
      throw _privateConstructorUsedError;

  /// Saved filter presets
  List<FlatFilterPreset> get filterPresets =>
      throw _privateConstructorUsedError;

  /// Current filter index being processed
  int get currentFilterIndex => throw _privateConstructorUsedError;

  /// Current frame index for active filter
  int get currentFrameIndex => throw _privateConstructorUsedError;

  /// Is capture/calibration in progress
  bool get isCapturing => throw _privateConstructorUsedError;

  /// Is currently exposing (for countdown)
  bool get isExposing => throw _privateConstructorUsedError;

  /// Current exposure start time (for countdown)
  DateTime? get exposureStartTime => throw _privateConstructorUsedError;

  /// Current exposure duration (for countdown)
  double? get currentExposureDuration => throw _privateConstructorUsedError;

  /// ADU measurements for convergence graph
  List<AduMeasurement> get aduHistory => throw _privateConstructorUsedError;

  /// Sky brightness measurements for rate tracking
  List<SkyBrightnessMeasurement> get skyBrightnessHistory =>
      throw _privateConstructorUsedError;

  /// Calculated sky brightness change rate (ADU/s)
  double? get skyAduRate => throw _privateConstructorUsedError;

  /// Twilight mode for sky flats
  TwilightMode get twilightMode => throw _privateConstructorUsedError;

  /// Most recent captured image path
  String? get lastImagePath => throw _privateConstructorUsedError;

  /// Most recent captured image data (for preview, runtime only)
  @RuntimeOnlyValueConverter()
  Object? get lastImageData => throw _privateConstructorUsedError;

  /// Error message if any
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Warning message (non-fatal, informational)
  String? get warningMessage => throw _privateConstructorUsedError;

  /// Status message for progress display
  String? get statusMessage => throw _privateConstructorUsedError;

  /// Visualization toggles
  bool get showAduGraph => throw _privateConstructorUsedError;
  bool get showExposureTimeline => throw _privateConstructorUsedError;
  bool get showSkyBrightness => throw _privateConstructorUsedError;
  bool get showFilterCards => throw _privateConstructorUsedError;
  bool get showHistogramOverlay => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FlatWizardStateCopyWith<FlatWizardState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlatWizardStateCopyWith<$Res> {
  factory $FlatWizardStateCopyWith(
          FlatWizardState value, $Res Function(FlatWizardState) then) =
      _$FlatWizardStateCopyWithImpl<$Res, FlatWizardState>;
  @useResult
  $Res call(
      {FlatWizardMode mode,
      FlatWizardGlobalSettings globalSettings,
      List<FlatFilterSettings> filterSettings,
      List<FlatFilterPreset> filterPresets,
      int currentFilterIndex,
      int currentFrameIndex,
      bool isCapturing,
      bool isExposing,
      DateTime? exposureStartTime,
      double? currentExposureDuration,
      List<AduMeasurement> aduHistory,
      List<SkyBrightnessMeasurement> skyBrightnessHistory,
      double? skyAduRate,
      TwilightMode twilightMode,
      String? lastImagePath,
      @RuntimeOnlyValueConverter() Object? lastImageData,
      String? errorMessage,
      String? warningMessage,
      String? statusMessage,
      bool showAduGraph,
      bool showExposureTimeline,
      bool showSkyBrightness,
      bool showFilterCards,
      bool showHistogramOverlay});

  $FlatWizardGlobalSettingsCopyWith<$Res> get globalSettings;
}

/// @nodoc
class _$FlatWizardStateCopyWithImpl<$Res, $Val extends FlatWizardState>
    implements $FlatWizardStateCopyWith<$Res> {
  _$FlatWizardStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mode = null,
    Object? globalSettings = null,
    Object? filterSettings = null,
    Object? filterPresets = null,
    Object? currentFilterIndex = null,
    Object? currentFrameIndex = null,
    Object? isCapturing = null,
    Object? isExposing = null,
    Object? exposureStartTime = freezed,
    Object? currentExposureDuration = freezed,
    Object? aduHistory = null,
    Object? skyBrightnessHistory = null,
    Object? skyAduRate = freezed,
    Object? twilightMode = null,
    Object? lastImagePath = freezed,
    Object? lastImageData = freezed,
    Object? errorMessage = freezed,
    Object? warningMessage = freezed,
    Object? statusMessage = freezed,
    Object? showAduGraph = null,
    Object? showExposureTimeline = null,
    Object? showSkyBrightness = null,
    Object? showFilterCards = null,
    Object? showHistogramOverlay = null,
  }) {
    return _then(_value.copyWith(
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as FlatWizardMode,
      globalSettings: null == globalSettings
          ? _value.globalSettings
          : globalSettings // ignore: cast_nullable_to_non_nullable
              as FlatWizardGlobalSettings,
      filterSettings: null == filterSettings
          ? _value.filterSettings
          : filterSettings // ignore: cast_nullable_to_non_nullable
              as List<FlatFilterSettings>,
      filterPresets: null == filterPresets
          ? _value.filterPresets
          : filterPresets // ignore: cast_nullable_to_non_nullable
              as List<FlatFilterPreset>,
      currentFilterIndex: null == currentFilterIndex
          ? _value.currentFilterIndex
          : currentFilterIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentFrameIndex: null == currentFrameIndex
          ? _value.currentFrameIndex
          : currentFrameIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isCapturing: null == isCapturing
          ? _value.isCapturing
          : isCapturing // ignore: cast_nullable_to_non_nullable
              as bool,
      isExposing: null == isExposing
          ? _value.isExposing
          : isExposing // ignore: cast_nullable_to_non_nullable
              as bool,
      exposureStartTime: freezed == exposureStartTime
          ? _value.exposureStartTime
          : exposureStartTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      currentExposureDuration: freezed == currentExposureDuration
          ? _value.currentExposureDuration
          : currentExposureDuration // ignore: cast_nullable_to_non_nullable
              as double?,
      aduHistory: null == aduHistory
          ? _value.aduHistory
          : aduHistory // ignore: cast_nullable_to_non_nullable
              as List<AduMeasurement>,
      skyBrightnessHistory: null == skyBrightnessHistory
          ? _value.skyBrightnessHistory
          : skyBrightnessHistory // ignore: cast_nullable_to_non_nullable
              as List<SkyBrightnessMeasurement>,
      skyAduRate: freezed == skyAduRate
          ? _value.skyAduRate
          : skyAduRate // ignore: cast_nullable_to_non_nullable
              as double?,
      twilightMode: null == twilightMode
          ? _value.twilightMode
          : twilightMode // ignore: cast_nullable_to_non_nullable
              as TwilightMode,
      lastImagePath: freezed == lastImagePath
          ? _value.lastImagePath
          : lastImagePath // ignore: cast_nullable_to_non_nullable
              as String?,
      lastImageData:
          freezed == lastImageData ? _value.lastImageData : lastImageData,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      warningMessage: freezed == warningMessage
          ? _value.warningMessage
          : warningMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      statusMessage: freezed == statusMessage
          ? _value.statusMessage
          : statusMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      showAduGraph: null == showAduGraph
          ? _value.showAduGraph
          : showAduGraph // ignore: cast_nullable_to_non_nullable
              as bool,
      showExposureTimeline: null == showExposureTimeline
          ? _value.showExposureTimeline
          : showExposureTimeline // ignore: cast_nullable_to_non_nullable
              as bool,
      showSkyBrightness: null == showSkyBrightness
          ? _value.showSkyBrightness
          : showSkyBrightness // ignore: cast_nullable_to_non_nullable
              as bool,
      showFilterCards: null == showFilterCards
          ? _value.showFilterCards
          : showFilterCards // ignore: cast_nullable_to_non_nullable
              as bool,
      showHistogramOverlay: null == showHistogramOverlay
          ? _value.showHistogramOverlay
          : showHistogramOverlay // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $FlatWizardGlobalSettingsCopyWith<$Res> get globalSettings {
    return $FlatWizardGlobalSettingsCopyWith<$Res>(_value.globalSettings,
        (value) {
      return _then(_value.copyWith(globalSettings: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$FlatWizardStateImplCopyWith<$Res>
    implements $FlatWizardStateCopyWith<$Res> {
  factory _$$FlatWizardStateImplCopyWith(_$FlatWizardStateImpl value,
          $Res Function(_$FlatWizardStateImpl) then) =
      __$$FlatWizardStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {FlatWizardMode mode,
      FlatWizardGlobalSettings globalSettings,
      List<FlatFilterSettings> filterSettings,
      List<FlatFilterPreset> filterPresets,
      int currentFilterIndex,
      int currentFrameIndex,
      bool isCapturing,
      bool isExposing,
      DateTime? exposureStartTime,
      double? currentExposureDuration,
      List<AduMeasurement> aduHistory,
      List<SkyBrightnessMeasurement> skyBrightnessHistory,
      double? skyAduRate,
      TwilightMode twilightMode,
      String? lastImagePath,
      @RuntimeOnlyValueConverter() Object? lastImageData,
      String? errorMessage,
      String? warningMessage,
      String? statusMessage,
      bool showAduGraph,
      bool showExposureTimeline,
      bool showSkyBrightness,
      bool showFilterCards,
      bool showHistogramOverlay});

  @override
  $FlatWizardGlobalSettingsCopyWith<$Res> get globalSettings;
}

/// @nodoc
class __$$FlatWizardStateImplCopyWithImpl<$Res>
    extends _$FlatWizardStateCopyWithImpl<$Res, _$FlatWizardStateImpl>
    implements _$$FlatWizardStateImplCopyWith<$Res> {
  __$$FlatWizardStateImplCopyWithImpl(
      _$FlatWizardStateImpl _value, $Res Function(_$FlatWizardStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mode = null,
    Object? globalSettings = null,
    Object? filterSettings = null,
    Object? filterPresets = null,
    Object? currentFilterIndex = null,
    Object? currentFrameIndex = null,
    Object? isCapturing = null,
    Object? isExposing = null,
    Object? exposureStartTime = freezed,
    Object? currentExposureDuration = freezed,
    Object? aduHistory = null,
    Object? skyBrightnessHistory = null,
    Object? skyAduRate = freezed,
    Object? twilightMode = null,
    Object? lastImagePath = freezed,
    Object? lastImageData = freezed,
    Object? errorMessage = freezed,
    Object? warningMessage = freezed,
    Object? statusMessage = freezed,
    Object? showAduGraph = null,
    Object? showExposureTimeline = null,
    Object? showSkyBrightness = null,
    Object? showFilterCards = null,
    Object? showHistogramOverlay = null,
  }) {
    return _then(_$FlatWizardStateImpl(
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as FlatWizardMode,
      globalSettings: null == globalSettings
          ? _value.globalSettings
          : globalSettings // ignore: cast_nullable_to_non_nullable
              as FlatWizardGlobalSettings,
      filterSettings: null == filterSettings
          ? _value._filterSettings
          : filterSettings // ignore: cast_nullable_to_non_nullable
              as List<FlatFilterSettings>,
      filterPresets: null == filterPresets
          ? _value._filterPresets
          : filterPresets // ignore: cast_nullable_to_non_nullable
              as List<FlatFilterPreset>,
      currentFilterIndex: null == currentFilterIndex
          ? _value.currentFilterIndex
          : currentFilterIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentFrameIndex: null == currentFrameIndex
          ? _value.currentFrameIndex
          : currentFrameIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isCapturing: null == isCapturing
          ? _value.isCapturing
          : isCapturing // ignore: cast_nullable_to_non_nullable
              as bool,
      isExposing: null == isExposing
          ? _value.isExposing
          : isExposing // ignore: cast_nullable_to_non_nullable
              as bool,
      exposureStartTime: freezed == exposureStartTime
          ? _value.exposureStartTime
          : exposureStartTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      currentExposureDuration: freezed == currentExposureDuration
          ? _value.currentExposureDuration
          : currentExposureDuration // ignore: cast_nullable_to_non_nullable
              as double?,
      aduHistory: null == aduHistory
          ? _value._aduHistory
          : aduHistory // ignore: cast_nullable_to_non_nullable
              as List<AduMeasurement>,
      skyBrightnessHistory: null == skyBrightnessHistory
          ? _value._skyBrightnessHistory
          : skyBrightnessHistory // ignore: cast_nullable_to_non_nullable
              as List<SkyBrightnessMeasurement>,
      skyAduRate: freezed == skyAduRate
          ? _value.skyAduRate
          : skyAduRate // ignore: cast_nullable_to_non_nullable
              as double?,
      twilightMode: null == twilightMode
          ? _value.twilightMode
          : twilightMode // ignore: cast_nullable_to_non_nullable
              as TwilightMode,
      lastImagePath: freezed == lastImagePath
          ? _value.lastImagePath
          : lastImagePath // ignore: cast_nullable_to_non_nullable
              as String?,
      lastImageData:
          freezed == lastImageData ? _value.lastImageData : lastImageData,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      warningMessage: freezed == warningMessage
          ? _value.warningMessage
          : warningMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      statusMessage: freezed == statusMessage
          ? _value.statusMessage
          : statusMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      showAduGraph: null == showAduGraph
          ? _value.showAduGraph
          : showAduGraph // ignore: cast_nullable_to_non_nullable
              as bool,
      showExposureTimeline: null == showExposureTimeline
          ? _value.showExposureTimeline
          : showExposureTimeline // ignore: cast_nullable_to_non_nullable
              as bool,
      showSkyBrightness: null == showSkyBrightness
          ? _value.showSkyBrightness
          : showSkyBrightness // ignore: cast_nullable_to_non_nullable
              as bool,
      showFilterCards: null == showFilterCards
          ? _value.showFilterCards
          : showFilterCards // ignore: cast_nullable_to_non_nullable
              as bool,
      showHistogramOverlay: null == showHistogramOverlay
          ? _value.showHistogramOverlay
          : showHistogramOverlay // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FlatWizardStateImpl implements _FlatWizardState {
  const _$FlatWizardStateImpl(
      {this.mode = FlatWizardMode.quick,
      this.globalSettings = const FlatWizardGlobalSettings(),
      final List<FlatFilterSettings> filterSettings = const [],
      final List<FlatFilterPreset> filterPresets = const [],
      this.currentFilterIndex = 0,
      this.currentFrameIndex = 0,
      this.isCapturing = false,
      this.isExposing = false,
      this.exposureStartTime,
      this.currentExposureDuration,
      final List<AduMeasurement> aduHistory = const [],
      final List<SkyBrightnessMeasurement> skyBrightnessHistory = const [],
      this.skyAduRate,
      this.twilightMode = TwilightMode.dusk,
      this.lastImagePath,
      @RuntimeOnlyValueConverter() this.lastImageData,
      this.errorMessage,
      this.warningMessage,
      this.statusMessage,
      this.showAduGraph = true,
      this.showExposureTimeline = true,
      this.showSkyBrightness = true,
      this.showFilterCards = true,
      this.showHistogramOverlay = false})
      : _filterSettings = filterSettings,
        _filterPresets = filterPresets,
        _aduHistory = aduHistory,
        _skyBrightnessHistory = skyBrightnessHistory;

  factory _$FlatWizardStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlatWizardStateImplFromJson(json);

  /// Current operating mode
  @override
  @JsonKey()
  final FlatWizardMode mode;

  /// Global settings
  @override
  @JsonKey()
  final FlatWizardGlobalSettings globalSettings;

  /// Per-filter settings
  final List<FlatFilterSettings> _filterSettings;

  /// Per-filter settings
  @override
  @JsonKey()
  List<FlatFilterSettings> get filterSettings {
    if (_filterSettings is EqualUnmodifiableListView) return _filterSettings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_filterSettings);
  }

  /// Saved filter presets
  final List<FlatFilterPreset> _filterPresets;

  /// Saved filter presets
  @override
  @JsonKey()
  List<FlatFilterPreset> get filterPresets {
    if (_filterPresets is EqualUnmodifiableListView) return _filterPresets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_filterPresets);
  }

  /// Current filter index being processed
  @override
  @JsonKey()
  final int currentFilterIndex;

  /// Current frame index for active filter
  @override
  @JsonKey()
  final int currentFrameIndex;

  /// Is capture/calibration in progress
  @override
  @JsonKey()
  final bool isCapturing;

  /// Is currently exposing (for countdown)
  @override
  @JsonKey()
  final bool isExposing;

  /// Current exposure start time (for countdown)
  @override
  final DateTime? exposureStartTime;

  /// Current exposure duration (for countdown)
  @override
  final double? currentExposureDuration;

  /// ADU measurements for convergence graph
  final List<AduMeasurement> _aduHistory;

  /// ADU measurements for convergence graph
  @override
  @JsonKey()
  List<AduMeasurement> get aduHistory {
    if (_aduHistory is EqualUnmodifiableListView) return _aduHistory;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_aduHistory);
  }

  /// Sky brightness measurements for rate tracking
  final List<SkyBrightnessMeasurement> _skyBrightnessHistory;

  /// Sky brightness measurements for rate tracking
  @override
  @JsonKey()
  List<SkyBrightnessMeasurement> get skyBrightnessHistory {
    if (_skyBrightnessHistory is EqualUnmodifiableListView)
      return _skyBrightnessHistory;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_skyBrightnessHistory);
  }

  /// Calculated sky brightness change rate (ADU/s)
  @override
  final double? skyAduRate;

  /// Twilight mode for sky flats
  @override
  @JsonKey()
  final TwilightMode twilightMode;

  /// Most recent captured image path
  @override
  final String? lastImagePath;

  /// Most recent captured image data (for preview, runtime only)
  @override
  @RuntimeOnlyValueConverter()
  final Object? lastImageData;

  /// Error message if any
  @override
  final String? errorMessage;

  /// Warning message (non-fatal, informational)
  @override
  final String? warningMessage;

  /// Status message for progress display
  @override
  final String? statusMessage;

  /// Visualization toggles
  @override
  @JsonKey()
  final bool showAduGraph;
  @override
  @JsonKey()
  final bool showExposureTimeline;
  @override
  @JsonKey()
  final bool showSkyBrightness;
  @override
  @JsonKey()
  final bool showFilterCards;
  @override
  @JsonKey()
  final bool showHistogramOverlay;

  @override
  String toString() {
    return 'FlatWizardState(mode: $mode, globalSettings: $globalSettings, filterSettings: $filterSettings, filterPresets: $filterPresets, currentFilterIndex: $currentFilterIndex, currentFrameIndex: $currentFrameIndex, isCapturing: $isCapturing, isExposing: $isExposing, exposureStartTime: $exposureStartTime, currentExposureDuration: $currentExposureDuration, aduHistory: $aduHistory, skyBrightnessHistory: $skyBrightnessHistory, skyAduRate: $skyAduRate, twilightMode: $twilightMode, lastImagePath: $lastImagePath, lastImageData: $lastImageData, errorMessage: $errorMessage, warningMessage: $warningMessage, statusMessage: $statusMessage, showAduGraph: $showAduGraph, showExposureTimeline: $showExposureTimeline, showSkyBrightness: $showSkyBrightness, showFilterCards: $showFilterCards, showHistogramOverlay: $showHistogramOverlay)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlatWizardStateImpl &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.globalSettings, globalSettings) ||
                other.globalSettings == globalSettings) &&
            const DeepCollectionEquality()
                .equals(other._filterSettings, _filterSettings) &&
            const DeepCollectionEquality()
                .equals(other._filterPresets, _filterPresets) &&
            (identical(other.currentFilterIndex, currentFilterIndex) ||
                other.currentFilterIndex == currentFilterIndex) &&
            (identical(other.currentFrameIndex, currentFrameIndex) ||
                other.currentFrameIndex == currentFrameIndex) &&
            (identical(other.isCapturing, isCapturing) ||
                other.isCapturing == isCapturing) &&
            (identical(other.isExposing, isExposing) ||
                other.isExposing == isExposing) &&
            (identical(other.exposureStartTime, exposureStartTime) ||
                other.exposureStartTime == exposureStartTime) &&
            (identical(
                    other.currentExposureDuration, currentExposureDuration) ||
                other.currentExposureDuration == currentExposureDuration) &&
            const DeepCollectionEquality()
                .equals(other._aduHistory, _aduHistory) &&
            const DeepCollectionEquality()
                .equals(other._skyBrightnessHistory, _skyBrightnessHistory) &&
            (identical(other.skyAduRate, skyAduRate) ||
                other.skyAduRate == skyAduRate) &&
            (identical(other.twilightMode, twilightMode) ||
                other.twilightMode == twilightMode) &&
            (identical(other.lastImagePath, lastImagePath) ||
                other.lastImagePath == lastImagePath) &&
            const DeepCollectionEquality()
                .equals(other.lastImageData, lastImageData) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.warningMessage, warningMessage) ||
                other.warningMessage == warningMessage) &&
            (identical(other.statusMessage, statusMessage) ||
                other.statusMessage == statusMessage) &&
            (identical(other.showAduGraph, showAduGraph) ||
                other.showAduGraph == showAduGraph) &&
            (identical(other.showExposureTimeline, showExposureTimeline) ||
                other.showExposureTimeline == showExposureTimeline) &&
            (identical(other.showSkyBrightness, showSkyBrightness) ||
                other.showSkyBrightness == showSkyBrightness) &&
            (identical(other.showFilterCards, showFilterCards) ||
                other.showFilterCards == showFilterCards) &&
            (identical(other.showHistogramOverlay, showHistogramOverlay) ||
                other.showHistogramOverlay == showHistogramOverlay));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        mode,
        globalSettings,
        const DeepCollectionEquality().hash(_filterSettings),
        const DeepCollectionEquality().hash(_filterPresets),
        currentFilterIndex,
        currentFrameIndex,
        isCapturing,
        isExposing,
        exposureStartTime,
        currentExposureDuration,
        const DeepCollectionEquality().hash(_aduHistory),
        const DeepCollectionEquality().hash(_skyBrightnessHistory),
        skyAduRate,
        twilightMode,
        lastImagePath,
        const DeepCollectionEquality().hash(lastImageData),
        errorMessage,
        warningMessage,
        statusMessage,
        showAduGraph,
        showExposureTimeline,
        showSkyBrightness,
        showFilterCards,
        showHistogramOverlay
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FlatWizardStateImplCopyWith<_$FlatWizardStateImpl> get copyWith =>
      __$$FlatWizardStateImplCopyWithImpl<_$FlatWizardStateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FlatWizardStateImplToJson(
      this,
    );
  }
}

abstract class _FlatWizardState implements FlatWizardState {
  const factory _FlatWizardState(
      {final FlatWizardMode mode,
      final FlatWizardGlobalSettings globalSettings,
      final List<FlatFilterSettings> filterSettings,
      final List<FlatFilterPreset> filterPresets,
      final int currentFilterIndex,
      final int currentFrameIndex,
      final bool isCapturing,
      final bool isExposing,
      final DateTime? exposureStartTime,
      final double? currentExposureDuration,
      final List<AduMeasurement> aduHistory,
      final List<SkyBrightnessMeasurement> skyBrightnessHistory,
      final double? skyAduRate,
      final TwilightMode twilightMode,
      final String? lastImagePath,
      @RuntimeOnlyValueConverter() final Object? lastImageData,
      final String? errorMessage,
      final String? warningMessage,
      final String? statusMessage,
      final bool showAduGraph,
      final bool showExposureTimeline,
      final bool showSkyBrightness,
      final bool showFilterCards,
      final bool showHistogramOverlay}) = _$FlatWizardStateImpl;

  factory _FlatWizardState.fromJson(Map<String, dynamic> json) =
      _$FlatWizardStateImpl.fromJson;

  @override

  /// Current operating mode
  FlatWizardMode get mode;
  @override

  /// Global settings
  FlatWizardGlobalSettings get globalSettings;
  @override

  /// Per-filter settings
  List<FlatFilterSettings> get filterSettings;
  @override

  /// Saved filter presets
  List<FlatFilterPreset> get filterPresets;
  @override

  /// Current filter index being processed
  int get currentFilterIndex;
  @override

  /// Current frame index for active filter
  int get currentFrameIndex;
  @override

  /// Is capture/calibration in progress
  bool get isCapturing;
  @override

  /// Is currently exposing (for countdown)
  bool get isExposing;
  @override

  /// Current exposure start time (for countdown)
  DateTime? get exposureStartTime;
  @override

  /// Current exposure duration (for countdown)
  double? get currentExposureDuration;
  @override

  /// ADU measurements for convergence graph
  List<AduMeasurement> get aduHistory;
  @override

  /// Sky brightness measurements for rate tracking
  List<SkyBrightnessMeasurement> get skyBrightnessHistory;
  @override

  /// Calculated sky brightness change rate (ADU/s)
  double? get skyAduRate;
  @override

  /// Twilight mode for sky flats
  TwilightMode get twilightMode;
  @override

  /// Most recent captured image path
  String? get lastImagePath;
  @override

  /// Most recent captured image data (for preview, runtime only)
  @RuntimeOnlyValueConverter()
  Object? get lastImageData;
  @override

  /// Error message if any
  String? get errorMessage;
  @override

  /// Warning message (non-fatal, informational)
  String? get warningMessage;
  @override

  /// Status message for progress display
  String? get statusMessage;
  @override

  /// Visualization toggles
  bool get showAduGraph;
  @override
  bool get showExposureTimeline;
  @override
  bool get showSkyBrightness;
  @override
  bool get showFilterCards;
  @override
  bool get showHistogramOverlay;
  @override
  @JsonKey(ignore: true)
  _$$FlatWizardStateImplCopyWith<_$FlatWizardStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
