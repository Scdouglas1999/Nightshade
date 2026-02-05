// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transient_alert.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TransientAlert _$TransientAlertFromJson(Map<String, dynamic> json) {
  return _TransientAlert.fromJson(json);
}

/// @nodoc
mixin _$TransientAlert {
  /// Unique identifier for this alert
  String get id => throw _privateConstructorUsedError;

  /// Object name/designation (e.g., "SN 2024abc", "V404 Cyg")
  String get name => throw _privateConstructorUsedError;

  /// Type of transient event
  TransientType get type => throw _privateConstructorUsedError;

  /// Right ascension in hours (0-24)
  double get raHours => throw _privateConstructorUsedError;

  /// Declination in degrees (-90 to +90)
  double get decDegrees => throw _privateConstructorUsedError;

  /// Current magnitude (null if unknown)
  double? get magnitude => throw _privateConstructorUsedError;

  /// Peak/discovery magnitude if known
  double? get peakMagnitude => throw _privateConstructorUsedError;

  /// When the transient was discovered
  DateTime get discoveryTime => throw _privateConstructorUsedError;

  /// When this alert was last updated
  DateTime get lastUpdated => throw _privateConstructorUsedError;

  /// Source of the alert data
  TransientSource get source => throw _privateConstructorUsedError;

  /// URL to source announcement/page
  String? get sourceUrl => throw _privateConstructorUsedError;

  /// Priority level 1-10 (1=highest, 10=lowest)
  int get priority => throw _privateConstructorUsedError;

  /// User notes about this transient
  String? get notes => throw _privateConstructorUsedError;

  /// Spectral classification if available (e.g., "Type Ia", "He-rich")
  String? get classification => throw _privateConstructorUsedError;

  /// Current state of this alert
  TransientAlertState get state => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TransientAlertCopyWith<TransientAlert> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransientAlertCopyWith<$Res> {
  factory $TransientAlertCopyWith(
          TransientAlert value, $Res Function(TransientAlert) then) =
      _$TransientAlertCopyWithImpl<$Res, TransientAlert>;
  @useResult
  $Res call(
      {String id,
      String name,
      TransientType type,
      double raHours,
      double decDegrees,
      double? magnitude,
      double? peakMagnitude,
      DateTime discoveryTime,
      DateTime lastUpdated,
      TransientSource source,
      String? sourceUrl,
      int priority,
      String? notes,
      String? classification,
      TransientAlertState state});
}

/// @nodoc
class _$TransientAlertCopyWithImpl<$Res, $Val extends TransientAlert>
    implements $TransientAlertCopyWith<$Res> {
  _$TransientAlertCopyWithImpl(this._value, this._then);

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
    Object? raHours = null,
    Object? decDegrees = null,
    Object? magnitude = freezed,
    Object? peakMagnitude = freezed,
    Object? discoveryTime = null,
    Object? lastUpdated = null,
    Object? source = null,
    Object? sourceUrl = freezed,
    Object? priority = null,
    Object? notes = freezed,
    Object? classification = freezed,
    Object? state = null,
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
              as TransientType,
      raHours: null == raHours
          ? _value.raHours
          : raHours // ignore: cast_nullable_to_non_nullable
              as double,
      decDegrees: null == decDegrees
          ? _value.decDegrees
          : decDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      peakMagnitude: freezed == peakMagnitude
          ? _value.peakMagnitude
          : peakMagnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      discoveryTime: null == discoveryTime
          ? _value.discoveryTime
          : discoveryTime // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastUpdated: null == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as TransientSource,
      sourceUrl: freezed == sourceUrl
          ? _value.sourceUrl
          : sourceUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      priority: null == priority
          ? _value.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      classification: freezed == classification
          ? _value.classification
          : classification // ignore: cast_nullable_to_non_nullable
              as String?,
      state: null == state
          ? _value.state
          : state // ignore: cast_nullable_to_non_nullable
              as TransientAlertState,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TransientAlertImplCopyWith<$Res>
    implements $TransientAlertCopyWith<$Res> {
  factory _$$TransientAlertImplCopyWith(_$TransientAlertImpl value,
          $Res Function(_$TransientAlertImpl) then) =
      __$$TransientAlertImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      TransientType type,
      double raHours,
      double decDegrees,
      double? magnitude,
      double? peakMagnitude,
      DateTime discoveryTime,
      DateTime lastUpdated,
      TransientSource source,
      String? sourceUrl,
      int priority,
      String? notes,
      String? classification,
      TransientAlertState state});
}

