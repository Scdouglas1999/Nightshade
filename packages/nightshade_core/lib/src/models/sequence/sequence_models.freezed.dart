// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sequence_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MosaicPanelInfo _$MosaicPanelInfoFromJson(Map<String, dynamic> json) {
  return _MosaicPanelInfo.fromJson(json);
}

/// @nodoc
mixin _$MosaicPanelInfo {
  String get mosaicName => throw _privateConstructorUsedError;
  int get panelIndex => throw _privateConstructorUsedError;
  int get totalPanels => throw _privateConstructorUsedError;
  int get row => throw _privateConstructorUsedError;
  int get column => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $MosaicPanelInfoCopyWith<MosaicPanelInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MosaicPanelInfoCopyWith<$Res> {
  factory $MosaicPanelInfoCopyWith(
          MosaicPanelInfo value, $Res Function(MosaicPanelInfo) then) =
      _$MosaicPanelInfoCopyWithImpl<$Res, MosaicPanelInfo>;
  @useResult
  $Res call(
      {String mosaicName,
      int panelIndex,
      int totalPanels,
      int row,
      int column});
}

/// @nodoc
class _$MosaicPanelInfoCopyWithImpl<$Res, $Val extends MosaicPanelInfo>
    implements $MosaicPanelInfoCopyWith<$Res> {
  _$MosaicPanelInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mosaicName = null,
    Object? panelIndex = null,
    Object? totalPanels = null,
    Object? row = null,
    Object? column = null,
  }) {
    return _then(_value.copyWith(
      mosaicName: null == mosaicName
          ? _value.mosaicName
          : mosaicName // ignore: cast_nullable_to_non_nullable
              as String,
      panelIndex: null == panelIndex
          ? _value.panelIndex
          : panelIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPanels: null == totalPanels
          ? _value.totalPanels
          : totalPanels // ignore: cast_nullable_to_non_nullable
              as int,
      row: null == row
          ? _value.row
          : row // ignore: cast_nullable_to_non_nullable
              as int,
      column: null == column
          ? _value.column
          : column // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MosaicPanelInfoImplCopyWith<$Res>
    implements $MosaicPanelInfoCopyWith<$Res> {
  factory _$$MosaicPanelInfoImplCopyWith(_$MosaicPanelInfoImpl value,
          $Res Function(_$MosaicPanelInfoImpl) then) =
      __$$MosaicPanelInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String mosaicName,
      int panelIndex,
      int totalPanels,
      int row,
      int column});
}

/// @nodoc
class __$$MosaicPanelInfoImplCopyWithImpl<$Res>
    extends _$MosaicPanelInfoCopyWithImpl<$Res, _$MosaicPanelInfoImpl>
    implements _$$MosaicPanelInfoImplCopyWith<$Res> {
  __$$MosaicPanelInfoImplCopyWithImpl(
      _$MosaicPanelInfoImpl _value, $Res Function(_$MosaicPanelInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mosaicName = null,
    Object? panelIndex = null,
    Object? totalPanels = null,
    Object? row = null,
    Object? column = null,
  }) {
    return _then(_$MosaicPanelInfoImpl(
      mosaicName: null == mosaicName
          ? _value.mosaicName
          : mosaicName // ignore: cast_nullable_to_non_nullable
              as String,
      panelIndex: null == panelIndex
          ? _value.panelIndex
          : panelIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPanels: null == totalPanels
          ? _value.totalPanels
          : totalPanels // ignore: cast_nullable_to_non_nullable
              as int,
      row: null == row
          ? _value.row
          : row // ignore: cast_nullable_to_non_nullable
              as int,
      column: null == column
          ? _value.column
          : column // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$MosaicPanelInfoImpl extends _MosaicPanelInfo {
  const _$MosaicPanelInfoImpl(
      {required this.mosaicName,
      required this.panelIndex,
      required this.totalPanels,
      required this.row,
      required this.column})
      : super._();

  factory _$MosaicPanelInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$MosaicPanelInfoImplFromJson(json);

  @override
  final String mosaicName;
  @override
  final int panelIndex;
  @override
  final int totalPanels;
  @override
  final int row;
  @override
  final int column;

  @override
  String toString() {
    return 'MosaicPanelInfo(mosaicName: $mosaicName, panelIndex: $panelIndex, totalPanels: $totalPanels, row: $row, column: $column)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MosaicPanelInfoImpl &&
            (identical(other.mosaicName, mosaicName) ||
                other.mosaicName == mosaicName) &&
            (identical(other.panelIndex, panelIndex) ||
                other.panelIndex == panelIndex) &&
            (identical(other.totalPanels, totalPanels) ||
                other.totalPanels == totalPanels) &&
            (identical(other.row, row) || other.row == row) &&
            (identical(other.column, column) || other.column == column));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, mosaicName, panelIndex, totalPanels, row, column);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MosaicPanelInfoImplCopyWith<_$MosaicPanelInfoImpl> get copyWith =>
      __$$MosaicPanelInfoImplCopyWithImpl<_$MosaicPanelInfoImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MosaicPanelInfoImplToJson(
      this,
    );
  }
}

abstract class _MosaicPanelInfo extends MosaicPanelInfo {
  const factory _MosaicPanelInfo(
      {required final String mosaicName,
      required final int panelIndex,
      required final int totalPanels,
      required final int row,
      required final int column}) = _$MosaicPanelInfoImpl;
  const _MosaicPanelInfo._() : super._();

  factory _MosaicPanelInfo.fromJson(Map<String, dynamic> json) =
      _$MosaicPanelInfoImpl.fromJson;

  @override
  String get mosaicName;
  @override
  int get panelIndex;
  @override
  int get totalPanels;
  @override
  int get row;
  @override
  int get column;
  @override
  @JsonKey(ignore: true)
  _$$MosaicPanelInfoImplCopyWith<_$MosaicPanelInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
