# Core Services API Reference

Core services provide high-level business logic and data management for the Nightshade application.

## ImagingService

Service for managing camera capture operations.

### `captureImage`

Start a single exposure capture.

```dart
Future<CapturedImageData?> captureImage({
  required ExposureSettings settings,
  String? targetName,
  int? frameNumber,
})
```

**Parameters:**
- `settings` - Exposure settings (time, frame type, binning, etc.)
- `targetName` - Optional target name
- `frameNumber` - Optional frame number

**Returns:** Captured image data or null if cancelled

**Example:**
```dart
final service = ImagingService(ref);
final image = await service.captureImage(
  settings: ExposureSettings(
    exposureTime: 60.0,
    frameType: FrameType.light,
    binningX: 1,
    binningY: 1,
  ),
  targetName: 'M42',
);
```

## DeviceService

Service for device discovery and connection management.

Located in `packages/nightshade_core/lib/src/services/device_service.dart`.

## PlateSolveService

Service for plate solving operations.

Located in `packages/nightshade_core/lib/src/services/plate_solve_service.dart`.

## ProfileService

Service for managing equipment profiles.

Located in `packages/nightshade_core/lib/src/services/profile_service.dart`.

## SequenceFileService

Service for sequence file operations.

Located in `packages/nightshade_core/lib/src/services/sequence_file_service.dart`.

## SequenceRepository

Repository for sequence data management.

Located in `packages/nightshade_core/lib/src/services/sequence_repository.dart`.

## AnnotationService

Service for image annotations.

Located in `packages/nightshade_core/lib/src/services/annotation_service.dart`.

## WcsOverlay

Service for World Coordinate System overlays.

Located in `packages/nightshade_core/lib/src/services/wcs_overlay.dart`.

## Providers

Core services are typically accessed through Riverpod providers:

- `backendProvider` - Backend instance
- `cameraStateProvider` - Camera connection state
- `imagingProvider` - Imaging operations
- `equipmentProvider` - Equipment management
- `sequenceProvider` - Sequence management
- `settingsProvider` - Application settings
- `profilesProvider` - Equipment profiles
- `sessionProvider` - Imaging session
- `guidingProvider` - Guiding operations

**Example:**
```dart
final backend = ref.read(backendProvider);
final cameraState = ref.watch(cameraStateProvider);
```

