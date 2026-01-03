// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$UpdateState {
  /// Current status
  UpdateStatus get status => throw _privateConstructorUsedError;

  /// Current app version
  String get currentVersion => throw _privateConstructorUsedError;

  /// Current build number
  int get currentBuildNumber => throw _privateConstructorUsedError;

  /// Available update manifest (if any)
  UpdateManifest? get availableUpdate => throw _privateConstructorUsedError;

  /// Download progress (0.0 to 1.0)
  double get downloadProgress => throw _privateConstructorUsedError;

  /// Downloaded bytes
  int get downloadedBytes => throw _privateConstructorUsedError;

  /// Total bytes to download
  int get totalBytes => throw _privateConstructorUsedError;

  /// Error message if status is error
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Path to staged update (if staged)
  String? get stagingPath => throw _privateConstructorUsedError;

  /// Last update check time
  DateTime? get lastCheckTime => throw _privateConstructorUsedError;

  /// Version user chose to skip
  String? get skippedVersion => throw _privateConstructorUsedError;

  /// Update server URL
  String? get updateServerUrl => throw _privateConstructorUsedError;

  /// Current update channel
  String get channel => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $UpdateStateCopyWith<UpdateState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateStateCopyWith<$Res> {
  factory $UpdateStateCopyWith(
          UpdateState value, $Res Function(UpdateState) then) =
      _$UpdateStateCopyWithImpl<$Res, UpdateState>;
  @useResult
  $Res call(
      {UpdateStatus status,
      String currentVersion,
      int currentBuildNumber,
      UpdateManifest? availableUpdate,
      double downloadProgress,
      int downloadedBytes,
      int totalBytes,
      String? errorMessage,
      String? stagingPath,
      DateTime? lastCheckTime,
      String? skippedVersion,
      String? updateServerUrl,
      String channel});

  $UpdateManifestCopyWith<$Res>? get availableUpdate;
}

