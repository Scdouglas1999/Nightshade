import 'dart:convert';
import 'dart:io';

const _inputPath = 'docs/production-readiness/release-pr-split-plan.json';
const _jsonOutputPath =
    'docs/production-readiness/release-pr-owner-decision-matrix.json';
const _markdownOutputPath =
    'docs/production-readiness/release-pr-owner-decision-matrix.md';

const _decisionGroupDefinitions = {
  'must_ship': _DecisionGroupDefinition(
    id: 'must_ship',
    title: 'Must Ship',
    description:
        'Human-authored release, API, platform, data, UI, and verification changes that need owner review for the public release branch.',
    validationRule: 'required_all',
  ),
  'generated_only': _DecisionGroupDefinition(
    id: 'generated_only',
    title: 'Generated Only',
    description:
        'Regenerated outputs and lock files that should be reviewed after their source bucket is approved.',
    validationRule: 'optional_all_or_none',
  ),
  'binary_evidence': _DecisionGroupDefinition(
    id: 'binary_evidence',
    title: 'Binary / Evidence',
    description:
        'Binary payloads, screenshots, databases, smoke logs, and packaged evidence that require deliberate artifact review.',
    validationRule: 'optional_all_or_none',
  ),
  'defer_exclude': _DecisionGroupDefinition(
    id: 'defer_exclude',
    title: 'Defer / Exclude',
    description:
        'Scratch, research, broad miscellaneous, or owner-quarantined paths that should not be staged into the public release branch.',
    validationRule: 'forbidden',
  ),
};

const _bucketDecisionGroups = {
  'generated-files': 'generated_only',
  'binary-and-evidence-artifacts': 'binary_evidence',
  'release-infra-evidence': 'must_ship',
  'headless-remote-api': 'must_ship',
  'mobile-remote-client': 'must_ship',
  'native-driver-bridge': 'must_ship',
  'core-data-model': 'must_ship',
  'desktop-ui-workflows': 'must_ship',
  'tests-and-support-tooling': 'must_ship',
  'out-of-release-scope-review': 'defer_exclude',
};

const _decisionGroupReleaseListIds = {
  'must_ship': 'must-ship',
  'generated_only': 'generated-only',
  'binary_evidence': 'binary-evidence',
  'defer_exclude': 'defer-exclude',
};

Future<void> main() async {
  final inputFile = File(_inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Missing release PR split plan: $_inputPath');
    stderr.writeln('Run: dart run melos run audit:release-pr-plan --no-select');
    exit(1);
  }

  final plan = jsonDecode(inputFile.readAsStringSync()) as Map<String, dynamic>;
  final buckets = _readBuckets(plan);
  final releaseLists = _readReleaseLists(plan);
  final groups = {
    for (final definition in _decisionGroupDefinitions.values)
      definition.id: _DecisionGroup(definition),
  };

  for (final group in groups.values) {
    group.releaseList = releaseLists[_decisionGroupReleaseListIds[group.id]];
  }

  for (final bucket in buckets) {
    final groupId = _bucketDecisionGroups[bucket.id] ?? 'defer_exclude';
    groups[groupId]!.buckets.add(bucket);
  }

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceSplitPlan': _inputPath,
    'sourceGeneratedAt': plan['generatedAt'],
    'sourceStagingAudit': plan['sourceStagingAudit'],
    'sourceStagingGeneratedAt': plan['sourceGeneratedAt'],
    'currentBranch': plan['currentBranch'],
    'head': plan['head'],
    'entryCount': plan['entryCount'],
    'bucketCount': plan['bucketCount'],
    'decisionGroups': {
      for (final group in groups.values) group.id: group.toJson(),
    },
    'releaseLists': {
      for (final group in groups.values)
        if (group.releaseList != null) group.id: group.releaseList!.toJson(),
    },
    'draftPullRequests': [
      for (final bucket in buckets) bucket.toDraftPullRequestJson(),
    ],
    'validation': {
      'indexCommand':
          'dart run tools/production/release_pr_staged_branch_validator.dart --mode=index',
      'branchCommand':
          'dart run tools/production/release_pr_staged_branch_validator.dart --mode=branch --base=main',
      'rules': [
        'All must_ship paths must be present in the validated staged/index or branch diff.',
        'generated_only and binary_evidence groups are optional, but if any path from the group is present then the whole group must be present.',
        'defer_exclude paths are forbidden.',
        'Paths outside the decision matrix are forbidden unless the validator is run with --allow-new-paths.',
      ],
    },
  };

  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(
    plan: plan,
    groups: groups,
    buckets: buckets,
  ));

  stdout.writeln('Release PR owner decision matrix complete.');
  stdout.writeln('Buckets: ${buckets.length}');
  stdout.writeln(
      'Paths: ${buckets.fold<int>(0, (sum, b) => sum + b.paths.length)}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');
}

List<_Bucket> _readBuckets(Map<String, dynamic> plan) {
  final rawBuckets = plan['buckets'] as List? ?? const [];
  return rawBuckets
      .whereType<Map>()
      .map((bucket) => _Bucket.fromJson(bucket.cast<String, dynamic>()))
      .toList();
}

