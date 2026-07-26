// Self-test runner for narrative_comment_audit.dart.
//
// Spawns the audit tool in --self-test mode against a throwaway temp dir and
// fails (non-zero exit) if any classifier or walk/allowlist case regresses.
// Kept as a separate entrypoint so CI / melos can run it the same way as the
// other `*_self_test.dart` tools in this directory.

import 'dart:io';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('narrative_audit_st_');
  try {
    final result = Process.runSync('dart', <String>[
      'run',
      'tools/production/narrative_comment_audit.dart',
      '--self-test',
      tmp.path,
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln('narrative_comment_audit self-test FAILED');
      exit(result.exitCode);
    }
  } finally {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  }
}
