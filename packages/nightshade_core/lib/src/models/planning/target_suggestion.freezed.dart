// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'target_suggestion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TargetSuggestion _$TargetSuggestionFromJson(Map<String, dynamic> json) {
  return _TargetSuggestion.fromJson(json);
}

/// @nodoc
mixin _$TargetSuggestion {
  /// Database target ID
  int get targetId => throw _privateConstructorUsedError;

  /// Display name of the target
  String get targetName => throw _privateConstructorUsedError;

  /// Catalog identifier (e.g., "NGC 7000", "M31")
  String? get catalogId => throw _privateConstructorUsedError;

  /// Right Ascension in hours (0-24)
  double get raHours => throw _privateConstructorUsedError;

  /// Declination in degrees (-90 to +90)
  double get decDegrees => throw _privateConstructorUsedError;

  /// Overall score from 0-100
  double get totalScore => throw _privateConstructorUsedError;

  /// Breakdown of individual score components
  /// Keys: altitude, moonDistance, transitProximity, darkness, airmass
  Map<String, double> get scoreBreakdown => throw _privateConstructorUsedError;

  /// Warnings about target conditions
  @TargetWarningListConverter()
  List<TargetWarning> get warnings => throw _privateConstructorUsedError;

  /// Visibility information for this target
  @TargetVisibilityInfoConverter()
  TargetVisibilityInfo get visibility => throw _privateConstructorUsedError;

  /// Human-readable explanation of why this target is suggested
  String get reasoning => throw _privateConstructorUsedError;

  /// Progress of data collection for this target (0.0 to 1.0)
  /// 0.0 = no data collected, 1.0 = fully complete
  double get dataProgress => throw _privateConstructorUsedError;

  /// Object type (e.g., "Galaxy", "Emission Nebula", "Open Cluster")
  String? get objectType => throw _privateConstructorUsedError;

  /// Visual magnitude
  double? get magnitude => throw _privateConstructorUsedError;

  /// Angular size in arcminutes
  double? get sizeArcmin => throw _privateConstructorUsedError;

  /// Constellation abbreviation
  String? get constellation => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TargetSuggestionCopyWith<TargetSuggestion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TargetSuggestionCopyWith<$Res> {
  factory $TargetSuggestionCopyWith(
          TargetSuggestion value, $Res Function(TargetSuggestion) then) =
      _$TargetSuggestionCopyWithImpl<$Res, TargetSuggestion>;
  @useResult
  $Res call(
      {int targetId,
      String targetName,
      String? catalogId,
      double raHours,
      double decDegrees,
      double totalScore,
      Map<String, double> scoreBreakdown,
      @TargetWarningListConverter() List<TargetWarning> warnings,
      @TargetVisibilityInfoConverter() TargetVisibilityInfo visibility,
      String reasoning,
      double dataProgress,
      String? objectType,
      double? magnitude,
      double? sizeArcmin,
      String? constellation});
}

/// @nodoc
class _$TargetSuggestionCopyWithImpl<$Res, $Val extends TargetSuggestion>
    implements $TargetSuggestionCopyWith<$Res> {
  _$TargetSuggestionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targetId = null,
    Object? targetName = null,
    Object? catalogId = freezed,
    Object? raHours = null,
    Object? decDegrees = null,
    Object? totalScore = null,
    Object? scoreBreakdown = null,
    Object? warnings = null,
    Object? visibility = null,
    Object? reasoning = null,
    Object? dataProgress = null,
    Object? objectType = freezed,
    Object? magnitude = freezed,
    Object? sizeArcmin = freezed,
    Object? constellation = freezed,
  }) {
    return _then(_value.copyWith(
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as int,
      targetName: null == targetName
          ? _value.targetName
          : targetName // ignore: cast_nullable_to_non_nullable
              as String,
      catalogId: freezed == catalogId
          ? _value.catalogId
          : catalogId // ignore: cast_nullable_to_non_nullable
              as String?,
      raHours: null == raHours
          ? _value.raHours
          : raHours // ignore: cast_nullable_to_non_nullable
              as double,
      decDegrees: null == decDegrees
          ? _value.decDegrees
          : decDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      totalScore: null == totalScore
          ? _value.totalScore
          : totalScore // ignore: cast_nullable_to_non_nullable
              as double,
      scoreBreakdown: null == scoreBreakdown
          ? _value.scoreBreakdown
          : scoreBreakdown // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      warnings: null == warnings
          ? _value.warnings
          : warnings // ignore: cast_nullable_to_non_nullable
              as List<TargetWarning>,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as TargetVisibilityInfo,
      reasoning: null == reasoning
          ? _value.reasoning
          : reasoning // ignore: cast_nullable_to_non_nullable
              as String,
      dataProgress: null == dataProgress
          ? _value.dataProgress
          : dataProgress // ignore: cast_nullable_to_non_nullable
              as double,
      objectType: freezed == objectType
          ? _value.objectType
          : objectType // ignore: cast_nullable_to_non_nullable
              as String?,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      sizeArcmin: freezed == sizeArcmin
          ? _value.sizeArcmin
          : sizeArcmin // ignore: cast_nullable_to_non_nullable
              as double?,
      constellation: freezed == constellation
          ? _value.constellation
          : constellation // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TargetSuggestionImplCopyWith<$Res>
    implements $TargetSuggestionCopyWith<$Res> {
  factory _$$TargetSuggestionImplCopyWith(_$TargetSuggestionImpl value,
          $Res Function(_$TargetSuggestionImpl) then) =
      __$$TargetSuggestionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int targetId,
      String targetName,
      String? catalogId,
      double raHours,
      double decDegrees,
      double totalScore,
      Map<String, double> scoreBreakdown,
      @TargetWarningListConverter() List<TargetWarning> warnings,
      @TargetVisibilityInfoConverter() TargetVisibilityInfo visibility,
      String reasoning,
      double dataProgress,
      String? objectType,
      double? magnitude,
      double? sizeArcmin,
      String? constellation});
}

/// @nodoc
class __$$TargetSuggestionImplCopyWithImpl<$Res>
    extends _$TargetSuggestionCopyWithImpl<$Res, _$TargetSuggestionImpl>
    implements _$$TargetSuggestionImplCopyWith<$Res> {
  __$$TargetSuggestionImplCopyWithImpl(_$TargetSuggestionImpl _value,
      $Res Function(_$TargetSuggestionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targetId = null,
    Object? targetName = null,
    Object? catalogId = freezed,
    Object? raHours = null,
    Object? decDegrees = null,
    Object? totalScore = null,
    Object? scoreBreakdown = null,
    Object? warnings = null,
    Object? visibility = null,
    Object? reasoning = null,
    Object? dataProgress = null,
    Object? objectType = freezed,
    Object? magnitude = freezed,
    Object? sizeArcmin = freezed,
    Object? constellation = freezed,
  }) {
    return _then(_$TargetSuggestionImpl(
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as int,
      targetName: null == targetName
          ? _value.targetName
          : targetName // ignore: cast_nullable_to_non_nullable
              as String,
      catalogId: freezed == catalogId
          ? _value.catalogId
          : catalogId // ignore: cast_nullable_to_non_nullable
              as String?,
      raHours: null == raHours
          ? _value.raHours
          : raHours // ignore: cast_nullable_to_non_nullable
              as double,
      decDegrees: null == decDegrees
          ? _value.decDegrees
          : decDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      totalScore: null == totalScore
          ? _value.totalScore
          : totalScore // ignore: cast_nullable_to_non_nullable
              as double,
      scoreBreakdown: null == scoreBreakdown
          ? _value._scoreBreakdown
          : scoreBreakdown // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      warnings: null == warnings
          ? _value._warnings
          : warnings // ignore: cast_nullable_to_non_nullable
              as List<TargetWarning>,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as TargetVisibilityInfo,
      reasoning: null == reasoning
          ? _value.reasoning
          : reasoning // ignore: cast_nullable_to_non_nullable
              as String,
      dataProgress: null == dataProgress
          ? _value.dataProgress
          : dataProgress // ignore: cast_nullable_to_non_nullable
              as double,
      objectType: freezed == objectType
          ? _value.objectType
          : objectType // ignore: cast_nullable_to_non_nullable
              as String?,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      sizeArcmin: freezed == sizeArcmin
          ? _value.sizeArcmin
          : sizeArcmin // ignore: cast_nullable_to_non_nullable
              as double?,
      constellation: freezed == constellation
          ? _value.constellation
          : constellation // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TargetSuggestionImpl implements _TargetSuggestion {
  const _$TargetSuggestionImpl(
      {required this.targetId,
      required this.targetName,
      this.catalogId,
      required this.raHours,
      required this.decDegrees,
      required this.totalScore,
      final Map<String, double> scoreBreakdown = const <String, double>{},
      @TargetWarningListConverter()
      final List<TargetWarning> warnings = const <TargetWarning>[],
      @TargetVisibilityInfoConverter() required this.visibility,
      this.reasoning = '',
      this.dataProgress = 0.0,
      this.objectType,
      this.magnitude,
      this.sizeArcmin,
      this.constellation})
      : _scoreBreakdown = scoreBreakdown,
        _warnings = warnings;

  factory _$TargetSuggestionImpl.fromJson(Map<String, dynamic> json) =>
      _$$TargetSuggestionImplFromJson(json);

  /// Database target ID
  @override
  final int targetId;

  /// Display name of the target
  @override
  final String targetName;

  /// Catalog identifier (e.g., "NGC 7000", "M31")
  @override
  final String? catalogId;

  /// Right Ascension in hours (0-24)
  @override
  final double raHours;

  /// Declination in degrees (-90 to +90)
  @override
  final double decDegrees;

  /// Overall score from 0-100
  @override
  final double totalScore;

  /// Breakdown of individual score components
  /// Keys: altitude, moonDistance, transitProximity, darkness, airmass
  final Map<String, double> _scoreBreakdown;

  /// Breakdown of individual score components
  /// Keys: altitude, moonDistance, transitProximity, darkness, airmass
  @override
  @JsonKey()
  Map<String, double> get scoreBreakdown {
    if (_scoreBreakdown is EqualUnmodifiableMapView) return _scoreBreakdown;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_scoreBreakdown);
  }

  /// Warnings about target conditions
  final List<TargetWarning> _warnings;

  /// Warnings about target conditions
  @override
  @JsonKey()
  @TargetWarningListConverter()
  List<TargetWarning> get warnings {
    if (_warnings is EqualUnmodifiableListView) return _warnings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_warnings);
  }

  /// Visibility information for this target
  @override
  @TargetVisibilityInfoConverter()
  final TargetVisibilityInfo visibility;

  /// Human-readable explanation of why this target is suggested
  @override
  @JsonKey()
  final String reasoning;

  /// Progress of data collection for this target (0.0 to 1.0)
  /// 0.0 = no data collected, 1.0 = fully complete
  @override
  @JsonKey()
  final double dataProgress;

  /// Object type (e.g., "Galaxy", "Emission Nebula", "Open Cluster")
  @override
  final String? objectType;

  /// Visual magnitude
  @override
  final double? magnitude;

  /// Angular size in arcminutes
  @override
  final double? sizeArcmin;

  /// Constellation abbreviation
  @override
  final String? constellation;

  @override
  String toString() {
    return 'TargetSuggestion(targetId: $targetId, targetName: $targetName, catalogId: $catalogId, raHours: $raHours, decDegrees: $decDegrees, totalScore: $totalScore, scoreBreakdown: $scoreBreakdown, warnings: $warnings, visibility: $visibility, reasoning: $reasoning, dataProgress: $dataProgress, objectType: $objectType, magnitude: $magnitude, sizeArcmin: $sizeArcmin, constellation: $constellation)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TargetSuggestionImpl &&
            (identical(other.targetId, targetId) ||
                other.targetId == targetId) &&
            (identical(other.targetName, targetName) ||
                other.targetName == targetName) &&
            (identical(other.catalogId, catalogId) ||
                other.catalogId == catalogId) &&
            (identical(other.raHours, raHours) || other.raHours == raHours) &&
            (identical(other.decDegrees, decDegrees) ||
                other.decDegrees == decDegrees) &&
            (identical(other.totalScore, totalScore) ||
                other.totalScore == totalScore) &&
            const DeepCollectionEquality()
                .equals(other._scoreBreakdown, _scoreBreakdown) &&
            const DeepCollectionEquality().equals(other._warnings, _warnings) &&
            (identical(other.visibility, visibility) ||
                other.visibility == visibility) &&
            (identical(other.reasoning, reasoning) ||
                other.reasoning == reasoning) &&
            (identical(other.dataProgress, dataProgress) ||
                other.dataProgress == dataProgress) &&
            (identical(other.objectType, objectType) ||
                other.objectType == objectType) &&
            (identical(other.magnitude, magnitude) ||
                other.magnitude == magnitude) &&
            (identical(other.sizeArcmin, sizeArcmin) ||
                other.sizeArcmin == sizeArcmin) &&
            (identical(other.constellation, constellation) ||
                other.constellation == constellation));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      targetId,
      targetName,
      catalogId,
      raHours,
      decDegrees,
      totalScore,
      const DeepCollectionEquality().hash(_scoreBreakdown),
      const DeepCollectionEquality().hash(_warnings),
      visibility,
      reasoning,
      dataProgress,
      objectType,
      magnitude,
      sizeArcmin,
      constellation);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TargetSuggestionImplCopyWith<_$TargetSuggestionImpl> get copyWith =>
      __$$TargetSuggestionImplCopyWithImpl<_$TargetSuggestionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TargetSuggestionImplToJson(
      this,
    );
  }
}

