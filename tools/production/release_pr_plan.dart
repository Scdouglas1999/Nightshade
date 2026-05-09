import 'dart:convert';
import 'dart:io';

const _stagingAuditPath = 'docs/production-readiness/release-staging-audit.json';
const _jsonOutputPath = 'docs/production-readiness/release-pr-plan.json';
const _markdownOutputPath = 'docs/production-readiness/release-pr-plan.md';

const _bucketOrder = [
  'release-tooling-and-evidence',
  'headless-remote-api',
  'mobile-remote-client',
  'native-and-generated-bindings',
  'core-database-and-services',
  'app-ui-and-workflows',
  'docs',
  'tests',
  'defer-or-exclude',
];

const _categoryToBucket = {
  'release-tooling': 'release-tooling-and-evidence',
  'release-evidence-docs': 'release-tooling-and-evidence',
  'release-evidence-binary': 'release-tooling-and-evidence',
  'headless-remote': 'headless-remote-api',
  'mobile': 'mobile-remote-client',
  'native-rust': 'native-and-generated-bindings',
  'bridge': 'native-and-generated-bindings',
  'generated': 'native-and-generated-bindings',
  'core': 'core-database-and-services',
  'app-ui': 'app-ui-and-workflows',
  'ui-system': 'app-ui-and-workflows',
  'planetarium': 'app-ui-and-workflows',
  'plugins': 'app-ui-and-workflows',
  'updater': 'app-ui-and-workflows',
  'webrtc': 'app-ui-and-workflows',
  'docs': 'docs',
  'tests': 'tests',
  'package-config': 'release-tooling-and-evidence',
  'tooling': 'release-tooling-and-evidence',
  'binary-native-artifact': 'defer-or-exclude',
  'other': 'defer-or-exclude',
};

const _bucketDescriptions = {
  'release-tooling-and-evidence':
      'Production audit/smoke tools, Melos wiring, and release-readiness evidence artifacts.',
  'headless-remote-api':
      'Headless API server, route metadata, auth policy, dashboard assets, and remote API handlers.',
  'mobile-remote-client':
      'Android/mobile client changes that support authenticated headless remote access.',
  'native-and-generated-bindings':
      'Rust/native bridge changes and generated binding/database outputs that should be reviewed separately from authored Dart/UI changes.',
  'core-database-and-services':
      'Core package providers, services, database model changes, and shared backend behavior.',
  'app-ui-and-workflows':
      'Desktop/app UI, workflow screens, design system, planetarium, plugins, updater, and WebRTC UI-facing changes.',
  'docs': 'User-facing docs outside production-readiness evidence.',
  'tests': 'Automated tests and test fixtures.',
  'defer-or-exclude':
      'Local reports, screenshots, binaries, scratch files, and other artifacts that need an explicit include/exclude decision.',
};

void main() async {
  final auditFile = File(_stagingAuditPath);
  if (!auditFile.existsSync()) {
    stderr.writeln('Missing staging audit: $_stagingAuditPath');
    exit(2);
  }

  final audit = jsonDecode(await auditFile.readAsString()) as Map<String, dynamic>;
  final categories = audit['categories'] as Map<String, dynamic>? ?? const {};
  final buckets = {
    for (final bucket in _bucketOrder) bucket: <_PlannedEntry>[],
  };

  for (final categoryEntry in categories.entries) {
    final category = categoryEntry.key;
    final bucket = _categoryToBucket[category] ?? 'defer-or-exclude';
    final categoryData = categoryEntry.value as Map<String, dynamic>;
    final paths = categoryData['paths'] as List? ?? const [];
    for (final item in paths.whereType<Map>()) {
      buckets[bucket]!.add(_PlannedEntry.fromJson(
        category: category,
        json: item.cast<String, dynamic>(),
      ));
    }
  }

  for (final entries in buckets.values) {
    entries.sort((a, b) => a.path.compareTo(b.path));
  }

  final summary = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceAudit': _stagingAuditPath,
    'sourceBranch': audit['currentBranch'],
    'sourceHead': audit['head'],
    'sourceEntryCount': audit['entryCount'],
    'sourceUntrackedReleaseCriticalCount':
        audit['untrackedReleaseCriticalCount'],
    'recommendedSequence': _bucketOrder,
    'buckets': {
      for (final bucket in _bucketOrder)
        bucket: {
          'description': _bucketDescriptions[bucket],
          'count': buckets[bucket]!.length,
          'untrackedCount':
              buckets[bucket]!.where((entry) => entry.untracked).length,
          'binaryCount': buckets[bucket]!.where((entry) => entry.binary).length,
          'generatedCount':
              buckets[bucket]!.where((entry) => entry.generated).length,
          'releaseCriticalCount':
              buckets[bucket]!.where((entry) => entry.releaseCritical).length,
          'paths': buckets[bucket]!.map((entry) => entry.toJson()).toList(),
        },
    },
    'notReadyReason':
        'This is a PR planning artifact only. It does not create a clean release branch, stage files, or open a PR.',
  };

  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(
    audit: audit,
    buckets: buckets,
  ));

  stdout.writeln('Release PR plan complete.');
  stdout.writeln('Source entries: ${audit['entryCount']}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');
}