/// @nodoc
class _$UpdateStateCopyWithImpl<$Res, $Val extends UpdateState>
    implements $UpdateStateCopyWith<$Res> {
  _$UpdateStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? currentVersion = null,
    Object? currentBuildNumber = null,
    Object? availableUpdate = freezed,
    Object? downloadProgress = null,
    Object? downloadedBytes = null,
    Object? totalBytes = null,
    Object? errorMessage = freezed,
    Object? stagingPath = freezed,
    Object? lastCheckTime = freezed,
    Object? skippedVersion = freezed,
    Object? updateServerUrl = freezed,
    Object? channel = null,
  }) {
    return _then(_value.copyWith(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as UpdateStatus,
      currentVersion: null == currentVersion
          ? _value.currentVersion
          : currentVersion // ignore: cast_nullable_to_non_nullable
              as String,
      currentBuildNumber: null == currentBuildNumber
          ? _value.currentBuildNumber
          : currentBuildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      availableUpdate: freezed == availableUpdate
          ? _value.availableUpdate
          : availableUpdate // ignore: cast_nullable_to_non_nullable
              as UpdateManifest?,
      downloadProgress: null == downloadProgress
          ? _value.downloadProgress
          : downloadProgress // ignore: cast_nullable_to_non_nullable
              as double,
      downloadedBytes: null == downloadedBytes
          ? _value.downloadedBytes
          : downloadedBytes // ignore: cast_nullable_to_non_nullable
              as int,
      totalBytes: null == totalBytes
          ? _value.totalBytes
          : totalBytes // ignore: cast_nullable_to_non_nullable
              as int,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      stagingPath: freezed == stagingPath
          ? _value.stagingPath
          : stagingPath // ignore: cast_nullable_to_non_nullable
              as String?,
      lastCheckTime: freezed == lastCheckTime
          ? _value.lastCheckTime
          : lastCheckTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      skippedVersion: freezed == skippedVersion
          ? _value.skippedVersion
          : skippedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      updateServerUrl: freezed == updateServerUrl
          ? _value.updateServerUrl
          : updateServerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      channel: null == channel
          ? _value.channel
          : channel // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $UpdateManifestCopyWith<$Res>? get availableUpdate {
    if (_value.availableUpdate == null) {
      return null;
    }

    return $UpdateManifestCopyWith<$Res>(_value.availableUpdate!, (value) {
      return _then(_value.copyWith(availableUpdate: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$UpdateStateImplCopyWith<$Res>
    implements $UpdateStateCopyWith<$Res> {
  factory _$$UpdateStateImplCopyWith(
          _$UpdateStateImpl value, $Res Function(_$UpdateStateImpl) then) =
      __$$UpdateStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {UpdateStatus status,
      String currentVersion,
      int currentBuildNumber,
      UpdateManifest? availableUpdate,
      double downloadProgress,
      int downloadedBytes,
      int totalBytes,
      String? errorMessage,
      String? stagingPath,
      DateTime? lastCheckTime,
      String? skippedVersion,
      String? updateServerUrl,
      String channel});

  @override
  $UpdateManifestCopyWith<$Res>? get availableUpdate;
}

/// @nodoc
class __$$UpdateStateImplCopyWithImpl<$Res>
    extends _$UpdateStateCopyWithImpl<$Res, _$UpdateStateImpl>
    implements _$$UpdateStateImplCopyWith<$Res> {
  __$$UpdateStateImplCopyWithImpl(
      _$UpdateStateImpl _value, $Res Function(_$UpdateStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? currentVersion = null,
    Object? currentBuildNumber = null,
    Object? availableUpdate = freezed,
    Object? downloadProgress = null,
    Object? downloadedBytes = null,
    Object? totalBytes = null,
    Object? errorMessage = freezed,
    Object? stagingPath = freezed,
    Object? lastCheckTime = freezed,
    Object? skippedVersion = freezed,
    Object? updateServerUrl = freezed,
    Object? channel = null,
  }) {
    return _then(_$UpdateStateImpl(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as UpdateStatus,
      currentVersion: null == currentVersion
          ? _value.currentVersion
          : currentVersion // ignore: cast_nullable_to_non_nullable
              as String,
      currentBuildNumber: null == currentBuildNumber
          ? _value.currentBuildNumber
          : currentBuildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      availableUpdate: freezed == availableUpdate
          ? _value.availableUpdate
          : availableUpdate // ignore: cast_nullable_to_non_nullable
              as UpdateManifest?,
      downloadProgress: null == downloadProgress
          ? _value.downloadProgress
          : downloadProgress // ignore: cast_nullable_to_non_nullable
              as double,
      downloadedBytes: null == downloadedBytes
          ? _value.downloadedBytes
          : downloadedBytes // ignore: cast_nullable_to_non_nullable
              as int,
      totalBytes: null == totalBytes
          ? _value.totalBytes
          : totalBytes // ignore: cast_nullable_to_non_nullable
              as int,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      stagingPath: freezed == stagingPath
          ? _value.stagingPath
          : stagingPath // ignore: cast_nullable_to_non_nullable
              as String?,
      lastCheckTime: freezed == lastCheckTime
          ? _value.lastCheckTime
          : lastCheckTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      skippedVersion: freezed == skippedVersion
          ? _value.skippedVersion
          : skippedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      updateServerUrl: freezed == updateServerUrl
          ? _value.updateServerUrl
          : updateServerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      channel: null == channel
          ? _value.channel
          : channel // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$UpdateStateImpl extends _UpdateState {
  const _$UpdateStateImpl(
      {this.status = UpdateStatus.idle,
      required this.currentVersion,
      required this.currentBuildNumber,
      this.availableUpdate,
      this.downloadProgress = 0.0,
      this.downloadedBytes = 0,
      this.totalBytes = 0,
      this.errorMessage,
      this.stagingPath,
      this.lastCheckTime,
      this.skippedVersion,
      this.updateServerUrl,
      this.channel = 'stable'})
      : super._();

  /// Current status
  @override
  @JsonKey()
  final UpdateStatus status;

  /// Current app version
  @override
  final String currentVersion;

  /// Current build number
  @override
  final int currentBuildNumber;

  /// Available update manifest (if any)
  @override
  final UpdateManifest? availableUpdate;

  /// Download progress (0.0 to 1.0)
  @override
  @JsonKey()
  final double downloadProgress;

  /// Downloaded bytes
  @override
  @JsonKey()
  final int downloadedBytes;

  /// Total bytes to download
  @override
  @JsonKey()
  final int totalBytes;

  /// Error message if status is error
  @override
  final String? errorMessage;

  /// Path to staged update (if staged)
  @override
  final String? stagingPath;

  /// Last update check time
  @override
  final DateTime? lastCheckTime;

  /// Version user chose to skip
  @override
  final String? skippedVersion;

  /// Update server URL
  @override
  final String? updateServerUrl;

  /// Current update channel
  @override
  @JsonKey()
  final String channel;

  @override
  String toString() {
    return 'UpdateState(status: $status, currentVersion: $currentVersion, currentBuildNumber: $currentBuildNumber, availableUpdate: $availableUpdate, downloadProgress: $downloadProgress, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, errorMessage: $errorMessage, stagingPath: $stagingPath, lastCheckTime: $lastCheckTime, skippedVersion: $skippedVersion, updateServerUrl: $updateServerUrl, channel: $channel)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateStateImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.currentVersion, currentVersion) ||
                other.currentVersion == currentVersion) &&
            (identical(other.currentBuildNumber, currentBuildNumber) ||
                other.currentBuildNumber == currentBuildNumber) &&
            (identical(other.availableUpdate, availableUpdate) ||
                other.availableUpdate == availableUpdate) &&
            (identical(other.downloadProgress, downloadProgress) ||
                other.downloadProgress == downloadProgress) &&
            (identical(other.downloadedBytes, downloadedBytes) ||
                other.downloadedBytes == downloadedBytes) &&
            (identical(other.totalBytes, totalBytes) ||
                other.totalBytes == totalBytes) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.stagingPath, stagingPath) ||
                other.stagingPath == stagingPath) &&
            (identical(other.lastCheckTime, lastCheckTime) ||
                other.lastCheckTime == lastCheckTime) &&
            (identical(other.skippedVersion, skippedVersion) ||
                other.skippedVersion == skippedVersion) &&
            (identical(other.updateServerUrl, updateServerUrl) ||
                other.updateServerUrl == updateServerUrl) &&
            (identical(other.channel, channel) || other.channel == channel));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      status,
      currentVersion,
      currentBuildNumber,
      availableUpdate,
      downloadProgress,
      downloadedBytes,
      totalBytes,
      errorMessage,
      stagingPath,
      lastCheckTime,
      skippedVersion,
      updateServerUrl,
      channel);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateStateImplCopyWith<_$UpdateStateImpl> get copyWith =>
      __$$UpdateStateImplCopyWithImpl<_$UpdateStateImpl>(this, _$identity);
}

abstract class _UpdateState extends UpdateState {
  const factory _UpdateState(
      {final UpdateStatus status,
      required final String currentVersion,
      required final int currentBuildNumber,
      final UpdateManifest? availableUpdate,
      final double downloadProgress,
      final int downloadedBytes,
      final int totalBytes,
      final String? errorMessage,
      final String? stagingPath,
      final DateTime? lastCheckTime,
      final String? skippedVersion,
      final String? updateServerUrl,
      final String channel}) = _$UpdateStateImpl;
  const _UpdateState._() : super._();

  @override

  /// Current status
  UpdateStatus get status;
  @override

  /// Current app version
  String get currentVersion;
  @override

  /// Current build number
  int get currentBuildNumber;
  @override

  /// Available update manifest (if any)
  UpdateManifest? get availableUpdate;
  @override

  /// Download progress (0.0 to 1.0)
  double get downloadProgress;
  @override

  /// Downloaded bytes
  int get downloadedBytes;
  @override

  /// Total bytes to download
  int get totalBytes;
  @override

  /// Error message if status is error
  String? get errorMessage;
  @override

  /// Path to staged update (if staged)
  String? get stagingPath;
  @override

  /// Last update check time
  DateTime? get lastCheckTime;
  @override

  /// Version user chose to skip
  String? get skippedVersion;
  @override

  /// Update server URL
  String? get updateServerUrl;
  @override

  /// Current update channel
  String get channel;
  @override
  @JsonKey(ignore: true)
  _$$UpdateStateImplCopyWith<_$UpdateStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$UpdateSettings {
  /// Whether automatic update checking is enabled
  bool get autoCheckEnabled => throw _privateConstructorUsedError;

  /// Update server URL
  String get serverUrl => throw _privateConstructorUsedError;

  /// Update channel (stable, beta, alpha)
  String get channel => throw _privateConstructorUsedError;

  /// Hours between automatic checks
  int get checkIntervalHours => throw _privateConstructorUsedError;

  /// Version user chose to skip (won't prompt for this version)
  String? get skippedVersion => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $UpdateSettingsCopyWith<UpdateSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateSettingsCopyWith<$Res> {
  factory $UpdateSettingsCopyWith(
          UpdateSettings value, $Res Function(UpdateSettings) then) =
      _$UpdateSettingsCopyWithImpl<$Res, UpdateSettings>;
  @useResult
  $Res call(
      {bool autoCheckEnabled,
      String serverUrl,
      String channel,
      int checkIntervalHours,
      String? skippedVersion});
}

/// @nodoc
class _$UpdateSettingsCopyWithImpl<$Res, $Val extends UpdateSettings>
    implements $UpdateSettingsCopyWith<$Res> {
  _$UpdateSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? autoCheckEnabled = null,
    Object? serverUrl = null,
    Object? channel = null,
    Object? checkIntervalHours = null,
    Object? skippedVersion = freezed,
  }) {
    return _then(_value.copyWith(
      autoCheckEnabled: null == autoCheckEnabled
          ? _value.autoCheckEnabled
          : autoCheckEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      serverUrl: null == serverUrl
          ? _value.serverUrl
          : serverUrl // ignore: cast_nullable_to_non_nullable
              as String,
      channel: null == channel
          ? _value.channel
          : channel // ignore: cast_nullable_to_non_nullable
              as String,
      checkIntervalHours: null == checkIntervalHours
          ? _value.checkIntervalHours
          : checkIntervalHours // ignore: cast_nullable_to_non_nullable
              as int,
      skippedVersion: freezed == skippedVersion
          ? _value.skippedVersion
          : skippedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UpdateSettingsImplCopyWith<$Res>
    implements $UpdateSettingsCopyWith<$Res> {
  factory _$$UpdateSettingsImplCopyWith(_$UpdateSettingsImpl value,
          $Res Function(_$UpdateSettingsImpl) then) =
      __$$UpdateSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool autoCheckEnabled,
      String serverUrl,
      String channel,
      int checkIntervalHours,
      String? skippedVersion});
}

/// @nodoc
class __$$UpdateSettingsImplCopyWithImpl<$Res>
    extends _$UpdateSettingsCopyWithImpl<$Res, _$UpdateSettingsImpl>
    implements _$$UpdateSettingsImplCopyWith<$Res> {
  __$$UpdateSettingsImplCopyWithImpl(
      _$UpdateSettingsImpl _value, $Res Function(_$UpdateSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? autoCheckEnabled = null,
    Object? serverUrl = null,
    Object? channel = null,
    Object? checkIntervalHours = null,
    Object? skippedVersion = freezed,
  }) {
    return _then(_$UpdateSettingsImpl(
      autoCheckEnabled: null == autoCheckEnabled
          ? _value.autoCheckEnabled
          : autoCheckEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      serverUrl: null == serverUrl
          ? _value.serverUrl
          : serverUrl // ignore: cast_nullable_to_non_nullable
              as String,
      channel: null == channel
          ? _value.channel
          : channel // ignore: cast_nullable_to_non_nullable
              as String,
      checkIntervalHours: null == checkIntervalHours
          ? _value.checkIntervalHours
          : checkIntervalHours // ignore: cast_nullable_to_non_nullable
              as int,
      skippedVersion: freezed == skippedVersion
          ? _value.skippedVersion
          : skippedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$UpdateSettingsImpl implements _UpdateSettings {
  const _$UpdateSettingsImpl(
      {this.autoCheckEnabled = true,
      required this.serverUrl,
      this.channel = 'stable',
      this.checkIntervalHours = 24,
      this.skippedVersion});

  /// Whether automatic update checking is enabled
  @override
  @JsonKey()
  final bool autoCheckEnabled;

  /// Update server URL
  @override
  final String serverUrl;

  /// Update channel (stable, beta, alpha)
  @override
  @JsonKey()
  final String channel;

  /// Hours between automatic checks
  @override
  @JsonKey()
  final int checkIntervalHours;

  /// Version user chose to skip (won't prompt for this version)
  @override
  final String? skippedVersion;

  @override
  String toString() {
    return 'UpdateSettings(autoCheckEnabled: $autoCheckEnabled, serverUrl: $serverUrl, channel: $channel, checkIntervalHours: $checkIntervalHours, skippedVersion: $skippedVersion)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateSettingsImpl &&
            (identical(other.autoCheckEnabled, autoCheckEnabled) ||
                other.autoCheckEnabled == autoCheckEnabled) &&
            (identical(other.serverUrl, serverUrl) ||
                other.serverUrl == serverUrl) &&
            (identical(other.channel, channel) || other.channel == channel) &&
            (identical(other.checkIntervalHours, checkIntervalHours) ||
                other.checkIntervalHours == checkIntervalHours) &&
            (identical(other.skippedVersion, skippedVersion) ||
                other.skippedVersion == skippedVersion));
  }

  @override
  int get hashCode => Object.hash(runtimeType, autoCheckEnabled, serverUrl,
      channel, checkIntervalHours, skippedVersion);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateSettingsImplCopyWith<_$UpdateSettingsImpl> get copyWith =>
      __$$UpdateSettingsImplCopyWithImpl<_$UpdateSettingsImpl>(
          this, _$identity);
}

abstract class _UpdateSettings implements UpdateSettings {
  const factory _UpdateSettings(
      {final bool autoCheckEnabled,
      required final String serverUrl,
      final String channel,
      final int checkIntervalHours,
      final String? skippedVersion}) = _$UpdateSettingsImpl;

  @override

  /// Whether automatic update checking is enabled
  bool get autoCheckEnabled;
  @override

  /// Update server URL
  String get serverUrl;
  @override

  /// Update channel (stable, beta, alpha)
  String get channel;
  @override

  /// Hours between automatic checks
  int get checkIntervalHours;
  @override

  /// Version user chose to skip (won't prompt for this version)
  String? get skippedVersion;
  @override
  @JsonKey(ignore: true)
  _$$UpdateSettingsImplCopyWith<_$UpdateSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
