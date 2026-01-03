// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'radar_frame.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RadarFrame _$RadarFrameFromJson(Map<String, dynamic> json) {
  return _RadarFrame.fromJson(json);
}

/// @nodoc
mixin _$RadarFrame {
  /// When this radar frame was captured
  DateTime get timestamp => throw _privateConstructorUsedError;

  /// URL template for map tiles
  /// - For XYZ: template with {z}/{x}/{y} placeholders
  /// - For WMS: base URL (without bbox parameter)
  String get tileUrlTemplate => throw _privateConstructorUsedError;

  /// Geographic bounds - northern boundary
  double get north => throw _privateConstructorUsedError;

  /// Geographic bounds - southern boundary
  double get south => throw _privateConstructorUsedError;

  /// Geographic bounds - eastern boundary
  double get east => throw _privateConstructorUsedError;

  /// Geographic bounds - western boundary
  double get west => throw _privateConstructorUsedError;

  /// Opacity for animation blending (0.0-1.0)
  double get opacity => throw _privateConstructorUsedError;

  /// True if this is a forecast frame vs historical
  bool get isForecast => throw _privateConstructorUsedError;

  /// Type of tile service (XYZ or WMS)
  RadarTileType get tileType => throw _privateConstructorUsedError;

  /// WMS layer name(s) - only used when tileType is wms
  String? get wmsLayers => throw _privateConstructorUsedError;

  /// Additional WMS parameters (e.g., time, styles) - only used when tileType is wms
  Map<String, String>? get wmsAdditionalOptions =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $RadarFrameCopyWith<RadarFrame> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RadarFrameCopyWith<$Res> {
  factory $RadarFrameCopyWith(
          RadarFrame value, $Res Function(RadarFrame) then) =
      _$RadarFrameCopyWithImpl<$Res, RadarFrame>;
  @useResult
  $Res call(
      {DateTime timestamp,
      String tileUrlTemplate,
      double north,
      double south,
      double east,
      double west,
      double opacity,
      bool isForecast,
      RadarTileType tileType,
      String? wmsLayers,
      Map<String, String>? wmsAdditionalOptions});
}

/// @nodoc
class _$RadarFrameCopyWithImpl<$Res, $Val extends RadarFrame>
    implements $RadarFrameCopyWith<$Res> {
  _$RadarFrameCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? tileUrlTemplate = null,
    Object? north = null,
    Object? south = null,
    Object? east = null,
    Object? west = null,
    Object? opacity = null,
    Object? isForecast = null,
    Object? tileType = null,
    Object? wmsLayers = freezed,
    Object? wmsAdditionalOptions = freezed,
  }) {
    return _then(_value.copyWith(
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      tileUrlTemplate: null == tileUrlTemplate
          ? _value.tileUrlTemplate
          : tileUrlTemplate // ignore: cast_nullable_to_non_nullable
              as String,
      north: null == north
          ? _value.north
          : north // ignore: cast_nullable_to_non_nullable
              as double,
      south: null == south
          ? _value.south
          : south // ignore: cast_nullable_to_non_nullable
              as double,
      east: null == east
          ? _value.east
          : east // ignore: cast_nullable_to_non_nullable
              as double,
      west: null == west
          ? _value.west
          : west // ignore: cast_nullable_to_non_nullable
              as double,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      isForecast: null == isForecast
          ? _value.isForecast
          : isForecast // ignore: cast_nullable_to_non_nullable
              as bool,
      tileType: null == tileType
          ? _value.tileType
          : tileType // ignore: cast_nullable_to_non_nullable
              as RadarTileType,
      wmsLayers: freezed == wmsLayers
          ? _value.wmsLayers
          : wmsLayers // ignore: cast_nullable_to_non_nullable
              as String?,
      wmsAdditionalOptions: freezed == wmsAdditionalOptions
          ? _value.wmsAdditionalOptions
          : wmsAdditionalOptions // ignore: cast_nullable_to_non_nullable
              as Map<String, String>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RadarFrameImplCopyWith<$Res>
    implements $RadarFrameCopyWith<$Res> {
  factory _$$RadarFrameImplCopyWith(
          _$RadarFrameImpl value, $Res Function(_$RadarFrameImpl) then) =
      __$$RadarFrameImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {DateTime timestamp,
      String tileUrlTemplate,
      double north,
      double south,
      double east,
      double west,
      double opacity,
      bool isForecast,
      RadarTileType tileType,
      String? wmsLayers,
      Map<String, String>? wmsAdditionalOptions});
}

/// @nodoc
class __$$RadarFrameImplCopyWithImpl<$Res>
    extends _$RadarFrameCopyWithImpl<$Res, _$RadarFrameImpl>
    implements _$$RadarFrameImplCopyWith<$Res> {
  __$$RadarFrameImplCopyWithImpl(
      _$RadarFrameImpl _value, $Res Function(_$RadarFrameImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? tileUrlTemplate = null,
    Object? north = null,
    Object? south = null,
    Object? east = null,
    Object? west = null,
    Object? opacity = null,
    Object? isForecast = null,
    Object? tileType = null,
    Object? wmsLayers = freezed,
    Object? wmsAdditionalOptions = freezed,
  }) {
    return _then(_$RadarFrameImpl(
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      tileUrlTemplate: null == tileUrlTemplate
          ? _value.tileUrlTemplate
          : tileUrlTemplate // ignore: cast_nullable_to_non_nullable
              as String,
      north: null == north
          ? _value.north
          : north // ignore: cast_nullable_to_non_nullable
              as double,
      south: null == south
          ? _value.south
          : south // ignore: cast_nullable_to_non_nullable
              as double,
      east: null == east
          ? _value.east
          : east // ignore: cast_nullable_to_non_nullable
              as double,
      west: null == west
          ? _value.west
          : west // ignore: cast_nullable_to_non_nullable
              as double,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      isForecast: null == isForecast
          ? _value.isForecast
          : isForecast // ignore: cast_nullable_to_non_nullable
              as bool,
      tileType: null == tileType
          ? _value.tileType
          : tileType // ignore: cast_nullable_to_non_nullable
              as RadarTileType,
      wmsLayers: freezed == wmsLayers
          ? _value.wmsLayers
          : wmsLayers // ignore: cast_nullable_to_non_nullable
              as String?,
      wmsAdditionalOptions: freezed == wmsAdditionalOptions
          ? _value._wmsAdditionalOptions
          : wmsAdditionalOptions // ignore: cast_nullable_to_non_nullable
              as Map<String, String>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RadarFrameImpl implements _RadarFrame {
  const _$RadarFrameImpl(
      {required this.timestamp,
      required this.tileUrlTemplate,
      required this.north,
      required this.south,
      required this.east,
      required this.west,
      this.opacity = 1.0,
      this.isForecast = false,
      this.tileType = RadarTileType.xyz,
      this.wmsLayers,
      final Map<String, String>? wmsAdditionalOptions})
      : _wmsAdditionalOptions = wmsAdditionalOptions;

  factory _$RadarFrameImpl.fromJson(Map<String, dynamic> json) =>
      _$$RadarFrameImplFromJson(json);

  /// When this radar frame was captured
  @override
  final DateTime timestamp;

  /// URL template for map tiles
  /// - For XYZ: template with {z}/{x}/{y} placeholders
  /// - For WMS: base URL (without bbox parameter)
  @override
  final String tileUrlTemplate;

  /// Geographic bounds - northern boundary
  @override
  final double north;

  /// Geographic bounds - southern boundary
  @override
  final double south;

  /// Geographic bounds - eastern boundary
  @override
  final double east;

  /// Geographic bounds - western boundary
  @override
  final double west;

  /// Opacity for animation blending (0.0-1.0)
  @override
  @JsonKey()
  final double opacity;

  /// True if this is a forecast frame vs historical
  @override
  @JsonKey()
  final bool isForecast;

  /// Type of tile service (XYZ or WMS)
  @override
  @JsonKey()
  final RadarTileType tileType;

  /// WMS layer name(s) - only used when tileType is wms
  @override
  final String? wmsLayers;

  /// Additional WMS parameters (e.g., time, styles) - only used when tileType is wms
  final Map<String, String>? _wmsAdditionalOptions;

  /// Additional WMS parameters (e.g., time, styles) - only used when tileType is wms
  @override
  Map<String, String>? get wmsAdditionalOptions {
    final value = _wmsAdditionalOptions;
    if (value == null) return null;
    if (_wmsAdditionalOptions is EqualUnmodifiableMapView)
      return _wmsAdditionalOptions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'RadarFrame(timestamp: $timestamp, tileUrlTemplate: $tileUrlTemplate, north: $north, south: $south, east: $east, west: $west, opacity: $opacity, isForecast: $isForecast, tileType: $tileType, wmsLayers: $wmsLayers, wmsAdditionalOptions: $wmsAdditionalOptions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RadarFrameImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.tileUrlTemplate, tileUrlTemplate) ||
                other.tileUrlTemplate == tileUrlTemplate) &&
            (identical(other.north, north) || other.north == north) &&
            (identical(other.south, south) || other.south == south) &&
            (identical(other.east, east) || other.east == east) &&
            (identical(other.west, west) || other.west == west) &&
            (identical(other.opacity, opacity) || other.opacity == opacity) &&
            (identical(other.isForecast, isForecast) ||
                other.isForecast == isForecast) &&
            (identical(other.tileType, tileType) ||
                other.tileType == tileType) &&
            (identical(other.wmsLayers, wmsLayers) ||
                other.wmsLayers == wmsLayers) &&
            const DeepCollectionEquality()
                .equals(other._wmsAdditionalOptions, _wmsAdditionalOptions));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      timestamp,
      tileUrlTemplate,
      north,
      south,
      east,
      west,
      opacity,
      isForecast,
      tileType,
      wmsLayers,
      const DeepCollectionEquality().hash(_wmsAdditionalOptions));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$RadarFrameImplCopyWith<_$RadarFrameImpl> get copyWith =>
      __$$RadarFrameImplCopyWithImpl<_$RadarFrameImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RadarFrameImplToJson(
      this,
    );
  }
}

abstract class _RadarFrame implements RadarFrame {
  const factory _RadarFrame(
      {required final DateTime timestamp,
      required final String tileUrlTemplate,
      required final double north,
      required final double south,
      required final double east,
      required final double west,
      final double opacity,
      final bool isForecast,
      final RadarTileType tileType,
      final String? wmsLayers,
      final Map<String, String>? wmsAdditionalOptions}) = _$RadarFrameImpl;

  factory _RadarFrame.fromJson(Map<String, dynamic> json) =
      _$RadarFrameImpl.fromJson;

  @override

  /// When this radar frame was captured
  DateTime get timestamp;
  @override

  /// URL template for map tiles
  /// - For XYZ: template with {z}/{x}/{y} placeholders
  /// - For WMS: base URL (without bbox parameter)
  String get tileUrlTemplate;
  @override

  /// Geographic bounds - northern boundary
  double get north;
  @override

  /// Geographic bounds - southern boundary
  double get south;
  @override

  /// Geographic bounds - eastern boundary
  double get east;
  @override

  /// Geographic bounds - western boundary
  double get west;
  @override

  /// Opacity for animation blending (0.0-1.0)
  double get opacity;
  @override

  /// True if this is a forecast frame vs historical
  bool get isForecast;
  @override

  /// Type of tile service (XYZ or WMS)
  RadarTileType get tileType;
  @override

  /// WMS layer name(s) - only used when tileType is wms
  String? get wmsLayers;
  @override

  /// Additional WMS parameters (e.g., time, styles) - only used when tileType is wms
  Map<String, String>? get wmsAdditionalOptions;
  @override
  @JsonKey(ignore: true)
  _$$RadarFrameImplCopyWith<_$RadarFrameImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
