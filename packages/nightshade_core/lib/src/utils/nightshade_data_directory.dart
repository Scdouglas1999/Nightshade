import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Environment variable that relocates this process's writable data root.
///
/// Set by headless/systemd units and by any second instance that must not
/// share state with the desktop GUI. The Rust side already honours it for its
/// own persistence (`NIGHTSHADE_DATA_DIR` in `bridge/src/api/imaging.rs`), so
/// Dart-side roots must resolve it the same way or the two halves of one
/// process write to two different trees.
const String nightshadeDataDirEnv = 'NIGHTSHADE_DATA_DIR';

/// Directory this process keeps its writable data under (logs, calibration
/// library, native persistence).
///
/// [nightshadeDataDirEnv] wins over the platform application-support folder
/// because that folder is per-application, not per-instance: a headless daemon
/// running beside the GUI — the configuration `main_headless` documents — would
/// otherwise resolve the same log directory as the GUI and the two would
/// interleave into one rolling log file.
Future<Directory> resolveNightshadeDataDirectory({
  Map<String, String>? environment,
  Future<Directory> Function()? applicationSupportDirectoryProvider,
}) async {
  final override = (environment ?? Platform.environment)[nightshadeDataDirEnv]
      ?.trim();
  if (override != null && override.isNotEmpty) {
    return Directory(override);
  }
  return (applicationSupportDirectoryProvider ??
      getApplicationSupportDirectory)();
}
