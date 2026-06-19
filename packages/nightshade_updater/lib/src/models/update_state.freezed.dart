// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateState {

/// Current status
 UpdateStatus get status;/// Current app version
 String get currentVersion;/// Current build number
 int get currentBuildNumber;/// Available update manifest (if any)
 UpdateManifest? get availableUpdate;/// Download progress (0.0 to 1.0)
 double get downloadProgress;/// Downloaded bytes
 int get downloadedBytes;/// Total bytes to download
 int get totalBytes;/// Error message if status is error
 String? get errorMessage;/// Path to staged update (if staged)
 String? get stagingPath;/// Last update check time
 DateTime? get lastCheckTime;/// Version user chose to skip
 String? get skippedVersion;/// Update server URL
 String? get updateServerUrl;/// Current update channel
 String get channel;
/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateStateCopyWith<UpdateState> get copyWith => _$UpdateStateCopyWithImpl<UpdateState>(this as UpdateState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateState&&(identical(other.status, status) || other.status == status)&&(identical(other.currentVersion, currentVersion) || other.currentVersion == currentVersion)&&(identical(other.currentBuildNumber, currentBuildNumber) || other.currentBuildNumber == currentBuildNumber)&&(identical(other.availableUpdate, availableUpdate) || other.availableUpdate == availableUpdate)&&(identical(other.downloadProgress, downloadProgress) || other.downloadProgress == downloadProgress)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.stagingPath, stagingPath) || other.stagingPath == stagingPath)&&(identical(other.lastCheckTime, lastCheckTime) || other.lastCheckTime == lastCheckTime)&&(identical(other.skippedVersion, skippedVersion) || other.skippedVersion == skippedVersion)&&(identical(other.updateServerUrl, updateServerUrl) || other.updateServerUrl == updateServerUrl)&&(identical(other.channel, channel) || other.channel == channel));
}


@override
int get hashCode => Object.hash(runtimeType,status,currentVersion,currentBuildNumber,availableUpdate,downloadProgress,downloadedBytes,totalBytes,errorMessage,stagingPath,lastCheckTime,skippedVersion,updateServerUrl,channel);

@override
String toString() {
  return 'UpdateState(status: $status, currentVersion: $currentVersion, currentBuildNumber: $currentBuildNumber, availableUpdate: $availableUpdate, downloadProgress: $downloadProgress, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, errorMessage: $errorMessage, stagingPath: $stagingPath, lastCheckTime: $lastCheckTime, skippedVersion: $skippedVersion, updateServerUrl: $updateServerUrl, channel: $channel)';
}


}

