import 'dart:async';
import 'dart:io';

import 'logging_service.dart';

/// Snapshot of disk-space usage for a single directory.
///
/// All sizes are in bytes. [path] is the directory that was queried; on
/// Windows this is the drive root (e.g. `C:\`) the path lives on, because
/// `Get-PSDrive` reports per-volume free space. On Unix the path is whatever
/// `df` resolved to (typically the mount-point of the filesystem holding the
/// directory).
class DiskSpaceInfo {
  final String path;
  final int totalBytes;
  final int freeBytes;
  final DateTime sampledAt;

  const DiskSpaceInfo({
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    required this.sampledAt,
  });

  int get usedBytes => totalBytes - freeBytes;

  double get freeFraction =>
      totalBytes > 0 ? freeBytes / totalBytes : 0.0;

  @override
  String toString() =>
      'DiskSpaceInfo(path=$path, free=${freeBytes ~/ (1024 * 1024)}MB, total=${totalBytes ~/ (1024 * 1024)}MB)';
}

/// Thrown when the disk-space query fails. We do NOT silently substitute
/// fallback values — capture sessions depend on this number being accurate,
/// and a silent fallback would hide misconfiguration (e.g. capture path on a
/// missing/disconnected drive). Errors are a feature: surface them.
class DiskSpaceException implements Exception {
  final String path;
  final String message;
  final Object? cause;

  const DiskSpaceException(this.path, this.message, [this.cause]);

  @override
  String toString() =>
      'DiskSpaceException: $message (path=$path${cause != null ? ", cause=$cause" : ""})';
}

/// Queries free / total disk space for a directory.
///
/// Pure Dart, no platform plugin. Shells out to OS utilities:
/// - Windows: `powershell -Command "(Get-PSDrive <letter>) | ..."`. We chose
///   `Get-PSDrive` over `wmic` because `wmic` is deprecated since Windows 11
///   and missing on newer Server SKUs.
/// - macOS/Linux: `df -Pk` (POSIX, 1024-byte blocks).
abstract class DiskSpaceService {
  Future<DiskSpaceInfo> query(String path);
}

/// Default implementation that shells out to the host OS.
///
/// Failure modes that propagate as [DiskSpaceException]:
/// - path is empty
/// - path does not exist
/// - subprocess exits non-zero
/// - subprocess output cannot be parsed
class HostDiskSpaceService implements DiskSpaceService {
  final LoggingService? _logger;

  HostDiskSpaceService({LoggingService? logger}) : _logger = logger;

  @override
  Future<DiskSpaceInfo> query(String path) async {
    if (path.isEmpty) {
      throw const DiskSpaceException(
        '',
        'Cannot query disk space: path is empty (capture directory not configured)',
      );
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      throw DiskSpaceException(
        path,
        'Path does not exist; cannot query free space',
      );
    }

    try {
      if (Platform.isWindows) {
        return await _queryWindows(path);
      }
      // macOS / Linux share the POSIX `df` invocation.
      return await _queryPosix(path);
    } on DiskSpaceException {
      rethrow;
    } catch (e, stack) {
      _logger?.warning(
        'Disk-space query failed for "$path": $e\n$stack',
        source: 'DiskSpaceService',
      );
      throw DiskSpaceException(path, 'Disk-space query failed', e);
    }
  }

  /// Windows uses PowerShell `Get-PSDrive` which reports both free and used
  /// space per drive letter. We resolve the drive letter from the supplied
  /// path, e.g. `D:\images\session1` -> drive `D`.
  Future<DiskSpaceInfo> _queryWindows(String path) async {
    // Resolve the absolute path so a relative input still works. Then extract
    // the drive letter (Windows paths always start with `<letter>:`).
    final absolute = Directory(path).absolute.path;
    if (absolute.length < 2 || absolute[1] != ':') {
      throw DiskSpaceException(
        path,
        'Could not determine drive letter from path "$absolute"',
      );
    }
    final driveLetter = absolute[0].toUpperCase();

    // Get-PSDrive returns Used + Free in bytes. We script it explicitly to a
    // simple `Free<TAB>Used` line so parsing is robust against locale-dependent
    // table formatting (German Windows etc.).
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        // Trailing newline avoided; use Out-String -NoNewline isn't 5.1-safe.
        '\$d = Get-PSDrive -Name $driveLetter -ErrorAction Stop; '
            'Write-Output ("\$(\$d.Free)`t\$(\$d.Used)")',
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      throw DiskSpaceException(
        path,
        'powershell Get-PSDrive failed (exit=${result.exitCode}): ${result.stderr}',
      );
    }

    final line = (result.stdout as String).trim();
    final parts = line.split('\t');
    if (parts.length != 2) {
      throw DiskSpaceException(
        path,
        'Unexpected Get-PSDrive output: "$line"',
      );
    }
    final free = int.tryParse(parts[0].trim());
    final used = int.tryParse(parts[1].trim());
    if (free == null || used == null) {
      throw DiskSpaceException(
        path,
        'Could not parse free/used bytes from "$line"',
      );
    }
    return DiskSpaceInfo(
      path: '$driveLetter:\\',
      totalBytes: free + used,
      freeBytes: free,
      sampledAt: DateTime.now(),
    );
  }

  /// POSIX uses `df -Pk` (POSIX mode, 1k-blocks). Output is two-line:
  ///   Filesystem 1024-blocks Used Available Capacity Mounted on
  ///   /dev/disk1s1 488245288 123456 365432 26% /
  /// We parse line 2.
  Future<DiskSpaceInfo> _queryPosix(String path) async {
    final result = await Process.run(
      'df',
      ['-Pk', path],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      throw DiskSpaceException(
        path,
        'df failed (exit=${result.exitCode}): ${result.stderr}',
      );
    }

    final lines = (result.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw DiskSpaceException(
        path,
        'df returned no data rows: "${result.stdout}"',
      );
    }

    // Filesystem names with spaces (rare but possible on bind mounts) push the
    // numeric columns rightward. We split on whitespace and read the LAST six
    // tokens — these are always the numeric block + mount point regardless of
    // the leading filesystem name.
    final tokens = lines[1].split(RegExp(r'\s+'));
    if (tokens.length < 6) {
      throw DiskSpaceException(
        path,
        'df row has too few columns: "${lines[1]}"',
      );
    }
    // Last 5 numeric columns + mount point: [..., 1k-blocks, used, available, capacity, mount]
    // Indices from the right:           -5         -4    -3        -2        -1
    final totalKb = int.tryParse(tokens[tokens.length - 5]);
    final availKb = int.tryParse(tokens[tokens.length - 3]);
    final mount = tokens[tokens.length - 1];
    if (totalKb == null || availKb == null) {
      throw DiskSpaceException(
        path,
        'Could not parse df numeric columns from "${lines[1]}"',
      );
    }
    return DiskSpaceInfo(
      path: mount,
      totalBytes: totalKb * 1024,
      freeBytes: availKb * 1024,
      sampledAt: DateTime.now(),
    );
  }
}
