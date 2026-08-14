// CON-53 -> WE-EQ-N1: the relocated-defect shape.
//
// CON-53 filed "Plan Tonight tells you to use Plan Tonight". The Wave D repair
// replaced that with "build one in the Target Queue tab" — and there is no
// Target Queue tab; it was merged into Schedule
// (planner_screen_parts/_schedule_tab.dart), leaving
// `plannerTabTargetQueue` as an orphan string with no live UI referent.
//
// One false direction was swapped for another because nothing checked the
// claim against the tab list. This test is that check: any user-visible copy
// under screens/planner that sends the reader to a NAMED tab must name a tab
// PlannerTab actually renders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';

/// The tab names this build renders, as `PlannerTab` + the English labels in
/// `translations.dart` (`plannerTab*`).
const _renderedTabLabels = <String>{
  'Recommendation',
  'Projects',
  'Schedule',
  'Framing',
  'Planetarium',
  'Discover',
};

/// Lines that are pure comments carry design history, not directions to the
/// operator, so they are exempt.
bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

void main() {
  test('the tab-label set matches PlannerTab', () {
    // If a tab is added or renamed, this fails first and points at the list
    // above rather than letting the copy check silently go stale.
    expect(PlannerTab.values, hasLength(_renderedTabLabels.length));
  });

  test('no planner copy sends the reader to a tab that does not exist', () {
    final dir = Directory('lib/screens/planner');
    expect(dir.existsSync(), isTrue,
        reason: 'run from packages/nightshade_app');

    // "Foo tab" / "Foo Bar tab" — a capitalised proper name immediately before
    // the word "tab" is a direction to a specific tab.
    final namedTab = RegExp(r'\b([A-Z][A-Za-z]*(?: [A-Z][A-Za-z]*)*) tab\b');
    // Words that read as "this tab"/"each tab" rather than a tab's name, plus
    // "Planner tab", which appears only in an `assert` message addressed to a
    // developer editing the enum — never to an operator.
    const generic = {
      'Each',
      'The',
      'This',
      'That',
      'A',
      'Its',
      'One',
      'Planner',
    };

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_isComment(line)) continue;
        for (final match in namedTab.allMatches(line)) {
          final name = match.group(1)!;
          if (generic.contains(name)) continue;
          // Allow a trailing generic word ("The Discover tab" -> Discover).
          final trimmed = name.split(' ').last;
          if (_renderedTabLabels.contains(name) ||
              _renderedTabLabels.contains(trimmed)) {
            continue;
          }
          offenders.add('${entity.path}:${i + 1}: "$name tab"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these strings direct the operator to a tab Plan Tonight does '
          'not render (tabs: ${_renderedTabLabels.join(", ")})',
    );
  });
}