/// @nodoc
class __$$TransientAlertImplCopyWithImpl<$Res>
    extends _$TransientAlertCopyWithImpl<$Res, _$TransientAlertImpl>
    implements _$$TransientAlertImplCopyWith<$Res> {
  __$$TransientAlertImplCopyWithImpl(
      _$TransientAlertImpl _value, $Res Function(_$TransientAlertImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? raHours = null,
    Object? decDegrees = null,
    Object? magnitude = freezed,
    Object? peakMagnitude = freezed,
    Object? discoveryTime = null,
    Object? lastUpdated = null,
    Object? source = null,
    Object? sourceUrl = freezed,
    Object? priority = null,
    Object? notes = freezed,
    Object? classification = freezed,
    Object? state = null,
  }) {
    return _then(_$TransientAlertImpl(
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
              as TransientType,
      raHours: null == raHours
          ? _value.raHours
          : raHours // ignore: cast_nullable_to_non_nullable
              as double,
      decDegrees: null == decDegrees
          ? _value.decDegrees
          : decDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      magnitude: freezed == magnitude
          ? _value.magnitude
          : magnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      peakMagnitude: freezed == peakMagnitude
          ? _value.peakMagnitude
          : peakMagnitude // ignore: cast_nullable_to_non_nullable
              as double?,
      discoveryTime: null == discoveryTime
          ? _value.discoveryTime
          : discoveryTime // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastUpdated: null == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as TransientSource,
      sourceUrl: freezed == sourceUrl
          ? _value.sourceUrl
          : sourceUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      priority: null == priority
          ? _value.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      classification: freezed == classification
          ? _value.classification
          : classification // ignore: cast_nullable_to_non_nullable
              as String?,
      state: null == state
          ? _value.state
          : state // ignore: cast_nullable_to_non_nullable
              as TransientAlertState,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TransientAlertImpl implements _TransientAlert {
  const _$TransientAlertImpl(
      {required this.id,
      required this.name,
      required this.type,
      required this.raHours,
      required this.decDegrees,
      this.magnitude,
      this.peakMagnitude,
      required this.discoveryTime,
      required this.lastUpdated,
      required this.source,
      this.sourceUrl,
      this.priority = 5,
      this.notes,
      this.classification,
      this.state = TransientAlertState.newAlert});

  factory _$TransientAlertImpl.fromJson(Map<String, dynamic> json) =>
      _$$TransientAlertImplFromJson(json);

  /// Unique identifier for this alert
  @override
  final String id;

  /// Object name/designation (e.g., "SN 2024abc", "V404 Cyg")
  @override
  final String name;

  /// Type of transient event
  @override
  final TransientType type;

  /// Right ascension in hours (0-24)
  @override
  final double raHours;

  /// Declination in degrees (-90 to +90)
  @override
  final double decDegrees;

  /// Current magnitude (null if unknown)
  @override
  final double? magnitude;

  /// Peak/discovery magnitude if known
  @override
  final double? peakMagnitude;

  /// When the transient was discovered
  @override
  final DateTime discoveryTime;

  /// When this alert was last updated
  @override
  final DateTime lastUpdated;

  /// Source of the alert data
  @override
  final TransientSource source;

  /// URL to source announcement/page
  @override
  final String? sourceUrl;

  /// Priority level 1-10 (1=highest, 10=lowest)
  @override
  @JsonKey()
  final int priority;

  /// User notes about this transient
  @override
  final String? notes;

  /// Spectral classification if available (e.g., "Type Ia", "He-rich")
  @override
  final String? classification;

  /// Current state of this alert
  @override
  @JsonKey()
  final TransientAlertState state;

  @override
  String toString() {
    return 'TransientAlert(id: $id, name: $name, type: $type, raHours: $raHours, decDegrees: $decDegrees, magnitude: $magnitude, peakMagnitude: $peakMagnitude, discoveryTime: $discoveryTime, lastUpdated: $lastUpdated, source: $source, sourceUrl: $sourceUrl, priority: $priority, notes: $notes, classification: $classification, state: $state)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransientAlertImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.raHours, raHours) || other.raHours == raHours) &&
            (identical(other.decDegrees, decDegrees) ||
                other.decDegrees == decDegrees) &&
            (identical(other.magnitude, magnitude) ||
                other.magnitude == magnitude) &&
            (identical(other.peakMagnitude, peakMagnitude) ||
                other.peakMagnitude == peakMagnitude) &&
            (identical(other.discoveryTime, discoveryTime) ||
                other.discoveryTime == discoveryTime) &&
            (identical(other.lastUpdated, lastUpdated) ||
                other.lastUpdated == lastUpdated) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.sourceUrl, sourceUrl) ||
                other.sourceUrl == sourceUrl) &&
            (identical(other.priority, priority) ||
                other.priority == priority) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.classification, classification) ||
                other.classification == classification) &&
            (identical(other.state, state) || other.state == state));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      type,
      raHours,
      decDegrees,
      magnitude,
      peakMagnitude,
      discoveryTime,
      lastUpdated,
      source,
      sourceUrl,
      priority,
      notes,
      classification,
      state);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TransientAlertImplCopyWith<_$TransientAlertImpl> get copyWith =>
      __$$TransientAlertImplCopyWithImpl<_$TransientAlertImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TransientAlertImplToJson(
      this,
    );
  }
}

