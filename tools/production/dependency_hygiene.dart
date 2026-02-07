import 'dart:io';

const _workspaceRoots = <String>['apps', 'packages'];
const _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
};

final _packageImportPattern = RegExp(
  r'''(?:import|export)\s+['"]package:([A-Za-z0-9_]+)/''',
);

void main() {
  final packageDirs = _findPackageDirs();
  final violations = <String>[];

  for (final packageDir in packageDirs) {
    final pubspec =
        File('${packageDir.path}${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) {
      continue;
    }

    final parsed = _parsePubspec(pubspec.readAsLinesSync());
    final packageName = parsed.name;
    if (packageName == null || packageName.isEmpty) {
      violations.add('${pubspec.path}: missing package name');
      continue;
    }

    final libDir = Directory('${packageDir.path}${Platform.pathSeparator}lib');
    if (!libDir.existsSync()) {
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
      violations.add(
        '${pubspec.path}: missing direct dependency "$dep" (imported from lib/) ',
      );
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('Dependency hygiene check passed.');
    return;
  }

  stderr.writeln('Dependency hygiene violations:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exit(1);
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

class _ParsedPubspec {
  final String? name;
  final Set<String> declaredDependencies;

  const _ParsedPubspec({
    required this.name,
    required this.declaredDependencies,
  });
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
      if (trimmed.endsWith(':')) {
        currentRoot = key;
      } else {
        currentRoot = '';
      }
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