/// @nodoc
abstract mixin class $UpdateStateCopyWith<$Res>  {
  factory $UpdateStateCopyWith(UpdateState value, $Res Function(UpdateState) _then) = _$UpdateStateCopyWithImpl;
@useResult
$Res call({
 UpdateStatus status, String currentVersion, int currentBuildNumber, UpdateManifest? availableUpdate, double downloadProgress, int downloadedBytes, int totalBytes, String? errorMessage, String? stagingPath, DateTime? lastCheckTime, String? skippedVersion, String? updateServerUrl, String channel
});


$UpdateManifestCopyWith<$Res>? get availableUpdate;

}
/// @nodoc
class _$UpdateStateCopyWithImpl<$Res>
    implements $UpdateStateCopyWith<$Res> {
  _$UpdateStateCopyWithImpl(this._self, this._then);

  final UpdateState _self;
  final $Res Function(UpdateState) _then;

/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? currentVersion = null,Object? currentBuildNumber = null,Object? availableUpdate = freezed,Object? downloadProgress = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? errorMessage = freezed,Object? stagingPath = freezed,Object? lastCheckTime = freezed,Object? skippedVersion = freezed,Object? updateServerUrl = freezed,Object? channel = null,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as UpdateStatus,currentVersion: null == currentVersion ? _self.currentVersion : currentVersion // ignore: cast_nullable_to_non_nullable
as String,currentBuildNumber: null == currentBuildNumber ? _self.currentBuildNumber : currentBuildNumber // ignore: cast_nullable_to_non_nullable
as int,availableUpdate: freezed == availableUpdate ? _self.availableUpdate : availableUpdate // ignore: cast_nullable_to_non_nullable
as UpdateManifest?,downloadProgress: null == downloadProgress ? _self.downloadProgress : downloadProgress // ignore: cast_nullable_to_non_nullable
as double,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,stagingPath: freezed == stagingPath ? _self.stagingPath : stagingPath // ignore: cast_nullable_to_non_nullable
as String?,lastCheckTime: freezed == lastCheckTime ? _self.lastCheckTime : lastCheckTime // ignore: cast_nullable_to_non_nullable
as DateTime?,skippedVersion: freezed == skippedVersion ? _self.skippedVersion : skippedVersion // ignore: cast_nullable_to_non_nullable
as String?,updateServerUrl: freezed == updateServerUrl ? _self.updateServerUrl : updateServerUrl // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateManifestCopyWith<$Res>? get availableUpdate {
    if (_self.availableUpdate == null) {
    return null;
  }

  return $UpdateManifestCopyWith<$Res>(_self.availableUpdate!, (value) {
    return _then(_self.copyWith(availableUpdate: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateState].
extension UpdateStatePatterns on UpdateState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateState value)  $default,){
final _that = this;
switch (_that) {
case _UpdateState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateState value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdateStatus status,  String currentVersion,  int currentBuildNumber,  UpdateManifest? availableUpdate,  double downloadProgress,  int downloadedBytes,  int totalBytes,  String? errorMessage,  String? stagingPath,  DateTime? lastCheckTime,  String? skippedVersion,  String? updateServerUrl,  String channel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateState() when $default != null:
return $default(_that.status,_that.currentVersion,_that.currentBuildNumber,_that.availableUpdate,_that.downloadProgress,_that.downloadedBytes,_that.totalBytes,_that.errorMessage,_that.stagingPath,_that.lastCheckTime,_that.skippedVersion,_that.updateServerUrl,_that.channel);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdateStatus status,  String currentVersion,  int currentBuildNumber,  UpdateManifest? availableUpdate,  double downloadProgress,  int downloadedBytes,  int totalBytes,  String? errorMessage,  String? stagingPath,  DateTime? lastCheckTime,  String? skippedVersion,  String? updateServerUrl,  String channel)  $default,) {final _that = this;
switch (_that) {
case _UpdateState():
return $default(_that.status,_that.currentVersion,_that.currentBuildNumber,_that.availableUpdate,_that.downloadProgress,_that.downloadedBytes,_that.totalBytes,_that.errorMessage,_that.stagingPath,_that.lastCheckTime,_that.skippedVersion,_that.updateServerUrl,_that.channel);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdateStatus status,  String currentVersion,  int currentBuildNumber,  UpdateManifest? availableUpdate,  double downloadProgress,  int downloadedBytes,  int totalBytes,  String? errorMessage,  String? stagingPath,  DateTime? lastCheckTime,  String? skippedVersion,  String? updateServerUrl,  String channel)?  $default,) {final _that = this;
switch (_that) {
case _UpdateState() when $default != null:
return $default(_that.status,_that.currentVersion,_that.currentBuildNumber,_that.availableUpdate,_that.downloadProgress,_that.downloadedBytes,_that.totalBytes,_that.errorMessage,_that.stagingPath,_that.lastCheckTime,_that.skippedVersion,_that.updateServerUrl,_that.channel);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateState extends UpdateState {
  const _UpdateState({this.status = UpdateStatus.idle, required this.currentVersion, required this.currentBuildNumber, this.availableUpdate, this.downloadProgress = 0.0, this.downloadedBytes = 0, this.totalBytes = 0, this.errorMessage, this.stagingPath, this.lastCheckTime, this.skippedVersion, this.updateServerUrl, this.channel = 'stable'}): super._();
  

/// Current status
@override@JsonKey() final  UpdateStatus status;
/// Current app version
@override final  String currentVersion;
/// Current build number
@override final  int currentBuildNumber;
/// Available update manifest (if any)
@override final  UpdateManifest? availableUpdate;
/// Download progress (0.0 to 1.0)
@override@JsonKey() final  double downloadProgress;
/// Downloaded bytes
@override@JsonKey() final  int downloadedBytes;
/// Total bytes to download
@override@JsonKey() final  int totalBytes;
/// Error message if status is error
@override final  String? errorMessage;
/// Path to staged update (if staged)
@override final  String? stagingPath;
/// Last update check time
@override final  DateTime? lastCheckTime;
/// Version user chose to skip
@override final  String? skippedVersion;
/// Update server URL
@override final  String? updateServerUrl;
/// Current update channel
@override@JsonKey() final  String channel;

/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateStateCopyWith<_UpdateState> get copyWith => __$UpdateStateCopyWithImpl<_UpdateState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateState&&(identical(other.status, status) || other.status == status)&&(identical(other.currentVersion, currentVersion) || other.currentVersion == currentVersion)&&(identical(other.currentBuildNumber, currentBuildNumber) || other.currentBuildNumber == currentBuildNumber)&&(identical(other.availableUpdate, availableUpdate) || other.availableUpdate == availableUpdate)&&(identical(other.downloadProgress, downloadProgress) || other.downloadProgress == downloadProgress)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.stagingPath, stagingPath) || other.stagingPath == stagingPath)&&(identical(other.lastCheckTime, lastCheckTime) || other.lastCheckTime == lastCheckTime)&&(identical(other.skippedVersion, skippedVersion) || other.skippedVersion == skippedVersion)&&(identical(other.updateServerUrl, updateServerUrl) || other.updateServerUrl == updateServerUrl)&&(identical(other.channel, channel) || other.channel == channel));
}


@override
int get hashCode => Object.hash(runtimeType,status,currentVersion,currentBuildNumber,availableUpdate,downloadProgress,downloadedBytes,totalBytes,errorMessage,stagingPath,lastCheckTime,skippedVersion,updateServerUrl,channel);

@override
String toString() {
  return 'UpdateState(status: $status, currentVersion: $currentVersion, currentBuildNumber: $currentBuildNumber, availableUpdate: $availableUpdate, downloadProgress: $downloadProgress, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, errorMessage: $errorMessage, stagingPath: $stagingPath, lastCheckTime: $lastCheckTime, skippedVersion: $skippedVersion, updateServerUrl: $updateServerUrl, channel: $channel)';
}


}

