// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'annotation_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AnnotationSettings _$AnnotationSettingsFromJson(Map<String, dynamic> json) {
  return _AnnotationSettings.fromJson(json);
}

/// @nodoc
mixin _$AnnotationSettings {
  /// Whether annotations are enabled
  bool get enabled => throw _privateConstructorUsedError;

  /// Magnitude cutoff for displayed objects (fainter = higher number)
  double get magnitudeCutoff => throw _privateConstructorUsedError;

  /// Minimum magnitude to display (brighter = lower number)
  double get minMagnitude => throw _privateConstructorUsedError;

  /// Object types to display
  Set<AnnotationObjectFilter> get visibleTypes =>
      throw _privateConstructorUsedError;

  /// Whether to show object labels
  bool get showLabels => throw _privateConstructorUsedError;

  /// Whether to show magnitude values
  bool get showMagnitudes => throw _privateConstructorUsedError;

  /// Whether to fade annotations when mouse is not over image
  bool get fadeWhenNotHovering => throw _privateConstructorUsedError;

  /// Opacity when mouse is hovering over image (0.0-1.0)
  double get hoverOpacity => throw _privateConstructorUsedError;

  /// Opacity when mouse is not hovering (0.0-1.0)
  double get idleOpacity => throw _privateConstructorUsedError;

  /// Duration of fade animation in milliseconds
  int get fadeAnimationMs => throw _privateConstructorUsedError;

  /// Whether to enable click-to-identify
  bool get clickToIdentify => throw _privateConstructorUsedError;

  /// Search radius for click-to-identify in arcseconds
  double get clickSearchRadiusArcsec => throw _privateConstructorUsedError;

  /// Whether to auto-annotate new captured images
  bool get autoAnnotate => throw _privateConstructorUsedError;

  /// Maximum number of objects to display
  int get maxObjectsToDisplay => throw _privateConstructorUsedError;

  /// Whether to show compass overlay (N/E arrows from plate solve rotation)
  bool get compassEnabled => throw _privateConstructorUsedError;

  /// Whether to show scale bar overlay (angular size reference)
  bool get scaleBarEnabled => throw _privateConstructorUsedError;

  /// Grid overlay type (none, pixel, or celestial RA/Dec)
  GridType get gridType => throw _privateConstructorUsedError;

  /// Whether to show plate solve residual vectors overlay
  bool get showSolveResiduals => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AnnotationSettingsCopyWith<AnnotationSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AnnotationSettingsCopyWith<$Res> {
  factory $AnnotationSettingsCopyWith(
          AnnotationSettings value, $Res Function(AnnotationSettings) then) =
      _$AnnotationSettingsCopyWithImpl<$Res, AnnotationSettings>;
  @useResult
  $Res call(
      {bool enabled,
      double magnitudeCutoff,
      double minMagnitude,
      Set<AnnotationObjectFilter> visibleTypes,
      bool showLabels,
      bool showMagnitudes,
      bool fadeWhenNotHovering,
      double hoverOpacity,
      double idleOpacity,
      int fadeAnimationMs,
      bool clickToIdentify,
      double clickSearchRadiusArcsec,
      bool autoAnnotate,
      int maxObjectsToDisplay,
      bool compassEnabled,
      bool scaleBarEnabled,
      GridType gridType,
      bool showSolveResiduals});
}

/// @nodoc
class _$AnnotationSettingsCopyWithImpl<$Res, $Val extends AnnotationSettings>
    implements $AnnotationSettingsCopyWith<$Res> {
  _$AnnotationSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabled = null,
    Object? magnitudeCutoff = null,
    Object? minMagnitude = null,
    Object? visibleTypes = null,
    Object? showLabels = null,
    Object? showMagnitudes = null,
    Object? fadeWhenNotHovering = null,
    Object? hoverOpacity = null,
    Object? idleOpacity = null,
    Object? fadeAnimationMs = null,
    Object? clickToIdentify = null,
    Object? clickSearchRadiusArcsec = null,
    Object? autoAnnotate = null,
    Object? maxObjectsToDisplay = null,
    Object? compassEnabled = null,
    Object? scaleBarEnabled = null,
    Object? gridType = null,
    Object? showSolveResiduals = null,
  }) {
    return _then(_value.copyWith(
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      magnitudeCutoff: null == magnitudeCutoff
          ? _value.magnitudeCutoff
          : magnitudeCutoff // ignore: cast_nullable_to_non_nullable
              as double,
      minMagnitude: null == minMagnitude
          ? _value.minMagnitude
          : minMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      visibleTypes: null == visibleTypes
          ? _value.visibleTypes
          : visibleTypes // ignore: cast_nullable_to_non_nullable
              as Set<AnnotationObjectFilter>,
      showLabels: null == showLabels
          ? _value.showLabels
          : showLabels // ignore: cast_nullable_to_non_nullable
              as bool,
      showMagnitudes: null == showMagnitudes
          ? _value.showMagnitudes
          : showMagnitudes // ignore: cast_nullable_to_non_nullable
              as bool,
      fadeWhenNotHovering: null == fadeWhenNotHovering
          ? _value.fadeWhenNotHovering
          : fadeWhenNotHovering // ignore: cast_nullable_to_non_nullable
              as bool,
      hoverOpacity: null == hoverOpacity
          ? _value.hoverOpacity
          : hoverOpacity // ignore: cast_nullable_to_non_nullable
              as double,
      idleOpacity: null == idleOpacity
          ? _value.idleOpacity
          : idleOpacity // ignore: cast_nullable_to_non_nullable
              as double,
      fadeAnimationMs: null == fadeAnimationMs
          ? _value.fadeAnimationMs
          : fadeAnimationMs // ignore: cast_nullable_to_non_nullable
              as int,
      clickToIdentify: null == clickToIdentify
          ? _value.clickToIdentify
          : clickToIdentify // ignore: cast_nullable_to_non_nullable
              as bool,
      clickSearchRadiusArcsec: null == clickSearchRadiusArcsec
          ? _value.clickSearchRadiusArcsec
          : clickSearchRadiusArcsec // ignore: cast_nullable_to_non_nullable
              as double,
      autoAnnotate: null == autoAnnotate
          ? _value.autoAnnotate
          : autoAnnotate // ignore: cast_nullable_to_non_nullable
              as bool,
      maxObjectsToDisplay: null == maxObjectsToDisplay
          ? _value.maxObjectsToDisplay
          : maxObjectsToDisplay // ignore: cast_nullable_to_non_nullable
              as int,
      compassEnabled: null == compassEnabled
          ? _value.compassEnabled
          : compassEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      scaleBarEnabled: null == scaleBarEnabled
          ? _value.scaleBarEnabled
          : scaleBarEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      gridType: null == gridType
          ? _value.gridType
          : gridType // ignore: cast_nullable_to_non_nullable
              as GridType,
      showSolveResiduals: null == showSolveResiduals
          ? _value.showSolveResiduals
          : showSolveResiduals // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AnnotationSettingsImplCopyWith<$Res>
    implements $AnnotationSettingsCopyWith<$Res> {
  factory _$$AnnotationSettingsImplCopyWith(_$AnnotationSettingsImpl value,
          $Res Function(_$AnnotationSettingsImpl) then) =
      __$$AnnotationSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool enabled,
      double magnitudeCutoff,
      double minMagnitude,
      Set<AnnotationObjectFilter> visibleTypes,
      bool showLabels,
      bool showMagnitudes,
      bool fadeWhenNotHovering,
      double hoverOpacity,
      double idleOpacity,
      int fadeAnimationMs,
      bool clickToIdentify,
      double clickSearchRadiusArcsec,
      bool autoAnnotate,
      int maxObjectsToDisplay,
      bool compassEnabled,
      bool scaleBarEnabled,
      GridType gridType,
      bool showSolveResiduals});
}

/// @nodoc
class __$$AnnotationSettingsImplCopyWithImpl<$Res>
    extends _$AnnotationSettingsCopyWithImpl<$Res, _$AnnotationSettingsImpl>
    implements _$$AnnotationSettingsImplCopyWith<$Res> {
  __$$AnnotationSettingsImplCopyWithImpl(_$AnnotationSettingsImpl _value,
      $Res Function(_$AnnotationSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabled = null,
    Object? magnitudeCutoff = null,
    Object? minMagnitude = null,
    Object? visibleTypes = null,
    Object? showLabels = null,
    Object? showMagnitudes = null,
    Object? fadeWhenNotHovering = null,
    Object? hoverOpacity = null,
    Object? idleOpacity = null,
    Object? fadeAnimationMs = null,
    Object? clickToIdentify = null,
    Object? clickSearchRadiusArcsec = null,
    Object? autoAnnotate = null,
    Object? maxObjectsToDisplay = null,
    Object? compassEnabled = null,
    Object? scaleBarEnabled = null,
    Object? gridType = null,
    Object? showSolveResiduals = null,
  }) {
    return _then(_$AnnotationSettingsImpl(
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      magnitudeCutoff: null == magnitudeCutoff
          ? _value.magnitudeCutoff
          : magnitudeCutoff // ignore: cast_nullable_to_non_nullable
              as double,
      minMagnitude: null == minMagnitude
          ? _value.minMagnitude
          : minMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      visibleTypes: null == visibleTypes
          ? _value._visibleTypes
          : visibleTypes // ignore: cast_nullable_to_non_nullable
              as Set<AnnotationObjectFilter>,
      showLabels: null == showLabels
          ? _value.showLabels
          : showLabels // ignore: cast_nullable_to_non_nullable
              as bool,
      showMagnitudes: null == showMagnitudes
          ? _value.showMagnitudes
          : showMagnitudes // ignore: cast_nullable_to_non_nullable
              as bool,
      fadeWhenNotHovering: null == fadeWhenNotHovering
          ? _value.fadeWhenNotHovering
          : fadeWhenNotHovering // ignore: cast_nullable_to_non_nullable
              as bool,
      hoverOpacity: null == hoverOpacity
          ? _value.hoverOpacity
          : hoverOpacity // ignore: cast_nullable_to_non_nullable
              as double,
      idleOpacity: null == idleOpacity
          ? _value.idleOpacity
          : idleOpacity // ignore: cast_nullable_to_non_nullable
              as double,
      fadeAnimationMs: null == fadeAnimationMs
          ? _value.fadeAnimationMs
          : fadeAnimationMs // ignore: cast_nullable_to_non_nullable
              as int,
      clickToIdentify: null == clickToIdentify
          ? _value.clickToIdentify
          : clickToIdentify // ignore: cast_nullable_to_non_nullable
              as bool,
      clickSearchRadiusArcsec: null == clickSearchRadiusArcsec
          ? _value.clickSearchRadiusArcsec
          : clickSearchRadiusArcsec // ignore: cast_nullable_to_non_nullable
              as double,
      autoAnnotate: null == autoAnnotate
          ? _value.autoAnnotate
          : autoAnnotate // ignore: cast_nullable_to_non_nullable
              as bool,
      maxObjectsToDisplay: null == maxObjectsToDisplay
          ? _value.maxObjectsToDisplay
          : maxObjectsToDisplay // ignore: cast_nullable_to_non_nullable
              as int,
      compassEnabled: null == compassEnabled
          ? _value.compassEnabled
          : compassEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      scaleBarEnabled: null == scaleBarEnabled
          ? _value.scaleBarEnabled
          : scaleBarEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      gridType: null == gridType
          ? _value.gridType
          : gridType // ignore: cast_nullable_to_non_nullable
              as GridType,
      showSolveResiduals: null == showSolveResiduals
          ? _value.showSolveResiduals
          : showSolveResiduals // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AnnotationSettingsImpl implements _AnnotationSettings {
  const _$AnnotationSettingsImpl(
      {this.enabled = true,
      this.magnitudeCutoff = 15.0,
      this.minMagnitude = -5.0,
      final Set<AnnotationObjectFilter> visibleTypes = const {
        AnnotationObjectFilter.galaxies,
        AnnotationObjectFilter.nebulae,
        AnnotationObjectFilter.starClusters,
        AnnotationObjectFilter.planetaryNebulae
      },
      this.showLabels = true,
      this.showMagnitudes = false,
      this.fadeWhenNotHovering = true,
      this.hoverOpacity = 0.8,
      this.idleOpacity = 0.2,
      this.fadeAnimationMs = 400,
      this.clickToIdentify = true,
      this.clickSearchRadiusArcsec = 30.0,
      this.autoAnnotate = true,
      this.maxObjectsToDisplay = 500,
      this.compassEnabled = true,
      this.scaleBarEnabled = true,
      this.gridType = GridType.none,
      this.showSolveResiduals = false})
      : _visibleTypes = visibleTypes;

  factory _$AnnotationSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$AnnotationSettingsImplFromJson(json);

  /// Whether annotations are enabled
  @override
  @JsonKey()
  final bool enabled;

  /// Magnitude cutoff for displayed objects (fainter = higher number)
  @override
  @JsonKey()
  final double magnitudeCutoff;

  /// Minimum magnitude to display (brighter = lower number)
  @override
  @JsonKey()
  final double minMagnitude;

  /// Object types to display
  final Set<AnnotationObjectFilter> _visibleTypes;

  /// Object types to display
  @override
  @JsonKey()
  Set<AnnotationObjectFilter> get visibleTypes {
    if (_visibleTypes is EqualUnmodifiableSetView) return _visibleTypes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_visibleTypes);
  }

  /// Whether to show object labels
  @override
  @JsonKey()
  final bool showLabels;

  /// Whether to show magnitude values
  @override
  @JsonKey()
  final bool showMagnitudes;

  /// Whether to fade annotations when mouse is not over image
  @override
  @JsonKey()
  final bool fadeWhenNotHovering;

  /// Opacity when mouse is hovering over image (0.0-1.0)
  @override
  @JsonKey()
  final double hoverOpacity;

  /// Opacity when mouse is not hovering (0.0-1.0)
  @override
  @JsonKey()
  final double idleOpacity;

  /// Duration of fade animation in milliseconds
  @override
  @JsonKey()
  final int fadeAnimationMs;

  /// Whether to enable click-to-identify
  @override
  @JsonKey()
  final bool clickToIdentify;

  /// Search radius for click-to-identify in arcseconds
  @override
  @JsonKey()
  final double clickSearchRadiusArcsec;

  /// Whether to auto-annotate new captured images
  @override
  @JsonKey()
  final bool autoAnnotate;

  /// Maximum number of objects to display
  @override
  @JsonKey()
  final int maxObjectsToDisplay;

  /// Whether to show compass overlay (N/E arrows from plate solve rotation)
  @override
  @JsonKey()
  final bool compassEnabled;

  /// Whether to show scale bar overlay (angular size reference)
  @override
  @JsonKey()
  final bool scaleBarEnabled;

  /// Grid overlay type (none, pixel, or celestial RA/Dec)
  @override
  @JsonKey()
  final GridType gridType;

  /// Whether to show plate solve residual vectors overlay
  @override
  @JsonKey()
  final bool showSolveResiduals;

  @override
  String toString() {
    return 'AnnotationSettings(enabled: $enabled, magnitudeCutoff: $magnitudeCutoff, minMagnitude: $minMagnitude, visibleTypes: $visibleTypes, showLabels: $showLabels, showMagnitudes: $showMagnitudes, fadeWhenNotHovering: $fadeWhenNotHovering, hoverOpacity: $hoverOpacity, idleOpacity: $idleOpacity, fadeAnimationMs: $fadeAnimationMs, clickToIdentify: $clickToIdentify, clickSearchRadiusArcsec: $clickSearchRadiusArcsec, autoAnnotate: $autoAnnotate, maxObjectsToDisplay: $maxObjectsToDisplay, compassEnabled: $compassEnabled, scaleBarEnabled: $scaleBarEnabled, gridType: $gridType, showSolveResiduals: $showSolveResiduals)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AnnotationSettingsImpl &&
            (identical(other.enabled, enabled) || other.enabled == enabled) &&
            (identical(other.magnitudeCutoff, magnitudeCutoff) ||
                other.magnitudeCutoff == magnitudeCutoff) &&
            (identical(other.minMagnitude, minMagnitude) ||
                other.minMagnitude == minMagnitude) &&
            const DeepCollectionEquality()
                .equals(other._visibleTypes, _visibleTypes) &&
            (identical(other.showLabels, showLabels) ||
                other.showLabels == showLabels) &&
            (identical(other.showMagnitudes, showMagnitudes) ||
                other.showMagnitudes == showMagnitudes) &&
            (identical(other.fadeWhenNotHovering, fadeWhenNotHovering) ||
                other.fadeWhenNotHovering == fadeWhenNotHovering) &&
            (identical(other.hoverOpacity, hoverOpacity) ||
                other.hoverOpacity == hoverOpacity) &&
            (identical(other.idleOpacity, idleOpacity) ||
                other.idleOpacity == idleOpacity) &&
            (identical(other.fadeAnimationMs, fadeAnimationMs) ||
                other.fadeAnimationMs == fadeAnimationMs) &&
            (identical(other.clickToIdentify, clickToIdentify) ||
                other.clickToIdentify == clickToIdentify) &&
            (identical(
                    other.clickSearchRadiusArcsec, clickSearchRadiusArcsec) ||
                other.clickSearchRadiusArcsec == clickSearchRadiusArcsec) &&
            (identical(other.autoAnnotate, autoAnnotate) ||
                other.autoAnnotate == autoAnnotate) &&
            (identical(other.maxObjectsToDisplay, maxObjectsToDisplay) ||
                other.maxObjectsToDisplay == maxObjectsToDisplay) &&
            (identical(other.compassEnabled, compassEnabled) ||
                other.compassEnabled == compassEnabled) &&
            (identical(other.scaleBarEnabled, scaleBarEnabled) ||
                other.scaleBarEnabled == scaleBarEnabled) &&
            (identical(other.gridType, gridType) ||
                other.gridType == gridType) &&
            (identical(other.showSolveResiduals, showSolveResiduals) ||
                other.showSolveResiduals == showSolveResiduals));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      enabled,
      magnitudeCutoff,
      minMagnitude,
      const DeepCollectionEquality().hash(_visibleTypes),
      showLabels,
      showMagnitudes,
      fadeWhenNotHovering,
      hoverOpacity,
      idleOpacity,
      fadeAnimationMs,
      clickToIdentify,
      clickSearchRadiusArcsec,
      autoAnnotate,
      maxObjectsToDisplay,
      compassEnabled,
      scaleBarEnabled,
      gridType,
      showSolveResiduals);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AnnotationSettingsImplCopyWith<_$AnnotationSettingsImpl> get copyWith =>
      __$$AnnotationSettingsImplCopyWithImpl<_$AnnotationSettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AnnotationSettingsImplToJson(
      this,
    );
  }
}

abstract class _AnnotationSettings implements AnnotationSettings {
  const factory _AnnotationSettings(
      {final bool enabled,
      final double magnitudeCutoff,
      final double minMagnitude,
      final Set<AnnotationObjectFilter> visibleTypes,
      final bool showLabels,
      final bool showMagnitudes,
      final bool fadeWhenNotHovering,
      final double hoverOpacity,
      final double idleOpacity,
      final int fadeAnimationMs,
      final bool clickToIdentify,
      final double clickSearchRadiusArcsec,
      final bool autoAnnotate,
      final int maxObjectsToDisplay,
      final bool compassEnabled,
      final bool scaleBarEnabled,
      final GridType gridType,
      final bool showSolveResiduals}) = _$AnnotationSettingsImpl;

  factory _AnnotationSettings.fromJson(Map<String, dynamic> json) =
      _$AnnotationSettingsImpl.fromJson;

  @override

  /// Whether annotations are enabled
  bool get enabled;
  @override

  /// Magnitude cutoff for displayed objects (fainter = higher number)
  double get magnitudeCutoff;
  @override

  /// Minimum magnitude to display (brighter = lower number)
  double get minMagnitude;
  @override

  /// Object types to display
  Set<AnnotationObjectFilter> get visibleTypes;
  @override

  /// Whether to show object labels
  bool get showLabels;
  @override

  /// Whether to show magnitude values
  bool get showMagnitudes;
  @override

  /// Whether to fade annotations when mouse is not over image
  bool get fadeWhenNotHovering;
  @override

  /// Opacity when mouse is hovering over image (0.0-1.0)
  double get hoverOpacity;
  @override

  /// Opacity when mouse is not hovering (0.0-1.0)
  double get idleOpacity;
  @override

  /// Duration of fade animation in milliseconds
  int get fadeAnimationMs;
  @override

  /// Whether to enable click-to-identify
  bool get clickToIdentify;
  @override

  /// Search radius for click-to-identify in arcseconds
  double get clickSearchRadiusArcsec;
  @override

  /// Whether to auto-annotate new captured images
  bool get autoAnnotate;
  @override

  /// Maximum number of objects to display
  int get maxObjectsToDisplay;
  @override

  /// Whether to show compass overlay (N/E arrows from plate solve rotation)
  bool get compassEnabled;
  @override

  /// Whether to show scale bar overlay (angular size reference)
  bool get scaleBarEnabled;
  @override

  /// Grid overlay type (none, pixel, or celestial RA/Dec)
  GridType get gridType;
  @override

  /// Whether to show plate solve residual vectors overlay
  bool get showSolveResiduals;
  @override
  @JsonKey(ignore: true)
  _$$AnnotationSettingsImplCopyWith<_$AnnotationSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

AnnotationMarkerStyle _$AnnotationMarkerStyleFromJson(
    Map<String, dynamic> json) {
  return _AnnotationMarkerStyle.fromJson(json);
}

/// @nodoc
mixin _$AnnotationMarkerStyle {
  /// Color for galaxy markers (gold)
  int get galaxyColor => throw _privateConstructorUsedError;

  /// Color for nebula markers (magenta)
  int get nebulaColor => throw _privateConstructorUsedError;

  /// Color for star cluster markers (cyan)
  int get clusterColor => throw _privateConstructorUsedError;

  /// Color for planetary nebula markers (violet)
  int get planetaryNebulaColor => throw _privateConstructorUsedError;

  /// Color for star markers (white)
  int get starColor => throw _privateConstructorUsedError;

  /// Color for unknown/other markers (green)
  int get otherColor => throw _privateConstructorUsedError;

  /// Stroke width for marker outlines
  double get strokeWidth => throw _privateConstructorUsedError;

  /// Font size for labels
  double get labelFontSize => throw _privateConstructorUsedError;

  /// Whether to scale markers based on object size
  bool get scaleBySize => throw _privateConstructorUsedError;

  /// Minimum marker size in pixels
  double get minMarkerSize => throw _privateConstructorUsedError;

  /// Maximum marker size in pixels
  double get maxMarkerSize => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AnnotationMarkerStyleCopyWith<AnnotationMarkerStyle> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AnnotationMarkerStyleCopyWith<$Res> {
  factory $AnnotationMarkerStyleCopyWith(AnnotationMarkerStyle value,
          $Res Function(AnnotationMarkerStyle) then) =
      _$AnnotationMarkerStyleCopyWithImpl<$Res, AnnotationMarkerStyle>;
  @useResult
  $Res call(
      {int galaxyColor,
      int nebulaColor,
      int clusterColor,
      int planetaryNebulaColor,
      int starColor,
      int otherColor,
      double strokeWidth,
      double labelFontSize,
      bool scaleBySize,
      double minMarkerSize,
      double maxMarkerSize});
}

/// @nodoc
class _$AnnotationMarkerStyleCopyWithImpl<$Res,
        $Val extends AnnotationMarkerStyle>
    implements $AnnotationMarkerStyleCopyWith<$Res> {
  _$AnnotationMarkerStyleCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galaxyColor = null,
    Object? nebulaColor = null,
    Object? clusterColor = null,
    Object? planetaryNebulaColor = null,
    Object? starColor = null,
    Object? otherColor = null,
    Object? strokeWidth = null,
    Object? labelFontSize = null,
    Object? scaleBySize = null,
    Object? minMarkerSize = null,
    Object? maxMarkerSize = null,
  }) {
    return _then(_value.copyWith(
      galaxyColor: null == galaxyColor
          ? _value.galaxyColor
          : galaxyColor // ignore: cast_nullable_to_non_nullable
              as int,
      nebulaColor: null == nebulaColor
          ? _value.nebulaColor
          : nebulaColor // ignore: cast_nullable_to_non_nullable
              as int,
      clusterColor: null == clusterColor
          ? _value.clusterColor
          : clusterColor // ignore: cast_nullable_to_non_nullable
              as int,
      planetaryNebulaColor: null == planetaryNebulaColor
          ? _value.planetaryNebulaColor
          : planetaryNebulaColor // ignore: cast_nullable_to_non_nullable
              as int,
      starColor: null == starColor
          ? _value.starColor
          : starColor // ignore: cast_nullable_to_non_nullable
              as int,
      otherColor: null == otherColor
          ? _value.otherColor
          : otherColor // ignore: cast_nullable_to_non_nullable
              as int,
      strokeWidth: null == strokeWidth
          ? _value.strokeWidth
          : strokeWidth // ignore: cast_nullable_to_non_nullable
              as double,
      labelFontSize: null == labelFontSize
          ? _value.labelFontSize
          : labelFontSize // ignore: cast_nullable_to_non_nullable
              as double,
      scaleBySize: null == scaleBySize
          ? _value.scaleBySize
          : scaleBySize // ignore: cast_nullable_to_non_nullable
              as bool,
      minMarkerSize: null == minMarkerSize
          ? _value.minMarkerSize
          : minMarkerSize // ignore: cast_nullable_to_non_nullable
              as double,
      maxMarkerSize: null == maxMarkerSize
          ? _value.maxMarkerSize
          : maxMarkerSize // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AnnotationMarkerStyleImplCopyWith<$Res>
    implements $AnnotationMarkerStyleCopyWith<$Res> {
  factory _$$AnnotationMarkerStyleImplCopyWith(
          _$AnnotationMarkerStyleImpl value,
          $Res Function(_$AnnotationMarkerStyleImpl) then) =
      __$$AnnotationMarkerStyleImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int galaxyColor,
      int nebulaColor,
      int clusterColor,
      int planetaryNebulaColor,
      int starColor,
      int otherColor,
      double strokeWidth,
      double labelFontSize,
      bool scaleBySize,
      double minMarkerSize,
      double maxMarkerSize});
}

/// @nodoc
class __$$AnnotationMarkerStyleImplCopyWithImpl<$Res>
    extends _$AnnotationMarkerStyleCopyWithImpl<$Res,
        _$AnnotationMarkerStyleImpl>
    implements _$$AnnotationMarkerStyleImplCopyWith<$Res> {
  __$$AnnotationMarkerStyleImplCopyWithImpl(_$AnnotationMarkerStyleImpl _value,
      $Res Function(_$AnnotationMarkerStyleImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? galaxyColor = null,
    Object? nebulaColor = null,
    Object? clusterColor = null,
    Object? planetaryNebulaColor = null,
    Object? starColor = null,
    Object? otherColor = null,
    Object? strokeWidth = null,
    Object? labelFontSize = null,
    Object? scaleBySize = null,
    Object? minMarkerSize = null,
    Object? maxMarkerSize = null,
  }) {
    return _then(_$AnnotationMarkerStyleImpl(
      galaxyColor: null == galaxyColor
          ? _value.galaxyColor
          : galaxyColor // ignore: cast_nullable_to_non_nullable
              as int,
      nebulaColor: null == nebulaColor
          ? _value.nebulaColor
          : nebulaColor // ignore: cast_nullable_to_non_nullable
              as int,
      clusterColor: null == clusterColor
          ? _value.clusterColor
          : clusterColor // ignore: cast_nullable_to_non_nullable
              as int,
      planetaryNebulaColor: null == planetaryNebulaColor
          ? _value.planetaryNebulaColor
          : planetaryNebulaColor // ignore: cast_nullable_to_non_nullable
              as int,
      starColor: null == starColor
          ? _value.starColor
          : starColor // ignore: cast_nullable_to_non_nullable
              as int,
      otherColor: null == otherColor
          ? _value.otherColor
          : otherColor // ignore: cast_nullable_to_non_nullable
              as int,
      strokeWidth: null == strokeWidth
          ? _value.strokeWidth
          : strokeWidth // ignore: cast_nullable_to_non_nullable
              as double,
      labelFontSize: null == labelFontSize
          ? _value.labelFontSize
          : labelFontSize // ignore: cast_nullable_to_non_nullable
              as double,
      scaleBySize: null == scaleBySize
          ? _value.scaleBySize
          : scaleBySize // ignore: cast_nullable_to_non_nullable
              as bool,
      minMarkerSize: null == minMarkerSize
          ? _value.minMarkerSize
          : minMarkerSize // ignore: cast_nullable_to_non_nullable
              as double,
      maxMarkerSize: null == maxMarkerSize
          ? _value.maxMarkerSize
          : maxMarkerSize // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AnnotationMarkerStyleImpl implements _AnnotationMarkerStyle {
  const _$AnnotationMarkerStyleImpl(
      {this.galaxyColor = 0xFFFFD700,
      this.nebulaColor = 0xFFFF00FF,
      this.clusterColor = 0xFF00FFFF,
      this.planetaryNebulaColor = 0xFF9400D3,
      this.starColor = 0xFFFFFFFF,
      this.otherColor = 0xFF00FF00,
      this.strokeWidth = 1.5,
      this.labelFontSize = 12.0,
      this.scaleBySize = true,
      this.minMarkerSize = 10.0,
      this.maxMarkerSize = 100.0});

  factory _$AnnotationMarkerStyleImpl.fromJson(Map<String, dynamic> json) =>
      _$$AnnotationMarkerStyleImplFromJson(json);

  /// Color for galaxy markers (gold)
  @override
  @JsonKey()
  final int galaxyColor;

  /// Color for nebula markers (magenta)
  @override
  @JsonKey()
  final int nebulaColor;

  /// Color for star cluster markers (cyan)
  @override
  @JsonKey()
  final int clusterColor;

  /// Color for planetary nebula markers (violet)
  @override
  @JsonKey()
  final int planetaryNebulaColor;

  /// Color for star markers (white)
  @override
  @JsonKey()
  final int starColor;

  /// Color for unknown/other markers (green)
  @override
  @JsonKey()
  final int otherColor;

  /// Stroke width for marker outlines
  @override
  @JsonKey()
  final double strokeWidth;

  /// Font size for labels
  @override
  @JsonKey()
  final double labelFontSize;

  /// Whether to scale markers based on object size
  @override
  @JsonKey()
  final bool scaleBySize;

  /// Minimum marker size in pixels
  @override
  @JsonKey()
  final double minMarkerSize;

  /// Maximum marker size in pixels
  @override
  @JsonKey()
  final double maxMarkerSize;

  @override
  String toString() {
    return 'AnnotationMarkerStyle(galaxyColor: $galaxyColor, nebulaColor: $nebulaColor, clusterColor: $clusterColor, planetaryNebulaColor: $planetaryNebulaColor, starColor: $starColor, otherColor: $otherColor, strokeWidth: $strokeWidth, labelFontSize: $labelFontSize, scaleBySize: $scaleBySize, minMarkerSize: $minMarkerSize, maxMarkerSize: $maxMarkerSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AnnotationMarkerStyleImpl &&
            (identical(other.galaxyColor, galaxyColor) ||
                other.galaxyColor == galaxyColor) &&
            (identical(other.nebulaColor, nebulaColor) ||
                other.nebulaColor == nebulaColor) &&
            (identical(other.clusterColor, clusterColor) ||
                other.clusterColor == clusterColor) &&
            (identical(other.planetaryNebulaColor, planetaryNebulaColor) ||
                other.planetaryNebulaColor == planetaryNebulaColor) &&
            (identical(other.starColor, starColor) ||
                other.starColor == starColor) &&
            (identical(other.otherColor, otherColor) ||
                other.otherColor == otherColor) &&
            (identical(other.strokeWidth, strokeWidth) ||
                other.strokeWidth == strokeWidth) &&
            (identical(other.labelFontSize, labelFontSize) ||
                other.labelFontSize == labelFontSize) &&
            (identical(other.scaleBySize, scaleBySize) ||
                other.scaleBySize == scaleBySize) &&
            (identical(other.minMarkerSize, minMarkerSize) ||
                other.minMarkerSize == minMarkerSize) &&
            (identical(other.maxMarkerSize, maxMarkerSize) ||
                other.maxMarkerSize == maxMarkerSize));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      galaxyColor,
      nebulaColor,
      clusterColor,
      planetaryNebulaColor,
      starColor,
      otherColor,
      strokeWidth,
      labelFontSize,
      scaleBySize,
      minMarkerSize,
      maxMarkerSize);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AnnotationMarkerStyleImplCopyWith<_$AnnotationMarkerStyleImpl>
      get copyWith => __$$AnnotationMarkerStyleImplCopyWithImpl<
          _$AnnotationMarkerStyleImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AnnotationMarkerStyleImplToJson(
      this,
    );
  }
}

abstract class _AnnotationMarkerStyle implements AnnotationMarkerStyle {
  const factory _AnnotationMarkerStyle(
      {final int galaxyColor,
      final int nebulaColor,
      final int clusterColor,
      final int planetaryNebulaColor,
      final int starColor,
      final int otherColor,
      final double strokeWidth,
      final double labelFontSize,
      final bool scaleBySize,
      final double minMarkerSize,
      final double maxMarkerSize}) = _$AnnotationMarkerStyleImpl;

  factory _AnnotationMarkerStyle.fromJson(Map<String, dynamic> json) =
      _$AnnotationMarkerStyleImpl.fromJson;

  @override

  /// Color for galaxy markers (gold)
  int get galaxyColor;
  @override

  /// Color for nebula markers (magenta)
  int get nebulaColor;
  @override

  /// Color for star cluster markers (cyan)
  int get clusterColor;
  @override

  /// Color for planetary nebula markers (violet)
  int get planetaryNebulaColor;
  @override

  /// Color for star markers (white)
  int get starColor;
  @override

  /// Color for unknown/other markers (green)
  int get otherColor;
  @override

  /// Stroke width for marker outlines
  double get strokeWidth;
  @override

  /// Font size for labels
  double get labelFontSize;
  @override

  /// Whether to scale markers based on object size
  bool get scaleBySize;
  @override

  /// Minimum marker size in pixels
  double get minMarkerSize;
  @override

  /// Maximum marker size in pixels
  double get maxMarkerSize;
  @override
  @JsonKey(ignore: true)
  _$$AnnotationMarkerStyleImplCopyWith<_$AnnotationMarkerStyleImpl>
      get copyWith => throw _privateConstructorUsedError;
}

AnnotationPreset _$AnnotationPresetFromJson(Map<String, dynamic> json) {
  return _AnnotationPreset.fromJson(json);
}

/// @nodoc
mixin _$AnnotationPreset {
  String get name => throw _privateConstructorUsedError;
  Set<AnnotationObjectFilter> get visibleTypes =>
      throw _privateConstructorUsedError;
  double get minMagnitude => throw _privateConstructorUsedError;
  double get magnitudeCutoff => throw _privateConstructorUsedError;
  bool get showLabels => throw _privateConstructorUsedError;
  bool get showMagnitudes => throw _privateConstructorUsedError;
  bool get isBuiltIn => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AnnotationPresetCopyWith<AnnotationPreset> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AnnotationPresetCopyWith<$Res> {
  factory $AnnotationPresetCopyWith(
          AnnotationPreset value, $Res Function(AnnotationPreset) then) =
      _$AnnotationPresetCopyWithImpl<$Res, AnnotationPreset>;
  @useResult
  $Res call(
      {String name,
      Set<AnnotationObjectFilter> visibleTypes,
      double minMagnitude,
      double magnitudeCutoff,
      bool showLabels,
      bool showMagnitudes,
      bool isBuiltIn});
}

/// @nodoc
class _$AnnotationPresetCopyWithImpl<$Res, $Val extends AnnotationPreset>
    implements $AnnotationPresetCopyWith<$Res> {
  _$AnnotationPresetCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? visibleTypes = null,
    Object? minMagnitude = null,
    Object? magnitudeCutoff = null,
    Object? showLabels = null,
    Object? showMagnitudes = null,
    Object? isBuiltIn = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      visibleTypes: null == visibleTypes
          ? _value.visibleTypes
          : visibleTypes // ignore: cast_nullable_to_non_nullable
              as Set<AnnotationObjectFilter>,
      minMagnitude: null == minMagnitude
          ? _value.minMagnitude
          : minMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      magnitudeCutoff: null == magnitudeCutoff
          ? _value.magnitudeCutoff
          : magnitudeCutoff // ignore: cast_nullable_to_non_nullable
              as double,
      showLabels: null == showLabels
          ? _value.showLabels
          : showLabels // ignore: cast_nullable_to_non_nullable
              as bool,
      showMagnitudes: null == showMagnitudes
          ? _value.showMagnitudes
          : showMagnitudes // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuiltIn: null == isBuiltIn
          ? _value.isBuiltIn
          : isBuiltIn // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AnnotationPresetImplCopyWith<$Res>
    implements $AnnotationPresetCopyWith<$Res> {
  factory _$$AnnotationPresetImplCopyWith(_$AnnotationPresetImpl value,
          $Res Function(_$AnnotationPresetImpl) then) =
      __$$AnnotationPresetImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      Set<AnnotationObjectFilter> visibleTypes,
      double minMagnitude,
      double magnitudeCutoff,
      bool showLabels,
      bool showMagnitudes,
      bool isBuiltIn});
}

/// @nodoc
class __$$AnnotationPresetImplCopyWithImpl<$Res>
    extends _$AnnotationPresetCopyWithImpl<$Res, _$AnnotationPresetImpl>
    implements _$$AnnotationPresetImplCopyWith<$Res> {
  __$$AnnotationPresetImplCopyWithImpl(_$AnnotationPresetImpl _value,
      $Res Function(_$AnnotationPresetImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? visibleTypes = null,
    Object? minMagnitude = null,
    Object? magnitudeCutoff = null,
    Object? showLabels = null,
    Object? showMagnitudes = null,
    Object? isBuiltIn = null,
  }) {
    return _then(_$AnnotationPresetImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      visibleTypes: null == visibleTypes
          ? _value._visibleTypes
          : visibleTypes // ignore: cast_nullable_to_non_nullable
              as Set<AnnotationObjectFilter>,
      minMagnitude: null == minMagnitude
          ? _value.minMagnitude
          : minMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      magnitudeCutoff: null == magnitudeCutoff
          ? _value.magnitudeCutoff
          : magnitudeCutoff // ignore: cast_nullable_to_non_nullable
              as double,
      showLabels: null == showLabels
          ? _value.showLabels
          : showLabels // ignore: cast_nullable_to_non_nullable
              as bool,
      showMagnitudes: null == showMagnitudes
          ? _value.showMagnitudes
          : showMagnitudes // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuiltIn: null == isBuiltIn
          ? _value.isBuiltIn
          : isBuiltIn // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AnnotationPresetImpl implements _AnnotationPreset {
  const _$AnnotationPresetImpl(
      {required this.name,
      required final Set<AnnotationObjectFilter> visibleTypes,
      required this.minMagnitude,
      required this.magnitudeCutoff,
      required this.showLabels,
      required this.showMagnitudes,
      this.isBuiltIn = false})
      : _visibleTypes = visibleTypes;

  factory _$AnnotationPresetImpl.fromJson(Map<String, dynamic> json) =>
      _$$AnnotationPresetImplFromJson(json);

  @override
  final String name;
  final Set<AnnotationObjectFilter> _visibleTypes;
  @override
  Set<AnnotationObjectFilter> get visibleTypes {
    if (_visibleTypes is EqualUnmodifiableSetView) return _visibleTypes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_visibleTypes);
  }

  @override
  final double minMagnitude;
  @override
  final double magnitudeCutoff;
  @override
  final bool showLabels;
  @override
  final bool showMagnitudes;
  @override
  @JsonKey()
  final bool isBuiltIn;

  @override
  String toString() {
    return 'AnnotationPreset(name: $name, visibleTypes: $visibleTypes, minMagnitude: $minMagnitude, magnitudeCutoff: $magnitudeCutoff, showLabels: $showLabels, showMagnitudes: $showMagnitudes, isBuiltIn: $isBuiltIn)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AnnotationPresetImpl &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._visibleTypes, _visibleTypes) &&
            (identical(other.minMagnitude, minMagnitude) ||
                other.minMagnitude == minMagnitude) &&
            (identical(other.magnitudeCutoff, magnitudeCutoff) ||
                other.magnitudeCutoff == magnitudeCutoff) &&
            (identical(other.showLabels, showLabels) ||
                other.showLabels == showLabels) &&
            (identical(other.showMagnitudes, showMagnitudes) ||
                other.showMagnitudes == showMagnitudes) &&
            (identical(other.isBuiltIn, isBuiltIn) ||
                other.isBuiltIn == isBuiltIn));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      name,
      const DeepCollectionEquality().hash(_visibleTypes),
      minMagnitude,
      magnitudeCutoff,
      showLabels,
      showMagnitudes,
      isBuiltIn);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AnnotationPresetImplCopyWith<_$AnnotationPresetImpl> get copyWith =>
      __$$AnnotationPresetImplCopyWithImpl<_$AnnotationPresetImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AnnotationPresetImplToJson(
      this,
    );
  }
}

abstract class _AnnotationPreset implements AnnotationPreset {
  const factory _AnnotationPreset(
      {required final String name,
      required final Set<AnnotationObjectFilter> visibleTypes,
      required final double minMagnitude,
      required final double magnitudeCutoff,
      required final bool showLabels,
      required final bool showMagnitudes,
      final bool isBuiltIn}) = _$AnnotationPresetImpl;

  factory _AnnotationPreset.fromJson(Map<String, dynamic> json) =
      _$AnnotationPresetImpl.fromJson;

  @override
  String get name;
  @override
  Set<AnnotationObjectFilter> get visibleTypes;
  @override
  double get minMagnitude;
  @override
  double get magnitudeCutoff;
  @override
  bool get showLabels;
  @override
  bool get showMagnitudes;
  @override
  bool get isBuiltIn;
  @override
  @JsonKey(ignore: true)
  _$$AnnotationPresetImplCopyWith<_$AnnotationPresetImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CustomAnnotation _$CustomAnnotationFromJson(Map<String, dynamic> json) {
  return _CustomAnnotation.fromJson(json);
}

/// @nodoc
mixin _$CustomAnnotation {
  String get id => throw _privateConstructorUsedError;
  CustomAnnotationType get type => throw _privateConstructorUsedError;

  /// Image pixel X of the anchor point (center for circles, start for arrows, position for text)
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;

  /// For circles: radius in pixels. For arrows: end X.
  double? get x2 => throw _privateConstructorUsedError;

  /// For arrows: end Y.
  double? get y2 => throw _privateConstructorUsedError;

  /// For circles: radius in pixels.
  double? get radius => throw _privateConstructorUsedError;

  /// Label text
  String get label => throw _privateConstructorUsedError;

  /// Color as ARGB int
  int get color => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CustomAnnotationCopyWith<CustomAnnotation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CustomAnnotationCopyWith<$Res> {
  factory $CustomAnnotationCopyWith(
          CustomAnnotation value, $Res Function(CustomAnnotation) then) =
      _$CustomAnnotationCopyWithImpl<$Res, CustomAnnotation>;
  @useResult
  $Res call(
      {String id,
      CustomAnnotationType type,
      double x,
      double y,
      double? x2,
      double? y2,
      double? radius,
      String label,
      int color});
}

/// @nodoc
class _$CustomAnnotationCopyWithImpl<$Res, $Val extends CustomAnnotation>
    implements $CustomAnnotationCopyWith<$Res> {
  _$CustomAnnotationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? x = null,
    Object? y = null,
    Object? x2 = freezed,
    Object? y2 = freezed,
    Object? radius = freezed,
    Object? label = null,
    Object? color = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as CustomAnnotationType,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      x2: freezed == x2
          ? _value.x2
          : x2 // ignore: cast_nullable_to_non_nullable
              as double?,
      y2: freezed == y2
          ? _value.y2
          : y2 // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CustomAnnotationImplCopyWith<$Res>
    implements $CustomAnnotationCopyWith<$Res> {
  factory _$$CustomAnnotationImplCopyWith(_$CustomAnnotationImpl value,
          $Res Function(_$CustomAnnotationImpl) then) =
      __$$CustomAnnotationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      CustomAnnotationType type,
      double x,
      double y,
      double? x2,
      double? y2,
      double? radius,
      String label,
      int color});
}

/// @nodoc
class __$$CustomAnnotationImplCopyWithImpl<$Res>
    extends _$CustomAnnotationCopyWithImpl<$Res, _$CustomAnnotationImpl>
    implements _$$CustomAnnotationImplCopyWith<$Res> {
  __$$CustomAnnotationImplCopyWithImpl(_$CustomAnnotationImpl _value,
      $Res Function(_$CustomAnnotationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? x = null,
    Object? y = null,
    Object? x2 = freezed,
    Object? y2 = freezed,
    Object? radius = freezed,
    Object? label = null,
    Object? color = null,
  }) {
    return _then(_$CustomAnnotationImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as CustomAnnotationType,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      x2: freezed == x2
          ? _value.x2
          : x2 // ignore: cast_nullable_to_non_nullable
              as double?,
      y2: freezed == y2
          ? _value.y2
          : y2 // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CustomAnnotationImpl implements _CustomAnnotation {
  const _$CustomAnnotationImpl(
      {required this.id,
      required this.type,
      required this.x,
      required this.y,
      this.x2,
      this.y2,
      this.radius,
      this.label = '',
      this.color = 0xFFFF6B6B});

  factory _$CustomAnnotationImpl.fromJson(Map<String, dynamic> json) =>
      _$$CustomAnnotationImplFromJson(json);

  @override
  final String id;
  @override
  final CustomAnnotationType type;

  /// Image pixel X of the anchor point (center for circles, start for arrows, position for text)
  @override
  final double x;
  @override
  final double y;

  /// For circles: radius in pixels. For arrows: end X.
  @override
  final double? x2;

  /// For arrows: end Y.
  @override
  final double? y2;

  /// For circles: radius in pixels.
  @override
  final double? radius;

  /// Label text
  @override
  @JsonKey()
  final String label;

  /// Color as ARGB int
  @override
  @JsonKey()
  final int color;

  @override
  String toString() {
    return 'CustomAnnotation(id: $id, type: $type, x: $x, y: $y, x2: $x2, y2: $y2, radius: $radius, label: $label, color: $color)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CustomAnnotationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.x2, x2) || other.x2 == x2) &&
            (identical(other.y2, y2) || other.y2 == y2) &&
            (identical(other.radius, radius) || other.radius == radius) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.color, color) || other.color == color));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, type, x, y, x2, y2, radius, label, color);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CustomAnnotationImplCopyWith<_$CustomAnnotationImpl> get copyWith =>
      __$$CustomAnnotationImplCopyWithImpl<_$CustomAnnotationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CustomAnnotationImplToJson(
      this,
    );
  }
}

abstract class _CustomAnnotation implements CustomAnnotation {
  const factory _CustomAnnotation(
      {required final String id,
      required final CustomAnnotationType type,
      required final double x,
      required final double y,
      final double? x2,
      final double? y2,
      final double? radius,
      final String label,
      final int color}) = _$CustomAnnotationImpl;

  factory _CustomAnnotation.fromJson(Map<String, dynamic> json) =
      _$CustomAnnotationImpl.fromJson;

  @override
  String get id;
  @override
  CustomAnnotationType get type;
  @override

  /// Image pixel X of the anchor point (center for circles, start for arrows, position for text)
  double get x;
  @override
  double get y;
  @override

  /// For circles: radius in pixels. For arrows: end X.
  double? get x2;
  @override

  /// For arrows: end Y.
  double? get y2;
  @override

  /// For circles: radius in pixels.
  double? get radius;
  @override

  /// Label text
  String get label;
  @override

  /// Color as ARGB int
  int get color;
  @override
  @JsonKey(ignore: true)
  _$$CustomAnnotationImplCopyWith<_$CustomAnnotationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
