import 'dart:convert';
import 'dart:io';

const _defaultJsonOutputPath =
    'docs/production-readiness/headless-response-helper-audit.json';
const _defaultMarkdownOutputPath =
    'docs/production-readiness/headless-response-helper-audit.md';

const _helperPath = 'apps/desktop/lib/headless_api/response_helpers.dart';
const _testPath = 'apps/desktop/test/headless_api/response_helpers_test.dart';

const _requiredHelperText = [
  'const jsonContentType',
  'const jsonResponseHeaders',
  'Response jsonResponse(',
  'Response jsonOk(',
  'Response jsonCreated(',
  'Response jsonBadRequest(',
  'Response jsonUnauthorized(',
  'Response jsonForbidden(',
  'Response jsonNotFound(',
  'Response jsonConflict(',
  'Response jsonTooLarge(',
  'Response jsonUpgradeRequired(',
  'Response jsonRateLimited(',
  'Response jsonInternalServerError(',
  'Response jsonNotImplemented(',
  'Response contentResponse(',
  'Response attachmentResponse(',
  'jsonEncode(body)',
];

const _requiredTestText = [
  'jsonOk encodes JSON',
  'jsonRateLimited',
  'jsonNotImplemented encodes 501 JSON',
  'contentResponse applies content type and length',
  'attachmentResponse applies safe disposition and length',
  'attachmentDisposition',
];

const _scanRoots = [
  'apps/desktop/lib/headless_api_server.dart',
  'apps/desktop/lib/headless_api/handlers',
];

Future<void> main(List<String> args) async {
  final root = Directory(_argValue(args, '--root') ?? Directory.current.path);
  final jsonOut = _argValue(args, '--json-out') ?? _defaultJsonOutputPath;
  final markdownOut = _argValue(args, '--md-out') ?? _defaultMarkdownOutputPath;
  final failOnIssue = !args.contains('--no-fail-on-issue');

  final helper = _auditFile(
    root: root,
    path: _helperPath,
    requiredText: _requiredHelperText,
  );
  final tests = _auditFile(
    root: root,
    path: _testPath,
    requiredText: _requiredTestText,
  );
  final usage = _scanUsage(root);
  final issues = [
    ...helper.issues,
    ...tests.issues,
    ...usage.issues,
  ];
  final passed = issues.isEmpty;
  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'passed': passed,
    'issueCount': issues.length,
    'issues': issues,
    'helper': helper.toJson(),
    'tests': tests.toJson(),
    'usage': usage.toJson(),
    'policy':
        'Headless JSON, binary, and attachment responses must have typed helpers available and unit-tested before broad route migration. Raw shelf Response usage is only allowed in the headless server for static dashboard assets and empty CORS preflight behavior; unclassified raw Response usage or handler-level raw Response usage is release-blocking.',
  };

  await File(jsonOut).parent.create(recursive: true);
  await File(jsonOut).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  await File(markdownOut).parent.create(recursive: true);
  await File(markdownOut).writeAsString(_renderMarkdown(
    passed: passed,
    issues: issues,
    helper: helper,
    tests: tests,
    usage: usage,
  ));

  stdout.writeln('Headless response helper audit complete.');
  stdout.writeln('Passed: $passed');
  stdout.writeln('Issues: ${issues.length}');
  stdout.writeln('Raw Response calls: ${usage.rawResponseCallCount}');
  stdout.writeln(
      'Intentional raw Response calls: ${usage.intentionalRawResponseCallCount}');
  stdout.writeln(
      'Unclassified raw Response calls: ${usage.unclassifiedRawResponseCallCount}');
  stdout.writeln('JSON content-type mentions: ${usage.jsonContentTypeCount}');
  stdout.writeln('JSON helper imports: ${usage.helperImportCount}');
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

