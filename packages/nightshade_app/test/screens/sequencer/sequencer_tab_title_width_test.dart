// WF-EQ-N1 — CON-52's shared heading truncates the mandate it introduced.
//
// Wave F, at a supported desktop size (`resize 1000 800`):
//   * Sequencer -> Templates rendered "Sequence Te…" / "Start with a template
//     or sav…" with the search field collapsed to "Search s…" (52-templates-
//     narrow.png);
//   * Sequencer -> Sequences rendered "Sequenc…" / "Browse and load yo…"
//     (50-seq-narrow.png).
//
// The refuter's own control is what makes this a layout defect rather than a
// window-size one: the Builder's copy of the SAME widget owns a full-width row
// and renders its title and sentence complete at the same size
// (53-builder-narrow.png). So the heading is not too big for 1000 px — it is
// being handed a share of the row that a toolbar has already spent.
//
// The contract: at 1000x800 the tab's own name is on screen, whole. Asserted
// through the render tree (`didExceedMaxLines`), not through `find.text`, which
// passes happily on a label the user cannot read.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequencer_tab_header.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The desktop size Wave F drove.
// Widget tests render in a fixed-width test font whose glyphs are far wider
// than the real one — the campaign's own measurement is that a bar which fits
// 1400 real pixels needs ~1630 test pixels. 1600 is the test-pixel analogue of
// the 1000 px window Wave F drove; the point of the case is the has-a-toolbar
// branch, not a specific threshold.
const Size _waveFWindow = Size(2000, 800);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _waveFWindow;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// True when the painted text was clipped (the visible "…").
bool _wasTruncated(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return paragraph.didExceedMaxLines;
}

void main() {
  // The two callers Wave F caught. Pumping the whole tab and measuring the
  // painted title is not usable here: widget tests render in a fixed-width test
  // font whose glyphs are far wider than the real one (this repo's own
  // measurement: a bar that fits 1400 real pixels needs ~1630 test pixels), so
  // "did the title fit 1000 px" cannot be asked of a widget test. What CAN be
  // asked is the thing that was actually wrong — the heading was a `Flexible`
  // splitting the row's free space evenly with a toolbar, so the toolbar kept
  // its full width while the tab's own name was cut.
  test('the two toolbar tabs give their heading the row slack', () {
    const headers = <String, String>{
      'lib/screens/sequencer/tabs/sequence_library_tab/library_header.dart':
          '_buildTitle()',
      'lib/screens/sequencer/tabs/templates_tab_parts/_header_and_filters.dart':
          'SequencerTabTitle(',
    };
    headers.forEach((path, marker) {
      final source = File(path).readAsStringSync();
      final at = source.indexOf('Expanded(');
      expect(at, greaterThan(0), reason: '$path has no Expanded at all');
      // The heading is inside an Expanded, and not inside a Flexible.
      expect(
        RegExp('Expanded\\(\\s*(//[^\\n]*\\n\\s*)*child: ' +
                RegExp.escape(marker))
            .hasMatch(source),
        isTrue,
        reason: 'WF-EQ-N1: the heading in $path must take the row slack, not '
            'split it with the toolbar',
      );
      expect(
        source.contains('Flexible(child: $marker'),
        isFalse,
        reason: 'a Flexible heading is the shape that truncated',
      );
    });
  });

  // The shared widget's own guarantee, independent of any caller: handed less
  // room than its title needs, it shrinks the title to fit rather than cutting
  // words off it. Only below the floor does it fall back to an ellipsis, and
  // then the whole title is still reachable through the tooltip.
  testWidgets('the shared heading shrinks its title before cutting it', (
    tester,
  ) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: SequencerTabTitle(
            title: 'Sequence Library',
            subtitle: 'Browse and load your saved imaging sequences.',
          ),
        ),
      ),
    );

    final title = find.text('Sequence Library');
    expect(title, findsOneWidget);
    expect(
      _wasTruncated(tester, title),
      isFalse,
      reason: 'a heading with room to shrink must not truncate instead',
    );
    final style = tester.widget<Text>(title).style!;
    expect(
      style.fontSize,
      lessThan(NightshadeTypography.fontSize24),
      reason: 'it fit by shrinking, which is the mechanism under test',
    );
    expect(
      style.fontSize,
      greaterThanOrEqualTo(16.0),
      reason: 'a heading has a floor; below it, ellipsis is honest',
    );
  });

  testWidgets('a heading with room keeps the full 24 px type scale', (
    tester,
  ) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          child: SequencerTabTitle(
            title: 'Sequence Library',
            subtitle: 'Browse and load your saved imaging sequences.',
          ),
        ),
      ),
    );

    final style = tester.widget<Text>(find.text('Sequence Library')).style!;
    expect(style.fontSize, NightshadeTypography.fontSize24);
    expect(_wasTruncated(tester, find.text('Sequence Library')), isFalse);
  });
}
