import 'dart:convert';
import 'dart:io';

const _completionAuditPath =
    'docs/production-readiness/public-release-completion-audit.json';
const _jsonOutputPath =
    'docs/production-readiness/public-release-owner-checklist.json';
const _markdownOutputPath =
    'docs/production-readiness/public-release-owner-checklist.md';

void main() {
  final auditFile = File(_completionAuditPath);
  if (!auditFile.existsSync()) {
    stderr.writeln('Missing completion audit: $_completionAuditPath');
    stderr.writeln(
      'Run: dart run melos run audit:public-release-completion --no-select',
    );
    exit(1);
  }

  final audit =
      jsonDecode(auditFile.readAsStringSync()) as Map<String, dynamic>;
  final checks = (audit['promptToArtifactChecklist'] as List? ?? const [])
      .whereType<Map>()
      .map((check) =>
          _OwnerChecklistItem.fromJson(check.cast<String, dynamic>()))
      .toList();
  final sourceArtifacts =
      (audit['sourceArtifacts'] as List? ?? const []).whereType<Map>().toList();
  final sourceArtifactBlockerCount = sourceArtifacts.fold<int>(
    0,
    (sum, artifact) => sum + _intValue(artifact['blockerCount']),
  );

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceCompletionAudit': _completionAuditPath,
    'completionAuditGeneratedAt': audit['generatedAt'],
    'decision': audit['decision'],
    'gateDecision': audit['gateDecision'],
    'ready': audit['ready'],
    'completionDecision': audit['completionDecision'] ?? audit['decision'],
    'completionDetail': audit['completionDetail'],
    'goalSectionsObserved': _stringList(audit['goalSectionsObserved']),
    'sourceArtifacts': sourceArtifacts,
    'sourceArtifactBlockerCount': sourceArtifactBlockerCount,
    'itemCount': checks.length,
    'completeCount': checks.where((check) => check.status == 'complete').length,
    'blockedOrIncompleteCount':
        checks.where((check) => check.status != 'complete').length,
    'items': checks.map((check) => check.toJson()).toList(),
  };

  File(_jsonOutputPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File(_markdownOutputPath).writeAsStringSync(_renderMarkdown(
    audit: audit,
    checks: checks,
  ));

  stdout.writeln('Public release owner checklist complete.');
  stdout.writeln('Decision: ${audit['decision']}');
  stdout.writeln('Items: ${checks.length}');
  stdout.writeln(
    'Blocked/incomplete: ${checks.where((check) => check.status != 'complete').length}',
  );
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');
}

String _renderMarkdown({
  required Map<String, dynamic> audit,
  required List<_OwnerChecklistItem> checks,
}) {
  final buffer = StringBuffer()
    ..writeln('# Public Release Owner Checklist')
    ..writeln()
    ..writeln('- Source audit: `$_completionAuditPath`')
    ..writeln('- Completion audit generated at: `${audit['generatedAt']}`')
    ..writeln('- Decision: `${audit['decision']}`')
    ..writeln('- Gate decision: `${audit['gateDecision']}`')
    ..writeln(
      '- Completion detail: ${audit['completionDetail'] ?? 'unknown'}',
    )
    ..writeln('- Ready: `${audit['ready']}`')
    ..writeln('- Items: `${checks.length}`')
    ..writeln(
      '- Complete: `${checks.where((check) => check.status == 'complete').length}`',
    )
    ..writeln(
      '- Blocked or incomplete: `${checks.where((check) => check.status != 'complete').length}`',
    )
    ..writeln()
    ..writeln(
      'This owner checklist is generated from structured completion-audit fields. Edit the underlying evidence, not this generated file.',
    )
    ..writeln()
    ..writeln('## Source Artifacts')
    ..writeln()
    ..writeln('| Artifact | Exists | Generated | Decision | Count | Blockers |')
    ..writeln('| --- | ---: | --- | --- | ---: | ---: |');

  for (final artifact
      in (audit['sourceArtifacts'] as List? ?? const []).whereType<Map>()) {
    final path = artifact['path']?.toString() ?? 'unknown';
    final generated = artifact['generatedAt']?.toString() ??
        artifact['fileModifiedAt']?.toString() ??
        'unknown';
    final decision = artifact['decision']?.toString() ??
        (artifact['ready'] == null ? '' : 'ready=${artifact['ready']}');
    final count = artifact['entryCount'] ??
        artifact['bucketCount'] ??
        artifact['passedCount'] ??
        artifact['checkCount'] ??
        '';
    final blockers = artifact['blockerCount'] ?? '';
    buffer.writeln(
      '| `$path` | `${artifact['exists']}` | `${_escapeTable(generated)}` | `${_escapeTable(decision)}` | `$count` | `$blockers` |',
    );
  }

  final goalSections = _stringList(audit['goalSectionsObserved']);
  if (goalSections.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Goal Sections Observed')
      ..writeln();
    _writeCodeList(buffer, goalSections);
  }

  buffer
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Status | Requirement | Gap |')
    ..writeln('| --- | --- | --- |');

  for (final check in checks) {
    final summaryGap = _displayGap(check);
    buffer.writeln(
      '| `${check.status}` | ${_escapeTable(check.requirement)} | ${_escapeTable(summaryGap)} |',
    );
  }

  buffer.writeln();
  for (final check in checks) {
    buffer
      ..writeln('## ${check.requirement}')
      ..writeln()
      ..writeln('- ID: `${check.id}`')
      ..writeln('- Status: `${check.status}`')
      ..writeln('- Verification: ${check.verification}')
      ..writeln('- Gap: ${_displayGap(check)}')
      ..writeln()
      ..writeln('Required input:')
      ..writeln();
    _writeList(
      buffer,
      check.requiredInput.isEmpty ? const [] : [check.requiredInput],
    );
    buffer
      ..writeln('Rerun commands:')
      ..writeln();
    _writeCodeList(buffer, check.rerunCommands);
    buffer
      ..writeln('Acceptance criteria:')
      ..writeln();
    _writeList(buffer, check.acceptanceCriteria);
    buffer
      ..writeln('Expected evidence:')
      ..writeln();
    _writeCodeList(buffer, check.expectedEvidence);
    buffer
      ..writeln('Current evidence references:')
      ..writeln();
    _writeCodeList(buffer, check.evidence);
    buffer.writeln();
  }

  return buffer.toString();
}

