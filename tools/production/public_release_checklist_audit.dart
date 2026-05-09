import 'dart:convert';
import 'dart:io';

const _checklistPath =
    'docs/production-readiness/public-release-master-checklist.md';
const _jsonOutputPath =
    'docs/production-readiness/public-release-checklist-audit.json';
const _markdownOutputPath =
    'docs/production-readiness/public-release-checklist-audit.md';

final _headingPattern = RegExp(r'^(#{2,6})\s+(.+)$');
final _checklistPattern = RegExp(r'^\s*- \[( |x|X)\]\s+(.+)$');
final _evidencePattern = RegExp(
  r'(^|\b)Evidence\b|(^|\b)evidence\b|code=|manual=|tests=|result=|`[^`]+`',
  caseSensitive: false,
);

void main(List<String> args) {
  final failOnUnchecked = args.contains('--fail-on-unchecked');
  final checklist = File(_checklistPath);
  if (!checklist.existsSync()) {
    stderr.writeln('Checklist not found: $_checklistPath');
    exit(2);
  }

  final content = checklist.readAsStringSync();
  final items = _parseChecklist(content);
  final checkedItems = items.where((item) => item.checked).toList();
  final uncheckedItems = items.where((item) => !item.checked).toList();
  final checkedWithoutEvidence =
      checkedItems.where((item) => !item.hasEvidence).toList();
  final sections = _sectionSummaries(items);
  final knownLimitationsReferenced =
      content.contains('docs/known-limitations.md');
  final supportedHardwareReferenced =
      content.contains('docs/supported-hardware-by-platform.md');

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceChecklist': _checklistPath,
    'totalItemCount': items.length,
    'checkedItemCount': checkedItems.length,
    'uncheckedItemCount': uncheckedItems.length,
    'checkedWithoutEvidenceCount': checkedWithoutEvidence.length,
    'knownLimitationsReferenced': knownLimitationsReferenced,
    'supportedHardwareByPlatformReferenced': supportedHardwareReferenced,
    'sections': sections.map((section) => section.toJson()).toList(),
    'checkedWithoutEvidence':
        checkedWithoutEvidence.map((item) => item.toJson()).toList(),
    'uncheckedItems': uncheckedItems.map((item) => item.toJson()).toList(),
  };

  File(_jsonOutputPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File(_markdownOutputPath).writeAsStringSync(_renderMarkdown(
    sections: sections,
    totalItemCount: items.length,
    checkedItemCount: checkedItems.length,
    uncheckedItems: uncheckedItems,
    checkedWithoutEvidence: checkedWithoutEvidence,
    knownLimitationsReferenced: knownLimitationsReferenced,
    supportedHardwareReferenced: supportedHardwareReferenced,
  ));

  stdout.writeln('Public release checklist audit complete.');
  stdout.writeln('Checklist items: ${items.length}');
  stdout.writeln('Checked items: ${checkedItems.length}');
  stdout.writeln('Unchecked items: ${uncheckedItems.length}');
  stdout.writeln('Checked without evidence: ${checkedWithoutEvidence.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');

  if (failOnUnchecked &&
      (uncheckedItems.isNotEmpty || checkedWithoutEvidence.isNotEmpty)) {
    exit(1);
  }
}

List<_ChecklistItem> _parseChecklist(String content) {
  final lines = const LineSplitter().convert(content);
  final items = <_ChecklistItem>[];
  var section = 'Preamble';
  _ChecklistItemBuilder? current;

  void finishCurrent() {
    final item = current;
    if (item != null) {
      items.add(item.build());
      current = null;
    }
  }

  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      finishCurrent();
      section = headingMatch.group(2)!.trim();
      continue;
    }

    final checklistMatch = _checklistPattern.firstMatch(line);
    if (checklistMatch != null) {
      finishCurrent();
      current = _ChecklistItemBuilder(
        section: section,
        checked: checklistMatch.group(1)!.toLowerCase() == 'x',
        text: checklistMatch.group(2)!.trim(),
        lineNumber: index + 1,
      );
      continue;
    }

    final item = current;
    if (item != null) {
      item.evidenceLines.add(line);
    }
  }

  finishCurrent();
  return items;
}

List<_SectionSummary> _sectionSummaries(List<_ChecklistItem> items) {
  final summaries = <String, _SectionSummaryBuilder>{};
  for (final item in items) {
    final summary = summaries.putIfAbsent(
      item.section,
      () => _SectionSummaryBuilder(item.section),
    );
    summary.total += 1;
    if (item.checked) {
      summary.checked += 1;
      if (!item.hasEvidence) {
        summary.checkedWithoutEvidence += 1;
      }
    } else {
      summary.unchecked += 1;
    }
  }
  return summaries.values.map((summary) => summary.build()).toList();
}

