import 'dart:convert';
import 'dart:io';

const _defaultJsonOutputPath =
    'docs/production-readiness/migration-regression-audit.json';
const _defaultMarkdownOutputPath =
    'docs/production-readiness/migration-regression-audit.md';

const _fixturePath =
    'packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart';
const _testPath =
    'packages/nightshade_core/test/services/database_migration_test.dart';
const _manualProbePath =
    'packages/nightshade_core/tool/production_migration_probe.dart';

const _requiredFixtureText = [
  'schema17WithCapturedImageMetadata',
  'schema20WithDuplicateActiveProfiles',
  'schema20WithDuplicateScienceSessionConfigs',
  'schema20WithDuplicateWeatherSettings',
  'PRAGMA user_version = 17',
  'DROP INDEX IF EXISTS idx_profiles_single_active',
  'DROP INDEX IF EXISTS idx_science_session_config_session_unique',
  'PRAGMA user_version = 20',
  'legacy FITS metadata',
  'Legacy Widefield',
  'Legacy Observatory',
  'is_active',
  'telescope_focal_length',
  'telescope_aperture',
  'science_session_config',
  'weather_settings',
  'legacy_primary',
  'legacy_duplicate',
];

const _requiredTestText = [
  'synthetic schema 17 image fixture preserves metadata cascade',
  'SyntheticOldProfileFixture.schema17WithCapturedImageMetadata',
  'Migration v18 should restore image metadata cascade delete',
  'Upgraded legacy image metadata should cascade on image delete',
  'synthetic schema 20 profile fixture normalizes active and optics',
  'SyntheticOldProfileFixture.schema20WithDuplicateActiveProfiles',
  'equals(db.schemaVersion)',
  'Migration v21 should keep only the newest active profile',
  'idx_profiles_single_active',
  'Upgraded legacy databases should reject another active',
  'telescopeFocalLength',
  'telescopeAperture',
  'focalLength',
  'aperture',
  'synthetic schema 20 science fixture deduplicates session configs',
  '.schema20WithDuplicateScienceSessionConfigs',
  'Migration v21 should dedupe science session configs',
  'idx_science_session_config_session_unique',
  'Upgraded legacy databases should reject another config',
  'synthetic schema 20 weather fixture deduplicates singleton settings',
  '.schema20WithDuplicateWeatherSettings',
  'primary singleton row on first settings access',
  'weatherSettingsDao.getOrCreateSettings',
  'legacy_primary',
  'schema 12 database upgrades to the complete current table set',
  'fresh and upgraded databases converge on the same default settings',
];

const _requiredManualProbeText = [
  'NIGHTSHADE_OLD_DATABASE',
  'sourceSizeBytes',
  'sourceSha256',
  'copiedSourceSha256',
  'copiedSourceSha256Matches',
  'expectedTableCount',
  'migratedTableCount',
  'defaultSettingCount',
  'Manual older-profile migration evidence probe. Synthetic migration tests remain separate.',
];

