import 'dart:convert';
import 'dart:io';

const _defaultMatrixPath =
    'docs/production-readiness/release-pr-owner-decision-matrix.json';
const _jsonOutputPath =
    'docs/production-readiness/release-pr-staged-branch-validation.json';
const _markdownOutputPath =
    'docs/production-readiness/release-pr-staged-branch-validation.md';
const _decisionGroupOrder = [
  'must_ship',
  'generated_only',
  'binary_evidence',
  'defer_exclude',
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final matrixFile = File(options.matrixPath);
  if (!matrixFile.existsSync()) {
    stderr.writeln('Missing release PR owner matrix: ${options.matrixPath}');
    stderr.writeln(
      'Run: dart run melos run audit:release-pr-owner-matrix --no-select',
    );
    exit(1);
  }

  final matrix =
      jsonDecode(matrixFile.readAsStringSync()) as Map<String, dynamic>;
  final groups = _readGroups(matrix);
  final matrixIntegrity = _checkMatrixIntegrity(matrix: matrix, groups: groups);
  final observedPaths = await _readObservedPaths(options);
  final result = _validate(
    groups: groups,
    observedPaths: observedPaths,
    allowNewPaths: options.allowNewPaths,
  );
  final issues = [...matrixIntegrity.issues, ...result.issues];
  final warnings = [...matrixIntegrity.warnings, ...result.warnings];
  final nextStageCommands = _buildNextStageCommands(
    groups: groups,
    groupCoverage: result.groupCoverage,
  );

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'matrixPath': options.matrixPath,
    'matrixGeneratedAt': matrix['generatedAt'],
    'matrixIntegrity': matrixIntegrity.toJson(),
    'mode': options.mode.reportName,
    'base': options.base,
    'passed': issues.isEmpty,
    'observedPathCount': observedPaths.length,
    'issueCount': issues.length,
    'warningCount': warnings.length,
    'issues': issues,
    'warnings': warnings,
    'decisionGroupCoverage': [
      for (final coverage in result.groupCoverage) coverage.toJson(),
    ],
    'nextStageCommands': [
      for (final commandGroup in nextStageCommands) commandGroup.toJson(),
    ],
    'observedPaths': observedPaths.toList()..sort(),
  };

  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(report));

  stdout.writeln('Release PR staged branch validation complete.');
  stdout.writeln('Mode: ${options.mode.reportName}');
  if (options.mode == _ValidationMode.branch) {
    stdout.writeln('Base: ${options.base}');
  }
  stdout.writeln('Observed paths: ${observedPaths.length}');
  stdout.writeln('Issues: ${issues.length}');
  stdout.writeln('Warnings: ${warnings.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');

  if (issues.isNotEmpty) {
    exit(1);
  }
}

Map<String, _DecisionGroup> _readGroups(Map<String, dynamic> matrix) {
  final rawGroups =
      matrix['decisionGroups'] as Map<String, dynamic>? ?? const {};
  return {
    for (final entry in rawGroups.entries)
      entry.key: _DecisionGroup.fromJson(entry.value as Map<String, dynamic>),
  };
}

