import 'dart:convert';
import 'dart:io';

const _defaultRegisterPath =
    'docs/production-readiness/behavioral-audit-register.md';
const _defaultReportPath = '.behavioral_audit_hits.txt';

// Focus the first behavioral gate on high-risk files that previously carried
// silent fallbacks, guessed defaults, and simulated runtime paths.
const _targetFiles = <String>[
  'packages/nightshade_core/lib/src/services/science/science_processing_service.dart',
  'packages/nightshade_core/lib/src/providers/framing_provider.dart',
  'packages/nightshade_core/lib/src/services/profile_service.dart',
  'packages/nightshade_core/lib/src/providers/science_provider.dart',
  'packages/nightshade_core/lib/src/providers/sequence_provider.dart',
  'packages/nightshade_core/lib/src/services/science/default_science_backend.dart',
  'packages/nightshade_app/lib/screens/analytics/widgets/image_thumbnail_strip.dart',
  'packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart',
  'packages/nightshade_app/lib/screens/settings/settings_screen.dart',
  'native/nightshade_native/bridge/src/ascom_wrapper_filterwheel.rs',
  'native/nightshade_native/native/src/vendor/moravian.rs',
  'native/nightshade_native/sequencer/src/flat_wizard.rs',
  'native/nightshade_native/sequencer/src/temperature_compensation.rs',
  'native/nightshade_native/sequencer/src/triggers.rs',
  'native/nightshade_native/sequencer/src/instructions.rs',
  'native/nightshade_native/sequencer/src/device_ops.rs',
  'native/nightshade_native/native/src/vendor/zwo.rs',
  'native/nightshade_native/sequencer/src/autofocus.rs',
];

class _Rule {
  final String id;
  final RegExp regex;
  final String summary;
  final bool highRisk;

  const _Rule(
      {required this.id,
      required this.regex,
      required this.summary,
      this.highRisk = true});
}

final _rules = <_Rule>[
  _Rule(
    id: 'empty_catch',
    regex: RegExp(r'catch\s*\(_\s*\)'),
    summary: 'Silent catch swallows runtime failures.',
  ),
  _Rule(
    id: 'guessed_now_timestamp',
    regex: RegExp(r'\?\?\s*DateTime\.now\(\)'),
    summary: 'Guessed current time used as metadata fallback.',
  ),
  _Rule(
    id: 'guessed_numeric_fallback',
    regex: RegExp(r'\?\?\s*1\.0\b|return\s+3\.5\b'),
    summary: 'Numeric fallback may hide missing required data.',
  ),
  _Rule(
    id: 'unwrap_or_literal',
    regex: RegExp(r'unwrap_or\((?:-?\d+(?:\.\d+)?|true|false)\)'),
    summary: 'Literal unwrap_or may silently coerce unknown state.',
  ),
  _Rule(
    id: 'hardcoded_location_fallback',
    regex: RegExp(r'45\.0,\s*-75\.0'),
    summary: 'Hardcoded observer location fallback.',
  ),
  _Rule(
    id: 'nonconvergence_best_guess',
    regex: RegExp(r'best guess|may not be optimal', caseSensitive: false),
    summary: 'Non-convergence treated as success.',
  ),
  _Rule(
    id: 'simulated_runtime_path',
    regex: RegExp(
        r'NullDeviceOps|simulated devices|useSimulationMode|sequencerSetSimulationMode'),
    summary: 'Simulation path present in runtime code.',
    highRisk: false,
  ),
  _Rule(
    id: 'unimplemented_behavior',
    regex: RegExp(r'not yet implemented|not implemented', caseSensitive: false),
    summary: 'Runtime behavior not implemented.',
  ),
];

void main(List<String> args) {
  final registerPath = _argValue(args, '--register') ?? _defaultRegisterPath;
  final reportPath = _argValue(args, '--report') ?? _defaultReportPath;
  final failOnUnregistered = args.contains('--fail-on-unregistered');
  final failOnOpen = args.contains('--fail-on-open');
  final failOnAnyHighRisk = args.contains('--fail-on-any-highrisk');

  final findings = <String, String>{};
  final highRisk = <String>{};

  for (final filePath in _targetFiles) {
    final file = File(filePath);
    if (!file.existsSync()) {
      continue;
    }
    final lines = _readLinesSafe(file);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final rule in _rules) {
        if (!rule.regex.hasMatch(line)) {
          continue;
        }
        final key = '$filePath:${i + 1}:${rule.id}';
        findings[key] = line.trimRight();
        if (rule.highRisk) {
          highRisk.add(key);
        }
      }
    }
  }

  final sortedKeys = findings.keys.toList()..sort();
  final reportLines = <String>[];
  for (final key in sortedKeys) {
    reportLines.add('$key:${findings[key]}');
  }
  File(reportPath).writeAsStringSync('${reportLines.join('\n')}\n');

  stdout.writeln('Behavioral audit complete.');
  stdout.writeln('Findings: ${sortedKeys.length} -> $reportPath');
  stdout.writeln('High-risk findings: ${highRisk.length}');

  final register = _readRegister(registerPath);
  final unregistered = <String>[];
  final open = <String>[];
  for (final key in sortedKeys) {
    final status = register[key];
    if (status == null) {
      unregistered.add(key);
      continue;
    }
    if (!_isClosedStatus(status)) {
      open.add('$key ($status)');
    }
  }

  if (unregistered.isNotEmpty) {
    stderr.writeln('Unregistered behavioral findings (${unregistered.length}):');
    for (final entry in unregistered) {
      stderr.writeln('  $entry');
    }
    if (failOnUnregistered) {
      exit(1);
    }
  }

  if (open.isNotEmpty) {
    stderr.writeln('Open behavioral findings (${open.length}):');
    for (final entry in open) {
      stderr.writeln('  $entry');
    }
    if (failOnOpen) {
      exit(1);
    }
  }

  if (failOnAnyHighRisk && highRisk.isNotEmpty) {
    stderr.writeln('High-risk behavioral findings remain.');
    exit(1);
  }
}

String? _argValue(List<String> args, String key) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == key && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  return null;
}

Map<String, String> _readRegister(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return const <String, String>{};
  }

  final out = <String, String>{};
  final lines = file.readAsLinesSync();
  for (final raw in lines) {
    final line = raw.trim();
    if (!line.startsWith('|')) {
      continue;
    }
    if (line.contains('finding_key') || line.contains('---')) {
      continue;
    }
    final cols = line
        .split('|')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (cols.length < 2) {
      continue;
    }
    final key = cols[0];
    final status = cols[1].toLowerCase();
    out[key] = status;
  }
  return out;
}

bool _isClosedStatus(String status) {
  switch (status) {
    case 'done':
    case 'accepted_modeled_approximation':
    case 'explicit_unsupported':
    case 'remove':
      return true;
    default:
      return false;
  }
}

List<String> _readLinesSafe(File file) {
  try {
    return const LineSplitter().convert(file.readAsStringSync());
  } catch (_) {
    try {
      final bytes = file.readAsBytesSync();
      return const LineSplitter()
          .convert(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return const <String>[];
    }
  }
}
