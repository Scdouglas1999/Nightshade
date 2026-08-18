// No Darkroom control may publish a button role without an enabled state.
//
// `Semantics(button: true, …)` with no `enabled:` field produces a node that
// resolves NO enabled state, and the AT-SPI bridge publishes ENABLED only for a
// node that resolves one — so Orca reads a working control as unavailable. The
// Darkroom shipped that twice: the compare picker's option row was the only
// route into A/B compare and announced as DISABLED while a click on the same
// row armed the comparison.
//
// Pinning the one row leaves the class alive, so this sweeps the directory. It
// is a source scan rather than a widget drive because most of these controls
// need a recipe, a master and a rendered preview to exist at all, while the
// rule holds without any of them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The directory this rule covers.
const _root = 'lib/screens/darkroom';

void main() {
  test('every Darkroom button node resolves an enabled state', () {
    final root = Directory(_root);
    expect(
      root.existsSync(),
      isTrue,
      reason: 'run from the nightshade_app package root',
    );

    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final code = _codeOnly(source);
      for (final site in _semanticsArguments(code)) {
        if (!site.arguments.contains('button: true')) continue;
        if (site.arguments.contains('enabled:')) continue;
        offenders.add('${entity.path}:${_lineOf(code, site.offset)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these nodes publish a button role with no enabled state, so '
          'assistive tech announces each working control as disabled:\n'
          '${offenders.join('\n')}',
    );
  });

  group('the scanner', () {
    test('reads the arguments of the Semantics call it is on, not its child',
        () {
      const source = '''
Semantics(
  container: true,
  button: true,
  label: 'outer',
  child: Semantics(button: true, enabled: true, child: Text('x')),
);
''';
      final sites = _semanticsArguments(_codeOnly(source));
      expect(sites, hasLength(2));
      expect(sites.first.arguments, contains('container: true'));
      expect(sites.first.arguments, contains('button: true'));
      expect(
        sites.first.arguments,
        isNot(contains('enabled:')),
        reason: 'the inner call\'s enabled: belongs to the inner node',
      );
      expect(sites.last.arguments, contains('enabled: true'));
    });

    test('does not read a comment or a string as code', () {
      const source = '''
// Semantics(button: true) in prose is not a call.
final text = 'Semantics(button: true)';
Semantics(button: true, enabled: true, child: Text('a (b'));
''';
      final sites = _semanticsArguments(_codeOnly(source));
      expect(sites, hasLength(1));
      expect(sites.single.arguments, contains('enabled: true'));
    });
  });
}

/// One `Semantics(…)` call: where it starts, and its own argument list with
/// every nested call, list and map blanked out.
class _SemanticsSite {
  final int offset;
  final String arguments;

  const _SemanticsSite(this.offset, this.arguments);
}

/// [source] with every comment and string literal replaced by spaces.
///
/// Offsets are preserved so a hit still reports the line it is on, and a
/// bracket inside a sentence — `Text('a (b')` — cannot unbalance the scan.
String _codeOnly(String source) {
  final out = List<String>.generate(source.length, (i) => source[i]);
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (char == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        while (i < source.length && source[i] != '\n') {
          out[i] = ' ';
          i++;
        }
        continue;
      }
      if (next == '*') {
        var depth = 0;
        while (i < source.length) {
          if (source.startsWith('/*', i)) {
            depth++;
            out[i] = out[i + 1] = ' ';
            i += 2;
            continue;
          }
          if (source.startsWith('*/', i)) {
            depth--;
            out[i] = out[i + 1] = ' ';
            i += 2;
            if (depth == 0) break;
            continue;
          }
          if (source[i] != '\n') out[i] = ' ';
          i++;
        }
        continue;
      }
    }
    if (char == "'" || char == '"') {
      final triple = source.startsWith(char * 3, i);
      final closer = triple ? char * 3 : char;
      out[i] = ' ';
      if (triple) out[i + 1] = out[i + 2] = ' ';
      i += closer.length;
      while (i < source.length) {
        if (source[i] == r'\') {
          out[i] = ' ';
          if (i + 1 < source.length) out[i + 1] = ' ';
          i += 2;
          continue;
        }
        if (source.startsWith(closer, i)) {
          for (var k = 0; k < closer.length; k++) {
            out[i + k] = ' ';
          }
          i += closer.length;
          break;
        }
        if (source[i] != '\n') out[i] = ' ';
        i++;
      }
      continue;
    }
    i++;
  }
  return out.join();
}

/// Every `Semantics(` call in [code], with its own arguments only.
///
/// Anything nested one level deeper — a child widget, a list, a map — is
/// blanked, so a wrapped control's `enabled:` is never credited to the node
/// wrapping it.
List<_SemanticsSite> _semanticsArguments(String code) {
  final opener = RegExp(r'(?<![A-Za-z0-9_$])Semantics\(');
  final sites = <_SemanticsSite>[];
  for (final match in opener.allMatches(code)) {
    final start = match.end;
    final buffer = StringBuffer();
    var depth = 0;
    var i = start;
    while (i < code.length) {
      final char = code[i];
      if (char == '(' || char == '[' || char == '{') {
        depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth == 0) break;
        depth--;
      }
      buffer.write(depth == 0 ? char : ' ');
      i++;
    }
    sites.add(_SemanticsSite(match.start, buffer.toString()));
  }
  return sites;
}

/// The 1-based line [offset] falls on.
int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;