_MatrixIntegrity _checkMatrixIntegrity({
  required Map<String, dynamic> matrix,
  required Map<String, _DecisionGroup> groups,
}) {
  final issues = <String>[];
  final warnings = <String>[];
  final pathspecFindings = <_PathspecIntegrity>[];
  final expectedPathsByPathspec = <String, Set<String>>{};

  final sourceSplitPlan = matrix['sourceSplitPlan']?.toString();
  var sourceSplitPlanExists = false;
  var sourceSplitPlanMatches = false;
  if (sourceSplitPlan == null || sourceSplitPlan.isEmpty) {
    issues.add('Decision matrix is missing sourceSplitPlan.');
  } else {
    final sourceFile = File(sourceSplitPlan);
    sourceSplitPlanExists = sourceFile.existsSync();
    if (!sourceSplitPlanExists) {
      issues.add(
          'Decision matrix source split plan is missing: $sourceSplitPlan');
    } else {
      final splitPlan =
          jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;
      for (final rawBucket in splitPlan['buckets'] as List? ?? const []) {
        if (rawBucket is! Map) continue;
        final bucket = rawBucket.cast<String, dynamic>();
        final bucketId = bucket['id']?.toString() ?? 'unknown';
        final pathspec = bucket['pathspecFile']?.toString().replaceAll(
              '\\',
              '/',
            );
        final rawPaths = bucket['paths'] as List? ?? const [];
        final bucketEntries = [
          for (final rawPath in rawPaths)
            if (rawPath is Map) rawPath.cast<String, dynamic>(),
        ];
        final generatedOnlyViolations = <String>{};
        final binaryEvidenceViolations = <String>{};
        for (final entry in bucketEntries) {
          final path = (entry['path']?.toString() ?? '').replaceAll('\\', '/');
          if (path.isEmpty) continue;
          if (bucketId == 'generated-files' && entry['generated'] != true) {
            generatedOnlyViolations.add(path);
          }
          if (bucketId == 'binary-and-evidence-artifacts' &&
              entry['binary'] != true) {
            binaryEvidenceViolations.add(path);
          }
        }
        if (generatedOnlyViolations.isNotEmpty) {
          issues.add(
            'Generated-only bucket contains non-generated paths: ${_formatPaths(generatedOnlyViolations)}',
          );
        }
        if (binaryEvidenceViolations.isNotEmpty) {
          issues.add(
            'Binary/evidence bucket contains non-binary evidence paths: ${_formatPaths(binaryEvidenceViolations)}',
          );
        }
        if (pathspec == null || pathspec.isEmpty) continue;
        expectedPathsByPathspec[pathspec] = {
          for (final entry in bucketEntries)
            (entry['path']?.toString() ?? '').replaceAll('\\', '/'),
        }..remove('');
      }
      final splitGeneratedAt = splitPlan['generatedAt']?.toString();
      final matrixSourceGeneratedAt = matrix['sourceGeneratedAt']?.toString();
      final splitSourceGeneratedAt = splitPlan['sourceGeneratedAt']?.toString();
      final matrixSourceStagingGeneratedAt =
          matrix['sourceStagingGeneratedAt']?.toString();
      final splitEntryCount = (splitPlan['entryCount'] as num?)?.toInt();
      final matrixEntryCount = (matrix['entryCount'] as num?)?.toInt();
      final splitBucketCount = (splitPlan['bucketCount'] as num?)?.toInt();
      final matrixBucketCount = (matrix['bucketCount'] as num?)?.toInt();

      sourceSplitPlanMatches = splitGeneratedAt == matrixSourceGeneratedAt &&
          splitSourceGeneratedAt == matrixSourceStagingGeneratedAt &&
          splitEntryCount == matrixEntryCount &&
          splitBucketCount == matrixBucketCount;
      if (splitGeneratedAt != matrixSourceGeneratedAt) {
        issues.add(
          'Decision matrix is stale: sourceGeneratedAt=$matrixSourceGeneratedAt but split plan generatedAt=$splitGeneratedAt.',
        );
      }
      if (splitSourceGeneratedAt != matrixSourceStagingGeneratedAt) {
        issues.add(
          'Decision matrix staging source is stale: sourceStagingGeneratedAt=$matrixSourceStagingGeneratedAt but split plan sourceGeneratedAt=$splitSourceGeneratedAt.',
        );
      }
      if (splitEntryCount != matrixEntryCount) {
        issues.add(
          'Decision matrix entryCount=$matrixEntryCount but split plan entryCount=$splitEntryCount.',
        );
      }
      if (splitBucketCount != matrixBucketCount) {
        issues.add(
          'Decision matrix bucketCount=$matrixBucketCount but split plan bucketCount=$splitBucketCount.',
        );
      }
    }
  }

  for (final group in groups.values) {
    for (final pathspec in group.pathspecFiles) {
      final file = File(pathspec);
      final expectedPaths = expectedPathsByPathspec[pathspec] ?? group.paths;
      final exists = file.existsSync();
      var lineCount = 0;
      var missingCount = expectedPaths.length;
      var unexpectedCount = 0;
      var duplicateCount = 0;
      if (!exists) {
        issues.add('Pathspec file is missing: $pathspec');
      } else {
        final lines = LineSplitter.split(file.readAsStringSync())
            .map((line) => line.trim().replaceAll('\\', '/'))
            .where((line) => line.isNotEmpty)
            .toList();
        lineCount = lines.length;
        final lineSet = lines.toSet();
        duplicateCount = lines.length - lineSet.length;
        final missing = expectedPaths.difference(lineSet);
        final unexpected = lineSet.difference(expectedPaths);
        missingCount = missing.length;
        unexpectedCount = unexpected.length;
        if (duplicateCount != 0) {
          issues.add('Pathspec file has duplicate entries: $pathspec');
        }
        if (missing.isNotEmpty) {
          issues.add(
            'Pathspec file $pathspec is missing matrix paths: ${_formatPaths(missing)}',
          );
        }
        if (unexpected.isNotEmpty) {
          issues.add(
            'Pathspec file $pathspec has paths outside the matrix group: ${_formatPaths(unexpected)}',
          );
        }
      }
      pathspecFindings.add(
        _PathspecIntegrity(
          path: pathspec,
          groupId: group.id,
          exists: exists,
          lineCount: lineCount,
          matrixPathCount: expectedPaths.length,
          missingCount: missingCount,
          unexpectedCount: unexpectedCount,
          duplicateCount: duplicateCount,
        ),
      );
    }
  }

  final draftPullRequests = matrix['draftPullRequests'] as List? ?? const [];
  if (draftPullRequests.isEmpty) {
    warnings.add('Decision matrix has no draftPullRequests entries.');
  } else {
    for (final rawDraft in draftPullRequests) {
      if (rawDraft is! Map) continue;
      final draft = rawDraft.cast<String, dynamic>();
      final bucketId = draft['bucketId']?.toString() ?? 'unknown';
      final title = draft['title']?.toString() ?? '';
      final body = draft['body']?.toString() ?? '';
      final pathspecFile = draft['pathspecFile']?.toString() ?? '';
      if (!title.startsWith('Release staging: ')) {
        issues
            .add('Draft PR for $bucketId is missing a release staging title.');
      }
      for (final marker in [
        '## Scope',
        '## Owner Decision',
        '## Verification',
        pathspecFile,
      ]) {
        if (marker.isNotEmpty && !body.contains(marker)) {
          issues
              .add('Draft PR for $bucketId is missing required text: $marker');
        }
      }
    }
  }

  return _MatrixIntegrity(
    sourceSplitPlan: sourceSplitPlan,
    sourceSplitPlanExists: sourceSplitPlanExists,
    sourceSplitPlanMatches: sourceSplitPlanMatches,
    pathspecs: pathspecFindings,
    issues: issues,
    warnings: warnings,
  );
}

