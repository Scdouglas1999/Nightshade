// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NightshadeError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NightshadeError()';
}


}

/// @nodoc
class $NightshadeErrorCopyWith<$Res>  {
$NightshadeErrorCopyWith(NightshadeError _, $Res Function(NightshadeError) __);
}


/// Adds pattern-matching-related methods to [NightshadeError].
extension NightshadeErrorPatterns on NightshadeError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NightshadeError_DeviceNotFound value)?  deviceNotFound,TResult Function( NightshadeError_ConnectionFailed value)?  connectionFailed,TResult Function( NightshadeError_AlreadyConnected value)?  alreadyConnected,TResult Function( NightshadeError_NotConnected value)?  notConnected,TResult Function( NightshadeError_DeviceDisconnected value)?  deviceDisconnected,TResult Function( NightshadeError_HardwareError value)?  hardwareError,TResult Function( NightshadeError_CommunicationError value)?  communicationError,TResult Function( NightshadeError_Timeout value)?  timeout,TResult Function( NightshadeError_DeviceTimeout value)?  deviceTimeout,TResult Function( NightshadeError_ConnectionTimeout value)?  connectionTimeout,TResult Function( NightshadeError_InvalidParameter value)?  invalidParameter,TResult Function( NightshadeError_InvalidInput value)?  invalidInput,TResult Function( NightshadeError_InvalidDeviceId value)?  invalidDeviceId,TResult Function( NightshadeError_ParameterOutOfRange value)?  parameterOutOfRange,TResult Function( NightshadeError_OperationFailed value)?  operationFailed,TResult Function( NightshadeError_NotSupported value)?  notSupported,TResult Function( NightshadeError_DeviceBusy value)?  deviceBusy,TResult Function( NightshadeError_ImageError value)?  imageError,TResult Function( NightshadeError_CameraError value)?  cameraError,TResult Function( NightshadeError_NoImageAvailable value)?  noImageAvailable,TResult Function( NightshadeError_ExposureCancelled value)?  exposureCancelled,TResult Function( NightshadeError_ExposureFailed value)?  exposureFailed,TResult Function( NightshadeError_DownloadFailed value)?  downloadFailed,TResult Function( NightshadeError_IoError value)?  ioError,TResult Function( NightshadeError_SerializationError value)?  serializationError,TResult Function( NightshadeError_PlateSolveError value)?  plateSolveError,TResult Function( NightshadeError_SequenceError value)?  sequenceError,TResult Function( NightshadeError_AscomError value)?  ascomError,TResult Function( NightshadeError_AlpacaError value)?  alpacaError,TResult Function( NightshadeError_IndiError value)?  indiError,TResult Function( NightshadeError_NativeError value)?  nativeError,TResult Function( NightshadeError_ComError value)?  comError,TResult Function( NightshadeError_Internal value)?  internal,TResult Function( NightshadeError_Cancelled value)?  cancelled,TResult Function( NightshadeError_RuntimeInitFailed value)?  runtimeInitFailed,TResult Function( NightshadeError_ResourceExhausted value)?  resourceExhausted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that);case NightshadeError_ConnectionFailed() when connectionFailed != null:
return connectionFailed(_that);case NightshadeError_AlreadyConnected() when alreadyConnected != null:
return alreadyConnected(_that);case NightshadeError_NotConnected() when notConnected != null:
return notConnected(_that);case NightshadeError_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that);case NightshadeError_HardwareError() when hardwareError != null:
return hardwareError(_that);case NightshadeError_CommunicationError() when communicationError != null:
return communicationError(_that);case NightshadeError_Timeout() when timeout != null:
return timeout(_that);case NightshadeError_DeviceTimeout() when deviceTimeout != null:
return deviceTimeout(_that);case NightshadeError_ConnectionTimeout() when connectionTimeout != null:
return connectionTimeout(_that);case NightshadeError_InvalidParameter() when invalidParameter != null:
return invalidParameter(_that);case NightshadeError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case NightshadeError_InvalidDeviceId() when invalidDeviceId != null:
return invalidDeviceId(_that);case NightshadeError_ParameterOutOfRange() when parameterOutOfRange != null:
return parameterOutOfRange(_that);case NightshadeError_OperationFailed() when operationFailed != null:
return operationFailed(_that);case NightshadeError_NotSupported() when notSupported != null:
return notSupported(_that);case NightshadeError_DeviceBusy() when deviceBusy != null:
return deviceBusy(_that);case NightshadeError_ImageError() when imageError != null:
return imageError(_that);case NightshadeError_CameraError() when cameraError != null:
return cameraError(_that);case NightshadeError_NoImageAvailable() when noImageAvailable != null:
return noImageAvailable(_that);case NightshadeError_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled(_that);case NightshadeError_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that);case NightshadeError_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that);case NightshadeError_IoError() when ioError != null:
return ioError(_that);case NightshadeError_SerializationError() when serializationError != null:
return serializationError(_that);case NightshadeError_PlateSolveError() when plateSolveError != null:
return plateSolveError(_that);case NightshadeError_SequenceError() when sequenceError != null:
return sequenceError(_that);case NightshadeError_AscomError() when ascomError != null:
return ascomError(_that);case NightshadeError_AlpacaError() when alpacaError != null:
return alpacaError(_that);case NightshadeError_IndiError() when indiError != null:
return indiError(_that);case NightshadeError_NativeError() when nativeError != null:
return nativeError(_that);case NightshadeError_ComError() when comError != null:
return comError(_that);case NightshadeError_Internal() when internal != null:
return internal(_that);case NightshadeError_Cancelled() when cancelled != null:
return cancelled(_that);case NightshadeError_RuntimeInitFailed() when runtimeInitFailed != null:
return runtimeInitFailed(_that);case NightshadeError_ResourceExhausted() when resourceExhausted != null:
return resourceExhausted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NightshadeError_DeviceNotFound value)  deviceNotFound,required TResult Function( NightshadeError_ConnectionFailed value)  connectionFailed,required TResult Function( NightshadeError_AlreadyConnected value)  alreadyConnected,required TResult Function( NightshadeError_NotConnected value)  notConnected,required TResult Function( NightshadeError_DeviceDisconnected value)  deviceDisconnected,required TResult Function( NightshadeError_HardwareError value)  hardwareError,required TResult Function( NightshadeError_CommunicationError value)  communicationError,required TResult Function( NightshadeError_Timeout value)  timeout,required TResult Function( NightshadeError_DeviceTimeout value)  deviceTimeout,required TResult Function( NightshadeError_ConnectionTimeout value)  connectionTimeout,required TResult Function( NightshadeError_InvalidParameter value)  invalidParameter,required TResult Function( NightshadeError_InvalidInput value)  invalidInput,required TResult Function( NightshadeError_InvalidDeviceId value)  invalidDeviceId,required TResult Function( NightshadeError_ParameterOutOfRange value)  parameterOutOfRange,required TResult Function( NightshadeError_OperationFailed value)  operationFailed,required TResult Function( NightshadeError_NotSupported value)  notSupported,required TResult Function( NightshadeError_DeviceBusy value)  deviceBusy,required TResult Function( NightshadeError_ImageError value)  imageError,required TResult Function( NightshadeError_CameraError value)  cameraError,required TResult Function( NightshadeError_NoImageAvailable value)  noImageAvailable,required TResult Function( NightshadeError_ExposureCancelled value)  exposureCancelled,required TResult Function( NightshadeError_ExposureFailed value)  exposureFailed,required TResult Function( NightshadeError_DownloadFailed value)  downloadFailed,required TResult Function( NightshadeError_IoError value)  ioError,required TResult Function( NightshadeError_SerializationError value)  serializationError,required TResult Function( NightshadeError_PlateSolveError value)  plateSolveError,required TResult Function( NightshadeError_SequenceError value)  sequenceError,required TResult Function( NightshadeError_AscomError value)  ascomError,required TResult Function( NightshadeError_AlpacaError value)  alpacaError,required TResult Function( NightshadeError_IndiError value)  indiError,required TResult Function( NightshadeError_NativeError value)  nativeError,required TResult Function( NightshadeError_ComError value)  comError,required TResult Function( NightshadeError_Internal value)  internal,required TResult Function( NightshadeError_Cancelled value)  cancelled,required TResult Function( NightshadeError_RuntimeInitFailed value)  runtimeInitFailed,required TResult Function( NightshadeError_ResourceExhausted value)  resourceExhausted,}){
final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound():
return deviceNotFound(_that);case NightshadeError_ConnectionFailed():
return connectionFailed(_that);case NightshadeError_AlreadyConnected():
return alreadyConnected(_that);case NightshadeError_NotConnected():
return notConnected(_that);case NightshadeError_DeviceDisconnected():
return deviceDisconnected(_that);case NightshadeError_HardwareError():
return hardwareError(_that);case NightshadeError_CommunicationError():
return communicationError(_that);case NightshadeError_Timeout():
return timeout(_that);case NightshadeError_DeviceTimeout():
return deviceTimeout(_that);case NightshadeError_ConnectionTimeout():
return connectionTimeout(_that);case NightshadeError_InvalidParameter():
return invalidParameter(_that);case NightshadeError_InvalidInput():
return invalidInput(_that);case NightshadeError_InvalidDeviceId():
return invalidDeviceId(_that);case NightshadeError_ParameterOutOfRange():
return parameterOutOfRange(_that);case NightshadeError_OperationFailed():
return operationFailed(_that);case NightshadeError_NotSupported():
return notSupported(_that);case NightshadeError_DeviceBusy():
return deviceBusy(_that);case NightshadeError_ImageError():
return imageError(_that);case NightshadeError_CameraError():
return cameraError(_that);case NightshadeError_NoImageAvailable():
return noImageAvailable(_that);case NightshadeError_ExposureCancelled():
return exposureCancelled(_that);case NightshadeError_ExposureFailed():
return exposureFailed(_that);case NightshadeError_DownloadFailed():
return downloadFailed(_that);case NightshadeError_IoError():
return ioError(_that);case NightshadeError_SerializationError():
return serializationError(_that);case NightshadeError_PlateSolveError():
return plateSolveError(_that);case NightshadeError_SequenceError():
return sequenceError(_that);case NightshadeError_AscomError():
return ascomError(_that);case NightshadeError_AlpacaError():
return alpacaError(_that);case NightshadeError_IndiError():
return indiError(_that);case NightshadeError_NativeError():
return nativeError(_that);case NightshadeError_ComError():
return comError(_that);case NightshadeError_Internal():
return internal(_that);case NightshadeError_Cancelled():
return cancelled(_that);case NightshadeError_RuntimeInitFailed():
return runtimeInitFailed(_that);case NightshadeError_ResourceExhausted():
return resourceExhausted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NightshadeError_DeviceNotFound value)?  deviceNotFound,TResult? Function( NightshadeError_ConnectionFailed value)?  connectionFailed,TResult? Function( NightshadeError_AlreadyConnected value)?  alreadyConnected,TResult? Function( NightshadeError_NotConnected value)?  notConnected,TResult? Function( NightshadeError_DeviceDisconnected value)?  deviceDisconnected,TResult? Function( NightshadeError_HardwareError value)?  hardwareError,TResult? Function( NightshadeError_CommunicationError value)?  communicationError,TResult? Function( NightshadeError_Timeout value)?  timeout,TResult? Function( NightshadeError_DeviceTimeout value)?  deviceTimeout,TResult? Function( NightshadeError_ConnectionTimeout value)?  connectionTimeout,TResult? Function( NightshadeError_InvalidParameter value)?  invalidParameter,TResult? Function( NightshadeError_InvalidInput value)?  invalidInput,TResult? Function( NightshadeError_InvalidDeviceId value)?  invalidDeviceId,TResult? Function( NightshadeError_ParameterOutOfRange value)?  parameterOutOfRange,TResult? Function( NightshadeError_OperationFailed value)?  operationFailed,TResult? Function( NightshadeError_NotSupported value)?  notSupported,TResult? Function( NightshadeError_DeviceBusy value)?  deviceBusy,TResult? Function( NightshadeError_ImageError value)?  imageError,TResult? Function( NightshadeError_CameraError value)?  cameraError,TResult? Function( NightshadeError_NoImageAvailable value)?  noImageAvailable,TResult? Function( NightshadeError_ExposureCancelled value)?  exposureCancelled,TResult? Function( NightshadeError_ExposureFailed value)?  exposureFailed,TResult? Function( NightshadeError_DownloadFailed value)?  downloadFailed,TResult? Function( NightshadeError_IoError value)?  ioError,TResult? Function( NightshadeError_SerializationError value)?  serializationError,TResult? Function( NightshadeError_PlateSolveError value)?  plateSolveError,TResult? Function( NightshadeError_SequenceError value)?  sequenceError,TResult? Function( NightshadeError_AscomError value)?  ascomError,TResult? Function( NightshadeError_AlpacaError value)?  alpacaError,TResult? Function( NightshadeError_IndiError value)?  indiError,TResult? Function( NightshadeError_NativeError value)?  nativeError,TResult? Function( NightshadeError_ComError value)?  comError,TResult? Function( NightshadeError_Internal value)?  internal,TResult? Function( NightshadeError_Cancelled value)?  cancelled,TResult? Function( NightshadeError_RuntimeInitFailed value)?  runtimeInitFailed,TResult? Function( NightshadeError_ResourceExhausted value)?  resourceExhausted,}){
final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that);case NightshadeError_ConnectionFailed() when connectionFailed != null:
return connectionFailed(_that);case NightshadeError_AlreadyConnected() when alreadyConnected != null:
return alreadyConnected(_that);case NightshadeError_NotConnected() when notConnected != null:
return notConnected(_that);case NightshadeError_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that);case NightshadeError_HardwareError() when hardwareError != null:
return hardwareError(_that);case NightshadeError_CommunicationError() when communicationError != null:
return communicationError(_that);case NightshadeError_Timeout() when timeout != null:
return timeout(_that);case NightshadeError_DeviceTimeout() when deviceTimeout != null:
return deviceTimeout(_that);case NightshadeError_ConnectionTimeout() when connectionTimeout != null:
return connectionTimeout(_that);case NightshadeError_InvalidParameter() when invalidParameter != null:
return invalidParameter(_that);case NightshadeError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case NightshadeError_InvalidDeviceId() when invalidDeviceId != null:
return invalidDeviceId(_that);case NightshadeError_ParameterOutOfRange() when parameterOutOfRange != null:
return parameterOutOfRange(_that);case NightshadeError_OperationFailed() when operationFailed != null:
return operationFailed(_that);case NightshadeError_NotSupported() when notSupported != null:
return notSupported(_that);case NightshadeError_DeviceBusy() when deviceBusy != null:
return deviceBusy(_that);case NightshadeError_ImageError() when imageError != null:
return imageError(_that);case NightshadeError_CameraError() when cameraError != null:
return cameraError(_that);case NightshadeError_NoImageAvailable() when noImageAvailable != null:
return noImageAvailable(_that);case NightshadeError_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled(_that);case NightshadeError_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that);case NightshadeError_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that);case NightshadeError_IoError() when ioError != null:
return ioError(_that);case NightshadeError_SerializationError() when serializationError != null:
return serializationError(_that);case NightshadeError_PlateSolveError() when plateSolveError != null:
return plateSolveError(_that);case NightshadeError_SequenceError() when sequenceError != null:
return sequenceError(_that);case NightshadeError_AscomError() when ascomError != null:
return ascomError(_that);case NightshadeError_AlpacaError() when alpacaError != null:
return alpacaError(_that);case NightshadeError_IndiError() when indiError != null:
return indiError(_that);case NightshadeError_NativeError() when nativeError != null:
return nativeError(_that);case NightshadeError_ComError() when comError != null:
return comError(_that);case NightshadeError_Internal() when internal != null:
return internal(_that);case NightshadeError_Cancelled() when cancelled != null:
return cancelled(_that);case NightshadeError_RuntimeInitFailed() when runtimeInitFailed != null:
return runtimeInitFailed(_that);case NightshadeError_ResourceExhausted() when resourceExhausted != null:
return resourceExhausted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  deviceNotFound,TResult Function( String deviceId,  String reason)?  connectionFailed,TResult Function( String field0)?  alreadyConnected,TResult Function( String field0)?  notConnected,TResult Function( String deviceId,  String reason)?  deviceDisconnected,TResult Function( String deviceId,  String message,  int? errorCode)?  hardwareError,TResult Function( String deviceId,  String message)?  communicationError,TResult Function( String field0)?  timeout,TResult Function( String deviceId,  String operation,  double timeoutSecs)?  deviceTimeout,TResult Function( String deviceId,  double timeoutSecs)?  connectionTimeout,TResult Function( String field0)?  invalidParameter,TResult Function( String field0)?  invalidInput,TResult Function( String deviceId,  String reason)?  invalidDeviceId,TResult Function( String paramName,  String value,  String min,  String max)?  parameterOutOfRange,TResult Function( String field0)?  operationFailed,TResult Function( String deviceId,  String operation)?  notSupported,TResult Function( String deviceId,  String currentOperation)?  deviceBusy,TResult Function( String field0)?  imageError,TResult Function( String field0)?  cameraError,TResult Function()?  noImageAvailable,TResult Function()?  exposureCancelled,TResult Function( String cameraId,  String reason)?  exposureFailed,TResult Function( String cameraId,  String reason)?  downloadFailed,TResult Function( String field0)?  ioError,TResult Function( String field0)?  serializationError,TResult Function( String field0)?  plateSolveError,TResult Function( String field0)?  sequenceError,TResult Function( String progId,  String message,  int errorCode)?  ascomError,TResult Function( String baseUrl,  int deviceNumber,  String message,  int errorCode)?  alpacaError,TResult Function( String server,  int port,  String deviceName,  String message)?  indiError,TResult Function( String vendor,  String message,  int errorCode)?  nativeError,TResult Function( String message,  int hresult)?  comError,TResult Function( String field0)?  internal,TResult Function()?  cancelled,TResult Function( String field0)?  runtimeInitFailed,TResult Function( String resource,  String message)?  resourceExhausted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that.field0);case NightshadeError_ConnectionFailed() when connectionFailed != null:
return connectionFailed(_that.deviceId,_that.reason);case NightshadeError_AlreadyConnected() when alreadyConnected != null:
return alreadyConnected(_that.field0);case NightshadeError_NotConnected() when notConnected != null:
return notConnected(_that.field0);case NightshadeError_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that.deviceId,_that.reason);case NightshadeError_HardwareError() when hardwareError != null:
return hardwareError(_that.deviceId,_that.message,_that.errorCode);case NightshadeError_CommunicationError() when communicationError != null:
return communicationError(_that.deviceId,_that.message);case NightshadeError_Timeout() when timeout != null:
return timeout(_that.field0);case NightshadeError_DeviceTimeout() when deviceTimeout != null:
return deviceTimeout(_that.deviceId,_that.operation,_that.timeoutSecs);case NightshadeError_ConnectionTimeout() when connectionTimeout != null:
return connectionTimeout(_that.deviceId,_that.timeoutSecs);case NightshadeError_InvalidParameter() when invalidParameter != null:
return invalidParameter(_that.field0);case NightshadeError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case NightshadeError_InvalidDeviceId() when invalidDeviceId != null:
return invalidDeviceId(_that.deviceId,_that.reason);case NightshadeError_ParameterOutOfRange() when parameterOutOfRange != null:
return parameterOutOfRange(_that.paramName,_that.value,_that.min,_that.max);case NightshadeError_OperationFailed() when operationFailed != null:
return operationFailed(_that.field0);case NightshadeError_NotSupported() when notSupported != null:
return notSupported(_that.deviceId,_that.operation);case NightshadeError_DeviceBusy() when deviceBusy != null:
return deviceBusy(_that.deviceId,_that.currentOperation);case NightshadeError_ImageError() when imageError != null:
return imageError(_that.field0);case NightshadeError_CameraError() when cameraError != null:
return cameraError(_that.field0);case NightshadeError_NoImageAvailable() when noImageAvailable != null:
return noImageAvailable();case NightshadeError_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled();case NightshadeError_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that.cameraId,_that.reason);case NightshadeError_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that.cameraId,_that.reason);case NightshadeError_IoError() when ioError != null:
return ioError(_that.field0);case NightshadeError_SerializationError() when serializationError != null:
return serializationError(_that.field0);case NightshadeError_PlateSolveError() when plateSolveError != null:
return plateSolveError(_that.field0);case NightshadeError_SequenceError() when sequenceError != null:
return sequenceError(_that.field0);case NightshadeError_AscomError() when ascomError != null:
return ascomError(_that.progId,_that.message,_that.errorCode);case NightshadeError_AlpacaError() when alpacaError != null:
return alpacaError(_that.baseUrl,_that.deviceNumber,_that.message,_that.errorCode);case NightshadeError_IndiError() when indiError != null:
return indiError(_that.server,_that.port,_that.deviceName,_that.message);case NightshadeError_NativeError() when nativeError != null:
return nativeError(_that.vendor,_that.message,_that.errorCode);case NightshadeError_ComError() when comError != null:
return comError(_that.message,_that.hresult);case NightshadeError_Internal() when internal != null:
return internal(_that.field0);case NightshadeError_Cancelled() when cancelled != null:
return cancelled();case NightshadeError_RuntimeInitFailed() when runtimeInitFailed != null:
return runtimeInitFailed(_that.field0);case NightshadeError_ResourceExhausted() when resourceExhausted != null:
return resourceExhausted(_that.resource,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  deviceNotFound,required TResult Function( String deviceId,  String reason)  connectionFailed,required TResult Function( String field0)  alreadyConnected,required TResult Function( String field0)  notConnected,required TResult Function( String deviceId,  String reason)  deviceDisconnected,required TResult Function( String deviceId,  String message,  int? errorCode)  hardwareError,required TResult Function( String deviceId,  String message)  communicationError,required TResult Function( String field0)  timeout,required TResult Function( String deviceId,  String operation,  double timeoutSecs)  deviceTimeout,required TResult Function( String deviceId,  double timeoutSecs)  connectionTimeout,required TResult Function( String field0)  invalidParameter,required TResult Function( String field0)  invalidInput,required TResult Function( String deviceId,  String reason)  invalidDeviceId,required TResult Function( String paramName,  String value,  String min,  String max)  parameterOutOfRange,required TResult Function( String field0)  operationFailed,required TResult Function( String deviceId,  String operation)  notSupported,required TResult Function( String deviceId,  String currentOperation)  deviceBusy,required TResult Function( String field0)  imageError,required TResult Function( String field0)  cameraError,required TResult Function()  noImageAvailable,required TResult Function()  exposureCancelled,required TResult Function( String cameraId,  String reason)  exposureFailed,required TResult Function( String cameraId,  String reason)  downloadFailed,required TResult Function( String field0)  ioError,required TResult Function( String field0)  serializationError,required TResult Function( String field0)  plateSolveError,required TResult Function( String field0)  sequenceError,required TResult Function( String progId,  String message,  int errorCode)  ascomError,required TResult Function( String baseUrl,  int deviceNumber,  String message,  int errorCode)  alpacaError,required TResult Function( String server,  int port,  String deviceName,  String message)  indiError,required TResult Function( String vendor,  String message,  int errorCode)  nativeError,required TResult Function( String message,  int hresult)  comError,required TResult Function( String field0)  internal,required TResult Function()  cancelled,required TResult Function( String field0)  runtimeInitFailed,required TResult Function( String resource,  String message)  resourceExhausted,}) {final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound():
return deviceNotFound(_that.field0);case NightshadeError_ConnectionFailed():
return connectionFailed(_that.deviceId,_that.reason);case NightshadeError_AlreadyConnected():
return alreadyConnected(_that.field0);case NightshadeError_NotConnected():
return notConnected(_that.field0);case NightshadeError_DeviceDisconnected():
return deviceDisconnected(_that.deviceId,_that.reason);case NightshadeError_HardwareError():
return hardwareError(_that.deviceId,_that.message,_that.errorCode);case NightshadeError_CommunicationError():
return communicationError(_that.deviceId,_that.message);case NightshadeError_Timeout():
return timeout(_that.field0);case NightshadeError_DeviceTimeout():
return deviceTimeout(_that.deviceId,_that.operation,_that.timeoutSecs);case NightshadeError_ConnectionTimeout():
return connectionTimeout(_that.deviceId,_that.timeoutSecs);case NightshadeError_InvalidParameter():
return invalidParameter(_that.field0);case NightshadeError_InvalidInput():
return invalidInput(_that.field0);case NightshadeError_InvalidDeviceId():
return invalidDeviceId(_that.deviceId,_that.reason);case NightshadeError_ParameterOutOfRange():
return parameterOutOfRange(_that.paramName,_that.value,_that.min,_that.max);case NightshadeError_OperationFailed():
return operationFailed(_that.field0);case NightshadeError_NotSupported():
return notSupported(_that.deviceId,_that.operation);case NightshadeError_DeviceBusy():
return deviceBusy(_that.deviceId,_that.currentOperation);case NightshadeError_ImageError():
return imageError(_that.field0);case NightshadeError_CameraError():
return cameraError(_that.field0);case NightshadeError_NoImageAvailable():
return noImageAvailable();case NightshadeError_ExposureCancelled():
return exposureCancelled();case NightshadeError_ExposureFailed():
return exposureFailed(_that.cameraId,_that.reason);case NightshadeError_DownloadFailed():
return downloadFailed(_that.cameraId,_that.reason);case NightshadeError_IoError():
return ioError(_that.field0);case NightshadeError_SerializationError():
return serializationError(_that.field0);case NightshadeError_PlateSolveError():
return plateSolveError(_that.field0);case NightshadeError_SequenceError():
return sequenceError(_that.field0);case NightshadeError_AscomError():
return ascomError(_that.progId,_that.message,_that.errorCode);case NightshadeError_AlpacaError():
return alpacaError(_that.baseUrl,_that.deviceNumber,_that.message,_that.errorCode);case NightshadeError_IndiError():
return indiError(_that.server,_that.port,_that.deviceName,_that.message);case NightshadeError_NativeError():
return nativeError(_that.vendor,_that.message,_that.errorCode);case NightshadeError_ComError():
return comError(_that.message,_that.hresult);case NightshadeError_Internal():
return internal(_that.field0);case NightshadeError_Cancelled():
return cancelled();case NightshadeError_RuntimeInitFailed():
return runtimeInitFailed(_that.field0);case NightshadeError_ResourceExhausted():
return resourceExhausted(_that.resource,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  deviceNotFound,TResult? Function( String deviceId,  String reason)?  connectionFailed,TResult? Function( String field0)?  alreadyConnected,TResult? Function( String field0)?  notConnected,TResult? Function( String deviceId,  String reason)?  deviceDisconnected,TResult? Function( String deviceId,  String message,  int? errorCode)?  hardwareError,TResult? Function( String deviceId,  String message)?  communicationError,TResult? Function( String field0)?  timeout,TResult? Function( String deviceId,  String operation,  double timeoutSecs)?  deviceTimeout,TResult? Function( String deviceId,  double timeoutSecs)?  connectionTimeout,TResult? Function( String field0)?  invalidParameter,TResult? Function( String field0)?  invalidInput,TResult? Function( String deviceId,  String reason)?  invalidDeviceId,TResult? Function( String paramName,  String value,  String min,  String max)?  parameterOutOfRange,TResult? Function( String field0)?  operationFailed,TResult? Function( String deviceId,  String operation)?  notSupported,TResult? Function( String deviceId,  String currentOperation)?  deviceBusy,TResult? Function( String field0)?  imageError,TResult? Function( String field0)?  cameraError,TResult? Function()?  noImageAvailable,TResult? Function()?  exposureCancelled,TResult? Function( String cameraId,  String reason)?  exposureFailed,TResult? Function( String cameraId,  String reason)?  downloadFailed,TResult? Function( String field0)?  ioError,TResult? Function( String field0)?  serializationError,TResult? Function( String field0)?  plateSolveError,TResult? Function( String field0)?  sequenceError,TResult? Function( String progId,  String message,  int errorCode)?  ascomError,TResult? Function( String baseUrl,  int deviceNumber,  String message,  int errorCode)?  alpacaError,TResult? Function( String server,  int port,  String deviceName,  String message)?  indiError,TResult? Function( String vendor,  String message,  int errorCode)?  nativeError,TResult? Function( String message,  int hresult)?  comError,TResult? Function( String field0)?  internal,TResult? Function()?  cancelled,TResult? Function( String field0)?  runtimeInitFailed,TResult? Function( String resource,  String message)?  resourceExhausted,}) {final _that = this;
switch (_that) {
case NightshadeError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that.field0);case NightshadeError_ConnectionFailed() when connectionFailed != null:
return connectionFailed(_that.deviceId,_that.reason);case NightshadeError_AlreadyConnected() when alreadyConnected != null:
return alreadyConnected(_that.field0);case NightshadeError_NotConnected() when notConnected != null:
return notConnected(_that.field0);case NightshadeError_DeviceDisconnected() when deviceDisconnected != null:
return deviceDisconnected(_that.deviceId,_that.reason);case NightshadeError_HardwareError() when hardwareError != null:
return hardwareError(_that.deviceId,_that.message,_that.errorCode);case NightshadeError_CommunicationError() when communicationError != null:
return communicationError(_that.deviceId,_that.message);case NightshadeError_Timeout() when timeout != null:
return timeout(_that.field0);case NightshadeError_DeviceTimeout() when deviceTimeout != null:
return deviceTimeout(_that.deviceId,_that.operation,_that.timeoutSecs);case NightshadeError_ConnectionTimeout() when connectionTimeout != null:
return connectionTimeout(_that.deviceId,_that.timeoutSecs);case NightshadeError_InvalidParameter() when invalidParameter != null:
return invalidParameter(_that.field0);case NightshadeError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case NightshadeError_InvalidDeviceId() when invalidDeviceId != null:
return invalidDeviceId(_that.deviceId,_that.reason);case NightshadeError_ParameterOutOfRange() when parameterOutOfRange != null:
return parameterOutOfRange(_that.paramName,_that.value,_that.min,_that.max);case NightshadeError_OperationFailed() when operationFailed != null:
return operationFailed(_that.field0);case NightshadeError_NotSupported() when notSupported != null:
return notSupported(_that.deviceId,_that.operation);case NightshadeError_DeviceBusy() when deviceBusy != null:
return deviceBusy(_that.deviceId,_that.currentOperation);case NightshadeError_ImageError() when imageError != null:
return imageError(_that.field0);case NightshadeError_CameraError() when cameraError != null:
return cameraError(_that.field0);case NightshadeError_NoImageAvailable() when noImageAvailable != null:
return noImageAvailable();case NightshadeError_ExposureCancelled() when exposureCancelled != null:
return exposureCancelled();case NightshadeError_ExposureFailed() when exposureFailed != null:
return exposureFailed(_that.cameraId,_that.reason);case NightshadeError_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that.cameraId,_that.reason);case NightshadeError_IoError() when ioError != null:
return ioError(_that.field0);case NightshadeError_SerializationError() when serializationError != null:
return serializationError(_that.field0);case NightshadeError_PlateSolveError() when plateSolveError != null:
return plateSolveError(_that.field0);case NightshadeError_SequenceError() when sequenceError != null:
return sequenceError(_that.field0);case NightshadeError_AscomError() when ascomError != null:
return ascomError(_that.progId,_that.message,_that.errorCode);case NightshadeError_AlpacaError() when alpacaError != null:
return alpacaError(_that.baseUrl,_that.deviceNumber,_that.message,_that.errorCode);case NightshadeError_IndiError() when indiError != null:
return indiError(_that.server,_that.port,_that.deviceName,_that.message);case NightshadeError_NativeError() when nativeError != null:
return nativeError(_that.vendor,_that.message,_that.errorCode);case NightshadeError_ComError() when comError != null:
return comError(_that.message,_that.hresult);case NightshadeError_Internal() when internal != null:
return internal(_that.field0);case NightshadeError_Cancelled() when cancelled != null:
return cancelled();case NightshadeError_RuntimeInitFailed() when runtimeInitFailed != null:
return runtimeInitFailed(_that.field0);case NightshadeError_ResourceExhausted() when resourceExhausted != null:
return resourceExhausted(_that.resource,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class NightshadeError_DeviceNotFound extends NightshadeError {
  const NightshadeError_DeviceNotFound(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_DeviceNotFoundCopyWith<NightshadeError_DeviceNotFound> get copyWith => _$NightshadeError_DeviceNotFoundCopyWithImpl<NightshadeError_DeviceNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_DeviceNotFound&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.deviceNotFound(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_DeviceNotFoundCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_DeviceNotFoundCopyWith(NightshadeError_DeviceNotFound value, $Res Function(NightshadeError_DeviceNotFound) _then) = _$NightshadeError_DeviceNotFoundCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_DeviceNotFoundCopyWithImpl<$Res>
    implements $NightshadeError_DeviceNotFoundCopyWith<$Res> {
  _$NightshadeError_DeviceNotFoundCopyWithImpl(this._self, this._then);

  final NightshadeError_DeviceNotFound _self;
  final $Res Function(NightshadeError_DeviceNotFound) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_DeviceNotFound(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_ConnectionFailed extends NightshadeError {
  const NightshadeError_ConnectionFailed({required this.deviceId, required this.reason}): super._();
  

 final  String deviceId;
 final  String reason;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ConnectionFailedCopyWith<NightshadeError_ConnectionFailed> get copyWith => _$NightshadeError_ConnectionFailedCopyWithImpl<NightshadeError_ConnectionFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ConnectionFailed&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,reason);

@override
String toString() {
  return 'NightshadeError.connectionFailed(deviceId: $deviceId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ConnectionFailedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ConnectionFailedCopyWith(NightshadeError_ConnectionFailed value, $Res Function(NightshadeError_ConnectionFailed) _then) = _$NightshadeError_ConnectionFailedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String reason
});




}
/// @nodoc
class _$NightshadeError_ConnectionFailedCopyWithImpl<$Res>
    implements $NightshadeError_ConnectionFailedCopyWith<$Res> {
  _$NightshadeError_ConnectionFailedCopyWithImpl(this._self, this._then);

  final NightshadeError_ConnectionFailed _self;
  final $Res Function(NightshadeError_ConnectionFailed) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? reason = null,}) {
  return _then(NightshadeError_ConnectionFailed(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_AlreadyConnected extends NightshadeError {
  const NightshadeError_AlreadyConnected(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_AlreadyConnectedCopyWith<NightshadeError_AlreadyConnected> get copyWith => _$NightshadeError_AlreadyConnectedCopyWithImpl<NightshadeError_AlreadyConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_AlreadyConnected&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.alreadyConnected(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_AlreadyConnectedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_AlreadyConnectedCopyWith(NightshadeError_AlreadyConnected value, $Res Function(NightshadeError_AlreadyConnected) _then) = _$NightshadeError_AlreadyConnectedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_AlreadyConnectedCopyWithImpl<$Res>
    implements $NightshadeError_AlreadyConnectedCopyWith<$Res> {
  _$NightshadeError_AlreadyConnectedCopyWithImpl(this._self, this._then);

  final NightshadeError_AlreadyConnected _self;
  final $Res Function(NightshadeError_AlreadyConnected) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_AlreadyConnected(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_NotConnected extends NightshadeError {
  const NightshadeError_NotConnected(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_NotConnectedCopyWith<NightshadeError_NotConnected> get copyWith => _$NightshadeError_NotConnectedCopyWithImpl<NightshadeError_NotConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_NotConnected&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.notConnected(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_NotConnectedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_NotConnectedCopyWith(NightshadeError_NotConnected value, $Res Function(NightshadeError_NotConnected) _then) = _$NightshadeError_NotConnectedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_NotConnectedCopyWithImpl<$Res>
    implements $NightshadeError_NotConnectedCopyWith<$Res> {
  _$NightshadeError_NotConnectedCopyWithImpl(this._self, this._then);

  final NightshadeError_NotConnected _self;
  final $Res Function(NightshadeError_NotConnected) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_NotConnected(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_DeviceDisconnected extends NightshadeError {
  const NightshadeError_DeviceDisconnected({required this.deviceId, required this.reason}): super._();
  

 final  String deviceId;
 final  String reason;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_DeviceDisconnectedCopyWith<NightshadeError_DeviceDisconnected> get copyWith => _$NightshadeError_DeviceDisconnectedCopyWithImpl<NightshadeError_DeviceDisconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_DeviceDisconnected&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,reason);

@override
String toString() {
  return 'NightshadeError.deviceDisconnected(deviceId: $deviceId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_DeviceDisconnectedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_DeviceDisconnectedCopyWith(NightshadeError_DeviceDisconnected value, $Res Function(NightshadeError_DeviceDisconnected) _then) = _$NightshadeError_DeviceDisconnectedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String reason
});




}
/// @nodoc
class _$NightshadeError_DeviceDisconnectedCopyWithImpl<$Res>
    implements $NightshadeError_DeviceDisconnectedCopyWith<$Res> {
  _$NightshadeError_DeviceDisconnectedCopyWithImpl(this._self, this._then);

  final NightshadeError_DeviceDisconnected _self;
  final $Res Function(NightshadeError_DeviceDisconnected) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? reason = null,}) {
  return _then(NightshadeError_DeviceDisconnected(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_HardwareError extends NightshadeError {
  const NightshadeError_HardwareError({required this.deviceId, required this.message, this.errorCode}): super._();
  

 final  String deviceId;
 final  String message;
/// Optional vendor-specific error code
 final  int? errorCode;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_HardwareErrorCopyWith<NightshadeError_HardwareError> get copyWith => _$NightshadeError_HardwareErrorCopyWithImpl<NightshadeError_HardwareError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_HardwareError&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.message, message) || other.message == message)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,message,errorCode);

@override
String toString() {
  return 'NightshadeError.hardwareError(deviceId: $deviceId, message: $message, errorCode: $errorCode)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_HardwareErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_HardwareErrorCopyWith(NightshadeError_HardwareError value, $Res Function(NightshadeError_HardwareError) _then) = _$NightshadeError_HardwareErrorCopyWithImpl;
@useResult
$Res call({
 String deviceId, String message, int? errorCode
});




}
/// @nodoc
class _$NightshadeError_HardwareErrorCopyWithImpl<$Res>
    implements $NightshadeError_HardwareErrorCopyWith<$Res> {
  _$NightshadeError_HardwareErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_HardwareError _self;
  final $Res Function(NightshadeError_HardwareError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? message = null,Object? errorCode = freezed,}) {
  return _then(NightshadeError_HardwareError(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class NightshadeError_CommunicationError extends NightshadeError {
  const NightshadeError_CommunicationError({required this.deviceId, required this.message}): super._();
  

 final  String deviceId;
 final  String message;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_CommunicationErrorCopyWith<NightshadeError_CommunicationError> get copyWith => _$NightshadeError_CommunicationErrorCopyWithImpl<NightshadeError_CommunicationError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_CommunicationError&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,message);

@override
String toString() {
  return 'NightshadeError.communicationError(deviceId: $deviceId, message: $message)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_CommunicationErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_CommunicationErrorCopyWith(NightshadeError_CommunicationError value, $Res Function(NightshadeError_CommunicationError) _then) = _$NightshadeError_CommunicationErrorCopyWithImpl;
@useResult
$Res call({
 String deviceId, String message
});




}
/// @nodoc
class _$NightshadeError_CommunicationErrorCopyWithImpl<$Res>
    implements $NightshadeError_CommunicationErrorCopyWith<$Res> {
  _$NightshadeError_CommunicationErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_CommunicationError _self;
  final $Res Function(NightshadeError_CommunicationError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? message = null,}) {
  return _then(NightshadeError_CommunicationError(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_Timeout extends NightshadeError {
  const NightshadeError_Timeout(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_TimeoutCopyWith<NightshadeError_Timeout> get copyWith => _$NightshadeError_TimeoutCopyWithImpl<NightshadeError_Timeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_Timeout&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.timeout(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_TimeoutCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_TimeoutCopyWith(NightshadeError_Timeout value, $Res Function(NightshadeError_Timeout) _then) = _$NightshadeError_TimeoutCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_TimeoutCopyWithImpl<$Res>
    implements $NightshadeError_TimeoutCopyWith<$Res> {
  _$NightshadeError_TimeoutCopyWithImpl(this._self, this._then);

  final NightshadeError_Timeout _self;
  final $Res Function(NightshadeError_Timeout) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_Timeout(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_DeviceTimeout extends NightshadeError {
  const NightshadeError_DeviceTimeout({required this.deviceId, required this.operation, required this.timeoutSecs}): super._();
  

 final  String deviceId;
 final  String operation;
 final  double timeoutSecs;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_DeviceTimeoutCopyWith<NightshadeError_DeviceTimeout> get copyWith => _$NightshadeError_DeviceTimeoutCopyWithImpl<NightshadeError_DeviceTimeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_DeviceTimeout&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.timeoutSecs, timeoutSecs) || other.timeoutSecs == timeoutSecs));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,operation,timeoutSecs);

@override
String toString() {
  return 'NightshadeError.deviceTimeout(deviceId: $deviceId, operation: $operation, timeoutSecs: $timeoutSecs)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_DeviceTimeoutCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_DeviceTimeoutCopyWith(NightshadeError_DeviceTimeout value, $Res Function(NightshadeError_DeviceTimeout) _then) = _$NightshadeError_DeviceTimeoutCopyWithImpl;
@useResult
$Res call({
 String deviceId, String operation, double timeoutSecs
});




}
/// @nodoc
class _$NightshadeError_DeviceTimeoutCopyWithImpl<$Res>
    implements $NightshadeError_DeviceTimeoutCopyWith<$Res> {
  _$NightshadeError_DeviceTimeoutCopyWithImpl(this._self, this._then);

  final NightshadeError_DeviceTimeout _self;
  final $Res Function(NightshadeError_DeviceTimeout) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? operation = null,Object? timeoutSecs = null,}) {
  return _then(NightshadeError_DeviceTimeout(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as String,timeoutSecs: null == timeoutSecs ? _self.timeoutSecs : timeoutSecs // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class NightshadeError_ConnectionTimeout extends NightshadeError {
  const NightshadeError_ConnectionTimeout({required this.deviceId, required this.timeoutSecs}): super._();
  

 final  String deviceId;
 final  double timeoutSecs;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ConnectionTimeoutCopyWith<NightshadeError_ConnectionTimeout> get copyWith => _$NightshadeError_ConnectionTimeoutCopyWithImpl<NightshadeError_ConnectionTimeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ConnectionTimeout&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.timeoutSecs, timeoutSecs) || other.timeoutSecs == timeoutSecs));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,timeoutSecs);

@override
String toString() {
  return 'NightshadeError.connectionTimeout(deviceId: $deviceId, timeoutSecs: $timeoutSecs)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ConnectionTimeoutCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ConnectionTimeoutCopyWith(NightshadeError_ConnectionTimeout value, $Res Function(NightshadeError_ConnectionTimeout) _then) = _$NightshadeError_ConnectionTimeoutCopyWithImpl;
@useResult
$Res call({
 String deviceId, double timeoutSecs
});




}
/// @nodoc
class _$NightshadeError_ConnectionTimeoutCopyWithImpl<$Res>
    implements $NightshadeError_ConnectionTimeoutCopyWith<$Res> {
  _$NightshadeError_ConnectionTimeoutCopyWithImpl(this._self, this._then);

  final NightshadeError_ConnectionTimeout _self;
  final $Res Function(NightshadeError_ConnectionTimeout) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? timeoutSecs = null,}) {
  return _then(NightshadeError_ConnectionTimeout(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,timeoutSecs: null == timeoutSecs ? _self.timeoutSecs : timeoutSecs // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class NightshadeError_InvalidParameter extends NightshadeError {
  const NightshadeError_InvalidParameter(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_InvalidParameterCopyWith<NightshadeError_InvalidParameter> get copyWith => _$NightshadeError_InvalidParameterCopyWithImpl<NightshadeError_InvalidParameter>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_InvalidParameter&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.invalidParameter(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_InvalidParameterCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_InvalidParameterCopyWith(NightshadeError_InvalidParameter value, $Res Function(NightshadeError_InvalidParameter) _then) = _$NightshadeError_InvalidParameterCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_InvalidParameterCopyWithImpl<$Res>
    implements $NightshadeError_InvalidParameterCopyWith<$Res> {
  _$NightshadeError_InvalidParameterCopyWithImpl(this._self, this._then);

  final NightshadeError_InvalidParameter _self;
  final $Res Function(NightshadeError_InvalidParameter) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_InvalidParameter(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_InvalidInput extends NightshadeError {
  const NightshadeError_InvalidInput(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_InvalidInputCopyWith<NightshadeError_InvalidInput> get copyWith => _$NightshadeError_InvalidInputCopyWithImpl<NightshadeError_InvalidInput>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_InvalidInput&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.invalidInput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_InvalidInputCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_InvalidInputCopyWith(NightshadeError_InvalidInput value, $Res Function(NightshadeError_InvalidInput) _then) = _$NightshadeError_InvalidInputCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_InvalidInputCopyWithImpl<$Res>
    implements $NightshadeError_InvalidInputCopyWith<$Res> {
  _$NightshadeError_InvalidInputCopyWithImpl(this._self, this._then);

  final NightshadeError_InvalidInput _self;
  final $Res Function(NightshadeError_InvalidInput) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_InvalidInput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_InvalidDeviceId extends NightshadeError {
  const NightshadeError_InvalidDeviceId({required this.deviceId, required this.reason}): super._();
  

 final  String deviceId;
 final  String reason;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_InvalidDeviceIdCopyWith<NightshadeError_InvalidDeviceId> get copyWith => _$NightshadeError_InvalidDeviceIdCopyWithImpl<NightshadeError_InvalidDeviceId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_InvalidDeviceId&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,reason);

@override
String toString() {
  return 'NightshadeError.invalidDeviceId(deviceId: $deviceId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_InvalidDeviceIdCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_InvalidDeviceIdCopyWith(NightshadeError_InvalidDeviceId value, $Res Function(NightshadeError_InvalidDeviceId) _then) = _$NightshadeError_InvalidDeviceIdCopyWithImpl;
@useResult
$Res call({
 String deviceId, String reason
});




}
/// @nodoc
class _$NightshadeError_InvalidDeviceIdCopyWithImpl<$Res>
    implements $NightshadeError_InvalidDeviceIdCopyWith<$Res> {
  _$NightshadeError_InvalidDeviceIdCopyWithImpl(this._self, this._then);

  final NightshadeError_InvalidDeviceId _self;
  final $Res Function(NightshadeError_InvalidDeviceId) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? reason = null,}) {
  return _then(NightshadeError_InvalidDeviceId(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_ParameterOutOfRange extends NightshadeError {
  const NightshadeError_ParameterOutOfRange({required this.paramName, required this.value, required this.min, required this.max}): super._();
  

 final  String paramName;
 final  String value;
 final  String min;
 final  String max;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ParameterOutOfRangeCopyWith<NightshadeError_ParameterOutOfRange> get copyWith => _$NightshadeError_ParameterOutOfRangeCopyWithImpl<NightshadeError_ParameterOutOfRange>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ParameterOutOfRange&&(identical(other.paramName, paramName) || other.paramName == paramName)&&(identical(other.value, value) || other.value == value)&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max));
}


@override
int get hashCode => Object.hash(runtimeType,paramName,value,min,max);

@override
String toString() {
  return 'NightshadeError.parameterOutOfRange(paramName: $paramName, value: $value, min: $min, max: $max)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ParameterOutOfRangeCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ParameterOutOfRangeCopyWith(NightshadeError_ParameterOutOfRange value, $Res Function(NightshadeError_ParameterOutOfRange) _then) = _$NightshadeError_ParameterOutOfRangeCopyWithImpl;
@useResult
$Res call({
 String paramName, String value, String min, String max
});




}
/// @nodoc
class _$NightshadeError_ParameterOutOfRangeCopyWithImpl<$Res>
    implements $NightshadeError_ParameterOutOfRangeCopyWith<$Res> {
  _$NightshadeError_ParameterOutOfRangeCopyWithImpl(this._self, this._then);

  final NightshadeError_ParameterOutOfRange _self;
  final $Res Function(NightshadeError_ParameterOutOfRange) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? paramName = null,Object? value = null,Object? min = null,Object? max = null,}) {
  return _then(NightshadeError_ParameterOutOfRange(
paramName: null == paramName ? _self.paramName : paramName // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,min: null == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as String,max: null == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_OperationFailed extends NightshadeError {
  const NightshadeError_OperationFailed(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_OperationFailedCopyWith<NightshadeError_OperationFailed> get copyWith => _$NightshadeError_OperationFailedCopyWithImpl<NightshadeError_OperationFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_OperationFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.operationFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_OperationFailedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_OperationFailedCopyWith(NightshadeError_OperationFailed value, $Res Function(NightshadeError_OperationFailed) _then) = _$NightshadeError_OperationFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_OperationFailedCopyWithImpl<$Res>
    implements $NightshadeError_OperationFailedCopyWith<$Res> {
  _$NightshadeError_OperationFailedCopyWithImpl(this._self, this._then);

  final NightshadeError_OperationFailed _self;
  final $Res Function(NightshadeError_OperationFailed) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_OperationFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_NotSupported extends NightshadeError {
  const NightshadeError_NotSupported({required this.deviceId, required this.operation}): super._();
  

 final  String deviceId;
 final  String operation;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_NotSupportedCopyWith<NightshadeError_NotSupported> get copyWith => _$NightshadeError_NotSupportedCopyWithImpl<NightshadeError_NotSupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_NotSupported&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.operation, operation) || other.operation == operation));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,operation);

@override
String toString() {
  return 'NightshadeError.notSupported(deviceId: $deviceId, operation: $operation)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_NotSupportedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_NotSupportedCopyWith(NightshadeError_NotSupported value, $Res Function(NightshadeError_NotSupported) _then) = _$NightshadeError_NotSupportedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String operation
});




}
/// @nodoc
class _$NightshadeError_NotSupportedCopyWithImpl<$Res>
    implements $NightshadeError_NotSupportedCopyWith<$Res> {
  _$NightshadeError_NotSupportedCopyWithImpl(this._self, this._then);

  final NightshadeError_NotSupported _self;
  final $Res Function(NightshadeError_NotSupported) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? operation = null,}) {
  return _then(NightshadeError_NotSupported(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_DeviceBusy extends NightshadeError {
  const NightshadeError_DeviceBusy({required this.deviceId, required this.currentOperation}): super._();
  

 final  String deviceId;
 final  String currentOperation;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_DeviceBusyCopyWith<NightshadeError_DeviceBusy> get copyWith => _$NightshadeError_DeviceBusyCopyWithImpl<NightshadeError_DeviceBusy>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_DeviceBusy&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.currentOperation, currentOperation) || other.currentOperation == currentOperation));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,currentOperation);

@override
String toString() {
  return 'NightshadeError.deviceBusy(deviceId: $deviceId, currentOperation: $currentOperation)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_DeviceBusyCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_DeviceBusyCopyWith(NightshadeError_DeviceBusy value, $Res Function(NightshadeError_DeviceBusy) _then) = _$NightshadeError_DeviceBusyCopyWithImpl;
@useResult
$Res call({
 String deviceId, String currentOperation
});




}
/// @nodoc
class _$NightshadeError_DeviceBusyCopyWithImpl<$Res>
    implements $NightshadeError_DeviceBusyCopyWith<$Res> {
  _$NightshadeError_DeviceBusyCopyWithImpl(this._self, this._then);

  final NightshadeError_DeviceBusy _self;
  final $Res Function(NightshadeError_DeviceBusy) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? currentOperation = null,}) {
  return _then(NightshadeError_DeviceBusy(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,currentOperation: null == currentOperation ? _self.currentOperation : currentOperation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_ImageError extends NightshadeError {
  const NightshadeError_ImageError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ImageErrorCopyWith<NightshadeError_ImageError> get copyWith => _$NightshadeError_ImageErrorCopyWithImpl<NightshadeError_ImageError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ImageError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.imageError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ImageErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ImageErrorCopyWith(NightshadeError_ImageError value, $Res Function(NightshadeError_ImageError) _then) = _$NightshadeError_ImageErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_ImageErrorCopyWithImpl<$Res>
    implements $NightshadeError_ImageErrorCopyWith<$Res> {
  _$NightshadeError_ImageErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_ImageError _self;
  final $Res Function(NightshadeError_ImageError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_ImageError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_CameraError extends NightshadeError {
  const NightshadeError_CameraError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_CameraErrorCopyWith<NightshadeError_CameraError> get copyWith => _$NightshadeError_CameraErrorCopyWithImpl<NightshadeError_CameraError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_CameraError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.cameraError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_CameraErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_CameraErrorCopyWith(NightshadeError_CameraError value, $Res Function(NightshadeError_CameraError) _then) = _$NightshadeError_CameraErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_CameraErrorCopyWithImpl<$Res>
    implements $NightshadeError_CameraErrorCopyWith<$Res> {
  _$NightshadeError_CameraErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_CameraError _self;
  final $Res Function(NightshadeError_CameraError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_CameraError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_NoImageAvailable extends NightshadeError {
  const NightshadeError_NoImageAvailable(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_NoImageAvailable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NightshadeError.noImageAvailable()';
}


}




/// @nodoc


class NightshadeError_ExposureCancelled extends NightshadeError {
  const NightshadeError_ExposureCancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ExposureCancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NightshadeError.exposureCancelled()';
}


}




/// @nodoc


class NightshadeError_ExposureFailed extends NightshadeError {
  const NightshadeError_ExposureFailed({required this.cameraId, required this.reason}): super._();
  

 final  String cameraId;
 final  String reason;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ExposureFailedCopyWith<NightshadeError_ExposureFailed> get copyWith => _$NightshadeError_ExposureFailedCopyWithImpl<NightshadeError_ExposureFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ExposureFailed&&(identical(other.cameraId, cameraId) || other.cameraId == cameraId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,cameraId,reason);

@override
String toString() {
  return 'NightshadeError.exposureFailed(cameraId: $cameraId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ExposureFailedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ExposureFailedCopyWith(NightshadeError_ExposureFailed value, $Res Function(NightshadeError_ExposureFailed) _then) = _$NightshadeError_ExposureFailedCopyWithImpl;
@useResult
$Res call({
 String cameraId, String reason
});




}
/// @nodoc
class _$NightshadeError_ExposureFailedCopyWithImpl<$Res>
    implements $NightshadeError_ExposureFailedCopyWith<$Res> {
  _$NightshadeError_ExposureFailedCopyWithImpl(this._self, this._then);

  final NightshadeError_ExposureFailed _self;
  final $Res Function(NightshadeError_ExposureFailed) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cameraId = null,Object? reason = null,}) {
  return _then(NightshadeError_ExposureFailed(
cameraId: null == cameraId ? _self.cameraId : cameraId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_DownloadFailed extends NightshadeError {
  const NightshadeError_DownloadFailed({required this.cameraId, required this.reason}): super._();
  

 final  String cameraId;
 final  String reason;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_DownloadFailedCopyWith<NightshadeError_DownloadFailed> get copyWith => _$NightshadeError_DownloadFailedCopyWithImpl<NightshadeError_DownloadFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_DownloadFailed&&(identical(other.cameraId, cameraId) || other.cameraId == cameraId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,cameraId,reason);

@override
String toString() {
  return 'NightshadeError.downloadFailed(cameraId: $cameraId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_DownloadFailedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_DownloadFailedCopyWith(NightshadeError_DownloadFailed value, $Res Function(NightshadeError_DownloadFailed) _then) = _$NightshadeError_DownloadFailedCopyWithImpl;
@useResult
$Res call({
 String cameraId, String reason
});




}
/// @nodoc
class _$NightshadeError_DownloadFailedCopyWithImpl<$Res>
    implements $NightshadeError_DownloadFailedCopyWith<$Res> {
  _$NightshadeError_DownloadFailedCopyWithImpl(this._self, this._then);

  final NightshadeError_DownloadFailed _self;
  final $Res Function(NightshadeError_DownloadFailed) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cameraId = null,Object? reason = null,}) {
  return _then(NightshadeError_DownloadFailed(
cameraId: null == cameraId ? _self.cameraId : cameraId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_IoError extends NightshadeError {
  const NightshadeError_IoError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_IoErrorCopyWith<NightshadeError_IoError> get copyWith => _$NightshadeError_IoErrorCopyWithImpl<NightshadeError_IoError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_IoError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.ioError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_IoErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_IoErrorCopyWith(NightshadeError_IoError value, $Res Function(NightshadeError_IoError) _then) = _$NightshadeError_IoErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_IoErrorCopyWithImpl<$Res>
    implements $NightshadeError_IoErrorCopyWith<$Res> {
  _$NightshadeError_IoErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_IoError _self;
  final $Res Function(NightshadeError_IoError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_IoError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_SerializationError extends NightshadeError {
  const NightshadeError_SerializationError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_SerializationErrorCopyWith<NightshadeError_SerializationError> get copyWith => _$NightshadeError_SerializationErrorCopyWithImpl<NightshadeError_SerializationError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_SerializationError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.serializationError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_SerializationErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_SerializationErrorCopyWith(NightshadeError_SerializationError value, $Res Function(NightshadeError_SerializationError) _then) = _$NightshadeError_SerializationErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_SerializationErrorCopyWithImpl<$Res>
    implements $NightshadeError_SerializationErrorCopyWith<$Res> {
  _$NightshadeError_SerializationErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_SerializationError _self;
  final $Res Function(NightshadeError_SerializationError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_SerializationError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_PlateSolveError extends NightshadeError {
  const NightshadeError_PlateSolveError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_PlateSolveErrorCopyWith<NightshadeError_PlateSolveError> get copyWith => _$NightshadeError_PlateSolveErrorCopyWithImpl<NightshadeError_PlateSolveError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_PlateSolveError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.plateSolveError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_PlateSolveErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_PlateSolveErrorCopyWith(NightshadeError_PlateSolveError value, $Res Function(NightshadeError_PlateSolveError) _then) = _$NightshadeError_PlateSolveErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_PlateSolveErrorCopyWithImpl<$Res>
    implements $NightshadeError_PlateSolveErrorCopyWith<$Res> {
  _$NightshadeError_PlateSolveErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_PlateSolveError _self;
  final $Res Function(NightshadeError_PlateSolveError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_PlateSolveError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_SequenceError extends NightshadeError {
  const NightshadeError_SequenceError(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_SequenceErrorCopyWith<NightshadeError_SequenceError> get copyWith => _$NightshadeError_SequenceErrorCopyWithImpl<NightshadeError_SequenceError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_SequenceError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.sequenceError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_SequenceErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_SequenceErrorCopyWith(NightshadeError_SequenceError value, $Res Function(NightshadeError_SequenceError) _then) = _$NightshadeError_SequenceErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_SequenceErrorCopyWithImpl<$Res>
    implements $NightshadeError_SequenceErrorCopyWith<$Res> {
  _$NightshadeError_SequenceErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_SequenceError _self;
  final $Res Function(NightshadeError_SequenceError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_SequenceError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_AscomError extends NightshadeError {
  const NightshadeError_AscomError({required this.progId, required this.message, required this.errorCode}): super._();
  

 final  String progId;
 final  String message;
 final  int errorCode;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_AscomErrorCopyWith<NightshadeError_AscomError> get copyWith => _$NightshadeError_AscomErrorCopyWithImpl<NightshadeError_AscomError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_AscomError&&(identical(other.progId, progId) || other.progId == progId)&&(identical(other.message, message) || other.message == message)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode));
}


@override
int get hashCode => Object.hash(runtimeType,progId,message,errorCode);

@override
String toString() {
  return 'NightshadeError.ascomError(progId: $progId, message: $message, errorCode: $errorCode)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_AscomErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_AscomErrorCopyWith(NightshadeError_AscomError value, $Res Function(NightshadeError_AscomError) _then) = _$NightshadeError_AscomErrorCopyWithImpl;
@useResult
$Res call({
 String progId, String message, int errorCode
});




}
/// @nodoc
class _$NightshadeError_AscomErrorCopyWithImpl<$Res>
    implements $NightshadeError_AscomErrorCopyWith<$Res> {
  _$NightshadeError_AscomErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_AscomError _self;
  final $Res Function(NightshadeError_AscomError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progId = null,Object? message = null,Object? errorCode = null,}) {
  return _then(NightshadeError_AscomError(
progId: null == progId ? _self.progId : progId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,errorCode: null == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class NightshadeError_AlpacaError extends NightshadeError {
  const NightshadeError_AlpacaError({required this.baseUrl, required this.deviceNumber, required this.message, required this.errorCode}): super._();
  

 final  String baseUrl;
 final  int deviceNumber;
 final  String message;
 final  int errorCode;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_AlpacaErrorCopyWith<NightshadeError_AlpacaError> get copyWith => _$NightshadeError_AlpacaErrorCopyWithImpl<NightshadeError_AlpacaError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_AlpacaError&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.deviceNumber, deviceNumber) || other.deviceNumber == deviceNumber)&&(identical(other.message, message) || other.message == message)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode));
}


@override
int get hashCode => Object.hash(runtimeType,baseUrl,deviceNumber,message,errorCode);

@override
String toString() {
  return 'NightshadeError.alpacaError(baseUrl: $baseUrl, deviceNumber: $deviceNumber, message: $message, errorCode: $errorCode)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_AlpacaErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_AlpacaErrorCopyWith(NightshadeError_AlpacaError value, $Res Function(NightshadeError_AlpacaError) _then) = _$NightshadeError_AlpacaErrorCopyWithImpl;
@useResult
$Res call({
 String baseUrl, int deviceNumber, String message, int errorCode
});




}
/// @nodoc
class _$NightshadeError_AlpacaErrorCopyWithImpl<$Res>
    implements $NightshadeError_AlpacaErrorCopyWith<$Res> {
  _$NightshadeError_AlpacaErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_AlpacaError _self;
  final $Res Function(NightshadeError_AlpacaError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? baseUrl = null,Object? deviceNumber = null,Object? message = null,Object? errorCode = null,}) {
  return _then(NightshadeError_AlpacaError(
baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,deviceNumber: null == deviceNumber ? _self.deviceNumber : deviceNumber // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,errorCode: null == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class NightshadeError_IndiError extends NightshadeError {
  const NightshadeError_IndiError({required this.server, required this.port, required this.deviceName, required this.message}): super._();
  

 final  String server;
 final  int port;
 final  String deviceName;
 final  String message;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_IndiErrorCopyWith<NightshadeError_IndiError> get copyWith => _$NightshadeError_IndiErrorCopyWithImpl<NightshadeError_IndiError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_IndiError&&(identical(other.server, server) || other.server == server)&&(identical(other.port, port) || other.port == port)&&(identical(other.deviceName, deviceName) || other.deviceName == deviceName)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,server,port,deviceName,message);

@override
String toString() {
  return 'NightshadeError.indiError(server: $server, port: $port, deviceName: $deviceName, message: $message)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_IndiErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_IndiErrorCopyWith(NightshadeError_IndiError value, $Res Function(NightshadeError_IndiError) _then) = _$NightshadeError_IndiErrorCopyWithImpl;
@useResult
$Res call({
 String server, int port, String deviceName, String message
});




}
/// @nodoc
class _$NightshadeError_IndiErrorCopyWithImpl<$Res>
    implements $NightshadeError_IndiErrorCopyWith<$Res> {
  _$NightshadeError_IndiErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_IndiError _self;
  final $Res Function(NightshadeError_IndiError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? server = null,Object? port = null,Object? deviceName = null,Object? message = null,}) {
  return _then(NightshadeError_IndiError(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,deviceName: null == deviceName ? _self.deviceName : deviceName // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_NativeError extends NightshadeError {
  const NightshadeError_NativeError({required this.vendor, required this.message, required this.errorCode}): super._();
  

 final  String vendor;
 final  String message;
 final  int errorCode;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_NativeErrorCopyWith<NightshadeError_NativeError> get copyWith => _$NightshadeError_NativeErrorCopyWithImpl<NightshadeError_NativeError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_NativeError&&(identical(other.vendor, vendor) || other.vendor == vendor)&&(identical(other.message, message) || other.message == message)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode));
}


@override
int get hashCode => Object.hash(runtimeType,vendor,message,errorCode);

@override
String toString() {
  return 'NightshadeError.nativeError(vendor: $vendor, message: $message, errorCode: $errorCode)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_NativeErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_NativeErrorCopyWith(NightshadeError_NativeError value, $Res Function(NightshadeError_NativeError) _then) = _$NightshadeError_NativeErrorCopyWithImpl;
@useResult
$Res call({
 String vendor, String message, int errorCode
});




}
/// @nodoc
class _$NightshadeError_NativeErrorCopyWithImpl<$Res>
    implements $NightshadeError_NativeErrorCopyWith<$Res> {
  _$NightshadeError_NativeErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_NativeError _self;
  final $Res Function(NightshadeError_NativeError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? vendor = null,Object? message = null,Object? errorCode = null,}) {
  return _then(NightshadeError_NativeError(
vendor: null == vendor ? _self.vendor : vendor // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,errorCode: null == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class NightshadeError_ComError extends NightshadeError {
  const NightshadeError_ComError({required this.message, required this.hresult}): super._();
  

 final  String message;
 final  int hresult;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ComErrorCopyWith<NightshadeError_ComError> get copyWith => _$NightshadeError_ComErrorCopyWithImpl<NightshadeError_ComError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ComError&&(identical(other.message, message) || other.message == message)&&(identical(other.hresult, hresult) || other.hresult == hresult));
}


@override
int get hashCode => Object.hash(runtimeType,message,hresult);

@override
String toString() {
  return 'NightshadeError.comError(message: $message, hresult: $hresult)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ComErrorCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ComErrorCopyWith(NightshadeError_ComError value, $Res Function(NightshadeError_ComError) _then) = _$NightshadeError_ComErrorCopyWithImpl;
@useResult
$Res call({
 String message, int hresult
});




}
/// @nodoc
class _$NightshadeError_ComErrorCopyWithImpl<$Res>
    implements $NightshadeError_ComErrorCopyWith<$Res> {
  _$NightshadeError_ComErrorCopyWithImpl(this._self, this._then);

  final NightshadeError_ComError _self;
  final $Res Function(NightshadeError_ComError) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? hresult = null,}) {
  return _then(NightshadeError_ComError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,hresult: null == hresult ? _self.hresult : hresult // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class NightshadeError_Internal extends NightshadeError {
  const NightshadeError_Internal(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_InternalCopyWith<NightshadeError_Internal> get copyWith => _$NightshadeError_InternalCopyWithImpl<NightshadeError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_Internal&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.internal(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_InternalCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_InternalCopyWith(NightshadeError_Internal value, $Res Function(NightshadeError_Internal) _then) = _$NightshadeError_InternalCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_InternalCopyWithImpl<$Res>
    implements $NightshadeError_InternalCopyWith<$Res> {
  _$NightshadeError_InternalCopyWithImpl(this._self, this._then);

  final NightshadeError_Internal _self;
  final $Res Function(NightshadeError_Internal) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_Internal(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_Cancelled extends NightshadeError {
  const NightshadeError_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NightshadeError.cancelled()';
}


}




/// @nodoc


class NightshadeError_RuntimeInitFailed extends NightshadeError {
  const NightshadeError_RuntimeInitFailed(this.field0): super._();
  

 final  String field0;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_RuntimeInitFailedCopyWith<NightshadeError_RuntimeInitFailed> get copyWith => _$NightshadeError_RuntimeInitFailedCopyWithImpl<NightshadeError_RuntimeInitFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_RuntimeInitFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'NightshadeError.runtimeInitFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_RuntimeInitFailedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_RuntimeInitFailedCopyWith(NightshadeError_RuntimeInitFailed value, $Res Function(NightshadeError_RuntimeInitFailed) _then) = _$NightshadeError_RuntimeInitFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$NightshadeError_RuntimeInitFailedCopyWithImpl<$Res>
    implements $NightshadeError_RuntimeInitFailedCopyWith<$Res> {
  _$NightshadeError_RuntimeInitFailedCopyWithImpl(this._self, this._then);

  final NightshadeError_RuntimeInitFailed _self;
  final $Res Function(NightshadeError_RuntimeInitFailed) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(NightshadeError_RuntimeInitFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NightshadeError_ResourceExhausted extends NightshadeError {
  const NightshadeError_ResourceExhausted({required this.resource, required this.message}): super._();
  

 final  String resource;
 final  String message;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NightshadeError_ResourceExhaustedCopyWith<NightshadeError_ResourceExhausted> get copyWith => _$NightshadeError_ResourceExhaustedCopyWithImpl<NightshadeError_ResourceExhausted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NightshadeError_ResourceExhausted&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,resource,message);

@override
String toString() {
  return 'NightshadeError.resourceExhausted(resource: $resource, message: $message)';
}


}

/// @nodoc
abstract mixin class $NightshadeError_ResourceExhaustedCopyWith<$Res> implements $NightshadeErrorCopyWith<$Res> {
  factory $NightshadeError_ResourceExhaustedCopyWith(NightshadeError_ResourceExhausted value, $Res Function(NightshadeError_ResourceExhausted) _then) = _$NightshadeError_ResourceExhaustedCopyWithImpl;
@useResult
$Res call({
 String resource, String message
});




}
/// @nodoc
class _$NightshadeError_ResourceExhaustedCopyWithImpl<$Res>
    implements $NightshadeError_ResourceExhaustedCopyWith<$Res> {
  _$NightshadeError_ResourceExhaustedCopyWithImpl(this._self, this._then);

  final NightshadeError_ResourceExhausted _self;
  final $Res Function(NightshadeError_ResourceExhausted) _then;

/// Create a copy of NightshadeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? message = null,}) {
  return _then(NightshadeError_ResourceExhausted(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
