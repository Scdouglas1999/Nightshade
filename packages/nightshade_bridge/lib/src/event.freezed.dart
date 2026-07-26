// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EquipmentEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent()';
}


}

/// @nodoc
class $EquipmentEventCopyWith<$Res>  {
$EquipmentEventCopyWith(EquipmentEvent _, $Res Function(EquipmentEvent) __);
}


/// Adds pattern-matching-related methods to [EquipmentEvent].
extension EquipmentEventPatterns on EquipmentEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EquipmentEvent_Connecting value)?  connecting,TResult Function( EquipmentEvent_Connected value)?  connected,TResult Function( EquipmentEvent_Disconnected value)?  disconnected,TResult Function( EquipmentEvent_PropertyChanged value)?  propertyChanged,TResult Function( EquipmentEvent_Error value)?  error,TResult Function( EquipmentEvent_MountSlewStarted value)?  mountSlewStarted,TResult Function( EquipmentEvent_MountSlewCompleted value)?  mountSlewCompleted,TResult Function( EquipmentEvent_MountTrackingStarted value)?  mountTrackingStarted,TResult Function( EquipmentEvent_MountTrackingStopped value)?  mountTrackingStopped,TResult Function( EquipmentEvent_MountParkStarted value)?  mountParkStarted,TResult Function( EquipmentEvent_MountParkCompleted value)?  mountParkCompleted,TResult Function( EquipmentEvent_MountUnparked value)?  mountUnparked,TResult Function( EquipmentEvent_FocuserMoveStarted value)?  focuserMoveStarted,TResult Function( EquipmentEvent_FocuserMoveCompleted value)?  focuserMoveCompleted,TResult Function( EquipmentEvent_FocuserTemperatureChanged value)?  focuserTemperatureChanged,TResult Function( EquipmentEvent_FilterChanging value)?  filterChanging,TResult Function( EquipmentEvent_FilterChanged value)?  filterChanged,TResult Function( EquipmentEvent_RotatorMoveStarted value)?  rotatorMoveStarted,TResult Function( EquipmentEvent_RotatorMoveCompleted value)?  rotatorMoveCompleted,TResult Function( EquipmentEvent_CameraCoolingStarted value)?  cameraCoolingStarted,TResult Function( EquipmentEvent_CameraCoolingReached value)?  cameraCoolingReached,TResult Function( EquipmentEvent_CameraWarmingStarted value)?  cameraWarmingStarted,TResult Function( EquipmentEvent_CameraWarmingCompleted value)?  cameraWarmingCompleted,TResult Function( EquipmentEvent_HeartbeatStarted value)?  heartbeatStarted,TResult Function( EquipmentEvent_HeartbeatStopped value)?  heartbeatStopped,TResult Function( EquipmentEvent_HeartbeatStatusChanged value)?  heartbeatStatusChanged,TResult Function( EquipmentEvent_HeartbeatReconnecting value)?  heartbeatReconnecting,TResult Function( EquipmentEvent_HeartbeatReconnected value)?  heartbeatReconnected,TResult Function( EquipmentEvent_DeviceDiscovered value)?  deviceDiscovered,TResult Function( EquipmentEvent_DeviceLost value)?  deviceLost,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EquipmentEvent_Connecting() when connecting != null:
return connecting(_that);case EquipmentEvent_Connected() when connected != null:
return connected(_that);case EquipmentEvent_Disconnected() when disconnected != null:
return disconnected(_that);case EquipmentEvent_PropertyChanged() when propertyChanged != null:
return propertyChanged(_that);case EquipmentEvent_Error() when error != null:
return error(_that);case EquipmentEvent_MountSlewStarted() when mountSlewStarted != null:
return mountSlewStarted(_that);case EquipmentEvent_MountSlewCompleted() when mountSlewCompleted != null:
return mountSlewCompleted(_that);case EquipmentEvent_MountTrackingStarted() when mountTrackingStarted != null:
return mountTrackingStarted(_that);case EquipmentEvent_MountTrackingStopped() when mountTrackingStopped != null:
return mountTrackingStopped(_that);case EquipmentEvent_MountParkStarted() when mountParkStarted != null:
return mountParkStarted(_that);case EquipmentEvent_MountParkCompleted() when mountParkCompleted != null:
return mountParkCompleted(_that);case EquipmentEvent_MountUnparked() when mountUnparked != null:
return mountUnparked(_that);case EquipmentEvent_FocuserMoveStarted() when focuserMoveStarted != null:
return focuserMoveStarted(_that);case EquipmentEvent_FocuserMoveCompleted() when focuserMoveCompleted != null:
return focuserMoveCompleted(_that);case EquipmentEvent_FocuserTemperatureChanged() when focuserTemperatureChanged != null:
return focuserTemperatureChanged(_that);case EquipmentEvent_FilterChanging() when filterChanging != null:
return filterChanging(_that);case EquipmentEvent_FilterChanged() when filterChanged != null:
return filterChanged(_that);case EquipmentEvent_RotatorMoveStarted() when rotatorMoveStarted != null:
return rotatorMoveStarted(_that);case EquipmentEvent_RotatorMoveCompleted() when rotatorMoveCompleted != null:
return rotatorMoveCompleted(_that);case EquipmentEvent_CameraCoolingStarted() when cameraCoolingStarted != null:
return cameraCoolingStarted(_that);case EquipmentEvent_CameraCoolingReached() when cameraCoolingReached != null:
return cameraCoolingReached(_that);case EquipmentEvent_CameraWarmingStarted() when cameraWarmingStarted != null:
return cameraWarmingStarted(_that);case EquipmentEvent_CameraWarmingCompleted() when cameraWarmingCompleted != null:
return cameraWarmingCompleted(_that);case EquipmentEvent_HeartbeatStarted() when heartbeatStarted != null:
return heartbeatStarted(_that);case EquipmentEvent_HeartbeatStopped() when heartbeatStopped != null:
return heartbeatStopped(_that);case EquipmentEvent_HeartbeatStatusChanged() when heartbeatStatusChanged != null:
return heartbeatStatusChanged(_that);case EquipmentEvent_HeartbeatReconnecting() when heartbeatReconnecting != null:
return heartbeatReconnecting(_that);case EquipmentEvent_HeartbeatReconnected() when heartbeatReconnected != null:
return heartbeatReconnected(_that);case EquipmentEvent_DeviceDiscovered() when deviceDiscovered != null:
return deviceDiscovered(_that);case EquipmentEvent_DeviceLost() when deviceLost != null:
return deviceLost(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EquipmentEvent_Connecting value)  connecting,required TResult Function( EquipmentEvent_Connected value)  connected,required TResult Function( EquipmentEvent_Disconnected value)  disconnected,required TResult Function( EquipmentEvent_PropertyChanged value)  propertyChanged,required TResult Function( EquipmentEvent_Error value)  error,required TResult Function( EquipmentEvent_MountSlewStarted value)  mountSlewStarted,required TResult Function( EquipmentEvent_MountSlewCompleted value)  mountSlewCompleted,required TResult Function( EquipmentEvent_MountTrackingStarted value)  mountTrackingStarted,required TResult Function( EquipmentEvent_MountTrackingStopped value)  mountTrackingStopped,required TResult Function( EquipmentEvent_MountParkStarted value)  mountParkStarted,required TResult Function( EquipmentEvent_MountParkCompleted value)  mountParkCompleted,required TResult Function( EquipmentEvent_MountUnparked value)  mountUnparked,required TResult Function( EquipmentEvent_FocuserMoveStarted value)  focuserMoveStarted,required TResult Function( EquipmentEvent_FocuserMoveCompleted value)  focuserMoveCompleted,required TResult Function( EquipmentEvent_FocuserTemperatureChanged value)  focuserTemperatureChanged,required TResult Function( EquipmentEvent_FilterChanging value)  filterChanging,required TResult Function( EquipmentEvent_FilterChanged value)  filterChanged,required TResult Function( EquipmentEvent_RotatorMoveStarted value)  rotatorMoveStarted,required TResult Function( EquipmentEvent_RotatorMoveCompleted value)  rotatorMoveCompleted,required TResult Function( EquipmentEvent_CameraCoolingStarted value)  cameraCoolingStarted,required TResult Function( EquipmentEvent_CameraCoolingReached value)  cameraCoolingReached,required TResult Function( EquipmentEvent_CameraWarmingStarted value)  cameraWarmingStarted,required TResult Function( EquipmentEvent_CameraWarmingCompleted value)  cameraWarmingCompleted,required TResult Function( EquipmentEvent_HeartbeatStarted value)  heartbeatStarted,required TResult Function( EquipmentEvent_HeartbeatStopped value)  heartbeatStopped,required TResult Function( EquipmentEvent_HeartbeatStatusChanged value)  heartbeatStatusChanged,required TResult Function( EquipmentEvent_HeartbeatReconnecting value)  heartbeatReconnecting,required TResult Function( EquipmentEvent_HeartbeatReconnected value)  heartbeatReconnected,required TResult Function( EquipmentEvent_DeviceDiscovered value)  deviceDiscovered,required TResult Function( EquipmentEvent_DeviceLost value)  deviceLost,}){
final _that = this;
switch (_that) {
case EquipmentEvent_Connecting():
return connecting(_that);case EquipmentEvent_Connected():
return connected(_that);case EquipmentEvent_Disconnected():
return disconnected(_that);case EquipmentEvent_PropertyChanged():
return propertyChanged(_that);case EquipmentEvent_Error():
return error(_that);case EquipmentEvent_MountSlewStarted():
return mountSlewStarted(_that);case EquipmentEvent_MountSlewCompleted():
return mountSlewCompleted(_that);case EquipmentEvent_MountTrackingStarted():
return mountTrackingStarted(_that);case EquipmentEvent_MountTrackingStopped():
return mountTrackingStopped(_that);case EquipmentEvent_MountParkStarted():
return mountParkStarted(_that);case EquipmentEvent_MountParkCompleted():
return mountParkCompleted(_that);case EquipmentEvent_MountUnparked():
return mountUnparked(_that);case EquipmentEvent_FocuserMoveStarted():
return focuserMoveStarted(_that);case EquipmentEvent_FocuserMoveCompleted():
return focuserMoveCompleted(_that);case EquipmentEvent_FocuserTemperatureChanged():
return focuserTemperatureChanged(_that);case EquipmentEvent_FilterChanging():
return filterChanging(_that);case EquipmentEvent_FilterChanged():
return filterChanged(_that);case EquipmentEvent_RotatorMoveStarted():
return rotatorMoveStarted(_that);case EquipmentEvent_RotatorMoveCompleted():
return rotatorMoveCompleted(_that);case EquipmentEvent_CameraCoolingStarted():
return cameraCoolingStarted(_that);case EquipmentEvent_CameraCoolingReached():
return cameraCoolingReached(_that);case EquipmentEvent_CameraWarmingStarted():
return cameraWarmingStarted(_that);case EquipmentEvent_CameraWarmingCompleted():
return cameraWarmingCompleted(_that);case EquipmentEvent_HeartbeatStarted():
return heartbeatStarted(_that);case EquipmentEvent_HeartbeatStopped():
return heartbeatStopped(_that);case EquipmentEvent_HeartbeatStatusChanged():
return heartbeatStatusChanged(_that);case EquipmentEvent_HeartbeatReconnecting():
return heartbeatReconnecting(_that);case EquipmentEvent_HeartbeatReconnected():
return heartbeatReconnected(_that);case EquipmentEvent_DeviceDiscovered():
return deviceDiscovered(_that);case EquipmentEvent_DeviceLost():
return deviceLost(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EquipmentEvent_Connecting value)?  connecting,TResult? Function( EquipmentEvent_Connected value)?  connected,TResult? Function( EquipmentEvent_Disconnected value)?  disconnected,TResult? Function( EquipmentEvent_PropertyChanged value)?  propertyChanged,TResult? Function( EquipmentEvent_Error value)?  error,TResult? Function( EquipmentEvent_MountSlewStarted value)?  mountSlewStarted,TResult? Function( EquipmentEvent_MountSlewCompleted value)?  mountSlewCompleted,TResult? Function( EquipmentEvent_MountTrackingStarted value)?  mountTrackingStarted,TResult? Function( EquipmentEvent_MountTrackingStopped value)?  mountTrackingStopped,TResult? Function( EquipmentEvent_MountParkStarted value)?  mountParkStarted,TResult? Function( EquipmentEvent_MountParkCompleted value)?  mountParkCompleted,TResult? Function( EquipmentEvent_MountUnparked value)?  mountUnparked,TResult? Function( EquipmentEvent_FocuserMoveStarted value)?  focuserMoveStarted,TResult? Function( EquipmentEvent_FocuserMoveCompleted value)?  focuserMoveCompleted,TResult? Function( EquipmentEvent_FocuserTemperatureChanged value)?  focuserTemperatureChanged,TResult? Function( EquipmentEvent_FilterChanging value)?  filterChanging,TResult? Function( EquipmentEvent_FilterChanged value)?  filterChanged,TResult? Function( EquipmentEvent_RotatorMoveStarted value)?  rotatorMoveStarted,TResult? Function( EquipmentEvent_RotatorMoveCompleted value)?  rotatorMoveCompleted,TResult? Function( EquipmentEvent_CameraCoolingStarted value)?  cameraCoolingStarted,TResult? Function( EquipmentEvent_CameraCoolingReached value)?  cameraCoolingReached,TResult? Function( EquipmentEvent_CameraWarmingStarted value)?  cameraWarmingStarted,TResult? Function( EquipmentEvent_CameraWarmingCompleted value)?  cameraWarmingCompleted,TResult? Function( EquipmentEvent_HeartbeatStarted value)?  heartbeatStarted,TResult? Function( EquipmentEvent_HeartbeatStopped value)?  heartbeatStopped,TResult? Function( EquipmentEvent_HeartbeatStatusChanged value)?  heartbeatStatusChanged,TResult? Function( EquipmentEvent_HeartbeatReconnecting value)?  heartbeatReconnecting,TResult? Function( EquipmentEvent_HeartbeatReconnected value)?  heartbeatReconnected,TResult? Function( EquipmentEvent_DeviceDiscovered value)?  deviceDiscovered,TResult? Function( EquipmentEvent_DeviceLost value)?  deviceLost,}){
final _that = this;
switch (_that) {
case EquipmentEvent_Connecting() when connecting != null:
return connecting(_that);case EquipmentEvent_Connected() when connected != null:
return connected(_that);case EquipmentEvent_Disconnected() when disconnected != null:
return disconnected(_that);case EquipmentEvent_PropertyChanged() when propertyChanged != null:
return propertyChanged(_that);case EquipmentEvent_Error() when error != null:
return error(_that);case EquipmentEvent_MountSlewStarted() when mountSlewStarted != null:
return mountSlewStarted(_that);case EquipmentEvent_MountSlewCompleted() when mountSlewCompleted != null:
return mountSlewCompleted(_that);case EquipmentEvent_MountTrackingStarted() when mountTrackingStarted != null:
return mountTrackingStarted(_that);case EquipmentEvent_MountTrackingStopped() when mountTrackingStopped != null:
return mountTrackingStopped(_that);case EquipmentEvent_MountParkStarted() when mountParkStarted != null:
return mountParkStarted(_that);case EquipmentEvent_MountParkCompleted() when mountParkCompleted != null:
return mountParkCompleted(_that);case EquipmentEvent_MountUnparked() when mountUnparked != null:
return mountUnparked(_that);case EquipmentEvent_FocuserMoveStarted() when focuserMoveStarted != null:
return focuserMoveStarted(_that);case EquipmentEvent_FocuserMoveCompleted() when focuserMoveCompleted != null:
return focuserMoveCompleted(_that);case EquipmentEvent_FocuserTemperatureChanged() when focuserTemperatureChanged != null:
return focuserTemperatureChanged(_that);case EquipmentEvent_FilterChanging() when filterChanging != null:
return filterChanging(_that);case EquipmentEvent_FilterChanged() when filterChanged != null:
return filterChanged(_that);case EquipmentEvent_RotatorMoveStarted() when rotatorMoveStarted != null:
return rotatorMoveStarted(_that);case EquipmentEvent_RotatorMoveCompleted() when rotatorMoveCompleted != null:
return rotatorMoveCompleted(_that);case EquipmentEvent_CameraCoolingStarted() when cameraCoolingStarted != null:
return cameraCoolingStarted(_that);case EquipmentEvent_CameraCoolingReached() when cameraCoolingReached != null:
return cameraCoolingReached(_that);case EquipmentEvent_CameraWarmingStarted() when cameraWarmingStarted != null:
return cameraWarmingStarted(_that);case EquipmentEvent_CameraWarmingCompleted() when cameraWarmingCompleted != null:
return cameraWarmingCompleted(_that);case EquipmentEvent_HeartbeatStarted() when heartbeatStarted != null:
return heartbeatStarted(_that);case EquipmentEvent_HeartbeatStopped() when heartbeatStopped != null:
return heartbeatStopped(_that);case EquipmentEvent_HeartbeatStatusChanged() when heartbeatStatusChanged != null:
return heartbeatStatusChanged(_that);case EquipmentEvent_HeartbeatReconnecting() when heartbeatReconnecting != null:
return heartbeatReconnecting(_that);case EquipmentEvent_HeartbeatReconnected() when heartbeatReconnected != null:
return heartbeatReconnected(_that);case EquipmentEvent_DeviceDiscovered() when deviceDiscovered != null:
return deviceDiscovered(_that);case EquipmentEvent_DeviceLost() when deviceLost != null:
return deviceLost(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String deviceType,  String deviceId)?  connecting,TResult Function( String deviceType,  String deviceId)?  connected,TResult Function( String deviceType,  String deviceId)?  disconnected,TResult Function( String deviceType,  String deviceId,  String property,  String value)?  propertyChanged,TResult Function( String deviceType,  String deviceId,  String message)?  error,TResult Function( double ra,  double dec)?  mountSlewStarted,TResult Function( double ra,  double dec)?  mountSlewCompleted,TResult Function()?  mountTrackingStarted,TResult Function()?  mountTrackingStopped,TResult Function()?  mountParkStarted,TResult Function()?  mountParkCompleted,TResult Function()?  mountUnparked,TResult Function( int targetPosition)?  focuserMoveStarted,TResult Function( int position)?  focuserMoveCompleted,TResult Function( double temperature)?  focuserTemperatureChanged,TResult Function( int fromPosition,  int toPosition,  String? filterName)?  filterChanging,TResult Function( int position,  String? filterName)?  filterChanged,TResult Function( double targetAngle)?  rotatorMoveStarted,TResult Function( double angle)?  rotatorMoveCompleted,TResult Function( double targetTemp)?  cameraCoolingStarted,TResult Function( double temperature)?  cameraCoolingReached,TResult Function()?  cameraWarmingStarted,TResult Function()?  cameraWarmingCompleted,TResult Function( String deviceType,  String deviceId,  BigInt intervalSecs)?  heartbeatStarted,TResult Function( String deviceType,  String deviceId)?  heartbeatStopped,TResult Function( String deviceType,  String deviceId,  HeartbeatStatus status,  int consecutiveFailures,  BigInt? lastRttMs)?  heartbeatStatusChanged,TResult Function( String deviceType,  String deviceId,  int attempt,  int maxAttempts)?  heartbeatReconnecting,TResult Function( String deviceType,  String deviceId,  int afterAttempts)?  heartbeatReconnected,TResult Function( String deviceClass,  String driver,  String id,  String name,  String displayName,  String? uniqueId)?  deviceDiscovered,TResult Function( String deviceClass,  String driver,  String id)?  deviceLost,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EquipmentEvent_Connecting() when connecting != null:
return connecting(_that.deviceType,_that.deviceId);case EquipmentEvent_Connected() when connected != null:
return connected(_that.deviceType,_that.deviceId);case EquipmentEvent_Disconnected() when disconnected != null:
return disconnected(_that.deviceType,_that.deviceId);case EquipmentEvent_PropertyChanged() when propertyChanged != null:
return propertyChanged(_that.deviceType,_that.deviceId,_that.property,_that.value);case EquipmentEvent_Error() when error != null:
return error(_that.deviceType,_that.deviceId,_that.message);case EquipmentEvent_MountSlewStarted() when mountSlewStarted != null:
return mountSlewStarted(_that.ra,_that.dec);case EquipmentEvent_MountSlewCompleted() when mountSlewCompleted != null:
return mountSlewCompleted(_that.ra,_that.dec);case EquipmentEvent_MountTrackingStarted() when mountTrackingStarted != null:
return mountTrackingStarted();case EquipmentEvent_MountTrackingStopped() when mountTrackingStopped != null:
return mountTrackingStopped();case EquipmentEvent_MountParkStarted() when mountParkStarted != null:
return mountParkStarted();case EquipmentEvent_MountParkCompleted() when mountParkCompleted != null:
return mountParkCompleted();case EquipmentEvent_MountUnparked() when mountUnparked != null:
return mountUnparked();case EquipmentEvent_FocuserMoveStarted() when focuserMoveStarted != null:
return focuserMoveStarted(_that.targetPosition);case EquipmentEvent_FocuserMoveCompleted() when focuserMoveCompleted != null:
return focuserMoveCompleted(_that.position);case EquipmentEvent_FocuserTemperatureChanged() when focuserTemperatureChanged != null:
return focuserTemperatureChanged(_that.temperature);case EquipmentEvent_FilterChanging() when filterChanging != null:
return filterChanging(_that.fromPosition,_that.toPosition,_that.filterName);case EquipmentEvent_FilterChanged() when filterChanged != null:
return filterChanged(_that.position,_that.filterName);case EquipmentEvent_RotatorMoveStarted() when rotatorMoveStarted != null:
return rotatorMoveStarted(_that.targetAngle);case EquipmentEvent_RotatorMoveCompleted() when rotatorMoveCompleted != null:
return rotatorMoveCompleted(_that.angle);case EquipmentEvent_CameraCoolingStarted() when cameraCoolingStarted != null:
return cameraCoolingStarted(_that.targetTemp);case EquipmentEvent_CameraCoolingReached() when cameraCoolingReached != null:
return cameraCoolingReached(_that.temperature);case EquipmentEvent_CameraWarmingStarted() when cameraWarmingStarted != null:
return cameraWarmingStarted();case EquipmentEvent_CameraWarmingCompleted() when cameraWarmingCompleted != null:
return cameraWarmingCompleted();case EquipmentEvent_HeartbeatStarted() when heartbeatStarted != null:
return heartbeatStarted(_that.deviceType,_that.deviceId,_that.intervalSecs);case EquipmentEvent_HeartbeatStopped() when heartbeatStopped != null:
return heartbeatStopped(_that.deviceType,_that.deviceId);case EquipmentEvent_HeartbeatStatusChanged() when heartbeatStatusChanged != null:
return heartbeatStatusChanged(_that.deviceType,_that.deviceId,_that.status,_that.consecutiveFailures,_that.lastRttMs);case EquipmentEvent_HeartbeatReconnecting() when heartbeatReconnecting != null:
return heartbeatReconnecting(_that.deviceType,_that.deviceId,_that.attempt,_that.maxAttempts);case EquipmentEvent_HeartbeatReconnected() when heartbeatReconnected != null:
return heartbeatReconnected(_that.deviceType,_that.deviceId,_that.afterAttempts);case EquipmentEvent_DeviceDiscovered() when deviceDiscovered != null:
return deviceDiscovered(_that.deviceClass,_that.driver,_that.id,_that.name,_that.displayName,_that.uniqueId);case EquipmentEvent_DeviceLost() when deviceLost != null:
return deviceLost(_that.deviceClass,_that.driver,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String deviceType,  String deviceId)  connecting,required TResult Function( String deviceType,  String deviceId)  connected,required TResult Function( String deviceType,  String deviceId)  disconnected,required TResult Function( String deviceType,  String deviceId,  String property,  String value)  propertyChanged,required TResult Function( String deviceType,  String deviceId,  String message)  error,required TResult Function( double ra,  double dec)  mountSlewStarted,required TResult Function( double ra,  double dec)  mountSlewCompleted,required TResult Function()  mountTrackingStarted,required TResult Function()  mountTrackingStopped,required TResult Function()  mountParkStarted,required TResult Function()  mountParkCompleted,required TResult Function()  mountUnparked,required TResult Function( int targetPosition)  focuserMoveStarted,required TResult Function( int position)  focuserMoveCompleted,required TResult Function( double temperature)  focuserTemperatureChanged,required TResult Function( int fromPosition,  int toPosition,  String? filterName)  filterChanging,required TResult Function( int position,  String? filterName)  filterChanged,required TResult Function( double targetAngle)  rotatorMoveStarted,required TResult Function( double angle)  rotatorMoveCompleted,required TResult Function( double targetTemp)  cameraCoolingStarted,required TResult Function( double temperature)  cameraCoolingReached,required TResult Function()  cameraWarmingStarted,required TResult Function()  cameraWarmingCompleted,required TResult Function( String deviceType,  String deviceId,  BigInt intervalSecs)  heartbeatStarted,required TResult Function( String deviceType,  String deviceId)  heartbeatStopped,required TResult Function( String deviceType,  String deviceId,  HeartbeatStatus status,  int consecutiveFailures,  BigInt? lastRttMs)  heartbeatStatusChanged,required TResult Function( String deviceType,  String deviceId,  int attempt,  int maxAttempts)  heartbeatReconnecting,required TResult Function( String deviceType,  String deviceId,  int afterAttempts)  heartbeatReconnected,required TResult Function( String deviceClass,  String driver,  String id,  String name,  String displayName,  String? uniqueId)  deviceDiscovered,required TResult Function( String deviceClass,  String driver,  String id)  deviceLost,}) {final _that = this;
switch (_that) {
case EquipmentEvent_Connecting():
return connecting(_that.deviceType,_that.deviceId);case EquipmentEvent_Connected():
return connected(_that.deviceType,_that.deviceId);case EquipmentEvent_Disconnected():
return disconnected(_that.deviceType,_that.deviceId);case EquipmentEvent_PropertyChanged():
return propertyChanged(_that.deviceType,_that.deviceId,_that.property,_that.value);case EquipmentEvent_Error():
return error(_that.deviceType,_that.deviceId,_that.message);case EquipmentEvent_MountSlewStarted():
return mountSlewStarted(_that.ra,_that.dec);case EquipmentEvent_MountSlewCompleted():
return mountSlewCompleted(_that.ra,_that.dec);case EquipmentEvent_MountTrackingStarted():
return mountTrackingStarted();case EquipmentEvent_MountTrackingStopped():
return mountTrackingStopped();case EquipmentEvent_MountParkStarted():
return mountParkStarted();case EquipmentEvent_MountParkCompleted():
return mountParkCompleted();case EquipmentEvent_MountUnparked():
return mountUnparked();case EquipmentEvent_FocuserMoveStarted():
return focuserMoveStarted(_that.targetPosition);case EquipmentEvent_FocuserMoveCompleted():
return focuserMoveCompleted(_that.position);case EquipmentEvent_FocuserTemperatureChanged():
return focuserTemperatureChanged(_that.temperature);case EquipmentEvent_FilterChanging():
return filterChanging(_that.fromPosition,_that.toPosition,_that.filterName);case EquipmentEvent_FilterChanged():
return filterChanged(_that.position,_that.filterName);case EquipmentEvent_RotatorMoveStarted():
return rotatorMoveStarted(_that.targetAngle);case EquipmentEvent_RotatorMoveCompleted():
return rotatorMoveCompleted(_that.angle);case EquipmentEvent_CameraCoolingStarted():
return cameraCoolingStarted(_that.targetTemp);case EquipmentEvent_CameraCoolingReached():
return cameraCoolingReached(_that.temperature);case EquipmentEvent_CameraWarmingStarted():
return cameraWarmingStarted();case EquipmentEvent_CameraWarmingCompleted():
return cameraWarmingCompleted();case EquipmentEvent_HeartbeatStarted():
return heartbeatStarted(_that.deviceType,_that.deviceId,_that.intervalSecs);case EquipmentEvent_HeartbeatStopped():
return heartbeatStopped(_that.deviceType,_that.deviceId);case EquipmentEvent_HeartbeatStatusChanged():
return heartbeatStatusChanged(_that.deviceType,_that.deviceId,_that.status,_that.consecutiveFailures,_that.lastRttMs);case EquipmentEvent_HeartbeatReconnecting():
return heartbeatReconnecting(_that.deviceType,_that.deviceId,_that.attempt,_that.maxAttempts);case EquipmentEvent_HeartbeatReconnected():
return heartbeatReconnected(_that.deviceType,_that.deviceId,_that.afterAttempts);case EquipmentEvent_DeviceDiscovered():
return deviceDiscovered(_that.deviceClass,_that.driver,_that.id,_that.name,_that.displayName,_that.uniqueId);case EquipmentEvent_DeviceLost():
return deviceLost(_that.deviceClass,_that.driver,_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String deviceType,  String deviceId)?  connecting,TResult? Function( String deviceType,  String deviceId)?  connected,TResult? Function( String deviceType,  String deviceId)?  disconnected,TResult? Function( String deviceType,  String deviceId,  String property,  String value)?  propertyChanged,TResult? Function( String deviceType,  String deviceId,  String message)?  error,TResult? Function( double ra,  double dec)?  mountSlewStarted,TResult? Function( double ra,  double dec)?  mountSlewCompleted,TResult? Function()?  mountTrackingStarted,TResult? Function()?  mountTrackingStopped,TResult? Function()?  mountParkStarted,TResult? Function()?  mountParkCompleted,TResult? Function()?  mountUnparked,TResult? Function( int targetPosition)?  focuserMoveStarted,TResult? Function( int position)?  focuserMoveCompleted,TResult? Function( double temperature)?  focuserTemperatureChanged,TResult? Function( int fromPosition,  int toPosition,  String? filterName)?  filterChanging,TResult? Function( int position,  String? filterName)?  filterChanged,TResult? Function( double targetAngle)?  rotatorMoveStarted,TResult? Function( double angle)?  rotatorMoveCompleted,TResult? Function( double targetTemp)?  cameraCoolingStarted,TResult? Function( double temperature)?  cameraCoolingReached,TResult? Function()?  cameraWarmingStarted,TResult? Function()?  cameraWarmingCompleted,TResult? Function( String deviceType,  String deviceId,  BigInt intervalSecs)?  heartbeatStarted,TResult? Function( String deviceType,  String deviceId)?  heartbeatStopped,TResult? Function( String deviceType,  String deviceId,  HeartbeatStatus status,  int consecutiveFailures,  BigInt? lastRttMs)?  heartbeatStatusChanged,TResult? Function( String deviceType,  String deviceId,  int attempt,  int maxAttempts)?  heartbeatReconnecting,TResult? Function( String deviceType,  String deviceId,  int afterAttempts)?  heartbeatReconnected,TResult? Function( String deviceClass,  String driver,  String id,  String name,  String displayName,  String? uniqueId)?  deviceDiscovered,TResult? Function( String deviceClass,  String driver,  String id)?  deviceLost,}) {final _that = this;
switch (_that) {
case EquipmentEvent_Connecting() when connecting != null:
return connecting(_that.deviceType,_that.deviceId);case EquipmentEvent_Connected() when connected != null:
return connected(_that.deviceType,_that.deviceId);case EquipmentEvent_Disconnected() when disconnected != null:
return disconnected(_that.deviceType,_that.deviceId);case EquipmentEvent_PropertyChanged() when propertyChanged != null:
return propertyChanged(_that.deviceType,_that.deviceId,_that.property,_that.value);case EquipmentEvent_Error() when error != null:
return error(_that.deviceType,_that.deviceId,_that.message);case EquipmentEvent_MountSlewStarted() when mountSlewStarted != null:
return mountSlewStarted(_that.ra,_that.dec);case EquipmentEvent_MountSlewCompleted() when mountSlewCompleted != null:
return mountSlewCompleted(_that.ra,_that.dec);case EquipmentEvent_MountTrackingStarted() when mountTrackingStarted != null:
return mountTrackingStarted();case EquipmentEvent_MountTrackingStopped() when mountTrackingStopped != null:
return mountTrackingStopped();case EquipmentEvent_MountParkStarted() when mountParkStarted != null:
return mountParkStarted();case EquipmentEvent_MountParkCompleted() when mountParkCompleted != null:
return mountParkCompleted();case EquipmentEvent_MountUnparked() when mountUnparked != null:
return mountUnparked();case EquipmentEvent_FocuserMoveStarted() when focuserMoveStarted != null:
return focuserMoveStarted(_that.targetPosition);case EquipmentEvent_FocuserMoveCompleted() when focuserMoveCompleted != null:
return focuserMoveCompleted(_that.position);case EquipmentEvent_FocuserTemperatureChanged() when focuserTemperatureChanged != null:
return focuserTemperatureChanged(_that.temperature);case EquipmentEvent_FilterChanging() when filterChanging != null:
return filterChanging(_that.fromPosition,_that.toPosition,_that.filterName);case EquipmentEvent_FilterChanged() when filterChanged != null:
return filterChanged(_that.position,_that.filterName);case EquipmentEvent_RotatorMoveStarted() when rotatorMoveStarted != null:
return rotatorMoveStarted(_that.targetAngle);case EquipmentEvent_RotatorMoveCompleted() when rotatorMoveCompleted != null:
return rotatorMoveCompleted(_that.angle);case EquipmentEvent_CameraCoolingStarted() when cameraCoolingStarted != null:
return cameraCoolingStarted(_that.targetTemp);case EquipmentEvent_CameraCoolingReached() when cameraCoolingReached != null:
return cameraCoolingReached(_that.temperature);case EquipmentEvent_CameraWarmingStarted() when cameraWarmingStarted != null:
return cameraWarmingStarted();case EquipmentEvent_CameraWarmingCompleted() when cameraWarmingCompleted != null:
return cameraWarmingCompleted();case EquipmentEvent_HeartbeatStarted() when heartbeatStarted != null:
return heartbeatStarted(_that.deviceType,_that.deviceId,_that.intervalSecs);case EquipmentEvent_HeartbeatStopped() when heartbeatStopped != null:
return heartbeatStopped(_that.deviceType,_that.deviceId);case EquipmentEvent_HeartbeatStatusChanged() when heartbeatStatusChanged != null:
return heartbeatStatusChanged(_that.deviceType,_that.deviceId,_that.status,_that.consecutiveFailures,_that.lastRttMs);case EquipmentEvent_HeartbeatReconnecting() when heartbeatReconnecting != null:
return heartbeatReconnecting(_that.deviceType,_that.deviceId,_that.attempt,_that.maxAttempts);case EquipmentEvent_HeartbeatReconnected() when heartbeatReconnected != null:
return heartbeatReconnected(_that.deviceType,_that.deviceId,_that.afterAttempts);case EquipmentEvent_DeviceDiscovered() when deviceDiscovered != null:
return deviceDiscovered(_that.deviceClass,_that.driver,_that.id,_that.name,_that.displayName,_that.uniqueId);case EquipmentEvent_DeviceLost() when deviceLost != null:
return deviceLost(_that.deviceClass,_that.driver,_that.id);case _:
  return null;

}
}

}

/// @nodoc


class EquipmentEvent_Connecting extends EquipmentEvent {
  const EquipmentEvent_Connecting({required this.deviceType, required this.deviceId}): super._();
  

 final  String deviceType;
 final  String deviceId;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_ConnectingCopyWith<EquipmentEvent_Connecting> get copyWith => _$EquipmentEvent_ConnectingCopyWithImpl<EquipmentEvent_Connecting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_Connecting&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId);