Future<Set<String>> _readObservedPaths(_Options options) async {
  final args = switch (options.mode) {
    _ValidationMode.stagedIndex => ['diff', '--cached', '--name-only'],
    _ValidationMode.branch => [
        'diff',
        '--name-only',
        '${options.base}...HEAD',
      ],
  };
  final result = await Process.run(
    'git',
    args,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }
  return LineSplitter.split(result.stdout as String)
      .map((line) => line.trim().replaceAll('\\', '/'))
      .where((line) => line.isNotEmpty)
      .toSet();
}

_ValidationResult _validate({
  required Map<String, _DecisionGroup> groups,
  required Set<String> observedPaths,
  required bool allowNewPaths,
}) {
  final issues = <String>[];
  final warnings = <String>[];
  final plannedPaths = <String>{};
  final groupCoverage = <_DecisionGroupCoverage>[];

  for (final group in groups.values) {
    plannedPaths.addAll(group.paths);
  }

  final sortedGroups = groups.values.toList()..sort(_compareDecisionGroups);
  for (final group in sortedGroups) {
    final observed = group.paths.intersection(observedPaths);
    final missing = group.paths.difference(observedPaths);
    final forbidden =
        group.validationRule == 'forbidden' ? observed : const <String>{};
    groupCoverage.add(
      _DecisionGroupCoverage(
        id: group.id,
        title: group.title,
        validationRule: group.validationRule,
        pathCount: group.paths.length,
        observedPathCount: observed.length,
        missingPathCount: missing.length,
        forbiddenPathCount: forbidden.length,
        status: _coverageStatus(
          validationRule: group.validationRule,
          observedPathCount: observed.length,
          missingPathCount: missing.length,
          forbiddenPathCount: forbidden.length,
        ),
      ),
    );
  }

  final mustShip = groups['must_ship'];
  if (mustShip == null) {
    issues.add('Decision matrix is missing the must_ship group.');
  } else {
    final missing = mustShip.paths.difference(observedPaths);
    if (missing.isNotEmpty) {
      issues.add(
        'Missing must_ship paths: ${_formatPaths(missing)}',
      );
    }
  }

  for (final groupId in const ['generated_only', 'binary_evidence']) {
    final group = groups[groupId];
    if (group == null) {
      issues.add('Decision matrix is missing the $groupId group.');
      continue;
    }
    final present = group.paths.intersection(observedPaths);
    if (present.isEmpty) {
      warnings.add('${group.title} paths are not included in this validation.');
      continue;
    }
    final missing = group.paths.difference(observedPaths);
    if (missing.isNotEmpty) {
      issues.add(
        '${group.title} is partially included; missing ${_formatPaths(missing)}',
      );
    }
  }

  final deferExclude = groups['defer_exclude'];
  if (deferExclude == null) {
    issues.add('Decision matrix is missing the defer_exclude group.');
  } else {
    final forbidden = deferExclude.paths.intersection(observedPaths);
    if (forbidden.isNotEmpty) {
      issues.add(
        'defer_exclude paths must not be staged: ${_formatPaths(forbidden)}',
      );
    }
  }

  final unexpected = observedPaths.difference(plannedPaths);
  if (unexpected.isNotEmpty) {
    final message = 'Unplanned paths are present: ${_formatPaths(unexpected)}';
    if (allowNewPaths) {
      warnings.add(message);
    } else {
      issues.add(message);
    }
  }

  if (observedPaths.isEmpty) {
    issues.add('No staged or branch-diff paths were observed.');
  }

  return _ValidationResult(
    issues: issues,
    warnings: warnings,
    groupCoverage: groupCoverage,
  );
}