/// @nodoc
abstract mixin class _$UpdateStateCopyWith<$Res> implements $UpdateStateCopyWith<$Res> {
  factory _$UpdateStateCopyWith(_UpdateState value, $Res Function(_UpdateState) _then) = __$UpdateStateCopyWithImpl;
@override @useResult
$Res call({
 UpdateStatus status, String currentVersion, int currentBuildNumber, UpdateManifest? availableUpdate, double downloadProgress, int downloadedBytes, int totalBytes, String? errorMessage, String? stagingPath, DateTime? lastCheckTime, String? skippedVersion, String? updateServerUrl, String channel
});


@override $UpdateManifestCopyWith<$Res>? get availableUpdate;

}
/// @nodoc
class __$UpdateStateCopyWithImpl<$Res>
    implements _$UpdateStateCopyWith<$Res> {
  __$UpdateStateCopyWithImpl(this._self, this._then);

  final _UpdateState _self;
  final $Res Function(_UpdateState) _then;

/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? currentVersion = null,Object? currentBuildNumber = null,Object? availableUpdate = freezed,Object? downloadProgress = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? errorMessage = freezed,Object? stagingPath = freezed,Object? lastCheckTime = freezed,Object? skippedVersion = freezed,Object? updateServerUrl = freezed,Object? channel = null,}) {
  return _then(_UpdateState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as UpdateStatus,currentVersion: null == currentVersion ? _self.currentVersion : currentVersion // ignore: cast_nullable_to_non_nullable
as String,currentBuildNumber: null == currentBuildNumber ? _self.currentBuildNumber : currentBuildNumber // ignore: cast_nullable_to_non_nullable
as int,availableUpdate: freezed == availableUpdate ? _self.availableUpdate : availableUpdate // ignore: cast_nullable_to_non_nullable
as UpdateManifest?,downloadProgress: null == downloadProgress ? _self.downloadProgress : downloadProgress // ignore: cast_nullable_to_non_nullable
as double,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,stagingPath: freezed == stagingPath ? _self.stagingPath : stagingPath // ignore: cast_nullable_to_non_nullable
as String?,lastCheckTime: freezed == lastCheckTime ? _self.lastCheckTime : lastCheckTime // ignore: cast_nullable_to_non_nullable
as DateTime?,skippedVersion: freezed == skippedVersion ? _self.skippedVersion : skippedVersion // ignore: cast_nullable_to_non_nullable
as String?,updateServerUrl: freezed == updateServerUrl ? _self.updateServerUrl : updateServerUrl // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of UpdateState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateManifestCopyWith<$Res>? get availableUpdate {
    if (_self.availableUpdate == null) {
    return null;
  }

  return $UpdateManifestCopyWith<$Res>(_self.availableUpdate!, (value) {
    return _then(_self.copyWith(availableUpdate: value));
  });
}
}

