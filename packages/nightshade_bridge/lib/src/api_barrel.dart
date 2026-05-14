/// Aggregate re-export of the split `api/` subdir, used by hand-written
/// consumers (e.g., `bridge_stub.dart`) that imported the old monolithic
/// `api.dart` as `gen_api`. FRB regenerates the individual `api/*.dart`
/// files; this barrel is the stable hand-written surface they import from.
library;

export 'api.dart';
export 'api/api_version.dart';
export 'api/connection.dart';
export 'api/connection/alpaca_connections.dart';
export 'api/connection/ascom_connections.dart';
export 'api/devices/camera.dart';
export 'api/devices/cover_calibrator.dart';
export 'api/devices/dome.dart';
export 'api/devices/filter_wheel.dart';
export 'api/devices/focuser.dart';
export 'api/devices/mount.dart';
export 'api/devices/simulation.dart';
export 'api/devices/switch.dart';
export 'api/diagnostics.dart';
export 'api/discovery.dart';
export 'api/event_stream.dart';
export 'api/heartbeat.dart';
export 'api/imaging.dart';
export 'api/init.dart';
export 'api/phd2.dart';
export 'api/plate_solve.dart';
export 'api/polar_alignment.dart';
export 'api/sequencer.dart';
export 'api/session.dart';
export 'api/storage.dart';
