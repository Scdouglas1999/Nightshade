import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The running application's semantic version + build number.
///
/// Single source of truth surfaced to all packages that need to label
/// payloads (backups, manifests, OTA updates, telemetry). Composed from
/// `version.yaml` and wired into the provider container at app startup
/// via `appVersionProvider.overrideWithValue(...)`.
class AppVersionInfo {
  final String version;
  final int buildNumber;

  const AppVersionInfo({required this.version, required this.buildNumber});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppVersionInfo &&
          other.version == version &&
          other.buildNumber == buildNumber);

  @override
  int get hashCode => Object.hash(version, buildNumber);

  @override
  String toString() => '$version+$buildNumber';
}

/// Provider for the running application version.
///
/// Why throw instead of returning a default: a misconfigured version masks
/// the entire OTA update flow (the server compares against this string to
/// decide whether to advertise a newer build). A bogus default like
/// `2.0.0` would cause the app to perpetually offer "updates" to a build
/// it is already running, or refuse legitimate updates.
/// "errors are a feature": consumers must override this provider at
/// startup, and an UnsupportedError here surfaces the configuration bug
/// loudly.
final appVersionProvider = Provider<AppVersionInfo>((ref) {
  throw UnsupportedError(
    'appVersionProvider must be overridden at app startup with the '
    'concrete version from version.yaml. See main.dart in apps/desktop '
    'or apps/mobile for the canonical override.',
  );
});

/// `Nightshade <version>` label for stamping exports and FITS headers
/// (AAVSO #SOFTWARE, NSHA_VER, science reports). Falls back to a plain
/// "Nightshade" when [appVersionProvider] has not been overridden (test
/// benches) so a label consumer never crashes a data export over version
/// metadata. Kept short — the FITS writeback needs it to fit a single
/// 80-char header card with room for a comment.
final appVersionLabelProvider = Provider<String>((ref) {
  try {
    final v = ref.read(appVersionProvider);
    return 'Nightshade ${v.version}';
  } catch (_) {
    return 'Nightshade';
  }
});
