import 'dart:convert';
import 'dart:io';

const _defaultReportPath = '.ui_consistency_audit.txt';
const _jsonOutputPath = 'docs/production-readiness/ui-consistency-audit.json';

const _scanRoots = <String>[
  'apps/desktop/lib',
  'apps/mobile/lib',
  'packages/nightshade_app/lib',
  'packages/nightshade_ui/lib',
];

const _excludedSegments = <String>[
  '/.dart_tool/',
  '/build/',
  '/generated/',
  '.g.dart',
  '.freezed.dart',
  'frb_generated',
];

class _Rule {
  final String id;
  final RegExp pattern;
  final String summary;

  const _Rule({
    required this.id,
    required this.pattern,
    required this.summary,
  });
}

final _rules = <_Rule>[
  _Rule(
    id: 'raw_button_style',
    pattern: RegExp(
      r'(?:ElevatedButton|OutlinedButton|FilledButton|TextButton)\.styleFrom'
      r'|\bButtonStyle\s*\(',
    ),
    summary: 'Raw Material button styling should be justified or moved to '
        'NightshadeButton/theme defaults.',
  ),
  _Rule(
    id: 'raw_material_color',
    pattern: RegExp(
      r'\bColors\.(?:amber|black|blue|brown|cyan|green|grey|gray|orange|'
      r'pink|purple|red|teal|white|yellow)\b',
    ),
    summary: 'Raw Material color should be classified as semantic theme color '
        'or intentional image/overlay color.',
  ),
  _Rule(
    id: 'large_radius',
    pattern: RegExp(
      r'\b(?:BorderRadius|Radius)\.circular\((?:1[2-9]|[2-9]\d)(?:\.0)?\)',
    ),
    summary: 'Large radius on ordinary tool surfaces should be reduced or '
        'documented as intentional.',
  ),
  _Rule(
    id: 'empty_callback',
    pattern: RegExp(
      r'\b(?:onPressed|onTap|onChanged|onSubmitted|onDismiss|onLongPress)'
      r'\s*:\s*(?:\(\s*\)|\([^)]*\))\s*(?:async\s*)?\{\s*\}',
    ),
    summary: 'Empty UI callback can create a dead or misleading control.',
  ),
  _Rule(
    id: 'fake_callback',
    pattern: RegExp(
      r'\b(?:onPressed|onTap|onChanged|onSubmitted|onDismiss|onLongPress)'
      r'\s*:\s*(?:\(\s*\)|\([^)]*\))\s*(?:async\s*)?=>\s*'
      r'(?:null|Future\.value\(\)|void\s+0|\{\})',
    ),
    summary:
        'No-op arrow callback should be a disabled control or real action.',
  ),
];