String _renderMarkdown({
  required Map<String, dynamic> audit,
  required Map<String, List<_PlannedEntry>> buckets,
}) {
  final buffer = StringBuffer()
    ..writeln('# Release PR Plan')
    ..writeln()
    ..writeln('- Source audit: `$_stagingAuditPath`')
    ..writeln('- Source branch: `${audit['currentBranch']}`')
    ..writeln('- Source HEAD: `${audit['head']}`')
    ..writeln('- Source changed/untracked entries: `${audit['entryCount']}`')
    ..writeln(
      '- Source untracked release-critical entries: `${audit['untrackedReleaseCriticalCount']}`',
    )
    ..writeln()
    ..writeln(
      'This is a planning artifact only. It does not create a clean release branch, stage files, commit, push, or open a PR.',
    )
    ..writeln()
    ..writeln('## Recommended Review Sequence')
    ..writeln()
    ..writeln('| Bucket | Count | Untracked | Binary | Generated | Release-Critical |')
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');

  for (final bucket in _bucketOrder) {
    final entries = buckets[bucket]!;
    buffer.writeln(
      '| $bucket | ${entries.length} | '
      '${entries.where((entry) => entry.untracked).length} | '
      '${entries.where((entry) => entry.binary).length} | '
      '${entries.where((entry) => entry.generated).length} | '
      '${entries.where((entry) => entry.releaseCritical).length} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Review Rules')
    ..writeln()
    ..writeln(
      '- Start from a clean branch before staging anything for public release.',
    )
    ..writeln(
      '- Keep generated and binary/native artifacts out of the first human-authored code review where possible.',
    )
    ..writeln(
      '- Include release evidence artifacts only if they are intended public-release records.',
    )
    ..writeln(
      '- Exclude local scratch reports, firmware research files, and unrelated screenshots unless explicitly approved.',
    )
    ..writeln(
      '- Rerun `audit:public-release-gate` after each staged PR bucket.',
    );

  for (final bucket in _bucketOrder) {
    final entries = buckets[bucket]!;
    buffer
      ..writeln()
      ..writeln('## $bucket')
      ..writeln()
      ..writeln(_bucketDescriptions[bucket])
      ..writeln();

    if (entries.isEmpty) {
      buffer.writeln('No entries.');
      continue;
    }

    for (final entry in entries.take(120)) {
      buffer.writeln(
        '- `${entry.status}` `${entry.path}` (${entry.category})',
      );
    }
    if (entries.length > 120) {
      buffer.writeln('- ... ${entries.length - 120} more entries omitted.');
    }
  }

  return buffer.toString();
}

class _PlannedEntry {
  final String category;
  final String status;
  final String path;
  final bool untracked;
  final bool deleted;
  final bool generated;
  final bool binary;
  final bool releaseCritical;

  const _PlannedEntry({
    required this.category,
    required this.status,
    required this.path,
    required this.untracked,
    required this.deleted,
    required this.generated,
    required this.binary,
    required this.releaseCritical,
  });

  factory _PlannedEntry.fromJson({
    required String category,
    required Map<String, dynamic> json,
  }) {
    return _PlannedEntry(
      category: category,
      status: json['status']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      untracked: json['untracked'] == true,
      deleted: json['deleted'] == true,
      generated: json['generated'] == true,
      binary: json['binary'] == true,
      releaseCritical: json['releaseCritical'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'category': category,
        'status': status,
        'path': path,
        'untracked': untracked,
        'deleted': deleted,
        'generated': generated,
        'binary': binary,
        'releaseCritical': releaseCritical,
      };
}
