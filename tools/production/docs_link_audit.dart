import 'dart:convert';
import 'dart:io';

const _docsRoot = 'docs';
const _jsonOutputPath = 'docs/production-readiness/docs-link-audit.json';
const _markdownOutputPath = 'docs/production-readiness/docs-link-audit.md';

final _markdownLinkPattern = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');

void main(List<String> args) {
  final failOnBroken = !args.contains('--no-fail-on-broken');
  final docsDir = Directory(_docsRoot);
  if (!docsDir.existsSync()) {
    stderr.writeln('Docs directory not found: $_docsRoot');
    exit(2);
  }

  final markdownFiles = docsDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.md'))
      .toList()
    ..sort((a, b) => _normalize(a.path).compareTo(_normalize(b.path)));

  final checkedLinks = <_CheckedLink>[];
  for (final file in markdownFiles) {
    checkedLinks.addAll(_linksForFile(file));
  }

  final localLinks =
      checkedLinks.where((link) => link.kind == _LinkKind.local).toList();
  final brokenLocalLinks = localLinks.where((link) => !link.exists).toList();

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'markdownFileCount': markdownFiles.length,
    'checkedLocalLinkCount': localLinks.length,
    'brokenLocalLinkCount': brokenLocalLinks.length,
    'externalOrSkippedLinkCount':
        checkedLinks.where((link) => link.kind != _LinkKind.local).length,
    'brokenLocalLinks': brokenLocalLinks.map((link) => link.toJson()).toList(),
  };

  File(_jsonOutputPath).parent.createSync(recursive: true);
  File(_jsonOutputPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File(_markdownOutputPath).parent.createSync(recursive: true);
  File(_markdownOutputPath).writeAsStringSync(_renderMarkdown(
    markdownFileCount: markdownFiles.length,
    localLinks: localLinks,
    brokenLocalLinks: brokenLocalLinks,
  ));

  stdout.writeln('Docs link audit complete.');
  stdout.writeln('Markdown files: ${markdownFiles.length}');
  stdout.writeln('Checked local links: ${localLinks.length}');
  stdout.writeln('Broken local links: ${brokenLocalLinks.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');

  if (failOnBroken && brokenLocalLinks.isNotEmpty) {
    exit(1);
  }
}

List<_CheckedLink> _linksForFile(File file) {
  final content = file.readAsStringSync();
  final links = <_CheckedLink>[];

  for (final match in _markdownLinkPattern.allMatches(content)) {
    final rawTarget = _stripWrappingAngles(match.group(1)!.trim());
    final normalizedTarget = rawTarget.split('#').first;
    if (normalizedTarget.trim().isEmpty) {
      links.add(_CheckedLink.skipped(file.path, rawTarget));
      continue;
    }
    if (_isExternalOrAbsolute(normalizedTarget)) {
      links.add(_CheckedLink.skipped(file.path, rawTarget));
      continue;
    }

    final decodedTarget = Uri.decodeComponent(normalizedTarget);
    final resolvedPath = File(
      '${file.parent.path}${Platform.pathSeparator}$decodedTarget',
    ).absolute.path;
    final normalizedResolvedPath = _normalizePathForPlatform(resolvedPath);
    final exists = File(normalizedResolvedPath).existsSync() ||
        Directory(normalizedResolvedPath).existsSync();

    links.add(_CheckedLink.local(
      sourcePath: file.path,
      target: rawTarget,
      resolvedPath: normalizedResolvedPath,
      exists: exists,
    ));
  }

  return links;
}

String _renderMarkdown({
  required int markdownFileCount,
  required List<_CheckedLink> localLinks,
  required List<_CheckedLink> brokenLocalLinks,
}) {
  final buffer = StringBuffer()
    ..writeln('# Docs Link Audit')
    ..writeln()
    ..writeln('- Markdown files: `$markdownFileCount`')
    ..writeln('- Checked local links: `${localLinks.length}`')
    ..writeln('- Broken local links: `${brokenLocalLinks.length}`')
    ..writeln()
    ..writeln(
      'This audit checks local Markdown link targets under `docs/`. It skips '
      'external URLs, mail links, anchors-only links, and absolute evidence '
      'links used by generated production-readiness reports.',
    )
    ..writeln();

  if (brokenLocalLinks.isEmpty) {
    buffer.writeln('No broken local docs links found.');
    return buffer.toString();
  }

  buffer
    ..writeln('## Broken Local Links')
    ..writeln()
    ..writeln('| Source | Link | Resolved target |')
    ..writeln('| --- | --- | --- |');
  for (final link in brokenLocalLinks) {
    buffer.writeln(
      '| `${link.sourcePath}` | `${link.target}` | `${link.resolvedPath}` |',
    );
  }

  return buffer.toString();
}

bool _isExternalOrAbsolute(String target) {
  final lower = target.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('file:') ||
      lower.startsWith('c:/') ||
      lower.startsWith('/c:/') ||
      lower.startsWith('#') ||
      target.startsWith('/');
}

String _stripWrappingAngles(String value) {
  if (value.startsWith('<') && value.endsWith('>') && value.length >= 2) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _normalizePathForPlatform(String path) {
  final uri = Uri.file(path);
  return File.fromUri(uri).absolute.path;
}

String _normalize(String path) => path.replaceAll('\\', '/');

enum _LinkKind { local, skipped }

class _CheckedLink {
  const _CheckedLink._({
    required this.kind,
    required this.sourcePath,
    required this.target,
    required this.resolvedPath,
    required this.exists,
  });

  factory _CheckedLink.local({
    required String sourcePath,
    required String target,
    required String resolvedPath,
    required bool exists,
  }) {
    return _CheckedLink._(
      kind: _LinkKind.local,
      sourcePath: _normalize(sourcePath),
      target: target,
      resolvedPath: _normalize(resolvedPath),
      exists: exists,
    );
  }

  factory _CheckedLink.skipped(String sourcePath, String target) {
    return _CheckedLink._(
      kind: _LinkKind.skipped,
      sourcePath: _normalize(sourcePath),
      target: target,
      resolvedPath: '',
      exists: false,
    );
  }

  final _LinkKind kind;
  final String sourcePath;
  final String target;
  final String resolvedPath;
  final bool exists;

  Map<String, Object?> toJson() => {
        'sourcePath': sourcePath,
        'target': target,
        'resolvedPath': resolvedPath,
        'exists': exists,
      };
}