List<_NextStageCommandGroup> _buildNextStageCommands({
  required Map<String, _DecisionGroup> groups,
  required List<_DecisionGroupCoverage> groupCoverage,
}) {
  final statusByGroupId = {
    for (final coverage in groupCoverage) coverage.id: coverage.status,
  };
  final sortedGroups = groups.values.toList()..sort(_compareDecisionGroups);

  return [
    for (final group in sortedGroups)
      if (group.pathspecFiles.isNotEmpty)
        _NextStageCommandGroup(
          groupId: group.id,
          title: group.title,
          validationRule: group.validationRule,
          status: statusByGroupId[group.id] ?? 'unknown',
          purpose: _stageCommandPurpose(group.validationRule),
          commands: [
            for (final pathspec in group.pathspecFiles)
              _stageCommandForRule(
                validationRule: group.validationRule,
                pathspec: pathspec,
              ),
          ],
        ),
  ];
}

int _compareDecisionGroups(_DecisionGroup a, _DecisionGroup b) {
  final aIndex = _decisionGroupOrder.indexOf(a.id);
  final bIndex = _decisionGroupOrder.indexOf(b.id);
  if (aIndex != -1 || bIndex != -1) {
    return (aIndex == -1 ? _decisionGroupOrder.length : aIndex)
        .compareTo(bIndex == -1 ? _decisionGroupOrder.length : bIndex);
  }
  return a.id.compareTo(b.id);
}

