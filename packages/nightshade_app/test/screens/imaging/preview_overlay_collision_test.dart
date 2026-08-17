// The viewport's bottom corners are shared, and the sharing has to be real.
//
// Each overlay is independently anchored in one stack, so an overlay that
// assumes it owns its corner collides with its neighbour on every frame at the
// default 1600x900 window: the field-of-view scale bar painted straight across
// the bottom-left histogram plot (its `10'` label inside the card's lower
// border), and the bottom-right image-stats card drawn over the compass rose,
// bisecting the circle and leaving only the red N arrow legible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/overlay_painters.dart';
import 'package:nightshade_app/screens/imaging/widgets/overlay_widgets.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

const _viewport = Size(1100, 720);

Future<Size> _measure(WidgetTester tester, Widget child) async {
  // Same constraints the viewport gives it: a Positioned with only edge
  // offsets, so the readout sizes to its content exactly as it does in the app.
  await tester.pumpWidget(
    MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: Stack(
          children: [Positioned(bottom: 16, left: 16, child: child)],
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byWidget(child));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the scale bar clears the histogram card', (tester) async {
    final histogram = HistogramWidget(
      colors: NightshadeColors.dark,
      histogram: List<int>.filled(256, 10),
    );
    final size = await _measure(tester, histogram);
    // The readout is anchored at bottom: 16.
    final histogramTop = _viewport.height - 16 - size.height;

    final scaleBar = ScaleBarPainter(
      pixelScaleArcsecPerPixel: 1.29,
      imageWidthPixels: 4000,
      zoomLevel: 0.25,
      bottomMargin: PreviewReadoutInsets.histogram,
    );
    // The bar's background plate extends ~8px above the bar and its label sits
    // below; the bar line itself is the lowest ink that matters here.
    expect(
      scaleBar.barBaselineIn(_viewport),
      lessThan(histogramTop),
      reason: 'the scale bar is drawn through the histogram plot',
    );
    expect(
      PreviewReadoutInsets.histogram,
      greaterThanOrEqualTo(16 + size.height),
      reason: 'the reserved inset must cover the readout it is reserving for',
    );
  });

  testWidgets('the compass rose clears the image-stats card', (tester) async {
    final stats = ImageStatsOverlay(
      colors: NightshadeColors.dark,
      stats: const ImageStats(
        hfr: 2.74,
        starCount: 121,
        median: 1024,
        mean: 1100,
      ),
    );
    final size = await _measure(tester, stats);
    final statsTop = _viewport.height - 16 - size.height;

    final compass = CompassOverlayPainter(
      rotationDegrees: 12,
      bottomMargin: PreviewReadoutInsets.stats,
      colors: NightshadeColors.dark,
    );
    expect(
      compass.boundsIn(_viewport).bottom,
      lessThanOrEqualTo(statsTop),
      reason: 'the stats card is drawn on top of the compass rose',
    );
    expect(
      PreviewReadoutInsets.stats,
      greaterThanOrEqualTo(16 + size.height),
      reason: 'the reserved inset must cover the readout it is reserving for',
    );
  });
}