abstract class _TargetSuggestion implements TargetSuggestion {
  const factory _TargetSuggestion(
      {required final int targetId,
      required final String targetName,
      final String? catalogId,
      required final double raHours,
      required final double decDegrees,
      required final double totalScore,
      final Map<String, double> scoreBreakdown,
      @TargetWarningListConverter() final List<TargetWarning> warnings,
      @TargetVisibilityInfoConverter()
      required final TargetVisibilityInfo visibility,
      final String reasoning,
      final double dataProgress,
      final String? objectType,
      final double? magnitude,
      final double? sizeArcmin,
      final String? constellation}) = _$TargetSuggestionImpl;

  factory _TargetSuggestion.fromJson(Map<String, dynamic> json) =
      _$TargetSuggestionImpl.fromJson;

  @override

  /// Database target ID
  int get targetId;
  @override

  /// Display name of the target
  String get targetName;
  @override

  /// Catalog identifier (e.g., "NGC 7000", "M31")
  String? get catalogId;
  @override

  /// Right Ascension in hours (0-24)
  double get raHours;
  @override

  /// Declination in degrees (-90 to +90)
  double get decDegrees;
  @override

  /// Overall score from 0-100
  double get totalScore;
  @override

  /// Breakdown of individual score components
  /// Keys: altitude, moonDistance, transitProximity, darkness, airmass
  Map<String, double> get scoreBreakdown;
  @override