@override
String toString() {
  return 'EquipmentEvent.connecting(deviceType: $deviceType, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_ConnectingCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_ConnectingCopyWith(EquipmentEvent_Connecting value, $Res Function(EquipmentEvent_Connecting) _then) = _$EquipmentEvent_ConnectingCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId
});




}
/// @nodoc
class _$EquipmentEvent_ConnectingCopyWithImpl<$Res>
    implements $EquipmentEvent_ConnectingCopyWith<$Res> {
  _$EquipmentEvent_ConnectingCopyWithImpl(this._self, this._then);

  final EquipmentEvent_Connecting _self;
  final $Res Function(EquipmentEvent_Connecting) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,}) {
  return _then(EquipmentEvent_Connecting(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_Connected extends EquipmentEvent {
  const EquipmentEvent_Connected({required this.deviceType, required this.deviceId}): super._();
  

 final  String deviceType;
 final  String deviceId;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_ConnectedCopyWith<EquipmentEvent_Connected> get copyWith => _$EquipmentEvent_ConnectedCopyWithImpl<EquipmentEvent_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_Connected&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId);

@override
String toString() {
  return 'EquipmentEvent.connected(deviceType: $deviceType, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_ConnectedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_ConnectedCopyWith(EquipmentEvent_Connected value, $Res Function(EquipmentEvent_Connected) _then) = _$EquipmentEvent_ConnectedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId
});




}
/// @nodoc
class _$EquipmentEvent_ConnectedCopyWithImpl<$Res>
    implements $EquipmentEvent_ConnectedCopyWith<$Res> {
  _$EquipmentEvent_ConnectedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_Connected _self;
  final $Res Function(EquipmentEvent_Connected) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,}) {
  return _then(EquipmentEvent_Connected(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_Disconnected extends EquipmentEvent {
  const EquipmentEvent_Disconnected({required this.deviceType, required this.deviceId}): super._();
  

 final  String deviceType;
 final  String deviceId;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_DisconnectedCopyWith<EquipmentEvent_Disconnected> get copyWith => _$EquipmentEvent_DisconnectedCopyWithImpl<EquipmentEvent_Disconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_Disconnected&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId);

@override
String toString() {
  return 'EquipmentEvent.disconnected(deviceType: $deviceType, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_DisconnectedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_DisconnectedCopyWith(EquipmentEvent_Disconnected value, $Res Function(EquipmentEvent_Disconnected) _then) = _$EquipmentEvent_DisconnectedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId
});




}
/// @nodoc
class _$EquipmentEvent_DisconnectedCopyWithImpl<$Res>
    implements $EquipmentEvent_DisconnectedCopyWith<$Res> {
  _$EquipmentEvent_DisconnectedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_Disconnected _self;
  final $Res Function(EquipmentEvent_Disconnected) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,}) {
  return _then(EquipmentEvent_Disconnected(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_PropertyChanged extends EquipmentEvent {
  const EquipmentEvent_PropertyChanged({required this.deviceType, required this.deviceId, required this.property, required this.value}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  String property;
 final  String value;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_PropertyChangedCopyWith<EquipmentEvent_PropertyChanged> get copyWith => _$EquipmentEvent_PropertyChangedCopyWithImpl<EquipmentEvent_PropertyChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_PropertyChanged&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.property, property) || other.property == property)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,property,value);

@override
String toString() {
  return 'EquipmentEvent.propertyChanged(deviceType: $deviceType, deviceId: $deviceId, property: $property, value: $value)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_PropertyChangedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_PropertyChangedCopyWith(EquipmentEvent_PropertyChanged value, $Res Function(EquipmentEvent_PropertyChanged) _then) = _$EquipmentEvent_PropertyChangedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, String property, String value
});




}
/// @nodoc
class _$EquipmentEvent_PropertyChangedCopyWithImpl<$Res>
    implements $EquipmentEvent_PropertyChangedCopyWith<$Res> {
  _$EquipmentEvent_PropertyChangedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_PropertyChanged _self;
  final $Res Function(EquipmentEvent_PropertyChanged) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? property = null,Object? value = null,}) {
  return _then(EquipmentEvent_PropertyChanged(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,property: null == property ? _self.property : property // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_Error extends EquipmentEvent {
  const EquipmentEvent_Error({required this.deviceType, required this.deviceId, required this.message}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  String message;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_ErrorCopyWith<EquipmentEvent_Error> get copyWith => _$EquipmentEvent_ErrorCopyWithImpl<EquipmentEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_Error&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,message);

@override
String toString() {
  return 'EquipmentEvent.error(deviceType: $deviceType, deviceId: $deviceId, message: $message)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_ErrorCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_ErrorCopyWith(EquipmentEvent_Error value, $Res Function(EquipmentEvent_Error) _then) = _$EquipmentEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, String message
});




}
/// @nodoc
class _$EquipmentEvent_ErrorCopyWithImpl<$Res>
    implements $EquipmentEvent_ErrorCopyWith<$Res> {
  _$EquipmentEvent_ErrorCopyWithImpl(this._self, this._then);

  final EquipmentEvent_Error _self;
  final $Res Function(EquipmentEvent_Error) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? message = null,}) {
  return _then(EquipmentEvent_Error(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_MountSlewStarted extends EquipmentEvent {
  const EquipmentEvent_MountSlewStarted({required this.ra, required this.dec}): super._();
  

 final  double ra;
 final  double dec;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_MountSlewStartedCopyWith<EquipmentEvent_MountSlewStarted> get copyWith => _$EquipmentEvent_MountSlewStartedCopyWithImpl<EquipmentEvent_MountSlewStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountSlewStarted&&(identical(other.ra, ra) || other.ra == ra)&&(identical(other.dec, dec) || other.dec == dec));
}


@override
int get hashCode => Object.hash(runtimeType,ra,dec);

@override
String toString() {
  return 'EquipmentEvent.mountSlewStarted(ra: $ra, dec: $dec)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_MountSlewStartedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_MountSlewStartedCopyWith(EquipmentEvent_MountSlewStarted value, $Res Function(EquipmentEvent_MountSlewStarted) _then) = _$EquipmentEvent_MountSlewStartedCopyWithImpl;
@useResult
$Res call({
 double ra, double dec
});




}
/// @nodoc
class _$EquipmentEvent_MountSlewStartedCopyWithImpl<$Res>
    implements $EquipmentEvent_MountSlewStartedCopyWith<$Res> {
  _$EquipmentEvent_MountSlewStartedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_MountSlewStarted _self;
  final $Res Function(EquipmentEvent_MountSlewStarted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ra = null,Object? dec = null,}) {
  return _then(EquipmentEvent_MountSlewStarted(
ra: null == ra ? _self.ra : ra // ignore: cast_nullable_to_non_nullable
as double,dec: null == dec ? _self.dec : dec // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_MountSlewCompleted extends EquipmentEvent {
  const EquipmentEvent_MountSlewCompleted({required this.ra, required this.dec}): super._();
  

 final  double ra;
 final  double dec;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_MountSlewCompletedCopyWith<EquipmentEvent_MountSlewCompleted> get copyWith => _$EquipmentEvent_MountSlewCompletedCopyWithImpl<EquipmentEvent_MountSlewCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountSlewCompleted&&(identical(other.ra, ra) || other.ra == ra)&&(identical(other.dec, dec) || other.dec == dec));
}


@override
int get hashCode => Object.hash(runtimeType,ra,dec);

@override
String toString() {
  return 'EquipmentEvent.mountSlewCompleted(ra: $ra, dec: $dec)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_MountSlewCompletedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_MountSlewCompletedCopyWith(EquipmentEvent_MountSlewCompleted value, $Res Function(EquipmentEvent_MountSlewCompleted) _then) = _$EquipmentEvent_MountSlewCompletedCopyWithImpl;
@useResult
$Res call({
 double ra, double dec
});




}
/// @nodoc
class _$EquipmentEvent_MountSlewCompletedCopyWithImpl<$Res>
    implements $EquipmentEvent_MountSlewCompletedCopyWith<$Res> {
  _$EquipmentEvent_MountSlewCompletedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_MountSlewCompleted _self;
  final $Res Function(EquipmentEvent_MountSlewCompleted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ra = null,Object? dec = null,}) {
  return _then(EquipmentEvent_MountSlewCompleted(
ra: null == ra ? _self.ra : ra // ignore: cast_nullable_to_non_nullable
as double,dec: null == dec ? _self.dec : dec // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_MountTrackingStarted extends EquipmentEvent {
  const EquipmentEvent_MountTrackingStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountTrackingStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.mountTrackingStarted()';
}


}




/// @nodoc


class EquipmentEvent_MountTrackingStopped extends EquipmentEvent {
  const EquipmentEvent_MountTrackingStopped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountTrackingStopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.mountTrackingStopped()';
}


}




/// @nodoc


class EquipmentEvent_MountParkStarted extends EquipmentEvent {
  const EquipmentEvent_MountParkStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountParkStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.mountParkStarted()';
}


}




/// @nodoc


class EquipmentEvent_MountParkCompleted extends EquipmentEvent {
  const EquipmentEvent_MountParkCompleted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountParkCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.mountParkCompleted()';
}


}




/// @nodoc


class EquipmentEvent_MountUnparked extends EquipmentEvent {
  const EquipmentEvent_MountUnparked(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_MountUnparked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.mountUnparked()';
}


}




/// @nodoc


class EquipmentEvent_FocuserMoveStarted extends EquipmentEvent {
  const EquipmentEvent_FocuserMoveStarted({required this.targetPosition}): super._();
  

 final  int targetPosition;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_FocuserMoveStartedCopyWith<EquipmentEvent_FocuserMoveStarted> get copyWith => _$EquipmentEvent_FocuserMoveStartedCopyWithImpl<EquipmentEvent_FocuserMoveStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_FocuserMoveStarted&&(identical(other.targetPosition, targetPosition) || other.targetPosition == targetPosition));
}


@override
int get hashCode => Object.hash(runtimeType,targetPosition);

@override
String toString() {
  return 'EquipmentEvent.focuserMoveStarted(targetPosition: $targetPosition)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_FocuserMoveStartedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_FocuserMoveStartedCopyWith(EquipmentEvent_FocuserMoveStarted value, $Res Function(EquipmentEvent_FocuserMoveStarted) _then) = _$EquipmentEvent_FocuserMoveStartedCopyWithImpl;
@useResult
$Res call({
 int targetPosition
});




}
/// @nodoc
class _$EquipmentEvent_FocuserMoveStartedCopyWithImpl<$Res>
    implements $EquipmentEvent_FocuserMoveStartedCopyWith<$Res> {
  _$EquipmentEvent_FocuserMoveStartedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_FocuserMoveStarted _self;
  final $Res Function(EquipmentEvent_FocuserMoveStarted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetPosition = null,}) {
  return _then(EquipmentEvent_FocuserMoveStarted(
targetPosition: null == targetPosition ? _self.targetPosition : targetPosition // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EquipmentEvent_FocuserMoveCompleted extends EquipmentEvent {
  const EquipmentEvent_FocuserMoveCompleted({required this.position}): super._();
  

 final  int position;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_FocuserMoveCompletedCopyWith<EquipmentEvent_FocuserMoveCompleted> get copyWith => _$EquipmentEvent_FocuserMoveCompletedCopyWithImpl<EquipmentEvent_FocuserMoveCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_FocuserMoveCompleted&&(identical(other.position, position) || other.position == position));
}


@override
int get hashCode => Object.hash(runtimeType,position);

@override
String toString() {
  return 'EquipmentEvent.focuserMoveCompleted(position: $position)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_FocuserMoveCompletedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_FocuserMoveCompletedCopyWith(EquipmentEvent_FocuserMoveCompleted value, $Res Function(EquipmentEvent_FocuserMoveCompleted) _then) = _$EquipmentEvent_FocuserMoveCompletedCopyWithImpl;
@useResult
$Res call({
 int position
});




}
/// @nodoc
class _$EquipmentEvent_FocuserMoveCompletedCopyWithImpl<$Res>
    implements $EquipmentEvent_FocuserMoveCompletedCopyWith<$Res> {
  _$EquipmentEvent_FocuserMoveCompletedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_FocuserMoveCompleted _self;
  final $Res Function(EquipmentEvent_FocuserMoveCompleted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? position = null,}) {
  return _then(EquipmentEvent_FocuserMoveCompleted(
position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EquipmentEvent_FocuserTemperatureChanged extends EquipmentEvent {
  const EquipmentEvent_FocuserTemperatureChanged({required this.temperature}): super._();
  

 final  double temperature;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_FocuserTemperatureChangedCopyWith<EquipmentEvent_FocuserTemperatureChanged> get copyWith => _$EquipmentEvent_FocuserTemperatureChangedCopyWithImpl<EquipmentEvent_FocuserTemperatureChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_FocuserTemperatureChanged&&(identical(other.temperature, temperature) || other.temperature == temperature));
}


@override
int get hashCode => Object.hash(runtimeType,temperature);

@override
String toString() {
  return 'EquipmentEvent.focuserTemperatureChanged(temperature: $temperature)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_FocuserTemperatureChangedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_FocuserTemperatureChangedCopyWith(EquipmentEvent_FocuserTemperatureChanged value, $Res Function(EquipmentEvent_FocuserTemperatureChanged) _then) = _$EquipmentEvent_FocuserTemperatureChangedCopyWithImpl;
@useResult
$Res call({
 double temperature
});




}
/// @nodoc
class _$EquipmentEvent_FocuserTemperatureChangedCopyWithImpl<$Res>
    implements $EquipmentEvent_FocuserTemperatureChangedCopyWith<$Res> {
  _$EquipmentEvent_FocuserTemperatureChangedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_FocuserTemperatureChanged _self;
  final $Res Function(EquipmentEvent_FocuserTemperatureChanged) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? temperature = null,}) {
  return _then(EquipmentEvent_FocuserTemperatureChanged(
temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_FilterChanging extends EquipmentEvent {
  const EquipmentEvent_FilterChanging({required this.fromPosition, required this.toPosition, this.filterName}): super._();
  

 final  int fromPosition;
 final  int toPosition;
 final  String? filterName;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_FilterChangingCopyWith<EquipmentEvent_FilterChanging> get copyWith => _$EquipmentEvent_FilterChangingCopyWithImpl<EquipmentEvent_FilterChanging>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_FilterChanging&&(identical(other.fromPosition, fromPosition) || other.fromPosition == fromPosition)&&(identical(other.toPosition, toPosition) || other.toPosition == toPosition)&&(identical(other.filterName, filterName) || other.filterName == filterName));
}


@override
int get hashCode => Object.hash(runtimeType,fromPosition,toPosition,filterName);

@override
String toString() {
  return 'EquipmentEvent.filterChanging(fromPosition: $fromPosition, toPosition: $toPosition, filterName: $filterName)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_FilterChangingCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_FilterChangingCopyWith(EquipmentEvent_FilterChanging value, $Res Function(EquipmentEvent_FilterChanging) _then) = _$EquipmentEvent_FilterChangingCopyWithImpl;
@useResult
$Res call({
 int fromPosition, int toPosition, String? filterName
});




}
/// @nodoc
class _$EquipmentEvent_FilterChangingCopyWithImpl<$Res>
    implements $EquipmentEvent_FilterChangingCopyWith<$Res> {
  _$EquipmentEvent_FilterChangingCopyWithImpl(this._self, this._then);

  final EquipmentEvent_FilterChanging _self;
  final $Res Function(EquipmentEvent_FilterChanging) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fromPosition = null,Object? toPosition = null,Object? filterName = freezed,}) {
  return _then(EquipmentEvent_FilterChanging(
fromPosition: null == fromPosition ? _self.fromPosition : fromPosition // ignore: cast_nullable_to_non_nullable
as int,toPosition: null == toPosition ? _self.toPosition : toPosition // ignore: cast_nullable_to_non_nullable
as int,filterName: freezed == filterName ? _self.filterName : filterName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class EquipmentEvent_FilterChanged extends EquipmentEvent {
  const EquipmentEvent_FilterChanged({required this.position, this.filterName}): super._();
  

 final  int position;
 final  String? filterName;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_FilterChangedCopyWith<EquipmentEvent_FilterChanged> get copyWith => _$EquipmentEvent_FilterChangedCopyWithImpl<EquipmentEvent_FilterChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_FilterChanged&&(identical(other.position, position) || other.position == position)&&(identical(other.filterName, filterName) || other.filterName == filterName));
}


@override
int get hashCode => Object.hash(runtimeType,position,filterName);

@override
String toString() {
  return 'EquipmentEvent.filterChanged(position: $position, filterName: $filterName)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_FilterChangedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_FilterChangedCopyWith(EquipmentEvent_FilterChanged value, $Res Function(EquipmentEvent_FilterChanged) _then) = _$EquipmentEvent_FilterChangedCopyWithImpl;
@useResult
$Res call({
 int position, String? filterName
});




}
/// @nodoc
class _$EquipmentEvent_FilterChangedCopyWithImpl<$Res>
    implements $EquipmentEvent_FilterChangedCopyWith<$Res> {
  _$EquipmentEvent_FilterChangedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_FilterChanged _self;
  final $Res Function(EquipmentEvent_FilterChanged) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? position = null,Object? filterName = freezed,}) {
  return _then(EquipmentEvent_FilterChanged(
position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,filterName: freezed == filterName ? _self.filterName : filterName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class EquipmentEvent_RotatorMoveStarted extends EquipmentEvent {
  const EquipmentEvent_RotatorMoveStarted({required this.targetAngle}): super._();
  

 final  double targetAngle;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_RotatorMoveStartedCopyWith<EquipmentEvent_RotatorMoveStarted> get copyWith => _$EquipmentEvent_RotatorMoveStartedCopyWithImpl<EquipmentEvent_RotatorMoveStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_RotatorMoveStarted&&(identical(other.targetAngle, targetAngle) || other.targetAngle == targetAngle));
}


@override
int get hashCode => Object.hash(runtimeType,targetAngle);

@override
String toString() {
  return 'EquipmentEvent.rotatorMoveStarted(targetAngle: $targetAngle)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_RotatorMoveStartedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_RotatorMoveStartedCopyWith(EquipmentEvent_RotatorMoveStarted value, $Res Function(EquipmentEvent_RotatorMoveStarted) _then) = _$EquipmentEvent_RotatorMoveStartedCopyWithImpl;
@useResult
$Res call({
 double targetAngle
});




}
/// @nodoc
class _$EquipmentEvent_RotatorMoveStartedCopyWithImpl<$Res>
    implements $EquipmentEvent_RotatorMoveStartedCopyWith<$Res> {
  _$EquipmentEvent_RotatorMoveStartedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_RotatorMoveStarted _self;
  final $Res Function(EquipmentEvent_RotatorMoveStarted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetAngle = null,}) {
  return _then(EquipmentEvent_RotatorMoveStarted(
targetAngle: null == targetAngle ? _self.targetAngle : targetAngle // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_RotatorMoveCompleted extends EquipmentEvent {
  const EquipmentEvent_RotatorMoveCompleted({required this.angle}): super._();
  

 final  double angle;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_RotatorMoveCompletedCopyWith<EquipmentEvent_RotatorMoveCompleted> get copyWith => _$EquipmentEvent_RotatorMoveCompletedCopyWithImpl<EquipmentEvent_RotatorMoveCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_RotatorMoveCompleted&&(identical(other.angle, angle) || other.angle == angle));
}


@override
int get hashCode => Object.hash(runtimeType,angle);

@override
String toString() {
  return 'EquipmentEvent.rotatorMoveCompleted(angle: $angle)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_RotatorMoveCompletedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_RotatorMoveCompletedCopyWith(EquipmentEvent_RotatorMoveCompleted value, $Res Function(EquipmentEvent_RotatorMoveCompleted) _then) = _$EquipmentEvent_RotatorMoveCompletedCopyWithImpl;
@useResult
$Res call({
 double angle
});




}
/// @nodoc
class _$EquipmentEvent_RotatorMoveCompletedCopyWithImpl<$Res>
    implements $EquipmentEvent_RotatorMoveCompletedCopyWith<$Res> {
  _$EquipmentEvent_RotatorMoveCompletedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_RotatorMoveCompleted _self;
  final $Res Function(EquipmentEvent_RotatorMoveCompleted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? angle = null,}) {
  return _then(EquipmentEvent_RotatorMoveCompleted(
angle: null == angle ? _self.angle : angle // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_CameraCoolingStarted extends EquipmentEvent {
  const EquipmentEvent_CameraCoolingStarted({required this.targetTemp}): super._();
  

 final  double targetTemp;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_CameraCoolingStartedCopyWith<EquipmentEvent_CameraCoolingStarted> get copyWith => _$EquipmentEvent_CameraCoolingStartedCopyWithImpl<EquipmentEvent_CameraCoolingStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_CameraCoolingStarted&&(identical(other.targetTemp, targetTemp) || other.targetTemp == targetTemp));
}


@override
int get hashCode => Object.hash(runtimeType,targetTemp);

@override
String toString() {
  return 'EquipmentEvent.cameraCoolingStarted(targetTemp: $targetTemp)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_CameraCoolingStartedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_CameraCoolingStartedCopyWith(EquipmentEvent_CameraCoolingStarted value, $Res Function(EquipmentEvent_CameraCoolingStarted) _then) = _$EquipmentEvent_CameraCoolingStartedCopyWithImpl;
@useResult
$Res call({
 double targetTemp
});




}
/// @nodoc
class _$EquipmentEvent_CameraCoolingStartedCopyWithImpl<$Res>
    implements $EquipmentEvent_CameraCoolingStartedCopyWith<$Res> {
  _$EquipmentEvent_CameraCoolingStartedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_CameraCoolingStarted _self;
  final $Res Function(EquipmentEvent_CameraCoolingStarted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetTemp = null,}) {
  return _then(EquipmentEvent_CameraCoolingStarted(
targetTemp: null == targetTemp ? _self.targetTemp : targetTemp // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_CameraCoolingReached extends EquipmentEvent {
  const EquipmentEvent_CameraCoolingReached({required this.temperature}): super._();
  

 final  double temperature;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_CameraCoolingReachedCopyWith<EquipmentEvent_CameraCoolingReached> get copyWith => _$EquipmentEvent_CameraCoolingReachedCopyWithImpl<EquipmentEvent_CameraCoolingReached>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_CameraCoolingReached&&(identical(other.temperature, temperature) || other.temperature == temperature));
}


@override
int get hashCode => Object.hash(runtimeType,temperature);

@override
String toString() {
  return 'EquipmentEvent.cameraCoolingReached(temperature: $temperature)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_CameraCoolingReachedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_CameraCoolingReachedCopyWith(EquipmentEvent_CameraCoolingReached value, $Res Function(EquipmentEvent_CameraCoolingReached) _then) = _$EquipmentEvent_CameraCoolingReachedCopyWithImpl;
@useResult
$Res call({
 double temperature
});




}
/// @nodoc
class _$EquipmentEvent_CameraCoolingReachedCopyWithImpl<$Res>
    implements $EquipmentEvent_CameraCoolingReachedCopyWith<$Res> {
  _$EquipmentEvent_CameraCoolingReachedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_CameraCoolingReached _self;
  final $Res Function(EquipmentEvent_CameraCoolingReached) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? temperature = null,}) {
  return _then(EquipmentEvent_CameraCoolingReached(
temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class EquipmentEvent_CameraWarmingStarted extends EquipmentEvent {
  const EquipmentEvent_CameraWarmingStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_CameraWarmingStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.cameraWarmingStarted()';
}


}




/// @nodoc


class EquipmentEvent_CameraWarmingCompleted extends EquipmentEvent {
  const EquipmentEvent_CameraWarmingCompleted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_CameraWarmingCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EquipmentEvent.cameraWarmingCompleted()';
}


}




/// @nodoc


class EquipmentEvent_HeartbeatStarted extends EquipmentEvent {
  const EquipmentEvent_HeartbeatStarted({required this.deviceType, required this.deviceId, required this.intervalSecs}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  BigInt intervalSecs;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_HeartbeatStartedCopyWith<EquipmentEvent_HeartbeatStarted> get copyWith => _$EquipmentEvent_HeartbeatStartedCopyWithImpl<EquipmentEvent_HeartbeatStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_HeartbeatStarted&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.intervalSecs, intervalSecs) || other.intervalSecs == intervalSecs));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,intervalSecs);

@override
String toString() {
  return 'EquipmentEvent.heartbeatStarted(deviceType: $deviceType, deviceId: $deviceId, intervalSecs: $intervalSecs)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_HeartbeatStartedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_HeartbeatStartedCopyWith(EquipmentEvent_HeartbeatStarted value, $Res Function(EquipmentEvent_HeartbeatStarted) _then) = _$EquipmentEvent_HeartbeatStartedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, BigInt intervalSecs
});




}
/// @nodoc
class _$EquipmentEvent_HeartbeatStartedCopyWithImpl<$Res>
    implements $EquipmentEvent_HeartbeatStartedCopyWith<$Res> {
  _$EquipmentEvent_HeartbeatStartedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_HeartbeatStarted _self;
  final $Res Function(EquipmentEvent_HeartbeatStarted) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? intervalSecs = null,}) {
  return _then(EquipmentEvent_HeartbeatStarted(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,intervalSecs: null == intervalSecs ? _self.intervalSecs : intervalSecs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class EquipmentEvent_HeartbeatStopped extends EquipmentEvent {
  const EquipmentEvent_HeartbeatStopped({required this.deviceType, required this.deviceId}): super._();
  

 final  String deviceType;
 final  String deviceId;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_HeartbeatStoppedCopyWith<EquipmentEvent_HeartbeatStopped> get copyWith => _$EquipmentEvent_HeartbeatStoppedCopyWithImpl<EquipmentEvent_HeartbeatStopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_HeartbeatStopped&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId);

@override
String toString() {
  return 'EquipmentEvent.heartbeatStopped(deviceType: $deviceType, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_HeartbeatStoppedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_HeartbeatStoppedCopyWith(EquipmentEvent_HeartbeatStopped value, $Res Function(EquipmentEvent_HeartbeatStopped) _then) = _$EquipmentEvent_HeartbeatStoppedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId
});




}
/// @nodoc
class _$EquipmentEvent_HeartbeatStoppedCopyWithImpl<$Res>
    implements $EquipmentEvent_HeartbeatStoppedCopyWith<$Res> {
  _$EquipmentEvent_HeartbeatStoppedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_HeartbeatStopped _self;
  final $Res Function(EquipmentEvent_HeartbeatStopped) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,}) {
  return _then(EquipmentEvent_HeartbeatStopped(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EquipmentEvent_HeartbeatStatusChanged extends EquipmentEvent {
  const EquipmentEvent_HeartbeatStatusChanged({required this.deviceType, required this.deviceId, required this.status, required this.consecutiveFailures, this.lastRttMs}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  HeartbeatStatus status;
 final  int consecutiveFailures;
 final  BigInt? lastRttMs;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_HeartbeatStatusChangedCopyWith<EquipmentEvent_HeartbeatStatusChanged> get copyWith => _$EquipmentEvent_HeartbeatStatusChangedCopyWithImpl<EquipmentEvent_HeartbeatStatusChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_HeartbeatStatusChanged&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.status, status) || other.status == status)&&(identical(other.consecutiveFailures, consecutiveFailures) || other.consecutiveFailures == consecutiveFailures)&&(identical(other.lastRttMs, lastRttMs) || other.lastRttMs == lastRttMs));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,status,consecutiveFailures,lastRttMs);

@override
String toString() {
  return 'EquipmentEvent.heartbeatStatusChanged(deviceType: $deviceType, deviceId: $deviceId, status: $status, consecutiveFailures: $consecutiveFailures, lastRttMs: $lastRttMs)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_HeartbeatStatusChangedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_HeartbeatStatusChangedCopyWith(EquipmentEvent_HeartbeatStatusChanged value, $Res Function(EquipmentEvent_HeartbeatStatusChanged) _then) = _$EquipmentEvent_HeartbeatStatusChangedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, HeartbeatStatus status, int consecutiveFailures, BigInt? lastRttMs
});




}
/// @nodoc
class _$EquipmentEvent_HeartbeatStatusChangedCopyWithImpl<$Res>
    implements $EquipmentEvent_HeartbeatStatusChangedCopyWith<$Res> {
  _$EquipmentEvent_HeartbeatStatusChangedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_HeartbeatStatusChanged _self;
  final $Res Function(EquipmentEvent_HeartbeatStatusChanged) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? status = null,Object? consecutiveFailures = null,Object? lastRttMs = freezed,}) {
  return _then(EquipmentEvent_HeartbeatStatusChanged(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as HeartbeatStatus,consecutiveFailures: null == consecutiveFailures ? _self.consecutiveFailures : consecutiveFailures // ignore: cast_nullable_to_non_nullable
as int,lastRttMs: freezed == lastRttMs ? _self.lastRttMs : lastRttMs // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class EquipmentEvent_HeartbeatReconnecting extends EquipmentEvent {
  const EquipmentEvent_HeartbeatReconnecting({required this.deviceType, required this.deviceId, required this.attempt, required this.maxAttempts}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  int attempt;
 final  int maxAttempts;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_HeartbeatReconnectingCopyWith<EquipmentEvent_HeartbeatReconnecting> get copyWith => _$EquipmentEvent_HeartbeatReconnectingCopyWithImpl<EquipmentEvent_HeartbeatReconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_HeartbeatReconnecting&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.attempt, attempt) || other.attempt == attempt)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,attempt,maxAttempts);

@override
String toString() {
  return 'EquipmentEvent.heartbeatReconnecting(deviceType: $deviceType, deviceId: $deviceId, attempt: $attempt, maxAttempts: $maxAttempts)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_HeartbeatReconnectingCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_HeartbeatReconnectingCopyWith(EquipmentEvent_HeartbeatReconnecting value, $Res Function(EquipmentEvent_HeartbeatReconnecting) _then) = _$EquipmentEvent_HeartbeatReconnectingCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, int attempt, int maxAttempts
});




}
/// @nodoc
class _$EquipmentEvent_HeartbeatReconnectingCopyWithImpl<$Res>
    implements $EquipmentEvent_HeartbeatReconnectingCopyWith<$Res> {
  _$EquipmentEvent_HeartbeatReconnectingCopyWithImpl(this._self, this._then);

  final EquipmentEvent_HeartbeatReconnecting _self;
  final $Res Function(EquipmentEvent_HeartbeatReconnecting) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? attempt = null,Object? maxAttempts = null,}) {
  return _then(EquipmentEvent_HeartbeatReconnecting(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EquipmentEvent_HeartbeatReconnected extends EquipmentEvent {
  const EquipmentEvent_HeartbeatReconnected({required this.deviceType, required this.deviceId, required this.afterAttempts}): super._();
  

 final  String deviceType;
 final  String deviceId;
 final  int afterAttempts;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_HeartbeatReconnectedCopyWith<EquipmentEvent_HeartbeatReconnected> get copyWith => _$EquipmentEvent_HeartbeatReconnectedCopyWithImpl<EquipmentEvent_HeartbeatReconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_HeartbeatReconnected&&(identical(other.deviceType, deviceType) || other.deviceType == deviceType)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.afterAttempts, afterAttempts) || other.afterAttempts == afterAttempts));
}


@override
int get hashCode => Object.hash(runtimeType,deviceType,deviceId,afterAttempts);

@override
String toString() {
  return 'EquipmentEvent.heartbeatReconnected(deviceType: $deviceType, deviceId: $deviceId, afterAttempts: $afterAttempts)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_HeartbeatReconnectedCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_HeartbeatReconnectedCopyWith(EquipmentEvent_HeartbeatReconnected value, $Res Function(EquipmentEvent_HeartbeatReconnected) _then) = _$EquipmentEvent_HeartbeatReconnectedCopyWithImpl;
@useResult
$Res call({
 String deviceType, String deviceId, int afterAttempts
});




}
/// @nodoc
class _$EquipmentEvent_HeartbeatReconnectedCopyWithImpl<$Res>
    implements $EquipmentEvent_HeartbeatReconnectedCopyWith<$Res> {
  _$EquipmentEvent_HeartbeatReconnectedCopyWithImpl(this._self, this._then);

  final EquipmentEvent_HeartbeatReconnected _self;
  final $Res Function(EquipmentEvent_HeartbeatReconnected) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceType = null,Object? deviceId = null,Object? afterAttempts = null,}) {
  return _then(EquipmentEvent_HeartbeatReconnected(
deviceType: null == deviceType ? _self.deviceType : deviceType // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,afterAttempts: null == afterAttempts ? _self.afterAttempts : afterAttempts // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EquipmentEvent_DeviceDiscovered extends EquipmentEvent {
  const EquipmentEvent_DeviceDiscovered({required this.deviceClass, required this.driver, required this.id, required this.name, required this.displayName, this.uniqueId}): super._();
  

/// Canonical device class (`camera`, `mount`, `focuser`, `filterWheel`,
/// `rotator`, …).
 final  String deviceClass;
/// Driver backend (`native`, `ascom`, `alpaca`, `indi`, `simulator`).
 final  String driver;
/// Backend-scoped device id used to connect.
 final  String id;
/// Raw device name as reported by the SDK / driver.
 final  String name;
/// User-facing display name (may equal `name`).
 final  String displayName;
/// Stable hardware identity (USB serial, etc.) when the backend exposes
/// one; `None` otherwise.
 final  String? uniqueId;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_DeviceDiscoveredCopyWith<EquipmentEvent_DeviceDiscovered> get copyWith => _$EquipmentEvent_DeviceDiscoveredCopyWithImpl<EquipmentEvent_DeviceDiscovered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_DeviceDiscovered&&(identical(other.deviceClass, deviceClass) || other.deviceClass == deviceClass)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.uniqueId, uniqueId) || other.uniqueId == uniqueId));
}


@override
int get hashCode => Object.hash(runtimeType,deviceClass,driver,id,name,displayName,uniqueId);

