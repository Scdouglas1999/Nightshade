// Cloud backup/sync — remote storage abstraction.
//
// A [SyncTarget] is a minimal remote filesystem the [SyncService] pushes
// backup bundles to and pulls them from. The contract is intentionally
// tiny (upload / download / list / delete / mkdir) so different remote
// protocols can sit behind it:
//
//   * [WebDavSyncTarget] (webdav_sync_target.dart) — Nextcloud / ownCloud /
//     generic WebDAV. The only implemented target today.
//   * [S3SyncTarget] (below) — placeholder for S3-compatible object stores.
//
// CONFLICT STANCE: sync is bundle-based. Whole backup bundles are uploaded
// and downloaded as opaque files; there is NO merging of remote and local
// state. Restoring a remote bundle replaces local configuration through the
// existing [BackupService.restoreBackup] path, with the same confirmation
// flow a local restore uses.

/// A single entry returned by [SyncTarget.listDirectory].
class SyncRemoteEntry {
  /// Bare file or directory name (no path components).
  final String name;
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? modified;

  const SyncRemoteEntry({
    required this.name,
    required this.isDirectory,
    this.sizeBytes,
    this.modified,
  });

  @override
  String toString() =>
      'SyncRemoteEntry($name${isDirectory ? '/' : ''}, $sizeBytes bytes)';
}

/// Coarse error categories so the UI / API can surface actionable messages
/// ("check your password" vs "server unreachable") without string-matching.
enum SyncTargetErrorKind {
  /// 401/403 — wrong credentials or insufficient permissions.
  auth,

  /// 404 — remote path does not exist.
  notFound,

  /// 405/409/423 — remote state conflicts with the request (e.g. MKCOL on
  /// an existing file, missing parent collection, locked resource).
  conflict,

  /// 5xx — remote server failed.
  server,

  /// Socket / TLS / DNS failure before an HTTP status was received.
  network,

  /// Anything else (unexpected status code, malformed response, ...).
  unknown,
}

/// Thrown by [SyncTarget] implementations for any remote-side failure.
class SyncTargetException implements Exception {
  final String message;
  final SyncTargetErrorKind kind;
  final int? statusCode;

  const SyncTargetException(
    this.message, {
    this.kind = SyncTargetErrorKind.unknown,
    this.statusCode,
  });

  @override
  String toString() =>
      'SyncTargetException($kind'
      '${statusCode != null ? ' HTTP $statusCode' : ''}): $message';
}

/// Minimal remote-filesystem contract used by [SyncService].
///
/// All paths are slash-separated and relative to the target's base URL
/// (e.g. `nightshade-sync/my-laptop/manifest.json`). Implementations are
/// responsible for URL-encoding individual segments.
abstract class SyncTarget {
  /// Create [path] (and any missing parents) as a directory/collection.
  /// Must be a no-op when the directory already exists.
  Future<void> ensureDirectory(String path);

  /// Upload [bytes] to [path], overwriting any existing file.
  Future<void> uploadFile(String path, List<int> bytes);

  /// Download the file at [path]. Throws [SyncTargetException] with
  /// [SyncTargetErrorKind.notFound] when it does not exist.
  Future<List<int>> downloadFile(String path);

  /// List the immediate children of the directory at [path]. The directory
  /// itself is not included. Throws [SyncTargetErrorKind.notFound] when the
  /// directory does not exist.
  Future<List<SyncRemoteEntry>> listDirectory(String path);

  /// Delete the file at [path]. Deleting a missing file is a no-op.
  Future<void> deleteFile(String path);

  /// Cheap reachability + credential probe against the base URL. Throws
  /// [SyncTargetException] on failure, returns normally on success.
  Future<void> testConnection();
}

/// TODO(sync): S3-compatible target (AWS S3, MinIO, Backblaze B2, ...).
///
/// Deliberately left unimplemented: S3 requires SigV4 request signing,
/// which is a meaningful chunk of code we don't want to hand-roll until
/// someone actually asks for it (and adding an SDK dependency is currently
/// off the table). The class exists so the settings UI / config plumbing
/// can grow a "provider" selector later without reshaping [SyncTarget].
class S3SyncTarget implements SyncTarget {
  S3SyncTarget();

  Never _unimplemented() => throw UnimplementedError(
    'S3-compatible sync targets are not implemented yet. '
    'Use a WebDAV target (Nextcloud, ownCloud, generic WebDAV).',
  );

  @override
  Future<void> ensureDirectory(String path) async => _unimplemented();

  @override
  Future<void> uploadFile(String path, List<int> bytes) async =>
      _unimplemented();

  @override
  Future<List<int>> downloadFile(String path) async => _unimplemented();

  @override
  Future<List<SyncRemoteEntry>> listDirectory(String path) async =>
      _unimplemented();

  @override
  Future<void> deleteFile(String path) async => _unimplemented();

  @override
  Future<void> testConnection() async => _unimplemented();
}
