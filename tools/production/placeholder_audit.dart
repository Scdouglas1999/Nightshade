import 'dart:convert';
import 'dart:io';

const _scanRoots = <String>['apps', 'packages', 'native/nightshade_native'];
const _defaultHitsPath = '.audit_hits.txt';
const _defaultHighRiskPath = '.audit_highrisk.txt';
const _defaultAllowlistPath =
    'docs/production-readiness/placeholder-allowlist.txt';

const _allowedExtensions = <String>{
  '.dart',
  '.rs',
  '.swift',
  '.kt',
  '.kts',
  '.java',
  '.m',
  '.mm',
  '.c',
  '.cc',
  '.cpp',
  '.h',
  '.hpp',
  '.cs',
  '.js',
  '.ts',
  '.sh',
  '.ps1',
  '.toml',
  '.yaml',
  '.yml',
};

const _excludedSegments = <String>[
  '/.dart_tool/',
  '/.git/',
  '/.worktrees/',
  '/build/',
  '/target/',
  '/coverage/',
  '/generated/',
  '/frb_dump/',
  '/frb_generated.',
  '/test/',
  '/tests/',
  '/example/',
  '/samples/',
];

final _runtimePathPatterns = <RegExp>[
  RegExp(r'^apps/[^/]+/lib/'),
  RegExp(r'^packages/[^/]+/lib/'),
  RegExp(r'^native/nightshade_native(?:/[^/]+)+/src/'),
];

final _markerPattern = RegExp(
  r'\bTODO\b|\bFIXME\b|placeholder|\bstub\b|'
  r'UnimplementedError|not implemented|for now|no-?op',
  caseSensitive: false,
);

final _highRiskPattern = RegExp(
  r'UnimplementedError|not implemented|'
  r'placeholder\s*-\s*to be implemented|'
  r'for now\s+return|for now,\s*return|for now\s+we\s+\w+\s+support|'
  r'no-?op in stub mode|silent no-?op|would be\b.+stub mode|'
  r'simulator implementation for now',
  caseSensitive: false,
);

void main(List<String> args) {
  final hitsPath = _argValue(args, '--out-hits') ?? _defaultHitsPath;
  final highRiskPath =
      _argValue(args, '--out-highrisk') ?? _defaultHighRiskPath;
  final compareBaseline = _argValue(args, '--compare-highrisk-baseline');
  final allowlistPath = _argValue(args, '--allowlist') ?? _defaultAllowlistPath;
  final failOnNewHighRisk = args.contains('--fail-on-new-highrisk');
  final failOnAnyHighRisk = args.contains('--fail-on-any-highrisk');

  final allowlist = _loadAllowlist(allowlistPath);
  final hits = <String>{};
  final highRisk = <String>{};
  final workspaceRoot = _normalize(Directory.current.absolute.path);

  for (final root in _scanRoots) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) {
      continue;
    }

    for (final entity
        in rootDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final normalizedPath = _toWorkspaceRelative(entity.path, workspaceRoot);
      if (!_isRuntimePath(normalizedPath) || _shouldSkip(normalizedPath)) {
        continue;
      }
      if (!_hasAllowedExtension(normalizedPath)) {
        continue;
      }

      final stat = entity.statSync();
      if (stat.size > 2 * 1024 * 1024) {
        continue;
      }

      final lines = _readLinesSafe(entity);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!_markerPattern.hasMatch(line)) {
          continue;
        }

        final trimmed = line.trimRight();
        final entry = '$normalizedPath:${i + 1}:$trimmed';
        if (_isAllowlisted(entry, allowlist)) {
          continue;
        }

        hits.add(entry);
        if (_highRiskPattern.hasMatch(line)) {
          highRisk.add(entry);
        }
      }
    }
  }

  final sortedHits = hits.toList()..sort();
  final sortedHighRisk = highRisk.toList()..sort();

  _writeTextFile(hitsPath, '${sortedHits.join('\n')}\n');
  _writeTextFile(highRiskPath, '${sortedHighRisk.join('\n')}\n');

  stdout.writeln('Runtime marker audit complete.');
  stdout.writeln('Hits: ${sortedHits.length} -> $hitsPath');
  stdout.writeln('High-risk hits: ${sortedHighRisk.length} -> $highRiskPath');

  if (failOnAnyHighRisk && sortedHighRisk.isNotEmpty) {
    stderr.writeln('High-risk runtime markers detected.');
    exit(1);
  }

  if (compareBaseline == null) {
    return;
  }

  final baselineFile = File(compareBaseline);
  if (!baselineFile.existsSync()) {
    stderr.writeln('Baseline not found: $compareBaseline');
    exit(2);
  }

  final baseline = baselineFile
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet();

  final newHighRisk =
      sortedHighRisk.where((entry) => !baseline.contains(entry)).toList();
  if (newHighRisk.isEmpty) {
    stdout.writeln('No new high-risk markers compared to baseline.');
    return;
  }

  stderr.writeln('Detected ${newHighRisk.length} new high-risk markers:');
  for (final entry in newHighRisk) {
    stderr.writeln('  $entry');
  }

  if (failOnNewHighRisk) {
    exit(1);
  }
}

String? _argValue(List<String> args, String key) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == key && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  return null;
}

void _writeTextFile(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Set<String> _loadAllowlist(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return <String>{};
  }

  return file
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(_normalize)
      .toSet();
}

bool _isAllowlisted(String entry, Set<String> allowlist) {
  final normalizedEntry = _normalize(entry);
  if (allowlist.contains(normalizedEntry)) {
    return true;
  }

  final pathLine = normalizedEntry.split(':').take(2).join(':');
  if (allowlist.contains(pathLine)) {
    return true;
  }

  final pathOnly = normalizedEntry.split(':').first;
  if (allowlist.contains(pathOnly)) {
    return true;
  }

  return false;
}

bool _hasAllowedExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  final ext = path.substring(dot).toLowerCase();
  return _allowedExtensions.contains(ext);
}

bool _isRuntimePath(String path) {
  for (final pattern in _runtimePathPatterns) {
    if (pattern.hasMatch(path)) {
      return true;
    }
  }
  return false;
}

bool _shouldSkip(String normalizedPath) {
  for (final segment in _excludedSegments) {
    if (normalizedPath.contains(segment)) {
      return true;
    }
  }
  return false;
}

List<String> _readLinesSafe(File file) {
  try {
    return const LineSplitter().convert(file.readAsStringSync());
  } catch (_) {
    try {
      final bytes = file.readAsBytesSync();
      return const LineSplitter()
          .convert(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return const <String>[];
    }
  }
}

String _normalize(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');

String _toWorkspaceRelative(String path, String workspaceRoot) {
  final absolute = _normalize(File(path).absolute.path);
  final lowerAbsolute = absolute.toLowerCase();
  final lowerRoot = workspaceRoot.toLowerCase();
  if (lowerAbsolute.startsWith(lowerRoot)) {
    final start = workspaceRoot.endsWith('/')
        ? workspaceRoot.length
        : workspaceRoot.length + 1;
    if (absolute.length >= start) {
      return absolute.substring(start);
    }
  }
  return _normalize(path);
}