@override
String toString() {
  return 'EquipmentEvent.deviceDiscovered(deviceClass: $deviceClass, driver: $driver, id: $id, name: $name, displayName: $displayName, uniqueId: $uniqueId)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_DeviceDiscoveredCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_DeviceDiscoveredCopyWith(EquipmentEvent_DeviceDiscovered value, $Res Function(EquipmentEvent_DeviceDiscovered) _then) = _$EquipmentEvent_DeviceDiscoveredCopyWithImpl;
@useResult
$Res call({
 String deviceClass, String driver, String id, String name, String displayName, String? uniqueId
});




}
/// @nodoc
class _$EquipmentEvent_DeviceDiscoveredCopyWithImpl<$Res>
    implements $EquipmentEvent_DeviceDiscoveredCopyWith<$Res> {
  _$EquipmentEvent_DeviceDiscoveredCopyWithImpl(this._self, this._then);

  final EquipmentEvent_DeviceDiscovered _self;
  final $Res Function(EquipmentEvent_DeviceDiscovered) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceClass = null,Object? driver = null,Object? id = null,Object? name = null,Object? displayName = null,Object? uniqueId = freezed,}) {
  return _then(EquipmentEvent_DeviceDiscovered(
deviceClass: null == deviceClass ? _self.deviceClass : deviceClass // ignore: cast_nullable_to_non_nullable
as String,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,uniqueId: freezed == uniqueId ? _self.uniqueId : uniqueId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class EquipmentEvent_DeviceLost extends EquipmentEvent {
  const EquipmentEvent_DeviceLost({required this.deviceClass, required this.driver, required this.id}): super._();
  

 final  String deviceClass;
 final  String driver;
 final  String id;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EquipmentEvent_DeviceLostCopyWith<EquipmentEvent_DeviceLost> get copyWith => _$EquipmentEvent_DeviceLostCopyWithImpl<EquipmentEvent_DeviceLost>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EquipmentEvent_DeviceLost&&(identical(other.deviceClass, deviceClass) || other.deviceClass == deviceClass)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,deviceClass,driver,id);

@override
String toString() {
  return 'EquipmentEvent.deviceLost(deviceClass: $deviceClass, driver: $driver, id: $id)';
}


}

/// @nodoc
abstract mixin class $EquipmentEvent_DeviceLostCopyWith<$Res> implements $EquipmentEventCopyWith<$Res> {
  factory $EquipmentEvent_DeviceLostCopyWith(EquipmentEvent_DeviceLost value, $Res Function(EquipmentEvent_DeviceLost) _then) = _$EquipmentEvent_DeviceLostCopyWithImpl;
@useResult
$Res call({
 String deviceClass, String driver, String id
});




}
/// @nodoc
class _$EquipmentEvent_DeviceLostCopyWithImpl<$Res>
    implements $EquipmentEvent_DeviceLostCopyWith<$Res> {
  _$EquipmentEvent_DeviceLostCopyWithImpl(this._self, this._then);

  final EquipmentEvent_DeviceLost _self;
  final $Res Function(EquipmentEvent_DeviceLost) _then;

/// Create a copy of EquipmentEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceClass = null,Object? driver = null,Object? id = null,}) {
  return _then(EquipmentEvent_DeviceLost(
deviceClass: null == deviceClass ? _self.deviceClass : deviceClass // ignore: cast_nullable_to_non_nullable
as String,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$EventPayload {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'EventPayload(field0: $field0)';
}


}

/// @nodoc
class $EventPayloadCopyWith<$Res>  {
$EventPayloadCopyWith(EventPayload _, $Res Function(EventPayload) __);
}


/// Adds pattern-matching-related methods to [EventPayload].
extension EventPayloadPatterns on EventPayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EventPayload_Equipment value)?  equipment,TResult Function( EventPayload_Imaging value)?  imaging,TResult Function( EventPayload_Guiding value)?  guiding,TResult Function( EventPayload_Sequencer value)?  sequencer,TResult Function( EventPayload_Safety value)?  safety,TResult Function( EventPayload_System value)?  system,TResult Function( EventPayload_PolarAlignment value)?  polarAlignment,TResult Function( EventPayload_PolarAlignmentStatus value)?  polarAlignmentStatus,TResult Function( EventPayload_PolarAlignmentImage value)?  polarAlignmentImage,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EventPayload_Equipment() when equipment != null:
return equipment(_that);case EventPayload_Imaging() when imaging != null:
return imaging(_that);case EventPayload_Guiding() when guiding != null:
return guiding(_that);case EventPayload_Sequencer() when sequencer != null:
return sequencer(_that);case EventPayload_Safety() when safety != null:
return safety(_that);case EventPayload_System() when system != null:
return system(_that);case EventPayload_PolarAlignment() when polarAlignment != null:
return polarAlignment(_that);case EventPayload_PolarAlignmentStatus() when polarAlignmentStatus != null:
return polarAlignmentStatus(_that);case EventPayload_PolarAlignmentImage() when polarAlignmentImage != null:
return polarAlignmentImage(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EventPayload_Equipment value)  equipment,required TResult Function( EventPayload_Imaging value)  imaging,required TResult Function( EventPayload_Guiding value)  guiding,required TResult Function( EventPayload_Sequencer value)  sequencer,required TResult Function( EventPayload_Safety value)  safety,required TResult Function( EventPayload_System value)  system,required TResult Function( EventPayload_PolarAlignment value)  polarAlignment,required TResult Function( EventPayload_PolarAlignmentStatus value)  polarAlignmentStatus,required TResult Function( EventPayload_PolarAlignmentImage value)  polarAlignmentImage,}){
final _that = this;
switch (_that) {
case EventPayload_Equipment():
return equipment(_that);case EventPayload_Imaging():
return imaging(_that);case EventPayload_Guiding():
return guiding(_that);case EventPayload_Sequencer():
return sequencer(_that);case EventPayload_Safety():
return safety(_that);case EventPayload_System():
return system(_that);case EventPayload_PolarAlignment():
return polarAlignment(_that);case EventPayload_PolarAlignmentStatus():
return polarAlignmentStatus(_that);case EventPayload_PolarAlignmentImage():
return polarAlignmentImage(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EventPayload_Equipment value)?  equipment,TResult? Function( EventPayload_Imaging value)?  imaging,TResult? Function( EventPayload_Guiding value)?  guiding,TResult? Function( EventPayload_Sequencer value)?  sequencer,TResult? Function( EventPayload_Safety value)?  safety,TResult? Function( EventPayload_System value)?  system,TResult? Function( EventPayload_PolarAlignment value)?  polarAlignment,TResult? Function( EventPayload_PolarAlignmentStatus value)?  polarAlignmentStatus,TResult? Function( EventPayload_PolarAlignmentImage value)?  polarAlignmentImage,}){
final _that = this;
switch (_that) {
case EventPayload_Equipment() when equipment != null:
return equipment(_that);case EventPayload_Imaging() when imaging != null:
return imaging(_that);case EventPayload_Guiding() when guiding != null:
return guiding(_that);case EventPayload_Sequencer() when sequencer != null:
return sequencer(_that);case EventPayload_Safety() when safety != null:
return safety(_that);case EventPayload_System() when system != null:
return system(_that);case EventPayload_PolarAlignment() when polarAlignment != null:
return polarAlignment(_that);case EventPayload_PolarAlignmentStatus() when polarAlignmentStatus != null:
return polarAlignmentStatus(_that);case EventPayload_PolarAlignmentImage() when polarAlignmentImage != null:
return polarAlignmentImage(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( EquipmentEvent field0)?  equipment,TResult Function( ImagingEvent field0)?  imaging,TResult Function( GuidingEvent field0)?  guiding,TResult Function( SequencerEvent field0)?  sequencer,TResult Function( SafetyEvent field0)?  safety,TResult Function( SystemEvent field0)?  system,TResult Function( PolarAlignmentEvent field0)?  polarAlignment,TResult Function( PolarAlignmentStatus field0)?  polarAlignmentStatus,TResult Function( PolarAlignmentImageEvent field0)?  polarAlignmentImage,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EventPayload_Equipment() when equipment != null:
return equipment(_that.field0);case EventPayload_Imaging() when imaging != null:
return imaging(_that.field0);case EventPayload_Guiding() when guiding != null:
return guiding(_that.field0);case EventPayload_Sequencer() when sequencer != null:
return sequencer(_that.field0);case EventPayload_Safety() when safety != null:
return safety(_that.field0);case EventPayload_System() when system != null:
return system(_that.field0);case EventPayload_PolarAlignment() when polarAlignment != null:
return polarAlignment(_that.field0);case EventPayload_PolarAlignmentStatus() when polarAlignmentStatus != null:
return polarAlignmentStatus(_that.field0);case EventPayload_PolarAlignmentImage() when polarAlignmentImage != null:
return polarAlignmentImage(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( EquipmentEvent field0)  equipment,required TResult Function( ImagingEvent field0)  imaging,required TResult Function( GuidingEvent field0)  guiding,required TResult Function( SequencerEvent field0)  sequencer,required TResult Function( SafetyEvent field0)  safety,required TResult Function( SystemEvent field0)  system,required TResult Function( PolarAlignmentEvent field0)  polarAlignment,required TResult Function( PolarAlignmentStatus field0)  polarAlignmentStatus,required TResult Function( PolarAlignmentImageEvent field0)  polarAlignmentImage,}) {final _that = this;
switch (_that) {
case EventPayload_Equipment():
return equipment(_that.field0);case EventPayload_Imaging():
return imaging(_that.field0);case EventPayload_Guiding():
return guiding(_that.field0);case EventPayload_Sequencer():
return sequencer(_that.field0);case EventPayload_Safety():
return safety(_that.field0);case EventPayload_System():
return system(_that.field0);case EventPayload_PolarAlignment():
return polarAlignment(_that.field0);case EventPayload_PolarAlignmentStatus():
return polarAlignmentStatus(_that.field0);case EventPayload_PolarAlignmentImage():
return polarAlignmentImage(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( EquipmentEvent field0)?  equipment,TResult? Function( ImagingEvent field0)?  imaging,TResult? Function( GuidingEvent field0)?  guiding,TResult? Function( SequencerEvent field0)?  sequencer,TResult? Function( SafetyEvent field0)?  safety,TResult? Function( SystemEvent field0)?  system,TResult? Function( PolarAlignmentEvent field0)?  polarAlignment,TResult? Function( PolarAlignmentStatus field0)?  polarAlignmentStatus,TResult? Function( PolarAlignmentImageEvent field0)?  polarAlignmentImage,}) {final _that = this;
switch (_that) {
case EventPayload_Equipment() when equipment != null:
return equipment(_that.field0);case EventPayload_Imaging() when imaging != null:
return imaging(_that.field0);case EventPayload_Guiding() when guiding != null:
return guiding(_that.field0);case EventPayload_Sequencer() when sequencer != null:
return sequencer(_that.field0);case EventPayload_Safety() when safety != null:
return safety(_that.field0);case EventPayload_System() when system != null:
return system(_that.field0);case EventPayload_PolarAlignment() when polarAlignment != null:
return polarAlignment(_that.field0);case EventPayload_PolarAlignmentStatus() when polarAlignmentStatus != null:
return polarAlignmentStatus(_that.field0);case EventPayload_PolarAlignmentImage() when polarAlignmentImage != null:
return polarAlignmentImage(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class EventPayload_Equipment extends EventPayload {
  const EventPayload_Equipment(this.field0): super._();
  

@override final  EquipmentEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_EquipmentCopyWith<EventPayload_Equipment> get copyWith => _$EventPayload_EquipmentCopyWithImpl<EventPayload_Equipment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_Equipment&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.equipment(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_EquipmentCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_EquipmentCopyWith(EventPayload_Equipment value, $Res Function(EventPayload_Equipment) _then) = _$EventPayload_EquipmentCopyWithImpl;
@useResult
$Res call({
 EquipmentEvent field0
});


$EquipmentEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_EquipmentCopyWithImpl<$Res>
    implements $EventPayload_EquipmentCopyWith<$Res> {
  _$EventPayload_EquipmentCopyWithImpl(this._self, this._then);

  final EventPayload_Equipment _self;
  final $Res Function(EventPayload_Equipment) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_Equipment(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as EquipmentEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EquipmentEventCopyWith<$Res> get field0 {
  
  return $EquipmentEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_Imaging extends EventPayload {
  const EventPayload_Imaging(this.field0): super._();
  

@override final  ImagingEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_ImagingCopyWith<EventPayload_Imaging> get copyWith => _$EventPayload_ImagingCopyWithImpl<EventPayload_Imaging>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_Imaging&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.imaging(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_ImagingCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_ImagingCopyWith(EventPayload_Imaging value, $Res Function(EventPayload_Imaging) _then) = _$EventPayload_ImagingCopyWithImpl;
@useResult
$Res call({
 ImagingEvent field0
});


$ImagingEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_ImagingCopyWithImpl<$Res>
    implements $EventPayload_ImagingCopyWith<$Res> {
  _$EventPayload_ImagingCopyWithImpl(this._self, this._then);

  final EventPayload_Imaging _self;
  final $Res Function(EventPayload_Imaging) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_Imaging(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ImagingEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ImagingEventCopyWith<$Res> get field0 {
  
  return $ImagingEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_Guiding extends EventPayload {
  const EventPayload_Guiding(this.field0): super._();
  

@override final  GuidingEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_GuidingCopyWith<EventPayload_Guiding> get copyWith => _$EventPayload_GuidingCopyWithImpl<EventPayload_Guiding>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_Guiding&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.guiding(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_GuidingCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_GuidingCopyWith(EventPayload_Guiding value, $Res Function(EventPayload_Guiding) _then) = _$EventPayload_GuidingCopyWithImpl;
@useResult
$Res call({
 GuidingEvent field0
});


$GuidingEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_GuidingCopyWithImpl<$Res>
    implements $EventPayload_GuidingCopyWith<$Res> {
  _$EventPayload_GuidingCopyWithImpl(this._self, this._then);

  final EventPayload_Guiding _self;
  final $Res Function(EventPayload_Guiding) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_Guiding(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as GuidingEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GuidingEventCopyWith<$Res> get field0 {
  
  return $GuidingEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_Sequencer extends EventPayload {
  const EventPayload_Sequencer(this.field0): super._();
  

@override final  SequencerEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_SequencerCopyWith<EventPayload_Sequencer> get copyWith => _$EventPayload_SequencerCopyWithImpl<EventPayload_Sequencer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_Sequencer&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.sequencer(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_SequencerCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_SequencerCopyWith(EventPayload_Sequencer value, $Res Function(EventPayload_Sequencer) _then) = _$EventPayload_SequencerCopyWithImpl;
@useResult
$Res call({
 SequencerEvent field0
});


$SequencerEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_SequencerCopyWithImpl<$Res>
    implements $EventPayload_SequencerCopyWith<$Res> {
  _$EventPayload_SequencerCopyWithImpl(this._self, this._then);

  final EventPayload_Sequencer _self;
  final $Res Function(EventPayload_Sequencer) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_Sequencer(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as SequencerEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SequencerEventCopyWith<$Res> get field0 {
  
  return $SequencerEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_Safety extends EventPayload {
  const EventPayload_Safety(this.field0): super._();
  

@override final  SafetyEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_SafetyCopyWith<EventPayload_Safety> get copyWith => _$EventPayload_SafetyCopyWithImpl<EventPayload_Safety>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_Safety&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.safety(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_SafetyCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_SafetyCopyWith(EventPayload_Safety value, $Res Function(EventPayload_Safety) _then) = _$EventPayload_SafetyCopyWithImpl;
@useResult
$Res call({
 SafetyEvent field0
});


$SafetyEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_SafetyCopyWithImpl<$Res>
    implements $EventPayload_SafetyCopyWith<$Res> {
  _$EventPayload_SafetyCopyWithImpl(this._self, this._then);

  final EventPayload_Safety _self;
  final $Res Function(EventPayload_Safety) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_Safety(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as SafetyEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SafetyEventCopyWith<$Res> get field0 {
  
  return $SafetyEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_System extends EventPayload {
  const EventPayload_System(this.field0): super._();
  

@override final  SystemEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_SystemCopyWith<EventPayload_System> get copyWith => _$EventPayload_SystemCopyWithImpl<EventPayload_System>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_System&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.system(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_SystemCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_SystemCopyWith(EventPayload_System value, $Res Function(EventPayload_System) _then) = _$EventPayload_SystemCopyWithImpl;
@useResult
$Res call({
 SystemEvent field0
});


$SystemEventCopyWith<$Res> get field0;

}
/// @nodoc
class _$EventPayload_SystemCopyWithImpl<$Res>
    implements $EventPayload_SystemCopyWith<$Res> {
  _$EventPayload_SystemCopyWithImpl(this._self, this._then);

  final EventPayload_System _self;
  final $Res Function(EventPayload_System) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_System(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as SystemEvent,
  ));
}

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SystemEventCopyWith<$Res> get field0 {
  
  return $SystemEventCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc


class EventPayload_PolarAlignment extends EventPayload {
  const EventPayload_PolarAlignment(this.field0): super._();
  

@override final  PolarAlignmentEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_PolarAlignmentCopyWith<EventPayload_PolarAlignment> get copyWith => _$EventPayload_PolarAlignmentCopyWithImpl<EventPayload_PolarAlignment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_PolarAlignment&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.polarAlignment(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_PolarAlignmentCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_PolarAlignmentCopyWith(EventPayload_PolarAlignment value, $Res Function(EventPayload_PolarAlignment) _then) = _$EventPayload_PolarAlignmentCopyWithImpl;
@useResult
$Res call({
 PolarAlignmentEvent field0
});




}
/// @nodoc
class _$EventPayload_PolarAlignmentCopyWithImpl<$Res>
    implements $EventPayload_PolarAlignmentCopyWith<$Res> {
  _$EventPayload_PolarAlignmentCopyWithImpl(this._self, this._then);

  final EventPayload_PolarAlignment _self;
  final $Res Function(EventPayload_PolarAlignment) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_PolarAlignment(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PolarAlignmentEvent,
  ));
}


}

/// @nodoc


class EventPayload_PolarAlignmentStatus extends EventPayload {
  const EventPayload_PolarAlignmentStatus(this.field0): super._();
  

@override final  PolarAlignmentStatus field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_PolarAlignmentStatusCopyWith<EventPayload_PolarAlignmentStatus> get copyWith => _$EventPayload_PolarAlignmentStatusCopyWithImpl<EventPayload_PolarAlignmentStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_PolarAlignmentStatus&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.polarAlignmentStatus(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_PolarAlignmentStatusCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_PolarAlignmentStatusCopyWith(EventPayload_PolarAlignmentStatus value, $Res Function(EventPayload_PolarAlignmentStatus) _then) = _$EventPayload_PolarAlignmentStatusCopyWithImpl;
@useResult
$Res call({
 PolarAlignmentStatus field0
});




}
/// @nodoc
class _$EventPayload_PolarAlignmentStatusCopyWithImpl<$Res>
    implements $EventPayload_PolarAlignmentStatusCopyWith<$Res> {
  _$EventPayload_PolarAlignmentStatusCopyWithImpl(this._self, this._then);

  final EventPayload_PolarAlignmentStatus _self;
  final $Res Function(EventPayload_PolarAlignmentStatus) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_PolarAlignmentStatus(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PolarAlignmentStatus,
  ));
}


}

/// @nodoc


class EventPayload_PolarAlignmentImage extends EventPayload {
  const EventPayload_PolarAlignmentImage(this.field0): super._();
  

@override final  PolarAlignmentImageEvent field0;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventPayload_PolarAlignmentImageCopyWith<EventPayload_PolarAlignmentImage> get copyWith => _$EventPayload_PolarAlignmentImageCopyWithImpl<EventPayload_PolarAlignmentImage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventPayload_PolarAlignmentImage&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'EventPayload.polarAlignmentImage(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $EventPayload_PolarAlignmentImageCopyWith<$Res> implements $EventPayloadCopyWith<$Res> {
  factory $EventPayload_PolarAlignmentImageCopyWith(EventPayload_PolarAlignmentImage value, $Res Function(EventPayload_PolarAlignmentImage) _then) = _$EventPayload_PolarAlignmentImageCopyWithImpl;
@useResult
$Res call({
 PolarAlignmentImageEvent field0
});




}
/// @nodoc
class _$EventPayload_PolarAlignmentImageCopyWithImpl<$Res>
    implements $EventPayload_PolarAlignmentImageCopyWith<$Res> {
  _$EventPayload_PolarAlignmentImageCopyWithImpl(this._self, this._then);

  final EventPayload_PolarAlignmentImage _self;
  final $Res Function(EventPayload_PolarAlignmentImage) _then;

/// Create a copy of EventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(EventPayload_PolarAlignmentImage(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PolarAlignmentImageEvent,
  ));
}


}

/// @nodoc
mixin _$GuidingEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent()';
}


}

/// @nodoc
class $GuidingEventCopyWith<$Res>  {
$GuidingEventCopyWith(GuidingEvent _, $Res Function(GuidingEvent) __);
}


/// Adds pattern-matching-related methods to [GuidingEvent].
extension GuidingEventPatterns on GuidingEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GuidingEvent_Connected value)?  connected,TResult Function( GuidingEvent_Disconnected value)?  disconnected,TResult Function( GuidingEvent_GuidingStarted value)?  guidingStarted,TResult Function( GuidingEvent_GuidingStopped value)?  guidingStopped,TResult Function( GuidingEvent_Paused value)?  paused,TResult Function( GuidingEvent_Resumed value)?  resumed,TResult Function( GuidingEvent_Settled value)?  settled,TResult Function( GuidingEvent_LostStar value)?  lostStar,TResult Function( GuidingEvent_DitherStarted value)?  ditherStarted,TResult Function( GuidingEvent_DitherCompleted value)?  ditherCompleted,TResult Function( GuidingEvent_Correction value)?  correction,TResult Function( GuidingEvent_Looping value)?  looping,TResult Function( GuidingEvent_Settling value)?  settling,TResult Function( GuidingEvent_Calibrating value)?  calibrating,TResult Function( GuidingEvent_CalibrationComplete value)?  calibrationComplete,TResult Function( GuidingEvent_StarSelected value)?  starSelected,TResult Function( GuidingEvent_AppState value)?  appState,TResult Function( GuidingEvent_GuideStats value)?  guideStats,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GuidingEvent_Connected() when connected != null:
return connected(_that);case GuidingEvent_Disconnected() when disconnected != null:
return disconnected(_that);case GuidingEvent_GuidingStarted() when guidingStarted != null:
return guidingStarted(_that);case GuidingEvent_GuidingStopped() when guidingStopped != null:
return guidingStopped(_that);case GuidingEvent_Paused() when paused != null:
return paused(_that);case GuidingEvent_Resumed() when resumed != null:
return resumed(_that);case GuidingEvent_Settled() when settled != null:
return settled(_that);case GuidingEvent_LostStar() when lostStar != null:
return lostStar(_that);case GuidingEvent_DitherStarted() when ditherStarted != null:
return ditherStarted(_that);case GuidingEvent_DitherCompleted() when ditherCompleted != null:
return ditherCompleted(_that);case GuidingEvent_Correction() when correction != null:
return correction(_that);case GuidingEvent_Looping() when looping != null:
return looping(_that);case GuidingEvent_Settling() when settling != null:
return settling(_that);case GuidingEvent_Calibrating() when calibrating != null:
return calibrating(_that);case GuidingEvent_CalibrationComplete() when calibrationComplete != null:
return calibrationComplete(_that);case GuidingEvent_StarSelected() when starSelected != null:
return starSelected(_that);case GuidingEvent_AppState() when appState != null:
return appState(_that);case GuidingEvent_GuideStats() when guideStats != null:
return guideStats(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GuidingEvent_Connected value)  connected,required TResult Function( GuidingEvent_Disconnected value)  disconnected,required TResult Function( GuidingEvent_GuidingStarted value)  guidingStarted,required TResult Function( GuidingEvent_GuidingStopped value)  guidingStopped,required TResult Function( GuidingEvent_Paused value)  paused,required TResult Function( GuidingEvent_Resumed value)  resumed,required TResult Function( GuidingEvent_Settled value)  settled,required TResult Function( GuidingEvent_LostStar value)  lostStar,required TResult Function( GuidingEvent_DitherStarted value)  ditherStarted,required TResult Function( GuidingEvent_DitherCompleted value)  ditherCompleted,required TResult Function( GuidingEvent_Correction value)  correction,required TResult Function( GuidingEvent_Looping value)  looping,required TResult Function( GuidingEvent_Settling value)  settling,required TResult Function( GuidingEvent_Calibrating value)  calibrating,required TResult Function( GuidingEvent_CalibrationComplete value)  calibrationComplete,required TResult Function( GuidingEvent_StarSelected value)  starSelected,required TResult Function( GuidingEvent_AppState value)  appState,required TResult Function( GuidingEvent_GuideStats value)  guideStats,}){
final _that = this;
switch (_that) {
case GuidingEvent_Connected():
return connected(_that);case GuidingEvent_Disconnected():
return disconnected(_that);case GuidingEvent_GuidingStarted():
return guidingStarted(_that);case GuidingEvent_GuidingStopped():
return guidingStopped(_that);case GuidingEvent_Paused():
return paused(_that);case GuidingEvent_Resumed():
return resumed(_that);case GuidingEvent_Settled():
return settled(_that);case GuidingEvent_LostStar():
return lostStar(_that);case GuidingEvent_DitherStarted():
return ditherStarted(_that);case GuidingEvent_DitherCompleted():
return ditherCompleted(_that);case GuidingEvent_Correction():
return correction(_that);case GuidingEvent_Looping():
return looping(_that);case GuidingEvent_Settling():
return settling(_that);case GuidingEvent_Calibrating():
return calibrating(_that);case GuidingEvent_CalibrationComplete():
return calibrationComplete(_that);case GuidingEvent_StarSelected():
return starSelected(_that);case GuidingEvent_AppState():
return appState(_that);case GuidingEvent_GuideStats():
return guideStats(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GuidingEvent_Connected value)?  connected,TResult? Function( GuidingEvent_Disconnected value)?  disconnected,TResult? Function( GuidingEvent_GuidingStarted value)?  guidingStarted,TResult? Function( GuidingEvent_GuidingStopped value)?  guidingStopped,TResult? Function( GuidingEvent_Paused value)?  paused,TResult? Function( GuidingEvent_Resumed value)?  resumed,TResult? Function( GuidingEvent_Settled value)?  settled,TResult? Function( GuidingEvent_LostStar value)?  lostStar,TResult? Function( GuidingEvent_DitherStarted value)?  ditherStarted,TResult? Function( GuidingEvent_DitherCompleted value)?  ditherCompleted,TResult? Function( GuidingEvent_Correction value)?  correction,TResult? Function( GuidingEvent_Looping value)?  looping,TResult? Function( GuidingEvent_Settling value)?  settling,TResult? Function( GuidingEvent_Calibrating value)?  calibrating,TResult? Function( GuidingEvent_CalibrationComplete value)?  calibrationComplete,TResult? Function( GuidingEvent_StarSelected value)?  starSelected,TResult? Function( GuidingEvent_AppState value)?  appState,TResult? Function( GuidingEvent_GuideStats value)?  guideStats,}){
final _that = this;
switch (_that) {
case GuidingEvent_Connected() when connected != null:
return connected(_that);case GuidingEvent_Disconnected() when disconnected != null:
return disconnected(_that);case GuidingEvent_GuidingStarted() when guidingStarted != null:
return guidingStarted(_that);case GuidingEvent_GuidingStopped() when guidingStopped != null:
return guidingStopped(_that);case GuidingEvent_Paused() when paused != null:
return paused(_that);case GuidingEvent_Resumed() when resumed != null:
return resumed(_that);case GuidingEvent_Settled() when settled != null:
return settled(_that);case GuidingEvent_LostStar() when lostStar != null:
return lostStar(_that);case GuidingEvent_DitherStarted() when ditherStarted != null:
return ditherStarted(_that);case GuidingEvent_DitherCompleted() when ditherCompleted != null:
return ditherCompleted(_that);case GuidingEvent_Correction() when correction != null:
return correction(_that);case GuidingEvent_Looping() when looping != null:
return looping(_that);case GuidingEvent_Settling() when settling != null:
return settling(_that);case GuidingEvent_Calibrating() when calibrating != null:
return calibrating(_that);case GuidingEvent_CalibrationComplete() when calibrationComplete != null:
return calibrationComplete(_that);case GuidingEvent_StarSelected() when starSelected != null:
return starSelected(_that);case GuidingEvent_AppState() when appState != null:
return appState(_that);case GuidingEvent_GuideStats() when guideStats != null:
return guideStats(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  connected,TResult Function()?  disconnected,TResult Function()?  guidingStarted,TResult Function()?  guidingStopped,TResult Function()?  paused,TResult Function()?  resumed,TResult Function( double rms)?  settled,TResult Function()?  lostStar,TResult Function( double pixels)?  ditherStarted,TResult Function()?  ditherCompleted,TResult Function( double ra,  double dec,  double raRaw,  double decRaw)?  correction,TResult Function()?  looping,TResult Function()?  settling,TResult Function()?  calibrating,TResult Function()?  calibrationComplete,TResult Function( double x,  double y)?  starSelected,TResult Function( String state)?  appState,TResult Function( double snr,  double starMass)?  guideStats,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GuidingEvent_Connected() when connected != null:
return connected();case GuidingEvent_Disconnected() when disconnected != null:
return disconnected();case GuidingEvent_GuidingStarted() when guidingStarted != null:
return guidingStarted();case GuidingEvent_GuidingStopped() when guidingStopped != null:
return guidingStopped();case GuidingEvent_Paused() when paused != null:
return paused();case GuidingEvent_Resumed() when resumed != null:
return resumed();case GuidingEvent_Settled() when settled != null:
return settled(_that.rms);case GuidingEvent_LostStar() when lostStar != null:
return lostStar();case GuidingEvent_DitherStarted() when ditherStarted != null:
return ditherStarted(_that.pixels);case GuidingEvent_DitherCompleted() when ditherCompleted != null:
return ditherCompleted();case GuidingEvent_Correction() when correction != null:
return correction(_that.ra,_that.dec,_that.raRaw,_that.decRaw);case GuidingEvent_Looping() when looping != null:
return looping();case GuidingEvent_Settling() when settling != null:
return settling();case GuidingEvent_Calibrating() when calibrating != null:
return calibrating();case GuidingEvent_CalibrationComplete() when calibrationComplete != null:
return calibrationComplete();case GuidingEvent_StarSelected() when starSelected != null:
return starSelected(_that.x,_that.y);case GuidingEvent_AppState() when appState != null:
return appState(_that.state);case GuidingEvent_GuideStats() when guideStats != null:
return guideStats(_that.snr,_that.starMass);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  connected,required TResult Function()  disconnected,required TResult Function()  guidingStarted,required TResult Function()  guidingStopped,required TResult Function()  paused,required TResult Function()  resumed,required TResult Function( double rms)  settled,required TResult Function()  lostStar,required TResult Function( double pixels)  ditherStarted,required TResult Function()  ditherCompleted,required TResult Function( double ra,  double dec,  double raRaw,  double decRaw)  correction,required TResult Function()  looping,required TResult Function()  settling,required TResult Function()  calibrating,required TResult Function()  calibrationComplete,required TResult Function( double x,  double y)  starSelected,required TResult Function( String state)  appState,required TResult Function( double snr,  double starMass)  guideStats,}) {final _that = this;
switch (_that) {
case GuidingEvent_Connected():
return connected();case GuidingEvent_Disconnected():
return disconnected();case GuidingEvent_GuidingStarted():
return guidingStarted();case GuidingEvent_GuidingStopped():
return guidingStopped();case GuidingEvent_Paused():
return paused();case GuidingEvent_Resumed():
return resumed();case GuidingEvent_Settled():
return settled(_that.rms);case GuidingEvent_LostStar():
return lostStar();case GuidingEvent_DitherStarted():
return ditherStarted(_that.pixels);case GuidingEvent_DitherCompleted():
return ditherCompleted();case GuidingEvent_Correction():
return correction(_that.ra,_that.dec,_that.raRaw,_that.decRaw);case GuidingEvent_Looping():
return looping();case GuidingEvent_Settling():
return settling();case GuidingEvent_Calibrating():
return calibrating();case GuidingEvent_CalibrationComplete():
return calibrationComplete();case GuidingEvent_StarSelected():
return starSelected(_that.x,_that.y);case GuidingEvent_AppState():
return appState(_that.state);case GuidingEvent_GuideStats():
return guideStats(_that.snr,_that.starMass);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  connected,TResult? Function()?  disconnected,TResult? Function()?  guidingStarted,TResult? Function()?  guidingStopped,TResult? Function()?  paused,TResult? Function()?  resumed,TResult? Function( double rms)?  settled,TResult? Function()?  lostStar,TResult? Function( double pixels)?  ditherStarted,TResult? Function()?  ditherCompleted,TResult? Function( double ra,  double dec,  double raRaw,  double decRaw)?  correction,TResult? Function()?  looping,TResult? Function()?  settling,TResult? Function()?  calibrating,TResult? Function()?  calibrationComplete,TResult? Function( double x,  double y)?  starSelected,TResult? Function( String state)?  appState,TResult? Function( double snr,  double starMass)?  guideStats,}) {final _that = this;
switch (_that) {
case GuidingEvent_Connected() when connected != null:
return connected();case GuidingEvent_Disconnected() when disconnected != null:
return disconnected();case GuidingEvent_GuidingStarted() when guidingStarted != null:
return guidingStarted();case GuidingEvent_GuidingStopped() when guidingStopped != null:
return guidingStopped();case GuidingEvent_Paused() when paused != null:
return paused();case GuidingEvent_Resumed() when resumed != null:
return resumed();case GuidingEvent_Settled() when settled != null:
return settled(_that.rms);case GuidingEvent_LostStar() when lostStar != null:
return lostStar();case GuidingEvent_DitherStarted() when ditherStarted != null:
return ditherStarted(_that.pixels);case GuidingEvent_DitherCompleted() when ditherCompleted != null:
return ditherCompleted();case GuidingEvent_Correction() when correction != null:
return correction(_that.ra,_that.dec,_that.raRaw,_that.decRaw);case GuidingEvent_Looping() when looping != null:
return looping();case GuidingEvent_Settling() when settling != null:
return settling();case GuidingEvent_Calibrating() when calibrating != null:
return calibrating();case GuidingEvent_CalibrationComplete() when calibrationComplete != null:
return calibrationComplete();case GuidingEvent_StarSelected() when starSelected != null:
return starSelected(_that.x,_that.y);case GuidingEvent_AppState() when appState != null:
return appState(_that.state);case GuidingEvent_GuideStats() when guideStats != null:
return guideStats(_that.snr,_that.starMass);case _:
  return null;

}
}

}

/// @nodoc


class GuidingEvent_Connected extends GuidingEvent {
  const GuidingEvent_Connected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Connected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.connected()';
}


}




/// @nodoc


class GuidingEvent_Disconnected extends GuidingEvent {
  const GuidingEvent_Disconnected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.disconnected()';
}


}




/// @nodoc


class GuidingEvent_GuidingStarted extends GuidingEvent {
  const GuidingEvent_GuidingStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_GuidingStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.guidingStarted()';
}


}




/// @nodoc


class GuidingEvent_GuidingStopped extends GuidingEvent {
  const GuidingEvent_GuidingStopped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_GuidingStopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.guidingStopped()';
}


}




/// @nodoc


class GuidingEvent_Paused extends GuidingEvent {
  const GuidingEvent_Paused(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Paused);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.paused()';
}


}




/// @nodoc


class GuidingEvent_Resumed extends GuidingEvent {
  const GuidingEvent_Resumed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Resumed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.resumed()';
}


}




/// @nodoc


class GuidingEvent_Settled extends GuidingEvent {
  const GuidingEvent_Settled({required this.rms}): super._();
  

 final  double rms;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_SettledCopyWith<GuidingEvent_Settled> get copyWith => _$GuidingEvent_SettledCopyWithImpl<GuidingEvent_Settled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Settled&&(identical(other.rms, rms) || other.rms == rms));
}


@override
int get hashCode => Object.hash(runtimeType,rms);

@override
String toString() {
  return 'GuidingEvent.settled(rms: $rms)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_SettledCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_SettledCopyWith(GuidingEvent_Settled value, $Res Function(GuidingEvent_Settled) _then) = _$GuidingEvent_SettledCopyWithImpl;
@useResult
$Res call({
 double rms
});




}
/// @nodoc
class _$GuidingEvent_SettledCopyWithImpl<$Res>
    implements $GuidingEvent_SettledCopyWith<$Res> {
  _$GuidingEvent_SettledCopyWithImpl(this._self, this._then);

  final GuidingEvent_Settled _self;
  final $Res Function(GuidingEvent_Settled) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rms = null,}) {
  return _then(GuidingEvent_Settled(
rms: null == rms ? _self.rms : rms // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class GuidingEvent_LostStar extends GuidingEvent {
  const GuidingEvent_LostStar(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_LostStar);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.lostStar()';
}


}




/// @nodoc


class GuidingEvent_DitherStarted extends GuidingEvent {
  const GuidingEvent_DitherStarted({required this.pixels}): super._();
  

 final  double pixels;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_DitherStartedCopyWith<GuidingEvent_DitherStarted> get copyWith => _$GuidingEvent_DitherStartedCopyWithImpl<GuidingEvent_DitherStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_DitherStarted&&(identical(other.pixels, pixels) || other.pixels == pixels));
}


@override
int get hashCode => Object.hash(runtimeType,pixels);

@override
String toString() {
  return 'GuidingEvent.ditherStarted(pixels: $pixels)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_DitherStartedCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_DitherStartedCopyWith(GuidingEvent_DitherStarted value, $Res Function(GuidingEvent_DitherStarted) _then) = _$GuidingEvent_DitherStartedCopyWithImpl;
@useResult
$Res call({
 double pixels
});




}
/// @nodoc
class _$GuidingEvent_DitherStartedCopyWithImpl<$Res>
    implements $GuidingEvent_DitherStartedCopyWith<$Res> {
  _$GuidingEvent_DitherStartedCopyWithImpl(this._self, this._then);

  final GuidingEvent_DitherStarted _self;
  final $Res Function(GuidingEvent_DitherStarted) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pixels = null,}) {
  return _then(GuidingEvent_DitherStarted(
pixels: null == pixels ? _self.pixels : pixels // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class GuidingEvent_DitherCompleted extends GuidingEvent {
  const GuidingEvent_DitherCompleted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_DitherCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.ditherCompleted()';
}


}




/// @nodoc


class GuidingEvent_Correction extends GuidingEvent {
  const GuidingEvent_Correction({required this.ra, required this.dec, required this.raRaw, required this.decRaw}): super._();
  

 final  double ra;
 final  double dec;
 final  double raRaw;
 final  double decRaw;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_CorrectionCopyWith<GuidingEvent_Correction> get copyWith => _$GuidingEvent_CorrectionCopyWithImpl<GuidingEvent_Correction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Correction&&(identical(other.ra, ra) || other.ra == ra)&&(identical(other.dec, dec) || other.dec == dec)&&(identical(other.raRaw, raRaw) || other.raRaw == raRaw)&&(identical(other.decRaw, decRaw) || other.decRaw == decRaw));
}


@override
int get hashCode => Object.hash(runtimeType,ra,dec,raRaw,decRaw);

@override
String toString() {
  return 'GuidingEvent.correction(ra: $ra, dec: $dec, raRaw: $raRaw, decRaw: $decRaw)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_CorrectionCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_CorrectionCopyWith(GuidingEvent_Correction value, $Res Function(GuidingEvent_Correction) _then) = _$GuidingEvent_CorrectionCopyWithImpl;
@useResult
$Res call({
 double ra, double dec, double raRaw, double decRaw
});




}
/// @nodoc
class _$GuidingEvent_CorrectionCopyWithImpl<$Res>
    implements $GuidingEvent_CorrectionCopyWith<$Res> {
  _$GuidingEvent_CorrectionCopyWithImpl(this._self, this._then);

  final GuidingEvent_Correction _self;
  final $Res Function(GuidingEvent_Correction) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ra = null,Object? dec = null,Object? raRaw = null,Object? decRaw = null,}) {
  return _then(GuidingEvent_Correction(
ra: null == ra ? _self.ra : ra // ignore: cast_nullable_to_non_nullable
as double,dec: null == dec ? _self.dec : dec // ignore: cast_nullable_to_non_nullable
as double,raRaw: null == raRaw ? _self.raRaw : raRaw // ignore: cast_nullable_to_non_nullable
as double,decRaw: null == decRaw ? _self.decRaw : decRaw // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class GuidingEvent_Looping extends GuidingEvent {
  const GuidingEvent_Looping(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Looping);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.looping()';
}


}




/// @nodoc


class GuidingEvent_Settling extends GuidingEvent {
  const GuidingEvent_Settling(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Settling);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.settling()';
}


}




/// @nodoc


class GuidingEvent_Calibrating extends GuidingEvent {
  const GuidingEvent_Calibrating(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_Calibrating);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.calibrating()';
}


}




/// @nodoc


class GuidingEvent_CalibrationComplete extends GuidingEvent {
  const GuidingEvent_CalibrationComplete(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_CalibrationComplete);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GuidingEvent.calibrationComplete()';
}


}




/// @nodoc


class GuidingEvent_StarSelected extends GuidingEvent {
  const GuidingEvent_StarSelected({required this.x, required this.y}): super._();
  

 final  double x;
 final  double y;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_StarSelectedCopyWith<GuidingEvent_StarSelected> get copyWith => _$GuidingEvent_StarSelectedCopyWithImpl<GuidingEvent_StarSelected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_StarSelected&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}


@override
int get hashCode => Object.hash(runtimeType,x,y);

@override
String toString() {
  return 'GuidingEvent.starSelected(x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_StarSelectedCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_StarSelectedCopyWith(GuidingEvent_StarSelected value, $Res Function(GuidingEvent_StarSelected) _then) = _$GuidingEvent_StarSelectedCopyWithImpl;
@useResult
$Res call({
 double x, double y
});




}
/// @nodoc
class _$GuidingEvent_StarSelectedCopyWithImpl<$Res>
    implements $GuidingEvent_StarSelectedCopyWith<$Res> {
  _$GuidingEvent_StarSelectedCopyWithImpl(this._self, this._then);

  final GuidingEvent_StarSelected _self;
  final $Res Function(GuidingEvent_StarSelected) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,}) {
  return _then(GuidingEvent_StarSelected(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class GuidingEvent_AppState extends GuidingEvent {
  const GuidingEvent_AppState({required this.state}): super._();
  

 final  String state;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_AppStateCopyWith<GuidingEvent_AppState> get copyWith => _$GuidingEvent_AppStateCopyWithImpl<GuidingEvent_AppState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_AppState&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,state);

@override
String toString() {
  return 'GuidingEvent.appState(state: $state)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_AppStateCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_AppStateCopyWith(GuidingEvent_AppState value, $Res Function(GuidingEvent_AppState) _then) = _$GuidingEvent_AppStateCopyWithImpl;
@useResult
$Res call({
 String state
});




}
/// @nodoc
class _$GuidingEvent_AppStateCopyWithImpl<$Res>
    implements $GuidingEvent_AppStateCopyWith<$Res> {
  _$GuidingEvent_AppStateCopyWithImpl(this._self, this._then);

  final GuidingEvent_AppState _self;
  final $Res Function(GuidingEvent_AppState) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,}) {
  return _then(GuidingEvent_AppState(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class GuidingEvent_GuideStats extends GuidingEvent {
  const GuidingEvent_GuideStats({required this.snr, required this.starMass}): super._();
  

 final  double snr;
 final  double starMass;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuidingEvent_GuideStatsCopyWith<GuidingEvent_GuideStats> get copyWith => _$GuidingEvent_GuideStatsCopyWithImpl<GuidingEvent_GuideStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuidingEvent_GuideStats&&(identical(other.snr, snr) || other.snr == snr)&&(identical(other.starMass, starMass) || other.starMass == starMass));
}


@override
int get hashCode => Object.hash(runtimeType,snr,starMass);

@override
String toString() {
  return 'GuidingEvent.guideStats(snr: $snr, starMass: $starMass)';
}


}

/// @nodoc
abstract mixin class $GuidingEvent_GuideStatsCopyWith<$Res> implements $GuidingEventCopyWith<$Res> {
  factory $GuidingEvent_GuideStatsCopyWith(GuidingEvent_GuideStats value, $Res Function(GuidingEvent_GuideStats) _then) = _$GuidingEvent_GuideStatsCopyWithImpl;
@useResult
$Res call({
 double snr, double starMass
});




}
/// @nodoc
class _$GuidingEvent_GuideStatsCopyWithImpl<$Res>
    implements $GuidingEvent_GuideStatsCopyWith<$Res> {
  _$GuidingEvent_GuideStatsCopyWithImpl(this._self, this._then);

  final GuidingEvent_GuideStats _self;
  final $Res Function(GuidingEvent_GuideStats) _then;

/// Create a copy of GuidingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snr = null,Object? starMass = null,}) {
  return _then(GuidingEvent_GuideStats(
snr: null == snr ? _self.snr : snr // ignore: cast_nullable_to_non_nullable
as double,starMass: null == starMass ? _self.starMass : starMass // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$ImagingEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImagingEvent()';
}


}

/// @nodoc
class $ImagingEventCopyWith<$Res>  {
$ImagingEventCopyWith(ImagingEvent _, $Res Function(ImagingEvent) __);
}


/// Adds pattern-matching-related methods to [ImagingEvent].
extension ImagingEventPatterns on ImagingEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ImagingEvent_ExposureStarted value)?  exposureStarted,TResult Function( ImagingEvent_ExposureStartedWithFrame value)?  exposureStartedWithFrame,TResult Function( ImagingEvent_ExposureProgress value)?  exposureProgress,TResult Function( ImagingEvent_ExposureCompleted value)?  exposureCompleted,TResult Function( ImagingEvent_ExposureCompletedWithFrame value)?  exposureCompletedWithFrame,TResult Function( ImagingEvent_ExposureFailed value)?  exposureFailed,TResult Function( ImagingEvent_ExposureCancelled value)?  exposureCancelled,TResult Function( ImagingEvent_DownloadStarted value)?  downloadStarted,TResult Function( ImagingEvent_DownloadCompleted value)?  downloadCompleted,TResult Function( ImagingEvent_ImageReady value)?  imageReady,TResult Function( ImagingEvent_ImageSaved value)?  imageSaved,TResult Function( ImagingEvent_IntegrationProgress value)?  integrationProgress,TResult Function( ImagingEvent_TemperatureChanged value)?  temperatureChanged,TResult Function( ImagingEvent_ExposureComplete value)?  exposureComplete,TResult Function( ImagingEvent_ExposureFailedOld value)?  exposureFailedOld,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that);case ImagingEvent_ExposureStartedWithFrame() when exposureStartedWithFrame != null:
return exposureStartedWithFrame(_that);case ImagingEvent_ExposureProgress() when exposureProgress != null:
return exposureProgress(_that);case ImagingEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that);case ImagingEvent_ExposureCompletedWithFrame() when exposureCompletedWithFrame != null:
return exposureCompletedWithFrame(_that);case ImagingEvent_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that);case ImagingEvent_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled(_that);case ImagingEvent_DownloadStarted() when downloadStarted != null:
return downloadStarted(_that);case ImagingEvent_DownloadCompleted() when downloadCompleted != null:
return downloadCompleted(_that);case ImagingEvent_ImageReady() when imageReady != null:
return imageReady(_that);case ImagingEvent_ImageSaved() when imageSaved != null:
return imageSaved(_that);case ImagingEvent_IntegrationProgress() when integrationProgress != null:
return integrationProgress(_that);case ImagingEvent_TemperatureChanged() when temperatureChanged != null:
return temperatureChanged(_that);case ImagingEvent_ExposureComplete() when exposureComplete != null:
return exposureComplete(_that);case ImagingEvent_ExposureFailedOld() when exposureFailedOld != null:
return exposureFailedOld(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ImagingEvent_ExposureStarted value)  exposureStarted,required TResult Function( ImagingEvent_ExposureStartedWithFrame value)  exposureStartedWithFrame,required TResult Function( ImagingEvent_ExposureProgress value)  exposureProgress,required TResult Function( ImagingEvent_ExposureCompleted value)  exposureCompleted,required TResult Function( ImagingEvent_ExposureCompletedWithFrame value)  exposureCompletedWithFrame,required TResult Function( ImagingEvent_ExposureFailed value)  exposureFailed,required TResult Function( ImagingEvent_ExposureCancelled value)  exposureCancelled,required TResult Function( ImagingEvent_DownloadStarted value)  downloadStarted,required TResult Function( ImagingEvent_DownloadCompleted value)  downloadCompleted,required TResult Function( ImagingEvent_ImageReady value)  imageReady,required TResult Function( ImagingEvent_ImageSaved value)  imageSaved,required TResult Function( ImagingEvent_IntegrationProgress value)  integrationProgress,required TResult Function( ImagingEvent_TemperatureChanged value)  temperatureChanged,required TResult Function( ImagingEvent_ExposureComplete value)  exposureComplete,required TResult Function( ImagingEvent_ExposureFailedOld value)  exposureFailedOld,}){
final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted():
return exposureStarted(_that);case ImagingEvent_ExposureStartedWithFrame():
return exposureStartedWithFrame(_that);case ImagingEvent_ExposureProgress():
return exposureProgress(_that);case ImagingEvent_ExposureCompleted():
return exposureCompleted(_that);case ImagingEvent_ExposureCompletedWithFrame():
return exposureCompletedWithFrame(_that);case ImagingEvent_ExposureFailed():
return exposureFailed(_that);case ImagingEvent_ExposureCancelled():
return exposureCancelled(_that);case ImagingEvent_DownloadStarted():
return downloadStarted(_that);case ImagingEvent_DownloadCompleted():
return downloadCompleted(_that);case ImagingEvent_ImageReady():
return imageReady(_that);case ImagingEvent_ImageSaved():
return imageSaved(_that);case ImagingEvent_IntegrationProgress():
return integrationProgress(_that);case ImagingEvent_TemperatureChanged():
return temperatureChanged(_that);case ImagingEvent_ExposureComplete():
return exposureComplete(_that);case ImagingEvent_ExposureFailedOld():
return exposureFailedOld(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ImagingEvent_ExposureStarted value)?  exposureStarted,TResult? Function( ImagingEvent_ExposureStartedWithFrame value)?  exposureStartedWithFrame,TResult? Function( ImagingEvent_ExposureProgress value)?  exposureProgress,TResult? Function( ImagingEvent_ExposureCompleted value)?  exposureCompleted,TResult? Function( ImagingEvent_ExposureCompletedWithFrame value)?  exposureCompletedWithFrame,TResult? Function( ImagingEvent_ExposureFailed value)?  exposureFailed,TResult? Function( ImagingEvent_ExposureCancelled value)?  exposureCancelled,TResult? Function( ImagingEvent_DownloadStarted value)?  downloadStarted,TResult? Function( ImagingEvent_DownloadCompleted value)?  downloadCompleted,TResult? Function( ImagingEvent_ImageReady value)?  imageReady,TResult? Function( ImagingEvent_ImageSaved value)?  imageSaved,TResult? Function( ImagingEvent_IntegrationProgress value)?  integrationProgress,TResult? Function( ImagingEvent_TemperatureChanged value)?  temperatureChanged,TResult? Function( ImagingEvent_ExposureComplete value)?  exposureComplete,TResult? Function( ImagingEvent_ExposureFailedOld value)?  exposureFailedOld,}){
final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that);case ImagingEvent_ExposureStartedWithFrame() when exposureStartedWithFrame != null:
return exposureStartedWithFrame(_that);case ImagingEvent_ExposureProgress() when exposureProgress != null:
return exposureProgress(_that);case ImagingEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that);case ImagingEvent_ExposureCompletedWithFrame() when exposureCompletedWithFrame != null:
return exposureCompletedWithFrame(_that);case ImagingEvent_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that);case ImagingEvent_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled(_that);case ImagingEvent_DownloadStarted() when downloadStarted != null:
return downloadStarted(_that);case ImagingEvent_DownloadCompleted() when downloadCompleted != null:
return downloadCompleted(_that);case ImagingEvent_ImageReady() when imageReady != null:
return imageReady(_that);case ImagingEvent_ImageSaved() when imageSaved != null:
return imageSaved(_that);case ImagingEvent_IntegrationProgress() when integrationProgress != null:
return integrationProgress(_that);case ImagingEvent_TemperatureChanged() when temperatureChanged != null:
return temperatureChanged(_that);case ImagingEvent_ExposureComplete() when exposureComplete != null:
return exposureComplete(_that);case ImagingEvent_ExposureFailedOld() when exposureFailedOld != null:
return exposureFailedOld(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( double durationSecs,  FrameType frameType)?  exposureStarted,TResult Function( double durationSecs,  FrameType frameType,  int frameNumber,  int? totalFrames)?  exposureStartedWithFrame,TResult Function( double progress,  double remainingSecs)?  exposureProgress,TResult Function( String? filePath,  double hfr,  int starsDetected)?  exposureCompleted,TResult Function( int frameNumber,  int? totalFrames,  double hfr,  int starsDetected)?  exposureCompletedWithFrame,TResult Function( String error)?  exposureFailed,TResult Function()?  exposureCancelled,TResult Function()?  downloadStarted,TResult Function()?  downloadCompleted,TResult Function( int width,  int height)?  imageReady,TResult Function( String filePath)?  imageSaved,TResult Function( String phase,  double fraction,  int? framesDone,  int? framesTotal)?  integrationProgress,TResult Function( double tempCelsius,  double coolerPower)?  temperatureChanged,TResult Function( bool success)?  exposureComplete,TResult Function( String reason)?  exposureFailedOld,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that.durationSecs,_that.frameType);case ImagingEvent_ExposureStartedWithFrame() when exposureStartedWithFrame != null:
return exposureStartedWithFrame(_that.durationSecs,_that.frameType,_that.frameNumber,_that.totalFrames);case ImagingEvent_ExposureProgress() when exposureProgress != null:
return exposureProgress(_that.progress,_that.remainingSecs);case ImagingEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that.filePath,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureCompletedWithFrame() when exposureCompletedWithFrame != null:
return exposureCompletedWithFrame(_that.frameNumber,_that.totalFrames,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that.error);case ImagingEvent_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled();case ImagingEvent_DownloadStarted() when downloadStarted != null:
return downloadStarted();case ImagingEvent_DownloadCompleted() when downloadCompleted != null:
return downloadCompleted();case ImagingEvent_ImageReady() when imageReady != null:
return imageReady(_that.width,_that.height);case ImagingEvent_ImageSaved() when imageSaved != null:
return imageSaved(_that.filePath);case ImagingEvent_IntegrationProgress() when integrationProgress != null:
return integrationProgress(_that.phase,_that.fraction,_that.framesDone,_that.framesTotal);case ImagingEvent_TemperatureChanged() when temperatureChanged != null:
return temperatureChanged(_that.tempCelsius,_that.coolerPower);case ImagingEvent_ExposureComplete() when exposureComplete != null:
return exposureComplete(_that.success);case ImagingEvent_ExposureFailedOld() when exposureFailedOld != null:
return exposureFailedOld(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( double durationSecs,  FrameType frameType)  exposureStarted,required TResult Function( double durationSecs,  FrameType frameType,  int frameNumber,  int? totalFrames)  exposureStartedWithFrame,required TResult Function( double progress,  double remainingSecs)  exposureProgress,required TResult Function( String? filePath,  double hfr,  int starsDetected)  exposureCompleted,required TResult Function( int frameNumber,  int? totalFrames,  double hfr,  int starsDetected)  exposureCompletedWithFrame,required TResult Function( String error)  exposureFailed,required TResult Function()  exposureCancelled,required TResult Function()  downloadStarted,required TResult Function()  downloadCompleted,required TResult Function( int width,  int height)  imageReady,required TResult Function( String filePath)  imageSaved,required TResult Function( String phase,  double fraction,  int? framesDone,  int? framesTotal)  integrationProgress,required TResult Function( double tempCelsius,  double coolerPower)  temperatureChanged,required TResult Function( bool success)  exposureComplete,required TResult Function( String reason)  exposureFailedOld,}) {final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted():
return exposureStarted(_that.durationSecs,_that.frameType);case ImagingEvent_ExposureStartedWithFrame():
return exposureStartedWithFrame(_that.durationSecs,_that.frameType,_that.frameNumber,_that.totalFrames);case ImagingEvent_ExposureProgress():
return exposureProgress(_that.progress,_that.remainingSecs);case ImagingEvent_ExposureCompleted():
return exposureCompleted(_that.filePath,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureCompletedWithFrame():
return exposureCompletedWithFrame(_that.frameNumber,_that.totalFrames,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureFailed():
return exposureFailed(_that.error);case ImagingEvent_ExposureCancelled():
return exposureCancelled();case ImagingEvent_DownloadStarted():
return downloadStarted();case ImagingEvent_DownloadCompleted():
return downloadCompleted();case ImagingEvent_ImageReady():
return imageReady(_that.width,_that.height);case ImagingEvent_ImageSaved():
return imageSaved(_that.filePath);case ImagingEvent_IntegrationProgress():
return integrationProgress(_that.phase,_that.fraction,_that.framesDone,_that.framesTotal);case ImagingEvent_TemperatureChanged():
return temperatureChanged(_that.tempCelsius,_that.coolerPower);case ImagingEvent_ExposureComplete():
return exposureComplete(_that.success);case ImagingEvent_ExposureFailedOld():
return exposureFailedOld(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( double durationSecs,  FrameType frameType)?  exposureStarted,TResult? Function( double durationSecs,  FrameType frameType,  int frameNumber,  int? totalFrames)?  exposureStartedWithFrame,TResult? Function( double progress,  double remainingSecs)?  exposureProgress,TResult? Function( String? filePath,  double hfr,  int starsDetected)?  exposureCompleted,TResult? Function( int frameNumber,  int? totalFrames,  double hfr,  int starsDetected)?  exposureCompletedWithFrame,TResult? Function( String error)?  exposureFailed,TResult? Function()?  exposureCancelled,TResult? Function()?  downloadStarted,TResult? Function()?  downloadCompleted,TResult? Function( int width,  int height)?  imageReady,TResult? Function( String filePath)?  imageSaved,TResult? Function( String phase,  double fraction,  int? framesDone,  int? framesTotal)?  integrationProgress,TResult? Function( double tempCelsius,  double coolerPower)?  temperatureChanged,TResult? Function( bool success)?  exposureComplete,TResult? Function( String reason)?  exposureFailedOld,}) {final _that = this;
switch (_that) {
case ImagingEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that.durationSecs,_that.frameType);case ImagingEvent_ExposureStartedWithFrame() when exposureStartedWithFrame != null:
return exposureStartedWithFrame(_that.durationSecs,_that.frameType,_that.frameNumber,_that.totalFrames);case ImagingEvent_ExposureProgress() when exposureProgress != null:
return exposureProgress(_that.progress,_that.remainingSecs);case ImagingEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that.filePath,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureCompletedWithFrame() when exposureCompletedWithFrame != null:
return exposureCompletedWithFrame(_that.frameNumber,_that.totalFrames,_that.hfr,_that.starsDetected);case ImagingEvent_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that.error);case ImagingEvent_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled();case ImagingEvent_DownloadStarted() when downloadStarted != null:
return downloadStarted();case ImagingEvent_DownloadCompleted() when downloadCompleted != null:
return downloadCompleted();case ImagingEvent_ImageReady() when imageReady != null:
return imageReady(_that.width,_that.height);case ImagingEvent_ImageSaved() when imageSaved != null:
return imageSaved(_that.filePath);case ImagingEvent_IntegrationProgress() when integrationProgress != null:
return integrationProgress(_that.phase,_that.fraction,_that.framesDone,_that.framesTotal);case ImagingEvent_TemperatureChanged() when temperatureChanged != null:
return temperatureChanged(_that.tempCelsius,_that.coolerPower);case ImagingEvent_ExposureComplete() when exposureComplete != null:
return exposureComplete(_that.success);case ImagingEvent_ExposureFailedOld() when exposureFailedOld != null:
return exposureFailedOld(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ImagingEvent_ExposureStarted extends ImagingEvent {
  const ImagingEvent_ExposureStarted({required this.durationSecs, required this.frameType}): super._();
  

 final  double durationSecs;
 final  FrameType frameType;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureStartedCopyWith<ImagingEvent_ExposureStarted> get copyWith => _$ImagingEvent_ExposureStartedCopyWithImpl<ImagingEvent_ExposureStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureStarted&&(identical(other.durationSecs, durationSecs) || other.durationSecs == durationSecs)&&(identical(other.frameType, frameType) || other.frameType == frameType));
}


@override
int get hashCode => Object.hash(runtimeType,durationSecs,frameType);

@override
String toString() {
  return 'ImagingEvent.exposureStarted(durationSecs: $durationSecs, frameType: $frameType)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureStartedCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureStartedCopyWith(ImagingEvent_ExposureStarted value, $Res Function(ImagingEvent_ExposureStarted) _then) = _$ImagingEvent_ExposureStartedCopyWithImpl;
@useResult
$Res call({
 double durationSecs, FrameType frameType
});




}
/// @nodoc
class _$ImagingEvent_ExposureStartedCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureStartedCopyWith<$Res> {
  _$ImagingEvent_ExposureStartedCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureStarted _self;
  final $Res Function(ImagingEvent_ExposureStarted) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationSecs = null,Object? frameType = null,}) {
  return _then(ImagingEvent_ExposureStarted(
durationSecs: null == durationSecs ? _self.durationSecs : durationSecs // ignore: cast_nullable_to_non_nullable
as double,frameType: null == frameType ? _self.frameType : frameType // ignore: cast_nullable_to_non_nullable
as FrameType,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureStartedWithFrame extends ImagingEvent {
  const ImagingEvent_ExposureStartedWithFrame({required this.durationSecs, required this.frameType, required this.frameNumber, this.totalFrames}): super._();
  

 final  double durationSecs;
 final  FrameType frameType;
 final  int frameNumber;
 final  int? totalFrames;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureStartedWithFrameCopyWith<ImagingEvent_ExposureStartedWithFrame> get copyWith => _$ImagingEvent_ExposureStartedWithFrameCopyWithImpl<ImagingEvent_ExposureStartedWithFrame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureStartedWithFrame&&(identical(other.durationSecs, durationSecs) || other.durationSecs == durationSecs)&&(identical(other.frameType, frameType) || other.frameType == frameType)&&(identical(other.frameNumber, frameNumber) || other.frameNumber == frameNumber)&&(identical(other.totalFrames, totalFrames) || other.totalFrames == totalFrames));
}


@override
int get hashCode => Object.hash(runtimeType,durationSecs,frameType,frameNumber,totalFrames);

@override
String toString() {
  return 'ImagingEvent.exposureStartedWithFrame(durationSecs: $durationSecs, frameType: $frameType, frameNumber: $frameNumber, totalFrames: $totalFrames)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureStartedWithFrameCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureStartedWithFrameCopyWith(ImagingEvent_ExposureStartedWithFrame value, $Res Function(ImagingEvent_ExposureStartedWithFrame) _then) = _$ImagingEvent_ExposureStartedWithFrameCopyWithImpl;
@useResult
$Res call({
 double durationSecs, FrameType frameType, int frameNumber, int? totalFrames
});




}
/// @nodoc
class _$ImagingEvent_ExposureStartedWithFrameCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureStartedWithFrameCopyWith<$Res> {
  _$ImagingEvent_ExposureStartedWithFrameCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureStartedWithFrame _self;
  final $Res Function(ImagingEvent_ExposureStartedWithFrame) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationSecs = null,Object? frameType = null,Object? frameNumber = null,Object? totalFrames = freezed,}) {
  return _then(ImagingEvent_ExposureStartedWithFrame(
durationSecs: null == durationSecs ? _self.durationSecs : durationSecs // ignore: cast_nullable_to_non_nullable
as double,frameType: null == frameType ? _self.frameType : frameType // ignore: cast_nullable_to_non_nullable
as FrameType,frameNumber: null == frameNumber ? _self.frameNumber : frameNumber // ignore: cast_nullable_to_non_nullable
as int,totalFrames: freezed == totalFrames ? _self.totalFrames : totalFrames // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureProgress extends ImagingEvent {
  const ImagingEvent_ExposureProgress({required this.progress, required this.remainingSecs}): super._();
  

 final  double progress;
 final  double remainingSecs;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureProgressCopyWith<ImagingEvent_ExposureProgress> get copyWith => _$ImagingEvent_ExposureProgressCopyWithImpl<ImagingEvent_ExposureProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureProgress&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.remainingSecs, remainingSecs) || other.remainingSecs == remainingSecs));
}


@override
int get hashCode => Object.hash(runtimeType,progress,remainingSecs);

@override
String toString() {
  return 'ImagingEvent.exposureProgress(progress: $progress, remainingSecs: $remainingSecs)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureProgressCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureProgressCopyWith(ImagingEvent_ExposureProgress value, $Res Function(ImagingEvent_ExposureProgress) _then) = _$ImagingEvent_ExposureProgressCopyWithImpl;
@useResult
$Res call({
 double progress, double remainingSecs
});




}
/// @nodoc
class _$ImagingEvent_ExposureProgressCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureProgressCopyWith<$Res> {
  _$ImagingEvent_ExposureProgressCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureProgress _self;
  final $Res Function(ImagingEvent_ExposureProgress) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,Object? remainingSecs = null,}) {
  return _then(ImagingEvent_ExposureProgress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,remainingSecs: null == remainingSecs ? _self.remainingSecs : remainingSecs // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureCompleted extends ImagingEvent {
  const ImagingEvent_ExposureCompleted({this.filePath, required this.hfr, required this.starsDetected}): super._();
  

 final  String? filePath;
 final  double hfr;
 final  int starsDetected;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureCompletedCopyWith<ImagingEvent_ExposureCompleted> get copyWith => _$ImagingEvent_ExposureCompletedCopyWithImpl<ImagingEvent_ExposureCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureCompleted&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.hfr, hfr) || other.hfr == hfr)&&(identical(other.starsDetected, starsDetected) || other.starsDetected == starsDetected));
}


@override
int get hashCode => Object.hash(runtimeType,filePath,hfr,starsDetected);

@override
String toString() {
  return 'ImagingEvent.exposureCompleted(filePath: $filePath, hfr: $hfr, starsDetected: $starsDetected)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureCompletedCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureCompletedCopyWith(ImagingEvent_ExposureCompleted value, $Res Function(ImagingEvent_ExposureCompleted) _then) = _$ImagingEvent_ExposureCompletedCopyWithImpl;
@useResult
$Res call({
 String? filePath, double hfr, int starsDetected
});




}
/// @nodoc
class _$ImagingEvent_ExposureCompletedCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureCompletedCopyWith<$Res> {
  _$ImagingEvent_ExposureCompletedCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureCompleted _self;
  final $Res Function(ImagingEvent_ExposureCompleted) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? filePath = freezed,Object? hfr = null,Object? starsDetected = null,}) {
  return _then(ImagingEvent_ExposureCompleted(
filePath: freezed == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String?,hfr: null == hfr ? _self.hfr : hfr // ignore: cast_nullable_to_non_nullable
as double,starsDetected: null == starsDetected ? _self.starsDetected : starsDetected // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureCompletedWithFrame extends ImagingEvent {
  const ImagingEvent_ExposureCompletedWithFrame({required this.frameNumber, this.totalFrames, required this.hfr, required this.starsDetected}): super._();
  

 final  int frameNumber;
 final  int? totalFrames;
 final  double hfr;
 final  int starsDetected;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureCompletedWithFrameCopyWith<ImagingEvent_ExposureCompletedWithFrame> get copyWith => _$ImagingEvent_ExposureCompletedWithFrameCopyWithImpl<ImagingEvent_ExposureCompletedWithFrame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureCompletedWithFrame&&(identical(other.frameNumber, frameNumber) || other.frameNumber == frameNumber)&&(identical(other.totalFrames, totalFrames) || other.totalFrames == totalFrames)&&(identical(other.hfr, hfr) || other.hfr == hfr)&&(identical(other.starsDetected, starsDetected) || other.starsDetected == starsDetected));
}


@override
int get hashCode => Object.hash(runtimeType,frameNumber,totalFrames,hfr,starsDetected);

@override
String toString() {
  return 'ImagingEvent.exposureCompletedWithFrame(frameNumber: $frameNumber, totalFrames: $totalFrames, hfr: $hfr, starsDetected: $starsDetected)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureCompletedWithFrameCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureCompletedWithFrameCopyWith(ImagingEvent_ExposureCompletedWithFrame value, $Res Function(ImagingEvent_ExposureCompletedWithFrame) _then) = _$ImagingEvent_ExposureCompletedWithFrameCopyWithImpl;
@useResult
$Res call({
 int frameNumber, int? totalFrames, double hfr, int starsDetected
});




}
/// @nodoc
class _$ImagingEvent_ExposureCompletedWithFrameCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureCompletedWithFrameCopyWith<$Res> {
  _$ImagingEvent_ExposureCompletedWithFrameCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureCompletedWithFrame _self;
  final $Res Function(ImagingEvent_ExposureCompletedWithFrame) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? frameNumber = null,Object? totalFrames = freezed,Object? hfr = null,Object? starsDetected = null,}) {
  return _then(ImagingEvent_ExposureCompletedWithFrame(
frameNumber: null == frameNumber ? _self.frameNumber : frameNumber // ignore: cast_nullable_to_non_nullable
as int,totalFrames: freezed == totalFrames ? _self.totalFrames : totalFrames // ignore: cast_nullable_to_non_nullable
as int?,hfr: null == hfr ? _self.hfr : hfr // ignore: cast_nullable_to_non_nullable
as double,starsDetected: null == starsDetected ? _self.starsDetected : starsDetected // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureFailed extends ImagingEvent {
  const ImagingEvent_ExposureFailed({required this.error}): super._();
  

 final  String error;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureFailedCopyWith<ImagingEvent_ExposureFailed> get copyWith => _$ImagingEvent_ExposureFailedCopyWithImpl<ImagingEvent_ExposureFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ImagingEvent.exposureFailed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureFailedCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureFailedCopyWith(ImagingEvent_ExposureFailed value, $Res Function(ImagingEvent_ExposureFailed) _then) = _$ImagingEvent_ExposureFailedCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$ImagingEvent_ExposureFailedCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureFailedCopyWith<$Res> {
  _$ImagingEvent_ExposureFailedCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureFailed _self;
  final $Res Function(ImagingEvent_ExposureFailed) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ImagingEvent_ExposureFailed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureCancelled extends ImagingEvent {
  const ImagingEvent_ExposureCancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureCancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImagingEvent.exposureCancelled()';
}


}




/// @nodoc


class ImagingEvent_DownloadStarted extends ImagingEvent {
  const ImagingEvent_DownloadStarted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_DownloadStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImagingEvent.downloadStarted()';
}


}




/// @nodoc


class ImagingEvent_DownloadCompleted extends ImagingEvent {
  const ImagingEvent_DownloadCompleted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_DownloadCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImagingEvent.downloadCompleted()';
}


}




/// @nodoc


class ImagingEvent_ImageReady extends ImagingEvent {
  const ImagingEvent_ImageReady({required this.width, required this.height}): super._();
  

 final  int width;
 final  int height;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ImageReadyCopyWith<ImagingEvent_ImageReady> get copyWith => _$ImagingEvent_ImageReadyCopyWithImpl<ImagingEvent_ImageReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ImageReady&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,width,height);

@override
String toString() {
  return 'ImagingEvent.imageReady(width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ImageReadyCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ImageReadyCopyWith(ImagingEvent_ImageReady value, $Res Function(ImagingEvent_ImageReady) _then) = _$ImagingEvent_ImageReadyCopyWithImpl;
@useResult
$Res call({
 int width, int height
});




}
/// @nodoc
class _$ImagingEvent_ImageReadyCopyWithImpl<$Res>
    implements $ImagingEvent_ImageReadyCopyWith<$Res> {
  _$ImagingEvent_ImageReadyCopyWithImpl(this._self, this._then);

  final ImagingEvent_ImageReady _self;
  final $Res Function(ImagingEvent_ImageReady) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? width = null,Object? height = null,}) {
  return _then(ImagingEvent_ImageReady(
width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImagingEvent_ImageSaved extends ImagingEvent {
  const ImagingEvent_ImageSaved({required this.filePath}): super._();
  

 final  String filePath;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ImageSavedCopyWith<ImagingEvent_ImageSaved> get copyWith => _$ImagingEvent_ImageSavedCopyWithImpl<ImagingEvent_ImageSaved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ImageSaved&&(identical(other.filePath, filePath) || other.filePath == filePath));
}


@override
int get hashCode => Object.hash(runtimeType,filePath);

@override
String toString() {
  return 'ImagingEvent.imageSaved(filePath: $filePath)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ImageSavedCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ImageSavedCopyWith(ImagingEvent_ImageSaved value, $Res Function(ImagingEvent_ImageSaved) _then) = _$ImagingEvent_ImageSavedCopyWithImpl;
@useResult
$Res call({
 String filePath
});




}
/// @nodoc
class _$ImagingEvent_ImageSavedCopyWithImpl<$Res>
    implements $ImagingEvent_ImageSavedCopyWith<$Res> {
  _$ImagingEvent_ImageSavedCopyWithImpl(this._self, this._then);

  final ImagingEvent_ImageSaved _self;
  final $Res Function(ImagingEvent_ImageSaved) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? filePath = null,}) {
  return _then(ImagingEvent_ImageSaved(
filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ImagingEvent_IntegrationProgress extends ImagingEvent {
  const ImagingEvent_IntegrationProgress({required this.phase, required this.fraction, this.framesDone, this.framesTotal}): super._();
  

/// Current pipeline phase: one of `"calibrating"`, `"registering"`,
/// `"normalizing"`, `"weighting"`, `"integrating"`, `"writing"`, or
/// `"preview"`.
 final  String phase;
/// Overall completion fraction in `0.0..=1.0`, monotonically advancing
/// across the phase sequence above.
 final  double fraction;
/// Frames processed so far in the current phase (`None` when the phase
/// has no per-frame granularity, e.g. `integrating`/`writing`).
 final  int? framesDone;
/// Total frames in the current phase (`None` when N/A).
 final  int? framesTotal;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_IntegrationProgressCopyWith<ImagingEvent_IntegrationProgress> get copyWith => _$ImagingEvent_IntegrationProgressCopyWithImpl<ImagingEvent_IntegrationProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_IntegrationProgress&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.fraction, fraction) || other.fraction == fraction)&&(identical(other.framesDone, framesDone) || other.framesDone == framesDone)&&(identical(other.framesTotal, framesTotal) || other.framesTotal == framesTotal));
}


@override
int get hashCode => Object.hash(runtimeType,phase,fraction,framesDone,framesTotal);

@override
String toString() {
  return 'ImagingEvent.integrationProgress(phase: $phase, fraction: $fraction, framesDone: $framesDone, framesTotal: $framesTotal)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_IntegrationProgressCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_IntegrationProgressCopyWith(ImagingEvent_IntegrationProgress value, $Res Function(ImagingEvent_IntegrationProgress) _then) = _$ImagingEvent_IntegrationProgressCopyWithImpl;
@useResult
$Res call({
 String phase, double fraction, int? framesDone, int? framesTotal
});




}
/// @nodoc
class _$ImagingEvent_IntegrationProgressCopyWithImpl<$Res>
    implements $ImagingEvent_IntegrationProgressCopyWith<$Res> {
  _$ImagingEvent_IntegrationProgressCopyWithImpl(this._self, this._then);

  final ImagingEvent_IntegrationProgress _self;
  final $Res Function(ImagingEvent_IntegrationProgress) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? fraction = null,Object? framesDone = freezed,Object? framesTotal = freezed,}) {
  return _then(ImagingEvent_IntegrationProgress(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,fraction: null == fraction ? _self.fraction : fraction // ignore: cast_nullable_to_non_nullable
as double,framesDone: freezed == framesDone ? _self.framesDone : framesDone // ignore: cast_nullable_to_non_nullable
as int?,framesTotal: freezed == framesTotal ? _self.framesTotal : framesTotal // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ImagingEvent_TemperatureChanged extends ImagingEvent {
  const ImagingEvent_TemperatureChanged({required this.tempCelsius, required this.coolerPower}): super._();
  

 final  double tempCelsius;
 final  double coolerPower;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_TemperatureChangedCopyWith<ImagingEvent_TemperatureChanged> get copyWith => _$ImagingEvent_TemperatureChangedCopyWithImpl<ImagingEvent_TemperatureChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_TemperatureChanged&&(identical(other.tempCelsius, tempCelsius) || other.tempCelsius == tempCelsius)&&(identical(other.coolerPower, coolerPower) || other.coolerPower == coolerPower));
}


@override
int get hashCode => Object.hash(runtimeType,tempCelsius,coolerPower);

@override
String toString() {
  return 'ImagingEvent.temperatureChanged(tempCelsius: $tempCelsius, coolerPower: $coolerPower)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_TemperatureChangedCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_TemperatureChangedCopyWith(ImagingEvent_TemperatureChanged value, $Res Function(ImagingEvent_TemperatureChanged) _then) = _$ImagingEvent_TemperatureChangedCopyWithImpl;
@useResult
$Res call({
 double tempCelsius, double coolerPower
});




}
/// @nodoc
class _$ImagingEvent_TemperatureChangedCopyWithImpl<$Res>
    implements $ImagingEvent_TemperatureChangedCopyWith<$Res> {
  _$ImagingEvent_TemperatureChangedCopyWithImpl(this._self, this._then);

  final ImagingEvent_TemperatureChanged _self;
  final $Res Function(ImagingEvent_TemperatureChanged) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? tempCelsius = null,Object? coolerPower = null,}) {
  return _then(ImagingEvent_TemperatureChanged(
tempCelsius: null == tempCelsius ? _self.tempCelsius : tempCelsius // ignore: cast_nullable_to_non_nullable
as double,coolerPower: null == coolerPower ? _self.coolerPower : coolerPower // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureComplete extends ImagingEvent {
  const ImagingEvent_ExposureComplete({required this.success}): super._();
  

 final  bool success;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureCompleteCopyWith<ImagingEvent_ExposureComplete> get copyWith => _$ImagingEvent_ExposureCompleteCopyWithImpl<ImagingEvent_ExposureComplete>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureComplete&&(identical(other.success, success) || other.success == success));
}


@override
int get hashCode => Object.hash(runtimeType,success);

@override
String toString() {
  return 'ImagingEvent.exposureComplete(success: $success)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureCompleteCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureCompleteCopyWith(ImagingEvent_ExposureComplete value, $Res Function(ImagingEvent_ExposureComplete) _then) = _$ImagingEvent_ExposureCompleteCopyWithImpl;
@useResult
$Res call({
 bool success
});




}
/// @nodoc
class _$ImagingEvent_ExposureCompleteCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureCompleteCopyWith<$Res> {
  _$ImagingEvent_ExposureCompleteCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureComplete _self;
  final $Res Function(ImagingEvent_ExposureComplete) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? success = null,}) {
  return _then(ImagingEvent_ExposureComplete(
success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ImagingEvent_ExposureFailedOld extends ImagingEvent {
  const ImagingEvent_ExposureFailedOld({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImagingEvent_ExposureFailedOldCopyWith<ImagingEvent_ExposureFailedOld> get copyWith => _$ImagingEvent_ExposureFailedOldCopyWithImpl<ImagingEvent_ExposureFailedOld>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImagingEvent_ExposureFailedOld&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'ImagingEvent.exposureFailedOld(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ImagingEvent_ExposureFailedOldCopyWith<$Res> implements $ImagingEventCopyWith<$Res> {
  factory $ImagingEvent_ExposureFailedOldCopyWith(ImagingEvent_ExposureFailedOld value, $Res Function(ImagingEvent_ExposureFailedOld) _then) = _$ImagingEvent_ExposureFailedOldCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ImagingEvent_ExposureFailedOldCopyWithImpl<$Res>
    implements $ImagingEvent_ExposureFailedOldCopyWith<$Res> {
  _$ImagingEvent_ExposureFailedOldCopyWithImpl(this._self, this._then);

  final ImagingEvent_ExposureFailedOld _self;
  final $Res Function(ImagingEvent_ExposureFailedOld) _then;

/// Create a copy of ImagingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ImagingEvent_ExposureFailedOld(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SafetyEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SafetyEvent()';
}


}

/// @nodoc
class $SafetyEventCopyWith<$Res>  {
$SafetyEventCopyWith(SafetyEvent _, $Res Function(SafetyEvent) __);
}


/// Adds pattern-matching-related methods to [SafetyEvent].
extension SafetyEventPatterns on SafetyEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SafetyEvent_WeatherUnsafe value)?  weatherUnsafe,TResult Function( SafetyEvent_WeatherSafe value)?  weatherSafe,TResult Function( SafetyEvent_EmergencyStop value)?  emergencyStop,TResult Function( SafetyEvent_ParkInitiated value)?  parkInitiated,TResult Function( SafetyEvent_ParkCompleted value)?  parkCompleted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe() when weatherUnsafe != null:
return weatherUnsafe(_that);case SafetyEvent_WeatherSafe() when weatherSafe != null:
return weatherSafe(_that);case SafetyEvent_EmergencyStop() when emergencyStop != null:
return emergencyStop(_that);case SafetyEvent_ParkInitiated() when parkInitiated != null:
return parkInitiated(_that);case SafetyEvent_ParkCompleted() when parkCompleted != null:
return parkCompleted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SafetyEvent_WeatherUnsafe value)  weatherUnsafe,required TResult Function( SafetyEvent_WeatherSafe value)  weatherSafe,required TResult Function( SafetyEvent_EmergencyStop value)  emergencyStop,required TResult Function( SafetyEvent_ParkInitiated value)  parkInitiated,required TResult Function( SafetyEvent_ParkCompleted value)  parkCompleted,}){
final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe():
return weatherUnsafe(_that);case SafetyEvent_WeatherSafe():
return weatherSafe(_that);case SafetyEvent_EmergencyStop():
return emergencyStop(_that);case SafetyEvent_ParkInitiated():
return parkInitiated(_that);case SafetyEvent_ParkCompleted():
return parkCompleted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SafetyEvent_WeatherUnsafe value)?  weatherUnsafe,TResult? Function( SafetyEvent_WeatherSafe value)?  weatherSafe,TResult? Function( SafetyEvent_EmergencyStop value)?  emergencyStop,TResult? Function( SafetyEvent_ParkInitiated value)?  parkInitiated,TResult? Function( SafetyEvent_ParkCompleted value)?  parkCompleted,}){
final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe() when weatherUnsafe != null:
return weatherUnsafe(_that);case SafetyEvent_WeatherSafe() when weatherSafe != null:
return weatherSafe(_that);case SafetyEvent_EmergencyStop() when emergencyStop != null:
return emergencyStop(_that);case SafetyEvent_ParkInitiated() when parkInitiated != null:
return parkInitiated(_that);case SafetyEvent_ParkCompleted() when parkCompleted != null:
return parkCompleted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String reason)?  weatherUnsafe,TResult Function()?  weatherSafe,TResult Function( String reason)?  emergencyStop,TResult Function( String reason)?  parkInitiated,TResult Function()?  parkCompleted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe() when weatherUnsafe != null:
return weatherUnsafe(_that.reason);case SafetyEvent_WeatherSafe() when weatherSafe != null:
return weatherSafe();case SafetyEvent_EmergencyStop() when emergencyStop != null:
return emergencyStop(_that.reason);case SafetyEvent_ParkInitiated() when parkInitiated != null:
return parkInitiated(_that.reason);case SafetyEvent_ParkCompleted() when parkCompleted != null:
return parkCompleted();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String reason)  weatherUnsafe,required TResult Function()  weatherSafe,required TResult Function( String reason)  emergencyStop,required TResult Function( String reason)  parkInitiated,required TResult Function()  parkCompleted,}) {final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe():
return weatherUnsafe(_that.reason);case SafetyEvent_WeatherSafe():
return weatherSafe();case SafetyEvent_EmergencyStop():
return emergencyStop(_that.reason);case SafetyEvent_ParkInitiated():
return parkInitiated(_that.reason);case SafetyEvent_ParkCompleted():
return parkCompleted();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String reason)?  weatherUnsafe,TResult? Function()?  weatherSafe,TResult? Function( String reason)?  emergencyStop,TResult? Function( String reason)?  parkInitiated,TResult? Function()?  parkCompleted,}) {final _that = this;
switch (_that) {
case SafetyEvent_WeatherUnsafe() when weatherUnsafe != null:
return weatherUnsafe(_that.reason);case SafetyEvent_WeatherSafe() when weatherSafe != null:
return weatherSafe();case SafetyEvent_EmergencyStop() when emergencyStop != null:
return emergencyStop(_that.reason);case SafetyEvent_ParkInitiated() when parkInitiated != null:
return parkInitiated(_that.reason);case SafetyEvent_ParkCompleted() when parkCompleted != null:
return parkCompleted();case _:
  return null;

}
}

}