String _renderMarkdown({
  required List<_SectionSummary> sections,
  required int totalItemCount,
  required int checkedItemCount,
  required List<_ChecklistItem> uncheckedItems,
  required List<_ChecklistItem> checkedWithoutEvidence,
  required bool knownLimitationsReferenced,
  required bool supportedHardwareReferenced,
}) {
  final buffer = StringBuffer()
    ..writeln('# Public Release Checklist Audit')
    ..writeln()
    ..writeln('- Source checklist: `$_checklistPath`')
    ..writeln('- Checklist items: `$totalItemCount`')
    ..writeln('- Checked items: `$checkedItemCount`')
    ..writeln('- Unchecked items: `${uncheckedItems.length}`')
    ..writeln(
      '- Checked items without evidence notes: `${checkedWithoutEvidence.length}`',
    )
    ..writeln('- Known limitations referenced: `$knownLimitationsReferenced`')
    ..writeln(
      '- Supported hardware by platform referenced: `$supportedHardwareReferenced`',
    )
    ..writeln()
    ..writeln(
      'This audit is a repeatable status artifact for the release checklist. '
      'It does not provide final sign-off by itself, and unchecked items remain '
      'release blockers.',
    )
    ..writeln()
    ..writeln('## Sections')
    ..writeln()
    ..writeln(
        '| Section | Total | Checked | Unchecked | Checked without evidence |')
    ..writeln('| --- | ---: | ---: | ---: | ---: |');

  for (final section in sections) {
    buffer.writeln(
      '| ${_escapeTable(section.name)} | ${section.total} | '
      '${section.checked} | ${section.unchecked} | '
      '${section.checkedWithoutEvidence} |',
    );
  }

  if (checkedWithoutEvidence.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Checked Without Evidence')
      ..writeln();
    for (final item in checkedWithoutEvidence.take(80)) {
      buffer.writeln(
        '- `line ${item.lineNumber}` `${item.section}`: ${item.text}',
      );
    }
    if (checkedWithoutEvidence.length > 80) {
      buffer.writeln('- ... ${checkedWithoutEvidence.length - 80} more.');
    }
  }

  if (uncheckedItems.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## First Unchecked Items')
      ..writeln();
    for (final item in uncheckedItems.take(80)) {
      buffer.writeln(
        '- `line ${item.lineNumber}` `${item.section}`: ${item.text}',
      );
    }
    if (uncheckedItems.length > 80) {
      buffer.writeln('- ... ${uncheckedItems.length - 80} more.');
    }
  }

  return buffer.toString();
}

String _escapeTable(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

class _ChecklistItemBuilder {
  final String section;
  final bool checked;
  final String text;
  final int lineNumber;
  final List<String> evidenceLines = [];

  _ChecklistItemBuilder({
    required this.section,
    required this.checked,
    required this.text,
    required this.lineNumber,
  });

  _ChecklistItem build() {
    final evidenceText = evidenceLines.join('\n').trim();
    return _ChecklistItem(
      section: section,
      checked: checked,
      text: text,
      lineNumber: lineNumber,
      hasEvidence:
          evidenceText.isNotEmpty && _evidencePattern.hasMatch(evidenceText),
    );
  }
}

class _ChecklistItem {
  final String section;
  final bool checked;
  final String text;
  final int lineNumber;
  final bool hasEvidence;

  const _ChecklistItem({
    required this.section,
    required this.checked,
    required this.text,
    required this.lineNumber,
    required this.hasEvidence,
  });

  Map<String, Object?> toJson() => {
        'section': section,
        'checked': checked,
        'text': text,
        'lineNumber': lineNumber,
        'hasEvidence': hasEvidence,
      };
}

class _SectionSummaryBuilder {
  final String name;
  var total = 0;
  var checked = 0;
  var unchecked = 0;
  var checkedWithoutEvidence = 0;

  _SectionSummaryBuilder(this.name);

  _SectionSummary build() => _SectionSummary(
        name: name,
        total: total,
        checked: checked,
        unchecked: unchecked,
        checkedWithoutEvidence: checkedWithoutEvidence,
      );
}

class _SectionSummary {
  final String name;
  final int total;
  final int checked;
  final int unchecked;
  final int checkedWithoutEvidence;

  const _SectionSummary({
    required this.name,
    required this.total,
    required this.checked,
    required this.unchecked,
    required this.checkedWithoutEvidence,
  });

  Map<String, Object?> toJson() => {
        'section': name,
        'total': total,
        'checked': checked,
        'unchecked': unchecked,
        'checkedWithoutEvidence': checkedWithoutEvidence,
      };
}
