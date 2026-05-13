import 'dart:io';

import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Pre-Riverpod boot artifacts captured during early initialisation so they
/// can be reused later by Riverpod-aware services without round-tripping
/// through `path_provider` a second time.
class DesktopBootPaths {
  final String logDirectory;
  final String profileDirectory;

  const DesktopBootPaths({
    required this.logDirectory,
    required this.profileDirectory,
  });
}

/// Initialise the Rust bridge with a log directory under the platform's
/// application-support folder, then wire profile + settings storage onto
/// the same root. Returns the resolved paths so the rest of the bootstrap
/// can hand them to the `LoggingService` and `ProfileService` without
/// re-querying [getApplicationSupportDirectory].
///
/// This step must run before any provider that touches the Rust runtime
/// (every backend method goes through `bridge.NativeBridge`), so it lives
/// outside the Riverpod container.
Future<DesktopBootPaths> initialiseDesktopLogging() async {
  final appSupportDir = await getApplicationSupportDirectory();
  final logDir = path.join(appSupportDir.path, 'logs');
  await Directory(logDir).create(recursive: true);
  await bridge.NativeBridge.init(logDirectory: logDir);

  final appDir = await getApplicationDocumentsDirectory();
  final profileDir = path.join(appDir.path, 'Nightshade', 'profiles');
  await Directory(profileDir).create(recursive: true);
  await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);
  await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);

  return DesktopBootPaths(
    logDirectory: logDir,
    profileDirectory: profileDir,
  );
}
