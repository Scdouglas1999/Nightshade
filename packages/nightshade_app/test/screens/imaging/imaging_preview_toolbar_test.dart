// Widget tests for the off-canvas ImagingPreviewToolbar.
//
// The imaging preview toolbar replaced the old on-image overlay bar: the six
// cryptic overlay-toggle icons collapsed into a single labelled "Overlays"
// popover, and the whole bar moved off the image canvas into a slim strip
// above the live preview.
//
// These tests pin the load-bearing behaviour change: the Overlays menu must
// still flip the SAME providers the old loose icons drove. We exercise the
// catalog-overlay row because it toggles a plain StateProvider
// (catalogOverlayEnabledProvider) we can read directly from the container —
// no callback indirection — so a green assertion proves the menu→provider
// wiring end to end, not just that a row rendered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/imaging_screen.dart';
import 'package:nightshade_app/screens/imaging/widgets/imaging_preview_toolbar.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// Drive several frames so async-provider overrides flow into the tree and the
/// screen's fade controller completes, without pumpAndSettle (BigActionButton's
/// loading animation never settles).
Future<void> _drainAsyncFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = defaultOnError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'toolbar_renders_above_preview: ImagingPreviewToolbar is present at '
      'desktop width', (tester) async {
    _swallowKnownOverflows();
    final handle = await pumpAppScreen(
      tester,
      const ImagingScreen(),
      size: const Size(1600, 900),
      settle: false,
    );
    await _drainAsyncFrames(tester);
    addTearDown(() async => handle.database.close());

    expect(find.byType(ImagingPreviewToolbar), findsOneWidget,
        reason:
            'The relocated, off-canvas preview toolbar must render once above '
            'the live preview.');
    // The single labelled Overlays control replaces the six former icons.
    expect(find.text('Overlays'), findsOneWidget,
        reason:
            'The six loose overlay icons collapsed into one labelled Overlays '
            'popover trigger.');
  });

  testWidgets(
      'overlays_menu_toggles_catalog_overlay_provider: tapping the Catalog '
      'overlay row flips catalogOverlayEnabledProvider', (tester) async {
    _swallowKnownOverflows();
    final handle = await pumpAppScreen(
      tester,
      const ImagingScreen(),
      size: const Size(1600, 900),
      settle: false,
    );
    await _drainAsyncFrames(tester);
    addTearDown(() async => handle.database.close());

    // Baseline: the catalog overlay starts disabled.
    expect(handle.container.read(catalogOverlayEnabledProvider), isFalse,
        reason: 'Catalog overlay defaults off.');

    // Open the Overlays popover. Fixed-step pumps instead of pumpAndSettle —
    // the imaging control panel's BigActionButton runs a repeating loading
    // animation that never settles, so pumpAndSettle would time out.
    await tester.tap(find.text('Overlays'));
    await _drainAsyncFrames(tester);

    // The popover lists labelled overlay rows; tap the Catalog overlay one.
    expect(find.text('Catalog overlay'), findsOneWidget,
        reason:
            'The Overlays popover must expose a labelled Catalog overlay row '
            'wired to the same provider the old catalog icon drove.');
    await tester.tap(find.text('Catalog overlay'));
    // PopupMenuItem.onTap fires after the menu dismisses on a post-frame
    // callback; drain frames so that write lands.
    await _drainAsyncFrames(tester);

    expect(handle.container.read(catalogOverlayEnabledProvider), isTrue,
        reason: 'Selecting the Catalog overlay row must flip '
            'catalogOverlayEnabledProvider true — proving the new menu drives '
            'the same provider as the retired loose icon.');
  });
}