Map<String, _ReleaseList> _readReleaseLists(Map<String, dynamic> plan) {
  final rawLists = plan['releaseLists'] as List? ?? const [];
  return {
    for (final rawList in rawLists.whereType<Map>())
      _ReleaseList.fromJson(rawList.cast<String, dynamic>()).id:
          _ReleaseList.fromJson(rawList.cast<String, dynamic>()),
  };
}

String _renderMarkdown({
  required Map<String, dynamic> plan,
  required Map<String, _DecisionGroup> groups,
  required List<_Bucket> buckets,
}) {
  final buffer = StringBuffer()
    ..writeln('# Release PR Owner Decision Matrix')
    ..writeln()
    ..writeln('- Source split plan: `$_inputPath`')
    ..writeln('- Source generated at: `${plan['generatedAt'] ?? 'unknown'}`')
    ..writeln(
        '- Branch at planning time: `${plan['currentBranch'] ?? 'unknown'}`')
    ..writeln('- HEAD at planning time: `${plan['head'] ?? 'unknown'}`')
    ..writeln('- Buckets: `${buckets.length}`')
    ..writeln(
      '- Paths: `${buckets.fold<int>(0, (sum, bucket) => sum + bucket.paths.length)}`',
    )
    ..writeln()
    ..writeln(
      'This file turns the generated pathspec buckets into owner-reviewable PR drafts and validation rules. It does not stage files or approve any bucket by itself.',
    )
    ..writeln()
    ..writeln('## Decision Groups')
    ..writeln()
    ..writeln(
      '| Group | Buckets | Paths | Validation rule | Related release list | Pathspecs |',
    )
    ..writeln('| --- | ---: | ---: | --- | --- | --- |');

  for (final groupId in _decisionGroupDefinitions.keys) {
    final group = groups[groupId]!;
    buffer.writeln(
      '| ${group.definition.title} | ${group.buckets.length} | ${group.pathCount} | `${group.definition.validationRule}` | ${group.releaseList == null ? '`missing`' : '`${group.releaseList!.pathspecFile}`'} | ${group.pathspecFiles.map((path) => '`$path`').join('<br>')} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Release Triage Lists')
    ..writeln()
    ..writeln(
      'These aggregate lists classify every dirty path by release triage. The decision groups above classify PR validation buckets, so counts can differ when a validation bucket contains both release-critical and support paths.',
    )
    ..writeln()
    ..writeln('| List | Paths | Pathspec | Description |')
    ..writeln('| --- | ---: | --- | --- |');

  for (final groupId in _decisionGroupDefinitions.keys) {
    final list = groups[groupId]!.releaseList;
    if (list == null) {
      buffer.writeln(
        '| ${_decisionGroupDefinitions[groupId]!.title} | 0 | `missing` | Missing release triage list. |',
      );
      continue;
    }
    buffer.writeln(
      '| ${list.title} | ${list.count} | `${list.pathspecFile}` | ${list.description} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Validation Commands')
    ..writeln()
    ..writeln(
      '- Validate currently staged index: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=index`',
    )
    ..writeln(
      '- Validate a committed PR branch against main: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=branch --base=main`',
    )
    ..writeln()
    ..writeln('## Draft PR Descriptions')
    ..writeln();

  for (final bucket in buckets) {
    final group = _bucketDecisionGroups[bucket.id] ?? 'defer_exclude';
    buffer
      ..writeln('### ${bucket.title}')
      ..writeln()
      ..writeln(
          '- Decision group: `${_decisionGroupDefinitions[group]!.title}`')
      ..writeln('- Bucket ID: `${bucket.id}`')
      ..writeln('- Paths: `${bucket.paths.length}`')
      ..writeln('- Pathspec: `${bucket.pathspecFile}`')
      ..writeln('- Owner command: `${bucket.ownerCommandFor(group)}`')
      ..writeln()
      ..writeln('Suggested PR title:')
      ..writeln()
      ..writeln('```text')
      ..writeln(bucket.prTitle)
      ..writeln('```')
      ..writeln()
      ..writeln('Suggested PR body:')
      ..writeln()
      ..writeln('```markdown')
      ..write(bucket.prBody(group))
      ..writeln('```')
      ..writeln();
  }

  buffer
    ..writeln('## Defer / Exclude Policy')
    ..writeln()
    ..writeln(
      'Any path in the `defer_exclude` group must remain unstaged unless the owner edits this matrix and reruns the validator. Any path outside this matrix is treated as an unplanned release change.',
    );

  return buffer.toString();
}

class _DecisionGroupDefinition {
  final String id;
  final String title;
  final String description;
  final String validationRule;

  const _DecisionGroupDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.validationRule,
  });
}

class _DecisionGroup {
  final _DecisionGroupDefinition definition;
  final List<_Bucket> buckets = [];
  _ReleaseList? releaseList;

  _DecisionGroup(this.definition);

