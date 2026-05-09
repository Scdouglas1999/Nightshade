import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final repoRoot = Directory.current;
  final script =
      File('${repoRoot.path}/tools/production/oversized_file_audit.dart');
  if (!script.existsSync()) {
    throw StateError('Oversized file audit script not found: ${script.path}');
  }

  final temp = await Directory.systemTemp.createTemp(
    'nightshade_oversized_file_audit_self_test_',
  );
  try {
    await _writeFixture(temp);

    final jsonPath =
        '${temp.path}/docs/production-readiness/oversized-file-audit.json';
    final markdownPath =
        '${temp.path}/docs/production-readiness/oversized-file-audit.md';
    final result = await Process.run(
      'dart',
      [
        script.path,
        '--root',
        temp.path,
        '--warning-lines',
        '5',
        '--critical-lines',
        '8',
        '--json-out',
        jsonPath,
        '--md-out',
        markdownPath,
      ],
      workingDirectory: repoRoot.path,
      runInShell: Platform.isWindows,
    );
    _expect(result.exitCode == 0, 'audit should pass without fail flag');

    final report =
        jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, dynamic>;
    _expect(
        report['scannedFileCount'] == 4, 'should scan 4 hand-authored files');
    _expect(report['warningFileCount'] == 2, 'should report 2 warning files');
    _expect(report['criticalFileCount'] == 1, 'should report 1 critical file');
    _expect(
      report['prioritySplitCandidateCount'] == 1,
      'should report 1 priority split candidate',
    );

    final criticalFiles =
        (report['criticalFiles'] as List).cast<Map<String, dynamic>>();
    _expect(
      criticalFiles.single['path'] ==
          'packages/example/lib/src/critical_file.dart',
      'critical file path should be normalized relative path',
    );

    final largestFiles =
        (report['largestFiles'] as List).cast<Map<String, dynamic>>();
    _expect(
      largestFiles.every((entry) =>
          !entry['path'].toString().contains('.g.dart') &&
          !entry['path'].toString().contains('vendor')),
      'generated and vendor files should be excluded',
    );
    final priorityCandidates = (report['prioritySplitCandidates'] as List)
        .cast<Map<String, dynamic>>();
    _expect(
      priorityCandidates.single['path'] ==
              'packages/nightshade_core/lib/src/backend/network_backend.dart' &&
          priorityCandidates.single['reason'].toString().contains(
                'NetworkBackend',
              ),
      'priority split candidates should preserve backend split rationale',
    );

    final failing = await Process.run(
      'dart',
      [
        script.path,
        '--root',
        temp.path,
        '--warning-lines',
        '5',
        '--critical-lines',
        '8',
        '--json-out',
        jsonPath,
        '--md-out',
        markdownPath,
        '--fail-on-critical',
      ],
      workingDirectory: repoRoot.path,
      runInShell: Platform.isWindows,
    );
    _expect(
      failing.exitCode != 0,
      'audit should fail with --fail-on-critical when critical files exist',
    );

    stdout.writeln('Oversized file audit self-test passed.');
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<void> _writeFixture(Directory root) async {
  await _writeLines(
    root,
    'packages/example/lib/src/small.dart',
    3,
  );
  await _writeLines(
    root,
    'packages/example/lib/src/warning_file.dart',
    5,
  );
  await _writeLines(
    root,
    'packages/example/lib/src/critical_file.dart',
    8,
  );
  await _writeLines(
    root,
    'packages/nightshade_core/lib/src/backend/network_backend.dart',
    6,
  );
  await _writeLines(
    root,
    'packages/example/lib/src/critical_file.g.dart',
    20,
  );
  await _writeLines(
    root,
    'packages/example/lib/vendor/critical_vendor.dart',
    20,
  );
}

Future<void> _writeLines(
  Directory root,
  String relativePath,
  int lineCount,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    List.generate(lineCount, (index) => 'void f$index() {}').join('\n'),
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
