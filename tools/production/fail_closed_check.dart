import 'dart:io';

class _Rule {
  final String description;
  final RegExp pattern;
  final List<String> files;

  const _Rule({
    required this.description,
    required this.pattern,
    required this.files,
  });
}

final _rules = <_Rule>[
  _Rule(
    description: 'Disallow UnimplementedError in production backend paths',
    pattern: RegExp(r'UnimplementedError\('),
    files: <String>[
      'packages/nightshade_bridge/lib/src/bridge_stub.dart',
      'packages/nightshade_core/lib/src/backend/ffi_backend.dart',
      'packages/nightshade_core/lib/src/backend/network_backend.dart',
    ],
  ),
  _Rule(
    description: 'Disallow sequencer checkpoint no-op stub logging',
    pattern: RegExp(r'sequencer.*no-op in stub mode', caseSensitive: false),
    files: <String>[
      'packages/nightshade_bridge/lib/src/bridge_stub.dart',
    ],
  ),
  _Rule(
    description: 'Disconnected backend focuserHalt must not be a no-op',
    pattern: RegExp(
      r'Future<void>\s+focuserHalt\s*\([^)]*\)\s*async\s*\{\s*\}',
      multiLine: true,
    ),
    files: <String>[
      'packages/nightshade_core/lib/src/backend/disconnected_backend.dart',
    ],
  ),
  _Rule(
    description: 'Disconnected backend autofocusCancel must not be a no-op',
    pattern: RegExp(
      r'Future<void>\s+autofocusCancel\s*\([^)]*\)\s*async\s*\{\s*\}',
      multiLine: true,
    ),
    files: <String>[
      'packages/nightshade_core/lib/src/backend/disconnected_backend.dart',
    ],
  ),
  _Rule(
    description:
        'Targets DAO must not return all targets for observability filtering',
    pattern: RegExp(r'For now,\s*return all targets', caseSensitive: false),
    files: <String>[
      'packages/nightshade_core/lib/src/database/daos/targets_dao.dart',
    ],
  ),
];

void main() {
  final violations = <String>[];

  for (final rule in _rules) {
    for (final path in rule.files) {
      final file = File(path);
      if (!file.existsSync()) {
        violations.add('[MISSING FILE] ${rule.description}: $path');
        continue;
      }
      final content = file.readAsStringSync();
      final matches = rule.pattern.allMatches(content).toList();
      if (matches.isEmpty) {
        continue;
      }

      for (final match in matches) {
        final line = _lineFromOffset(content, match.start);
        violations.add('[${rule.description}] $path:$line');
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('Fail-closed policy checks passed.');
    return;
  }

  stderr.writeln('Fail-closed policy violations detected:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exit(1);
}

int _lineFromOffset(String content, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < content.length; i++) {
    if (content.codeUnitAt(i) == 10) {
      line++;
    }
  }
  return line;
}