  String get id => definition.id;
  int get pathCount =>
      buckets.fold<int>(0, (sum, bucket) => sum + bucket.paths.length);
  List<String> get pathspecFiles =>
      buckets.map((bucket) => bucket.pathspecFile).toList();

  Map<String, Object?> toJson() => {
        'id': definition.id,
        'title': definition.title,
        'description': definition.description,
        'validationRule': definition.validationRule,
        'bucketIds': buckets.map((bucket) => bucket.id).toList(),
        'bucketCount': buckets.length,
        'pathCount': pathCount,
        'relatedReleaseListFile': releaseList?.pathspecFile,
        'relatedReleaseListPathCount': releaseList?.count,
        'pathspecFiles': pathspecFiles,
        'paths': [
          for (final bucket in buckets) ...bucket.paths,
        ],
      };
}

class _ReleaseList {
  final String id;
  final String title;
  final String description;
  final String pathspecFile;
  final int count;

  const _ReleaseList({
    required this.id,
    required this.title,
    required this.description,
    required this.pathspecFile,
    required this.count,
  });

  factory _ReleaseList.fromJson(Map<String, dynamic> json) {
    return _ReleaseList(
      id: json['id']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? 'Unknown',
      description: json['description']?.toString() ?? '',
      pathspecFile: json['pathspecFile']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'pathspecFile': pathspecFile,
        'count': count,
      };
}

class _Bucket {
  final String id;
  final String title;
  final String intent;
  final String recommendedAction;
  final String pathspecFile;
  final String stageCommand;
  final int trackedChangeCount;
  final int untrackedCount;
  final int deletedCount;
  final int generatedCount;
  final int binaryCount;
  final int releaseCriticalCount;
  final Map<String, int> categoryCounts;
  final List<String> paths;

  const _Bucket({
    required this.id,
    required this.title,
    required this.intent,
    required this.recommendedAction,
    required this.pathspecFile,
    required this.stageCommand,
    required this.trackedChangeCount,
    required this.untrackedCount,
    required this.deletedCount,
    required this.generatedCount,
    required this.binaryCount,
    required this.releaseCriticalCount,
    required this.categoryCounts,
    required this.paths,
  });

  factory _Bucket.fromJson(Map<String, dynamic> json) {
    final categoryCounts = <String, int>{};
    for (final entry in (json['categoryCounts'] as Map? ?? const {}).entries) {
      categoryCounts[entry.key.toString()] =
          (entry.value as num?)?.toInt() ?? 0;
    }

    return _Bucket(
      id: json['id']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? 'Unknown',
      intent: json['intent']?.toString() ?? '',
      recommendedAction: json['recommendedAction']?.toString() ?? '',
      pathspecFile: json['pathspecFile']?.toString() ?? '',
      stageCommand: json['stageCommand']?.toString() ?? '',
      trackedChangeCount: (json['trackedChangeCount'] as num?)?.toInt() ?? 0,
      untrackedCount: (json['untrackedCount'] as num?)?.toInt() ?? 0,
      deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
      generatedCount: (json['generatedCount'] as num?)?.toInt() ?? 0,
      binaryCount: (json['binaryCount'] as num?)?.toInt() ?? 0,
      releaseCriticalCount:
          (json['releaseCriticalCount'] as num?)?.toInt() ?? 0,
      categoryCounts: categoryCounts,
      paths: [
        for (final entry in json['paths'] as List? ?? const [])
          ((entry as Map)['path'] as String).replaceAll('\\', '/'),
      ],
    );
  }

  String get prTitle => 'Release staging: $title';

  String prBody(String decisionGroup) {
    final group = _decisionGroupDefinitions[decisionGroup]!;
    final categories = categoryCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final categorySummary = categories.isEmpty
        ? '- None'
        : categories
            .map((entry) => '- `${entry.key}`: `${entry.value}`')
            .join('\n');

    return '''
## Scope
$intent

## Owner Decision
- Decision group: `${group.title}`
- Validation rule: `${group.validationRule}`
- Pathspec: `$pathspecFile`
- Owner command: `${ownerCommandFor(decisionGroup)}`

## Counts
- Paths: `${paths.length}`
- Tracked changes: `$trackedChangeCount`
- Untracked: `$untrackedCount`
- Deleted: `$deletedCount`
- Generated: `$generatedCount`
- Binary/evidence: `$binaryCount`
- Release-critical: `$releaseCriticalCount`

## Review Notes
$recommendedAction

## Category Mix
$categorySummary

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
''';
  }

  Map<String, Object?> toDraftPullRequestJson() {
    final groupId = _bucketDecisionGroups[id] ?? 'defer_exclude';
    return {
      'bucketId': id,
      'decisionGroup': groupId,
      'title': prTitle,
      'pathspecFile': pathspecFile,
      'stageCommand': ownerCommandFor(groupId),
      'body': prBody(groupId),
    };
  }

  String ownerCommandFor(String decisionGroup) {
    final group = _decisionGroupDefinitions[decisionGroup];
    if (group?.validationRule == 'forbidden') {
      return 'git restore --staged --pathspec-from-file=$pathspecFile';
    }
    return stageCommand;
  }
}
