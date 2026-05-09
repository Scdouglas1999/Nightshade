import 'dart:convert';
import 'dart:io';

const _jsonOutputPath =
    'docs/production-readiness/public-release-self-tests.json';
const _markdownOutputPath =
    'docs/production-readiness/public-release-self-tests.md';

const _selfTests = [
  'tools/production/analyzer_rollup_self_test.dart',
  'tools/production/public_release_gate_self_test.dart',
  'tools/production/public_release_blocker_inputs_self_test.dart',
  'tools/production/public_release_external_evidence_self_test.dart',
  'tools/production/public_release_completion_audit_self_test.dart',
  'tools/production/public_release_owner_checklist_self_test.dart',
  'tools/production/public_release_checklist_audit_self_test.dart',
  'tools/production/placeholder_audit_self_test.dart',
  'tools/production/fail_closed_check_self_test.dart',
  'tools/production/release_staging_pr_plan_self_test.dart',
  'tools/production/release_pr_owner_matrix_self_test.dart',
  'tools/production/linux_release_package_metadata_self_test.dart',
  'tools/production/linux_release_workflow_audit_self_test.dart',
  'tools/production/oversized_file_audit_self_test.dart',
  'tools/production/dependency_hygiene_self_test.dart',
  'tools/production/developer_quality_audit_self_test.dart',
  'tools/production/docs_link_audit_self_test.dart',
  'tools/production/headless_api_contract_audit_self_test.dart',
  'tools/production/headless_route_policy_audit_self_test.dart',
  'tools/production/headless_response_helper_audit_self_test.dart',
  'tools/production/migration_regression_audit_self_test.dart',
  'tools/production/release_docs_audit_self_test.dart',
  'tools/production/platform_capability_audit_self_test.dart',
  'tools/production/ui_consistency_audit_self_test.dart',
  'tools/production/windows_bundle_audit_self_test.dart',
];

Future<void> main() async {
  final failures = <String>[];
  final results = <_SelfTestResult>[];
  final startedAt = DateTime.now().toUtc();
  final aggregateWatch = Stopwatch()..start();

  for (final script in _selfTests) {
    stdout.writeln('Running $script');
    final watch = Stopwatch()..start();
    final result = await Process.run(
      'dart',
      ['run', script],
      runInShell: Platform.isWindows,
    );
    watch.stop();
    stdout.write(result.stdout);
    stderr.write(result.stderr);

    results.add(_SelfTestResult(
      script: script,
      exitCode: result.exitCode,
      durationMillis: watch.elapsedMilliseconds,
      stdoutText: result.stdout.toString(),
      stderrText: result.stderr.toString(),
    ));

    if (result.exitCode != 0) {
      failures.add('$script exited with ${result.exitCode}');
    }
  }

  aggregateWatch.stop();
  await _writeReports(
    generatedAt: startedAt,
    durationMillis: aggregateWatch.elapsedMilliseconds,
    results: results,
  );

  if (failures.isNotEmpty) {
    stderr.writeln('Public release self-tests failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exit(1);
  }

  stdout.writeln('Public release self-tests passed (${_selfTests.length}).');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');
}

Future<void> _writeReports({
  required DateTime generatedAt,
  required int durationMillis,
  required List<_SelfTestResult> results,
}) async {
  final passedCount = results.where((result) => result.passed).length;
  final failedCount = results.length - passedCount;
  final report = {
    'generatedAt': generatedAt.toIso8601String(),
    'durationMillis': durationMillis,
    'passed': failedCount == 0 && results.length == _selfTests.length,
    'selfTestCount': results.length,
    'expectedSelfTestCount': _selfTests.length,
    'passedCount': passedCount,
    'failedCount': failedCount,
    'results': results.map((result) => result.toJson()).toList(),
  };

  await Directory('docs/production-readiness').create(recursive: true);
  await File(_jsonOutputPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File(_markdownOutputPath).writeAsString(_renderMarkdown(
    generatedAt: generatedAt,
    durationMillis: durationMillis,
    passedCount: passedCount,
    failedCount: failedCount,
    results: results,
  ));
}

String _renderMarkdown({
  required DateTime generatedAt,
  required int durationMillis,
  required int passedCount,
  required int failedCount,
  required List<_SelfTestResult> results,
}) {
  final buffer = StringBuffer()
    ..writeln('# Public Release Self-Tests')
    ..writeln()
    ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
    ..writeln('- Duration: `${durationMillis}ms`')
    ..writeln('- Self-tests: `${results.length}`')
    ..writeln('- Passed: `$passedCount`')
    ..writeln('- Failed: `$failedCount`')
    ..writeln()
    ..writeln(
      'This artifact records the aggregate verifier self-test run. It proves the release verifier scripts execute against temporary fixtures; it does not prove the public release itself is ready.',
    )
    ..writeln()
    ..writeln('| Script | Exit | Duration |')
    ..writeln('| --- | ---: | ---: |');

  for (final result in results) {
    buffer.writeln(
      '| `${result.script}` | ${result.exitCode} | ${result.durationMillis}ms |',
    );
  }

  return buffer.toString();
}

class _SelfTestResult {
  final String script;
  final int exitCode;
  final int durationMillis;
  final String stdoutText;
  final String stderrText;

  const _SelfTestResult({
    required this.script,
    required this.exitCode,
    required this.durationMillis,
    required this.stdoutText,
    required this.stderrText,
  });

  bool get passed => exitCode == 0;

  Map<String, Object?> toJson() => {
        'script': script,
        'exitCode': exitCode,
        'passed': passed,
        'durationMillis': durationMillis,
        'stdout': stdoutText,
        'stderr': stderrText,
      };
}
