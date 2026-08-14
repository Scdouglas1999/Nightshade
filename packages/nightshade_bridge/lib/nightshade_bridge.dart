/// Nightshade Bridge - Dart FFI bindings to Rust native code
library;

export 'src/frb_generated.dart';
export 'src/event.dart';
export 'src/event_display.dart';
export 'src/device.dart';
export 'src/bridge_stub.dart'
    hide
        // Types that conflict with frb_generated/api.dart
        AutofocusConfigApi,
        AutofocusResultApi,
        CapturedImageResult,
        CheckpointInfoApi,
        ImageStatsResult,
        Phd2Status,
        Phd2StarImage,
        PlateSolveResult,
        SequencerState,
        // Types that conflict with event.dart
        NightshadeEvent,
        EventSeverity,
        EventCategory,
        PolarAlignmentEvent,
        // Types that conflict with device.dart
        DeviceType,
        DriverType,
        CameraStatus,
        DeviceInfo,
        FilterWheelStatus,
        FocuserStatus,
        MountStatus,
        PierSide,
        RotatorStatus,
        TrackingRate,
        FrameType,
        ShutterState;
export 'src/api_barrel.dart';

// Export PHD2 utilities
export 'src/rolling_rms_calculator.dart';

// Export device capabilities
export 'src/device_capabilities.dart';

// Export safe-cast helpers used at the FFI boundary.
// Re-exported from nightshade_core for discoverability.
export 'src/utils/safe_cast.dart';

// Export the FRB-generated NightshadeError sealed class hierarchy so
// consumers don't have to reach into `src/error.dart` directly.
export 'src/error.dart';
