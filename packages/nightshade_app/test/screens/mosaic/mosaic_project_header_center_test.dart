// The mosaic project header's "target region" claim must be TRUE.
//
// It derives the mosaic centre from the panel centres. RA was averaged
// arithmetically, which is invalid for an angle: a mosaic straddling RA 0h has
// panels at (e.g.) 23.97h and 0.03h, whose arithmetic mean is 12.0h. The header
// therefore stated, with full confidence and to the second, a centre on the
// exact opposite side of the sky from the grid it was describing — and the
// operator has nothing else on that screen to check it against.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_controller.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  MosaicProject project({int rows = 2, int cols = 2}) {
    final now = DateTime.utc(2026, 7, 29);
    return MosaicProject(
      id: 1,
      name: 'Seam Mosaic',
      rows: rows,
      cols: cols,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<MosaicProjectPanel> panels(List<(double ra, double dec)> centers) {
    return [
      for (var i = 0; i < centers.length; i++)
        MosaicProjectPanel(
          projectId: 1,
          panelIndex: i,
          centerRa: centers[i].$1,
          centerDec: centers[i].$2,
        ),
    ];
  }

  Future<String> pumpHeaderSubtitle(
    WidgetTester tester, {
    required MosaicProject mosaicProject,
    required List<MosaicProjectPanel> mosaicPanels,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: MosaicProjectHeader(
            project: mosaicProject,
            state: MosaicProjectState(
              project: mosaicProject,
              panels: mosaicPanels,
              isLoading: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        // The subtitle leads with the axis-labelled grid dimensions
        // ("3 wide x 2 high"); see mosaic_format.dart.
        .where((data) => data.contains(' wide '))
        .toList();
    expect(
      texts,
      isNotEmpty,
      reason: 'header subtitle (containing the grid dimensions) '
          'was not rendered',
    );
    return texts.single;
  }

  testWidgets(
    'a mosaic straddling RA 0h reports a centre near 0h, not 12h',
    (tester) async {
      final subtitle = await pumpHeaderSubtitle(
        tester,
        mosaicProject: project(),
        mosaicPanels: panels(const [
          (23.97, 40.0),
          (0.03, 40.0),
          (23.97, 41.0),
          (0.03, 41.0),
        ]),
      );

      // The arithmetic-mean bug rendered "12:00:00.00".
      expect(subtitle, isNot(contains('12:00:00')));
      // Circular mean puts the centre back on the RA 0h seam — either side of
      // it is the same place on the sky.
      expect(
        subtitle.contains('00:00:00') || subtitle.contains('23:59:5'),
        isTrue,
        reason: 'expected a centre at the RA 0h seam, got: $subtitle',
      );
    },
  );

  testWidgets('a mosaic well away from the seam is unchanged', (tester) async {
    final subtitle = await pumpHeaderSubtitle(
      tester,
      mosaicProject: project(rows: 1, cols: 2),
      mosaicPanels: panels(const [
        (5.55, -5.0),
        (5.65, -5.0),
      ]),
    );

    // 5.55h and 5.65h average to 5.60h = 05:36:00. (Field-wise rounding used
    // to render this same value as the impossible '05:35:60.00'.)
    expect(subtitle, contains('05:36:00.00'));
    // One convention, axis-labelled, shared with the Collaborate card.
    expect(subtitle, contains('2 wide × 1 high'));
  });

  testWidgets(
      'a project with no panels omits the centre rather than '
      'inventing 00h00m00s', (tester) async {
    final subtitle = await pumpHeaderSubtitle(
      tester,
      mosaicProject: project(rows: 1, cols: 1),
      mosaicPanels: const [],
    );

    // No centre segment at all. Matched on the sexagesimal colons rather than
    // a bare 'h', which the axis-labelled grid ("1 wide × 1 high") also carries.
    expect(subtitle, isNot(contains(':')));
    expect(subtitle, contains('0 of 1 panels'));
  });

  testWidgets(
      'a sparse grid (cells disabled in the wizard) reports the '
      'panels that exist, not rows x cols', (tester) async {
    // A 3x3 project created with one corner disabled persists 8 panels. The
    // header used to say "9 panels" right above a grid of 8 and an action row
    // reading "… of 8 panels integrated".
    final subtitle = await pumpHeaderSubtitle(
      tester,
      mosaicProject: project(rows: 3, cols: 3),
      mosaicPanels: panels(const [
        (5.0, 10.0),
        (5.1, 10.0),
        (5.2, 10.0),
        (5.0, 10.5),
        (5.1, 10.5),
        (5.2, 10.5),
        (5.0, 11.0),
        (5.1, 11.0),
      ]),
    );

    expect(subtitle, contains('3 wide × 3 high'));
    expect(subtitle, contains('8 of 9 panels'));
    // The bare "9 panels" claim (rows x cols) must be gone.
    expect(subtitle, isNot(contains('·  9 panels')));
  });

  testWidgets('a complete grid still reads as a plain panel count',
      (tester) async {
    final subtitle = await pumpHeaderSubtitle(
      tester,
      mosaicProject: project(rows: 1, cols: 2),
      mosaicPanels: panels(const [
        (5.0, 10.0),
        (5.1, 10.0),
      ]),
    );

    expect(subtitle, contains('2 panels'));
    expect(subtitle, isNot(contains('of 2 panels')));
  });
}