/// @nodoc
mixin _$UpdateSettings {

/// Whether automatic update checking is enabled
 bool get autoCheckEnabled;/// Update server URL
 String get serverUrl;/// Update channel (stable, beta, alpha)
 String get channel;/// Hours between automatic checks
 int get checkIntervalHours;/// Version user chose to skip (won't prompt for this version)
 String? get skippedVersion;
/// Create a copy of UpdateSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateSettingsCopyWith<UpdateSettings> get copyWith => _$UpdateSettingsCopyWithImpl<UpdateSettings>(this as UpdateSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateSettings&&(identical(other.autoCheckEnabled, autoCheckEnabled) || other.autoCheckEnabled == autoCheckEnabled)&&(identical(other.serverUrl, serverUrl) || other.serverUrl == serverUrl)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.checkIntervalHours, checkIntervalHours) || other.checkIntervalHours == checkIntervalHours)&&(identical(other.skippedVersion, skippedVersion) || other.skippedVersion == skippedVersion));
}


@override
int get hashCode => Object.hash(runtimeType,autoCheckEnabled,serverUrl,channel,checkIntervalHours,skippedVersion);

@override
String toString() {
  return 'UpdateSettings(autoCheckEnabled: $autoCheckEnabled, serverUrl: $serverUrl, channel: $channel, checkIntervalHours: $checkIntervalHours, skippedVersion: $skippedVersion)';
}


}

