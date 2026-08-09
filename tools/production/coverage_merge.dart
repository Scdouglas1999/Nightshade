// Folds a sweep's results back into the coverage ledger.
//
// A sweep is only worth running if its coverage survives it. This reads the
// per-area result files a sweep writes into `reports/coverage/swept/`, marks the
// units each agent actually visited, and records why the rest were not reached.
// `coverage_inventory.dart --report` then answers "what has never been looked
// at?" -- which is the question no previous audit of this app could answer.
//
// USAGE
//   dart run tools/production/coverage_merge.dart reports/coverage/swept/*.json
import 'dart:convert';
import 'dart:io';

const _outDir = 'reports/coverage';

void main(List<String> args) {
  final root = _findRepoRoot();
  if (root == null) {
    stderr.writeln('error: could not locate repo root (no melos.yaml found)');
    exit(2);
  }

  final statusFile = File('$root/$_outDir/status.json');
  final status = statusFile.existsSync()
      ? (jsonDecode(statusFile.readAsStringSync()) as Map)
            .cast<String, dynamic>()
      : <String, dynamic>{};

  var visited = 0, unreached = 0;
  for (final path in args) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('skip: $path does not exist');
      continue;
    }
    final data = (jsonDecode(f.readAsStringSync()) as Map)
        .cast<String, dynamic>();
    final area = data['area'] as String? ?? f.uri.pathSegments.last;

    for (final unit in (data['units_visited'] as List? ?? const [])) {
      status['$unit'] = {'state': 'visited', 'by': area};
      visited++;
    }
    // An unreached unit is recorded, not dropped. Silently omitting it is how a
    // partial sweep gets read as a complete one.
    for (final u in (data['units_unreached'] as List? ?? const [])) {
      final m = (u as Map).cast<String, dynamic>();
      status['${m['unit']}'] = {
        'state': 'unreached',
        'by': area,
        'why': m['why'],
      };
      unreached++;
    }
  }

  statusFile
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(status));
  stdout.writeln(
    'merged: $visited visited, $unreached unreached -> $_outDir/status.json',
  );
}

String? _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/melos.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
