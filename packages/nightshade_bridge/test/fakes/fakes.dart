// Barrel for test fakes — import in downstream test packages as:
//   import 'package:nightshade_bridge/test/fakes/fakes.dart';
//
// (Or copy the absolute file path; this barrel only exists so the harness in
// `nightshade_app/test/harness/` and ad-hoc widget tests have a single, stable
// entry point as more fakes are added in W-TEST.)

export 'fake_native_bridge.dart';