/// @nodoc
abstract mixin class $UpdateSettingsCopyWith<$Res>  {
  factory $UpdateSettingsCopyWith(UpdateSettings value, $Res Function(UpdateSettings) _then) = _$UpdateSettingsCopyWithImpl;
@useResult
$Res call({
 bool autoCheckEnabled, String serverUrl, String channel, int checkIntervalHours, String? skippedVersion
});




}
/// @nodoc
class _$UpdateSettingsCopyWithImpl<$Res>
    implements $UpdateSettingsCopyWith<$Res> {
  _$UpdateSettingsCopyWithImpl(this._self, this._then);

  final UpdateSettings _self;
  final $Res Function(UpdateSettings) _then;

/// Create a copy of UpdateSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? autoCheckEnabled = null,Object? serverUrl = null,Object? channel = null,Object? checkIntervalHours = null,Object? skippedVersion = freezed,}) {
  return _then(_self.copyWith(
autoCheckEnabled: null == autoCheckEnabled ? _self.autoCheckEnabled : autoCheckEnabled // ignore: cast_nullable_to_non_nullable
as bool,serverUrl: null == serverUrl ? _self.serverUrl : serverUrl // ignore: cast_nullable_to_non_nullable
as String,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,checkIntervalHours: null == checkIntervalHours ? _self.checkIntervalHours : checkIntervalHours // ignore: cast_nullable_to_non_nullable
as int,skippedVersion: freezed == skippedVersion ? _self.skippedVersion : skippedVersion // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateSettings].
extension UpdateSettingsPatterns on UpdateSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateSettings value)  $default,){
final _that = this;
switch (_that) {
case _UpdateSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateSettings value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool autoCheckEnabled,  String serverUrl,  String channel,  int checkIntervalHours,  String? skippedVersion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateSettings() when $default != null:
return $default(_that.autoCheckEnabled,_that.serverUrl,_that.channel,_that.checkIntervalHours,_that.skippedVersion);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool autoCheckEnabled,  String serverUrl,  String channel,  int checkIntervalHours,  String? skippedVersion)  $default,) {final _that = this;
switch (_that) {
case _UpdateSettings():
return $default(_that.autoCheckEnabled,_that.serverUrl,_that.channel,_that.checkIntervalHours,_that.skippedVersion);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool autoCheckEnabled,  String serverUrl,  String channel,  int checkIntervalHours,  String? skippedVersion)?  $default,) {final _that = this;
switch (_that) {
case _UpdateSettings() when $default != null:
return $default(_that.autoCheckEnabled,_that.serverUrl,_that.channel,_that.checkIntervalHours,_that.skippedVersion);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateSettings implements UpdateSettings {
  const _UpdateSettings({this.autoCheckEnabled = true, required this.serverUrl, this.channel = 'stable', this.checkIntervalHours = 24, this.skippedVersion});
  

/// Whether automatic update checking is enabled
@override@JsonKey() final  bool autoCheckEnabled;
/// Update server URL
@override final  String serverUrl;
/// Update channel (stable, beta, alpha)
@override@JsonKey() final  String channel;
/// Hours between automatic checks
@override@JsonKey() final  int checkIntervalHours;
/// Version user chose to skip (won't prompt for this version)
@override final  String? skippedVersion;

/// Create a copy of UpdateSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateSettingsCopyWith<_UpdateSettings> get copyWith => __$UpdateSettingsCopyWithImpl<_UpdateSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateSettings&&(identical(other.autoCheckEnabled, autoCheckEnabled) || other.autoCheckEnabled == autoCheckEnabled)&&(identical(other.serverUrl, serverUrl) || other.serverUrl == serverUrl)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.checkIntervalHours, checkIntervalHours) || other.checkIntervalHours == checkIntervalHours)&&(identical(other.skippedVersion, skippedVersion) || other.skippedVersion == skippedVersion));
}


@override
int get hashCode => Object.hash(runtimeType,autoCheckEnabled,serverUrl,channel,checkIntervalHours,skippedVersion);

@override
String toString() {
  return 'UpdateSettings(autoCheckEnabled: $autoCheckEnabled, serverUrl: $serverUrl, channel: $channel, checkIntervalHours: $checkIntervalHours, skippedVersion: $skippedVersion)';
}


}

/// @nodoc
abstract mixin class _$UpdateSettingsCopyWith<$Res> implements $UpdateSettingsCopyWith<$Res> {
  factory _$UpdateSettingsCopyWith(_UpdateSettings value, $Res Function(_UpdateSettings) _then) = __$UpdateSettingsCopyWithImpl;
@override @useResult
$Res call({
 bool autoCheckEnabled, String serverUrl, String channel, int checkIntervalHours, String? skippedVersion
});




}
/// @nodoc
class __$UpdateSettingsCopyWithImpl<$Res>
    implements _$UpdateSettingsCopyWith<$Res> {
  __$UpdateSettingsCopyWithImpl(this._self, this._then);

  final _UpdateSettings _self;
  final $Res Function(_UpdateSettings) _then;

/// Create a copy of UpdateSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? autoCheckEnabled = null,Object? serverUrl = null,Object? channel = null,Object? checkIntervalHours = null,Object? skippedVersion = freezed,}) {
  return _then(_UpdateSettings(
autoCheckEnabled: null == autoCheckEnabled ? _self.autoCheckEnabled : autoCheckEnabled // ignore: cast_nullable_to_non_nullable
as bool,serverUrl: null == serverUrl ? _self.serverUrl : serverUrl // ignore: cast_nullable_to_non_nullable
as String,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,checkIntervalHours: null == checkIntervalHours ? _self.checkIntervalHours : checkIntervalHours // ignore: cast_nullable_to_non_nullable
as int,skippedVersion: freezed == skippedVersion ? _self.skippedVersion : skippedVersion // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