  /// Warnings about target conditions
  @TargetWarningListConverter()
  List<TargetWarning> get warnings;
  @override

  /// Visibility information for this target
  @TargetVisibilityInfoConverter()
  TargetVisibilityInfo get visibility;
  @override

  /// Human-readable explanation of why this target is suggested
  String get reasoning;
  @override

  /// Progress of data collection for this target (0.0 to 1.0)
  /// 0.0 = no data collected, 1.0 = fully complete
  double get dataProgress;
  @override

  /// Object type (e.g., "Galaxy", "Emission Nebula", "Open Cluster")
  String? get objectType;
  @override

  /// Visual magnitude
  double? get magnitude;
  @override

  /// Angular size in arcminutes
  double? get sizeArcmin;
  @override

  /// Constellation abbreviation
  String? get constellation;
  @override
  @JsonKey(ignore: true)
  _$$TargetSuggestionImplCopyWith<_$TargetSuggestionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TargetSuggestionConfig _$TargetSuggestionConfigFromJson(
    Map<String, dynamic> json) {
  return _TargetSuggestionConfig.fromJson(json);
}

/// @nodoc
mixin _$TargetSuggestionConfig {
  /// Minimum altitude in degrees for targets to be considered
  double get minAltitude => throw _privateConstructorUsedError;

  /// Maximum distance from moon in degrees (null = no limit)
  double? get maxMoonDistance => throw _privateConstructorUsedError;

  /// Preferred object types to prioritize (e.g., ["Galaxy", "Nebula"])
  List<String> get preferredObjectTypes => throw _privateConstructorUsedError;

  /// Whether to prioritize targets that need more data
  bool get prioritizeIncomplete => throw _privateConstructorUsedError;

  /// Minimum score (0-100) for a target to be suggested
  double get minScore => throw _privateConstructorUsedError;

  /// How to sort the suggestions
  SuggestionSortMode get sortMode => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TargetSuggestionConfigCopyWith<TargetSuggestionConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TargetSuggestionConfigCopyWith<$Res> {
  factory $TargetSuggestionConfigCopyWith(TargetSuggestionConfig value,
          $Res Function(TargetSuggestionConfig) then) =
      _$TargetSuggestionConfigCopyWithImpl<$Res, TargetSuggestionConfig>;
  @useResult
  $Res call(
      {double minAltitude,
      double? maxMoonDistance,
      List<String> preferredObjectTypes,
      bool prioritizeIncomplete,
      double minScore,
      SuggestionSortMode sortMode});
}

/// @nodoc
class _$TargetSuggestionConfigCopyWithImpl<$Res,
        $Val extends TargetSuggestionConfig>
    implements $TargetSuggestionConfigCopyWith<$Res> {
  _$TargetSuggestionConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minAltitude = null,
    Object? maxMoonDistance = freezed,
    Object? preferredObjectTypes = null,
    Object? prioritizeIncomplete = null,
    Object? minScore = null,
    Object? sortMode = null,
  }) {
    return _then(_value.copyWith(
      minAltitude: null == minAltitude
          ? _value.minAltitude
          : minAltitude // ignore: cast_nullable_to_non_nullable
              as double,
      maxMoonDistance: freezed == maxMoonDistance
          ? _value.maxMoonDistance
          : maxMoonDistance // ignore: cast_nullable_to_non_nullable
              as double?,
      preferredObjectTypes: null == preferredObjectTypes
          ? _value.preferredObjectTypes
          : preferredObjectTypes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      prioritizeIncomplete: null == prioritizeIncomplete
          ? _value.prioritizeIncomplete
          : prioritizeIncomplete // ignore: cast_nullable_to_non_nullable
              as bool,
      minScore: null == minScore
          ? _value.minScore
          : minScore // ignore: cast_nullable_to_non_nullable
              as double,
      sortMode: null == sortMode
          ? _value.sortMode
          : sortMode // ignore: cast_nullable_to_non_nullable
              as SuggestionSortMode,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TargetSuggestionConfigImplCopyWith<$Res>
    implements $TargetSuggestionConfigCopyWith<$Res> {
  factory _$$TargetSuggestionConfigImplCopyWith(
          _$TargetSuggestionConfigImpl value,
          $Res Function(_$TargetSuggestionConfigImpl) then) =
      __$$TargetSuggestionConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double minAltitude,
      double? maxMoonDistance,
      List<String> preferredObjectTypes,
      bool prioritizeIncomplete,
      double minScore,
      SuggestionSortMode sortMode});
}

/// @nodoc
class __$$TargetSuggestionConfigImplCopyWithImpl<$Res>
    extends _$TargetSuggestionConfigCopyWithImpl<$Res,
        _$TargetSuggestionConfigImpl>
    implements _$$TargetSuggestionConfigImplCopyWith<$Res> {
  __$$TargetSuggestionConfigImplCopyWithImpl(
      _$TargetSuggestionConfigImpl _value,
      $Res Function(_$TargetSuggestionConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minAltitude = null,
    Object? maxMoonDistance = freezed,
    Object? preferredObjectTypes = null,
    Object? prioritizeIncomplete = null,
    Object? minScore = null,
    Object? sortMode = null,
  }) {
    return _then(_$TargetSuggestionConfigImpl(
      minAltitude: null == minAltitude
          ? _value.minAltitude
          : minAltitude // ignore: cast_nullable_to_non_nullable
              as double,
      maxMoonDistance: freezed == maxMoonDistance
          ? _value.maxMoonDistance
          : maxMoonDistance // ignore: cast_nullable_to_non_nullable
              as double?,
      preferredObjectTypes: null == preferredObjectTypes
          ? _value._preferredObjectTypes
          : preferredObjectTypes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      prioritizeIncomplete: null == prioritizeIncomplete
          ? _value.prioritizeIncomplete
          : prioritizeIncomplete // ignore: cast_nullable_to_non_nullable
              as bool,
      minScore: null == minScore
          ? _value.minScore
          : minScore // ignore: cast_nullable_to_non_nullable
              as double,
      sortMode: null == sortMode
          ? _value.sortMode
          : sortMode // ignore: cast_nullable_to_non_nullable
              as SuggestionSortMode,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TargetSuggestionConfigImpl implements _TargetSuggestionConfig {
  const _$TargetSuggestionConfigImpl(
      {this.minAltitude = 30.0,
      this.maxMoonDistance,
      final List<String> preferredObjectTypes = const <String>[],
      this.prioritizeIncomplete = true,
      this.minScore = 50.0,
      this.sortMode = SuggestionSortMode.bestScore})
      : _preferredObjectTypes = preferredObjectTypes;

  factory _$TargetSuggestionConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$TargetSuggestionConfigImplFromJson(json);

  /// Minimum altitude in degrees for targets to be considered
  @override
  @JsonKey()
  final double minAltitude;

  /// Maximum distance from moon in degrees (null = no limit)
  @override
  final double? maxMoonDistance;

  /// Preferred object types to prioritize (e.g., ["Galaxy", "Nebula"])
  final List<String> _preferredObjectTypes;

  /// Preferred object types to prioritize (e.g., ["Galaxy", "Nebula"])
  @override
  @JsonKey()
  List<String> get preferredObjectTypes {
    if (_preferredObjectTypes is EqualUnmodifiableListView)
      return _preferredObjectTypes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_preferredObjectTypes);
  }

  /// Whether to prioritize targets that need more data
  @override
  @JsonKey()
  final bool prioritizeIncomplete;

  /// Minimum score (0-100) for a target to be suggested
  @override
  @JsonKey()
  final double minScore;

  /// How to sort the suggestions
  @override
  @JsonKey()
  final SuggestionSortMode sortMode;

  @override
  String toString() {
    return 'TargetSuggestionConfig(minAltitude: $minAltitude, maxMoonDistance: $maxMoonDistance, preferredObjectTypes: $preferredObjectTypes, prioritizeIncomplete: $prioritizeIncomplete, minScore: $minScore, sortMode: $sortMode)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TargetSuggestionConfigImpl &&
            (identical(other.minAltitude, minAltitude) ||
                other.minAltitude == minAltitude) &&
            (identical(other.maxMoonDistance, maxMoonDistance) ||
                other.maxMoonDistance == maxMoonDistance) &&
            const DeepCollectionEquality()
                .equals(other._preferredObjectTypes, _preferredObjectTypes) &&
            (identical(other.prioritizeIncomplete, prioritizeIncomplete) ||
                other.prioritizeIncomplete == prioritizeIncomplete) &&
            (identical(other.minScore, minScore) ||
                other.minScore == minScore) &&
            (identical(other.sortMode, sortMode) ||
                other.sortMode == sortMode));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      minAltitude,
      maxMoonDistance,
      const DeepCollectionEquality().hash(_preferredObjectTypes),
      prioritizeIncomplete,
      minScore,
      sortMode);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TargetSuggestionConfigImplCopyWith<_$TargetSuggestionConfigImpl>
      get copyWith => __$$TargetSuggestionConfigImplCopyWithImpl<
          _$TargetSuggestionConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TargetSuggestionConfigImplToJson(
      this,
    );
  }
}

abstract class _TargetSuggestionConfig implements TargetSuggestionConfig {
  const factory _TargetSuggestionConfig(
      {final double minAltitude,
      final double? maxMoonDistance,
      final List<String> preferredObjectTypes,
      final bool prioritizeIncomplete,
      final double minScore,
      final SuggestionSortMode sortMode}) = _$TargetSuggestionConfigImpl;

  factory _TargetSuggestionConfig.fromJson(Map<String, dynamic> json) =
      _$TargetSuggestionConfigImpl.fromJson;

  @override

  /// Minimum altitude in degrees for targets to be considered
  double get minAltitude;
  @override

  /// Maximum distance from moon in degrees (null = no limit)
  double? get maxMoonDistance;
  @override

  /// Preferred object types to prioritize (e.g., ["Galaxy", "Nebula"])
  List<String> get preferredObjectTypes;
  @override

  /// Whether to prioritize targets that need more data
  bool get prioritizeIncomplete;
  @override

  /// Minimum score (0-100) for a target to be suggested
  double get minScore;
  @override

  /// How to sort the suggestions
  SuggestionSortMode get sortMode;
  @override
  @JsonKey(ignore: true)
  _$$TargetSuggestionConfigImplCopyWith<_$TargetSuggestionConfigImpl>
      get copyWith => throw _privateConstructorUsedError;
}
