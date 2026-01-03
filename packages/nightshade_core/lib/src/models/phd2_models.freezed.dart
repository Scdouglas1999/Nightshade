// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'phd2_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Phd2StarImage _$Phd2StarImageFromJson(Map<String, dynamic> json) {
  return _Phd2StarImage.fromJson(json);
}

/// @nodoc
mixin _$Phd2StarImage {
  /// Frame number
  int get frame => throw _privateConstructorUsedError;

  /// Image width in pixels
  int get width => throw _privateConstructorUsedError;

  /// Image height in pixels
  int get height => throw _privateConstructorUsedError;

  /// Star centroid X position within the subframe
  double get starX => throw _privateConstructorUsedError;

  /// Star centroid Y position within the subframe
  double get starY => throw _privateConstructorUsedError;

  /// Raw pixel data (16-bit grayscale, row-major order)
  /// Note: This is stored as Uint8List but represents 16-bit values
  @Uint8ListConverter()
  Uint8List get pixels => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $Phd2StarImageCopyWith<Phd2StarImage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $Phd2StarImageCopyWith<$Res> {
  factory $Phd2StarImageCopyWith(
          Phd2StarImage value, $Res Function(Phd2StarImage) then) =
      _$Phd2StarImageCopyWithImpl<$Res, Phd2StarImage>;
  @useResult
  $Res call(
      {int frame,
      int width,
      int height,
      double starX,
      double starY,
      @Uint8ListConverter() Uint8List pixels});
}

/// @nodoc
class _$Phd2StarImageCopyWithImpl<$Res, $Val extends Phd2StarImage>
    implements $Phd2StarImageCopyWith<$Res> {
  _$Phd2StarImageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? frame = null,
    Object? width = null,
    Object? height = null,
    Object? starX = null,
    Object? starY = null,
    Object? pixels = null,
  }) {
    return _then(_value.copyWith(
      frame: null == frame
          ? _value.frame
          : frame // ignore: cast_nullable_to_non_nullable
              as int,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int,
      starX: null == starX
          ? _value.starX
          : starX // ignore: cast_nullable_to_non_nullable
              as double,
      starY: null == starY
          ? _value.starY
          : starY // ignore: cast_nullable_to_non_nullable
              as double,
      pixels: null == pixels
          ? _value.pixels
          : pixels // ignore: cast_nullable_to_non_nullable
              as Uint8List,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$Phd2StarImageImplCopyWith<$Res>
    implements $Phd2StarImageCopyWith<$Res> {
  factory _$$Phd2StarImageImplCopyWith(
          _$Phd2StarImageImpl value, $Res Function(_$Phd2StarImageImpl) then) =
      __$$Phd2StarImageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int frame,
      int width,
      int height,
      double starX,
      double starY,
      @Uint8ListConverter() Uint8List pixels});
}

/// @nodoc
class __$$Phd2StarImageImplCopyWithImpl<$Res>
    extends _$Phd2StarImageCopyWithImpl<$Res, _$Phd2StarImageImpl>
    implements _$$Phd2StarImageImplCopyWith<$Res> {
  __$$Phd2StarImageImplCopyWithImpl(
      _$Phd2StarImageImpl _value, $Res Function(_$Phd2StarImageImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? frame = null,
    Object? width = null,
    Object? height = null,
    Object? starX = null,
    Object? starY = null,
    Object? pixels = null,
  }) {
    return _then(_$Phd2StarImageImpl(
      frame: null == frame
          ? _value.frame
          : frame // ignore: cast_nullable_to_non_nullable
              as int,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int,
      starX: null == starX
          ? _value.starX
          : starX // ignore: cast_nullable_to_non_nullable
              as double,
      starY: null == starY
          ? _value.starY
          : starY // ignore: cast_nullable_to_non_nullable
              as double,
      pixels: null == pixels
          ? _value.pixels
          : pixels // ignore: cast_nullable_to_non_nullable
              as Uint8List,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$Phd2StarImageImpl implements _Phd2StarImage {
  const _$Phd2StarImageImpl(
      {required this.frame,
      required this.width,
      required this.height,
      required this.starX,
      required this.starY,
      @Uint8ListConverter() required this.pixels});

  factory _$Phd2StarImageImpl.fromJson(Map<String, dynamic> json) =>
      _$$Phd2StarImageImplFromJson(json);

  /// Frame number
  @override
  final int frame;

  /// Image width in pixels
  @override
  final int width;

  /// Image height in pixels
  @override
  final int height;

  /// Star centroid X position within the subframe
  @override
  final double starX;

  /// Star centroid Y position within the subframe
  @override
  final double starY;

  /// Raw pixel data (16-bit grayscale, row-major order)
  /// Note: This is stored as Uint8List but represents 16-bit values
  @override
  @Uint8ListConverter()
  final Uint8List pixels;

  @override
  String toString() {
    return 'Phd2StarImage(frame: $frame, width: $width, height: $height, starX: $starX, starY: $starY, pixels: $pixels)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Phd2StarImageImpl &&
            (identical(other.frame, frame) || other.frame == frame) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.starX, starX) || other.starX == starX) &&
            (identical(other.starY, starY) || other.starY == starY) &&
            const DeepCollectionEquality().equals(other.pixels, pixels));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, frame, width, height, starX,
      starY, const DeepCollectionEquality().hash(pixels));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$Phd2StarImageImplCopyWith<_$Phd2StarImageImpl> get copyWith =>
      __$$Phd2StarImageImplCopyWithImpl<_$Phd2StarImageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$Phd2StarImageImplToJson(
      this,
    );
  }
}

abstract class _Phd2StarImage implements Phd2StarImage {
  const factory _Phd2StarImage(
          {required final int frame,
          required final int width,
          required final int height,
          required final double starX,
          required final double starY,
          @Uint8ListConverter() required final Uint8List pixels}) =
      _$Phd2StarImageImpl;

  factory _Phd2StarImage.fromJson(Map<String, dynamic> json) =
      _$Phd2StarImageImpl.fromJson;

  @override

  /// Frame number
  int get frame;
  @override

  /// Image width in pixels
  int get width;
  @override

  /// Image height in pixels
  int get height;
  @override

  /// Star centroid X position within the subframe
  double get starX;
  @override

  /// Star centroid Y position within the subframe
  double get starY;
  @override

  /// Raw pixel data (16-bit grayscale, row-major order)
  /// Note: This is stored as Uint8List but represents 16-bit values
  @Uint8ListConverter()
  Uint8List get pixels;
  @override
  @JsonKey(ignore: true)
  _$$Phd2StarImageImplCopyWith<_$Phd2StarImageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Phd2AlgoParam _$Phd2AlgoParamFromJson(Map<String, dynamic> json) {
  return _Phd2AlgoParam.fromJson(json);
}

/// @nodoc
mixin _$Phd2AlgoParam {
  /// Parameter name (e.g., "Aggressiveness", "Hysteresis")
  String get name => throw _privateConstructorUsedError;

  /// Parameter value
  double get value => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $Phd2AlgoParamCopyWith<Phd2AlgoParam> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $Phd2AlgoParamCopyWith<$Res> {
  factory $Phd2AlgoParamCopyWith(
          Phd2AlgoParam value, $Res Function(Phd2AlgoParam) then) =
      _$Phd2AlgoParamCopyWithImpl<$Res, Phd2AlgoParam>;
  @useResult
  $Res call({String name, double value});
}

/// @nodoc
class _$Phd2AlgoParamCopyWithImpl<$Res, $Val extends Phd2AlgoParam>
    implements $Phd2AlgoParamCopyWith<$Res> {
  _$Phd2AlgoParamCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? value = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$Phd2AlgoParamImplCopyWith<$Res>
    implements $Phd2AlgoParamCopyWith<$Res> {
  factory _$$Phd2AlgoParamImplCopyWith(
          _$Phd2AlgoParamImpl value, $Res Function(_$Phd2AlgoParamImpl) then) =
      __$$Phd2AlgoParamImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, double value});
}

/// @nodoc
class __$$Phd2AlgoParamImplCopyWithImpl<$Res>
    extends _$Phd2AlgoParamCopyWithImpl<$Res, _$Phd2AlgoParamImpl>
    implements _$$Phd2AlgoParamImplCopyWith<$Res> {
  __$$Phd2AlgoParamImplCopyWithImpl(
      _$Phd2AlgoParamImpl _value, $Res Function(_$Phd2AlgoParamImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? value = null,
  }) {
    return _then(_$Phd2AlgoParamImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$Phd2AlgoParamImpl implements _Phd2AlgoParam {
  const _$Phd2AlgoParamImpl({required this.name, required this.value});

  factory _$Phd2AlgoParamImpl.fromJson(Map<String, dynamic> json) =>
      _$$Phd2AlgoParamImplFromJson(json);

  /// Parameter name (e.g., "Aggressiveness", "Hysteresis")
  @override
  final String name;

  /// Parameter value
  @override
  final double value;

  @override
  String toString() {
    return 'Phd2AlgoParam(name: $name, value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Phd2AlgoParamImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.value, value) || other.value == value));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, name, value);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$Phd2AlgoParamImplCopyWith<_$Phd2AlgoParamImpl> get copyWith =>
      __$$Phd2AlgoParamImplCopyWithImpl<_$Phd2AlgoParamImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$Phd2AlgoParamImplToJson(
      this,
    );
  }
}

abstract class _Phd2AlgoParam implements Phd2AlgoParam {
  const factory _Phd2AlgoParam(
      {required final String name,
      required final double value}) = _$Phd2AlgoParamImpl;

  factory _Phd2AlgoParam.fromJson(Map<String, dynamic> json) =
      _$Phd2AlgoParamImpl.fromJson;

  @override

  /// Parameter name (e.g., "Aggressiveness", "Hysteresis")
  String get name;
  @override

  /// Parameter value
  double get value;
  @override
  @JsonKey(ignore: true)
  _$$Phd2AlgoParamImplCopyWith<_$Phd2AlgoParamImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Phd2BrainParams _$Phd2BrainParamsFromJson(Map<String, dynamic> json) {
  return _Phd2BrainParams.fromJson(json);
}

/// @nodoc
mixin _$Phd2BrainParams {
  /// RA axis parameter names
  List<String> get raParamNames => throw _privateConstructorUsedError;

  /// Dec axis parameter names
  List<String> get decParamNames => throw _privateConstructorUsedError;

  /// RA axis parameters (name -> value)
  Map<String, double> get raParams => throw _privateConstructorUsedError;

  /// Dec axis parameters (name -> value)
  Map<String, double> get decParams => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $Phd2BrainParamsCopyWith<Phd2BrainParams> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $Phd2BrainParamsCopyWith<$Res> {
  factory $Phd2BrainParamsCopyWith(
          Phd2BrainParams value, $Res Function(Phd2BrainParams) then) =
      _$Phd2BrainParamsCopyWithImpl<$Res, Phd2BrainParams>;
  @useResult
  $Res call(
      {List<String> raParamNames,
      List<String> decParamNames,
      Map<String, double> raParams,
      Map<String, double> decParams});
}

/// @nodoc
class _$Phd2BrainParamsCopyWithImpl<$Res, $Val extends Phd2BrainParams>
    implements $Phd2BrainParamsCopyWith<$Res> {
  _$Phd2BrainParamsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? raParamNames = null,
    Object? decParamNames = null,
    Object? raParams = null,
    Object? decParams = null,
  }) {
    return _then(_value.copyWith(
      raParamNames: null == raParamNames
          ? _value.raParamNames
          : raParamNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      decParamNames: null == decParamNames
          ? _value.decParamNames
          : decParamNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      raParams: null == raParams
          ? _value.raParams
          : raParams // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      decParams: null == decParams
          ? _value.decParams
          : decParams // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$Phd2BrainParamsImplCopyWith<$Res>
    implements $Phd2BrainParamsCopyWith<$Res> {
  factory _$$Phd2BrainParamsImplCopyWith(_$Phd2BrainParamsImpl value,
          $Res Function(_$Phd2BrainParamsImpl) then) =
      __$$Phd2BrainParamsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<String> raParamNames,
      List<String> decParamNames,
      Map<String, double> raParams,
      Map<String, double> decParams});
}

/// @nodoc
class __$$Phd2BrainParamsImplCopyWithImpl<$Res>
    extends _$Phd2BrainParamsCopyWithImpl<$Res, _$Phd2BrainParamsImpl>
    implements _$$Phd2BrainParamsImplCopyWith<$Res> {
  __$$Phd2BrainParamsImplCopyWithImpl(
      _$Phd2BrainParamsImpl _value, $Res Function(_$Phd2BrainParamsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? raParamNames = null,
    Object? decParamNames = null,
    Object? raParams = null,
    Object? decParams = null,
  }) {
    return _then(_$Phd2BrainParamsImpl(
      raParamNames: null == raParamNames
          ? _value._raParamNames
          : raParamNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      decParamNames: null == decParamNames
          ? _value._decParamNames
          : decParamNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      raParams: null == raParams
          ? _value._raParams
          : raParams // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      decParams: null == decParams
          ? _value._decParams
          : decParams // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$Phd2BrainParamsImpl implements _Phd2BrainParams {
  const _$Phd2BrainParamsImpl(
      {required final List<String> raParamNames,
      required final List<String> decParamNames,
      required final Map<String, double> raParams,
      required final Map<String, double> decParams})
      : _raParamNames = raParamNames,
        _decParamNames = decParamNames,
        _raParams = raParams,
        _decParams = decParams;

  factory _$Phd2BrainParamsImpl.fromJson(Map<String, dynamic> json) =>
      _$$Phd2BrainParamsImplFromJson(json);

  /// RA axis parameter names
  final List<String> _raParamNames;

  /// RA axis parameter names
  @override
  List<String> get raParamNames {
    if (_raParamNames is EqualUnmodifiableListView) return _raParamNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_raParamNames);
  }

  /// Dec axis parameter names
  final List<String> _decParamNames;

  /// Dec axis parameter names
  @override
  List<String> get decParamNames {
    if (_decParamNames is EqualUnmodifiableListView) return _decParamNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_decParamNames);
  }

  /// RA axis parameters (name -> value)
  final Map<String, double> _raParams;

  /// RA axis parameters (name -> value)
  @override
  Map<String, double> get raParams {
    if (_raParams is EqualUnmodifiableMapView) return _raParams;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_raParams);
  }

  /// Dec axis parameters (name -> value)
  final Map<String, double> _decParams;

  /// Dec axis parameters (name -> value)
  @override
  Map<String, double> get decParams {
    if (_decParams is EqualUnmodifiableMapView) return _decParams;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_decParams);
  }

  @override
  String toString() {
    return 'Phd2BrainParams(raParamNames: $raParamNames, decParamNames: $decParamNames, raParams: $raParams, decParams: $decParams)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Phd2BrainParamsImpl &&
            const DeepCollectionEquality()
                .equals(other._raParamNames, _raParamNames) &&
            const DeepCollectionEquality()
                .equals(other._decParamNames, _decParamNames) &&
            const DeepCollectionEquality().equals(other._raParams, _raParams) &&
            const DeepCollectionEquality()
                .equals(other._decParams, _decParams));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_raParamNames),
      const DeepCollectionEquality().hash(_decParamNames),
      const DeepCollectionEquality().hash(_raParams),
      const DeepCollectionEquality().hash(_decParams));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$Phd2BrainParamsImplCopyWith<_$Phd2BrainParamsImpl> get copyWith =>
      __$$Phd2BrainParamsImplCopyWithImpl<_$Phd2BrainParamsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$Phd2BrainParamsImplToJson(
      this,
    );
  }
}

abstract class _Phd2BrainParams implements Phd2BrainParams {
  const factory _Phd2BrainParams(
      {required final List<String> raParamNames,
      required final List<String> decParamNames,
      required final Map<String, double> raParams,
      required final Map<String, double> decParams}) = _$Phd2BrainParamsImpl;

  factory _Phd2BrainParams.fromJson(Map<String, dynamic> json) =
      _$Phd2BrainParamsImpl.fromJson;

  @override

  /// RA axis parameter names
  List<String> get raParamNames;
  @override

  /// Dec axis parameter names
  List<String> get decParamNames;
  @override

  /// RA axis parameters (name -> value)
  Map<String, double> get raParams;
  @override

  /// Dec axis parameters (name -> value)
  Map<String, double> get decParams;
  @override
  @JsonKey(ignore: true)
  _$$Phd2BrainParamsImplCopyWith<_$Phd2BrainParamsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GuideErrorPoint _$GuideErrorPointFromJson(Map<String, dynamic> json) {
  return _GuideErrorPoint.fromJson(json);
}

/// @nodoc
mixin _$GuideErrorPoint {
  /// RA error in arcseconds
  double get raError => throw _privateConstructorUsedError;

  /// Dec error in arcseconds
  double get decError => throw _privateConstructorUsedError;

  /// Timestamp when this error was recorded
  DateTime get timestamp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GuideErrorPointCopyWith<GuideErrorPoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GuideErrorPointCopyWith<$Res> {
  factory $GuideErrorPointCopyWith(
          GuideErrorPoint value, $Res Function(GuideErrorPoint) then) =
      _$GuideErrorPointCopyWithImpl<$Res, GuideErrorPoint>;
  @useResult
  $Res call({double raError, double decError, DateTime timestamp});
}

/// @nodoc
class _$GuideErrorPointCopyWithImpl<$Res, $Val extends GuideErrorPoint>
    implements $GuideErrorPointCopyWith<$Res> {
  _$GuideErrorPointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? raError = null,
    Object? decError = null,
    Object? timestamp = null,
  }) {
    return _then(_value.copyWith(
      raError: null == raError
          ? _value.raError
          : raError // ignore: cast_nullable_to_non_nullable
              as double,
      decError: null == decError
          ? _value.decError
          : decError // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GuideErrorPointImplCopyWith<$Res>
    implements $GuideErrorPointCopyWith<$Res> {
  factory _$$GuideErrorPointImplCopyWith(_$GuideErrorPointImpl value,
          $Res Function(_$GuideErrorPointImpl) then) =
      __$$GuideErrorPointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double raError, double decError, DateTime timestamp});
}

/// @nodoc
class __$$GuideErrorPointImplCopyWithImpl<$Res>
    extends _$GuideErrorPointCopyWithImpl<$Res, _$GuideErrorPointImpl>
    implements _$$GuideErrorPointImplCopyWith<$Res> {
  __$$GuideErrorPointImplCopyWithImpl(
      _$GuideErrorPointImpl _value, $Res Function(_$GuideErrorPointImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? raError = null,
    Object? decError = null,
    Object? timestamp = null,
  }) {
    return _then(_$GuideErrorPointImpl(
      raError: null == raError
          ? _value.raError
          : raError // ignore: cast_nullable_to_non_nullable
              as double,
      decError: null == decError
          ? _value.decError
          : decError // ignore: cast_nullable_to_non_nullable
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
class _$GuideErrorPointImpl implements _GuideErrorPoint {
  const _$GuideErrorPointImpl(
      {required this.raError, required this.decError, required this.timestamp});

  factory _$GuideErrorPointImpl.fromJson(Map<String, dynamic> json) =>
      _$$GuideErrorPointImplFromJson(json);

  /// RA error in arcseconds
  @override
  final double raError;

  /// Dec error in arcseconds
  @override
  final double decError;

  /// Timestamp when this error was recorded
  @override
  final DateTime timestamp;

  @override
  String toString() {
    return 'GuideErrorPoint(raError: $raError, decError: $decError, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GuideErrorPointImpl &&
            (identical(other.raError, raError) || other.raError == raError) &&
            (identical(other.decError, decError) ||
                other.decError == decError) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, raError, decError, timestamp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GuideErrorPointImplCopyWith<_$GuideErrorPointImpl> get copyWith =>
      __$$GuideErrorPointImplCopyWithImpl<_$GuideErrorPointImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GuideErrorPointImplToJson(
      this,
    );
  }
}

abstract class _GuideErrorPoint implements GuideErrorPoint {
  const factory _GuideErrorPoint(
      {required final double raError,
      required final double decError,
      required final DateTime timestamp}) = _$GuideErrorPointImpl;

  factory _GuideErrorPoint.fromJson(Map<String, dynamic> json) =
      _$GuideErrorPointImpl.fromJson;

  @override

  /// RA error in arcseconds
  double get raError;
  @override

  /// Dec error in arcseconds
  double get decError;
  @override

  /// Timestamp when this error was recorded
  DateTime get timestamp;
  @override
  @JsonKey(ignore: true)
  _$$GuideErrorPointImplCopyWith<_$GuideErrorPointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Phd2GuideStats _$Phd2GuideStatsFromJson(Map<String, dynamic> json) {
  return _Phd2GuideStats.fromJson(json);
}

/// @nodoc
mixin _$Phd2GuideStats {
  /// RMS error in RA (arcseconds)
  double get rmsRa => throw _privateConstructorUsedError;

  /// RMS error in Dec (arcseconds)
  double get rmsDec => throw _privateConstructorUsedError;

  /// Total RMS error (arcseconds)
  double get rmsTotal => throw _privateConstructorUsedError;

  /// Peak RA error (arcseconds)
  double get peakRa => throw _privateConstructorUsedError;

  /// Peak Dec error (arcseconds)
  double get peakDec => throw _privateConstructorUsedError;

  /// SNR of guide star
  double get snr => throw _privateConstructorUsedError;

  /// Star mass (brightness)
  double get starMass => throw _privateConstructorUsedError;

  /// HFD (Half Flux Diameter)
  double get hfd => throw _privateConstructorUsedError;

  /// Guide star X position
  double get starX => throw _privateConstructorUsedError;

  /// Guide star Y position
  double get starY => throw _privateConstructorUsedError;

  /// Pixel scale (arcsec/pixel)
  double get pixelScale => throw _privateConstructorUsedError;

  /// Number of guide frames
  int get frameCount => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $Phd2GuideStatsCopyWith<Phd2GuideStats> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $Phd2GuideStatsCopyWith<$Res> {
  factory $Phd2GuideStatsCopyWith(
          Phd2GuideStats value, $Res Function(Phd2GuideStats) then) =
      _$Phd2GuideStatsCopyWithImpl<$Res, Phd2GuideStats>;
  @useResult
  $Res call(
      {double rmsRa,
      double rmsDec,
      double rmsTotal,
      double peakRa,
      double peakDec,
      double snr,
      double starMass,
      double hfd,
      double starX,
      double starY,
      double pixelScale,
      int frameCount});
}

/// @nodoc
class _$Phd2GuideStatsCopyWithImpl<$Res, $Val extends Phd2GuideStats>
    implements $Phd2GuideStatsCopyWith<$Res> {
  _$Phd2GuideStatsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? rmsRa = null,
    Object? rmsDec = null,
    Object? rmsTotal = null,
    Object? peakRa = null,
    Object? peakDec = null,
    Object? snr = null,
    Object? starMass = null,
    Object? hfd = null,
    Object? starX = null,
    Object? starY = null,
    Object? pixelScale = null,
    Object? frameCount = null,
  }) {
    return _then(_value.copyWith(
      rmsRa: null == rmsRa
          ? _value.rmsRa
          : rmsRa // ignore: cast_nullable_to_non_nullable
              as double,
      rmsDec: null == rmsDec
          ? _value.rmsDec
          : rmsDec // ignore: cast_nullable_to_non_nullable
              as double,
      rmsTotal: null == rmsTotal
          ? _value.rmsTotal
          : rmsTotal // ignore: cast_nullable_to_non_nullable
              as double,
      peakRa: null == peakRa
          ? _value.peakRa
          : peakRa // ignore: cast_nullable_to_non_nullable
              as double,
      peakDec: null == peakDec
          ? _value.peakDec
          : peakDec // ignore: cast_nullable_to_non_nullable
              as double,
      snr: null == snr
          ? _value.snr
          : snr // ignore: cast_nullable_to_non_nullable
              as double,
      starMass: null == starMass
          ? _value.starMass
          : starMass // ignore: cast_nullable_to_non_nullable
              as double,
      hfd: null == hfd
          ? _value.hfd
          : hfd // ignore: cast_nullable_to_non_nullable
              as double,
      starX: null == starX
          ? _value.starX
          : starX // ignore: cast_nullable_to_non_nullable
              as double,
      starY: null == starY
          ? _value.starY
          : starY // ignore: cast_nullable_to_non_nullable
              as double,
      pixelScale: null == pixelScale
          ? _value.pixelScale
          : pixelScale // ignore: cast_nullable_to_non_nullable
              as double,
      frameCount: null == frameCount
          ? _value.frameCount
          : frameCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$Phd2GuideStatsImplCopyWith<$Res>
    implements $Phd2GuideStatsCopyWith<$Res> {
  factory _$$Phd2GuideStatsImplCopyWith(_$Phd2GuideStatsImpl value,
          $Res Function(_$Phd2GuideStatsImpl) then) =
      __$$Phd2GuideStatsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double rmsRa,
      double rmsDec,
      double rmsTotal,
      double peakRa,
      double peakDec,
      double snr,
      double starMass,
      double hfd,
      double starX,
      double starY,
      double pixelScale,
      int frameCount});
}

/// @nodoc
class __$$Phd2GuideStatsImplCopyWithImpl<$Res>
    extends _$Phd2GuideStatsCopyWithImpl<$Res, _$Phd2GuideStatsImpl>
    implements _$$Phd2GuideStatsImplCopyWith<$Res> {
  __$$Phd2GuideStatsImplCopyWithImpl(
      _$Phd2GuideStatsImpl _value, $Res Function(_$Phd2GuideStatsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? rmsRa = null,
    Object? rmsDec = null,
    Object? rmsTotal = null,
    Object? peakRa = null,
    Object? peakDec = null,
    Object? snr = null,
    Object? starMass = null,
    Object? hfd = null,
    Object? starX = null,
    Object? starY = null,
    Object? pixelScale = null,
    Object? frameCount = null,
  }) {
    return _then(_$Phd2GuideStatsImpl(
      rmsRa: null == rmsRa
          ? _value.rmsRa
          : rmsRa // ignore: cast_nullable_to_non_nullable
              as double,
      rmsDec: null == rmsDec
          ? _value.rmsDec
          : rmsDec // ignore: cast_nullable_to_non_nullable
              as double,
      rmsTotal: null == rmsTotal
          ? _value.rmsTotal
          : rmsTotal // ignore: cast_nullable_to_non_nullable
              as double,
      peakRa: null == peakRa
          ? _value.peakRa
          : peakRa // ignore: cast_nullable_to_non_nullable
              as double,
      peakDec: null == peakDec
          ? _value.peakDec
          : peakDec // ignore: cast_nullable_to_non_nullable
              as double,
      snr: null == snr
          ? _value.snr
          : snr // ignore: cast_nullable_to_non_nullable
              as double,
      starMass: null == starMass
          ? _value.starMass
          : starMass // ignore: cast_nullable_to_non_nullable
              as double,
      hfd: null == hfd
          ? _value.hfd
          : hfd // ignore: cast_nullable_to_non_nullable
              as double,
      starX: null == starX
          ? _value.starX
          : starX // ignore: cast_nullable_to_non_nullable
              as double,
      starY: null == starY
          ? _value.starY
          : starY // ignore: cast_nullable_to_non_nullable
              as double,
      pixelScale: null == pixelScale
          ? _value.pixelScale
          : pixelScale // ignore: cast_nullable_to_non_nullable
              as double,
      frameCount: null == frameCount
          ? _value.frameCount
          : frameCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$Phd2GuideStatsImpl implements _Phd2GuideStats {
  const _$Phd2GuideStatsImpl(
      {this.rmsRa = 0.0,
      this.rmsDec = 0.0,
      this.rmsTotal = 0.0,
      this.peakRa = 0.0,
      this.peakDec = 0.0,
      this.snr = 0.0,
      this.starMass = 0.0,
      this.hfd = 0.0,
      this.starX = 0.0,
      this.starY = 0.0,
      this.pixelScale = 0.0,
      this.frameCount = 0});

  factory _$Phd2GuideStatsImpl.fromJson(Map<String, dynamic> json) =>
      _$$Phd2GuideStatsImplFromJson(json);

  /// RMS error in RA (arcseconds)
  @override
  @JsonKey()
  final double rmsRa;

  /// RMS error in Dec (arcseconds)
  @override
  @JsonKey()
  final double rmsDec;

  /// Total RMS error (arcseconds)
  @override
  @JsonKey()
  final double rmsTotal;

  /// Peak RA error (arcseconds)
  @override
  @JsonKey()
  final double peakRa;

  /// Peak Dec error (arcseconds)
  @override
  @JsonKey()
  final double peakDec;

  /// SNR of guide star
  @override
  @JsonKey()
  final double snr;

  /// Star mass (brightness)
  @override
  @JsonKey()
  final double starMass;

  /// HFD (Half Flux Diameter)
  @override
  @JsonKey()
  final double hfd;

  /// Guide star X position
  @override
  @JsonKey()
  final double starX;

  /// Guide star Y position
  @override
  @JsonKey()
  final double starY;

  /// Pixel scale (arcsec/pixel)
  @override
  @JsonKey()
  final double pixelScale;

  /// Number of guide frames
  @override
  @JsonKey()
  final int frameCount;

  @override
  String toString() {
    return 'Phd2GuideStats(rmsRa: $rmsRa, rmsDec: $rmsDec, rmsTotal: $rmsTotal, peakRa: $peakRa, peakDec: $peakDec, snr: $snr, starMass: $starMass, hfd: $hfd, starX: $starX, starY: $starY, pixelScale: $pixelScale, frameCount: $frameCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Phd2GuideStatsImpl &&
            (identical(other.rmsRa, rmsRa) || other.rmsRa == rmsRa) &&
            (identical(other.rmsDec, rmsDec) || other.rmsDec == rmsDec) &&
            (identical(other.rmsTotal, rmsTotal) ||
                other.rmsTotal == rmsTotal) &&
            (identical(other.peakRa, peakRa) || other.peakRa == peakRa) &&
            (identical(other.peakDec, peakDec) || other.peakDec == peakDec) &&
            (identical(other.snr, snr) || other.snr == snr) &&
            (identical(other.starMass, starMass) ||
                other.starMass == starMass) &&
            (identical(other.hfd, hfd) || other.hfd == hfd) &&
            (identical(other.starX, starX) || other.starX == starX) &&
            (identical(other.starY, starY) || other.starY == starY) &&
            (identical(other.pixelScale, pixelScale) ||
                other.pixelScale == pixelScale) &&
            (identical(other.frameCount, frameCount) ||
                other.frameCount == frameCount));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, rmsRa, rmsDec, rmsTotal, peakRa,
      peakDec, snr, starMass, hfd, starX, starY, pixelScale, frameCount);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$Phd2GuideStatsImplCopyWith<_$Phd2GuideStatsImpl> get copyWith =>
      __$$Phd2GuideStatsImplCopyWithImpl<_$Phd2GuideStatsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$Phd2GuideStatsImplToJson(
      this,
    );
  }
}

abstract class _Phd2GuideStats implements Phd2GuideStats {
  const factory _Phd2GuideStats(
      {final double rmsRa,
      final double rmsDec,
      final double rmsTotal,
      final double peakRa,
      final double peakDec,
      final double snr,
      final double starMass,
      final double hfd,
      final double starX,
      final double starY,
      final double pixelScale,
      final int frameCount}) = _$Phd2GuideStatsImpl;

  factory _Phd2GuideStats.fromJson(Map<String, dynamic> json) =
      _$Phd2GuideStatsImpl.fromJson;

  @override

  /// RMS error in RA (arcseconds)
  double get rmsRa;
  @override

  /// RMS error in Dec (arcseconds)
  double get rmsDec;
  @override

  /// Total RMS error (arcseconds)
  double get rmsTotal;
  @override

  /// Peak RA error (arcseconds)
  double get peakRa;
  @override

  /// Peak Dec error (arcseconds)
  double get peakDec;
  @override

  /// SNR of guide star
  double get snr;
  @override

  /// Star mass (brightness)
  double get starMass;
  @override

  /// HFD (Half Flux Diameter)
  double get hfd;
  @override

  /// Guide star X position
  double get starX;
  @override

  /// Guide star Y position
  double get starY;
  @override

  /// Pixel scale (arcsec/pixel)
  double get pixelScale;
  @override

  /// Number of guide frames
  int get frameCount;
  @override
  @JsonKey(ignore: true)
  _$$Phd2GuideStatsImplCopyWith<_$Phd2GuideStatsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Phd2CalibrationData _$Phd2CalibrationDataFromJson(Map<String, dynamic> json) {
  return _Phd2CalibrationData.fromJson(json);
}

/// @nodoc
mixin _$Phd2CalibrationData {
  /// Whether calibration is complete
  bool get isCalibrated => throw _privateConstructorUsedError;

  /// Calibration timestamp
  DateTime? get calibratedAt => throw _privateConstructorUsedError;

  /// RA calibration rate (pixels/ms)
  double? get raRate => throw _privateConstructorUsedError;

  /// Dec calibration rate (pixels/ms)
  double? get decRate => throw _privateConstructorUsedError;

  /// Camera rotation angle (degrees)
  double? get rotationAngle => throw _privateConstructorUsedError;

  /// Dec guide mode ("Auto", "North", "South", "Off")
  String? get decGuideMode => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $Phd2CalibrationDataCopyWith<Phd2CalibrationData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $Phd2CalibrationDataCopyWith<$Res> {
  factory $Phd2CalibrationDataCopyWith(
          Phd2CalibrationData value, $Res Function(Phd2CalibrationData) then) =
      _$Phd2CalibrationDataCopyWithImpl<$Res, Phd2CalibrationData>;
  @useResult
  $Res call(
      {bool isCalibrated,
      DateTime? calibratedAt,
      double? raRate,
      double? decRate,
      double? rotationAngle,
      String? decGuideMode});
}

/// @nodoc
class _$Phd2CalibrationDataCopyWithImpl<$Res, $Val extends Phd2CalibrationData>
    implements $Phd2CalibrationDataCopyWith<$Res> {
  _$Phd2CalibrationDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isCalibrated = null,
    Object? calibratedAt = freezed,
    Object? raRate = freezed,
    Object? decRate = freezed,
    Object? rotationAngle = freezed,
    Object? decGuideMode = freezed,
  }) {
    return _then(_value.copyWith(
      isCalibrated: null == isCalibrated
          ? _value.isCalibrated
          : isCalibrated // ignore: cast_nullable_to_non_nullable
              as bool,
      calibratedAt: freezed == calibratedAt
          ? _value.calibratedAt
          : calibratedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      raRate: freezed == raRate
          ? _value.raRate
          : raRate // ignore: cast_nullable_to_non_nullable
              as double?,
      decRate: freezed == decRate
          ? _value.decRate
          : decRate // ignore: cast_nullable_to_non_nullable
              as double?,
      rotationAngle: freezed == rotationAngle
          ? _value.rotationAngle
          : rotationAngle // ignore: cast_nullable_to_non_nullable
              as double?,
      decGuideMode: freezed == decGuideMode
          ? _value.decGuideMode
          : decGuideMode // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$Phd2CalibrationDataImplCopyWith<$Res>
    implements $Phd2CalibrationDataCopyWith<$Res> {
  factory _$$Phd2CalibrationDataImplCopyWith(_$Phd2CalibrationDataImpl value,
          $Res Function(_$Phd2CalibrationDataImpl) then) =
      __$$Phd2CalibrationDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool isCalibrated,
      DateTime? calibratedAt,
      double? raRate,
      double? decRate,
      double? rotationAngle,
      String? decGuideMode});
}

/// @nodoc
class __$$Phd2CalibrationDataImplCopyWithImpl<$Res>
    extends _$Phd2CalibrationDataCopyWithImpl<$Res, _$Phd2CalibrationDataImpl>
    implements _$$Phd2CalibrationDataImplCopyWith<$Res> {
  __$$Phd2CalibrationDataImplCopyWithImpl(_$Phd2CalibrationDataImpl _value,
      $Res Function(_$Phd2CalibrationDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isCalibrated = null,
    Object? calibratedAt = freezed,
    Object? raRate = freezed,
    Object? decRate = freezed,
    Object? rotationAngle = freezed,
    Object? decGuideMode = freezed,
  }) {
    return _then(_$Phd2CalibrationDataImpl(
      isCalibrated: null == isCalibrated
          ? _value.isCalibrated
          : isCalibrated // ignore: cast_nullable_to_non_nullable
              as bool,
      calibratedAt: freezed == calibratedAt
          ? _value.calibratedAt
          : calibratedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      raRate: freezed == raRate
          ? _value.raRate
          : raRate // ignore: cast_nullable_to_non_nullable
              as double?,
      decRate: freezed == decRate
          ? _value.decRate
          : decRate // ignore: cast_nullable_to_non_nullable
              as double?,
      rotationAngle: freezed == rotationAngle
          ? _value.rotationAngle
          : rotationAngle // ignore: cast_nullable_to_non_nullable
              as double?,
      decGuideMode: freezed == decGuideMode
          ? _value.decGuideMode
          : decGuideMode // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$Phd2CalibrationDataImpl implements _Phd2CalibrationData {
  const _$Phd2CalibrationDataImpl(
      {this.isCalibrated = false,
      this.calibratedAt,
      this.raRate,
      this.decRate,
      this.rotationAngle,
      this.decGuideMode});

  factory _$Phd2CalibrationDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$Phd2CalibrationDataImplFromJson(json);

  /// Whether calibration is complete
  @override
  @JsonKey()
  final bool isCalibrated;

  /// Calibration timestamp
  @override
  final DateTime? calibratedAt;

  /// RA calibration rate (pixels/ms)
  @override
  final double? raRate;

  /// Dec calibration rate (pixels/ms)
  @override
  final double? decRate;

  /// Camera rotation angle (degrees)
  @override
  final double? rotationAngle;

  /// Dec guide mode ("Auto", "North", "South", "Off")
  @override
  final String? decGuideMode;

  @override
  String toString() {
    return 'Phd2CalibrationData(isCalibrated: $isCalibrated, calibratedAt: $calibratedAt, raRate: $raRate, decRate: $decRate, rotationAngle: $rotationAngle, decGuideMode: $decGuideMode)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Phd2CalibrationDataImpl &&
            (identical(other.isCalibrated, isCalibrated) ||
                other.isCalibrated == isCalibrated) &&
            (identical(other.calibratedAt, calibratedAt) ||
                other.calibratedAt == calibratedAt) &&
            (identical(other.raRate, raRate) || other.raRate == raRate) &&
            (identical(other.decRate, decRate) || other.decRate == decRate) &&
            (identical(other.rotationAngle, rotationAngle) ||
                other.rotationAngle == rotationAngle) &&
            (identical(other.decGuideMode, decGuideMode) ||
                other.decGuideMode == decGuideMode));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, isCalibrated, calibratedAt,
      raRate, decRate, rotationAngle, decGuideMode);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$Phd2CalibrationDataImplCopyWith<_$Phd2CalibrationDataImpl> get copyWith =>
      __$$Phd2CalibrationDataImplCopyWithImpl<_$Phd2CalibrationDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$Phd2CalibrationDataImplToJson(
      this,
    );
  }
}

abstract class _Phd2CalibrationData implements Phd2CalibrationData {
  const factory _Phd2CalibrationData(
      {final bool isCalibrated,
      final DateTime? calibratedAt,
      final double? raRate,
      final double? decRate,
      final double? rotationAngle,
      final String? decGuideMode}) = _$Phd2CalibrationDataImpl;

  factory _Phd2CalibrationData.fromJson(Map<String, dynamic> json) =
      _$Phd2CalibrationDataImpl.fromJson;

  @override

  /// Whether calibration is complete
  bool get isCalibrated;
  @override

  /// Calibration timestamp
  DateTime? get calibratedAt;
  @override

  /// RA calibration rate (pixels/ms)
  double? get raRate;
  @override

  /// Dec calibration rate (pixels/ms)
  double? get decRate;
  @override

  /// Camera rotation angle (degrees)
  double? get rotationAngle;
  @override

  /// Dec guide mode ("Auto", "North", "South", "Off")
  String? get decGuideMode;
  @override
  @JsonKey(ignore: true)
  _$$Phd2CalibrationDataImplCopyWith<_$Phd2CalibrationDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
