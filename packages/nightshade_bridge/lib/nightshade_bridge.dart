/// Nightshade Bridge - Dart FFI bindings to Rust native code
library nightshade_bridge;

export 'src/frb_generated.dart';
export 'src/event.dart';
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
        CameraState,
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
export 'src/api.dart';

// Export Alpaca client for direct HTTP-based device communication
export 'src/alpaca_client.dart';

// Export ASCOM client for native Windows COM-based device communication
export 'src/ascom_client.dart';

// Export PHD2 client for autoguiding control
export 'src/phd2_client.dart';

// Export PHD2 utilities
export 'src/rolling_rms_calculator.dart';

// Export device capabilities
export 'src/device_capabilities.dart';
