import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class UnsafeArchiveEntryException implements Exception {
  UnsafeArchiveEntryException(this.entryName, this.reason);

  final String entryName;
  final String reason;

  @override
  String toString() => 'Unsafe archive entry "$entryName": $reason';
}

Future<void> extractZipSafely(File zipFile, Directory destination) async {
  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  await extractArchiveSafely(archive, destination);
}

Future<void> extractArchiveSafely(
    Archive archive, Directory destination) async {
  await destination.create(recursive: true);
  final destinationRoot = await destination.resolveSymbolicLinks();

  for (final entry in archive) {
    final relativePath = _safeArchiveEntryPath(entry.name);
    final outputPath = path.joinAll([
      destinationRoot,
      ...relativePath.split('/'),
    ]);

    if (entry.isFile) {
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await _assertInsideDestination(destinationRoot, outputFile.parent);
      if (await outputFile.exists()) {
        await _assertInsideDestination(destinationRoot, outputFile);
      }
      await outputFile.writeAsBytes(entry.content as List<int>);
    } else {
      final outputDirectory = Directory(outputPath);
      await outputDirectory.create(recursive: true);
      await _assertInsideDestination(destinationRoot, outputDirectory);
    }
  }
}

String _safeArchiveEntryPath(String entryName) {
  final portableName = entryName.replaceAll('\\', '/');
  if (portableName.isEmpty) {
    throw UnsafeArchiveEntryException(entryName, 'empty path');
  }
  if (path.posix.isAbsolute(portableName) ||
      RegExp(r'^[a-zA-Z]:/').hasMatch(portableName) ||
      portableName.startsWith('//')) {
    throw UnsafeArchiveEntryException(entryName, 'absolute path');
  }

  final normalized = path.posix.normalize(portableName);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.contains('/../')) {
    throw UnsafeArchiveEntryException(entryName, 'path traversal');
  }
  if (normalized.split('/').any((part) => part.isEmpty || part == '.')) {
    throw UnsafeArchiveEntryException(entryName, 'invalid path component');
  }

  return normalized;
}

Future<void> _assertInsideDestination(
  String destinationRoot,
  FileSystemEntity entity,
) async {
  final resolvedPath = await entity.resolveSymbolicLinks();
  if (!_isWithinDirectory(destinationRoot, resolvedPath)) {
    throw UnsafeArchiveEntryException(
      entity.path,
      'resolved outside extraction directory',
    );
  }
}

bool _isWithinDirectory(String root, String candidate) {
  final normalizedRoot = _normalizeForComparison(path.normalize(root));
  final normalizedCandidate =
      _normalizeForComparison(path.normalize(candidate));
  if (normalizedCandidate == normalizedRoot) {
    return true;
  }

  final rootWithSeparator = normalizedRoot.endsWith(path.separator)
      ? normalizedRoot
      : '$normalizedRoot${path.separator}';
  return normalizedCandidate.startsWith(rootWithSeparator);
}

String _normalizeForComparison(String value) {
  return Platform.isWindows ? value.toLowerCase() : value;
}