String _stageCommandPurpose(String validationRule) {
  return switch (validationRule) {
    'required_all' =>
      'Required: stage every listed pathspec before the release PR validation can pass.',
    'optional_all_or_none' =>
      'Optional: leave this group unstaged, or stage every listed pathspec together.',
    'forbidden' =>
      'Cleanup: remove these paths from the index if they appear in a staged release branch.',
    _ => 'Review this group before staging.',
  };
}

String _stageCommandForRule({
  required String validationRule,
  required String pathspec,
}) {
  if (validationRule == 'forbidden') {
    return 'git restore --staged --pathspec-from-file=$pathspec';
  }
  return 'git add --pathspec-from-file=$pathspec';
}

String _coverageStatus({
  required String validationRule,
  required int observedPathCount,
  required int missingPathCount,
  required int forbiddenPathCount,
}) {
  return switch (validationRule) {
    'required_all' => missingPathCount == 0 ? 'complete' : 'incomplete',
    'optional_all_or_none' => observedPathCount == 0
        ? 'not_included'
        : missingPathCount == 0
            ? 'complete'
            : 'partial',
    'forbidden' => forbiddenPathCount == 0 ? 'clean' : 'forbidden_present',
    _ => missingPathCount == 0 ? 'complete' : 'unknown',
  };
}

String _formatPaths(Set<String> paths) {
  final sorted = paths.toList()..sort();
  const limit = 20;
  final visible = sorted.take(limit).map((path) => '`$path`').join(', ');
  if (sorted.length <= limit) {
    return visible;
  }
  return '$visible, ... ${sorted.length - limit} more';
}