/// @nodoc


class SafetyEvent_WeatherUnsafe extends SafetyEvent {
  const SafetyEvent_WeatherUnsafe({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafetyEvent_WeatherUnsafeCopyWith<SafetyEvent_WeatherUnsafe> get copyWith => _$SafetyEvent_WeatherUnsafeCopyWithImpl<SafetyEvent_WeatherUnsafe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent_WeatherUnsafe&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SafetyEvent.weatherUnsafe(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SafetyEvent_WeatherUnsafeCopyWith<$Res> implements $SafetyEventCopyWith<$Res> {
  factory $SafetyEvent_WeatherUnsafeCopyWith(SafetyEvent_WeatherUnsafe value, $Res Function(SafetyEvent_WeatherUnsafe) _then) = _$SafetyEvent_WeatherUnsafeCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SafetyEvent_WeatherUnsafeCopyWithImpl<$Res>
    implements $SafetyEvent_WeatherUnsafeCopyWith<$Res> {
  _$SafetyEvent_WeatherUnsafeCopyWithImpl(this._self, this._then);

  final SafetyEvent_WeatherUnsafe _self;
  final $Res Function(SafetyEvent_WeatherUnsafe) _then;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SafetyEvent_WeatherUnsafe(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SafetyEvent_WeatherSafe extends SafetyEvent {
  const SafetyEvent_WeatherSafe(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent_WeatherSafe);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SafetyEvent.weatherSafe()';
}


}




/// @nodoc


class SafetyEvent_EmergencyStop extends SafetyEvent {
  const SafetyEvent_EmergencyStop({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafetyEvent_EmergencyStopCopyWith<SafetyEvent_EmergencyStop> get copyWith => _$SafetyEvent_EmergencyStopCopyWithImpl<SafetyEvent_EmergencyStop>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent_EmergencyStop&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SafetyEvent.emergencyStop(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SafetyEvent_EmergencyStopCopyWith<$Res> implements $SafetyEventCopyWith<$Res> {
  factory $SafetyEvent_EmergencyStopCopyWith(SafetyEvent_EmergencyStop value, $Res Function(SafetyEvent_EmergencyStop) _then) = _$SafetyEvent_EmergencyStopCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SafetyEvent_EmergencyStopCopyWithImpl<$Res>
    implements $SafetyEvent_EmergencyStopCopyWith<$Res> {
  _$SafetyEvent_EmergencyStopCopyWithImpl(this._self, this._then);

  final SafetyEvent_EmergencyStop _self;
  final $Res Function(SafetyEvent_EmergencyStop) _then;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SafetyEvent_EmergencyStop(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SafetyEvent_ParkInitiated extends SafetyEvent {
  const SafetyEvent_ParkInitiated({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafetyEvent_ParkInitiatedCopyWith<SafetyEvent_ParkInitiated> get copyWith => _$SafetyEvent_ParkInitiatedCopyWithImpl<SafetyEvent_ParkInitiated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent_ParkInitiated&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SafetyEvent.parkInitiated(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SafetyEvent_ParkInitiatedCopyWith<$Res> implements $SafetyEventCopyWith<$Res> {
  factory $SafetyEvent_ParkInitiatedCopyWith(SafetyEvent_ParkInitiated value, $Res Function(SafetyEvent_ParkInitiated) _then) = _$SafetyEvent_ParkInitiatedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SafetyEvent_ParkInitiatedCopyWithImpl<$Res>
    implements $SafetyEvent_ParkInitiatedCopyWith<$Res> {
  _$SafetyEvent_ParkInitiatedCopyWithImpl(this._self, this._then);

  final SafetyEvent_ParkInitiated _self;
  final $Res Function(SafetyEvent_ParkInitiated) _then;

/// Create a copy of SafetyEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SafetyEvent_ParkInitiated(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SafetyEvent_ParkCompleted extends SafetyEvent {
  const SafetyEvent_ParkCompleted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafetyEvent_ParkCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SafetyEvent.parkCompleted()';
}


}




/// @nodoc
mixin _$SequencerEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SequencerEvent()';
}


}

/// @nodoc
class $SequencerEventCopyWith<$Res>  {
$SequencerEventCopyWith(SequencerEvent _, $Res Function(SequencerEvent) __);
}


/// Adds pattern-matching-related methods to [SequencerEvent].
extension SequencerEventPatterns on SequencerEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SequencerEvent_Started value)?  started,TResult Function( SequencerEvent_Paused value)?  paused,TResult Function( SequencerEvent_Resumed value)?  resumed,TResult Function( SequencerEvent_Stopped value)?  stopped,TResult Function( SequencerEvent_Completed value)?  completed,TResult Function( SequencerEvent_Failed value)?  failed,TResult Function( SequencerEvent_NodeStarted value)?  nodeStarted,TResult Function( SequencerEvent_NodeCompleted value)?  nodeCompleted,TResult Function( SequencerEvent_Progress value)?  progress,TResult Function( SequencerEvent_TargetChanged value)?  targetChanged,TResult Function( SequencerEvent_TargetCompleted value)?  targetCompleted,TResult Function( SequencerEvent_ExposureStarted value)?  exposureStarted,TResult Function( SequencerEvent_ExposureCompleted value)?  exposureCompleted,TResult Function( SequencerEvent_Error value)?  error,TResult Function( SequencerEvent_MeridianFlipOutcome value)?  meridianFlipOutcome,TResult Function( SequencerEvent_TriggerFired value)?  triggerFired,TResult Function( SequencerEvent_InstructionProgress value)?  instructionProgress,TResult Function( SequencerEvent_InstructionProgressStructured value)?  instructionProgressStructured,TResult Function( SequencerEvent_FrameAccepted value)?  frameAccepted,TResult Function( SequencerEvent_FrameRejected value)?  frameRejected,TResult Function( SequencerEvent_SchedulerDecision value)?  schedulerDecision,TResult Function( SequencerEvent_IntegrationBudget value)?  integrationBudget,TResult Function( SequencerEvent_ExposureAdjusted value)?  exposureAdjusted,TResult Function( SequencerEvent_PhotometryFrame value)?  photometryFrame,TResult Function( SequencerEvent_PhotometryCadenceBroken value)?  photometryCadenceBroken,TResult Function( SequencerEvent_PhotometrySummary value)?  photometrySummary,TResult Function( SequencerEvent_RecoveryStarted value)?  recoveryStarted,TResult Function( SequencerEvent_RecoveryProgress value)?  recoveryProgress,TResult Function( SequencerEvent_RecoveryCompleted value)?  recoveryCompleted,TResult Function( SequencerEvent_RecoveryGaveUp value)?  recoveryGaveUp,TResult Function( SequencerEvent_PluginNodeRequested value)?  pluginNodeRequested,TResult Function( SequencerEvent_PluginNodeProgress value)?  pluginNodeProgress,TResult Function( SequencerEvent_DecisionLogged value)?  decisionLogged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SequencerEvent_Started() when started != null:
return started(_that);case SequencerEvent_Paused() when paused != null:
return paused(_that);case SequencerEvent_Resumed() when resumed != null:
return resumed(_that);case SequencerEvent_Stopped() when stopped != null:
return stopped(_that);case SequencerEvent_Completed() when completed != null:
return completed(_that);case SequencerEvent_Failed() when failed != null:
return failed(_that);case SequencerEvent_NodeStarted() when nodeStarted != null:
return nodeStarted(_that);case SequencerEvent_NodeCompleted() when nodeCompleted != null:
return nodeCompleted(_that);case SequencerEvent_Progress() when progress != null:
return progress(_that);case SequencerEvent_TargetChanged() when targetChanged != null:
return targetChanged(_that);case SequencerEvent_TargetCompleted() when targetCompleted != null:
return targetCompleted(_that);case SequencerEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that);case SequencerEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that);case SequencerEvent_Error() when error != null:
return error(_that);case SequencerEvent_MeridianFlipOutcome() when meridianFlipOutcome != null:
return meridianFlipOutcome(_that);case SequencerEvent_TriggerFired() when triggerFired != null:
return triggerFired(_that);case SequencerEvent_InstructionProgress() when instructionProgress != null:
return instructionProgress(_that);case SequencerEvent_InstructionProgressStructured() when instructionProgressStructured != null:
return instructionProgressStructured(_that);case SequencerEvent_FrameAccepted() when frameAccepted != null:
return frameAccepted(_that);case SequencerEvent_FrameRejected() when frameRejected != null:
return frameRejected(_that);case SequencerEvent_SchedulerDecision() when schedulerDecision != null:
return schedulerDecision(_that);case SequencerEvent_IntegrationBudget() when integrationBudget != null:
return integrationBudget(_that);case SequencerEvent_ExposureAdjusted() when exposureAdjusted != null:
return exposureAdjusted(_that);case SequencerEvent_PhotometryFrame() when photometryFrame != null:
return photometryFrame(_that);case SequencerEvent_PhotometryCadenceBroken() when photometryCadenceBroken != null:
return photometryCadenceBroken(_that);case SequencerEvent_PhotometrySummary() when photometrySummary != null:
return photometrySummary(_that);case SequencerEvent_RecoveryStarted() when recoveryStarted != null:
return recoveryStarted(_that);case SequencerEvent_RecoveryProgress() when recoveryProgress != null:
return recoveryProgress(_that);case SequencerEvent_RecoveryCompleted() when recoveryCompleted != null:
return recoveryCompleted(_that);case SequencerEvent_RecoveryGaveUp() when recoveryGaveUp != null:
return recoveryGaveUp(_that);case SequencerEvent_PluginNodeRequested() when pluginNodeRequested != null:
return pluginNodeRequested(_that);case SequencerEvent_PluginNodeProgress() when pluginNodeProgress != null:
return pluginNodeProgress(_that);case SequencerEvent_DecisionLogged() when decisionLogged != null:
return decisionLogged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SequencerEvent_Started value)  started,required TResult Function( SequencerEvent_Paused value)  paused,required TResult Function( SequencerEvent_Resumed value)  resumed,required TResult Function( SequencerEvent_Stopped value)  stopped,required TResult Function( SequencerEvent_Completed value)  completed,required TResult Function( SequencerEvent_Failed value)  failed,required TResult Function( SequencerEvent_NodeStarted value)  nodeStarted,required TResult Function( SequencerEvent_NodeCompleted value)  nodeCompleted,required TResult Function( SequencerEvent_Progress value)  progress,required TResult Function( SequencerEvent_TargetChanged value)  targetChanged,required TResult Function( SequencerEvent_TargetCompleted value)  targetCompleted,required TResult Function( SequencerEvent_ExposureStarted value)  exposureStarted,required TResult Function( SequencerEvent_ExposureCompleted value)  exposureCompleted,required TResult Function( SequencerEvent_Error value)  error,required TResult Function( SequencerEvent_MeridianFlipOutcome value)  meridianFlipOutcome,required TResult Function( SequencerEvent_TriggerFired value)  triggerFired,required TResult Function( SequencerEvent_InstructionProgress value)  instructionProgress,required TResult Function( SequencerEvent_InstructionProgressStructured value)  instructionProgressStructured,required TResult Function( SequencerEvent_FrameAccepted value)  frameAccepted,required TResult Function( SequencerEvent_FrameRejected value)  frameRejected,required TResult Function( SequencerEvent_SchedulerDecision value)  schedulerDecision,required TResult Function( SequencerEvent_IntegrationBudget value)  integrationBudget,required TResult Function( SequencerEvent_ExposureAdjusted value)  exposureAdjusted,required TResult Function( SequencerEvent_PhotometryFrame value)  photometryFrame,required TResult Function( SequencerEvent_PhotometryCadenceBroken value)  photometryCadenceBroken,required TResult Function( SequencerEvent_PhotometrySummary value)  photometrySummary,required TResult Function( SequencerEvent_RecoveryStarted value)  recoveryStarted,required TResult Function( SequencerEvent_RecoveryProgress value)  recoveryProgress,required TResult Function( SequencerEvent_RecoveryCompleted value)  recoveryCompleted,required TResult Function( SequencerEvent_RecoveryGaveUp value)  recoveryGaveUp,required TResult Function( SequencerEvent_PluginNodeRequested value)  pluginNodeRequested,required TResult Function( SequencerEvent_PluginNodeProgress value)  pluginNodeProgress,required TResult Function( SequencerEvent_DecisionLogged value)  decisionLogged,}){
final _that = this;
switch (_that) {
case SequencerEvent_Started():
return started(_that);case SequencerEvent_Paused():
return paused(_that);case SequencerEvent_Resumed():
return resumed(_that);case SequencerEvent_Stopped():
return stopped(_that);case SequencerEvent_Completed():
return completed(_that);case SequencerEvent_Failed():
return failed(_that);case SequencerEvent_NodeStarted():
return nodeStarted(_that);case SequencerEvent_NodeCompleted():
return nodeCompleted(_that);case SequencerEvent_Progress():
return progress(_that);case SequencerEvent_TargetChanged():
return targetChanged(_that);case SequencerEvent_TargetCompleted():
return targetCompleted(_that);case SequencerEvent_ExposureStarted():
return exposureStarted(_that);case SequencerEvent_ExposureCompleted():
return exposureCompleted(_that);case SequencerEvent_Error():
return error(_that);case SequencerEvent_MeridianFlipOutcome():
return meridianFlipOutcome(_that);case SequencerEvent_TriggerFired():
return triggerFired(_that);case SequencerEvent_InstructionProgress():
return instructionProgress(_that);case SequencerEvent_InstructionProgressStructured():
return instructionProgressStructured(_that);case SequencerEvent_FrameAccepted():
return frameAccepted(_that);case SequencerEvent_FrameRejected():
return frameRejected(_that);case SequencerEvent_SchedulerDecision():
return schedulerDecision(_that);case SequencerEvent_IntegrationBudget():
return integrationBudget(_that);case SequencerEvent_ExposureAdjusted():
return exposureAdjusted(_that);case SequencerEvent_PhotometryFrame():
return photometryFrame(_that);case SequencerEvent_PhotometryCadenceBroken():
return photometryCadenceBroken(_that);case SequencerEvent_PhotometrySummary():
return photometrySummary(_that);case SequencerEvent_RecoveryStarted():
return recoveryStarted(_that);case SequencerEvent_RecoveryProgress():
return recoveryProgress(_that);case SequencerEvent_RecoveryCompleted():
return recoveryCompleted(_that);case SequencerEvent_RecoveryGaveUp():
return recoveryGaveUp(_that);case SequencerEvent_PluginNodeRequested():
return pluginNodeRequested(_that);case SequencerEvent_PluginNodeProgress():
return pluginNodeProgress(_that);case SequencerEvent_DecisionLogged():
return decisionLogged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SequencerEvent_Started value)?  started,TResult? Function( SequencerEvent_Paused value)?  paused,TResult? Function( SequencerEvent_Resumed value)?  resumed,TResult? Function( SequencerEvent_Stopped value)?  stopped,TResult? Function( SequencerEvent_Completed value)?  completed,TResult? Function( SequencerEvent_Failed value)?  failed,TResult? Function( SequencerEvent_NodeStarted value)?  nodeStarted,TResult? Function( SequencerEvent_NodeCompleted value)?  nodeCompleted,TResult? Function( SequencerEvent_Progress value)?  progress,TResult? Function( SequencerEvent_TargetChanged value)?  targetChanged,TResult? Function( SequencerEvent_TargetCompleted value)?  targetCompleted,TResult? Function( SequencerEvent_ExposureStarted value)?  exposureStarted,TResult? Function( SequencerEvent_ExposureCompleted value)?  exposureCompleted,TResult? Function( SequencerEvent_Error value)?  error,TResult? Function( SequencerEvent_MeridianFlipOutcome value)?  meridianFlipOutcome,TResult? Function( SequencerEvent_TriggerFired value)?  triggerFired,TResult? Function( SequencerEvent_InstructionProgress value)?  instructionProgress,TResult? Function( SequencerEvent_InstructionProgressStructured value)?  instructionProgressStructured,TResult? Function( SequencerEvent_FrameAccepted value)?  frameAccepted,TResult? Function( SequencerEvent_FrameRejected value)?  frameRejected,TResult? Function( SequencerEvent_SchedulerDecision value)?  schedulerDecision,TResult? Function( SequencerEvent_IntegrationBudget value)?  integrationBudget,TResult? Function( SequencerEvent_ExposureAdjusted value)?  exposureAdjusted,TResult? Function( SequencerEvent_PhotometryFrame value)?  photometryFrame,TResult? Function( SequencerEvent_PhotometryCadenceBroken value)?  photometryCadenceBroken,TResult? Function( SequencerEvent_PhotometrySummary value)?  photometrySummary,TResult? Function( SequencerEvent_RecoveryStarted value)?  recoveryStarted,TResult? Function( SequencerEvent_RecoveryProgress value)?  recoveryProgress,TResult? Function( SequencerEvent_RecoveryCompleted value)?  recoveryCompleted,TResult? Function( SequencerEvent_RecoveryGaveUp value)?  recoveryGaveUp,TResult? Function( SequencerEvent_PluginNodeRequested value)?  pluginNodeRequested,TResult? Function( SequencerEvent_PluginNodeProgress value)?  pluginNodeProgress,TResult? Function( SequencerEvent_DecisionLogged value)?  decisionLogged,}){
final _that = this;
switch (_that) {
case SequencerEvent_Started() when started != null:
return started(_that);case SequencerEvent_Paused() when paused != null:
return paused(_that);case SequencerEvent_Resumed() when resumed != null:
return resumed(_that);case SequencerEvent_Stopped() when stopped != null:
return stopped(_that);case SequencerEvent_Completed() when completed != null:
return completed(_that);case SequencerEvent_Failed() when failed != null:
return failed(_that);case SequencerEvent_NodeStarted() when nodeStarted != null:
return nodeStarted(_that);case SequencerEvent_NodeCompleted() when nodeCompleted != null:
return nodeCompleted(_that);case SequencerEvent_Progress() when progress != null:
return progress(_that);case SequencerEvent_TargetChanged() when targetChanged != null:
return targetChanged(_that);case SequencerEvent_TargetCompleted() when targetCompleted != null:
return targetCompleted(_that);case SequencerEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that);case SequencerEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that);case SequencerEvent_Error() when error != null:
return error(_that);case SequencerEvent_MeridianFlipOutcome() when meridianFlipOutcome != null:
return meridianFlipOutcome(_that);case SequencerEvent_TriggerFired() when triggerFired != null:
return triggerFired(_that);case SequencerEvent_InstructionProgress() when instructionProgress != null:
return instructionProgress(_that);case SequencerEvent_InstructionProgressStructured() when instructionProgressStructured != null:
return instructionProgressStructured(_that);case SequencerEvent_FrameAccepted() when frameAccepted != null:
return frameAccepted(_that);case SequencerEvent_FrameRejected() when frameRejected != null:
return frameRejected(_that);case SequencerEvent_SchedulerDecision() when schedulerDecision != null:
return schedulerDecision(_that);case SequencerEvent_IntegrationBudget() when integrationBudget != null:
return integrationBudget(_that);case SequencerEvent_ExposureAdjusted() when exposureAdjusted != null:
return exposureAdjusted(_that);case SequencerEvent_PhotometryFrame() when photometryFrame != null:
return photometryFrame(_that);case SequencerEvent_PhotometryCadenceBroken() when photometryCadenceBroken != null:
return photometryCadenceBroken(_that);case SequencerEvent_PhotometrySummary() when photometrySummary != null:
return photometrySummary(_that);case SequencerEvent_RecoveryStarted() when recoveryStarted != null:
return recoveryStarted(_that);case SequencerEvent_RecoveryProgress() when recoveryProgress != null:
return recoveryProgress(_that);case SequencerEvent_RecoveryCompleted() when recoveryCompleted != null:
return recoveryCompleted(_that);case SequencerEvent_RecoveryGaveUp() when recoveryGaveUp != null:
return recoveryGaveUp(_that);case SequencerEvent_PluginNodeRequested() when pluginNodeRequested != null:
return pluginNodeRequested(_that);case SequencerEvent_PluginNodeProgress() when pluginNodeProgress != null:
return pluginNodeProgress(_that);case SequencerEvent_DecisionLogged() when decisionLogged != null:
return decisionLogged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String sequenceName)?  started,TResult Function()?  paused,TResult Function()?  resumed,TResult Function()?  stopped,TResult Function()?  completed,TResult Function( String error)?  failed,TResult Function( String nodeId,  String nodeType)?  nodeStarted,TResult Function( String nodeId,  String status)?  nodeCompleted,TResult Function( int current,  int total)?  progress,TResult Function( String targetName,  double? ra,  double? dec)?  targetChanged,TResult Function( String targetName)?  targetCompleted,TResult Function( int frame,  int total,  String? filter,  double durationSecs)?  exposureStarted,TResult Function( int frame,  int total,  double durationSecs)?  exposureCompleted,TResult Function( String message)?  error,TResult Function( String outcome,  String targetName,  String newPierSide,  double durationSecs,  int attempts,  List<String> failedSteps,  String? error,  String? actionTaken)?  meridianFlipOutcome,TResult Function( String triggerId,  String triggerName,  String action)?  triggerFired,TResult Function( String nodeId,  String instruction,  double progressPercent,  String detail)?  instructionProgress,TResult Function( String nodeId,  String instruction,  double progressPercent,  String detailKind,  String detailJson)?  instructionProgressStructured,TResult Function( String nodeId,  int frame,  int total,  double? hfr,  double? eccentricity,  int? starCount,  int acceptedTotal,  int rejectedTotal,  String? savePath)?  frameAccepted,TResult Function( String nodeId,  int frame,  int total,  String reason,  double? hfr,  double? eccentricity,  int? starCount,  String rejectPath,  int consecutiveRejects,  int acceptedTotal,  int rejectedTotal,  String? likelyCauseLabel,  List<String> evidence,  double? skyBrightnessAtCapture,  double? cloudCoverAtCapture,  double? windAtCapture,  double? guideRmsAtCapture,  double? sensorTempAtCapture)?  frameRejected,TResult Function( String nodeId,  int decisionCounter,  String? pickedTargetId,  String? pickedTargetName,  double? pickedScore,  List<SchedulerScoreEntry> scores)?  schedulerDecision,TResult Function( String targetId,  String filter,  double completedSecs,  double budgetSecs,  double fraction,  bool budgetMet)?  integrationBudget,TResult Function( String nodeId,  double adaptedSecs,  double nominalSecs,  double? skyBrightnessMag,  String? filter,  String reason)?  exposureAdjusted,TResult Function( String nodeId,  String targetDesignation,  List<String> referenceStars,  int frame,  int total,  String filter,  double exposureSecs,  double? airmass,  double? fwhmArcsec,  double? snr,  double mjdObs,  double frameStartUnix,  bool accepted,  String? rejectReason,  bool reduceLive,  bool applyDifferential)?  photometryFrame,TResult Function( String nodeId,  int frame,  int total,  double gapSecs,  double maxGapSecs,  int cadenceBreaks)?  photometryCadenceBroken,TResult Function( String nodeId,  String targetDesignation,  String filter,  int framesCaptured,  int cadenceBreaks,  String? lastRejectReason)?  photometrySummary,TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryStarted,TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryProgress,TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryCompleted,TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError,  bool abortedByUser)?  recoveryGaveUp,TResult Function( String nodeId,  String pluginId,  String nodeTypeId,  String configJson,  String? displayName,  int timeoutSecs)?  pluginNodeRequested,TResult Function( String nodeId,  String pluginId,  String nodeTypeId,  String detailJson)?  pluginNodeProgress,TResult Function( String timestampIso,  String category,  String summary,  String detailsJson,  String? nodeId,  PlatformInt64? sequenceRunId)?  decisionLogged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SequencerEvent_Started() when started != null:
return started(_that.sequenceName);case SequencerEvent_Paused() when paused != null:
return paused();case SequencerEvent_Resumed() when resumed != null:
return resumed();case SequencerEvent_Stopped() when stopped != null:
return stopped();case SequencerEvent_Completed() when completed != null:
return completed();case SequencerEvent_Failed() when failed != null:
return failed(_that.error);case SequencerEvent_NodeStarted() when nodeStarted != null:
return nodeStarted(_that.nodeId,_that.nodeType);case SequencerEvent_NodeCompleted() when nodeCompleted != null:
return nodeCompleted(_that.nodeId,_that.status);case SequencerEvent_Progress() when progress != null:
return progress(_that.current,_that.total);case SequencerEvent_TargetChanged() when targetChanged != null:
return targetChanged(_that.targetName,_that.ra,_that.dec);case SequencerEvent_TargetCompleted() when targetCompleted != null:
return targetCompleted(_that.targetName);case SequencerEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that.frame,_that.total,_that.filter,_that.durationSecs);case SequencerEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that.frame,_that.total,_that.durationSecs);case SequencerEvent_Error() when error != null:
return error(_that.message);case SequencerEvent_MeridianFlipOutcome() when meridianFlipOutcome != null:
return meridianFlipOutcome(_that.outcome,_that.targetName,_that.newPierSide,_that.durationSecs,_that.attempts,_that.failedSteps,_that.error,_that.actionTaken);case SequencerEvent_TriggerFired() when triggerFired != null:
return triggerFired(_that.triggerId,_that.triggerName,_that.action);case SequencerEvent_InstructionProgress() when instructionProgress != null:
return instructionProgress(_that.nodeId,_that.instruction,_that.progressPercent,_that.detail);case SequencerEvent_InstructionProgressStructured() when instructionProgressStructured != null:
return instructionProgressStructured(_that.nodeId,_that.instruction,_that.progressPercent,_that.detailKind,_that.detailJson);case SequencerEvent_FrameAccepted() when frameAccepted != null:
return frameAccepted(_that.nodeId,_that.frame,_that.total,_that.hfr,_that.eccentricity,_that.starCount,_that.acceptedTotal,_that.rejectedTotal,_that.savePath);case SequencerEvent_FrameRejected() when frameRejected != null:
return frameRejected(_that.nodeId,_that.frame,_that.total,_that.reason,_that.hfr,_that.eccentricity,_that.starCount,_that.rejectPath,_that.consecutiveRejects,_that.acceptedTotal,_that.rejectedTotal,_that.likelyCauseLabel,_that.evidence,_that.skyBrightnessAtCapture,_that.cloudCoverAtCapture,_that.windAtCapture,_that.guideRmsAtCapture,_that.sensorTempAtCapture);case SequencerEvent_SchedulerDecision() when schedulerDecision != null:
return schedulerDecision(_that.nodeId,_that.decisionCounter,_that.pickedTargetId,_that.pickedTargetName,_that.pickedScore,_that.scores);case SequencerEvent_IntegrationBudget() when integrationBudget != null:
return integrationBudget(_that.targetId,_that.filter,_that.completedSecs,_that.budgetSecs,_that.fraction,_that.budgetMet);case SequencerEvent_ExposureAdjusted() when exposureAdjusted != null:
return exposureAdjusted(_that.nodeId,_that.adaptedSecs,_that.nominalSecs,_that.skyBrightnessMag,_that.filter,_that.reason);case SequencerEvent_PhotometryFrame() when photometryFrame != null:
return photometryFrame(_that.nodeId,_that.targetDesignation,_that.referenceStars,_that.frame,_that.total,_that.filter,_that.exposureSecs,_that.airmass,_that.fwhmArcsec,_that.snr,_that.mjdObs,_that.frameStartUnix,_that.accepted,_that.rejectReason,_that.reduceLive,_that.applyDifferential);case SequencerEvent_PhotometryCadenceBroken() when photometryCadenceBroken != null:
return photometryCadenceBroken(_that.nodeId,_that.frame,_that.total,_that.gapSecs,_that.maxGapSecs,_that.cadenceBreaks);case SequencerEvent_PhotometrySummary() when photometrySummary != null:
return photometrySummary(_that.nodeId,_that.targetDesignation,_that.filter,_that.framesCaptured,_that.cadenceBreaks,_that.lastRejectReason);case SequencerEvent_RecoveryStarted() when recoveryStarted != null:
return recoveryStarted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryProgress() when recoveryProgress != null:
return recoveryProgress(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryCompleted() when recoveryCompleted != null:
return recoveryCompleted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryGaveUp() when recoveryGaveUp != null:
return recoveryGaveUp(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError,_that.abortedByUser);case SequencerEvent_PluginNodeRequested() when pluginNodeRequested != null:
return pluginNodeRequested(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.configJson,_that.displayName,_that.timeoutSecs);case SequencerEvent_PluginNodeProgress() when pluginNodeProgress != null:
return pluginNodeProgress(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.detailJson);case SequencerEvent_DecisionLogged() when decisionLogged != null:
return decisionLogged(_that.timestampIso,_that.category,_that.summary,_that.detailsJson,_that.nodeId,_that.sequenceRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String sequenceName)  started,required TResult Function()  paused,required TResult Function()  resumed,required TResult Function()  stopped,required TResult Function()  completed,required TResult Function( String error)  failed,required TResult Function( String nodeId,  String nodeType)  nodeStarted,required TResult Function( String nodeId,  String status)  nodeCompleted,required TResult Function( int current,  int total)  progress,required TResult Function( String targetName,  double? ra,  double? dec)  targetChanged,required TResult Function( String targetName)  targetCompleted,required TResult Function( int frame,  int total,  String? filter,  double durationSecs)  exposureStarted,required TResult Function( int frame,  int total,  double durationSecs)  exposureCompleted,required TResult Function( String message)  error,required TResult Function( String outcome,  String targetName,  String newPierSide,  double durationSecs,  int attempts,  List<String> failedSteps,  String? error,  String? actionTaken)  meridianFlipOutcome,required TResult Function( String triggerId,  String triggerName,  String action)  triggerFired,required TResult Function( String nodeId,  String instruction,  double progressPercent,  String detail)  instructionProgress,required TResult Function( String nodeId,  String instruction,  double progressPercent,  String detailKind,  String detailJson)  instructionProgressStructured,required TResult Function( String nodeId,  int frame,  int total,  double? hfr,  double? eccentricity,  int? starCount,  int acceptedTotal,  int rejectedTotal,  String? savePath)  frameAccepted,required TResult Function( String nodeId,  int frame,  int total,  String reason,  double? hfr,  double? eccentricity,  int? starCount,  String rejectPath,  int consecutiveRejects,  int acceptedTotal,  int rejectedTotal,  String? likelyCauseLabel,  List<String> evidence,  double? skyBrightnessAtCapture,  double? cloudCoverAtCapture,  double? windAtCapture,  double? guideRmsAtCapture,  double? sensorTempAtCapture)  frameRejected,required TResult Function( String nodeId,  int decisionCounter,  String? pickedTargetId,  String? pickedTargetName,  double? pickedScore,  List<SchedulerScoreEntry> scores)  schedulerDecision,required TResult Function( String targetId,  String filter,  double completedSecs,  double budgetSecs,  double fraction,  bool budgetMet)  integrationBudget,required TResult Function( String nodeId,  double adaptedSecs,  double nominalSecs,  double? skyBrightnessMag,  String? filter,  String reason)  exposureAdjusted,required TResult Function( String nodeId,  String targetDesignation,  List<String> referenceStars,  int frame,  int total,  String filter,  double exposureSecs,  double? airmass,  double? fwhmArcsec,  double? snr,  double mjdObs,  double frameStartUnix,  bool accepted,  String? rejectReason,  bool reduceLive,  bool applyDifferential)  photometryFrame,required TResult Function( String nodeId,  int frame,  int total,  double gapSecs,  double maxGapSecs,  int cadenceBreaks)  photometryCadenceBroken,required TResult Function( String nodeId,  String targetDesignation,  String filter,  int framesCaptured,  int cadenceBreaks,  String? lastRejectReason)  photometrySummary,required TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)  recoveryStarted,required TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)  recoveryProgress,required TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)  recoveryCompleted,required TResult Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError,  bool abortedByUser)  recoveryGaveUp,required TResult Function( String nodeId,  String pluginId,  String nodeTypeId,  String configJson,  String? displayName,  int timeoutSecs)  pluginNodeRequested,required TResult Function( String nodeId,  String pluginId,  String nodeTypeId,  String detailJson)  pluginNodeProgress,required TResult Function( String timestampIso,  String category,  String summary,  String detailsJson,  String? nodeId,  PlatformInt64? sequenceRunId)  decisionLogged,}) {final _that = this;
switch (_that) {
case SequencerEvent_Started():
return started(_that.sequenceName);case SequencerEvent_Paused():
return paused();case SequencerEvent_Resumed():
return resumed();case SequencerEvent_Stopped():
return stopped();case SequencerEvent_Completed():
return completed();case SequencerEvent_Failed():
return failed(_that.error);case SequencerEvent_NodeStarted():
return nodeStarted(_that.nodeId,_that.nodeType);case SequencerEvent_NodeCompleted():
return nodeCompleted(_that.nodeId,_that.status);case SequencerEvent_Progress():
return progress(_that.current,_that.total);case SequencerEvent_TargetChanged():
return targetChanged(_that.targetName,_that.ra,_that.dec);case SequencerEvent_TargetCompleted():
return targetCompleted(_that.targetName);case SequencerEvent_ExposureStarted():
return exposureStarted(_that.frame,_that.total,_that.filter,_that.durationSecs);case SequencerEvent_ExposureCompleted():
return exposureCompleted(_that.frame,_that.total,_that.durationSecs);case SequencerEvent_Error():
return error(_that.message);case SequencerEvent_MeridianFlipOutcome():
return meridianFlipOutcome(_that.outcome,_that.targetName,_that.newPierSide,_that.durationSecs,_that.attempts,_that.failedSteps,_that.error,_that.actionTaken);case SequencerEvent_TriggerFired():
return triggerFired(_that.triggerId,_that.triggerName,_that.action);case SequencerEvent_InstructionProgress():
return instructionProgress(_that.nodeId,_that.instruction,_that.progressPercent,_that.detail);case SequencerEvent_InstructionProgressStructured():
return instructionProgressStructured(_that.nodeId,_that.instruction,_that.progressPercent,_that.detailKind,_that.detailJson);case SequencerEvent_FrameAccepted():
return frameAccepted(_that.nodeId,_that.frame,_that.total,_that.hfr,_that.eccentricity,_that.starCount,_that.acceptedTotal,_that.rejectedTotal,_that.savePath);case SequencerEvent_FrameRejected():
return frameRejected(_that.nodeId,_that.frame,_that.total,_that.reason,_that.hfr,_that.eccentricity,_that.starCount,_that.rejectPath,_that.consecutiveRejects,_that.acceptedTotal,_that.rejectedTotal,_that.likelyCauseLabel,_that.evidence,_that.skyBrightnessAtCapture,_that.cloudCoverAtCapture,_that.windAtCapture,_that.guideRmsAtCapture,_that.sensorTempAtCapture);case SequencerEvent_SchedulerDecision():
return schedulerDecision(_that.nodeId,_that.decisionCounter,_that.pickedTargetId,_that.pickedTargetName,_that.pickedScore,_that.scores);case SequencerEvent_IntegrationBudget():
return integrationBudget(_that.targetId,_that.filter,_that.completedSecs,_that.budgetSecs,_that.fraction,_that.budgetMet);case SequencerEvent_ExposureAdjusted():
return exposureAdjusted(_that.nodeId,_that.adaptedSecs,_that.nominalSecs,_that.skyBrightnessMag,_that.filter,_that.reason);case SequencerEvent_PhotometryFrame():
return photometryFrame(_that.nodeId,_that.targetDesignation,_that.referenceStars,_that.frame,_that.total,_that.filter,_that.exposureSecs,_that.airmass,_that.fwhmArcsec,_that.snr,_that.mjdObs,_that.frameStartUnix,_that.accepted,_that.rejectReason,_that.reduceLive,_that.applyDifferential);case SequencerEvent_PhotometryCadenceBroken():
return photometryCadenceBroken(_that.nodeId,_that.frame,_that.total,_that.gapSecs,_that.maxGapSecs,_that.cadenceBreaks);case SequencerEvent_PhotometrySummary():
return photometrySummary(_that.nodeId,_that.targetDesignation,_that.filter,_that.framesCaptured,_that.cadenceBreaks,_that.lastRejectReason);case SequencerEvent_RecoveryStarted():
return recoveryStarted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryProgress():
return recoveryProgress(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryCompleted():
return recoveryCompleted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryGaveUp():
return recoveryGaveUp(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError,_that.abortedByUser);case SequencerEvent_PluginNodeRequested():
return pluginNodeRequested(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.configJson,_that.displayName,_that.timeoutSecs);case SequencerEvent_PluginNodeProgress():
return pluginNodeProgress(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.detailJson);case SequencerEvent_DecisionLogged():
return decisionLogged(_that.timestampIso,_that.category,_that.summary,_that.detailsJson,_that.nodeId,_that.sequenceRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String sequenceName)?  started,TResult? Function()?  paused,TResult? Function()?  resumed,TResult? Function()?  stopped,TResult? Function()?  completed,TResult? Function( String error)?  failed,TResult? Function( String nodeId,  String nodeType)?  nodeStarted,TResult? Function( String nodeId,  String status)?  nodeCompleted,TResult? Function( int current,  int total)?  progress,TResult? Function( String targetName,  double? ra,  double? dec)?  targetChanged,TResult? Function( String targetName)?  targetCompleted,TResult? Function( int frame,  int total,  String? filter,  double durationSecs)?  exposureStarted,TResult? Function( int frame,  int total,  double durationSecs)?  exposureCompleted,TResult? Function( String message)?  error,TResult? Function( String outcome,  String targetName,  String newPierSide,  double durationSecs,  int attempts,  List<String> failedSteps,  String? error,  String? actionTaken)?  meridianFlipOutcome,TResult? Function( String triggerId,  String triggerName,  String action)?  triggerFired,TResult? Function( String nodeId,  String instruction,  double progressPercent,  String detail)?  instructionProgress,TResult? Function( String nodeId,  String instruction,  double progressPercent,  String detailKind,  String detailJson)?  instructionProgressStructured,TResult? Function( String nodeId,  int frame,  int total,  double? hfr,  double? eccentricity,  int? starCount,  int acceptedTotal,  int rejectedTotal,  String? savePath)?  frameAccepted,TResult? Function( String nodeId,  int frame,  int total,  String reason,  double? hfr,  double? eccentricity,  int? starCount,  String rejectPath,  int consecutiveRejects,  int acceptedTotal,  int rejectedTotal,  String? likelyCauseLabel,  List<String> evidence,  double? skyBrightnessAtCapture,  double? cloudCoverAtCapture,  double? windAtCapture,  double? guideRmsAtCapture,  double? sensorTempAtCapture)?  frameRejected,TResult? Function( String nodeId,  int decisionCounter,  String? pickedTargetId,  String? pickedTargetName,  double? pickedScore,  List<SchedulerScoreEntry> scores)?  schedulerDecision,TResult? Function( String targetId,  String filter,  double completedSecs,  double budgetSecs,  double fraction,  bool budgetMet)?  integrationBudget,TResult? Function( String nodeId,  double adaptedSecs,  double nominalSecs,  double? skyBrightnessMag,  String? filter,  String reason)?  exposureAdjusted,TResult? Function( String nodeId,  String targetDesignation,  List<String> referenceStars,  int frame,  int total,  String filter,  double exposureSecs,  double? airmass,  double? fwhmArcsec,  double? snr,  double mjdObs,  double frameStartUnix,  bool accepted,  String? rejectReason,  bool reduceLive,  bool applyDifferential)?  photometryFrame,TResult? Function( String nodeId,  int frame,  int total,  double gapSecs,  double maxGapSecs,  int cadenceBreaks)?  photometryCadenceBroken,TResult? Function( String nodeId,  String targetDesignation,  String filter,  int framesCaptured,  int cadenceBreaks,  String? lastRejectReason)?  photometrySummary,TResult? Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryStarted,TResult? Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryProgress,TResult? Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError)?  recoveryCompleted,TResult? Function( String startedAtIso,  String causeKind,  String? causeCustomLabel,  String? lastAttemptAtIso,  int attemptCount,  int maxAttempts,  double retryIntervalSecs,  double maxDurationSecs,  String phase,  String? lastError,  bool abortedByUser)?  recoveryGaveUp,TResult? Function( String nodeId,  String pluginId,  String nodeTypeId,  String configJson,  String? displayName,  int timeoutSecs)?  pluginNodeRequested,TResult? Function( String nodeId,  String pluginId,  String nodeTypeId,  String detailJson)?  pluginNodeProgress,TResult? Function( String timestampIso,  String category,  String summary,  String detailsJson,  String? nodeId,  PlatformInt64? sequenceRunId)?  decisionLogged,}) {final _that = this;
switch (_that) {
case SequencerEvent_Started() when started != null:
return started(_that.sequenceName);case SequencerEvent_Paused() when paused != null:
return paused();case SequencerEvent_Resumed() when resumed != null:
return resumed();case SequencerEvent_Stopped() when stopped != null:
return stopped();case SequencerEvent_Completed() when completed != null:
return completed();case SequencerEvent_Failed() when failed != null:
return failed(_that.error);case SequencerEvent_NodeStarted() when nodeStarted != null:
return nodeStarted(_that.nodeId,_that.nodeType);case SequencerEvent_NodeCompleted() when nodeCompleted != null:
return nodeCompleted(_that.nodeId,_that.status);case SequencerEvent_Progress() when progress != null:
return progress(_that.current,_that.total);case SequencerEvent_TargetChanged() when targetChanged != null:
return targetChanged(_that.targetName,_that.ra,_that.dec);case SequencerEvent_TargetCompleted() when targetCompleted != null:
return targetCompleted(_that.targetName);case SequencerEvent_ExposureStarted() when exposureStarted != null:
return exposureStarted(_that.frame,_that.total,_that.filter,_that.durationSecs);case SequencerEvent_ExposureCompleted() when exposureCompleted != null:
return exposureCompleted(_that.frame,_that.total,_that.durationSecs);case SequencerEvent_Error() when error != null:
return error(_that.message);case SequencerEvent_MeridianFlipOutcome() when meridianFlipOutcome != null:
return meridianFlipOutcome(_that.outcome,_that.targetName,_that.newPierSide,_that.durationSecs,_that.attempts,_that.failedSteps,_that.error,_that.actionTaken);case SequencerEvent_TriggerFired() when triggerFired != null:
return triggerFired(_that.triggerId,_that.triggerName,_that.action);case SequencerEvent_InstructionProgress() when instructionProgress != null:
return instructionProgress(_that.nodeId,_that.instruction,_that.progressPercent,_that.detail);case SequencerEvent_InstructionProgressStructured() when instructionProgressStructured != null:
return instructionProgressStructured(_that.nodeId,_that.instruction,_that.progressPercent,_that.detailKind,_that.detailJson);case SequencerEvent_FrameAccepted() when frameAccepted != null:
return frameAccepted(_that.nodeId,_that.frame,_that.total,_that.hfr,_that.eccentricity,_that.starCount,_that.acceptedTotal,_that.rejectedTotal,_that.savePath);case SequencerEvent_FrameRejected() when frameRejected != null:
return frameRejected(_that.nodeId,_that.frame,_that.total,_that.reason,_that.hfr,_that.eccentricity,_that.starCount,_that.rejectPath,_that.consecutiveRejects,_that.acceptedTotal,_that.rejectedTotal,_that.likelyCauseLabel,_that.evidence,_that.skyBrightnessAtCapture,_that.cloudCoverAtCapture,_that.windAtCapture,_that.guideRmsAtCapture,_that.sensorTempAtCapture);case SequencerEvent_SchedulerDecision() when schedulerDecision != null:
return schedulerDecision(_that.nodeId,_that.decisionCounter,_that.pickedTargetId,_that.pickedTargetName,_that.pickedScore,_that.scores);case SequencerEvent_IntegrationBudget() when integrationBudget != null:
return integrationBudget(_that.targetId,_that.filter,_that.completedSecs,_that.budgetSecs,_that.fraction,_that.budgetMet);case SequencerEvent_ExposureAdjusted() when exposureAdjusted != null:
return exposureAdjusted(_that.nodeId,_that.adaptedSecs,_that.nominalSecs,_that.skyBrightnessMag,_that.filter,_that.reason);case SequencerEvent_PhotometryFrame() when photometryFrame != null:
return photometryFrame(_that.nodeId,_that.targetDesignation,_that.referenceStars,_that.frame,_that.total,_that.filter,_that.exposureSecs,_that.airmass,_that.fwhmArcsec,_that.snr,_that.mjdObs,_that.frameStartUnix,_that.accepted,_that.rejectReason,_that.reduceLive,_that.applyDifferential);case SequencerEvent_PhotometryCadenceBroken() when photometryCadenceBroken != null:
return photometryCadenceBroken(_that.nodeId,_that.frame,_that.total,_that.gapSecs,_that.maxGapSecs,_that.cadenceBreaks);case SequencerEvent_PhotometrySummary() when photometrySummary != null:
return photometrySummary(_that.nodeId,_that.targetDesignation,_that.filter,_that.framesCaptured,_that.cadenceBreaks,_that.lastRejectReason);case SequencerEvent_RecoveryStarted() when recoveryStarted != null:
return recoveryStarted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryProgress() when recoveryProgress != null:
return recoveryProgress(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryCompleted() when recoveryCompleted != null:
return recoveryCompleted(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError);case SequencerEvent_RecoveryGaveUp() when recoveryGaveUp != null:
return recoveryGaveUp(_that.startedAtIso,_that.causeKind,_that.causeCustomLabel,_that.lastAttemptAtIso,_that.attemptCount,_that.maxAttempts,_that.retryIntervalSecs,_that.maxDurationSecs,_that.phase,_that.lastError,_that.abortedByUser);case SequencerEvent_PluginNodeRequested() when pluginNodeRequested != null:
return pluginNodeRequested(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.configJson,_that.displayName,_that.timeoutSecs);case SequencerEvent_PluginNodeProgress() when pluginNodeProgress != null:
return pluginNodeProgress(_that.nodeId,_that.pluginId,_that.nodeTypeId,_that.detailJson);case SequencerEvent_DecisionLogged() when decisionLogged != null:
return decisionLogged(_that.timestampIso,_that.category,_that.summary,_that.detailsJson,_that.nodeId,_that.sequenceRunId);case _:
  return null;

}
}

}

