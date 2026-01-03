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
      int maxObjectsToDisplay});
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
      int maxObjectsToDisplay});
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
      this.maxObjectsToDisplay = 500})
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

  @override
  String toString() {
    return 'AnnotationSettings(enabled: $enabled, magnitudeCutoff: $magnitudeCutoff, minMagnitude: $minMagnitude, visibleTypes: $visibleTypes, showLabels: $showLabels, showMagnitudes: $showMagnitudes, fadeWhenNotHovering: $fadeWhenNotHovering, hoverOpacity: $hoverOpacity, idleOpacity: $idleOpacity, fadeAnimationMs: $fadeAnimationMs, clickToIdentify: $clickToIdentify, clickSearchRadiusArcsec: $clickSearchRadiusArcsec, autoAnnotate: $autoAnnotate, maxObjectsToDisplay: $maxObjectsToDisplay)';
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
                other.maxObjectsToDisplay == maxObjectsToDisplay));
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
      maxObjectsToDisplay);

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
      final int maxObjectsToDisplay}) = _$AnnotationSettingsImpl;

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