Future<void> main(List<String> args) async {
  final root = Directory(_argValue(args, '--root') ?? Directory.current.path);
  final jsonOut = _argValue(args, '--json-out') ?? _defaultJsonOutputPath;
  final markdownOut = _argValue(args, '--md-out') ?? _defaultMarkdownOutputPath;
  final failOnIssue = !args.contains('--no-fail-on-issue');

  final fixture = _auditFile(
    root: root,
    path: _fixturePath,
    requiredText: _requiredFixtureText,
  );
  final tests = _auditFile(
    root: root,
    path: _testPath,
    requiredText: _requiredTestText,
  );
  final manualProbe = _auditFile(
    root: root,
    path: _manualProbePath,
    requiredText: _requiredManualProbeText,
  );
  final issues = [
    ...fixture.issues,
    ...tests.issues,
    ...manualProbe.issues,
  ];
  final passed = issues.isEmpty;
  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'passed': passed,
    'issueCount': issues.length,
    'issues': issues,
    'fixture': fixture.toJson(),
    'tests': tests.toJson(),
    'manualProbe': manualProbe.toJson(),
    'manualRealArtifactGatePreserved': manualProbe.passed,
    'focusedTestCommand':
        'cd packages/nightshade_core && flutter test test/services/database_migration_test.dart',
    'policy':
        'Synthetic migration fixtures reduce upgrade risk without using real user data. They do not satisfy the release blocker for an older real Nightshade profile/database artifact.',
  };

  await File(jsonOut).parent.create(recursive: true);
  await File(jsonOut).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  await File(markdownOut).parent.create(recursive: true);
  await File(markdownOut).writeAsString(_renderMarkdown(
    passed: passed,
    issues: issues,
    fixture: fixture,
    tests: tests,
    manualProbe: manualProbe,
  ));

  stdout.writeln('Migration regression audit complete.');
  stdout.writeln('Passed: $passed');
  stdout.writeln('Issues: ${issues.length}');
  stdout.writeln('JSON: $jsonOut');
  stdout.writeln('Markdown: $markdownOut');

  if (failOnIssue && !passed) {
    exit(1);
  }
}

_FileAudit _auditFile({
  required Directory root,
  required String path,
  required List<String> requiredText,
}) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    return _FileAudit(
      path: path,
      exists: false,
      sizeBytes: 0,
      missingText: requiredText,
    );
  }
  final text = file.readAsStringSync();
  return _FileAudit(
    path: path,
    exists: true,
    sizeBytes: file.lengthSync(),
    missingText: [
      for (final required in requiredText)
        if (!text.contains(required)) required,
    ],
  );
}

String _renderMarkdown({
  required bool passed,
  required List<String> issues,
  required _FileAudit fixture,
  required _FileAudit tests,
  required _FileAudit manualProbe,
}) {
  final buffer = StringBuffer()
    ..writeln('# Migration Regression Audit')
    ..writeln()
    ..writeln('- Passed: `$passed`')
    ..writeln('- Issues: `${issues.length}`')
    ..writeln()
    ..writeln(
      'This audit verifies synthetic old-schema/profile migration coverage and confirms the separate real older-profile migration gate remains documented. It does not replace the required real artifact probe.',
    )
    ..writeln()
    ..writeln('## Required Files')
    ..writeln()
    ..writeln('| File | Exists | Missing required text |')
    ..writeln('| --- | --- | ---: |')
    ..writeln(
      '| `${fixture.path}` | `${fixture.exists}` | `${fixture.missingText.length}` |',
    )
    ..writeln(
      '| `${tests.path}` | `${tests.exists}` | `${tests.missingText.length}` |',
    )
    ..writeln(
      '| `${manualProbe.path}` | `${manualProbe.exists}` | `${manualProbe.missingText.length}` |',
    )
    ..writeln()
    ..writeln('## Focused Verification')
    ..writeln()
    ..writeln(
      '`cd packages/nightshade_core && flutter test test/services/database_migration_test.dart`',
    );

  if (issues.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Issues')
      ..writeln();
    for (final issue in issues) {
      buffer.writeln('- $issue');
    }
  }

  return buffer.toString();
}

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

class _FileAudit {
  final String path;
  final bool exists;
  final int sizeBytes;
  final List<String> missingText;

  const _FileAudit({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    required this.missingText,
  });

  bool get passed => exists && missingText.isEmpty;

  List<String> get issues {
    if (!exists) {
      return ['Missing required file: $path'];
    }
    return [
      for (final text in missingText) '$path is missing required text: `$text`',
    ];
  }

  Map<String, Object?> toJson() => {
        'path': path,
        'exists': exists,
        'sizeBytes': sizeBytes,
        'missingText': missingText,
        'missingTextCount': missingText.length,
        'passed': passed,
      };
}
