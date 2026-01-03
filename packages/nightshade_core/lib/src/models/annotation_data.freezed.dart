// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'annotation_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ImageAnnotation _$ImageAnnotationFromJson(Map<String, dynamic> json) {
  return _ImageAnnotation.fromJson(json);
}

/// @nodoc
mixin _$ImageAnnotation {
  String get imagePath => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;
  PlateSolveData get plateSolve => throw _privateConstructorUsedError;
  List<CelestialObjectAnnotation> get objects =>
      throw _privateConstructorUsedError;
  bool get visible => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ImageAnnotationCopyWith<ImageAnnotation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImageAnnotationCopyWith<$Res> {
  factory $ImageAnnotationCopyWith(
          ImageAnnotation value, $Res Function(ImageAnnotation) then) =
      _$ImageAnnotationCopyWithImpl<$Res, ImageAnnotation>;
  @useResult
  $Res call(
      {String imagePath,
      DateTime timestamp,
      PlateSolveData plateSolve,
      List<CelestialObjectAnnotation> objects,
      bool visible});

  $PlateSolveDataCopyWith<$Res> get plateSolve;
}

/// @nodoc
class _$ImageAnnotationCopyWithImpl<$Res, $Val extends ImageAnnotation>
    implements $ImageAnnotationCopyWith<$Res> {
  _$ImageAnnotationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imagePath = null,
    Object? timestamp = null,
    Object? plateSolve = null,
    Object? objects = null,
    Object? visible = null,
  }) {
    return _then(_value.copyWith(
      imagePath: null == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      plateSolve: null == plateSolve
          ? _value.plateSolve
          : plateSolve // ignore: cast_nullable_to_non_nullable
              as PlateSolveData,
      objects: null == objects
          ? _value.objects
          : objects // ignore: cast_nullable_to_non_nullable
              as List<CelestialObjectAnnotation>,
      visible: null == visible
          ? _value.visible
          : visible // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $PlateSolveDataCopyWith<$Res> get plateSolve {
    return $PlateSolveDataCopyWith<$Res>(_value.plateSolve, (value) {
      return _then(_value.copyWith(plateSolve: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ImageAnnotationImplCopyWith<$Res>
    implements $ImageAnnotationCopyWith<$Res> {
  factory _$$ImageAnnotationImplCopyWith(_$ImageAnnotationImpl value,
          $Res Function(_$ImageAnnotationImpl) then) =
      __$$ImageAnnotationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String imagePath,
      DateTime timestamp,
      PlateSolveData plateSolve,
      List<CelestialObjectAnnotation> objects,
      bool visible});

  @override
  $PlateSolveDataCopyWith<$Res> get plateSolve;
}

/// @nodoc
class __$$ImageAnnotationImplCopyWithImpl<$Res>
    extends _$ImageAnnotationCopyWithImpl<$Res, _$ImageAnnotationImpl>
    implements _$$ImageAnnotationImplCopyWith<$Res> {
  __$$ImageAnnotationImplCopyWithImpl(
      _$ImageAnnotationImpl _value, $Res Function(_$ImageAnnotationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imagePath = null,
    Object? timestamp = null,
    Object? plateSolve = null,
    Object? objects = null,
    Object? visible = null,
  }) {
    return _then(_$ImageAnnotationImpl(
      imagePath: null == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      plateSolve: null == plateSolve
          ? _value.plateSolve
          : plateSolve // ignore: cast_nullable_to_non_nullable
              as PlateSolveData,
      objects: null == objects
          ? _value._objects
          : objects // ignore: cast_nullable_to_non_nullable
              as List<CelestialObjectAnnotation>,
      visible: null == visible
          ? _value.visible
          : visible // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageAnnotationImpl implements _ImageAnnotation {
  const _$ImageAnnotationImpl(
      {required this.imagePath,
      required this.timestamp,
      required this.plateSolve,
      required final List<CelestialObjectAnnotation> objects,
      this.visible = true})
      : _objects = objects;

  factory _$ImageAnnotationImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageAnnotationImplFromJson(json);

  @override
  final String imagePath;
  @override
  final DateTime timestamp;
  @override
  final PlateSolveData plateSolve;
  final List<CelestialObjectAnnotation> _objects;
  @override
  List<CelestialObjectAnnotation> get objects {
    if (_objects is EqualUnmodifiableListView) return _objects;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_objects);
  }

  @override
  @JsonKey()
  final bool visible;

  @override
  String toString() {
    return 'ImageAnnotation(imagePath: $imagePath, timestamp: $timestamp, plateSolve: $plateSolve, objects: $objects, visible: $visible)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageAnnotationImpl &&
            (identical(other.imagePath, imagePath) ||
                other.imagePath == imagePath) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.plateSolve, plateSolve) ||
                other.plateSolve == plateSolve) &&
            const DeepCollectionEquality().equals(other._objects, _objects) &&
            (identical(other.visible, visible) || other.visible == visible));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, imagePath, timestamp, plateSolve,
      const DeepCollectionEquality().hash(_objects), visible);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageAnnotationImplCopyWith<_$ImageAnnotationImpl> get copyWith =>
      __$$ImageAnnotationImplCopyWithImpl<_$ImageAnnotationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageAnnotationImplToJson(
      this,
    );
  }
}

abstract class _ImageAnnotation implements ImageAnnotation {
  const factory _ImageAnnotation(
      {required final String imagePath,
      required final DateTime timestamp,
      required final PlateSolveData plateSolve,
      required final List<CelestialObjectAnnotation> objects,
      final bool visible}) = _$ImageAnnotationImpl;

  factory _ImageAnnotation.fromJson(Map<String, dynamic> json) =
      _$ImageAnnotationImpl.fromJson;

  @override
  String get imagePath;
  @override
  DateTime get timestamp;
  @override
  PlateSolveData get plateSolve;
  @override
  List<CelestialObjectAnnotation> get objects;
  @override
  bool get visible;
  @override
  @JsonKey(ignore: true)
  _$$ImageAnnotationImplCopyWith<_$ImageAnnotationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PlateSolveData _$PlateSolveDataFromJson(Map<String, dynamic> json) {
  return _PlateSolveData.fromJson(json);
}

/// @nodoc
mixin _$PlateSolveData {
  double get ra => throw _privateConstructorUsedError;
  double get dec => throw _privateConstructorUsedError;
  double get pixelScale => throw _privateConstructorUsedError; // arcsec/pixel
  double get rotation => throw _privateConstructorUsedError; // degrees
  double get fieldWidth => throw _privateConstructorUsedError; // degrees
  double get fieldHeight => throw _privateConstructorUsedError; // degrees
  int get imageWidth => throw _privateConstructorUsedError; // pixels
  int get imageHeight => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PlateSolveDataCopyWith<PlateSolveData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlateSolveDataCopyWith<$Res> {
  factory $PlateSolveDataCopyWith(
          PlateSolveData value, $Res Function(PlateSolveData) then) =
      _$PlateSolveDataCopyWithImpl<$Res, PlateSolveData>;
  @useResult
  $Res call(
      {double ra,
      double dec,
      double pixelScale,
      double rotation,
      double fieldWidth,
      double fieldHeight,
      int imageWidth,
      int imageHeight});
}

/// @nodoc
class _$PlateSolveDataCopyWithImpl<$Res, $Val extends PlateSolveData>
    implements $PlateSolveDataCopyWith<$Res> {
  _$PlateSolveDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ra = null,
    Object? dec = null,
    Object? pixelScale = null,
    Object? rotation = null,
    Object? fieldWidth = null,
    Object? fieldHeight = null,
    Object? imageWidth = null,
    Object? imageHeight = null,
  }) {
    return _then(_value.copyWith(
      ra: null == ra
          ? _value.ra
          : ra // ignore: cast_nullable_to_non_nullable
              as double,
      dec: null == dec
          ? _value.dec
          : dec // ignore: cast_nullable_to_non_nullable
              as double,
      pixelScale: null == pixelScale
          ? _value.pixelScale
          : pixelScale // ignore: cast_nullable_to_non_nullable
              as double,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      fieldWidth: null == fieldWidth
          ? _value.fieldWidth
          : fieldWidth // ignore: cast_nullable_to_non_nullable
              as double,
      fieldHeight: null == fieldHeight
          ? _value.fieldHeight
          : fieldHeight // ignore: cast_nullable_to_non_nullable
              as double,
      imageWidth: null == imageWidth
          ? _value.imageWidth
          : imageWidth // ignore: cast_nullable_to_non_nullable
              as int,
      imageHeight: null == imageHeight
          ? _value.imageHeight
          : imageHeight // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PlateSolveDataImplCopyWith<$Res>
    implements $PlateSolveDataCopyWith<$Res> {
  factory _$$PlateSolveDataImplCopyWith(_$PlateSolveDataImpl value,
          $Res Function(_$PlateSolveDataImpl) then) =
      __$$PlateSolveDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double ra,
      double dec,
      double pixelScale,
      double rotation,
      double fieldWidth,
      double fieldHeight,
      int imageWidth,
      int imageHeight});
}

/// @nodoc
class __$$PlateSolveDataImplCopyWithImpl<$Res>
    extends _$PlateSolveDataCopyWithImpl<$Res, _$PlateSolveDataImpl>
    implements _$$PlateSolveDataImplCopyWith<$Res> {
  __$$PlateSolveDataImplCopyWithImpl(
      _$PlateSolveDataImpl _value, $Res Function(_$PlateSolveDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ra = null,
    Object? dec = null,
    Object? pixelScale = null,
    Object? rotation = null,
    Object? fieldWidth = null,
    Object? fieldHeight = null,
    Object? imageWidth = null,
    Object? imageHeight = null,
  }) {
    return _then(_$PlateSolveDataImpl(
      ra: null == ra
          ? _value.ra
          : ra // ignore: cast_nullable_to_non_nullable
              as double,
      dec: null == dec
          ? _value.dec
          : dec // ignore: cast_nullable_to_non_nullable
              as double,
      pixelScale: null == pixelScale
          ? _value.pixelScale
          : pixelScale // ignore: cast_nullable_to_non_nullable
              as double,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      fieldWidth: null == fieldWidth
          ? _value.fieldWidth
          : fieldWidth // ignore: cast_nullable_to_non_nullable
              as double,
      fieldHeight: null == fieldHeight
          ? _value.fieldHeight
          : fieldHeight // ignore: cast_nullable_to_non_nullable
              as double,
      imageWidth: null == imageWidth
          ? _value.imageWidth
          : imageWidth // ignore: cast_nullable_to_non_nullable
              as int,
      imageHeight: null == imageHeight
          ? _value.imageHeight
          : imageHeight // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PlateSolveDataImpl implements _PlateSolveData {
  const _$PlateSolveDataImpl(
      {required this.ra,
      required this.dec,
      required this.pixelScale,
      required this.rotation,
      required this.fieldWidth,
      required this.fieldHeight,
      required this.imageWidth,
      required this.imageHeight});

  factory _$PlateSolveDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$PlateSolveDataImplFromJson(json);

  @override
  final double ra;
  @override
  final double dec;
  @override
  final double pixelScale;
// arcsec/pixel
  @override
  final double rotation;
// degrees
  @override
  final double fieldWidth;
// degrees
  @override
  final double fieldHeight;
// degrees
  @override
  final int imageWidth;
// pixels
  @override
  final int imageHeight;

  @override
  String toString() {
    return 'PlateSolveData(ra: $ra, dec: $dec, pixelScale: $pixelScale, rotation: $rotation, fieldWidth: $fieldWidth, fieldHeight: $fieldHeight, imageWidth: $imageWidth, imageHeight: $imageHeight)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlateSolveDataImpl &&
            (identical(other.ra, ra) || other.ra == ra) &&
            (identical(other.dec, dec) || other.dec == dec) &&
            (identical(other.pixelScale, pixelScale) ||
                other.pixelScale == pixelScale) &&
            (identical(other.rotation, rotation) ||
                other.rotation == rotation) &&
            (identical(other.fieldWidth, fieldWidth) ||
                other.fieldWidth == fieldWidth) &&
            (identical(other.fieldHeight, fieldHeight) ||
                other.fieldHeight == fieldHeight) &&
            (identical(other.imageWidth, imageWidth) ||
                other.imageWidth == imageWidth) &&
            (identical(other.imageHeight, imageHeight) ||
                other.imageHeight == imageHeight));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, ra, dec, pixelScale, rotation,
      fieldWidth, fieldHeight, imageWidth, imageHeight);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlateSolveDataImplCopyWith<_$PlateSolveDataImpl> get copyWith =>
      __$$PlateSolveDataImplCopyWithImpl<_$PlateSolveDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PlateSolveDataImplToJson(
      this,
    );
  }
}

abstract class _PlateSolveData implements PlateSolveData {
  const factory _PlateSolveData(
      {required final double ra,
      required final double dec,
      required final double pixelScale,
      required final double rotation,
      required final double fieldWidth,
      required final double fieldHeight,
      required final int imageWidth,
      required final int imageHeight}) = _$PlateSolveDataImpl;

  factory _PlateSolveData.fromJson(Map<String, dynamic> json) =
      _$PlateSolveDataImpl.fromJson;

  @override
  double get ra;
  @override
  double get dec;
  @override
  double get pixelScale;
  @override // arcsec/pixel
  double get rotation;
  @override // degrees
  double get fieldWidth;
  @override // degrees
  double get fieldHeight;
  @override // degrees
  int get imageWidth;
  @override // pixels
  int get imageHeight;
  @override
  @JsonKey(ignore: true)
  _$$PlateSolveDataImplCopyWith<_$PlateSolveDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CelestialObjectAnnotation _$CelestialObjectAnnotationFromJson(
    Map<String, dynamic> json) {
  return _CelestialObjectAnnotation.fromJson(json);
}

/// @nodoc
mixin _$CelestialObjectAnnotation {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  ObjectType get type => throw _privateConstructorUsedError;
  double get ra => throw _privateConstructorUsedError; // J2000
  double get dec => throw _privateConstructorUsedError; // J2000
  double get x => throw _privateConstructorUsedError; // Image pixel X
  double get y => throw _privateConstructorUsedError; // Image pixel Y
  String? get catalogId =>
      throw _privateConstructorUsedError; // e.g., "NGC 224", "M 31"
  String? get commonName =>
      throw _privateConstructorUsedError; // Common name (e.g., "Andromeda Galaxy")
  double? get magnitude => throw _privateConstructorUsedError;
  double? get size => throw _privateConstructorUsedError; // arcminutes
  ObjectData? get detailedData => throw _privateConstructorUsedError;
  bool get visible => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CelestialObjectAnnotationCopyWith<CelestialObjectAnnotation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CelestialObjectAnnotationCopyWith<$Res> {
  factory $CelestialObjectAnnotationCopyWith(CelestialObjectAnnotation value,
          $Res Function(CelestialObjectAnnotation) then) =
      _$CelestialObjectAnnotationCopyWithImpl<$Res, CelestialObjectAnnotation>;
  @useResult
  $Res call(
      {String id,
      String name,
      ObjectType type,
      double ra,
      double dec,
      double x,
      double y,
      String? catalogId,
      String? commonName,
      double? magnitude,
      double? size,
      ObjectData? detailedData,
      bool visible});

  $ObjectDataCopyWith<$Res>? get detailedData;
}

/// @nodoc
class _$CelestialObjectAnnotationCopyWithImpl<$Res,
        $Val extends CelestialObjectAnnotation>
    implements $CelestialObjectAnnotationCopyWith<$Res> {
  _$CelestialObjectAnnotationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? ra = null,
    Object? dec = null,
    Object? x = null,
    Object? y = null,
    Object? catalogId = freezed,
    Object? commonName = freezed,
    Object? magnitude = freezed,
    Object? size = freezed,
    Object? detailedData = freezed,
    Object? visible = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as ObjectType,
      ra: null == ra
          ? _value.ra
          : ra // ignore: cast_nullable_to_non_nullable
              as double,
      dec: null == dec
          ? _value.dec
          : dec // ignore: cast_nullable_to_non_nullable
              as double,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      catalogId: freezed == catalogId
          ? _value.catalogId
          : catalogId // ignore: cast_nullable_to_non_nullable
              as String?,
      commonName: freezed == commonName
          ? _value.commonName
          : commonName // ignore: cast_nullable_to_non_nullable
              as String?,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      size: freezed == size
          ? _value.size
          : size // ignore: cast_nullable_to_non_nullable
              as double?,
      detailedData: freezed == detailedData
          ? _value.detailedData
          : detailedData // ignore: cast_nullable_to_non_nullable
              as ObjectData?,
      visible: null == visible
          ? _value.visible
          : visible // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ObjectDataCopyWith<$Res>? get detailedData {
    if (_value.detailedData == null) {
      return null;
    }

    return $ObjectDataCopyWith<$Res>(_value.detailedData!, (value) {
      return _then(_value.copyWith(detailedData: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$CelestialObjectAnnotationImplCopyWith<$Res>
    implements $CelestialObjectAnnotationCopyWith<$Res> {
  factory _$$CelestialObjectAnnotationImplCopyWith(
          _$CelestialObjectAnnotationImpl value,
          $Res Function(_$CelestialObjectAnnotationImpl) then) =
      __$$CelestialObjectAnnotationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      ObjectType type,
      double ra,
      double dec,
      double x,
      double y,
      String? catalogId,
      String? commonName,
      double? magnitude,
      double? size,
      ObjectData? detailedData,
      bool visible});

  @override
  $ObjectDataCopyWith<$Res>? get detailedData;
}

/// @nodoc
class __$$CelestialObjectAnnotationImplCopyWithImpl<$Res>
    extends _$CelestialObjectAnnotationCopyWithImpl<$Res,
        _$CelestialObjectAnnotationImpl>
    implements _$$CelestialObjectAnnotationImplCopyWith<$Res> {
  __$$CelestialObjectAnnotationImplCopyWithImpl(
      _$CelestialObjectAnnotationImpl _value,
      $Res Function(_$CelestialObjectAnnotationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? ra = null,
    Object? dec = null,
    Object? x = null,
    Object? y = null,
    Object? catalogId = freezed,
    Object? commonName = freezed,
    Object? magnitude = freezed,
    Object? size = freezed,
    Object? detailedData = freezed,
    Object? visible = null,
  }) {
    return _then(_$CelestialObjectAnnotationImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as ObjectType,
      ra: null == ra
          ? _value.ra
          : ra // ignore: cast_nullable_to_non_nullable
              as double,
      dec: null == dec
          ? _value.dec
          : dec // ignore: cast_nullable_to_non_nullable
              as double,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      catalogId: freezed == catalogId
          ? _value.catalogId
          : catalogId // ignore: cast_nullable_to_non_nullable
              as String?,
      commonName: freezed == commonName
          ? _value.commonName
          : commonName // ignore: cast_nullable_to_non_nullable
              as String?,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      size: freezed == size
          ? _value.size
          : size // ignore: cast_nullable_to_non_nullable
              as double?,
      detailedData: freezed == detailedData
          ? _value.detailedData
          : detailedData // ignore: cast_nullable_to_non_nullable
              as ObjectData?,
      visible: null == visible
          ? _value.visible
          : visible // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CelestialObjectAnnotationImpl implements _CelestialObjectAnnotation {
  const _$CelestialObjectAnnotationImpl(
      {required this.id,
      required this.name,
      required this.type,
      required this.ra,
      required this.dec,
      required this.x,
      required this.y,
      this.catalogId,
      this.commonName,
      this.magnitude,
      this.size,
      this.detailedData,
      this.visible = true});

  factory _$CelestialObjectAnnotationImpl.fromJson(Map<String, dynamic> json) =>
      _$$CelestialObjectAnnotationImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final ObjectType type;
  @override
  final double ra;
// J2000
  @override
  final double dec;
// J2000
  @override
  final double x;
// Image pixel X
  @override
  final double y;
// Image pixel Y
  @override
  final String? catalogId;
// e.g., "NGC 224", "M 31"
  @override
  final String? commonName;
// Common name (e.g., "Andromeda Galaxy")
  @override
  final double? magnitude;
  @override
  final double? size;
// arcminutes
  @override
  final ObjectData? detailedData;
  @override
  @JsonKey()
  final bool visible;

  @override
  String toString() {
    return 'CelestialObjectAnnotation(id: $id, name: $name, type: $type, ra: $ra, dec: $dec, x: $x, y: $y, catalogId: $catalogId, commonName: $commonName, magnitude: $magnitude, size: $size, detailedData: $detailedData, visible: $visible)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CelestialObjectAnnotationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.ra, ra) || other.ra == ra) &&
            (identical(other.dec, dec) || other.dec == dec) &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.catalogId, catalogId) ||
                other.catalogId == catalogId) &&
            (identical(other.commonName, commonName) ||
                other.commonName == commonName) &&
            (identical(other.magnitude, magnitude) ||
                other.magnitude == magnitude) &&
            (identical(other.size, size) || other.size == size) &&
            (identical(other.detailedData, detailedData) ||
                other.detailedData == detailedData) &&
            (identical(other.visible, visible) || other.visible == visible));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, type, ra, dec, x, y,
      catalogId, commonName, magnitude, size, detailedData, visible);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CelestialObjectAnnotationImplCopyWith<_$CelestialObjectAnnotationImpl>
      get copyWith => __$$CelestialObjectAnnotationImplCopyWithImpl<
          _$CelestialObjectAnnotationImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CelestialObjectAnnotationImplToJson(
      this,
    );
  }
}

abstract class _CelestialObjectAnnotation implements CelestialObjectAnnotation {
  const factory _CelestialObjectAnnotation(
      {required final String id,
      required final String name,
      required final ObjectType type,
      required final double ra,
      required final double dec,
      required final double x,
      required final double y,
      final String? catalogId,
      final String? commonName,
      final double? magnitude,
      final double? size,
      final ObjectData? detailedData,
      final bool visible}) = _$CelestialObjectAnnotationImpl;

  factory _CelestialObjectAnnotation.fromJson(Map<String, dynamic> json) =
      _$CelestialObjectAnnotationImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  ObjectType get type;
  @override
  double get ra;
  @override // J2000
  double get dec;
  @override // J2000
  double get x;
  @override // Image pixel X
  double get y;
  @override // Image pixel Y
  String? get catalogId;
  @override // e.g., "NGC 224", "M 31"
  String? get commonName;
  @override // Common name (e.g., "Andromeda Galaxy")
  double? get magnitude;
  @override
  double? get size;
  @override // arcminutes
  ObjectData? get detailedData;
  @override
  bool get visible;
  @override
  @JsonKey(ignore: true)
  _$$CelestialObjectAnnotationImplCopyWith<_$CelestialObjectAnnotationImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ObjectData _$ObjectDataFromJson(Map<String, dynamic> json) {
  return _ObjectData.fromJson(json);
}

/// @nodoc
mixin _$ObjectData {
// Basic info
  String? get description => throw _privateConstructorUsedError;
  String? get objectClass =>
      throw _privateConstructorUsedError; // e.g., "Spiral Galaxy", "Open Cluster"
// Stellar data (for stars)
  SpectralClass? get spectralType => throw _privateConstructorUsedError;
  double? get temperature => throw _privateConstructorUsedError; // Kelvin
  double? get mass => throw _privateConstructorUsedError; // Solar masses
  double? get radius => throw _privateConstructorUsedError; // Solar radii
  double? get luminosity =>
      throw _privateConstructorUsedError; // Solar luminosities
  double? get distance => throw _privateConstructorUsedError; // parsecs
  double? get parallax => throw _privateConstructorUsedError; // milliarcseconds
  String? get properMotion =>
      throw _privateConstructorUsedError; // Exoplanet data
  List<ExoplanetData>? get exoplanets =>
      throw _privateConstructorUsedError; // DSO data (galaxies, nebulae, clusters)
  double? get surfaceBrightness => throw _privateConstructorUsedError;
  double? get redshift => throw _privateConstructorUsedError;
  String? get morphology =>
      throw _privateConstructorUsedError; // External references
  String? get simbadId => throw _privateConstructorUsedError;
  String? get wikipediaUrl => throw _privateConstructorUsedError;
  Map<String, String>? get catalogIds =>
      throw _privateConstructorUsedError; // {"NGC": "224", "M": "31"}
// Cache metadata
  DateTime? get lastUpdated => throw _privateConstructorUsedError;
  String? get dataSource => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ObjectDataCopyWith<ObjectData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ObjectDataCopyWith<$Res> {
  factory $ObjectDataCopyWith(
          ObjectData value, $Res Function(ObjectData) then) =
      _$ObjectDataCopyWithImpl<$Res, ObjectData>;
  @useResult
  $Res call(
      {String? description,
      String? objectClass,
      SpectralClass? spectralType,
      double? temperature,
      double? mass,
      double? radius,
      double? luminosity,
      double? distance,
      double? parallax,
      String? properMotion,
      List<ExoplanetData>? exoplanets,
      double? surfaceBrightness,
      double? redshift,
      String? morphology,
      String? simbadId,
      String? wikipediaUrl,
      Map<String, String>? catalogIds,
      DateTime? lastUpdated,
      String? dataSource});
}

/// @nodoc
class _$ObjectDataCopyWithImpl<$Res, $Val extends ObjectData>
    implements $ObjectDataCopyWith<$Res> {
  _$ObjectDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? description = freezed,
    Object? objectClass = freezed,
    Object? spectralType = freezed,
    Object? temperature = freezed,
    Object? mass = freezed,
    Object? radius = freezed,
    Object? luminosity = freezed,
    Object? distance = freezed,
    Object? parallax = freezed,
    Object? properMotion = freezed,
    Object? exoplanets = freezed,
    Object? surfaceBrightness = freezed,
    Object? redshift = freezed,
    Object? morphology = freezed,
    Object? simbadId = freezed,
    Object? wikipediaUrl = freezed,
    Object? catalogIds = freezed,
    Object? lastUpdated = freezed,
    Object? dataSource = freezed,
  }) {
    return _then(_value.copyWith(
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      objectClass: freezed == objectClass
          ? _value.objectClass
          : objectClass // ignore: cast_nullable_to_non_nullable
              as String?,
      spectralType: freezed == spectralType
          ? _value.spectralType
          : spectralType // ignore: cast_nullable_to_non_nullable
              as SpectralClass?,
      temperature: freezed == temperature
          ? _value.temperature
          : temperature // ignore: cast_nullable_to_non_nullable
              as double?,
      mass: freezed == mass
          ? _value.mass
          : mass // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      luminosity: freezed == luminosity
          ? _value.luminosity
          : luminosity // ignore: cast_nullable_to_non_nullable
              as double?,
      distance: freezed == distance
          ? _value.distance
          : distance // ignore: cast_nullable_to_non_nullable
              as double?,
      parallax: freezed == parallax
          ? _value.parallax
          : parallax // ignore: cast_nullable_to_non_nullable
              as double?,
      properMotion: freezed == properMotion
          ? _value.properMotion
          : properMotion // ignore: cast_nullable_to_non_nullable
              as String?,
      exoplanets: freezed == exoplanets
          ? _value.exoplanets
          : exoplanets // ignore: cast_nullable_to_non_nullable
              as List<ExoplanetData>?,
      surfaceBrightness: freezed == surfaceBrightness
          ? _value.surfaceBrightness
          : surfaceBrightness // ignore: cast_nullable_to_non_nullable
              as double?,
      redshift: freezed == redshift
          ? _value.redshift
          : redshift // ignore: cast_nullable_to_non_nullable
              as double?,
      morphology: freezed == morphology
          ? _value.morphology
          : morphology // ignore: cast_nullable_to_non_nullable
              as String?,
      simbadId: freezed == simbadId
          ? _value.simbadId
          : simbadId // ignore: cast_nullable_to_non_nullable
              as String?,
      wikipediaUrl: freezed == wikipediaUrl
          ? _value.wikipediaUrl
          : wikipediaUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      catalogIds: freezed == catalogIds
          ? _value.catalogIds
          : catalogIds // ignore: cast_nullable_to_non_nullable
              as Map<String, String>?,
      lastUpdated: freezed == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      dataSource: freezed == dataSource
          ? _value.dataSource
          : dataSource // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ObjectDataImplCopyWith<$Res>
    implements $ObjectDataCopyWith<$Res> {
  factory _$$ObjectDataImplCopyWith(
          _$ObjectDataImpl value, $Res Function(_$ObjectDataImpl) then) =
      __$$ObjectDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? description,
      String? objectClass,
      SpectralClass? spectralType,
      double? temperature,
      double? mass,
      double? radius,
      double? luminosity,
      double? distance,
      double? parallax,
      String? properMotion,
      List<ExoplanetData>? exoplanets,
      double? surfaceBrightness,
      double? redshift,
      String? morphology,
      String? simbadId,
      String? wikipediaUrl,
      Map<String, String>? catalogIds,
      DateTime? lastUpdated,
      String? dataSource});
}

/// @nodoc
class __$$ObjectDataImplCopyWithImpl<$Res>
    extends _$ObjectDataCopyWithImpl<$Res, _$ObjectDataImpl>
    implements _$$ObjectDataImplCopyWith<$Res> {
  __$$ObjectDataImplCopyWithImpl(
      _$ObjectDataImpl _value, $Res Function(_$ObjectDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? description = freezed,
    Object? objectClass = freezed,
    Object? spectralType = freezed,
    Object? temperature = freezed,
    Object? mass = freezed,
    Object? radius = freezed,
    Object? luminosity = freezed,
    Object? distance = freezed,
    Object? parallax = freezed,
    Object? properMotion = freezed,
    Object? exoplanets = freezed,
    Object? surfaceBrightness = freezed,
    Object? redshift = freezed,
    Object? morphology = freezed,
    Object? simbadId = freezed,
    Object? wikipediaUrl = freezed,
    Object? catalogIds = freezed,
    Object? lastUpdated = freezed,
    Object? dataSource = freezed,
  }) {
    return _then(_$ObjectDataImpl(
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      objectClass: freezed == objectClass
          ? _value.objectClass
          : objectClass // ignore: cast_nullable_to_non_nullable
              as String?,
      spectralType: freezed == spectralType
          ? _value.spectralType
          : spectralType // ignore: cast_nullable_to_non_nullable
              as SpectralClass?,
      temperature: freezed == temperature
          ? _value.temperature
          : temperature // ignore: cast_nullable_to_non_nullable
              as double?,
      mass: freezed == mass
          ? _value.mass
          : mass // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      luminosity: freezed == luminosity
          ? _value.luminosity
          : luminosity // ignore: cast_nullable_to_non_nullable
              as double?,
      distance: freezed == distance
          ? _value.distance
          : distance // ignore: cast_nullable_to_non_nullable
              as double?,
      parallax: freezed == parallax
          ? _value.parallax
          : parallax // ignore: cast_nullable_to_non_nullable
              as double?,
      properMotion: freezed == properMotion
          ? _value.properMotion
          : properMotion // ignore: cast_nullable_to_non_nullable
              as String?,
      exoplanets: freezed == exoplanets
          ? _value._exoplanets
          : exoplanets // ignore: cast_nullable_to_non_nullable
              as List<ExoplanetData>?,
      surfaceBrightness: freezed == surfaceBrightness
          ? _value.surfaceBrightness
          : surfaceBrightness // ignore: cast_nullable_to_non_nullable
              as double?,
      redshift: freezed == redshift
          ? _value.redshift
          : redshift // ignore: cast_nullable_to_non_nullable
              as double?,
      morphology: freezed == morphology
          ? _value.morphology
          : morphology // ignore: cast_nullable_to_non_nullable
              as String?,
      simbadId: freezed == simbadId
          ? _value.simbadId
          : simbadId // ignore: cast_nullable_to_non_nullable
              as String?,
      wikipediaUrl: freezed == wikipediaUrl
          ? _value.wikipediaUrl
          : wikipediaUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      catalogIds: freezed == catalogIds
          ? _value._catalogIds
          : catalogIds // ignore: cast_nullable_to_non_nullable
              as Map<String, String>?,
      lastUpdated: freezed == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      dataSource: freezed == dataSource
          ? _value.dataSource
          : dataSource // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ObjectDataImpl implements _ObjectData {
  const _$ObjectDataImpl(
      {this.description,
      this.objectClass,
      this.spectralType,
      this.temperature,
      this.mass,
      this.radius,
      this.luminosity,
      this.distance,
      this.parallax,
      this.properMotion,
      final List<ExoplanetData>? exoplanets,
      this.surfaceBrightness,
      this.redshift,
      this.morphology,
      this.simbadId,
      this.wikipediaUrl,
      final Map<String, String>? catalogIds,
      this.lastUpdated,
      this.dataSource})
      : _exoplanets = exoplanets,
        _catalogIds = catalogIds;

  factory _$ObjectDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ObjectDataImplFromJson(json);

// Basic info
  @override
  final String? description;
  @override
  final String? objectClass;
// e.g., "Spiral Galaxy", "Open Cluster"
// Stellar data (for stars)
  @override
  final SpectralClass? spectralType;
  @override
  final double? temperature;
// Kelvin
  @override
  final double? mass;
// Solar masses
  @override
  final double? radius;
// Solar radii
  @override
  final double? luminosity;
// Solar luminosities
  @override
  final double? distance;
// parsecs
  @override
  final double? parallax;
// milliarcseconds
  @override
  final String? properMotion;
// Exoplanet data
  final List<ExoplanetData>? _exoplanets;
// Exoplanet data
  @override
  List<ExoplanetData>? get exoplanets {
    final value = _exoplanets;
    if (value == null) return null;
    if (_exoplanets is EqualUnmodifiableListView) return _exoplanets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

// DSO data (galaxies, nebulae, clusters)
  @override
  final double? surfaceBrightness;
  @override
  final double? redshift;
  @override
  final String? morphology;
// External references
  @override
  final String? simbadId;
  @override
  final String? wikipediaUrl;
  final Map<String, String>? _catalogIds;
  @override
  Map<String, String>? get catalogIds {
    final value = _catalogIds;
    if (value == null) return null;
    if (_catalogIds is EqualUnmodifiableMapView) return _catalogIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

// {"NGC": "224", "M": "31"}
// Cache metadata
  @override
  final DateTime? lastUpdated;
  @override
  final String? dataSource;

  @override
  String toString() {
    return 'ObjectData(description: $description, objectClass: $objectClass, spectralType: $spectralType, temperature: $temperature, mass: $mass, radius: $radius, luminosity: $luminosity, distance: $distance, parallax: $parallax, properMotion: $properMotion, exoplanets: $exoplanets, surfaceBrightness: $surfaceBrightness, redshift: $redshift, morphology: $morphology, simbadId: $simbadId, wikipediaUrl: $wikipediaUrl, catalogIds: $catalogIds, lastUpdated: $lastUpdated, dataSource: $dataSource)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ObjectDataImpl &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.objectClass, objectClass) ||
                other.objectClass == objectClass) &&
            (identical(other.spectralType, spectralType) ||
                other.spectralType == spectralType) &&
            (identical(other.temperature, temperature) ||
                other.temperature == temperature) &&
            (identical(other.mass, mass) || other.mass == mass) &&
            (identical(other.radius, radius) || other.radius == radius) &&
            (identical(other.luminosity, luminosity) ||
                other.luminosity == luminosity) &&
            (identical(other.distance, distance) ||
                other.distance == distance) &&
            (identical(other.parallax, parallax) ||
                other.parallax == parallax) &&
            (identical(other.properMotion, properMotion) ||
                other.properMotion == properMotion) &&
            const DeepCollectionEquality()
                .equals(other._exoplanets, _exoplanets) &&
            (identical(other.surfaceBrightness, surfaceBrightness) ||
                other.surfaceBrightness == surfaceBrightness) &&
            (identical(other.redshift, redshift) ||
                other.redshift == redshift) &&
            (identical(other.morphology, morphology) ||
                other.morphology == morphology) &&
            (identical(other.simbadId, simbadId) ||
                other.simbadId == simbadId) &&
            (identical(other.wikipediaUrl, wikipediaUrl) ||
                other.wikipediaUrl == wikipediaUrl) &&
            const DeepCollectionEquality()
                .equals(other._catalogIds, _catalogIds) &&
            (identical(other.lastUpdated, lastUpdated) ||
                other.lastUpdated == lastUpdated) &&
            (identical(other.dataSource, dataSource) ||
                other.dataSource == dataSource));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        description,
        objectClass,
        spectralType,
        temperature,
        mass,
        radius,
        luminosity,
        distance,
        parallax,
        properMotion,
        const DeepCollectionEquality().hash(_exoplanets),
        surfaceBrightness,
        redshift,
        morphology,
        simbadId,
        wikipediaUrl,
        const DeepCollectionEquality().hash(_catalogIds),
        lastUpdated,
        dataSource
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ObjectDataImplCopyWith<_$ObjectDataImpl> get copyWith =>
      __$$ObjectDataImplCopyWithImpl<_$ObjectDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ObjectDataImplToJson(
      this,
    );
  }
}

abstract class _ObjectData implements ObjectData {
  const factory _ObjectData(
      {final String? description,
      final String? objectClass,
      final SpectralClass? spectralType,
      final double? temperature,
      final double? mass,
      final double? radius,
      final double? luminosity,
      final double? distance,
      final double? parallax,
      final String? properMotion,
      final List<ExoplanetData>? exoplanets,
      final double? surfaceBrightness,
      final double? redshift,
      final String? morphology,
      final String? simbadId,
      final String? wikipediaUrl,
      final Map<String, String>? catalogIds,
      final DateTime? lastUpdated,
      final String? dataSource}) = _$ObjectDataImpl;

  factory _ObjectData.fromJson(Map<String, dynamic> json) =
      _$ObjectDataImpl.fromJson;

  @override // Basic info
  String? get description;
  @override
  String? get objectClass;
  @override // e.g., "Spiral Galaxy", "Open Cluster"
// Stellar data (for stars)
  SpectralClass? get spectralType;
  @override
  double? get temperature;
  @override // Kelvin
  double? get mass;
  @override // Solar masses
  double? get radius;
  @override // Solar radii
  double? get luminosity;
  @override // Solar luminosities
  double? get distance;
  @override // parsecs
  double? get parallax;
  @override // milliarcseconds
  String? get properMotion;
  @override // Exoplanet data
  List<ExoplanetData>? get exoplanets;
  @override // DSO data (galaxies, nebulae, clusters)
  double? get surfaceBrightness;
  @override
  double? get redshift;
  @override
  String? get morphology;
  @override // External references
  String? get simbadId;
  @override
  String? get wikipediaUrl;
  @override
  Map<String, String>? get catalogIds;
  @override // {"NGC": "224", "M": "31"}
// Cache metadata
  DateTime? get lastUpdated;
  @override
  String? get dataSource;
  @override
  @JsonKey(ignore: true)
  _$$ObjectDataImplCopyWith<_$ObjectDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ExoplanetData _$ExoplanetDataFromJson(Map<String, dynamic> json) {
  return _ExoplanetData.fromJson(json);
}

/// @nodoc
mixin _$ExoplanetData {
  String get name => throw _privateConstructorUsedError;
  double? get mass => throw _privateConstructorUsedError; // Jupiter masses
  double? get radius => throw _privateConstructorUsedError; // Jupiter radii
  double? get orbitalPeriod => throw _privateConstructorUsedError; // days
  double? get semiMajorAxis => throw _privateConstructorUsedError; // AU
  double? get eccentricity => throw _privateConstructorUsedError;
  String? get discoveryMethod => throw _privateConstructorUsedError;
  int? get discoveryYear => throw _privateConstructorUsedError;
  double? get equilibriumTemp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ExoplanetDataCopyWith<ExoplanetData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExoplanetDataCopyWith<$Res> {
  factory $ExoplanetDataCopyWith(
          ExoplanetData value, $Res Function(ExoplanetData) then) =
      _$ExoplanetDataCopyWithImpl<$Res, ExoplanetData>;
  @useResult
  $Res call(
      {String name,
      double? mass,
      double? radius,
      double? orbitalPeriod,
      double? semiMajorAxis,
      double? eccentricity,
      String? discoveryMethod,
      int? discoveryYear,
      double? equilibriumTemp});
}

/// @nodoc
class _$ExoplanetDataCopyWithImpl<$Res, $Val extends ExoplanetData>
    implements $ExoplanetDataCopyWith<$Res> {
  _$ExoplanetDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? mass = freezed,
    Object? radius = freezed,
    Object? orbitalPeriod = freezed,
    Object? semiMajorAxis = freezed,
    Object? eccentricity = freezed,
    Object? discoveryMethod = freezed,
    Object? discoveryYear = freezed,
    Object? equilibriumTemp = freezed,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      mass: freezed == mass
          ? _value.mass
          : mass // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      orbitalPeriod: freezed == orbitalPeriod
          ? _value.orbitalPeriod
          : orbitalPeriod // ignore: cast_nullable_to_non_nullable
              as double?,
      semiMajorAxis: freezed == semiMajorAxis
          ? _value.semiMajorAxis
          : semiMajorAxis // ignore: cast_nullable_to_non_nullable
              as double?,
      eccentricity: freezed == eccentricity
          ? _value.eccentricity
          : eccentricity // ignore: cast_nullable_to_non_nullable
              as double?,
      discoveryMethod: freezed == discoveryMethod
          ? _value.discoveryMethod
          : discoveryMethod // ignore: cast_nullable_to_non_nullable
              as String?,
      discoveryYear: freezed == discoveryYear
          ? _value.discoveryYear
          : discoveryYear // ignore: cast_nullable_to_non_nullable
              as int?,
      equilibriumTemp: freezed == equilibriumTemp
          ? _value.equilibriumTemp
          : equilibriumTemp // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExoplanetDataImplCopyWith<$Res>
    implements $ExoplanetDataCopyWith<$Res> {
  factory _$$ExoplanetDataImplCopyWith(
          _$ExoplanetDataImpl value, $Res Function(_$ExoplanetDataImpl) then) =
      __$$ExoplanetDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      double? mass,
      double? radius,
      double? orbitalPeriod,
      double? semiMajorAxis,
      double? eccentricity,
      String? discoveryMethod,
      int? discoveryYear,
      double? equilibriumTemp});
}

/// @nodoc
class __$$ExoplanetDataImplCopyWithImpl<$Res>
    extends _$ExoplanetDataCopyWithImpl<$Res, _$ExoplanetDataImpl>
    implements _$$ExoplanetDataImplCopyWith<$Res> {
  __$$ExoplanetDataImplCopyWithImpl(
      _$ExoplanetDataImpl _value, $Res Function(_$ExoplanetDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? mass = freezed,
    Object? radius = freezed,
    Object? orbitalPeriod = freezed,
    Object? semiMajorAxis = freezed,
    Object? eccentricity = freezed,
    Object? discoveryMethod = freezed,
    Object? discoveryYear = freezed,
    Object? equilibriumTemp = freezed,
  }) {
    return _then(_$ExoplanetDataImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      mass: freezed == mass
          ? _value.mass
          : mass // ignore: cast_nullable_to_non_nullable
              as double?,
      radius: freezed == radius
          ? _value.radius
          : radius // ignore: cast_nullable_to_non_nullable
              as double?,
      orbitalPeriod: freezed == orbitalPeriod
          ? _value.orbitalPeriod
          : orbitalPeriod // ignore: cast_nullable_to_non_nullable
              as double?,
      semiMajorAxis: freezed == semiMajorAxis
          ? _value.semiMajorAxis
          : semiMajorAxis // ignore: cast_nullable_to_non_nullable
              as double?,
      eccentricity: freezed == eccentricity
          ? _value.eccentricity
          : eccentricity // ignore: cast_nullable_to_non_nullable
              as double?,
      discoveryMethod: freezed == discoveryMethod
          ? _value.discoveryMethod
          : discoveryMethod // ignore: cast_nullable_to_non_nullable
              as String?,
      discoveryYear: freezed == discoveryYear
          ? _value.discoveryYear
          : discoveryYear // ignore: cast_nullable_to_non_nullable
              as int?,
      equilibriumTemp: freezed == equilibriumTemp
          ? _value.equilibriumTemp
          : equilibriumTemp // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExoplanetDataImpl implements _ExoplanetData {
  const _$ExoplanetDataImpl(
      {required this.name,
      this.mass,
      this.radius,
      this.orbitalPeriod,
      this.semiMajorAxis,
      this.eccentricity,
      this.discoveryMethod,
      this.discoveryYear,
      this.equilibriumTemp});

  factory _$ExoplanetDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExoplanetDataImplFromJson(json);

  @override
  final String name;
  @override
  final double? mass;
// Jupiter masses
  @override
  final double? radius;
// Jupiter radii
  @override
  final double? orbitalPeriod;
// days
  @override
  final double? semiMajorAxis;
// AU
  @override
  final double? eccentricity;
  @override
  final String? discoveryMethod;
  @override
  final int? discoveryYear;
  @override
  final double? equilibriumTemp;

  @override
  String toString() {
    return 'ExoplanetData(name: $name, mass: $mass, radius: $radius, orbitalPeriod: $orbitalPeriod, semiMajorAxis: $semiMajorAxis, eccentricity: $eccentricity, discoveryMethod: $discoveryMethod, discoveryYear: $discoveryYear, equilibriumTemp: $equilibriumTemp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExoplanetDataImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.mass, mass) || other.mass == mass) &&
            (identical(other.radius, radius) || other.radius == radius) &&
            (identical(other.orbitalPeriod, orbitalPeriod) ||
                other.orbitalPeriod == orbitalPeriod) &&
            (identical(other.semiMajorAxis, semiMajorAxis) ||
                other.semiMajorAxis == semiMajorAxis) &&
            (identical(other.eccentricity, eccentricity) ||
                other.eccentricity == eccentricity) &&
            (identical(other.discoveryMethod, discoveryMethod) ||
                other.discoveryMethod == discoveryMethod) &&
            (identical(other.discoveryYear, discoveryYear) ||
                other.discoveryYear == discoveryYear) &&
            (identical(other.equilibriumTemp, equilibriumTemp) ||
                other.equilibriumTemp == equilibriumTemp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      name,
      mass,
      radius,
      orbitalPeriod,
      semiMajorAxis,
      eccentricity,
      discoveryMethod,
      discoveryYear,
      equilibriumTemp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ExoplanetDataImplCopyWith<_$ExoplanetDataImpl> get copyWith =>
      __$$ExoplanetDataImplCopyWithImpl<_$ExoplanetDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExoplanetDataImplToJson(
      this,
    );
  }
}

abstract class _ExoplanetData implements ExoplanetData {
  const factory _ExoplanetData(
      {required final String name,
      final double? mass,
      final double? radius,
      final double? orbitalPeriod,
      final double? semiMajorAxis,
      final double? eccentricity,
      final String? discoveryMethod,
      final int? discoveryYear,
      final double? equilibriumTemp}) = _$ExoplanetDataImpl;

  factory _ExoplanetData.fromJson(Map<String, dynamic> json) =
      _$ExoplanetDataImpl.fromJson;

  @override
  String get name;
  @override
  double? get mass;
  @override // Jupiter masses
  double? get radius;
  @override // Jupiter radii
  double? get orbitalPeriod;
  @override // days
  double? get semiMajorAxis;
  @override // AU
  double? get eccentricity;
  @override
  String? get discoveryMethod;
  @override
  int? get discoveryYear;
  @override
  double? get equilibriumTemp;
  @override
  @JsonKey(ignore: true)
  _$$ExoplanetDataImplCopyWith<_$ExoplanetDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