/// @nodoc


class SequencerEvent_Started extends SequencerEvent {
  const SequencerEvent_Started({required this.sequenceName}): super._();
  

 final  String sequenceName;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_StartedCopyWith<SequencerEvent_Started> get copyWith => _$SequencerEvent_StartedCopyWithImpl<SequencerEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Started&&(identical(other.sequenceName, sequenceName) || other.sequenceName == sequenceName));
}


@override
int get hashCode => Object.hash(runtimeType,sequenceName);

@override
String toString() {
  return 'SequencerEvent.started(sequenceName: $sequenceName)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_StartedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_StartedCopyWith(SequencerEvent_Started value, $Res Function(SequencerEvent_Started) _then) = _$SequencerEvent_StartedCopyWithImpl;
@useResult
$Res call({
 String sequenceName
});




}
/// @nodoc
class _$SequencerEvent_StartedCopyWithImpl<$Res>
    implements $SequencerEvent_StartedCopyWith<$Res> {
  _$SequencerEvent_StartedCopyWithImpl(this._self, this._then);

  final SequencerEvent_Started _self;
  final $Res Function(SequencerEvent_Started) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sequenceName = null,}) {
  return _then(SequencerEvent_Started(
sequenceName: null == sequenceName ? _self.sequenceName : sequenceName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_Paused extends SequencerEvent {
  const SequencerEvent_Paused(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Paused);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SequencerEvent.paused()';
}


}




/// @nodoc


class SequencerEvent_Resumed extends SequencerEvent {
  const SequencerEvent_Resumed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Resumed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SequencerEvent.resumed()';
}


}




/// @nodoc


class SequencerEvent_Stopped extends SequencerEvent {
  const SequencerEvent_Stopped(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Stopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SequencerEvent.stopped()';
}


}




/// @nodoc


class SequencerEvent_Completed extends SequencerEvent {
  const SequencerEvent_Completed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Completed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SequencerEvent.completed()';
}


}




