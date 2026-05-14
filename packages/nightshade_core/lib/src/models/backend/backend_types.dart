/// Barrel file for backend model types.
///
/// Import this file to get all backend-related types:
/// ```dart
/// import 'package:nightshade_core/src/models/backend/backend_types.dart';
/// ```

export 'autofocus_result.dart';
export 'builtin_guider_config.dart';
export 'device_capabilities.dart';
export 'device_info.dart';
export 'device_status.dart';
export 'device_types.dart';
export 'event_types.dart';
export 'fits_header.dart';
export 'image_result.dart';
export 'platform_capabilities.dart';
export 'phd2_status.dart';
// PlateSolveResult comes from the FRB-canonical type
// (`package:nightshade_bridge/src/api/plate_solve.dart`); re-exported through
// `nightshade_core.dart`'s `nightshade_bridge` re-export.
export 'remote_api_compatibility.dart';
export 'sequencer_status.dart';
export '../errors/nightshade_error.dart';