String _renderMarkdown(Map<String, dynamic> report) {
  final issues = report['issues'] as List? ?? const [];
  final warnings = report['warnings'] as List? ?? const [];
  final coverage = report['decisionGroupCoverage'] as List? ?? const [];
  final nextStageCommands = report['nextStageCommands'] as List? ?? const [];
  final matrixIntegrity =
      report['matrixIntegrity'] as Map<String, dynamic>? ?? const {};
  final pathspecs = matrixIntegrity['pathspecs'] as List? ?? const [];
  final observed = report['observedPaths'] as List? ?? const [];
  final buffer = StringBuffer()
    ..writeln('# Release PR Staged Branch Validation')
    ..writeln()
    ..writeln('- Generated at: `${report['generatedAt']}`')
    ..writeln('- Matrix: `${report['matrixPath']}`')
    ..writeln('- Mode: `${report['mode']}`')
    ..writeln('- Base: `${report['base']}`')
    ..writeln('- Passed: `${report['passed']}`')
    ..writeln('- Observed paths: `${report['observedPathCount']}`')
    ..writeln('- Issues: `${report['issueCount']}`')
    ..writeln('- Warnings: `${report['warningCount']}`')
    ..writeln();

  _writeList(buffer, 'Issues', issues);
  _writeList(buffer, 'Warnings', warnings);

  buffer
    ..writeln('## Matrix Integrity')
    ..writeln()
    ..writeln(
      '- Source split plan: `${matrixIntegrity['sourceSplitPlan'] ?? 'unknown'}`',
    )
    ..writeln(
      '- Source split plan exists: `${matrixIntegrity['sourceSplitPlanExists']}`',
    )
    ..writeln(
      '- Source split plan matches matrix: `${matrixIntegrity['sourceSplitPlanMatches']}`',
    )
    ..writeln()
    ..writeln(
        '| Pathspec | Group | Exists | Lines | Matrix paths | Missing | Unexpected | Duplicates |')
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final rawPathspec in pathspecs) {
    final pathspec = rawPathspec as Map<String, dynamic>;
    buffer.writeln(
      '| `${pathspec['path']}` | `${pathspec['groupId']}` | '
      '`${pathspec['exists']}` | `${pathspec['lineCount']}` | '
      '`${pathspec['matrixPathCount']}` | `${pathspec['missingCount']}` | '
      '`${pathspec['unexpectedCount']}` | `${pathspec['duplicateCount']}` |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Decision Group Coverage')
    ..writeln()
    ..writeln(
      '| Group | Rule | Status | Paths | Observed | Missing | Forbidden |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: |');
  for (final item in coverage) {
    final group = item as Map<String, dynamic>;
    buffer.writeln(
      '| ${group['title']} | `${group['validationRule']}` | '
      '`${group['status']}` | `${group['pathCount']}` | '
      '`${group['observedPathCount']}` | `${group['missingPathCount']}` | '
      '`${group['forbiddenPathCount']}` |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Next Stage Commands')
    ..writeln()
    ..writeln(
      'These commands are derived from the owner decision matrix pathspecs. Review the pathspec files before running them; cleanup commands only change the staged index.',
    )
    ..writeln();
  if (nextStageCommands.isEmpty) {
    buffer.writeln('None.');
  } else {
    for (final item in nextStageCommands) {
      final commandGroup = item as Map<String, dynamic>;
      final commands = commandGroup['commands'] as List? ?? const [];
      buffer
        ..writeln('### ${commandGroup['title']}')
        ..writeln()
        ..writeln('- Status: `${commandGroup['status']}`')
        ..writeln('- Rule: `${commandGroup['validationRule']}`')
        ..writeln('- Purpose: ${commandGroup['purpose']}')
        ..writeln()
        ..writeln('```powershell');
      for (final command in commands) {
        buffer.writeln(command);
      }
      buffer
        ..writeln('```')
        ..writeln();
    }
  }

  buffer
    ..writeln('## Observed Paths')
    ..writeln();
  if (observed.isEmpty) {
    buffer.writeln('None.');
  } else {
    for (final path in observed.take(120)) {
      buffer.writeln('- `$path`');
    }
    if (observed.length > 120) {
      buffer.writeln('- ... ${observed.length - 120} more paths omitted.');
    }
  }
  return buffer.toString();
}

void _writeList(StringBuffer buffer, String title, List<dynamic> values) {
  buffer
    ..writeln('## $title')
    ..writeln();
  if (values.isEmpty) {
    buffer.writeln('None.');
  } else {
    for (final value in values) {
      buffer.writeln('- $value');
    }
  }
  buffer.writeln();
}

enum _ValidationMode { stagedIndex, branch }

extension _ValidationModeReportName on _ValidationMode {
  String get reportName => switch (this) {
        _ValidationMode.stagedIndex => 'index',
        _ValidationMode.branch => 'branch',
      };
}

class _Options {
  final String matrixPath;
  final _ValidationMode mode;
  final String base;
  final bool allowNewPaths;

  const _Options({
    required this.matrixPath,
    required this.mode,
    required this.base,
    required this.allowNewPaths,
  });

  factory _Options.parse(List<String> args) {
    var matrixPath = _defaultMatrixPath;
    var mode = _ValidationMode.stagedIndex;
    var base = 'main';
    var allowNewPaths = false;

    for (final arg in args) {
      if (arg.startsWith('--matrix=')) {
        matrixPath = arg.substring('--matrix='.length);
      } else if (arg.startsWith('--mode=')) {
        final value = arg.substring('--mode='.length);
        mode = switch (value) {
          'index' => _ValidationMode.stagedIndex,
          'branch' => _ValidationMode.branch,
          _ => throw ArgumentError('Unsupported validation mode: $value'),
        };
      } else if (arg.startsWith('--base=')) {
        base = arg.substring('--base='.length);
      } else if (arg == '--allow-new-paths') {
        allowNewPaths = true;
      } else if (arg == '--help' || arg == '-h') {
        stdout.writeln(
          'Usage: dart run tools/production/release_pr_staged_branch_validator.dart [--mode=index|branch] [--base=main] [--matrix=path] [--allow-new-paths]',
        );
        exit(0);
      } else {
        throw ArgumentError('Unknown argument: $arg');
      }
    }

    return _Options(
      matrixPath: matrixPath,
      mode: mode,
      base: base,
      allowNewPaths: allowNewPaths,
    );
  }
}

class _DecisionGroup {
  final String id;
  final String title;
  final String validationRule;
  final List<String> pathspecFiles;
  final Set<String> paths;

  const _DecisionGroup({
    required this.id,
    required this.title,
    required this.validationRule,
    required this.pathspecFiles,
    required this.paths,
  });

  factory _DecisionGroup.fromJson(Map<String, dynamic> json) {
    return _DecisionGroup(
      id: json['id']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? 'Unknown',
      validationRule: json['validationRule']?.toString() ?? 'unknown',
      pathspecFiles: [
        for (final path in json['pathspecFiles'] as List? ?? const [])
          path.toString().replaceAll('\\', '/'),
      ],
      paths: {
        for (final path in json['paths'] as List? ?? const [])
          path.toString().replaceAll('\\', '/'),
      },
    );
  }
}

class _ValidationResult {
  final List<String> issues;
  final List<String> warnings;
  final List<_DecisionGroupCoverage> groupCoverage;

  const _ValidationResult({
    required this.issues,
    required this.warnings,
    required this.groupCoverage,
  });

  bool get passed => issues.isEmpty;
}

class _MatrixIntegrity {
  final String? sourceSplitPlan;
  final bool sourceSplitPlanExists;
  final bool sourceSplitPlanMatches;
  final List<_PathspecIntegrity> pathspecs;
  final List<String> issues;
  final List<String> warnings;

  const _MatrixIntegrity({
    required this.sourceSplitPlan,
    required this.sourceSplitPlanExists,
    required this.sourceSplitPlanMatches,
    required this.pathspecs,
    required this.issues,
    required this.warnings,
  });

  Map<String, Object?> toJson() => {
        'sourceSplitPlan': sourceSplitPlan,
        'sourceSplitPlanExists': sourceSplitPlanExists,
        'sourceSplitPlanMatches': sourceSplitPlanMatches,
        'pathspecCount': pathspecs.length,
        'pathspecs': [
          for (final pathspec in pathspecs) pathspec.toJson(),
        ],
        'issueCount': issues.length,
        'warningCount': warnings.length,
      };
}

class _PathspecIntegrity {
  final String path;
  final String groupId;
  final bool exists;
  final int lineCount;
  final int matrixPathCount;
  final int missingCount;
  final int unexpectedCount;
  final int duplicateCount;

  const _PathspecIntegrity({
    required this.path,
    required this.groupId,
    required this.exists,
    required this.lineCount,
    required this.matrixPathCount,
    required this.missingCount,
    required this.unexpectedCount,
    required this.duplicateCount,
  });

  Map<String, Object?> toJson() => {
        'path': path,
        'groupId': groupId,
        'exists': exists,
        'lineCount': lineCount,
        'matrixPathCount': matrixPathCount,
        'missingCount': missingCount,
        'unexpectedCount': unexpectedCount,
        'duplicateCount': duplicateCount,
      };
}

class _DecisionGroupCoverage {
  final String id;
  final String title;
  final String validationRule;
  final int pathCount;
  final int observedPathCount;
  final int missingPathCount;
  final int forbiddenPathCount;
  final String status;

  const _DecisionGroupCoverage({
    required this.id,
    required this.title,
    required this.validationRule,
    required this.pathCount,
    required this.observedPathCount,
    required this.missingPathCount,
    required this.forbiddenPathCount,
    required this.status,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'validationRule': validationRule,
        'pathCount': pathCount,
        'observedPathCount': observedPathCount,
        'missingPathCount': missingPathCount,
        'forbiddenPathCount': forbiddenPathCount,
        'status': status,
      };
}

class _NextStageCommandGroup {
  final String groupId;
  final String title;
  final String validationRule;
  final String status;
  final String purpose;
  final List<String> commands;

  const _NextStageCommandGroup({
    required this.groupId,
    required this.title,
    required this.validationRule,
    required this.status,
    required this.purpose,
    required this.commands,
  });

  Map<String, Object?> toJson() => {
        'groupId': groupId,
        'title': title,
        'validationRule': validationRule,
        'status': status,
        'purpose': purpose,
        'commands': commands,
      };
}