abstract class _TransientAlert implements TransientAlert {
  const factory _TransientAlert(
      {required final String id,
      required final String name,
      required final TransientType type,
      required final double raHours,
      required final double decDegrees,
      final double? magnitude,
      final double? peakMagnitude,
      required final DateTime discoveryTime,
      required final DateTime lastUpdated,
      required final TransientSource source,
      final String? sourceUrl,
      final int priority,
      final String? notes,
      final String? classification,
      final TransientAlertState state}) = _$TransientAlertImpl;

  factory _TransientAlert.fromJson(Map<String, dynamic> json) =
      _$TransientAlertImpl.fromJson;

  @override

  /// Unique identifier for this alert
  String get id;
  @override

  /// Object name/designation (e.g., "SN 2024abc", "V404 Cyg")
  String get name;
  @override

  /// Type of transient event
  TransientType get type;
  @override

  /// Right ascension in hours (0-24)
  double get raHours;
  @override

  /// Declination in degrees (-90 to +90)
  double get decDegrees;
  @override

  /// Current magnitude (null if unknown)
  double? get magnitude;
  @override

  /// Peak/discovery magnitude if known
  double? get peakMagnitude;
  @override

  /// When the transient was discovered
  DateTime get discoveryTime;
  @override

  /// When this alert was last updated
  DateTime get lastUpdated;
  @override

  /// Source of the alert data
  TransientSource get source;
  @override

  /// URL to source announcement/page
  String? get sourceUrl;
  @override

  /// Priority level 1-10 (1=highest, 10=lowest)
  int get priority;
  @override

  /// User notes about this transient
  String? get notes;
  @override

  /// Spectral classification if available (e.g., "Type Ia", "He-rich")
  String? get classification;
  @override

