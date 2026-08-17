import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Pre-Riverpod boot artifacts captured during early initialisation so they
/// can be reused later by Riverpod-aware services without round-tripping
/// through `path_provider` a second time.
class DesktopBootPaths {
  final String logDirectory;
  final String profileDirectory;
  final String dataDirectory;

  const DesktopBootPaths({
    required this.logDirectory,
    required this.profileDirectory,
    required this.dataDirectory,
  });
}

/// Sets [NIGHTSHADE_DATA_DIR] for the current process before Rust reads it.
///
/// Respects a value already supplied by the parent shell or systemd unit.
/// The path matches [getApplicationSupportDirectory] — the same root used for
/// logs — so defect maps and other native persistence align with the GUI host.
void configureNightshadeDataDirectory(
  String dataDirectory, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final existing = env['NIGHTSHADE_DATA_DIR']?.trim();
  if (existing != null && existing.isNotEmpty) {
    return;
  }
  _setProcessEnvironment('NIGHTSHADE_DATA_DIR', dataDirectory);
}

/// Resolves the root that owns this instance's logs and native persistence.
///
/// [envDataDir] is the process's `NIGHTSHADE_DATA_DIR`; [appSupportPath] is
/// [getApplicationSupportDirectory]. When the operator has pointed
/// `NIGHTSHADE_DATA_DIR` at their own directory — the one supported way to run
/// a second instance side by side — the logs must follow it.
///
/// They did not: the log directory was hard-coded to the platform support
/// folder while only Rust's persistence honoured the env var, so every
/// instance on the machine appended to one shared `nightshade.log`. A
/// diagnostic dump then carried other instances' capture paths, target names
/// and host names to whoever received the bug report.
String resolveDesktopDataRoot({
  required String? envDataDir,
  required String appSupportPath,
}) {
  final trimmed = envDataDir?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return appSupportPath;
}

/// Resolves the directory that owns this instance's native profile, settings
/// and plate-solver JSON.
///
/// The native store holds the observer site the sequencer, the planetarium and
/// `GET /api/settings/location` all read, so it follows the same
/// operator-configured data directory as `nightshade.db` and `pairing.db` —
/// [nightshadeDatabaseDirEnv]. It did not: it resolved straight to
/// `getApplicationDocumentsDirectory()/Nightshade/profiles`, so an instance
/// pinned to its own database still read and rewrote the machine-wide file.
/// One process then answered `GET /api/settings` with the scratch database's
/// 0,0 and `GET /api/settings/location` with another install's real site,
/// and every scratch or harness run mutated the operator's own settings.
///
/// With no override the path is unchanged, so an existing install keeps its
/// profiles exactly where they are.
Future<String> resolveDesktopProfileDirectory({
  Map<String, String>? environment,
  Future<Directory> Function()? documentsDirectoryProvider,
}) async {
  final env = environment ?? Platform.environment;
  final overrideDir = env[nightshadeDatabaseDirEnv]?.trim();
  if (overrideDir != null && overrideDir.isNotEmpty) {
    return path.join(overrideDir, 'profiles');
  }

  final appDir =
      await (documentsDirectoryProvider ?? getApplicationDocumentsDirectory)();
  return path.join(appDir.path, 'Nightshade', 'profiles');
}

/// Resolves and creates this instance's log directory, publishing the same
/// root to `NIGHTSHADE_DATA_DIR` for the Rust side.
///
/// Separate from [initialiseDesktopLogging] so the path decision is reachable
/// without the native bridge: everything after this point in the bootstrap
/// requires a loadable `libnightshade_bridge`.
Future<({String dataRoot, String logDirectory})> prepareDesktopLogDirectory({
  Map<String, String>? environment,
  Future<Directory> Function()? applicationSupportDirectory,
}) async {
  final env = environment ?? Platform.environment;
  final appSupportDir =
      await (applicationSupportDirectory ?? getApplicationSupportDirectory)();
  final dataRoot = resolveDesktopDataRoot(
    envDataDir: env['NIGHTSHADE_DATA_DIR'],
    appSupportPath: appSupportDir.path,
  );
  configureNightshadeDataDirectory(dataRoot, environment: env);

  final logDir = path.join(dataRoot, 'logs');
  await Directory(logDir).create(recursive: true);
  return (dataRoot: dataRoot, logDirectory: logDir);
}

/// Product version from the built app's pubspec (`version` + build number).
Future<AppVersionInfo> loadDesktopAppVersion() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final buildNumber = int.tryParse(packageInfo.buildNumber);
  if (buildNumber == null) {
    throw StateError(
      'Invalid build number in PackageInfo: ${packageInfo.buildNumber}',
    );
  }
  return AppVersionInfo(version: packageInfo.version, buildNumber: buildNumber);
}