/// @nodoc


class SequencerEvent_Failed extends SequencerEvent {
  const SequencerEvent_Failed({required this.error}): super._();
  

 final  String error;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_FailedCopyWith<SequencerEvent_Failed> get copyWith => _$SequencerEvent_FailedCopyWithImpl<SequencerEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'SequencerEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_FailedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_FailedCopyWith(SequencerEvent_Failed value, $Res Function(SequencerEvent_Failed) _then) = _$SequencerEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$SequencerEvent_FailedCopyWithImpl<$Res>
    implements $SequencerEvent_FailedCopyWith<$Res> {
  _$SequencerEvent_FailedCopyWithImpl(this._self, this._then);

  final SequencerEvent_Failed _self;
  final $Res Function(SequencerEvent_Failed) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(SequencerEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_NodeStarted extends SequencerEvent {
  const SequencerEvent_NodeStarted({required this.nodeId, required this.nodeType}): super._();
  

 final  String nodeId;
 final  String nodeType;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_NodeStartedCopyWith<SequencerEvent_NodeStarted> get copyWith => _$SequencerEvent_NodeStartedCopyWithImpl<SequencerEvent_NodeStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_NodeStarted&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.nodeType, nodeType) || other.nodeType == nodeType));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,nodeType);

@override
String toString() {
  return 'SequencerEvent.nodeStarted(nodeId: $nodeId, nodeType: $nodeType)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_NodeStartedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_NodeStartedCopyWith(SequencerEvent_NodeStarted value, $Res Function(SequencerEvent_NodeStarted) _then) = _$SequencerEvent_NodeStartedCopyWithImpl;
@useResult
$Res call({
 String nodeId, String nodeType
});




}
/// @nodoc
class _$SequencerEvent_NodeStartedCopyWithImpl<$Res>
    implements $SequencerEvent_NodeStartedCopyWith<$Res> {
  _$SequencerEvent_NodeStartedCopyWithImpl(this._self, this._then);

  final SequencerEvent_NodeStarted _self;
  final $Res Function(SequencerEvent_NodeStarted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? nodeType = null,}) {
  return _then(SequencerEvent_NodeStarted(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,nodeType: null == nodeType ? _self.nodeType : nodeType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_NodeCompleted extends SequencerEvent {
  const SequencerEvent_NodeCompleted({required this.nodeId, required this.status}): super._();
  

 final  String nodeId;
/// Completion status: "success", "failed", "cancelled", or "skipped"
 final  String status;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_NodeCompletedCopyWith<SequencerEvent_NodeCompleted> get copyWith => _$SequencerEvent_NodeCompletedCopyWithImpl<SequencerEvent_NodeCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_NodeCompleted&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,status);

@override
String toString() {
  return 'SequencerEvent.nodeCompleted(nodeId: $nodeId, status: $status)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_NodeCompletedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_NodeCompletedCopyWith(SequencerEvent_NodeCompleted value, $Res Function(SequencerEvent_NodeCompleted) _then) = _$SequencerEvent_NodeCompletedCopyWithImpl;
@useResult
$Res call({
 String nodeId, String status
});




}
/// @nodoc
class _$SequencerEvent_NodeCompletedCopyWithImpl<$Res>
    implements $SequencerEvent_NodeCompletedCopyWith<$Res> {
  _$SequencerEvent_NodeCompletedCopyWithImpl(this._self, this._then);

  final SequencerEvent_NodeCompleted _self;
  final $Res Function(SequencerEvent_NodeCompleted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? status = null,}) {
  return _then(SequencerEvent_NodeCompleted(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_Progress extends SequencerEvent {
  const SequencerEvent_Progress({required this.current, required this.total}): super._();
  

 final  int current;
 final  int total;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_ProgressCopyWith<SequencerEvent_Progress> get copyWith => _$SequencerEvent_ProgressCopyWithImpl<SequencerEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Progress&&(identical(other.current, current) || other.current == current)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode => Object.hash(runtimeType,current,total);

@override
String toString() {
  return 'SequencerEvent.progress(current: $current, total: $total)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_ProgressCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_ProgressCopyWith(SequencerEvent_Progress value, $Res Function(SequencerEvent_Progress) _then) = _$SequencerEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 int current, int total
});




}
/// @nodoc
class _$SequencerEvent_ProgressCopyWithImpl<$Res>
    implements $SequencerEvent_ProgressCopyWith<$Res> {
  _$SequencerEvent_ProgressCopyWithImpl(this._self, this._then);

  final SequencerEvent_Progress _self;
  final $Res Function(SequencerEvent_Progress) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? current = null,Object? total = null,}) {
  return _then(SequencerEvent_Progress(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class SequencerEvent_TargetChanged extends SequencerEvent {
  const SequencerEvent_TargetChanged({required this.targetName, this.ra, this.dec}): super._();
  

 final  String targetName;
/// Right Ascension in hours (0-24), if available from the target header
 final  double? ra;
/// Declination in degrees (-90 to +90), if available from the target header
 final  double? dec;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_TargetChangedCopyWith<SequencerEvent_TargetChanged> get copyWith => _$SequencerEvent_TargetChangedCopyWithImpl<SequencerEvent_TargetChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_TargetChanged&&(identical(other.targetName, targetName) || other.targetName == targetName)&&(identical(other.ra, ra) || other.ra == ra)&&(identical(other.dec, dec) || other.dec == dec));
}


@override
int get hashCode => Object.hash(runtimeType,targetName,ra,dec);

@override
String toString() {
  return 'SequencerEvent.targetChanged(targetName: $targetName, ra: $ra, dec: $dec)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_TargetChangedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_TargetChangedCopyWith(SequencerEvent_TargetChanged value, $Res Function(SequencerEvent_TargetChanged) _then) = _$SequencerEvent_TargetChangedCopyWithImpl;
@useResult
$Res call({
 String targetName, double? ra, double? dec
});




}
/// @nodoc
class _$SequencerEvent_TargetChangedCopyWithImpl<$Res>
    implements $SequencerEvent_TargetChangedCopyWith<$Res> {
  _$SequencerEvent_TargetChangedCopyWithImpl(this._self, this._then);

  final SequencerEvent_TargetChanged _self;
  final $Res Function(SequencerEvent_TargetChanged) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetName = null,Object? ra = freezed,Object? dec = freezed,}) {
  return _then(SequencerEvent_TargetChanged(
targetName: null == targetName ? _self.targetName : targetName // ignore: cast_nullable_to_non_nullable
as String,ra: freezed == ra ? _self.ra : ra // ignore: cast_nullable_to_non_nullable
as double?,dec: freezed == dec ? _self.dec : dec // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class SequencerEvent_TargetCompleted extends SequencerEvent {
  const SequencerEvent_TargetCompleted({required this.targetName}): super._();
  

 final  String targetName;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_TargetCompletedCopyWith<SequencerEvent_TargetCompleted> get copyWith => _$SequencerEvent_TargetCompletedCopyWithImpl<SequencerEvent_TargetCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_TargetCompleted&&(identical(other.targetName, targetName) || other.targetName == targetName));
}


@override
int get hashCode => Object.hash(runtimeType,targetName);

@override
String toString() {
  return 'SequencerEvent.targetCompleted(targetName: $targetName)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_TargetCompletedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_TargetCompletedCopyWith(SequencerEvent_TargetCompleted value, $Res Function(SequencerEvent_TargetCompleted) _then) = _$SequencerEvent_TargetCompletedCopyWithImpl;
@useResult
$Res call({
 String targetName
});




}
/// @nodoc
class _$SequencerEvent_TargetCompletedCopyWithImpl<$Res>
    implements $SequencerEvent_TargetCompletedCopyWith<$Res> {
  _$SequencerEvent_TargetCompletedCopyWithImpl(this._self, this._then);

  final SequencerEvent_TargetCompleted _self;
  final $Res Function(SequencerEvent_TargetCompleted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetName = null,}) {
  return _then(SequencerEvent_TargetCompleted(
targetName: null == targetName ? _self.targetName : targetName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_ExposureStarted extends SequencerEvent {
  const SequencerEvent_ExposureStarted({required this.frame, required this.total, this.filter, required this.durationSecs}): super._();
  

 final  int frame;
 final  int total;
 final  String? filter;
 final  double durationSecs;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_ExposureStartedCopyWith<SequencerEvent_ExposureStarted> get copyWith => _$SequencerEvent_ExposureStartedCopyWithImpl<SequencerEvent_ExposureStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_ExposureStarted&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.durationSecs, durationSecs) || other.durationSecs == durationSecs));
}


@override
int get hashCode => Object.hash(runtimeType,frame,total,filter,durationSecs);

@override
String toString() {
  return 'SequencerEvent.exposureStarted(frame: $frame, total: $total, filter: $filter, durationSecs: $durationSecs)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_ExposureStartedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_ExposureStartedCopyWith(SequencerEvent_ExposureStarted value, $Res Function(SequencerEvent_ExposureStarted) _then) = _$SequencerEvent_ExposureStartedCopyWithImpl;
@useResult
$Res call({
 int frame, int total, String? filter, double durationSecs
});




}
/// @nodoc
class _$SequencerEvent_ExposureStartedCopyWithImpl<$Res>
    implements $SequencerEvent_ExposureStartedCopyWith<$Res> {
  _$SequencerEvent_ExposureStartedCopyWithImpl(this._self, this._then);

  final SequencerEvent_ExposureStarted _self;
  final $Res Function(SequencerEvent_ExposureStarted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? frame = null,Object? total = null,Object? filter = freezed,Object? durationSecs = null,}) {
  return _then(SequencerEvent_ExposureStarted(
frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,durationSecs: null == durationSecs ? _self.durationSecs : durationSecs // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class SequencerEvent_ExposureCompleted extends SequencerEvent {
  const SequencerEvent_ExposureCompleted({required this.frame, required this.total, required this.durationSecs}): super._();
  

 final  int frame;
 final  int total;
 final  double durationSecs;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_ExposureCompletedCopyWith<SequencerEvent_ExposureCompleted> get copyWith => _$SequencerEvent_ExposureCompletedCopyWithImpl<SequencerEvent_ExposureCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_ExposureCompleted&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.durationSecs, durationSecs) || other.durationSecs == durationSecs));
}


@override
int get hashCode => Object.hash(runtimeType,frame,total,durationSecs);

@override
String toString() {
  return 'SequencerEvent.exposureCompleted(frame: $frame, total: $total, durationSecs: $durationSecs)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_ExposureCompletedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_ExposureCompletedCopyWith(SequencerEvent_ExposureCompleted value, $Res Function(SequencerEvent_ExposureCompleted) _then) = _$SequencerEvent_ExposureCompletedCopyWithImpl;
@useResult
$Res call({
 int frame, int total, double durationSecs
});




}
/// @nodoc
class _$SequencerEvent_ExposureCompletedCopyWithImpl<$Res>
    implements $SequencerEvent_ExposureCompletedCopyWith<$Res> {
  _$SequencerEvent_ExposureCompletedCopyWithImpl(this._self, this._then);

  final SequencerEvent_ExposureCompleted _self;
  final $Res Function(SequencerEvent_ExposureCompleted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? frame = null,Object? total = null,Object? durationSecs = null,}) {
  return _then(SequencerEvent_ExposureCompleted(
frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,durationSecs: null == durationSecs ? _self.durationSecs : durationSecs // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class SequencerEvent_Error extends SequencerEvent {
  const SequencerEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_ErrorCopyWith<SequencerEvent_Error> get copyWith => _$SequencerEvent_ErrorCopyWithImpl<SequencerEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SequencerEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_ErrorCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_ErrorCopyWith(SequencerEvent_Error value, $Res Function(SequencerEvent_Error) _then) = _$SequencerEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SequencerEvent_ErrorCopyWithImpl<$Res>
    implements $SequencerEvent_ErrorCopyWith<$Res> {
  _$SequencerEvent_ErrorCopyWithImpl(this._self, this._then);

  final SequencerEvent_Error _self;
  final $Res Function(SequencerEvent_Error) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SequencerEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_MeridianFlipOutcome extends SequencerEvent {
  const SequencerEvent_MeridianFlipOutcome({required this.outcome, required this.targetName, required this.newPierSide, required this.durationSecs, required this.attempts, required final  List<String> failedSteps, this.error, this.actionTaken}): _failedSteps = failedSteps,super._();
  

/// `"success"`, `"failed"`, or `"aborted"`.
 final  String outcome;
/// Target the flip was performed for.
 final  String targetName;
/// Pier side reported after the flip (`East` / `West` / `Unknown`).
 final  String newPierSide;
/// Wall-clock seconds for the whole flip, retries included.
 final  double durationSecs;
/// Attempts made; `> 1` means the flip was DEGRADED.
 final  int attempts;
/// One `"<step>: <error>"` per failed attempt, oldest first.
 final  List<String> _failedSteps;
/// One `"<step>: <error>"` per failed attempt, oldest first.
 List<String> get failedSteps {
  if (_failedSteps is EqualUnmodifiableListView) return _failedSteps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_failedSteps);
}

/// Terminal error. `None` on a clean success.
 final  String? error;
/// Failure action executed (`"PauseAndAlert"` / `"AbortAndPark"`).
 final  String? actionTaken;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_MeridianFlipOutcomeCopyWith<SequencerEvent_MeridianFlipOutcome> get copyWith => _$SequencerEvent_MeridianFlipOutcomeCopyWithImpl<SequencerEvent_MeridianFlipOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_MeridianFlipOutcome&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.targetName, targetName) || other.targetName == targetName)&&(identical(other.newPierSide, newPierSide) || other.newPierSide == newPierSide)&&(identical(other.durationSecs, durationSecs) || other.durationSecs == durationSecs)&&(identical(other.attempts, attempts) || other.attempts == attempts)&&const DeepCollectionEquality().equals(other._failedSteps, _failedSteps)&&(identical(other.error, error) || other.error == error)&&(identical(other.actionTaken, actionTaken) || other.actionTaken == actionTaken));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,targetName,newPierSide,durationSecs,attempts,const DeepCollectionEquality().hash(_failedSteps),error,actionTaken);

@override
String toString() {
  return 'SequencerEvent.meridianFlipOutcome(outcome: $outcome, targetName: $targetName, newPierSide: $newPierSide, durationSecs: $durationSecs, attempts: $attempts, failedSteps: $failedSteps, error: $error, actionTaken: $actionTaken)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_MeridianFlipOutcomeCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_MeridianFlipOutcomeCopyWith(SequencerEvent_MeridianFlipOutcome value, $Res Function(SequencerEvent_MeridianFlipOutcome) _then) = _$SequencerEvent_MeridianFlipOutcomeCopyWithImpl;
@useResult
$Res call({
 String outcome, String targetName, String newPierSide, double durationSecs, int attempts, List<String> failedSteps, String? error, String? actionTaken
});




}
/// @nodoc
class _$SequencerEvent_MeridianFlipOutcomeCopyWithImpl<$Res>
    implements $SequencerEvent_MeridianFlipOutcomeCopyWith<$Res> {
  _$SequencerEvent_MeridianFlipOutcomeCopyWithImpl(this._self, this._then);

  final SequencerEvent_MeridianFlipOutcome _self;
  final $Res Function(SequencerEvent_MeridianFlipOutcome) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,Object? targetName = null,Object? newPierSide = null,Object? durationSecs = null,Object? attempts = null,Object? failedSteps = null,Object? error = freezed,Object? actionTaken = freezed,}) {
  return _then(SequencerEvent_MeridianFlipOutcome(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,targetName: null == targetName ? _self.targetName : targetName // ignore: cast_nullable_to_non_nullable
as String,newPierSide: null == newPierSide ? _self.newPierSide : newPierSide // ignore: cast_nullable_to_non_nullable
as String,durationSecs: null == durationSecs ? _self.durationSecs : durationSecs // ignore: cast_nullable_to_non_nullable
as double,attempts: null == attempts ? _self.attempts : attempts // ignore: cast_nullable_to_non_nullable
as int,failedSteps: null == failedSteps ? _self._failedSteps : failedSteps // ignore: cast_nullable_to_non_nullable
as List<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,actionTaken: freezed == actionTaken ? _self.actionTaken : actionTaken // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_TriggerFired extends SequencerEvent {
  const SequencerEvent_TriggerFired({required this.triggerId, required this.triggerName, required this.action}): super._();
  

/// Unique trigger identifier
 final  String triggerId;
/// Human-readable trigger name
 final  String triggerName;
/// Action taken (e.g., "Autofocus", "Dither", "PauseSequence")
 final  String action;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_TriggerFiredCopyWith<SequencerEvent_TriggerFired> get copyWith => _$SequencerEvent_TriggerFiredCopyWithImpl<SequencerEvent_TriggerFired>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_TriggerFired&&(identical(other.triggerId, triggerId) || other.triggerId == triggerId)&&(identical(other.triggerName, triggerName) || other.triggerName == triggerName)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode => Object.hash(runtimeType,triggerId,triggerName,action);

@override
String toString() {
  return 'SequencerEvent.triggerFired(triggerId: $triggerId, triggerName: $triggerName, action: $action)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_TriggerFiredCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_TriggerFiredCopyWith(SequencerEvent_TriggerFired value, $Res Function(SequencerEvent_TriggerFired) _then) = _$SequencerEvent_TriggerFiredCopyWithImpl;
@useResult
$Res call({
 String triggerId, String triggerName, String action
});




}
/// @nodoc
class _$SequencerEvent_TriggerFiredCopyWithImpl<$Res>
    implements $SequencerEvent_TriggerFiredCopyWith<$Res> {
  _$SequencerEvent_TriggerFiredCopyWithImpl(this._self, this._then);

  final SequencerEvent_TriggerFired _self;
  final $Res Function(SequencerEvent_TriggerFired) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? triggerId = null,Object? triggerName = null,Object? action = null,}) {
  return _then(SequencerEvent_TriggerFired(
triggerId: null == triggerId ? _self.triggerId : triggerId // ignore: cast_nullable_to_non_nullable
as String,triggerName: null == triggerName ? _self.triggerName : triggerName // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_InstructionProgress extends SequencerEvent {
  const SequencerEvent_InstructionProgress({required this.nodeId, required this.instruction, required this.progressPercent, required this.detail}): super._();
  

/// Node ID for mapping progress to the correct tree node
 final  String nodeId;
/// Name of the instruction (e.g., "Cool Camera", "Autofocus")
 final  String instruction;
/// Progress percentage (0.0 to 100.0)
 final  double progressPercent;
/// Detailed status message
 final  String detail;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_InstructionProgressCopyWith<SequencerEvent_InstructionProgress> get copyWith => _$SequencerEvent_InstructionProgressCopyWithImpl<SequencerEvent_InstructionProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_InstructionProgress&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.progressPercent, progressPercent) || other.progressPercent == progressPercent)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,instruction,progressPercent,detail);

@override
String toString() {
  return 'SequencerEvent.instructionProgress(nodeId: $nodeId, instruction: $instruction, progressPercent: $progressPercent, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_InstructionProgressCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_InstructionProgressCopyWith(SequencerEvent_InstructionProgress value, $Res Function(SequencerEvent_InstructionProgress) _then) = _$SequencerEvent_InstructionProgressCopyWithImpl;
@useResult
$Res call({
 String nodeId, String instruction, double progressPercent, String detail
});




}
/// @nodoc
class _$SequencerEvent_InstructionProgressCopyWithImpl<$Res>
    implements $SequencerEvent_InstructionProgressCopyWith<$Res> {
  _$SequencerEvent_InstructionProgressCopyWithImpl(this._self, this._then);

  final SequencerEvent_InstructionProgress _self;
  final $Res Function(SequencerEvent_InstructionProgress) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? instruction = null,Object? progressPercent = null,Object? detail = null,}) {
  return _then(SequencerEvent_InstructionProgress(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,progressPercent: null == progressPercent ? _self.progressPercent : progressPercent // ignore: cast_nullable_to_non_nullable
as double,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_InstructionProgressStructured extends SequencerEvent {
  const SequencerEvent_InstructionProgressStructured({required this.nodeId, required this.instruction, required this.progressPercent, required this.detailKind, required this.detailJson}): super._();
  

/// Node ID for mapping progress to the correct tree node
 final  String nodeId;
/// Name of the instruction (e.g., "Cool Camera", "Autofocus")
 final  String instruction;
/// Progress percentage (0.0 to 100.0)
 final  double progressPercent;
/// `ProgressDetail` variant name (e.g. `Exposure`, `Autofocus`)
 final  String detailKind;
/// JSON-stringified inner payload for the variant.
 final  String detailJson;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_InstructionProgressStructuredCopyWith<SequencerEvent_InstructionProgressStructured> get copyWith => _$SequencerEvent_InstructionProgressStructuredCopyWithImpl<SequencerEvent_InstructionProgressStructured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_InstructionProgressStructured&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.progressPercent, progressPercent) || other.progressPercent == progressPercent)&&(identical(other.detailKind, detailKind) || other.detailKind == detailKind)&&(identical(other.detailJson, detailJson) || other.detailJson == detailJson));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,instruction,progressPercent,detailKind,detailJson);

@override
String toString() {
  return 'SequencerEvent.instructionProgressStructured(nodeId: $nodeId, instruction: $instruction, progressPercent: $progressPercent, detailKind: $detailKind, detailJson: $detailJson)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_InstructionProgressStructuredCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_InstructionProgressStructuredCopyWith(SequencerEvent_InstructionProgressStructured value, $Res Function(SequencerEvent_InstructionProgressStructured) _then) = _$SequencerEvent_InstructionProgressStructuredCopyWithImpl;
@useResult
$Res call({
 String nodeId, String instruction, double progressPercent, String detailKind, String detailJson
});




}
/// @nodoc
class _$SequencerEvent_InstructionProgressStructuredCopyWithImpl<$Res>
    implements $SequencerEvent_InstructionProgressStructuredCopyWith<$Res> {
  _$SequencerEvent_InstructionProgressStructuredCopyWithImpl(this._self, this._then);

  final SequencerEvent_InstructionProgressStructured _self;
  final $Res Function(SequencerEvent_InstructionProgressStructured) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? instruction = null,Object? progressPercent = null,Object? detailKind = null,Object? detailJson = null,}) {
  return _then(SequencerEvent_InstructionProgressStructured(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,progressPercent: null == progressPercent ? _self.progressPercent : progressPercent // ignore: cast_nullable_to_non_nullable
as double,detailKind: null == detailKind ? _self.detailKind : detailKind // ignore: cast_nullable_to_non_nullable
as String,detailJson: null == detailJson ? _self.detailJson : detailJson // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_FrameAccepted extends SequencerEvent {
  const SequencerEvent_FrameAccepted({required this.nodeId, required this.frame, required this.total, this.hfr, this.eccentricity, this.starCount, required this.acceptedTotal, required this.rejectedTotal, this.savePath}): super._();
  

 final  String nodeId;
/// 1-based frame index within the current TakeExposure burst.
 final  int frame;
 final  int total;
 final  double? hfr;
 final  double? eccentricity;
 final  int? starCount;
/// Running count of accepted frames for the whole run.
 final  int acceptedTotal;
/// Running count of rejected frames for the whole run.
 final  int rejectedTotal;
/// on-disk save path of the accepted frame, so
/// the thumbnail strip can render an inline preview of
/// accepted frames the same way it already does for rejected
/// frames via `FrameRejected.reject_path`. `None` for legacy /
/// non-grading emit sites that did not thread the path through.
 final  String? savePath;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_FrameAcceptedCopyWith<SequencerEvent_FrameAccepted> get copyWith => _$SequencerEvent_FrameAcceptedCopyWithImpl<SequencerEvent_FrameAccepted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_FrameAccepted&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.hfr, hfr) || other.hfr == hfr)&&(identical(other.eccentricity, eccentricity) || other.eccentricity == eccentricity)&&(identical(other.starCount, starCount) || other.starCount == starCount)&&(identical(other.acceptedTotal, acceptedTotal) || other.acceptedTotal == acceptedTotal)&&(identical(other.rejectedTotal, rejectedTotal) || other.rejectedTotal == rejectedTotal)&&(identical(other.savePath, savePath) || other.savePath == savePath));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,frame,total,hfr,eccentricity,starCount,acceptedTotal,rejectedTotal,savePath);

@override
String toString() {
  return 'SequencerEvent.frameAccepted(nodeId: $nodeId, frame: $frame, total: $total, hfr: $hfr, eccentricity: $eccentricity, starCount: $starCount, acceptedTotal: $acceptedTotal, rejectedTotal: $rejectedTotal, savePath: $savePath)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_FrameAcceptedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_FrameAcceptedCopyWith(SequencerEvent_FrameAccepted value, $Res Function(SequencerEvent_FrameAccepted) _then) = _$SequencerEvent_FrameAcceptedCopyWithImpl;
@useResult
$Res call({
 String nodeId, int frame, int total, double? hfr, double? eccentricity, int? starCount, int acceptedTotal, int rejectedTotal, String? savePath
});




}
/// @nodoc
class _$SequencerEvent_FrameAcceptedCopyWithImpl<$Res>
    implements $SequencerEvent_FrameAcceptedCopyWith<$Res> {
  _$SequencerEvent_FrameAcceptedCopyWithImpl(this._self, this._then);

  final SequencerEvent_FrameAccepted _self;
  final $Res Function(SequencerEvent_FrameAccepted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? frame = null,Object? total = null,Object? hfr = freezed,Object? eccentricity = freezed,Object? starCount = freezed,Object? acceptedTotal = null,Object? rejectedTotal = null,Object? savePath = freezed,}) {
  return _then(SequencerEvent_FrameAccepted(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,hfr: freezed == hfr ? _self.hfr : hfr // ignore: cast_nullable_to_non_nullable
as double?,eccentricity: freezed == eccentricity ? _self.eccentricity : eccentricity // ignore: cast_nullable_to_non_nullable
as double?,starCount: freezed == starCount ? _self.starCount : starCount // ignore: cast_nullable_to_non_nullable
as int?,acceptedTotal: null == acceptedTotal ? _self.acceptedTotal : acceptedTotal // ignore: cast_nullable_to_non_nullable
as int,rejectedTotal: null == rejectedTotal ? _self.rejectedTotal : rejectedTotal // ignore: cast_nullable_to_non_nullable
as int,savePath: freezed == savePath ? _self.savePath : savePath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_FrameRejected extends SequencerEvent {
  const SequencerEvent_FrameRejected({required this.nodeId, required this.frame, required this.total, required this.reason, this.hfr, this.eccentricity, this.starCount, required this.rejectPath, required this.consecutiveRejects, required this.acceptedTotal, required this.rejectedTotal, this.likelyCauseLabel, required final  List<String> evidence, this.skyBrightnessAtCapture, this.cloudCoverAtCapture, this.windAtCapture, this.guideRmsAtCapture, this.sensorTempAtCapture}): _evidence = evidence,super._();
  

 final  String nodeId;
 final  int frame;
 final  int total;
 final  String reason;
 final  double? hfr;
 final  double? eccentricity;
 final  int? starCount;
 final  String rejectPath;
/// Running consecutive-rejects counter. When this reaches the
/// configured `max_consecutive_rejects`, the executor pauses
/// the sequence and emits an additional `Error` event.
 final  int consecutiveRejects;
 final  int acceptedTotal;
 final  int rejectedTotal;
/// Classified cause label (wire-stable snake_case string from
/// `LikelyCause::label()`). `None` when the classifier was not
/// consulted or could not pick a single best guess. Dart maps
/// this back to its `LikelyCause` enum via
/// `LikelyCauseExt.fromLabel`.
 final  String? likelyCauseLabel;
/// Human-readable evidence bullets the dashboard surfaces in
/// the Forensics panel and Frame Detail dialog. Empty list
/// when no telemetry was available.
 final  List<String> _evidence;
/// Human-readable evidence bullets the dashboard surfaces in
/// the Forensics panel and Frame Detail dialog. Empty list
/// when no telemetry was available.
 List<String> get evidence {
  if (_evidence is EqualUnmodifiableListView) return _evidence;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_evidence);
}

/// Sky brightness reading at capture time (mag/arcsec²).
 final  double? skyBrightnessAtCapture;
/// Cloud cover percentage (0-100) at capture time.
 final  double? cloudCoverAtCapture;
/// Wind speed at capture time (km/h). `None` when no weather
/// feed is wired through to the sequencer.
 final  double? windAtCapture;
/// Guide RMS (arc-seconds) sampled at capture time.
 final  double? guideRmsAtCapture;
/// Sensor temperature (°C) at capture time.
 final  double? sensorTempAtCapture;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_FrameRejectedCopyWith<SequencerEvent_FrameRejected> get copyWith => _$SequencerEvent_FrameRejectedCopyWithImpl<SequencerEvent_FrameRejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_FrameRejected&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.hfr, hfr) || other.hfr == hfr)&&(identical(other.eccentricity, eccentricity) || other.eccentricity == eccentricity)&&(identical(other.starCount, starCount) || other.starCount == starCount)&&(identical(other.rejectPath, rejectPath) || other.rejectPath == rejectPath)&&(identical(other.consecutiveRejects, consecutiveRejects) || other.consecutiveRejects == consecutiveRejects)&&(identical(other.acceptedTotal, acceptedTotal) || other.acceptedTotal == acceptedTotal)&&(identical(other.rejectedTotal, rejectedTotal) || other.rejectedTotal == rejectedTotal)&&(identical(other.likelyCauseLabel, likelyCauseLabel) || other.likelyCauseLabel == likelyCauseLabel)&&const DeepCollectionEquality().equals(other._evidence, _evidence)&&(identical(other.skyBrightnessAtCapture, skyBrightnessAtCapture) || other.skyBrightnessAtCapture == skyBrightnessAtCapture)&&(identical(other.cloudCoverAtCapture, cloudCoverAtCapture) || other.cloudCoverAtCapture == cloudCoverAtCapture)&&(identical(other.windAtCapture, windAtCapture) || other.windAtCapture == windAtCapture)&&(identical(other.guideRmsAtCapture, guideRmsAtCapture) || other.guideRmsAtCapture == guideRmsAtCapture)&&(identical(other.sensorTempAtCapture, sensorTempAtCapture) || other.sensorTempAtCapture == sensorTempAtCapture));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,frame,total,reason,hfr,eccentricity,starCount,rejectPath,consecutiveRejects,acceptedTotal,rejectedTotal,likelyCauseLabel,const DeepCollectionEquality().hash(_evidence),skyBrightnessAtCapture,cloudCoverAtCapture,windAtCapture,guideRmsAtCapture,sensorTempAtCapture);

@override
String toString() {
  return 'SequencerEvent.frameRejected(nodeId: $nodeId, frame: $frame, total: $total, reason: $reason, hfr: $hfr, eccentricity: $eccentricity, starCount: $starCount, rejectPath: $rejectPath, consecutiveRejects: $consecutiveRejects, acceptedTotal: $acceptedTotal, rejectedTotal: $rejectedTotal, likelyCauseLabel: $likelyCauseLabel, evidence: $evidence, skyBrightnessAtCapture: $skyBrightnessAtCapture, cloudCoverAtCapture: $cloudCoverAtCapture, windAtCapture: $windAtCapture, guideRmsAtCapture: $guideRmsAtCapture, sensorTempAtCapture: $sensorTempAtCapture)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_FrameRejectedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_FrameRejectedCopyWith(SequencerEvent_FrameRejected value, $Res Function(SequencerEvent_FrameRejected) _then) = _$SequencerEvent_FrameRejectedCopyWithImpl;
@useResult
$Res call({
 String nodeId, int frame, int total, String reason, double? hfr, double? eccentricity, int? starCount, String rejectPath, int consecutiveRejects, int acceptedTotal, int rejectedTotal, String? likelyCauseLabel, List<String> evidence, double? skyBrightnessAtCapture, double? cloudCoverAtCapture, double? windAtCapture, double? guideRmsAtCapture, double? sensorTempAtCapture
});




}
/// @nodoc
class _$SequencerEvent_FrameRejectedCopyWithImpl<$Res>
    implements $SequencerEvent_FrameRejectedCopyWith<$Res> {
  _$SequencerEvent_FrameRejectedCopyWithImpl(this._self, this._then);

  final SequencerEvent_FrameRejected _self;
  final $Res Function(SequencerEvent_FrameRejected) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? frame = null,Object? total = null,Object? reason = null,Object? hfr = freezed,Object? eccentricity = freezed,Object? starCount = freezed,Object? rejectPath = null,Object? consecutiveRejects = null,Object? acceptedTotal = null,Object? rejectedTotal = null,Object? likelyCauseLabel = freezed,Object? evidence = null,Object? skyBrightnessAtCapture = freezed,Object? cloudCoverAtCapture = freezed,Object? windAtCapture = freezed,Object? guideRmsAtCapture = freezed,Object? sensorTempAtCapture = freezed,}) {
  return _then(SequencerEvent_FrameRejected(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,hfr: freezed == hfr ? _self.hfr : hfr // ignore: cast_nullable_to_non_nullable
as double?,eccentricity: freezed == eccentricity ? _self.eccentricity : eccentricity // ignore: cast_nullable_to_non_nullable
as double?,starCount: freezed == starCount ? _self.starCount : starCount // ignore: cast_nullable_to_non_nullable
as int?,rejectPath: null == rejectPath ? _self.rejectPath : rejectPath // ignore: cast_nullable_to_non_nullable
as String,consecutiveRejects: null == consecutiveRejects ? _self.consecutiveRejects : consecutiveRejects // ignore: cast_nullable_to_non_nullable
as int,acceptedTotal: null == acceptedTotal ? _self.acceptedTotal : acceptedTotal // ignore: cast_nullable_to_non_nullable
as int,rejectedTotal: null == rejectedTotal ? _self.rejectedTotal : rejectedTotal // ignore: cast_nullable_to_non_nullable
as int,likelyCauseLabel: freezed == likelyCauseLabel ? _self.likelyCauseLabel : likelyCauseLabel // ignore: cast_nullable_to_non_nullable
as String?,evidence: null == evidence ? _self._evidence : evidence // ignore: cast_nullable_to_non_nullable
as List<String>,skyBrightnessAtCapture: freezed == skyBrightnessAtCapture ? _self.skyBrightnessAtCapture : skyBrightnessAtCapture // ignore: cast_nullable_to_non_nullable
as double?,cloudCoverAtCapture: freezed == cloudCoverAtCapture ? _self.cloudCoverAtCapture : cloudCoverAtCapture // ignore: cast_nullable_to_non_nullable
as double?,windAtCapture: freezed == windAtCapture ? _self.windAtCapture : windAtCapture // ignore: cast_nullable_to_non_nullable
as double?,guideRmsAtCapture: freezed == guideRmsAtCapture ? _self.guideRmsAtCapture : guideRmsAtCapture // ignore: cast_nullable_to_non_nullable
as double?,sensorTempAtCapture: freezed == sensorTempAtCapture ? _self.sensorTempAtCapture : sensorTempAtCapture // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class SequencerEvent_SchedulerDecision extends SequencerEvent {
  const SequencerEvent_SchedulerDecision({required this.nodeId, required this.decisionCounter, this.pickedTargetId, this.pickedTargetName, this.pickedScore, required final  List<SchedulerScoreEntry> scores}): _scores = scores,super._();
  

 final  String nodeId;
/// 1-based decision counter for this scheduler instance.
 final  int decisionCounter;
/// `None` when no target cleared `min_score_to_run`.
 final  String? pickedTargetId;
 final  String? pickedTargetName;
/// Picked target's total score (0..=100). `None` when nothing
/// was picked.
 final  double? pickedScore;
/// Flat score table (runnable first, then by descending total).
 final  List<SchedulerScoreEntry> _scores;
/// Flat score table (runnable first, then by descending total).
 List<SchedulerScoreEntry> get scores {
  if (_scores is EqualUnmodifiableListView) return _scores;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_scores);
}


/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_SchedulerDecisionCopyWith<SequencerEvent_SchedulerDecision> get copyWith => _$SequencerEvent_SchedulerDecisionCopyWithImpl<SequencerEvent_SchedulerDecision>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_SchedulerDecision&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.decisionCounter, decisionCounter) || other.decisionCounter == decisionCounter)&&(identical(other.pickedTargetId, pickedTargetId) || other.pickedTargetId == pickedTargetId)&&(identical(other.pickedTargetName, pickedTargetName) || other.pickedTargetName == pickedTargetName)&&(identical(other.pickedScore, pickedScore) || other.pickedScore == pickedScore)&&const DeepCollectionEquality().equals(other._scores, _scores));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,decisionCounter,pickedTargetId,pickedTargetName,pickedScore,const DeepCollectionEquality().hash(_scores));