_UsageAudit _scanUsage(Directory root) {
  final files = <File>[];
  for (final scanRoot in _scanRoots) {
    final entity = FileSystemEntity.typeSync('${root.path}/$scanRoot');
    if (entity == FileSystemEntityType.file) {
      files.add(File('${root.path}/$scanRoot'));
    } else if (entity == FileSystemEntityType.directory) {
      files.addAll(
        Directory('${root.path}/$scanRoot')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      );
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final rawResponsePattern = RegExp(r'\bResponse\.(ok|badRequest|notFound|'
      r'internalServerError|forbidden|unauthorized|movedPermanently)\b|'
      r'\bResponse\s*\(');
  final helperCallPattern = RegExp(r'\bjson(Ok|Created|BadRequest|'
      r'Unauthorized|Forbidden|NotFound|Conflict|TooLarge|UpgradeRequired|'
      r'RateLimited|InternalServerError|NotImplemented|Response)\s*\(|'
      r'\b(contentResponse|attachmentResponse)\s*\(');
  final perFile = <Map<String, Object?>>[];
  var rawResponseCallCount = 0;
  var intentionalRawResponseCallCount = 0;
  var unclassifiedRawResponseCallCount = 0;
  var jsonContentTypeCount = 0;
  var helperImportCount = 0;
  var helperCallCount = 0;

  for (final file in files) {
    final path = _relative(root, file);
    final text = file.readAsStringSync();
    final rawResponseMatches = rawResponsePattern.allMatches(text).toList();
    final rawResponses = rawResponseMatches.length;
    final reasons = <String>[];
    for (final match in rawResponseMatches) {
      final snippet = _rawResponseSnippet(text, match.start);
      final reason = _intentionalRawResponseReason(path, snippet);
      if (reason != null) {
        reasons.add(reason);
      }
    }
    final intentionalRawResponses = reasons.length;
    final unclassifiedRawResponses = rawResponses - intentionalRawResponses;
    final contentTypes = RegExp('application/json').allMatches(text).length;
    final imports = RegExp("response_helpers\\.dart").allMatches(text).length;
    final helperCalls = helperCallPattern.allMatches(text).length;
    rawResponseCallCount += rawResponses;
    intentionalRawResponseCallCount += intentionalRawResponses;
    unclassifiedRawResponseCallCount += unclassifiedRawResponses;
    jsonContentTypeCount += contentTypes;
    helperImportCount += imports;
    helperCallCount += helperCalls;
    if (rawResponses > 0 ||
        contentTypes > 0 ||
        imports > 0 ||
        helperCalls > 0) {
      perFile.add({
        'path': path,
        'rawResponseCalls': rawResponses,
        'intentionalRawResponseCalls': intentionalRawResponses,
        'unclassifiedRawResponseCalls': unclassifiedRawResponses,
        'intentionalRawResponseReasons': reasons,
        'jsonContentTypeMentions': contentTypes,
        'helperImports': imports,
        'helperCalls': helperCalls,
      });
    }
  }

  return _UsageAudit(
    scannedFileCount: files.length,
    rawResponseCallCount: rawResponseCallCount,
    intentionalRawResponseCallCount: intentionalRawResponseCallCount,
    unclassifiedRawResponseCallCount: unclassifiedRawResponseCallCount,
    jsonContentTypeCount: jsonContentTypeCount,
    helperImportCount: helperImportCount,
    helperCallCount: helperCallCount,
    files: perFile,
  );
}

String _rawResponseSnippet(String text, int start) {
  final end = text.indexOf('\n    }', start);
  if (end == -1) {
    final fallbackEnd = text.indexOf(';', start);
    return text.substring(start, fallbackEnd == -1 ? text.length : fallbackEnd);
  }
  return text.substring(start, end);
}

String? _intentionalRawResponseReason(String path, String snippet) {
  if (path == 'apps/desktop/lib/headless_api_server.dart' &&
      snippet.contains('_getMimeType(filePath)')) {
    return 'dashboard static asset byte response';
  }
  if (path == 'apps/desktop/lib/headless_api_server.dart' &&
      snippet.contains("Response.ok('', headers: corsHeaders)")) {
    return 'empty CORS preflight response';
  }
  if (snippet.contains('content-disposition') ||
      snippet.contains('attachmentDisposition(')) {
    return 'download/export attachment response';
  }
  if (snippet.contains("'content-type': 'image/") ||
      snippet.contains('"content-type": "image/')) {
    return 'image byte response';
  }
  if (snippet.contains('application/octet-stream')) {
    return 'binary byte response';
  }
  if (snippet.contains('file.openRead()')) {
    return 'file stream response';
  }
  return null;
}

String _renderMarkdown({
  required bool passed,
  required List<String> issues,
  required _FileAudit helper,
  required _FileAudit tests,
  required _UsageAudit usage,
}) {
  final buffer = StringBuffer()
    ..writeln('# Headless Response Helper Audit')
    ..writeln()
    ..writeln('- Passed: `$passed`')
    ..writeln('- Issues: `${issues.length}`')
    ..writeln('- Scanned files: `${usage.scannedFileCount}`')
    ..writeln('- Raw `Response.*` calls: `${usage.rawResponseCallCount}`')
    ..writeln(
        '- Intentional raw `Response.*` calls: `${usage.intentionalRawResponseCallCount}`')
    ..writeln(
        '- Unclassified raw `Response.*` calls: `${usage.unclassifiedRawResponseCallCount}`')
    ..writeln('- JSON content-type mentions: `${usage.jsonContentTypeCount}`')
    ..writeln('- JSON helper imports: `${usage.helperImportCount}`')
    ..writeln('- JSON helper calls: `${usage.helperCallCount}`')
    ..writeln()
    ..writeln(
      'This audit proves typed response helpers exist and are covered by unit tests. Raw `Response.*` route calls are allowed only in the headless server for static dashboard assets and empty CORS preflight behavior.',
    )
    ..writeln()
    ..writeln('## Required Files')
    ..writeln()
    ..writeln('| File | Exists | Missing required text |')
    ..writeln('| --- | --- | ---: |')
    ..writeln(
      '| `${helper.path}` | `${helper.exists}` | `${helper.missingText.length}` |',
    )
    ..writeln(
      '| `${tests.path}` | `${tests.exists}` | `${tests.missingText.length}` |',
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

  final rawResponseFiles = usage.files
      .where((file) => (file['rawResponseCalls'] as int? ?? 0) > 0)
      .toList();
  if (rawResponseFiles.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Classified Raw Responses')
      ..writeln()
      ..writeln('| File | Raw | Intentional | Unclassified | Reasons |')
      ..writeln('| --- | ---: | ---: | ---: | --- |');
    for (final file in rawResponseFiles) {
      final reasons =
          (file['intentionalRawResponseReasons'] as List? ?? const <Object?>[])
              .map((reason) => reason.toString())
              .toSet()
              .join('<br>');
      buffer.writeln(
        '| `${file['path']}` | `${file['rawResponseCalls']}` | '
        '`${file['intentionalRawResponseCalls']}` | '
        '`${file['unclassifiedRawResponseCalls']}` | '
        '${reasons.isEmpty ? 'none' : reasons} |',
      );
    }
  }

  return buffer.toString();
}

String _relative(Directory root, File file) {
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final filePath = file.absolute.path.replaceAll('\\', '/');
  final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  return filePath.startsWith(prefix)
      ? filePath.substring(prefix.length)
      : filePath;
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
        'passed': exists && missingText.isEmpty,
      };
}

class _UsageAudit {
  final int scannedFileCount;
  final int rawResponseCallCount;
  final int intentionalRawResponseCallCount;
  final int unclassifiedRawResponseCallCount;
  final int jsonContentTypeCount;
  final int helperImportCount;
  final int helperCallCount;
  final List<Map<String, Object?>> files;

  const _UsageAudit({
    required this.scannedFileCount,
    required this.rawResponseCallCount,
    required this.intentionalRawResponseCallCount,
    required this.unclassifiedRawResponseCallCount,
    required this.jsonContentTypeCount,
    required this.helperImportCount,
    required this.helperCallCount,
    required this.files,
  });

  List<String> get issues {
    final issues = <String>[];
    if (unclassifiedRawResponseCallCount != 0) {
      issues.add(
        'Unclassified raw headless Response calls: '
        '$unclassifiedRawResponseCallCount.',
      );
    }
    for (final file in files) {
      final path = file['path']?.toString() ?? '';
      final rawResponses = (file['rawResponseCalls'] as int?) ?? 0;
      if (rawResponses > 0 &&
          path.startsWith('apps/desktop/lib/headless_api/handlers/')) {
        issues.add(
          'Headless handler raw Response calls must use response_helpers.dart: '
          '$path has $rawResponses.',
        );
      }
    }
    return issues;
  }

  Map<String, Object?> toJson() => {
        'scannedFileCount': scannedFileCount,
        'rawResponseCallCount': rawResponseCallCount,
        'intentionalRawResponseCallCount': intentionalRawResponseCallCount,
        'unclassifiedRawResponseCallCount': unclassifiedRawResponseCallCount,
        'jsonContentTypeCount': jsonContentTypeCount,
        'helperImportCount': helperImportCount,
        'helperCallCount': helperCallCount,
        'files': files,
      };
}