  /// Current state of this alert
  TransientAlertState get state;
  @override
  @JsonKey(ignore: true)
  _$$TransientAlertImplCopyWith<_$TransientAlertImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TransientAlertSettings _$TransientAlertSettingsFromJson(
    Map<String, dynamic> json) {
  return _TransientAlertSettings.fromJson(json);
}

/// @nodoc
mixin _$TransientAlertSettings {
  /// Which alert sources to monitor
  /// Note: TNS requires an API key to be configured (see tnsApiKey)
  Set<TransientSource> get enabledSources => throw _privateConstructorUsedError;

  /// Only show alerts brighter than this magnitude
  double get magnitudeThreshold => throw _privateConstructorUsedError;

  /// Which transient types to monitor
  Set<TransientType> get typesToMonitor => throw _privateConstructorUsedError;

  /// Show notification when new alerts arrive
  bool get notifyOnNew => throw _privateConstructorUsedError;

  /// Automatically queue bright transients for observation
  bool get autoQueueBright => throw _privateConstructorUsedError;

  /// Magnitude threshold for auto-queuing (brighter = lower number)
  double get autoQueueMagnitude => throw _privateConstructorUsedError;

  /// TNS (Transient Name Server) API key.
  /// Required for TNS alerts. Obtain at https://www.wis-tns.org/
  /// Leave empty to disable TNS source.
  String? get tnsApiKey => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TransientAlertSettingsCopyWith<TransientAlertSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransientAlertSettingsCopyWith<$Res> {
  factory $TransientAlertSettingsCopyWith(TransientAlertSettings value,
          $Res Function(TransientAlertSettings) then) =
      _$TransientAlertSettingsCopyWithImpl<$Res, TransientAlertSettings>;
  @useResult
  $Res call(
      {Set<TransientSource> enabledSources,
      double magnitudeThreshold,
      Set<TransientType> typesToMonitor,
      bool notifyOnNew,
      bool autoQueueBright,
      double autoQueueMagnitude,
      String? tnsApiKey});
}

/// @nodoc
class _$TransientAlertSettingsCopyWithImpl<$Res,
        $Val extends TransientAlertSettings>
    implements $TransientAlertSettingsCopyWith<$Res> {
  _$TransientAlertSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabledSources = null,
    Object? magnitudeThreshold = null,
    Object? typesToMonitor = null,
    Object? notifyOnNew = null,
    Object? autoQueueBright = null,
    Object? autoQueueMagnitude = null,
    Object? tnsApiKey = freezed,
  }) {
    return _then(_value.copyWith(
      enabledSources: null == enabledSources
          ? _value.enabledSources
          : enabledSources // ignore: cast_nullable_to_non_nullable
              as Set<TransientSource>,
      magnitudeThreshold: null == magnitudeThreshold
          ? _value.magnitudeThreshold
          : magnitudeThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      typesToMonitor: null == typesToMonitor
          ? _value.typesToMonitor
          : typesToMonitor // ignore: cast_nullable_to_non_nullable
              as Set<TransientType>,
      notifyOnNew: null == notifyOnNew
          ? _value.notifyOnNew
          : notifyOnNew // ignore: cast_nullable_to_non_nullable
              as bool,
      autoQueueBright: null == autoQueueBright
          ? _value.autoQueueBright
          : autoQueueBright // ignore: cast_nullable_to_non_nullable
              as bool,
      autoQueueMagnitude: null == autoQueueMagnitude
          ? _value.autoQueueMagnitude
          : autoQueueMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      tnsApiKey: freezed == tnsApiKey
          ? _value.tnsApiKey
          : tnsApiKey // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TransientAlertSettingsImplCopyWith<$Res>
    implements $TransientAlertSettingsCopyWith<$Res> {
  factory _$$TransientAlertSettingsImplCopyWith(
          _$TransientAlertSettingsImpl value,
          $Res Function(_$TransientAlertSettingsImpl) then) =
      __$$TransientAlertSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {Set<TransientSource> enabledSources,
      double magnitudeThreshold,
      Set<TransientType> typesToMonitor,
      bool notifyOnNew,
      bool autoQueueBright,
      double autoQueueMagnitude,
      String? tnsApiKey});
}

/// @nodoc
class __$$TransientAlertSettingsImplCopyWithImpl<$Res>
    extends _$TransientAlertSettingsCopyWithImpl<$Res,
        _$TransientAlertSettingsImpl>
    implements _$$TransientAlertSettingsImplCopyWith<$Res> {
  __$$TransientAlertSettingsImplCopyWithImpl(
      _$TransientAlertSettingsImpl _value,
      $Res Function(_$TransientAlertSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? enabledSources = null,
    Object? magnitudeThreshold = null,
    Object? typesToMonitor = null,
    Object? notifyOnNew = null,
    Object? autoQueueBright = null,
    Object? autoQueueMagnitude = null,
    Object? tnsApiKey = freezed,
  }) {
    return _then(_$TransientAlertSettingsImpl(
      enabledSources: null == enabledSources
          ? _value._enabledSources
          : enabledSources // ignore: cast_nullable_to_non_nullable
              as Set<TransientSource>,
      magnitudeThreshold: null == magnitudeThreshold
          ? _value.magnitudeThreshold
          : magnitudeThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      typesToMonitor: null == typesToMonitor
          ? _value._typesToMonitor
          : typesToMonitor // ignore: cast_nullable_to_non_nullable
              as Set<TransientType>,
      notifyOnNew: null == notifyOnNew
          ? _value.notifyOnNew
          : notifyOnNew // ignore: cast_nullable_to_non_nullable
              as bool,
      autoQueueBright: null == autoQueueBright
          ? _value.autoQueueBright
          : autoQueueBright // ignore: cast_nullable_to_non_nullable
              as bool,
      autoQueueMagnitude: null == autoQueueMagnitude
          ? _value.autoQueueMagnitude
          : autoQueueMagnitude // ignore: cast_nullable_to_non_nullable
              as double,
      tnsApiKey: freezed == tnsApiKey
          ? _value.tnsApiKey
          : tnsApiKey // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TransientAlertSettingsImpl implements _TransientAlertSettings {
  const _$TransientAlertSettingsImpl(
      {final Set<TransientSource> enabledSources = const {
        TransientSource.aavso,
        TransientSource.mpec,
        TransientSource.cbat,
        TransientSource.manual
      },
      this.magnitudeThreshold = 15.0,
      final Set<TransientType> typesToMonitor = const {
        TransientType.nova,
        TransientType.supernova,
        TransientType.cataclysmic,
        TransientType.comet,
        TransientType.asteroid,
        TransientType.variableStar,
        TransientType.gammaRayBurst,
        TransientType.other
      },
      this.notifyOnNew = true,
      this.autoQueueBright = false,
      this.autoQueueMagnitude = 10.0,
      this.tnsApiKey})
      : _enabledSources = enabledSources,
        _typesToMonitor = typesToMonitor;

  factory _$TransientAlertSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$TransientAlertSettingsImplFromJson(json);

  /// Which alert sources to monitor
  /// Note: TNS requires an API key to be configured (see tnsApiKey)
  final Set<TransientSource> _enabledSources;

  /// Which alert sources to monitor
  /// Note: TNS requires an API key to be configured (see tnsApiKey)
  @override
  @JsonKey()
  Set<TransientSource> get enabledSources {
    if (_enabledSources is EqualUnmodifiableSetView) return _enabledSources;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_enabledSources);
  }

  /// Only show alerts brighter than this magnitude
  @override
  @JsonKey()
  final double magnitudeThreshold;

  /// Which transient types to monitor
  final Set<TransientType> _typesToMonitor;

  /// Which transient types to monitor
  @override
  @JsonKey()
  Set<TransientType> get typesToMonitor {
    if (_typesToMonitor is EqualUnmodifiableSetView) return _typesToMonitor;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_typesToMonitor);
  }

  /// Show notification when new alerts arrive
  @override
  @JsonKey()
  final bool notifyOnNew;

  /// Automatically queue bright transients for observation
  @override
  @JsonKey()
  final bool autoQueueBright;

  /// Magnitude threshold for auto-queuing (brighter = lower number)
  @override
  @JsonKey()
  final double autoQueueMagnitude;

  /// TNS (Transient Name Server) API key.
  /// Required for TNS alerts. Obtain at https://www.wis-tns.org/
  /// Leave empty to disable TNS source.
  @override
  final String? tnsApiKey;

  @override
  String toString() {
    return 'TransientAlertSettings(enabledSources: $enabledSources, magnitudeThreshold: $magnitudeThreshold, typesToMonitor: $typesToMonitor, notifyOnNew: $notifyOnNew, autoQueueBright: $autoQueueBright, autoQueueMagnitude: $autoQueueMagnitude, tnsApiKey: $tnsApiKey)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransientAlertSettingsImpl &&
            const DeepCollectionEquality()
                .equals(other._enabledSources, _enabledSources) &&
            (identical(other.magnitudeThreshold, magnitudeThreshold) ||
                other.magnitudeThreshold == magnitudeThreshold) &&
            const DeepCollectionEquality()
                .equals(other._typesToMonitor, _typesToMonitor) &&
            (identical(other.notifyOnNew, notifyOnNew) ||
                other.notifyOnNew == notifyOnNew) &&
            (identical(other.autoQueueBright, autoQueueBright) ||
                other.autoQueueBright == autoQueueBright) &&
            (identical(other.autoQueueMagnitude, autoQueueMagnitude) ||
                other.autoQueueMagnitude == autoQueueMagnitude) &&
            (identical(other.tnsApiKey, tnsApiKey) ||
                other.tnsApiKey == tnsApiKey));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_enabledSources),
      magnitudeThreshold,
      const DeepCollectionEquality().hash(_typesToMonitor),
      notifyOnNew,
      autoQueueBright,
      autoQueueMagnitude,
      tnsApiKey);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TransientAlertSettingsImplCopyWith<_$TransientAlertSettingsImpl>
      get copyWith => __$$TransientAlertSettingsImplCopyWithImpl<
          _$TransientAlertSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TransientAlertSettingsImplToJson(
      this,
    );
  }
}

abstract class _TransientAlertSettings implements TransientAlertSettings {
  const factory _TransientAlertSettings(
      {final Set<TransientSource> enabledSources,
      final double magnitudeThreshold,
      final Set<TransientType> typesToMonitor,
      final bool notifyOnNew,
      final bool autoQueueBright,
      final double autoQueueMagnitude,
      final String? tnsApiKey}) = _$TransientAlertSettingsImpl;

  factory _TransientAlertSettings.fromJson(Map<String, dynamic> json) =
      _$TransientAlertSettingsImpl.fromJson;

  @override

  /// Which alert sources to monitor
  /// Note: TNS requires an API key to be configured (see tnsApiKey)
  Set<TransientSource> get enabledSources;
  @override

  /// Only show alerts brighter than this magnitude
  double get magnitudeThreshold;
  @override

  /// Which transient types to monitor
  Set<TransientType> get typesToMonitor;
  @override

  /// Show notification when new alerts arrive
  bool get notifyOnNew;
  @override

  /// Automatically queue bright transients for observation
  bool get autoQueueBright;
  @override

  /// Magnitude threshold for auto-queuing (brighter = lower number)
  double get autoQueueMagnitude;
  @override

  /// TNS (Transient Name Server) API key.
  /// Required for TNS alerts. Obtain at https://www.wis-tns.org/
  /// Leave empty to disable TNS source.
  String? get tnsApiKey;
  @override
  @JsonKey(ignore: true)
  _$$TransientAlertSettingsImplCopyWith<_$TransientAlertSettingsImpl>
      get copyWith => throw _privateConstructorUsedError;
}
