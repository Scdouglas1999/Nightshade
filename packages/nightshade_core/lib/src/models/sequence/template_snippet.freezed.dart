// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'template_snippet.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TemplateSnippet _$TemplateSnippetFromJson(Map<String, dynamic> json) {
  return _TemplateSnippet.fromJson(json);
}

/// @nodoc
mixin _$TemplateSnippet {
  /// Unique identifier for this snippet
  String get id => throw _privateConstructorUsedError;

  /// Display name for the snippet
  String get name => throw _privateConstructorUsedError;

  /// Description of what this snippet does
  String get description => throw _privateConstructorUsedError;

  /// Category for organization
  SnippetCategory get category => throw _privateConstructorUsedError;

  /// Lucide icon name (e.g., 'focus', 'filter', 'shield')
  String get iconName => throw _privateConstructorUsedError;

  /// Serialized node data for recreation when inserting
  List<Map<String, dynamic>> get nodeData => throw _privateConstructorUsedError;

  /// Whether this is a built-in snippet (cannot be deleted)
  bool get isBuiltIn => throw _privateConstructorUsedError;

  /// When this snippet was created
  DateTime get createdAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TemplateSnippetCopyWith<TemplateSnippet> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TemplateSnippetCopyWith<$Res> {
  factory $TemplateSnippetCopyWith(
          TemplateSnippet value, $Res Function(TemplateSnippet) then) =
      _$TemplateSnippetCopyWithImpl<$Res, TemplateSnippet>;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      SnippetCategory category,
      String iconName,
      List<Map<String, dynamic>> nodeData,
      bool isBuiltIn,
      DateTime createdAt});
}

/// @nodoc
class _$TemplateSnippetCopyWithImpl<$Res, $Val extends TemplateSnippet>
    implements $TemplateSnippetCopyWith<$Res> {
  _$TemplateSnippetCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? category = null,
    Object? iconName = null,
    Object? nodeData = null,
    Object? isBuiltIn = null,
    Object? createdAt = null,
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
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as SnippetCategory,
      iconName: null == iconName
          ? _value.iconName
          : iconName // ignore: cast_nullable_to_non_nullable
              as String,
      nodeData: null == nodeData
          ? _value.nodeData
          : nodeData // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      isBuiltIn: null == isBuiltIn
          ? _value.isBuiltIn
          : isBuiltIn // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TemplateSnippetImplCopyWith<$Res>
    implements $TemplateSnippetCopyWith<$Res> {
  factory _$$TemplateSnippetImplCopyWith(_$TemplateSnippetImpl value,
          $Res Function(_$TemplateSnippetImpl) then) =
      __$$TemplateSnippetImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      SnippetCategory category,
      String iconName,
      List<Map<String, dynamic>> nodeData,
      bool isBuiltIn,
      DateTime createdAt});
}

/// @nodoc
class __$$TemplateSnippetImplCopyWithImpl<$Res>
    extends _$TemplateSnippetCopyWithImpl<$Res, _$TemplateSnippetImpl>
    implements _$$TemplateSnippetImplCopyWith<$Res> {
  __$$TemplateSnippetImplCopyWithImpl(
      _$TemplateSnippetImpl _value, $Res Function(_$TemplateSnippetImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? category = null,
    Object? iconName = null,
    Object? nodeData = null,
    Object? isBuiltIn = null,
    Object? createdAt = null,
  }) {
    return _then(_$TemplateSnippetImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as SnippetCategory,
      iconName: null == iconName
          ? _value.iconName
          : iconName // ignore: cast_nullable_to_non_nullable
              as String,
      nodeData: null == nodeData
          ? _value._nodeData
          : nodeData // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      isBuiltIn: null == isBuiltIn
          ? _value.isBuiltIn
          : isBuiltIn // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TemplateSnippetImpl extends _TemplateSnippet {
  const _$TemplateSnippetImpl(
      {required this.id,
      required this.name,
      required this.description,
      required this.category,
      required this.iconName,
      required final List<Map<String, dynamic>> nodeData,
      this.isBuiltIn = false,
      required this.createdAt})
      : _nodeData = nodeData,
        super._();

  factory _$TemplateSnippetImpl.fromJson(Map<String, dynamic> json) =>
      _$$TemplateSnippetImplFromJson(json);

  /// Unique identifier for this snippet
  @override
  final String id;

  /// Display name for the snippet
  @override
  final String name;

  /// Description of what this snippet does
  @override
  final String description;

  /// Category for organization
  @override
  final SnippetCategory category;

  /// Lucide icon name (e.g., 'focus', 'filter', 'shield')
  @override
  final String iconName;

  /// Serialized node data for recreation when inserting
  final List<Map<String, dynamic>> _nodeData;

  /// Serialized node data for recreation when inserting
  @override
  List<Map<String, dynamic>> get nodeData {
    if (_nodeData is EqualUnmodifiableListView) return _nodeData;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_nodeData);
  }

  /// Whether this is a built-in snippet (cannot be deleted)
  @override
  @JsonKey()
  final bool isBuiltIn;

  /// When this snippet was created
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'TemplateSnippet(id: $id, name: $name, description: $description, category: $category, iconName: $iconName, nodeData: $nodeData, isBuiltIn: $isBuiltIn, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TemplateSnippetImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.iconName, iconName) ||
                other.iconName == iconName) &&
            const DeepCollectionEquality().equals(other._nodeData, _nodeData) &&
            (identical(other.isBuiltIn, isBuiltIn) ||
                other.isBuiltIn == isBuiltIn) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      category,
      iconName,
      const DeepCollectionEquality().hash(_nodeData),
      isBuiltIn,
      createdAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TemplateSnippetImplCopyWith<_$TemplateSnippetImpl> get copyWith =>
      __$$TemplateSnippetImplCopyWithImpl<_$TemplateSnippetImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TemplateSnippetImplToJson(
      this,
    );
  }
}

abstract class _TemplateSnippet extends TemplateSnippet {
  const factory _TemplateSnippet(
      {required final String id,
      required final String name,
      required final String description,
      required final SnippetCategory category,
      required final String iconName,
      required final List<Map<String, dynamic>> nodeData,
      final bool isBuiltIn,
      required final DateTime createdAt}) = _$TemplateSnippetImpl;
  const _TemplateSnippet._() : super._();

  factory _TemplateSnippet.fromJson(Map<String, dynamic> json) =
      _$TemplateSnippetImpl.fromJson;

  @override

  /// Unique identifier for this snippet
  String get id;
  @override

  /// Display name for the snippet
  String get name;
  @override

  /// Description of what this snippet does
  String get description;
  @override

  /// Category for organization
  SnippetCategory get category;
  @override

  /// Lucide icon name (e.g., 'focus', 'filter', 'shield')
  String get iconName;
  @override

  /// Serialized node data for recreation when inserting
  List<Map<String, dynamic>> get nodeData;
  @override

  /// Whether this is a built-in snippet (cannot be deleted)
  bool get isBuiltIn;
  @override

  /// When this snippet was created
  DateTime get createdAt;
  @override
  @JsonKey(ignore: true)
  _$$TemplateSnippetImplCopyWith<_$TemplateSnippetImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