/// Initialise the Rust bridge with this instance's log directory, then wire
/// native profile + settings storage onto [resolveDesktopProfileDirectory].
/// Returns the resolved paths so the rest of the bootstrap can hand them to
/// the `LoggingService` and `ProfileService` without re-querying
/// [getApplicationSupportDirectory].
///
/// This step must run before any provider that touches the Rust runtime
/// (every backend method goes through `bridge.NativeBridge`), so it lives
/// outside the Riverpod container.
Future<DesktopBootPaths> initialiseDesktopLogging() async {
  final (dataRoot: dataRoot, logDirectory: logDir) =
      await prepareDesktopLogDirectory();

  // Ensure libraw.dll and other deps next to nightshade_bridge.dll resolve when
  // the process working directory is not the Release folder (e.g. shortcuts).
  configureWindowsNativeDllSearchPath();

  await bridge.NativeBridge.init(logDirectory: logDir);
  if (!bridge.NativeBridge.isNativeAvailable) {
    // Name the CURRENT platform's library and layout, so the hint points at a
    // path that exists on the operator's machine.
    final (libName, bundleHint) = switch (Platform.operatingSystem) {
      'windows' => (
        'nightshade_bridge.dll (plus libraw.dll)',
        r'build\windows\x64\runner\Release\nightshade_desktop.exe with the DLLs beside it',
      ),
      'macos' => (
        'libnightshade_bridge.dylib',
        'build/macos/Build/Products/Release/nightshade_desktop.app with the dylib in Frameworks/',
      ),
      _ => (
        'libnightshade_bridge.so',
        'build/linux/x64/release/bundle/nightshade_desktop with the .so in that bundle\'s lib/ directory',
      ),
    };
    throw StateError(
      'Native bridge failed to initialize: $libName could not be loaded, or it '
      'is stale relative to this build. Run '
      '$bundleHint. '
      'After changing the Rust API run `flutter_rust_bridge_codegen generate`, '
      'rebuild the bridge, and copy the fresh library into the bundle — a '
      'bridge library older than the Dart build fails here with no other '
      'symptom. Check the console for "[Bridge] RustLib initialization failed".',
    );
  }

  final profileDir = await resolveDesktopProfileDirectory();
  await Directory(profileDir).create(recursive: true);
  await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);
  await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);

  return DesktopBootPaths(
    logDirectory: logDir,
    profileDirectory: profileDir,
    // The root actually in use, so the headless banner names the directory
    // this process is really reading and writing.
    dataDirectory: dataRoot,
  );
}

/// Adds the executable directory to the Windows DLL search path so
/// `nightshade_bridge.dll` can resolve `libraw.dll` and MSVC runtimes staged
/// beside the desktop exe.
void configureWindowsNativeDllSearchPath() {
  if (!Platform.isWindows) return;

  final exeDir = path.dirname(Platform.resolvedExecutable);
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setDllDirectory = kernel32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('SetDllDirectoryW');
  final dirPtr = exeDir.toNativeUtf16();
  try {
    final result = setDllDirectory(dirPtr);
    if (result == 0) {
      throw StateError(
        'SetDllDirectoryW failed for native DLL search path: $exeDir',
      );
    }
  } finally {
    malloc.free(dirPtr);
  }
}

void _setProcessEnvironment(String name, String value) {
  if (Platform.isWindows) {
    _setWindowsEnvironment(name, value);
    return;
  }
  _setPosixEnvironment(name, value);
}

void _setPosixEnvironment(String name, String value) {
  final setenv = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('setenv');
  final namePtr = name.toNativeUtf8();
  final valuePtr = value.toNativeUtf8();
  try {
    final result = setenv(namePtr, valuePtr, 1);
    if (result != 0) {
      throw StateError('setenv($name) failed (code $result)');
    }
  } finally {
    malloc.free(namePtr);
    malloc.free(valuePtr);
  }
}

void _setWindowsEnvironment(String name, String value) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setEnvironmentVariable = kernel32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)
      >('SetEnvironmentVariableW');
  final namePtr = name.toNativeUtf16();
  final valuePtr = value.toNativeUtf16();
  try {
    final result = setEnvironmentVariable(namePtr, valuePtr);
    if (result == 0) {
      throw StateError('SetEnvironmentVariableW($name) failed');
    }
  } finally {
    malloc.free(namePtr);
    malloc.free(valuePtr);
  }
}