@override
String toString() {
  return 'SequencerEvent.schedulerDecision(nodeId: $nodeId, decisionCounter: $decisionCounter, pickedTargetId: $pickedTargetId, pickedTargetName: $pickedTargetName, pickedScore: $pickedScore, scores: $scores)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_SchedulerDecisionCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_SchedulerDecisionCopyWith(SequencerEvent_SchedulerDecision value, $Res Function(SequencerEvent_SchedulerDecision) _then) = _$SequencerEvent_SchedulerDecisionCopyWithImpl;
@useResult
$Res call({
 String nodeId, int decisionCounter, String? pickedTargetId, String? pickedTargetName, double? pickedScore, List<SchedulerScoreEntry> scores
});




}
/// @nodoc
class _$SequencerEvent_SchedulerDecisionCopyWithImpl<$Res>
    implements $SequencerEvent_SchedulerDecisionCopyWith<$Res> {
  _$SequencerEvent_SchedulerDecisionCopyWithImpl(this._self, this._then);

  final SequencerEvent_SchedulerDecision _self;
  final $Res Function(SequencerEvent_SchedulerDecision) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? decisionCounter = null,Object? pickedTargetId = freezed,Object? pickedTargetName = freezed,Object? pickedScore = freezed,Object? scores = null,}) {
  return _then(SequencerEvent_SchedulerDecision(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,decisionCounter: null == decisionCounter ? _self.decisionCounter : decisionCounter // ignore: cast_nullable_to_non_nullable
as int,pickedTargetId: freezed == pickedTargetId ? _self.pickedTargetId : pickedTargetId // ignore: cast_nullable_to_non_nullable
as String?,pickedTargetName: freezed == pickedTargetName ? _self.pickedTargetName : pickedTargetName // ignore: cast_nullable_to_non_nullable
as String?,pickedScore: freezed == pickedScore ? _self.pickedScore : pickedScore // ignore: cast_nullable_to_non_nullable
as double?,scores: null == scores ? _self._scores : scores // ignore: cast_nullable_to_non_nullable
as List<SchedulerScoreEntry>,
  ));
}


}

/// @nodoc


class SequencerEvent_IntegrationBudget extends SequencerEvent {
  const SequencerEvent_IntegrationBudget({required this.targetId, required this.filter, required this.completedSecs, required this.budgetSecs, required this.fraction, required this.budgetMet}): super._();
  

/// The TargetHeader node id this budget belongs to.
 final  String targetId;
/// Filter the credit was applied to (`""` for no-filter cameras).
 final  String filter;
 final  double completedSecs;
 final  double budgetSecs;
 final  double fraction;
 final  bool budgetMet;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_IntegrationBudgetCopyWith<SequencerEvent_IntegrationBudget> get copyWith => _$SequencerEvent_IntegrationBudgetCopyWithImpl<SequencerEvent_IntegrationBudget>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_IntegrationBudget&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.completedSecs, completedSecs) || other.completedSecs == completedSecs)&&(identical(other.budgetSecs, budgetSecs) || other.budgetSecs == budgetSecs)&&(identical(other.fraction, fraction) || other.fraction == fraction)&&(identical(other.budgetMet, budgetMet) || other.budgetMet == budgetMet));
}


@override
int get hashCode => Object.hash(runtimeType,targetId,filter,completedSecs,budgetSecs,fraction,budgetMet);

@override
String toString() {
  return 'SequencerEvent.integrationBudget(targetId: $targetId, filter: $filter, completedSecs: $completedSecs, budgetSecs: $budgetSecs, fraction: $fraction, budgetMet: $budgetMet)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_IntegrationBudgetCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_IntegrationBudgetCopyWith(SequencerEvent_IntegrationBudget value, $Res Function(SequencerEvent_IntegrationBudget) _then) = _$SequencerEvent_IntegrationBudgetCopyWithImpl;
@useResult
$Res call({
 String targetId, String filter, double completedSecs, double budgetSecs, double fraction, bool budgetMet
});




}
/// @nodoc
class _$SequencerEvent_IntegrationBudgetCopyWithImpl<$Res>
    implements $SequencerEvent_IntegrationBudgetCopyWith<$Res> {
  _$SequencerEvent_IntegrationBudgetCopyWithImpl(this._self, this._then);

  final SequencerEvent_IntegrationBudget _self;
  final $Res Function(SequencerEvent_IntegrationBudget) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetId = null,Object? filter = null,Object? completedSecs = null,Object? budgetSecs = null,Object? fraction = null,Object? budgetMet = null,}) {
  return _then(SequencerEvent_IntegrationBudget(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String,completedSecs: null == completedSecs ? _self.completedSecs : completedSecs // ignore: cast_nullable_to_non_nullable
as double,budgetSecs: null == budgetSecs ? _self.budgetSecs : budgetSecs // ignore: cast_nullable_to_non_nullable
as double,fraction: null == fraction ? _self.fraction : fraction // ignore: cast_nullable_to_non_nullable
as double,budgetMet: null == budgetMet ? _self.budgetMet : budgetMet // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class SequencerEvent_ExposureAdjusted extends SequencerEvent {
  const SequencerEvent_ExposureAdjusted({required this.nodeId, required this.adaptedSecs, required this.nominalSecs, this.skyBrightnessMag, this.filter, required this.reason}): super._();
  

 final  String nodeId;
/// Adapted (effective) exposure duration in seconds.
 final  double adaptedSecs;
/// User-configured nominal duration in seconds.
 final  double nominalSecs;
/// Live sky brightness used in the decision (mag/arcsec²). `None`
/// when the adapter fell back due to missing telemetry.
 final  double? skyBrightnessMag;
/// Filter being captured through. `None` for monochrome / no
/// filter wheel rigs.
 final  String? filter;
/// Lowercase tag: `adapted`, `clamped_min`, `clamped_max`,
/// `unavailable`, `disabled`, `out_of_nominal_bounds`.
 final  String reason;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_ExposureAdjustedCopyWith<SequencerEvent_ExposureAdjusted> get copyWith => _$SequencerEvent_ExposureAdjustedCopyWithImpl<SequencerEvent_ExposureAdjusted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_ExposureAdjusted&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.adaptedSecs, adaptedSecs) || other.adaptedSecs == adaptedSecs)&&(identical(other.nominalSecs, nominalSecs) || other.nominalSecs == nominalSecs)&&(identical(other.skyBrightnessMag, skyBrightnessMag) || other.skyBrightnessMag == skyBrightnessMag)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,adaptedSecs,nominalSecs,skyBrightnessMag,filter,reason);

@override
String toString() {
  return 'SequencerEvent.exposureAdjusted(nodeId: $nodeId, adaptedSecs: $adaptedSecs, nominalSecs: $nominalSecs, skyBrightnessMag: $skyBrightnessMag, filter: $filter, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_ExposureAdjustedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_ExposureAdjustedCopyWith(SequencerEvent_ExposureAdjusted value, $Res Function(SequencerEvent_ExposureAdjusted) _then) = _$SequencerEvent_ExposureAdjustedCopyWithImpl;
@useResult
$Res call({
 String nodeId, double adaptedSecs, double nominalSecs, double? skyBrightnessMag, String? filter, String reason
});




}
/// @nodoc
class _$SequencerEvent_ExposureAdjustedCopyWithImpl<$Res>
    implements $SequencerEvent_ExposureAdjustedCopyWith<$Res> {
  _$SequencerEvent_ExposureAdjustedCopyWithImpl(this._self, this._then);

  final SequencerEvent_ExposureAdjusted _self;
  final $Res Function(SequencerEvent_ExposureAdjusted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? adaptedSecs = null,Object? nominalSecs = null,Object? skyBrightnessMag = freezed,Object? filter = freezed,Object? reason = null,}) {
  return _then(SequencerEvent_ExposureAdjusted(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,adaptedSecs: null == adaptedSecs ? _self.adaptedSecs : adaptedSecs // ignore: cast_nullable_to_non_nullable
as double,nominalSecs: null == nominalSecs ? _self.nominalSecs : nominalSecs // ignore: cast_nullable_to_non_nullable
as double,skyBrightnessMag: freezed == skyBrightnessMag ? _self.skyBrightnessMag : skyBrightnessMag // ignore: cast_nullable_to_non_nullable
as double?,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_PhotometryFrame extends SequencerEvent {
  const SequencerEvent_PhotometryFrame({required this.nodeId, required this.targetDesignation, required final  List<String> referenceStars, required this.frame, required this.total, required this.filter, required this.exposureSecs, this.airmass, this.fwhmArcsec, this.snr, required this.mjdObs, required this.frameStartUnix, required this.accepted, this.rejectReason, required this.reduceLive, required this.applyDifferential}): _referenceStars = referenceStars,super._();
  

/// Node ID for mapping progress to the correct tree node.
 final  String nodeId;
/// Resolved target designation (e.g. `"V* DY Peg"`).
 final  String targetDesignation;
/// Reference / comparison star designations used for differential
/// photometry. Empty when differential photometry is disabled.
 final  List<String> _referenceStars;
/// Reference / comparison star designations used for differential
/// photometry. Empty when differential photometry is disabled.
 List<String> get referenceStars {
  if (_referenceStars is EqualUnmodifiableListView) return _referenceStars;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_referenceStars);
}

/// 1-based frame index within the current photometry burst.
 final  int frame;
 final  int total;
 final  String filter;
 final  double exposureSecs;
/// Airmass at exposure midpoint. `None` when no WCS / pointing was
/// available to compute it.
 final  double? airmass;
/// Measured stellar FWHM (arc-seconds). `None` when the frame yielded
/// no usable star measurement.
 final  double? fwhmArcsec;
/// Signal-to-noise ratio of the target aperture. `None` when not
/// measured.
 final  double? snr;
/// Modified Julian Date at exposure midpoint (FITS `MJD-OBS`).
 final  double mjdObs;
/// Unix epoch seconds at exposure start.
 final  double frameStartUnix;
/// True when the frame passed every quality gate
/// (`PhotometryFrameVerdict::Pass`).
 final  bool accepted;
/// Rejection reason when `accepted == false`
/// (`PhotometryFrameVerdict::Reject { reason }`); `None` when accepted.
 final  String? rejectReason;
/// True when live reduction was performed for this frame.
 final  bool reduceLive;
/// True when differential photometry was applied for this frame.
 final  bool applyDifferential;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_PhotometryFrameCopyWith<SequencerEvent_PhotometryFrame> get copyWith => _$SequencerEvent_PhotometryFrameCopyWithImpl<SequencerEvent_PhotometryFrame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_PhotometryFrame&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.targetDesignation, targetDesignation) || other.targetDesignation == targetDesignation)&&const DeepCollectionEquality().equals(other._referenceStars, _referenceStars)&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.exposureSecs, exposureSecs) || other.exposureSecs == exposureSecs)&&(identical(other.airmass, airmass) || other.airmass == airmass)&&(identical(other.fwhmArcsec, fwhmArcsec) || other.fwhmArcsec == fwhmArcsec)&&(identical(other.snr, snr) || other.snr == snr)&&(identical(other.mjdObs, mjdObs) || other.mjdObs == mjdObs)&&(identical(other.frameStartUnix, frameStartUnix) || other.frameStartUnix == frameStartUnix)&&(identical(other.accepted, accepted) || other.accepted == accepted)&&(identical(other.rejectReason, rejectReason) || other.rejectReason == rejectReason)&&(identical(other.reduceLive, reduceLive) || other.reduceLive == reduceLive)&&(identical(other.applyDifferential, applyDifferential) || other.applyDifferential == applyDifferential));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,targetDesignation,const DeepCollectionEquality().hash(_referenceStars),frame,total,filter,exposureSecs,airmass,fwhmArcsec,snr,mjdObs,frameStartUnix,accepted,rejectReason,reduceLive,applyDifferential);

@override
String toString() {
  return 'SequencerEvent.photometryFrame(nodeId: $nodeId, targetDesignation: $targetDesignation, referenceStars: $referenceStars, frame: $frame, total: $total, filter: $filter, exposureSecs: $exposureSecs, airmass: $airmass, fwhmArcsec: $fwhmArcsec, snr: $snr, mjdObs: $mjdObs, frameStartUnix: $frameStartUnix, accepted: $accepted, rejectReason: $rejectReason, reduceLive: $reduceLive, applyDifferential: $applyDifferential)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_PhotometryFrameCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_PhotometryFrameCopyWith(SequencerEvent_PhotometryFrame value, $Res Function(SequencerEvent_PhotometryFrame) _then) = _$SequencerEvent_PhotometryFrameCopyWithImpl;
@useResult
$Res call({
 String nodeId, String targetDesignation, List<String> referenceStars, int frame, int total, String filter, double exposureSecs, double? airmass, double? fwhmArcsec, double? snr, double mjdObs, double frameStartUnix, bool accepted, String? rejectReason, bool reduceLive, bool applyDifferential
});




}
/// @nodoc
class _$SequencerEvent_PhotometryFrameCopyWithImpl<$Res>
    implements $SequencerEvent_PhotometryFrameCopyWith<$Res> {
  _$SequencerEvent_PhotometryFrameCopyWithImpl(this._self, this._then);

  final SequencerEvent_PhotometryFrame _self;
  final $Res Function(SequencerEvent_PhotometryFrame) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? targetDesignation = null,Object? referenceStars = null,Object? frame = null,Object? total = null,Object? filter = null,Object? exposureSecs = null,Object? airmass = freezed,Object? fwhmArcsec = freezed,Object? snr = freezed,Object? mjdObs = null,Object? frameStartUnix = null,Object? accepted = null,Object? rejectReason = freezed,Object? reduceLive = null,Object? applyDifferential = null,}) {
  return _then(SequencerEvent_PhotometryFrame(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,targetDesignation: null == targetDesignation ? _self.targetDesignation : targetDesignation // ignore: cast_nullable_to_non_nullable
as String,referenceStars: null == referenceStars ? _self._referenceStars : referenceStars // ignore: cast_nullable_to_non_nullable
as List<String>,frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String,exposureSecs: null == exposureSecs ? _self.exposureSecs : exposureSecs // ignore: cast_nullable_to_non_nullable
as double,airmass: freezed == airmass ? _self.airmass : airmass // ignore: cast_nullable_to_non_nullable
as double?,fwhmArcsec: freezed == fwhmArcsec ? _self.fwhmArcsec : fwhmArcsec // ignore: cast_nullable_to_non_nullable
as double?,snr: freezed == snr ? _self.snr : snr // ignore: cast_nullable_to_non_nullable
as double?,mjdObs: null == mjdObs ? _self.mjdObs : mjdObs // ignore: cast_nullable_to_non_nullable
as double,frameStartUnix: null == frameStartUnix ? _self.frameStartUnix : frameStartUnix // ignore: cast_nullable_to_non_nullable
as double,accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,rejectReason: freezed == rejectReason ? _self.rejectReason : rejectReason // ignore: cast_nullable_to_non_nullable
as String?,reduceLive: null == reduceLive ? _self.reduceLive : reduceLive // ignore: cast_nullable_to_non_nullable
as bool,applyDifferential: null == applyDifferential ? _self.applyDifferential : applyDifferential // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class SequencerEvent_PhotometryCadenceBroken extends SequencerEvent {
  const SequencerEvent_PhotometryCadenceBroken({required this.nodeId, required this.frame, required this.total, required this.gapSecs, required this.maxGapSecs, required this.cadenceBreaks}): super._();
  

/// Node ID for mapping progress to the correct tree node.
 final  String nodeId;
/// 1-based frame index whose start broke the cadence.
 final  int frame;
 final  int total;
/// Observed start-to-start gap (seconds).
 final  double gapSecs;
/// Configured maximum allowed gap (seconds).
 final  double maxGapSecs;
/// Cumulative cadence breaks for the current node run.
 final  int cadenceBreaks;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_PhotometryCadenceBrokenCopyWith<SequencerEvent_PhotometryCadenceBroken> get copyWith => _$SequencerEvent_PhotometryCadenceBrokenCopyWithImpl<SequencerEvent_PhotometryCadenceBroken>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_PhotometryCadenceBroken&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.total, total) || other.total == total)&&(identical(other.gapSecs, gapSecs) || other.gapSecs == gapSecs)&&(identical(other.maxGapSecs, maxGapSecs) || other.maxGapSecs == maxGapSecs)&&(identical(other.cadenceBreaks, cadenceBreaks) || other.cadenceBreaks == cadenceBreaks));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,frame,total,gapSecs,maxGapSecs,cadenceBreaks);

@override
String toString() {
  return 'SequencerEvent.photometryCadenceBroken(nodeId: $nodeId, frame: $frame, total: $total, gapSecs: $gapSecs, maxGapSecs: $maxGapSecs, cadenceBreaks: $cadenceBreaks)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_PhotometryCadenceBrokenCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_PhotometryCadenceBrokenCopyWith(SequencerEvent_PhotometryCadenceBroken value, $Res Function(SequencerEvent_PhotometryCadenceBroken) _then) = _$SequencerEvent_PhotometryCadenceBrokenCopyWithImpl;
@useResult
$Res call({
 String nodeId, int frame, int total, double gapSecs, double maxGapSecs, int cadenceBreaks
});




}
/// @nodoc
class _$SequencerEvent_PhotometryCadenceBrokenCopyWithImpl<$Res>
    implements $SequencerEvent_PhotometryCadenceBrokenCopyWith<$Res> {
  _$SequencerEvent_PhotometryCadenceBrokenCopyWithImpl(this._self, this._then);

  final SequencerEvent_PhotometryCadenceBroken _self;
  final $Res Function(SequencerEvent_PhotometryCadenceBroken) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? frame = null,Object? total = null,Object? gapSecs = null,Object? maxGapSecs = null,Object? cadenceBreaks = null,}) {
  return _then(SequencerEvent_PhotometryCadenceBroken(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,frame: null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,gapSecs: null == gapSecs ? _self.gapSecs : gapSecs // ignore: cast_nullable_to_non_nullable
as double,maxGapSecs: null == maxGapSecs ? _self.maxGapSecs : maxGapSecs // ignore: cast_nullable_to_non_nullable
as double,cadenceBreaks: null == cadenceBreaks ? _self.cadenceBreaks : cadenceBreaks // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class SequencerEvent_PhotometrySummary extends SequencerEvent {
  const SequencerEvent_PhotometrySummary({required this.nodeId, required this.targetDesignation, required this.filter, required this.framesCaptured, required this.cadenceBreaks, this.lastRejectReason}): super._();
  

/// Node ID for mapping progress to the correct tree node.
 final  String nodeId;
 final  String targetDesignation;
 final  String filter;
/// Number of frames captured during the burst (accepted + rejected).
 final  int framesCaptured;
/// Total cadence breaks observed during the burst.
 final  int cadenceBreaks;
/// Last rejection reason seen during the burst; `None` when no frame
/// was rejected.
 final  String? lastRejectReason;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_PhotometrySummaryCopyWith<SequencerEvent_PhotometrySummary> get copyWith => _$SequencerEvent_PhotometrySummaryCopyWithImpl<SequencerEvent_PhotometrySummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_PhotometrySummary&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.targetDesignation, targetDesignation) || other.targetDesignation == targetDesignation)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.framesCaptured, framesCaptured) || other.framesCaptured == framesCaptured)&&(identical(other.cadenceBreaks, cadenceBreaks) || other.cadenceBreaks == cadenceBreaks)&&(identical(other.lastRejectReason, lastRejectReason) || other.lastRejectReason == lastRejectReason));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,targetDesignation,filter,framesCaptured,cadenceBreaks,lastRejectReason);

