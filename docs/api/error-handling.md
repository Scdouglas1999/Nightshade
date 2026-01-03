# Error Handling Reference

Complete guide to error handling in the Nightshade API.

## NightshadeError

All API methods may throw `NightshadeError` exceptions. This is a sealed class with multiple error variants.

### Error Types

#### DeviceNotFound

Device not found.

```dart
NightshadeError.deviceNotFound('Device camera-1 not found')
```

#### ConnectionFailed

Device connection failed.

```dart
NightshadeError.connectionFailed('Failed to connect: timeout')
```

#### AlreadyConnected

Device already connected.

```dart
NightshadeError.alreadyConnected('Device camera-1 is already connected')
```

#### NotConnected

Device not connected.

```dart
NightshadeError.notConnected('Device camera-1 is not connected')
```

#### Timeout

Operation timed out.

```dart
NightshadeError.timeout('Exposure timed out after 60 seconds')
```

#### InvalidParameter

Invalid parameter value.

```dart
NightshadeError.invalidParameter('Exposure time must be positive')
```

#### InvalidInput

Invalid input data.

```dart
NightshadeError.invalidInput('Invalid coordinates: RA must be 0-24 hours')
```

#### InvalidDeviceId

Invalid device identifier.

```dart
NightshadeError.invalidDeviceId('Invalid device ID format')
```

#### OperationFailed

Operation failed.

```dart
NightshadeError.operationFailed('Slew failed: mount error')
```

#### ImageError

Image processing error.

```dart
NightshadeError.imageError('Failed to decode image data')
```

#### IoError

File I/O error.

```dart
NightshadeError.ioError('Failed to read file: permission denied')
```

#### PlateSolveError

Plate solving error.

```dart
NightshadeError.plateSolveError('Plate solve failed: no stars detected')
```

#### SequenceError

Sequence execution error.

```dart
NightshadeError.sequenceError('Sequence node failed: exposure error')
```

#### NoImageAvailable

No image available.

```dart
NightshadeError.noImageAvailable()
```

#### ExposureCancelled

Exposure was cancelled.

```dart
NightshadeError.exposureCancelled()
```

#### Cancelled

Operation was cancelled.

```dart
NightshadeError.cancelled()
```

#### CameraError

Camera-specific error.

```dart
NightshadeError.cameraError('Camera temperature too high')
```

#### Internal

Internal error.

```dart
NightshadeError.internal('Unexpected error in device driver')
```

## Error Handling Patterns

### Basic Error Handling

```dart
try {
  await backend.connectDevice(DeviceType.camera, 'camera-1');
} on NightshadeError catch (e) {
  print('Error: ${e.toString()}');
}
```

### Specific Error Handling

```dart
try {
  await backend.cameraStartExposure(
    deviceId: 'camera-1',
    exposureTime: 60.0,
    frameType: FrameType.light,
  );
} on NightshadeError catch (e) {
  switch (e) {
    case NightshadeError_NotConnected():
      print('Camera not connected');
      break;
    case NightshadeError_Timeout():
      print('Exposure timed out');
      break;
    case NightshadeError_OperationFailed(field0: final message):
      print('Operation failed: $message');
      break;
    default:
      print('Unknown error: $e');
  }
}
```

### Error Handling with Pattern Matching

```dart
try {
  await backend.mountSlewToCoordinates('mount-1', 5.5, -5.0);
} on NightshadeError catch (e) {
  e.when(
    deviceNotFound: (msg) => showError('Device not found: $msg'),
    connectionFailed: (msg) => showError('Connection failed: $msg'),
    notConnected: (msg) => showError('Not connected: $msg'),
    timeout: (msg) => showError('Timeout: $msg'),
    operationFailed: (msg) => showError('Operation failed: $msg'),
    // ... handle other cases
    orElse: () => showError('Unknown error: $e'),
  );
}
```

### Error Handling in Async Operations

```dart
Future<void> captureImage() async {
  try {
    final image = await backend.cameraGetLastImage('camera-1');
    if (image == null) {
      throw NightshadeError.noImageAvailable();
    }
    // Process image
  } on NightshadeError_NoImageAvailable {
    print('No image available yet');
  } on NightshadeError_NotConnected {
    print('Camera not connected');
  } catch (e) {
    print('Unexpected error: $e');
  }
}
```

### Error Propagation

```dart
Future<void> startSequence() async {
  try {
    await backend.sequencerStart();
  } on NightshadeError catch (e) {
    // Log error
    logger.error('Sequence start failed', error: e);
    // Re-throw or handle
    rethrow;
  }
}
```

## Error Messages

All error types (except parameterless ones) include a message string that provides details about what went wrong.

```dart
try {
  await backend.connectDevice(DeviceType.camera, 'invalid-id');
} on NightshadeError_ConnectionFailed catch (e) {
  print(e.field0); // "Connection failed: Device not found"
}
```

## Error Events

Errors may also be emitted through the event stream:

```dart
backend.eventStream.listen((event) {
  if (event.severity == EventSeverity.error) {
    print('Error event: ${event.eventType}');
    print('Details: ${event.data}');
  }
});
```

## Best Practices

1. **Always handle errors** - Don't let errors propagate unhandled
2. **Provide user feedback** - Show meaningful error messages to users
3. **Log errors** - Log errors for debugging
4. **Retry logic** - Consider retrying transient errors (timeouts, connection failures)
5. **Graceful degradation** - Handle errors gracefully without crashing

## Example: Comprehensive Error Handling

```dart
Future<bool> connectCamera(String deviceId) async {
  try {
    await backend.connectDevice(DeviceType.camera, deviceId);
    return true;
  } on NightshadeError_DeviceNotFound catch (e) {
    showError('Camera not found: ${e.field0}');
    return false;
  } on NightshadeError_ConnectionFailed catch (e) {
    showError('Connection failed: ${e.field0}');
    // Retry logic could go here
    return false;
  } on NightshadeError_AlreadyConnected {
    // Already connected, this is OK
    return true;
  } on NightshadeError catch (e) {
    logger.error('Unexpected error connecting camera', error: e);
    showError('Unexpected error: ${e.toString()}');
    return false;
  } catch (e) {
    logger.error('Non-Nightshade error', error: e);
    showError('System error: ${e.toString()}');
    return false;
  }
}
```