void main(List<String> args) {
  final reportPath = _argValue(args, '--out') ?? _defaultReportPath;
  final failOnAny = args.contains('--fail-on-any');
  final maxFindings = int.tryParse(_argValue(args, '--max-findings') ?? '');

  final findings = <String>[];
  final countsByRule = <String, int>{};
  final rawColorClassifications = <String, int>{};

  for (final root in _scanRoots) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) {
      continue;
    }

    for (final entity
        in rootDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final path = _normalize(entity.path);
      if (!path.endsWith('.dart') || _shouldSkip(path)) {
        continue;
      }

      final lines = _readLinesSafe(entity);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final rule in _rules) {
          if (!rule.pattern.hasMatch(line)) {
            continue;
          }
          if (_isScopedOutFinding(path: path, ruleId: rule.id)) {
            continue;
          }
          countsByRule[rule.id] = (countsByRule[rule.id] ?? 0) + 1;
          if (rule.id == 'raw_material_color') {
            final classification = _classifyRawMaterialColor(
              path: path,
              line: line,
            );
            rawColorClassifications[classification] =
                (rawColorClassifications[classification] ?? 0) + 1;
            findings.add(
              '$path:${i + 1}:${rule.id}:$classification:${line.trimRight()}',
            );
          } else {
            findings.add('$path:${i + 1}:${rule.id}:${line.trimRight()}');
          }
        }
      }

      final stubCallbackFindings = _stubCallbackFindings(
        path: path,
        lines: lines,
      );
      if (stubCallbackFindings.isNotEmpty) {
        countsByRule['stub_callback'] =
            (countsByRule['stub_callback'] ?? 0) + stubCallbackFindings.length;
        findings.addAll(stubCallbackFindings);
      }
    }
  }

  final routeFindings = _headlessRouteFindings();
  findings.addAll(routeFindings);
  if (routeFindings.isNotEmpty) {
    countsByRule['headless_route_not_advertised'] = routeFindings.length;
  }

  final galleryEvidence = _designSystemGalleryEvidence();
  if (!(galleryEvidence['ready'] as bool)) {
    countsByRule['design_system_gallery_missing'] =
        (galleryEvidence['missing'] as List<String>).length;
    for (final missing in galleryEvidence['missing'] as List<String>) {
      findings.add(
        'packages/nightshade_ui/lib/src/widgets/design_system_gallery.dart:'
        '0:design_system_gallery_missing:$missing',
      );
    }
  }

  findings.sort();
  final report = _buildReport(
    findings: findings,
    countsByRule: countsByRule,
    rawColorClassifications: rawColorClassifications,
    galleryEvidence: galleryEvidence,
  );
  File(reportPath).parent.createSync(recursive: true);
  Directory('docs/production-readiness').createSync(recursive: true);
  File(reportPath).writeAsStringSync(report);
  File(_jsonOutputPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(
      _buildJsonReport(
        reportPath: reportPath,
        findings: findings,
        countsByRule: countsByRule,
        rawColorClassifications: rawColorClassifications,
        galleryEvidence: galleryEvidence,
      ),
    ),
  );

  stdout.writeln('UI consistency audit complete.');
  stdout.writeln('Findings: ${findings.length} -> $reportPath');
  stdout.writeln('JSON: $_jsonOutputPath');
  for (final entry in countsByRule.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    stdout.writeln('${entry.key}: ${entry.value}');
  }

  if (failOnAny && findings.isNotEmpty) {
    stderr.writeln('UI consistency findings remain.');
    exit(1);
  }

  if (maxFindings != null && findings.length > maxFindings) {
    stderr.writeln(
      'UI consistency findings exceed max-findings=$maxFindings.',
    );
    exit(1);
  }
}

Map<String, Object?> _buildJsonReport({
  required String reportPath,
  required List<String> findings,
  required Map<String, int> countsByRule,
  required Map<String, int> rawColorClassifications,
  required Map<String, Object?> galleryEvidence,
}) {
  final semanticRawColors =
      rawColorClassifications['semantic_theme_color'] ?? 0;
  final blockingRuleIds = <String>[
    'raw_button_style',
    'large_radius',
    'empty_callback',
    'fake_callback',
    'stub_callback',
    'headless_route_not_advertised',
    'design_system_gallery_missing',
  ];
  final blockingFindings = blockingRuleIds.fold<int>(
        0,
        (sum, id) => sum + (countsByRule[id] ?? 0),
      ) +
      semanticRawColors;

  return {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'textReportPath': reportPath,
    'scanRoots': _scanRoots,
    'findingCount': findings.length,
    'blockingFindingCount': blockingFindings,
    'countsByRule': countsByRule,
    'rawColorClassifications': rawColorClassifications,
    'designSystemGallery': galleryEvidence,
    'blockingRuleIds': blockingRuleIds,
    'policy':
        'Blocking findings are raw button styles, large ordinary radii, empty, fake, or stub callbacks, unadvertised headless routes, missing design-system gallery evidence, and semantic raw Material colors. Intentional image/overlay colors are report-only.',
  };
}

