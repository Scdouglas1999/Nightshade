// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'meridian_flip_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MeridianFlipSettings _$MeridianFlipSettingsFromJson(Map<String, dynamic> json) {
  return _MeridianFlipSettings.fromJson(json);
}

/// @nodoc
mixin _$MeridianFlipSettings {
// === Mode Control ===
  /// Enable standalone monitoring when no sequence is running
  bool get standaloneMonitoringEnabled =>
      throw _privateConstructorUsedError; // === Trigger Conditions ===
  /// Which method to use for determining flip timing
  MeridianTriggerMethod get triggerMethod => throw _privateConstructorUsedError;

  /// Minutes past meridian to trigger flip (default: 5)
  double get minutesPastMeridian => throw _privateConstructorUsedError;

  /// Minutes before mount limit to trigger flip (default: 10)
  double get minutesBeforeLimit => throw _privateConstructorUsedError;

  /// Hour angle threshold in hours to trigger flip (default: 0.5 = 30 min)
  double get hourAngleThreshold =>
      throw _privateConstructorUsedError; // === Flip Sequence Options ===
  /// Pause guider before flip
  bool get pauseGuidingBeforeFlip => throw _privateConstructorUsedError;

  /// Plate solve and re-center after flip
  bool get recenterAfterFlip => throw _privateConstructorUsedError;

  /// Run autofocus after flip
  bool get refocusAfterFlip => throw _privateConstructorUsedError;

  /// Settle time in seconds after flip completes
  double get settleTimeSeconds => throw _privateConstructorUsedError;

  /// Resume guiding after flip (if was running)
  bool get resumeGuidingAfterFlip =>
      throw _privateConstructorUsedError; // === Error Handling ===
  /// Maximum retry attempts
  int get maxRetries => throw _privateConstructorUsedError;

  /// Delay between retries in seconds
  List<double> get retryDelaysSeconds => throw _privateConstructorUsedError;

  /// Action to take on permanent failure
  FlipFailureAction get failureAction =>
      throw _privateConstructorUsedError; // === Notifications ===
  /// Play sound alert when flip starts/completes/fails
  bool get soundAlertOnFlip => throw _privateConstructorUsedError;

  /// Send push notification to mobile app
  bool get pushNotificationOnFlip => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $MeridianFlipSettingsCopyWith<MeridianFlipSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MeridianFlipSettingsCopyWith<$Res> {
  factory $MeridianFlipSettingsCopyWith(MeridianFlipSettings value,
          $Res Function(MeridianFlipSettings) then) =
      _$MeridianFlipSettingsCopyWithImpl<$Res, MeridianFlipSettings>;
  @useResult
  $Res call(
      {bool standaloneMonitoringEnabled,
      MeridianTriggerMethod triggerMethod,
      double minutesPastMeridian,
      double minutesBeforeLimit,
      double hourAngleThreshold,
      bool pauseGuidingBeforeFlip,
      bool recenterAfterFlip,
      bool refocusAfterFlip,
      double settleTimeSeconds,
      bool resumeGuidingAfterFlip,
      int maxRetries,
      List<double> retryDelaysSeconds,
      FlipFailureAction failureAction,
      bool soundAlertOnFlip,
      bool pushNotificationOnFlip});
}

/// @nodoc
class _$MeridianFlipSettingsCopyWithImpl<$Res,
        $Val extends MeridianFlipSettings>
    implements $MeridianFlipSettingsCopyWith<$Res> {
  _$MeridianFlipSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? standaloneMonitoringEnabled = null,
    Object? triggerMethod = null,
    Object? minutesPastMeridian = null,
    Object? minutesBeforeLimit = null,
    Object? hourAngleThreshold = null,
    Object? pauseGuidingBeforeFlip = null,
    Object? recenterAfterFlip = null,
    Object? refocusAfterFlip = null,
    Object? settleTimeSeconds = null,
    Object? resumeGuidingAfterFlip = null,
    Object? maxRetries = null,
    Object? retryDelaysSeconds = null,
    Object? failureAction = null,
    Object? soundAlertOnFlip = null,
    Object? pushNotificationOnFlip = null,
  }) {
    return _then(_value.copyWith(
      standaloneMonitoringEnabled: null == standaloneMonitoringEnabled
          ? _value.standaloneMonitoringEnabled
          : standaloneMonitoringEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      triggerMethod: null == triggerMethod
          ? _value.triggerMethod
          : triggerMethod // ignore: cast_nullable_to_non_nullable
              as MeridianTriggerMethod,
      minutesPastMeridian: null == minutesPastMeridian
          ? _value.minutesPastMeridian
          : minutesPastMeridian // ignore: cast_nullable_to_non_nullable
              as double,
      minutesBeforeLimit: null == minutesBeforeLimit
          ? _value.minutesBeforeLimit
          : minutesBeforeLimit // ignore: cast_nullable_to_non_nullable
              as double,
      hourAngleThreshold: null == hourAngleThreshold
          ? _value.hourAngleThreshold
          : hourAngleThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      pauseGuidingBeforeFlip: null == pauseGuidingBeforeFlip
          ? _value.pauseGuidingBeforeFlip
          : pauseGuidingBeforeFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      recenterAfterFlip: null == recenterAfterFlip
          ? _value.recenterAfterFlip
          : recenterAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      refocusAfterFlip: null == refocusAfterFlip
          ? _value.refocusAfterFlip
          : refocusAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      settleTimeSeconds: null == settleTimeSeconds
          ? _value.settleTimeSeconds
          : settleTimeSeconds // ignore: cast_nullable_to_non_nullable
              as double,
      resumeGuidingAfterFlip: null == resumeGuidingAfterFlip
          ? _value.resumeGuidingAfterFlip
          : resumeGuidingAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      maxRetries: null == maxRetries
          ? _value.maxRetries
          : maxRetries // ignore: cast_nullable_to_non_nullable
              as int,
      retryDelaysSeconds: null == retryDelaysSeconds
          ? _value.retryDelaysSeconds
          : retryDelaysSeconds // ignore: cast_nullable_to_non_nullable
              as List<double>,
      failureAction: null == failureAction
          ? _value.failureAction
          : failureAction // ignore: cast_nullable_to_non_nullable
              as FlipFailureAction,
      soundAlertOnFlip: null == soundAlertOnFlip
          ? _value.soundAlertOnFlip
          : soundAlertOnFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      pushNotificationOnFlip: null == pushNotificationOnFlip
          ? _value.pushNotificationOnFlip
          : pushNotificationOnFlip // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MeridianFlipSettingsImplCopyWith<$Res>
    implements $MeridianFlipSettingsCopyWith<$Res> {
  factory _$$MeridianFlipSettingsImplCopyWith(_$MeridianFlipSettingsImpl value,
          $Res Function(_$MeridianFlipSettingsImpl) then) =
      __$$MeridianFlipSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool standaloneMonitoringEnabled,
      MeridianTriggerMethod triggerMethod,
      double minutesPastMeridian,
      double minutesBeforeLimit,
      double hourAngleThreshold,
      bool pauseGuidingBeforeFlip,
      bool recenterAfterFlip,
      bool refocusAfterFlip,
      double settleTimeSeconds,
      bool resumeGuidingAfterFlip,
      int maxRetries,
      List<double> retryDelaysSeconds,
      FlipFailureAction failureAction,
      bool soundAlertOnFlip,
      bool pushNotificationOnFlip});
}

/// @nodoc
class __$$MeridianFlipSettingsImplCopyWithImpl<$Res>
    extends _$MeridianFlipSettingsCopyWithImpl<$Res, _$MeridianFlipSettingsImpl>
    implements _$$MeridianFlipSettingsImplCopyWith<$Res> {
  __$$MeridianFlipSettingsImplCopyWithImpl(_$MeridianFlipSettingsImpl _value,
      $Res Function(_$MeridianFlipSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? standaloneMonitoringEnabled = null,
    Object? triggerMethod = null,
    Object? minutesPastMeridian = null,
    Object? minutesBeforeLimit = null,
    Object? hourAngleThreshold = null,
    Object? pauseGuidingBeforeFlip = null,
    Object? recenterAfterFlip = null,
    Object? refocusAfterFlip = null,
    Object? settleTimeSeconds = null,
    Object? resumeGuidingAfterFlip = null,
    Object? maxRetries = null,
    Object? retryDelaysSeconds = null,
    Object? failureAction = null,
    Object? soundAlertOnFlip = null,
    Object? pushNotificationOnFlip = null,
  }) {
    return _then(_$MeridianFlipSettingsImpl(
      standaloneMonitoringEnabled: null == standaloneMonitoringEnabled
          ? _value.standaloneMonitoringEnabled
          : standaloneMonitoringEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      triggerMethod: null == triggerMethod
          ? _value.triggerMethod
          : triggerMethod // ignore: cast_nullable_to_non_nullable
              as MeridianTriggerMethod,
      minutesPastMeridian: null == minutesPastMeridian
          ? _value.minutesPastMeridian
          : minutesPastMeridian // ignore: cast_nullable_to_non_nullable
              as double,
      minutesBeforeLimit: null == minutesBeforeLimit
          ? _value.minutesBeforeLimit
          : minutesBeforeLimit // ignore: cast_nullable_to_non_nullable
              as double,
      hourAngleThreshold: null == hourAngleThreshold
          ? _value.hourAngleThreshold
          : hourAngleThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      pauseGuidingBeforeFlip: null == pauseGuidingBeforeFlip
          ? _value.pauseGuidingBeforeFlip
          : pauseGuidingBeforeFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      recenterAfterFlip: null == recenterAfterFlip
          ? _value.recenterAfterFlip
          : recenterAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      refocusAfterFlip: null == refocusAfterFlip
          ? _value.refocusAfterFlip
          : refocusAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      settleTimeSeconds: null == settleTimeSeconds
          ? _value.settleTimeSeconds
          : settleTimeSeconds // ignore: cast_nullable_to_non_nullable
              as double,
      resumeGuidingAfterFlip: null == resumeGuidingAfterFlip
          ? _value.resumeGuidingAfterFlip
          : resumeGuidingAfterFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      maxRetries: null == maxRetries
          ? _value.maxRetries
          : maxRetries // ignore: cast_nullable_to_non_nullable
              as int,
      retryDelaysSeconds: null == retryDelaysSeconds
          ? _value._retryDelaysSeconds
          : retryDelaysSeconds // ignore: cast_nullable_to_non_nullable
              as List<double>,
      failureAction: null == failureAction
          ? _value.failureAction
          : failureAction // ignore: cast_nullable_to_non_nullable
              as FlipFailureAction,
      soundAlertOnFlip: null == soundAlertOnFlip
          ? _value.soundAlertOnFlip
          : soundAlertOnFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      pushNotificationOnFlip: null == pushNotificationOnFlip
          ? _value.pushNotificationOnFlip
          : pushNotificationOnFlip // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipSettingsImpl extends _MeridianFlipSettings {
  const _$MeridianFlipSettingsImpl(
      {this.standaloneMonitoringEnabled = false,
      this.triggerMethod = MeridianTriggerMethod.minutesPastMeridian,
      this.minutesPastMeridian = 5.0,
      this.minutesBeforeLimit = 10.0,
      this.hourAngleThreshold = 0.5,
      this.pauseGuidingBeforeFlip = true,
      this.recenterAfterFlip = true,
      this.refocusAfterFlip = false,
      this.settleTimeSeconds = 10.0,
      this.resumeGuidingAfterFlip = true,
      this.maxRetries = 3,
      final List<double> retryDelaysSeconds = const [30.0, 60.0, 120.0],
      this.failureAction = FlipFailureAction.pauseAndAlert,
      this.soundAlertOnFlip = false,
      this.pushNotificationOnFlip = true})
      : _retryDelaysSeconds = retryDelaysSeconds,
        super._();

  factory _$MeridianFlipSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipSettingsImplFromJson(json);

// === Mode Control ===
  /// Enable standalone monitoring when no sequence is running
  @override
  @JsonKey()
  final bool standaloneMonitoringEnabled;
// === Trigger Conditions ===
  /// Which method to use for determining flip timing
  @override
  @JsonKey()
  final MeridianTriggerMethod triggerMethod;

  /// Minutes past meridian to trigger flip (default: 5)
  @override
  @JsonKey()
  final double minutesPastMeridian;

  /// Minutes before mount limit to trigger flip (default: 10)
  @override
  @JsonKey()
  final double minutesBeforeLimit;

  /// Hour angle threshold in hours to trigger flip (default: 0.5 = 30 min)
  @override
  @JsonKey()
  final double hourAngleThreshold;
// === Flip Sequence Options ===
  /// Pause guider before flip
  @override
  @JsonKey()
  final bool pauseGuidingBeforeFlip;

  /// Plate solve and re-center after flip
  @override
  @JsonKey()
  final bool recenterAfterFlip;

  /// Run autofocus after flip
  @override
  @JsonKey()
  final bool refocusAfterFlip;

  /// Settle time in seconds after flip completes
  @override
  @JsonKey()
  final double settleTimeSeconds;

  /// Resume guiding after flip (if was running)
  @override
  @JsonKey()
  final bool resumeGuidingAfterFlip;
// === Error Handling ===
  /// Maximum retry attempts
  @override
  @JsonKey()
  final int maxRetries;

  /// Delay between retries in seconds
  final List<double> _retryDelaysSeconds;

  /// Delay between retries in seconds
  @override
  @JsonKey()
  List<double> get retryDelaysSeconds {
    if (_retryDelaysSeconds is EqualUnmodifiableListView)
      return _retryDelaysSeconds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_retryDelaysSeconds);
  }

  /// Action to take on permanent failure
  @override
  @JsonKey()
  final FlipFailureAction failureAction;
// === Notifications ===
  /// Play sound alert when flip starts/completes/fails
  @override
  @JsonKey()
  final bool soundAlertOnFlip;

  /// Send push notification to mobile app
  @override
  @JsonKey()
  final bool pushNotificationOnFlip;

  @override
  String toString() {
    return 'MeridianFlipSettings(standaloneMonitoringEnabled: $standaloneMonitoringEnabled, triggerMethod: $triggerMethod, minutesPastMeridian: $minutesPastMeridian, minutesBeforeLimit: $minutesBeforeLimit, hourAngleThreshold: $hourAngleThreshold, pauseGuidingBeforeFlip: $pauseGuidingBeforeFlip, recenterAfterFlip: $recenterAfterFlip, refocusAfterFlip: $refocusAfterFlip, settleTimeSeconds: $settleTimeSeconds, resumeGuidingAfterFlip: $resumeGuidingAfterFlip, maxRetries: $maxRetries, retryDelaysSeconds: $retryDelaysSeconds, failureAction: $failureAction, soundAlertOnFlip: $soundAlertOnFlip, pushNotificationOnFlip: $pushNotificationOnFlip)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipSettingsImpl &&
            (identical(other.standaloneMonitoringEnabled,
                    standaloneMonitoringEnabled) ||
                other.standaloneMonitoringEnabled ==
                    standaloneMonitoringEnabled) &&
            (identical(other.triggerMethod, triggerMethod) ||
                other.triggerMethod == triggerMethod) &&
            (identical(other.minutesPastMeridian, minutesPastMeridian) ||
                other.minutesPastMeridian == minutesPastMeridian) &&
            (identical(other.minutesBeforeLimit, minutesBeforeLimit) ||
                other.minutesBeforeLimit == minutesBeforeLimit) &&
            (identical(other.hourAngleThreshold, hourAngleThreshold) ||
                other.hourAngleThreshold == hourAngleThreshold) &&
            (identical(other.pauseGuidingBeforeFlip, pauseGuidingBeforeFlip) ||
                other.pauseGuidingBeforeFlip == pauseGuidingBeforeFlip) &&
            (identical(other.recenterAfterFlip, recenterAfterFlip) ||
                other.recenterAfterFlip == recenterAfterFlip) &&
            (identical(other.refocusAfterFlip, refocusAfterFlip) ||
                other.refocusAfterFlip == refocusAfterFlip) &&
            (identical(other.settleTimeSeconds, settleTimeSeconds) ||
                other.settleTimeSeconds == settleTimeSeconds) &&
            (identical(other.resumeGuidingAfterFlip, resumeGuidingAfterFlip) ||
                other.resumeGuidingAfterFlip == resumeGuidingAfterFlip) &&
            (identical(other.maxRetries, maxRetries) ||
                other.maxRetries == maxRetries) &&
            const DeepCollectionEquality()
                .equals(other._retryDelaysSeconds, _retryDelaysSeconds) &&
            (identical(other.failureAction, failureAction) ||
                other.failureAction == failureAction) &&
            (identical(other.soundAlertOnFlip, soundAlertOnFlip) ||
                other.soundAlertOnFlip == soundAlertOnFlip) &&
            (identical(other.pushNotificationOnFlip, pushNotificationOnFlip) ||
                other.pushNotificationOnFlip == pushNotificationOnFlip));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      standaloneMonitoringEnabled,
      triggerMethod,
      minutesPastMeridian,
      minutesBeforeLimit,
      hourAngleThreshold,
      pauseGuidingBeforeFlip,
      recenterAfterFlip,
      refocusAfterFlip,
      settleTimeSeconds,
      resumeGuidingAfterFlip,
      maxRetries,
      const DeepCollectionEquality().hash(_retryDelaysSeconds),
      failureAction,
      soundAlertOnFlip,
      pushNotificationOnFlip);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipSettingsImplCopyWith<_$MeridianFlipSettingsImpl>
      get copyWith =>
          __$$MeridianFlipSettingsImplCopyWithImpl<_$MeridianFlipSettingsImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipSettingsImplToJson(
      this,
    );
  }
}

abstract class _MeridianFlipSettings extends MeridianFlipSettings {
  const factory _MeridianFlipSettings(
      {final bool standaloneMonitoringEnabled,
      final MeridianTriggerMethod triggerMethod,
      final double minutesPastMeridian,
      final double minutesBeforeLimit,
      final double hourAngleThreshold,
      final bool pauseGuidingBeforeFlip,
      final bool recenterAfterFlip,
      final bool refocusAfterFlip,
      final double settleTimeSeconds,
      final bool resumeGuidingAfterFlip,
      final int maxRetries,
      final List<double> retryDelaysSeconds,
      final FlipFailureAction failureAction,
      final bool soundAlertOnFlip,
      final bool pushNotificationOnFlip}) = _$MeridianFlipSettingsImpl;
  const _MeridianFlipSettings._() : super._();

  factory _MeridianFlipSettings.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipSettingsImpl.fromJson;

  @override // === Mode Control ===
  /// Enable standalone monitoring when no sequence is running
  bool get standaloneMonitoringEnabled;
  @override // === Trigger Conditions ===
  /// Which method to use for determining flip timing
  MeridianTriggerMethod get triggerMethod;
  @override

  /// Minutes past meridian to trigger flip (default: 5)
  double get minutesPastMeridian;
  @override

  /// Minutes before mount limit to trigger flip (default: 10)
  double get minutesBeforeLimit;
  @override

  /// Hour angle threshold in hours to trigger flip (default: 0.5 = 30 min)
  double get hourAngleThreshold;
  @override // === Flip Sequence Options ===
  /// Pause guider before flip
  bool get pauseGuidingBeforeFlip;
  @override

  /// Plate solve and re-center after flip
  bool get recenterAfterFlip;
  @override

  /// Run autofocus after flip
  bool get refocusAfterFlip;
  @override

  /// Settle time in seconds after flip completes
  double get settleTimeSeconds;
  @override

  /// Resume guiding after flip (if was running)
  bool get resumeGuidingAfterFlip;
  @override // === Error Handling ===
  /// Maximum retry attempts
  int get maxRetries;
  @override

  /// Delay between retries in seconds
  List<double> get retryDelaysSeconds;
  @override

  /// Action to take on permanent failure
  FlipFailureAction get failureAction;
  @override // === Notifications ===
  /// Play sound alert when flip starts/completes/fails
  bool get soundAlertOnFlip;
  @override

  /// Send push notification to mobile app
  bool get pushNotificationOnFlip;
  @override
  @JsonKey(ignore: true)
  _$$MeridianFlipSettingsImplCopyWith<_$MeridianFlipSettingsImpl>
      get copyWith => throw _privateConstructorUsedError;
}
