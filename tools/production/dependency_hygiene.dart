import 'dart:convert';
import 'dart:io';

const _jsonOutputPath = 'docs/production-readiness/dependency-hygiene.json';
const _markdownOutputPath = 'docs/production-readiness/dependency-hygiene.md';

const _workspaceRoots = <String>['apps', 'packages'];
const _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
};

final _packageImportPattern = RegExp(
  r'''(?:import|export)\s+['"]package:([A-Za-z0-9_]+)/''',
);

void main(List<String> args) {
  final failOnViolation = !args.contains('--no-fail-on-violation');
  final packageDirs = _findPackageDirs();
  final violations = <_DependencyViolation>[];
  final packageReports = <_PackageReport>[];

  for (final packageDir in packageDirs) {
    final pubspec =
        File('${packageDir.path}${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) {
      continue;
    }

    final parsed = _parsePubspec(pubspec.readAsLinesSync());
    final packageName = parsed.name;
    if (packageName == null || packageName.isEmpty) {
      violations.add(_DependencyViolation(
        pubspecPath: _normalize(pubspec.path),
        packageName: 'unknown',
        dependencyName: 'name',
        reason: 'missing package name',
      ));
      continue;
    }

    final libDir = Directory('${packageDir.path}${Platform.pathSeparator}lib');
    if (!libDir.existsSync()) {
      packageReports.add(_PackageReport(
        packageName: packageName,
        path: _normalize(packageDir.path),
        importedPackageCount: 0,
        declaredDependencyCount: parsed.declaredDependencies.length,
        missingDirectDependencies: const [],
      ));
      continue;
    }

    final importedPackages = <String>{};
    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final contents = entity.readAsStringSync();
      for (final match in _packageImportPattern.allMatches(contents)) {
        final dep = match.group(1);
        if (dep != null && dep.isNotEmpty) {
          importedPackages.add(dep);
        }
      }
    }

    final missing = importedPackages
        .where((pkg) =>
            pkg != packageName &&
            pkg != 'flutter' &&
            pkg != 'flutter_test' &&
            !parsed.declaredDependencies.contains(pkg))
        .toList()
      ..sort();

    for (final dep in missing) {
      violations.add(_DependencyViolation(
        pubspecPath: _normalize(pubspec.path),
        packageName: packageName,
        dependencyName: dep,
        reason: 'missing direct dependency imported from lib/',
      ));
    }

    packageReports.add(_PackageReport(
      packageName: packageName,
      path: _normalize(packageDir.path),
      importedPackageCount: importedPackages.length,
      declaredDependencyCount: parsed.declaredDependencies.length,
      missingDirectDependencies: missing,
    ));
  }

  packageReports.sort((a, b) => a.path.compareTo(b.path));
  violations.sort((a, b) => a.display.compareTo(b.display));

  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'passed': violations.isEmpty,
    'packageCount': packageReports.length,
    'violationCount': violations.length,
    'workspaceRoots': _workspaceRoots,
    'violations': violations.map((violation) => violation.toJson()).toList(),
    'packages': packageReports.map((report) => report.toJson()).toList(),
  };
  File(_jsonOutputPath).parent.createSync(recursive: true);
  File(_jsonOutputPath)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File(_markdownOutputPath).parent.createSync(recursive: true);
  File(_markdownOutputPath).writeAsStringSync(_renderMarkdown(
    packageReports: packageReports,
    violations: violations,
  ));

  stdout.writeln('Dependency hygiene check complete.');
  stdout.writeln('Packages scanned: ${packageReports.length}');
  stdout.writeln('Violations: ${violations.length}');
  stdout.writeln('JSON: $_jsonOutputPath');
  stdout.writeln('Markdown: $_markdownOutputPath');

  if (violations.isEmpty) {
    stdout.writeln('Dependency hygiene check passed.');
    return;
  }

  stderr.writeln('Dependency hygiene violations:');
  for (final violation in violations) {
    stderr.writeln('  ${violation.display}');
  }
  if (failOnViolation) {
    exit(1);
  }
}