@override
String toString() {
  return 'SequencerEvent.photometrySummary(nodeId: $nodeId, targetDesignation: $targetDesignation, filter: $filter, framesCaptured: $framesCaptured, cadenceBreaks: $cadenceBreaks, lastRejectReason: $lastRejectReason)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_PhotometrySummaryCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_PhotometrySummaryCopyWith(SequencerEvent_PhotometrySummary value, $Res Function(SequencerEvent_PhotometrySummary) _then) = _$SequencerEvent_PhotometrySummaryCopyWithImpl;
@useResult
$Res call({
 String nodeId, String targetDesignation, String filter, int framesCaptured, int cadenceBreaks, String? lastRejectReason
});




}
/// @nodoc
class _$SequencerEvent_PhotometrySummaryCopyWithImpl<$Res>
    implements $SequencerEvent_PhotometrySummaryCopyWith<$Res> {
  _$SequencerEvent_PhotometrySummaryCopyWithImpl(this._self, this._then);

  final SequencerEvent_PhotometrySummary _self;
  final $Res Function(SequencerEvent_PhotometrySummary) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? targetDesignation = null,Object? filter = null,Object? framesCaptured = null,Object? cadenceBreaks = null,Object? lastRejectReason = freezed,}) {
  return _then(SequencerEvent_PhotometrySummary(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,targetDesignation: null == targetDesignation ? _self.targetDesignation : targetDesignation // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String,framesCaptured: null == framesCaptured ? _self.framesCaptured : framesCaptured // ignore: cast_nullable_to_non_nullable
as int,cadenceBreaks: null == cadenceBreaks ? _self.cadenceBreaks : cadenceBreaks // ignore: cast_nullable_to_non_nullable
as int,lastRejectReason: freezed == lastRejectReason ? _self.lastRejectReason : lastRejectReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_RecoveryStarted extends SequencerEvent {
  const SequencerEvent_RecoveryStarted({required this.startedAtIso, required this.causeKind, this.causeCustomLabel, this.lastAttemptAtIso, required this.attemptCount, required this.maxAttempts, required this.retryIntervalSecs, required this.maxDurationSecs, required this.phase, this.lastError}): super._();
  

 final  String startedAtIso;
 final  String causeKind;
 final  String? causeCustomLabel;
 final  String? lastAttemptAtIso;
 final  int attemptCount;
 final  int maxAttempts;
 final  double retryIntervalSecs;
 final  double maxDurationSecs;
 final  String phase;
 final  String? lastError;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_RecoveryStartedCopyWith<SequencerEvent_RecoveryStarted> get copyWith => _$SequencerEvent_RecoveryStartedCopyWithImpl<SequencerEvent_RecoveryStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_RecoveryStarted&&(identical(other.startedAtIso, startedAtIso) || other.startedAtIso == startedAtIso)&&(identical(other.causeKind, causeKind) || other.causeKind == causeKind)&&(identical(other.causeCustomLabel, causeCustomLabel) || other.causeCustomLabel == causeCustomLabel)&&(identical(other.lastAttemptAtIso, lastAttemptAtIso) || other.lastAttemptAtIso == lastAttemptAtIso)&&(identical(other.attemptCount, attemptCount) || other.attemptCount == attemptCount)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts)&&(identical(other.retryIntervalSecs, retryIntervalSecs) || other.retryIntervalSecs == retryIntervalSecs)&&(identical(other.maxDurationSecs, maxDurationSecs) || other.maxDurationSecs == maxDurationSecs)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}


@override
int get hashCode => Object.hash(runtimeType,startedAtIso,causeKind,causeCustomLabel,lastAttemptAtIso,attemptCount,maxAttempts,retryIntervalSecs,maxDurationSecs,phase,lastError);

@override
String toString() {
  return 'SequencerEvent.recoveryStarted(startedAtIso: $startedAtIso, causeKind: $causeKind, causeCustomLabel: $causeCustomLabel, lastAttemptAtIso: $lastAttemptAtIso, attemptCount: $attemptCount, maxAttempts: $maxAttempts, retryIntervalSecs: $retryIntervalSecs, maxDurationSecs: $maxDurationSecs, phase: $phase, lastError: $lastError)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_RecoveryStartedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_RecoveryStartedCopyWith(SequencerEvent_RecoveryStarted value, $Res Function(SequencerEvent_RecoveryStarted) _then) = _$SequencerEvent_RecoveryStartedCopyWithImpl;
@useResult
$Res call({
 String startedAtIso, String causeKind, String? causeCustomLabel, String? lastAttemptAtIso, int attemptCount, int maxAttempts, double retryIntervalSecs, double maxDurationSecs, String phase, String? lastError
});




}
/// @nodoc
class _$SequencerEvent_RecoveryStartedCopyWithImpl<$Res>
    implements $SequencerEvent_RecoveryStartedCopyWith<$Res> {
  _$SequencerEvent_RecoveryStartedCopyWithImpl(this._self, this._then);

  final SequencerEvent_RecoveryStarted _self;
  final $Res Function(SequencerEvent_RecoveryStarted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAtIso = null,Object? causeKind = null,Object? causeCustomLabel = freezed,Object? lastAttemptAtIso = freezed,Object? attemptCount = null,Object? maxAttempts = null,Object? retryIntervalSecs = null,Object? maxDurationSecs = null,Object? phase = null,Object? lastError = freezed,}) {
  return _then(SequencerEvent_RecoveryStarted(
startedAtIso: null == startedAtIso ? _self.startedAtIso : startedAtIso // ignore: cast_nullable_to_non_nullable
as String,causeKind: null == causeKind ? _self.causeKind : causeKind // ignore: cast_nullable_to_non_nullable
as String,causeCustomLabel: freezed == causeCustomLabel ? _self.causeCustomLabel : causeCustomLabel // ignore: cast_nullable_to_non_nullable
as String?,lastAttemptAtIso: freezed == lastAttemptAtIso ? _self.lastAttemptAtIso : lastAttemptAtIso // ignore: cast_nullable_to_non_nullable
as String?,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,retryIntervalSecs: null == retryIntervalSecs ? _self.retryIntervalSecs : retryIntervalSecs // ignore: cast_nullable_to_non_nullable
as double,maxDurationSecs: null == maxDurationSecs ? _self.maxDurationSecs : maxDurationSecs // ignore: cast_nullable_to_non_nullable
as double,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_RecoveryProgress extends SequencerEvent {
  const SequencerEvent_RecoveryProgress({required this.startedAtIso, required this.causeKind, this.causeCustomLabel, this.lastAttemptAtIso, required this.attemptCount, required this.maxAttempts, required this.retryIntervalSecs, required this.maxDurationSecs, required this.phase, this.lastError}): super._();
  

 final  String startedAtIso;
 final  String causeKind;
 final  String? causeCustomLabel;
 final  String? lastAttemptAtIso;
 final  int attemptCount;
 final  int maxAttempts;
 final  double retryIntervalSecs;
 final  double maxDurationSecs;
 final  String phase;
 final  String? lastError;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_RecoveryProgressCopyWith<SequencerEvent_RecoveryProgress> get copyWith => _$SequencerEvent_RecoveryProgressCopyWithImpl<SequencerEvent_RecoveryProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_RecoveryProgress&&(identical(other.startedAtIso, startedAtIso) || other.startedAtIso == startedAtIso)&&(identical(other.causeKind, causeKind) || other.causeKind == causeKind)&&(identical(other.causeCustomLabel, causeCustomLabel) || other.causeCustomLabel == causeCustomLabel)&&(identical(other.lastAttemptAtIso, lastAttemptAtIso) || other.lastAttemptAtIso == lastAttemptAtIso)&&(identical(other.attemptCount, attemptCount) || other.attemptCount == attemptCount)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts)&&(identical(other.retryIntervalSecs, retryIntervalSecs) || other.retryIntervalSecs == retryIntervalSecs)&&(identical(other.maxDurationSecs, maxDurationSecs) || other.maxDurationSecs == maxDurationSecs)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}


@override
int get hashCode => Object.hash(runtimeType,startedAtIso,causeKind,causeCustomLabel,lastAttemptAtIso,attemptCount,maxAttempts,retryIntervalSecs,maxDurationSecs,phase,lastError);

@override
String toString() {
  return 'SequencerEvent.recoveryProgress(startedAtIso: $startedAtIso, causeKind: $causeKind, causeCustomLabel: $causeCustomLabel, lastAttemptAtIso: $lastAttemptAtIso, attemptCount: $attemptCount, maxAttempts: $maxAttempts, retryIntervalSecs: $retryIntervalSecs, maxDurationSecs: $maxDurationSecs, phase: $phase, lastError: $lastError)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_RecoveryProgressCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_RecoveryProgressCopyWith(SequencerEvent_RecoveryProgress value, $Res Function(SequencerEvent_RecoveryProgress) _then) = _$SequencerEvent_RecoveryProgressCopyWithImpl;
@useResult
$Res call({
 String startedAtIso, String causeKind, String? causeCustomLabel, String? lastAttemptAtIso, int attemptCount, int maxAttempts, double retryIntervalSecs, double maxDurationSecs, String phase, String? lastError
});




}
/// @nodoc
class _$SequencerEvent_RecoveryProgressCopyWithImpl<$Res>
    implements $SequencerEvent_RecoveryProgressCopyWith<$Res> {
  _$SequencerEvent_RecoveryProgressCopyWithImpl(this._self, this._then);

  final SequencerEvent_RecoveryProgress _self;
  final $Res Function(SequencerEvent_RecoveryProgress) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAtIso = null,Object? causeKind = null,Object? causeCustomLabel = freezed,Object? lastAttemptAtIso = freezed,Object? attemptCount = null,Object? maxAttempts = null,Object? retryIntervalSecs = null,Object? maxDurationSecs = null,Object? phase = null,Object? lastError = freezed,}) {
  return _then(SequencerEvent_RecoveryProgress(
startedAtIso: null == startedAtIso ? _self.startedAtIso : startedAtIso // ignore: cast_nullable_to_non_nullable
as String,causeKind: null == causeKind ? _self.causeKind : causeKind // ignore: cast_nullable_to_non_nullable
as String,causeCustomLabel: freezed == causeCustomLabel ? _self.causeCustomLabel : causeCustomLabel // ignore: cast_nullable_to_non_nullable
as String?,lastAttemptAtIso: freezed == lastAttemptAtIso ? _self.lastAttemptAtIso : lastAttemptAtIso // ignore: cast_nullable_to_non_nullable
as String?,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,retryIntervalSecs: null == retryIntervalSecs ? _self.retryIntervalSecs : retryIntervalSecs // ignore: cast_nullable_to_non_nullable
as double,maxDurationSecs: null == maxDurationSecs ? _self.maxDurationSecs : maxDurationSecs // ignore: cast_nullable_to_non_nullable
as double,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_RecoveryCompleted extends SequencerEvent {
  const SequencerEvent_RecoveryCompleted({required this.startedAtIso, required this.causeKind, this.causeCustomLabel, this.lastAttemptAtIso, required this.attemptCount, required this.maxAttempts, required this.retryIntervalSecs, required this.maxDurationSecs, required this.phase, this.lastError}): super._();
  

 final  String startedAtIso;
 final  String causeKind;
 final  String? causeCustomLabel;
 final  String? lastAttemptAtIso;
 final  int attemptCount;
 final  int maxAttempts;
 final  double retryIntervalSecs;
 final  double maxDurationSecs;
 final  String phase;
 final  String? lastError;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_RecoveryCompletedCopyWith<SequencerEvent_RecoveryCompleted> get copyWith => _$SequencerEvent_RecoveryCompletedCopyWithImpl<SequencerEvent_RecoveryCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_RecoveryCompleted&&(identical(other.startedAtIso, startedAtIso) || other.startedAtIso == startedAtIso)&&(identical(other.causeKind, causeKind) || other.causeKind == causeKind)&&(identical(other.causeCustomLabel, causeCustomLabel) || other.causeCustomLabel == causeCustomLabel)&&(identical(other.lastAttemptAtIso, lastAttemptAtIso) || other.lastAttemptAtIso == lastAttemptAtIso)&&(identical(other.attemptCount, attemptCount) || other.attemptCount == attemptCount)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts)&&(identical(other.retryIntervalSecs, retryIntervalSecs) || other.retryIntervalSecs == retryIntervalSecs)&&(identical(other.maxDurationSecs, maxDurationSecs) || other.maxDurationSecs == maxDurationSecs)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}


@override
int get hashCode => Object.hash(runtimeType,startedAtIso,causeKind,causeCustomLabel,lastAttemptAtIso,attemptCount,maxAttempts,retryIntervalSecs,maxDurationSecs,phase,lastError);

@override
String toString() {
  return 'SequencerEvent.recoveryCompleted(startedAtIso: $startedAtIso, causeKind: $causeKind, causeCustomLabel: $causeCustomLabel, lastAttemptAtIso: $lastAttemptAtIso, attemptCount: $attemptCount, maxAttempts: $maxAttempts, retryIntervalSecs: $retryIntervalSecs, maxDurationSecs: $maxDurationSecs, phase: $phase, lastError: $lastError)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_RecoveryCompletedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_RecoveryCompletedCopyWith(SequencerEvent_RecoveryCompleted value, $Res Function(SequencerEvent_RecoveryCompleted) _then) = _$SequencerEvent_RecoveryCompletedCopyWithImpl;
@useResult
$Res call({
 String startedAtIso, String causeKind, String? causeCustomLabel, String? lastAttemptAtIso, int attemptCount, int maxAttempts, double retryIntervalSecs, double maxDurationSecs, String phase, String? lastError
});




}
/// @nodoc
class _$SequencerEvent_RecoveryCompletedCopyWithImpl<$Res>
    implements $SequencerEvent_RecoveryCompletedCopyWith<$Res> {
  _$SequencerEvent_RecoveryCompletedCopyWithImpl(this._self, this._then);

  final SequencerEvent_RecoveryCompleted _self;
  final $Res Function(SequencerEvent_RecoveryCompleted) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAtIso = null,Object? causeKind = null,Object? causeCustomLabel = freezed,Object? lastAttemptAtIso = freezed,Object? attemptCount = null,Object? maxAttempts = null,Object? retryIntervalSecs = null,Object? maxDurationSecs = null,Object? phase = null,Object? lastError = freezed,}) {
  return _then(SequencerEvent_RecoveryCompleted(
startedAtIso: null == startedAtIso ? _self.startedAtIso : startedAtIso // ignore: cast_nullable_to_non_nullable
as String,causeKind: null == causeKind ? _self.causeKind : causeKind // ignore: cast_nullable_to_non_nullable
as String,causeCustomLabel: freezed == causeCustomLabel ? _self.causeCustomLabel : causeCustomLabel // ignore: cast_nullable_to_non_nullable
as String?,lastAttemptAtIso: freezed == lastAttemptAtIso ? _self.lastAttemptAtIso : lastAttemptAtIso // ignore: cast_nullable_to_non_nullable
as String?,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,retryIntervalSecs: null == retryIntervalSecs ? _self.retryIntervalSecs : retryIntervalSecs // ignore: cast_nullable_to_non_nullable
as double,maxDurationSecs: null == maxDurationSecs ? _self.maxDurationSecs : maxDurationSecs // ignore: cast_nullable_to_non_nullable
as double,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class SequencerEvent_RecoveryGaveUp extends SequencerEvent {
  const SequencerEvent_RecoveryGaveUp({required this.startedAtIso, required this.causeKind, this.causeCustomLabel, this.lastAttemptAtIso, required this.attemptCount, required this.maxAttempts, required this.retryIntervalSecs, required this.maxDurationSecs, required this.phase, this.lastError, required this.abortedByUser}): super._();
  

 final  String startedAtIso;
 final  String causeKind;
 final  String? causeCustomLabel;
 final  String? lastAttemptAtIso;
 final  int attemptCount;
 final  int maxAttempts;
 final  double retryIntervalSecs;
 final  double maxDurationSecs;
 final  String phase;
 final  String? lastError;
/// True when the loop exited because the user pressed Abort.
/// Distinct from exhaustion so the UI can render different copy
/// ("Aborted by operator" vs "Exhausted retries").
 final  bool abortedByUser;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_RecoveryGaveUpCopyWith<SequencerEvent_RecoveryGaveUp> get copyWith => _$SequencerEvent_RecoveryGaveUpCopyWithImpl<SequencerEvent_RecoveryGaveUp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_RecoveryGaveUp&&(identical(other.startedAtIso, startedAtIso) || other.startedAtIso == startedAtIso)&&(identical(other.causeKind, causeKind) || other.causeKind == causeKind)&&(identical(other.causeCustomLabel, causeCustomLabel) || other.causeCustomLabel == causeCustomLabel)&&(identical(other.lastAttemptAtIso, lastAttemptAtIso) || other.lastAttemptAtIso == lastAttemptAtIso)&&(identical(other.attemptCount, attemptCount) || other.attemptCount == attemptCount)&&(identical(other.maxAttempts, maxAttempts) || other.maxAttempts == maxAttempts)&&(identical(other.retryIntervalSecs, retryIntervalSecs) || other.retryIntervalSecs == retryIntervalSecs)&&(identical(other.maxDurationSecs, maxDurationSecs) || other.maxDurationSecs == maxDurationSecs)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.lastError, lastError) || other.lastError == lastError)&&(identical(other.abortedByUser, abortedByUser) || other.abortedByUser == abortedByUser));
}


@override
int get hashCode => Object.hash(runtimeType,startedAtIso,causeKind,causeCustomLabel,lastAttemptAtIso,attemptCount,maxAttempts,retryIntervalSecs,maxDurationSecs,phase,lastError,abortedByUser);

@override
String toString() {
  return 'SequencerEvent.recoveryGaveUp(startedAtIso: $startedAtIso, causeKind: $causeKind, causeCustomLabel: $causeCustomLabel, lastAttemptAtIso: $lastAttemptAtIso, attemptCount: $attemptCount, maxAttempts: $maxAttempts, retryIntervalSecs: $retryIntervalSecs, maxDurationSecs: $maxDurationSecs, phase: $phase, lastError: $lastError, abortedByUser: $abortedByUser)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_RecoveryGaveUpCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_RecoveryGaveUpCopyWith(SequencerEvent_RecoveryGaveUp value, $Res Function(SequencerEvent_RecoveryGaveUp) _then) = _$SequencerEvent_RecoveryGaveUpCopyWithImpl;
@useResult
$Res call({
 String startedAtIso, String causeKind, String? causeCustomLabel, String? lastAttemptAtIso, int attemptCount, int maxAttempts, double retryIntervalSecs, double maxDurationSecs, String phase, String? lastError, bool abortedByUser
});




}
/// @nodoc
class _$SequencerEvent_RecoveryGaveUpCopyWithImpl<$Res>
    implements $SequencerEvent_RecoveryGaveUpCopyWith<$Res> {
  _$SequencerEvent_RecoveryGaveUpCopyWithImpl(this._self, this._then);

  final SequencerEvent_RecoveryGaveUp _self;
  final $Res Function(SequencerEvent_RecoveryGaveUp) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAtIso = null,Object? causeKind = null,Object? causeCustomLabel = freezed,Object? lastAttemptAtIso = freezed,Object? attemptCount = null,Object? maxAttempts = null,Object? retryIntervalSecs = null,Object? maxDurationSecs = null,Object? phase = null,Object? lastError = freezed,Object? abortedByUser = null,}) {
  return _then(SequencerEvent_RecoveryGaveUp(
startedAtIso: null == startedAtIso ? _self.startedAtIso : startedAtIso // ignore: cast_nullable_to_non_nullable
as String,causeKind: null == causeKind ? _self.causeKind : causeKind // ignore: cast_nullable_to_non_nullable
as String,causeCustomLabel: freezed == causeCustomLabel ? _self.causeCustomLabel : causeCustomLabel // ignore: cast_nullable_to_non_nullable
as String?,lastAttemptAtIso: freezed == lastAttemptAtIso ? _self.lastAttemptAtIso : lastAttemptAtIso // ignore: cast_nullable_to_non_nullable
as String?,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,maxAttempts: null == maxAttempts ? _self.maxAttempts : maxAttempts // ignore: cast_nullable_to_non_nullable
as int,retryIntervalSecs: null == retryIntervalSecs ? _self.retryIntervalSecs : retryIntervalSecs // ignore: cast_nullable_to_non_nullable
as double,maxDurationSecs: null == maxDurationSecs ? _self.maxDurationSecs : maxDurationSecs // ignore: cast_nullable_to_non_nullable
as double,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,abortedByUser: null == abortedByUser ? _self.abortedByUser : abortedByUser // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class SequencerEvent_PluginNodeRequested extends SequencerEvent {
  const SequencerEvent_PluginNodeRequested({required this.nodeId, required this.pluginId, required this.nodeTypeId, required this.configJson, this.displayName, required this.timeoutSecs}): super._();
  

/// Executor-side node identifier. The reply MUST echo this.
 final  String nodeId;
/// Stable plugin identifier (e.g. `com.example.pushover`).
 final  String pluginId;
/// Stable per-plugin node type identifier (e.g. `pushover.notify`).
 final  String nodeTypeId;
/// Opaque JSON payload the plugin author authored on the Dart
/// side. Rust forwards verbatim.
 final  String configJson;
/// Optional human-readable label. `None` => UI uses
/// `node_type_id`.
 final  String? displayName;
/// Effective timeout (seconds) the Rust side will wait. Dart
/// MUST honour this; a longer run on the Dart side will be
/// timed out by Rust first and surfaced as a failure.
 final  int timeoutSecs;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_PluginNodeRequestedCopyWith<SequencerEvent_PluginNodeRequested> get copyWith => _$SequencerEvent_PluginNodeRequestedCopyWithImpl<SequencerEvent_PluginNodeRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_PluginNodeRequested&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.pluginId, pluginId) || other.pluginId == pluginId)&&(identical(other.nodeTypeId, nodeTypeId) || other.nodeTypeId == nodeTypeId)&&(identical(other.configJson, configJson) || other.configJson == configJson)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.timeoutSecs, timeoutSecs) || other.timeoutSecs == timeoutSecs));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,pluginId,nodeTypeId,configJson,displayName,timeoutSecs);

@override
String toString() {
  return 'SequencerEvent.pluginNodeRequested(nodeId: $nodeId, pluginId: $pluginId, nodeTypeId: $nodeTypeId, configJson: $configJson, displayName: $displayName, timeoutSecs: $timeoutSecs)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_PluginNodeRequestedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_PluginNodeRequestedCopyWith(SequencerEvent_PluginNodeRequested value, $Res Function(SequencerEvent_PluginNodeRequested) _then) = _$SequencerEvent_PluginNodeRequestedCopyWithImpl;
@useResult
$Res call({
 String nodeId, String pluginId, String nodeTypeId, String configJson, String? displayName, int timeoutSecs
});




}
/// @nodoc
class _$SequencerEvent_PluginNodeRequestedCopyWithImpl<$Res>
    implements $SequencerEvent_PluginNodeRequestedCopyWith<$Res> {
  _$SequencerEvent_PluginNodeRequestedCopyWithImpl(this._self, this._then);

  final SequencerEvent_PluginNodeRequested _self;
  final $Res Function(SequencerEvent_PluginNodeRequested) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? pluginId = null,Object? nodeTypeId = null,Object? configJson = null,Object? displayName = freezed,Object? timeoutSecs = null,}) {
  return _then(SequencerEvent_PluginNodeRequested(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,pluginId: null == pluginId ? _self.pluginId : pluginId // ignore: cast_nullable_to_non_nullable
as String,nodeTypeId: null == nodeTypeId ? _self.nodeTypeId : nodeTypeId // ignore: cast_nullable_to_non_nullable
as String,configJson: null == configJson ? _self.configJson : configJson // ignore: cast_nullable_to_non_nullable
as String,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,timeoutSecs: null == timeoutSecs ? _self.timeoutSecs : timeoutSecs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class SequencerEvent_PluginNodeProgress extends SequencerEvent {
  const SequencerEvent_PluginNodeProgress({required this.nodeId, required this.pluginId, required this.nodeTypeId, required this.detailJson}): super._();
  

 final  String nodeId;
 final  String pluginId;
 final  String nodeTypeId;
/// Stringified plugin-authored payload. Empty string when the
/// plugin emitted no payload.
 final  String detailJson;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_PluginNodeProgressCopyWith<SequencerEvent_PluginNodeProgress> get copyWith => _$SequencerEvent_PluginNodeProgressCopyWithImpl<SequencerEvent_PluginNodeProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_PluginNodeProgress&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.pluginId, pluginId) || other.pluginId == pluginId)&&(identical(other.nodeTypeId, nodeTypeId) || other.nodeTypeId == nodeTypeId)&&(identical(other.detailJson, detailJson) || other.detailJson == detailJson));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,pluginId,nodeTypeId,detailJson);

@override
String toString() {
  return 'SequencerEvent.pluginNodeProgress(nodeId: $nodeId, pluginId: $pluginId, nodeTypeId: $nodeTypeId, detailJson: $detailJson)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_PluginNodeProgressCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_PluginNodeProgressCopyWith(SequencerEvent_PluginNodeProgress value, $Res Function(SequencerEvent_PluginNodeProgress) _then) = _$SequencerEvent_PluginNodeProgressCopyWithImpl;
@useResult
$Res call({
 String nodeId, String pluginId, String nodeTypeId, String detailJson
});




}
/// @nodoc
class _$SequencerEvent_PluginNodeProgressCopyWithImpl<$Res>
    implements $SequencerEvent_PluginNodeProgressCopyWith<$Res> {
  _$SequencerEvent_PluginNodeProgressCopyWithImpl(this._self, this._then);

  final SequencerEvent_PluginNodeProgress _self;
  final $Res Function(SequencerEvent_PluginNodeProgress) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? pluginId = null,Object? nodeTypeId = null,Object? detailJson = null,}) {
  return _then(SequencerEvent_PluginNodeProgress(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,pluginId: null == pluginId ? _self.pluginId : pluginId // ignore: cast_nullable_to_non_nullable
as String,nodeTypeId: null == nodeTypeId ? _self.nodeTypeId : nodeTypeId // ignore: cast_nullable_to_non_nullable
as String,detailJson: null == detailJson ? _self.detailJson : detailJson // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SequencerEvent_DecisionLogged extends SequencerEvent {
  const SequencerEvent_DecisionLogged({required this.timestampIso, required this.category, required this.summary, required this.detailsJson, this.nodeId, this.sequenceRunId}): super._();
  

/// ISO-8601 UTC timestamp when the decision was made.
 final  String timestampIso;
/// Stable wire key for the underlying DecisionCategory variant.
 final  String category;
/// One-line human-readable summary.
 final  String summary;
/// JSON-stringified opaque details payload.
 final  String detailsJson;
/// Optional associated node id (scheduler / target / exposure
/// node).
 final  String? nodeId;
/// `sequence_runs.id` this decision belongs to, if the executor
/// has been stamped with one.
 final  PlatformInt64? sequenceRunId;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SequencerEvent_DecisionLoggedCopyWith<SequencerEvent_DecisionLogged> get copyWith => _$SequencerEvent_DecisionLoggedCopyWithImpl<SequencerEvent_DecisionLogged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SequencerEvent_DecisionLogged&&(identical(other.timestampIso, timestampIso) || other.timestampIso == timestampIso)&&(identical(other.category, category) || other.category == category)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.detailsJson, detailsJson) || other.detailsJson == detailsJson)&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.sequenceRunId, sequenceRunId) || other.sequenceRunId == sequenceRunId));
}


@override
int get hashCode => Object.hash(runtimeType,timestampIso,category,summary,detailsJson,nodeId,sequenceRunId);

@override
String toString() {
  return 'SequencerEvent.decisionLogged(timestampIso: $timestampIso, category: $category, summary: $summary, detailsJson: $detailsJson, nodeId: $nodeId, sequenceRunId: $sequenceRunId)';
}


}

/// @nodoc
abstract mixin class $SequencerEvent_DecisionLoggedCopyWith<$Res> implements $SequencerEventCopyWith<$Res> {
  factory $SequencerEvent_DecisionLoggedCopyWith(SequencerEvent_DecisionLogged value, $Res Function(SequencerEvent_DecisionLogged) _then) = _$SequencerEvent_DecisionLoggedCopyWithImpl;
@useResult
$Res call({
 String timestampIso, String category, String summary, String detailsJson, String? nodeId, PlatformInt64? sequenceRunId
});




}
/// @nodoc
class _$SequencerEvent_DecisionLoggedCopyWithImpl<$Res>
    implements $SequencerEvent_DecisionLoggedCopyWith<$Res> {
  _$SequencerEvent_DecisionLoggedCopyWithImpl(this._self, this._then);

  final SequencerEvent_DecisionLogged _self;
  final $Res Function(SequencerEvent_DecisionLogged) _then;

/// Create a copy of SequencerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? timestampIso = null,Object? category = null,Object? summary = null,Object? detailsJson = null,Object? nodeId = freezed,Object? sequenceRunId = freezed,}) {
  return _then(SequencerEvent_DecisionLogged(
timestampIso: null == timestampIso ? _self.timestampIso : timestampIso // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,detailsJson: null == detailsJson ? _self.detailsJson : detailsJson // ignore: cast_nullable_to_non_nullable
as String,nodeId: freezed == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String?,sequenceRunId: freezed == sequenceRunId ? _self.sequenceRunId : sequenceRunId // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc
mixin _$SystemEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SystemEvent()';
}


}

/// @nodoc
class $SystemEventCopyWith<$Res>  {
$SystemEventCopyWith(SystemEvent _, $Res Function(SystemEvent) __);
}


/// Adds pattern-matching-related methods to [SystemEvent].
extension SystemEventPatterns on SystemEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SystemEvent_Initialized value)?  initialized,TResult Function( SystemEvent_ShuttingDown value)?  shuttingDown,TResult Function( SystemEvent_Error value)?  error,TResult Function( SystemEvent_DiskSpaceLow value)?  diskSpaceLow,TResult Function( SystemEvent_Notification value)?  notification,TResult Function( SystemEvent_EventsDropped value)?  eventsDropped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SystemEvent_Initialized() when initialized != null:
return initialized(_that);case SystemEvent_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case SystemEvent_Error() when error != null:
return error(_that);case SystemEvent_DiskSpaceLow() when diskSpaceLow != null:
return diskSpaceLow(_that);case SystemEvent_Notification() when notification != null:
return notification(_that);case SystemEvent_EventsDropped() when eventsDropped != null:
return eventsDropped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SystemEvent_Initialized value)  initialized,required TResult Function( SystemEvent_ShuttingDown value)  shuttingDown,required TResult Function( SystemEvent_Error value)  error,required TResult Function( SystemEvent_DiskSpaceLow value)  diskSpaceLow,required TResult Function( SystemEvent_Notification value)  notification,required TResult Function( SystemEvent_EventsDropped value)  eventsDropped,}){
final _that = this;
switch (_that) {
case SystemEvent_Initialized():
return initialized(_that);case SystemEvent_ShuttingDown():
return shuttingDown(_that);case SystemEvent_Error():
return error(_that);case SystemEvent_DiskSpaceLow():
return diskSpaceLow(_that);case SystemEvent_Notification():
return notification(_that);case SystemEvent_EventsDropped():
return eventsDropped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SystemEvent_Initialized value)?  initialized,TResult? Function( SystemEvent_ShuttingDown value)?  shuttingDown,TResult? Function( SystemEvent_Error value)?  error,TResult? Function( SystemEvent_DiskSpaceLow value)?  diskSpaceLow,TResult? Function( SystemEvent_Notification value)?  notification,TResult? Function( SystemEvent_EventsDropped value)?  eventsDropped,}){
final _that = this;
switch (_that) {
case SystemEvent_Initialized() when initialized != null:
return initialized(_that);case SystemEvent_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case SystemEvent_Error() when error != null:
return error(_that);case SystemEvent_DiskSpaceLow() when diskSpaceLow != null:
return diskSpaceLow(_that);case SystemEvent_Notification() when notification != null:
return notification(_that);case SystemEvent_EventsDropped() when eventsDropped != null:
return eventsDropped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initialized,TResult Function()?  shuttingDown,TResult Function( String message)?  error,TResult Function( double availableGb)?  diskSpaceLow,TResult Function( String title,  String message,  String level,  List<String>? explicitTransports)?  notification,TResult Function( BigInt droppedCount,  BigInt totalDropped)?  eventsDropped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SystemEvent_Initialized() when initialized != null:
return initialized();case SystemEvent_ShuttingDown() when shuttingDown != null:
return shuttingDown();case SystemEvent_Error() when error != null:
return error(_that.message);case SystemEvent_DiskSpaceLow() when diskSpaceLow != null:
return diskSpaceLow(_that.availableGb);case SystemEvent_Notification() when notification != null:
return notification(_that.title,_that.message,_that.level,_that.explicitTransports);case SystemEvent_EventsDropped() when eventsDropped != null:
return eventsDropped(_that.droppedCount,_that.totalDropped);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initialized,required TResult Function()  shuttingDown,required TResult Function( String message)  error,required TResult Function( double availableGb)  diskSpaceLow,required TResult Function( String title,  String message,  String level,  List<String>? explicitTransports)  notification,required TResult Function( BigInt droppedCount,  BigInt totalDropped)  eventsDropped,}) {final _that = this;
switch (_that) {
case SystemEvent_Initialized():
return initialized();case SystemEvent_ShuttingDown():
return shuttingDown();case SystemEvent_Error():
return error(_that.message);case SystemEvent_DiskSpaceLow():
return diskSpaceLow(_that.availableGb);case SystemEvent_Notification():
return notification(_that.title,_that.message,_that.level,_that.explicitTransports);case SystemEvent_EventsDropped():
return eventsDropped(_that.droppedCount,_that.totalDropped);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initialized,TResult? Function()?  shuttingDown,TResult? Function( String message)?  error,TResult? Function( double availableGb)?  diskSpaceLow,TResult? Function( String title,  String message,  String level,  List<String>? explicitTransports)?  notification,TResult? Function( BigInt droppedCount,  BigInt totalDropped)?  eventsDropped,}) {final _that = this;
switch (_that) {
case SystemEvent_Initialized() when initialized != null:
return initialized();case SystemEvent_ShuttingDown() when shuttingDown != null:
return shuttingDown();case SystemEvent_Error() when error != null:
return error(_that.message);case SystemEvent_DiskSpaceLow() when diskSpaceLow != null:
return diskSpaceLow(_that.availableGb);case SystemEvent_Notification() when notification != null:
return notification(_that.title,_that.message,_that.level,_that.explicitTransports);case SystemEvent_EventsDropped() when eventsDropped != null:
return eventsDropped(_that.droppedCount,_that.totalDropped);case _:
  return null;

}
}

}

/// @nodoc


class SystemEvent_Initialized extends SystemEvent {
  const SystemEvent_Initialized(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_Initialized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SystemEvent.initialized()';
}


}




/// @nodoc


class SystemEvent_ShuttingDown extends SystemEvent {
  const SystemEvent_ShuttingDown(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_ShuttingDown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SystemEvent.shuttingDown()';
}


}




/// @nodoc


class SystemEvent_Error extends SystemEvent {
  const SystemEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemEvent_ErrorCopyWith<SystemEvent_Error> get copyWith => _$SystemEvent_ErrorCopyWithImpl<SystemEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SystemEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $SystemEvent_ErrorCopyWith<$Res> implements $SystemEventCopyWith<$Res> {
  factory $SystemEvent_ErrorCopyWith(SystemEvent_Error value, $Res Function(SystemEvent_Error) _then) = _$SystemEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SystemEvent_ErrorCopyWithImpl<$Res>
    implements $SystemEvent_ErrorCopyWith<$Res> {
  _$SystemEvent_ErrorCopyWithImpl(this._self, this._then);

  final SystemEvent_Error _self;
  final $Res Function(SystemEvent_Error) _then;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SystemEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SystemEvent_DiskSpaceLow extends SystemEvent {
  const SystemEvent_DiskSpaceLow({required this.availableGb}): super._();
  

 final  double availableGb;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemEvent_DiskSpaceLowCopyWith<SystemEvent_DiskSpaceLow> get copyWith => _$SystemEvent_DiskSpaceLowCopyWithImpl<SystemEvent_DiskSpaceLow>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_DiskSpaceLow&&(identical(other.availableGb, availableGb) || other.availableGb == availableGb));
}


@override
int get hashCode => Object.hash(runtimeType,availableGb);

@override
String toString() {
  return 'SystemEvent.diskSpaceLow(availableGb: $availableGb)';
}


}

/// @nodoc
abstract mixin class $SystemEvent_DiskSpaceLowCopyWith<$Res> implements $SystemEventCopyWith<$Res> {
  factory $SystemEvent_DiskSpaceLowCopyWith(SystemEvent_DiskSpaceLow value, $Res Function(SystemEvent_DiskSpaceLow) _then) = _$SystemEvent_DiskSpaceLowCopyWithImpl;
@useResult
$Res call({
 double availableGb
});




}
/// @nodoc
class _$SystemEvent_DiskSpaceLowCopyWithImpl<$Res>
    implements $SystemEvent_DiskSpaceLowCopyWith<$Res> {
  _$SystemEvent_DiskSpaceLowCopyWithImpl(this._self, this._then);

  final SystemEvent_DiskSpaceLow _self;
  final $Res Function(SystemEvent_DiskSpaceLow) _then;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? availableGb = null,}) {
  return _then(SystemEvent_DiskSpaceLow(
availableGb: null == availableGb ? _self.availableGb : availableGb // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class SystemEvent_Notification extends SystemEvent {
  const SystemEvent_Notification({required this.title, required this.message, required this.level, final  List<String>? explicitTransports}): _explicitTransports = explicitTransports,super._();
  

 final  String title;
 final  String message;
 final  String level;
/// per-NotificationNode override list of
/// NotificationTransportKind names (Dart enum, serialised as strings).
/// The Dart NotificationRouter consumes this field to bypass the
/// matrix's `custom` rule and dispatch to the user-picked transports
/// directly. `None` or empty = use matrix routing.
 final  List<String>? _explicitTransports;
/// per-NotificationNode override list of
/// NotificationTransportKind names (Dart enum, serialised as strings).
/// The Dart NotificationRouter consumes this field to bypass the
/// matrix's `custom` rule and dispatch to the user-picked transports
/// directly. `None` or empty = use matrix routing.
 List<String>? get explicitTransports {
  final value = _explicitTransports;
  if (value == null) return null;
  if (_explicitTransports is EqualUnmodifiableListView) return _explicitTransports;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemEvent_NotificationCopyWith<SystemEvent_Notification> get copyWith => _$SystemEvent_NotificationCopyWithImpl<SystemEvent_Notification>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_Notification&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other._explicitTransports, _explicitTransports));
}


@override
int get hashCode => Object.hash(runtimeType,title,message,level,const DeepCollectionEquality().hash(_explicitTransports));

@override
String toString() {
  return 'SystemEvent.notification(title: $title, message: $message, level: $level, explicitTransports: $explicitTransports)';
}


}

/// @nodoc
abstract mixin class $SystemEvent_NotificationCopyWith<$Res> implements $SystemEventCopyWith<$Res> {
  factory $SystemEvent_NotificationCopyWith(SystemEvent_Notification value, $Res Function(SystemEvent_Notification) _then) = _$SystemEvent_NotificationCopyWithImpl;
@useResult
$Res call({
 String title, String message, String level, List<String>? explicitTransports
});




}
/// @nodoc
class _$SystemEvent_NotificationCopyWithImpl<$Res>
    implements $SystemEvent_NotificationCopyWith<$Res> {
  _$SystemEvent_NotificationCopyWithImpl(this._self, this._then);

  final SystemEvent_Notification _self;
  final $Res Function(SystemEvent_Notification) _then;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? message = null,Object? level = null,Object? explicitTransports = freezed,}) {
  return _then(SystemEvent_Notification(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,explicitTransports: freezed == explicitTransports ? _self._explicitTransports : explicitTransports // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}


}

/// @nodoc


class SystemEvent_EventsDropped extends SystemEvent {
  const SystemEvent_EventsDropped({required this.droppedCount, required this.totalDropped}): super._();
  

/// Number of events that were dropped/skipped
 final  BigInt droppedCount;
/// Total number of events dropped since app start
 final  BigInt totalDropped;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemEvent_EventsDroppedCopyWith<SystemEvent_EventsDropped> get copyWith => _$SystemEvent_EventsDroppedCopyWithImpl<SystemEvent_EventsDropped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemEvent_EventsDropped&&(identical(other.droppedCount, droppedCount) || other.droppedCount == droppedCount)&&(identical(other.totalDropped, totalDropped) || other.totalDropped == totalDropped));
}


@override
int get hashCode => Object.hash(runtimeType,droppedCount,totalDropped);

@override
String toString() {
  return 'SystemEvent.eventsDropped(droppedCount: $droppedCount, totalDropped: $totalDropped)';
}


}

/// @nodoc
abstract mixin class $SystemEvent_EventsDroppedCopyWith<$Res> implements $SystemEventCopyWith<$Res> {
  factory $SystemEvent_EventsDroppedCopyWith(SystemEvent_EventsDropped value, $Res Function(SystemEvent_EventsDropped) _then) = _$SystemEvent_EventsDroppedCopyWithImpl;
@useResult
$Res call({
 BigInt droppedCount, BigInt totalDropped
});




}
/// @nodoc
class _$SystemEvent_EventsDroppedCopyWithImpl<$Res>
    implements $SystemEvent_EventsDroppedCopyWith<$Res> {
  _$SystemEvent_EventsDroppedCopyWithImpl(this._self, this._then);

  final SystemEvent_EventsDropped _self;
  final $Res Function(SystemEvent_EventsDropped) _then;

/// Create a copy of SystemEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? droppedCount = null,Object? totalDropped = null,}) {
  return _then(SystemEvent_EventsDropped(
droppedCount: null == droppedCount ? _self.droppedCount : droppedCount // ignore: cast_nullable_to_non_nullable
as BigInt,totalDropped: null == totalDropped ? _self.totalDropped : totalDropped // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