String _buildReport({
  required List<String> findings,
  required Map<String, int> countsByRule,
  required Map<String, int> rawColorClassifications,
  required Map<String, Object?> galleryEvidence,
}) {
  final buffer = StringBuffer()
    ..writeln('# UI Consistency Audit')
    ..writeln()
    ..writeln(
        'Generated by `dart run tools/production/ui_consistency_audit.dart`.')
    ..writeln()
    ..writeln('## Summary');

  if (countsByRule.isEmpty) {
    buffer.writeln('- No findings.');
  } else {
    for (final entry in countsByRule.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
  }

  if (rawColorClassifications.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Raw Material Color Classification');
    for (final entry in rawColorClassifications.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Design System Gallery')
    ..writeln('- Ready: ${galleryEvidence['ready']}')
    ..writeln('- Widget: ${galleryEvidence['widgetPath']}')
    ..writeln('- Test: ${galleryEvidence['testPath']}');
  final missingGalleryEvidence = galleryEvidence['missing'] as List<String>;
  if (missingGalleryEvidence.isEmpty) {
    buffer.writeln('- Missing evidence: none');
  } else {
    buffer.writeln('- Missing evidence:');
    for (final missing in missingGalleryEvidence) {
      buffer.writeln('  - $missing');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Findings');

  if (findings.isEmpty) {
    buffer.writeln('None.');
  } else {
    for (final finding in findings) {
      buffer.writeln(finding);
    }
  }

  return buffer.toString();
}

List<String> _stubCallbackFindings({
  required String path,
  required List<String> lines,
}) {
  final content = lines.join('\n');
  final callbackRegex = RegExp(
    r'\b(?:onPressed|onTap|onChanged|onSubmitted|onDismiss|onLongPress)'
    r'\s*:\s*(?:\(\s*\)|\([^)]*\))\s*(?:async\s*)?\{([^{}]{0,240})\}',
    multiLine: true,
  );
  final findings = <String>[];
  for (final match in callbackRegex.allMatches(content)) {
    final body = match.group(1) ?? '';
    if (!_isStubCallbackBody(body)) {
      continue;
    }
    final lineNumber = _lineNumberAt(content, match.start);
    final snippet = lines[lineNumber - 1].trimRight();
    findings.add('$path:$lineNumber:stub_callback:$snippet');
  }
  return findings;
}

bool _isStubCallbackBody(String body) {
  final normalized = body.toLowerCase();
  final hasStubMarker = normalized.contains('todo') ||
      normalized.contains('unimplemented') ||
      normalized.contains('not implemented') ||
      normalized.contains('placeholder') ||
      normalized.contains('stub') ||
      normalized.contains('coming soon');
  if (!hasStubMarker) {
    return false;
  }
  if (RegExp(r'throw\s+UnimplementedError\s*\(').hasMatch(body)) {
    return true;
  }
  final withoutComments = body
      .replaceAll(RegExp(r'//.*', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .trim();
  return withoutComments.isEmpty;
}

int _lineNumberAt(String content, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < content.length; i++) {
    if (content.codeUnitAt(i) == 10) {
      line++;
    }
  }
  return line;
}

String _classifyRawMaterialColor({
  required String path,
  required String line,
}) {
  final normalizedLine = line.toLowerCase();
  final overlayPathHints = <String>[
    '/framing/',
    '/guiding/',
    '/imaging/widgets/annotation',
    '/imaging/widgets/custom_annotation_drawing.dart',
    '/imaging/widgets/overlay_',
    '/imaging/widgets/live_preview_area.dart',
    '/imaging/tabs/camera_tab.dart',
    '/imaging/tabs/capture_tab.dart',
    '/planetarium/',
    '/dashboard/widgets/live_preview_card.dart',
    '/dashboard/widgets/dashboard_tile.dart',
    '/dashboard/widgets/glass_card.dart',
    '/analytics/widgets/session_chart.dart',
  ];
  final overlayLineHints = <String>[
    'paint',
    'canvas',
    'shadow',
    'overlay',
    'preview',
    'thumbnail',
    'thumbcolor',
    'linecolor',
    'chart',
    'histogram',
    'star',
    'sky',
    'image',
    'alpha',
    'withvalues',
  ];

  final isOverlayPath = overlayPathHints.any(path.contains);
  final isOverlayLine = overlayLineHints.any(normalizedLine.contains);
  if (isOverlayPath || isOverlayLine) {
    return 'intentional_image_overlay';
  }

  return 'semantic_theme_color';
}

List<String> _headlessRouteFindings() {
  final file = File('apps/desktop/lib/headless_api_server.dart');
  if (!file.existsSync()) {
    return const <String>[];
  }

  final content = file.readAsStringSync();
  final registered = <String>{};
  final routeRegex = RegExp(
    r"router\.(get|post|put|delete|patch)\s*\(\s*'([^']+)'",
    multiLine: true,
  );
  for (final match in routeRegex.allMatches(content)) {
    final path = match.group(2)!;
    if (!path.startsWith('/api/')) {
      continue;
    }
    final routeCall = content.substring(
      match.start,
      match.end + 80 > content.length ? content.length : match.end + 80,
    );
    final method = routeCall.contains('webSocketHandler')
        ? 'WS'
        : match.group(1)!.toUpperCase();
    registered.add('$method $path');
  }

  final advertised = <String>{};
  final availableBlock = RegExp(
    r'List<String>\s+_getAvailableEndpoints\(\)\s*\{.*?return\s*\[(.*?)\];',
    dotAll: true,
  ).firstMatch(content);
  if (availableBlock != null) {
    final literalRegex =
        RegExp(r"'(GET|POST|PUT|DELETE|PATCH|WS) (/api/[^']+)'");
    for (final match in literalRegex.allMatches(availableBlock.group(1)!)) {
      advertised.add('${match.group(1)} ${match.group(2)}');
    }
  }

  final findings = <String>[];
  for (final route in registered) {
    if (!advertised.contains(route)) {
      findings.add(
        'apps/desktop/lib/headless_api_server.dart:'
        '0:headless_route_not_advertised:$route',
      );
    }
  }

  return findings;
}

Map<String, Object?> _designSystemGalleryEvidence() {
  const widgetPath =
      'packages/nightshade_ui/lib/src/widgets/design_system_gallery.dart';
  const exportPath = 'packages/nightshade_ui/lib/nightshade_ui.dart';
  const testPath =
      'packages/nightshade_ui/test/design_system_gallery_test.dart';
  final missing = <String>[];
  final componentEvidence = <String, bool>{};
  final testEvidence = <String, bool>{};

  final widget = File(widgetPath);
  final exportFile = File(exportPath);
  final test = File(testPath);

  final widgetContent = widget.existsSync() ? widget.readAsStringSync() : '';
  final exportContent =
      exportFile.existsSync() ? exportFile.readAsStringSync() : '';
  final testContent = test.existsSync() ? test.readAsStringSync() : '';

  if (widgetContent.isEmpty) {
    missing.add('gallery_widget');
  }
  if (!exportContent.contains(
    "export 'src/widgets/design_system_gallery.dart'",
  )) {
    missing.add('package_export');
  }

  const requiredComponentMarkers = <String>[
    'Buttons',
    'Cards',
    'Inputs',
    'Tabs',
    'Chips and Status Pills',
    'Alerts',
    'NightshadeButton',
    'NightshadeCard',
    'NightshadeTextField',
    'NightshadeDropdown',
    'SubTabButton',
    'StatusPill',
    'StatusPillStatus.success',
    'StatusPillStatus.inactive',
    'NightshadeAlert',
  ];
  for (final marker in requiredComponentMarkers) {
    final present = widgetContent.contains(marker);
    componentEvidence[marker] = present;
    if (!present) {
      missing.add('component_marker:$marker');
    }
  }

  if (testContent.isEmpty) {
    missing.add('gallery_widget_test');
  }

  const requiredTestMarkers = <String>[
    'NightshadeTheme.dark',
    'NightshadeTheme.light',
    'NightshadeTheme.redNight',
    'gallery controls update representative states',
    'gallery-button-primary',
    'gallery-dropdown',
    'gallery-status-active',
    'gallery-status-success',
    'gallery-status-inactive',
    'DropdownButton<String>',
    'NightshadeCheckbox',
    'NightshadeSwitch',
    'SubTabButton',
  ];
  for (final marker in requiredTestMarkers) {
    final present = testContent.contains(marker);
    testEvidence[marker] = present;
    if (!present) {
      missing.add('test_marker:$marker');
    }
  }

  return {
    'ready': missing.isEmpty,
    'widgetPath': widgetPath,
    'testPath': testPath,
    'exportPath': exportPath,
    'componentEvidence': componentEvidence,
    'testEvidence': testEvidence,
    'missing': missing,
  };
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

bool _shouldSkip(String normalizedPath) {
  for (final segment in _excludedSegments) {
    if (normalizedPath.contains(segment)) {
      return true;
    }
  }
  return false;
}

bool _isScopedOutFinding({
  required String path,
  required String ruleId,
}) {
  if (ruleId == 'raw_button_style' &&
      path == 'packages/nightshade_ui/lib/src/theme/nightshade_theme.dart') {
    // ThemeData button defaults are the preferred fallback for Material buttons.
    return true;
  }

  return false;
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

String _normalize(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