List<Directory> _findPackageDirs() {
  final dirs = <Directory>[];
  for (final root in _workspaceRoots) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) {
      continue;
    }
    for (final entity in rootDir.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final pubspec =
          File('${entity.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        dirs.add(entity);
      }
    }
  }
  return dirs;
}

_ParsedPubspec _parsePubspec(List<String> lines) {
  String? name;
  String currentRoot = '';
  final deps = <String>{};

  for (final rawLine in lines) {
    final line = rawLine.replaceAll('\t', '  ');
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final indent = line.length - line.trimLeft().length;
    if (indent == 0 && trimmed.contains(':')) {
      final colon = trimmed.indexOf(':');
      final key = trimmed.substring(0, colon).trim();
      final value = trimmed.substring(colon + 1).trim();
      if (key == 'name') {
        name = _stripQuotes(value);
      }
      currentRoot = trimmed.endsWith(':') ? key : '';
      continue;
    }

    if (_dependencySections.contains(currentRoot) && indent == 2) {
      final colon = trimmed.indexOf(':');
      if (colon > 0) {
        final depName = trimmed.substring(0, colon).trim();
        if (depName.isNotEmpty) {
          deps.add(depName);
        }
      }
    }
  }

  return _ParsedPubspec(name: name, declaredDependencies: deps);
}

String _stripQuotes(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _renderMarkdown({
  required List<_PackageReport> packageReports,
  required List<_DependencyViolation> violations,
}) {
  final buffer = StringBuffer()
    ..writeln('# Dependency Hygiene Audit')
    ..writeln()
    ..writeln('- Packages scanned: `${packageReports.length}`')
    ..writeln('- Violations: `${violations.length}`')
    ..writeln()
    ..writeln(
      'This audit scans each workspace package `lib/` tree for `package:` '
      'imports and verifies each imported package is declared directly in that '
      'package pubspec. It does not audit transitive vulnerability status.',
    );

  if (violations.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Violations')
      ..writeln();
    for (final violation in violations) {
      buffer.writeln('- ${violation.display}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Packages')
    ..writeln()
    ..writeln('| Package | Path | Imports | Declared dependencies | Missing |')
    ..writeln('| --- | --- | ---: | ---: | ---: |');
  for (final report in packageReports) {
    buffer.writeln(
      '| `${report.packageName}` | `${report.path}` | '
      '${report.importedPackageCount} | ${report.declaredDependencyCount} | '
      '${report.missingDirectDependencies.length} |',
    );
  }

  return buffer.toString();
}

String _normalize(String path) => path.replaceAll('\\', '/');

class _ParsedPubspec {
  final String? name;
  final Set<String> declaredDependencies;

  const _ParsedPubspec({
    required this.name,
    required this.declaredDependencies,
  });
}

class _DependencyViolation {
  final String pubspecPath;
  final String packageName;
  final String dependencyName;
  final String reason;

  const _DependencyViolation({
    required this.pubspecPath,
    required this.packageName,
    required this.dependencyName,
    required this.reason,
  });

  String get display =>
      '$pubspecPath: $reason "$dependencyName" for package "$packageName"';

  Map<String, Object?> toJson() => {
        'pubspecPath': pubspecPath,
        'packageName': packageName,
        'dependencyName': dependencyName,
        'reason': reason,
      };
}

class _PackageReport {
  final String packageName;
  final String path;
  final int importedPackageCount;
  final int declaredDependencyCount;
  final List<String> missingDirectDependencies;

  const _PackageReport({
    required this.packageName,
    required this.path,
    required this.importedPackageCount,
    required this.declaredDependencyCount,
    required this.missingDirectDependencies,
  });

  Map<String, Object?> toJson() => {
        'packageName': packageName,
        'path': path,
        'importedPackageCount': importedPackageCount,
        'declaredDependencyCount': declaredDependencyCount,
        'missingDirectDependencies': missingDirectDependencies,
      };
}