String _displayGap(_OwnerChecklistItem check) {
  if (check.requiredInput.isEmpty) {
    return check.gap.trim().isEmpty ? 'None recorded.' : check.gap.trim();
  }
  final requiredInput = check.requiredInput.replaceAll(RegExp(r'\s+'), ' ');
  final normalizedGap = check.gap
      .replaceAll('Required input:', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final displayGap = normalizedGap
      .replaceAll(requiredInput, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return displayGap.isEmpty ? 'See required input.' : displayGap;
}

void _writeList(StringBuffer buffer, List<String> values) {
  if (values.isEmpty) {
    buffer.writeln('- None recorded.');
    return;
  }
  for (final value in values) {
    buffer.writeln('- $value');
  }
}

void _writeCodeList(StringBuffer buffer, List<String> values) {
  if (values.isEmpty) {
    buffer.writeln('- `None recorded`');
    return;
  }
  for (final value in values) {
    buffer.writeln('- `$value`');
  }
}

String _escapeTable(String value) => value.replaceAll('|', r'\|');

class _OwnerChecklistItem {
  final String id;
  final String requirement;
  final String status;
  final List<String> evidence;
  final String verification;
  final String requiredInput;
  final List<String> rerunCommands;
  final List<String> acceptanceCriteria;
  final List<String> expectedEvidence;
  final String gap;

  const _OwnerChecklistItem({
    required this.id,
    required this.requirement,
    required this.status,
    required this.evidence,
    required this.verification,
    required this.requiredInput,
    required this.rerunCommands,
    required this.acceptanceCriteria,
    required this.expectedEvidence,
    required this.gap,
  });

  factory _OwnerChecklistItem.fromJson(Map<String, dynamic> json) {
    return _OwnerChecklistItem(
      id: json['id']?.toString() ?? 'unknown',
      requirement: json['requirement']?.toString() ?? 'Unknown requirement',
      status: json['status']?.toString() ?? 'unknown',
      evidence: _stringList(json['evidence']),
      verification: json['verification']?.toString() ?? '',
      requiredInput: json['requiredInput']?.toString() ?? '',
      rerunCommands: _stringList(json['rerunCommands']),
      acceptanceCriteria: _stringList(json['acceptanceCriteria']),
      expectedEvidence: _stringList(json['expectedEvidence']),
      gap: json['gap']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'requirement': requirement,
        'status': status,
        'evidence': evidence,
        'verification': verification,
        'requiredInput': requiredInput,
        'rerunCommands': rerunCommands,
        'acceptanceCriteria': acceptanceCriteria,
        'expectedEvidence': expectedEvidence,
        'gap': gap,
      };
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  if (value == null || value.toString().trim().isEmpty) {
    return const [];
  }
  return [value.toString()];
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
