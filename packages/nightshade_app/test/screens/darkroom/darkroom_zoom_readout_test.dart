// The Darkroom's magnification readout, in both views that carry it.
//
// The percentage is the one number that says what the operator is looking at,
// and both halves of it were measured wrong in the running app:
//
//  * the SINGLE-recipe viewport opened saying "100% of master" while the fit
//    written from the surface's layout callback had laid a 1600x1200 render at
//    half that — the readout only started telling the truth once the operator
//    touched a zoom control;
//  * the A/B COMPARE readout never moved at all: both panes zoomed under the
//    shared transform while the toolbar stayed on its entry value.
//
// Driven at widget level because that is where the defect lives: the transform,
// the fit and the readout are all this screen's, and none of them needs pixels
// from the engine to be wrong.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_backend.dart';
import '../../harness/mock_database.dart';
import '../../harness/pump_app_screen.dart';

const String _masterPath = '/tmp/nightshade-test/m31_L.fits';

/// A render big enough that a fit is well under 1:1, which is the case the
/// readout got wrong: 100% and the fit only coincide on a picture that happens
/// to be smaller than its pane.
const int _previewWidth = 1600;
const int _previewHeight = 1200;

/// A Darkroom seam that answers one fixed render.
class _FixedRender implements DarkroomSeam {
  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    return {
      'ok': true,
      'error': null,
      'steps': [
        for (var i = 0; i < steps.length; i++)
          {'index': i, 'registered': true, 'valid': true},
      ],
    };
  }

  @override
  Future<DarkroomRenderedPreview> renderPreview({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    return DarkroomRenderedPreview(
      width: _previewWidth,
      height: _previewHeight,
      isColor: false,
      rgba: Uint8List(_previewWidth * _previewHeight * 4),
      report: {
        'encoding': {
          'requested': 'auto',
          'applied': 'screen',
          'sourceDomain': 'linear',
          'clampedSamples': 0,
          'screenTransfer': null,
          'screenTransferAffectsRecipe': false,
        },
        // Level 0: one rendered pixel per master pixel, so the readout is the
        // viewer's own scale and nothing else can explain a wrong percentage.
        'level': {'level': 0, 'scaleFromMaster': 1.0},
        'report': {'steps': const <dynamic>[]},
      },
    );
  }

  @override
  Future<Map<String, dynamic>> renderExport({
    required String recipeJson,
    required Map<String, dynamic> args,
  }) async {
    throw UnimplementedError('this test never exports');
  }

  @override
  Future<Map<String, dynamic>> registry(Map<String, dynamic> args) async {
    return {
      'schemaVersion': 1,
      'ops': [
        {
          'id': 'background_extract',
          'version': 1,
          'stage': 'linear',
          'summary': 'Fits and subtracts a smooth background model.',
          'params': const <dynamic>[],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> cancel(Map<String, dynamic> args) async =>
      {'renderId': args['renderId'], 'running': false};
}

DawnPhotometryResolver _emptyPhotometry() {
  return DawnPhotometryResolver(
    coneSearch: (center, radiusDegrees, {maxMagnitude}) async => const [],
  );
}

Map<String, dynamic> _step(String opId) => {
      'opId': opId,
      'opVersion': 1,
      'params': <String, dynamic>{},
      'enabled': true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late RecipesDao recipes;

  setUp(() {
    db = mockDatabase();
    recipes = RecipesDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedRecipe({String name = 'Draft'}) => recipes.create(
        baseMasterPath: _masterPath,
        name: name,
        stepsJson: jsonEncode([_step('background_extract')]),
        createdBy: RecipeAuthor.autopilot,
      );

  Future<void> pump(WidgetTester tester, int recipeId) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, mockBackend()),
        ),
        databaseProvider.overrideWithValue(db),
        appVersionProvider.overrideWithValue(
          const AppVersionInfo(version: '0.0.0-test', buildNumber: 0),
        ),
        darkroomSeamProvider.overrideWithValue(_FixedRender()),
        dawnPhotometryResolverProvider.overrideWithValue(_emptyPhotometry()),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/darkroom?recipe=$recipeId',
      routes: [
        GoRoute(
          path: '/darkroom',
          builder: (context, state) {
            final raw = state.uri.queryParameters['recipe'];
            final id = raw == null ? null : int.tryParse(raw);
            return DarkroomScreen(
              scope: id == null
                  ? const DarkroomScope.empty()
                  : DarkroomScope.recipe(id),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: NightshadeTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  /// Let `decodeImageFromPixels` answer: it runs on the engine, which the fake
  /// clock inside `testWidgets` never reaches, so without real time the surface
  /// stays on its first-frame spinner and never fits anything.
  Future<void> decodeFrames(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump();
  }

  /// The percentage the toolbar prints, as an integer.
  int readout(WidgetTester tester) {
    final text = tester
        .widgetList<Text>(find.textContaining('% of master'))
        .single
        .data!;
    return int.parse(text.split('%').first);
  }

  /// What the picture on screen IS at, measured off the laid-out box rather
  /// than off the transform the readout also reads.
  ///
  /// A fit lays the whole render inside its pane, so the scale is the pane over
  /// the render on the tighter axis. Independent of every line under test: the
  /// readout has to agree with the geometry, not merely with itself.
  double fitScale(WidgetTester tester) {
    final box = tester.getSize(find.byKey(kDarkroomPreviewSurfaceKey).first);
    final x = box.width / _previewWidth;
    final y = box.height / _previewHeight;
    return x < y ? x : y;
  }

  /// [fitScale] as the whole percent the toolbar would print for it.
  int fitPercent(WidgetTester tester) => (fitScale(tester) * 100).round();

  testWidgets('the single-recipe readout states the fit it opened at', (
    tester,
  ) async {
    final root = await seedRecipe();
    await pump(tester, root);
    await decodeFrames(tester);
    await settle(tester);

    // The picture is laid out fitted — well under 1:1 for a 1600x1200 render in
    // this pane — and the readout said "100% of master" over it: the scale was
    // read with `getMaxScaleOnAxis`, whose maximum includes a Z column the
    // viewer never scales, so every view narrower than 1:1 measured as exactly
    // 1.0. "100%" is a claim about the operator's own pixels.
    expect(fitPercent(tester), lessThan(100));
    expect(readout(tester), fitPercent(tester));
    await drain(tester);
  });

  testWidgets('zooming in past 1:1 keeps the single-recipe readout honest', (
    tester,
  ) async {
    final root = await seedRecipe();
    await pump(tester, root);
    await decodeFrames(tester);
    await settle(tester);

    final fit = fitScale(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pump();
    }
    await tester.pump();

    // Four steps of 1.25 off the fit, and every intermediate value is a real
    // one: the readout used to sit on 100% for the whole run below 1:1 and then
    // jump straight to 128%.
    expect(readout(tester), (fit * 1.25 * 1.25 * 1.25 * 1.25 * 100).round());
    await drain(tester);
  });

  testWidgets('1:1 reaches one screen pixel per master pixel from a fit', (
    tester,
  ) async {
    final root = await seedRecipe();
    await pump(tester, root);
    await decodeFrames(tester);
    await settle(tester);
    // The view it starts from has to be the fit it is actually at, or the press
    // below proves nothing: a readout stuck on 100 makes 1:1 look reached from
    // a picture that is nowhere near it.
    expect(fitPercent(tester), lessThan(100));
    expect(readout(tester), fitPercent(tester));

    await tester.tap(find.widgetWithText(NightshadeButton, '1:1'));
    await tester.pump();
    await tester.pump();

    // The one magnification the control exists for. It was a no-op from any fit
    // below 1:1 over a level-0 render: the scale it asked for was the scale it
    // had just been told it was already at, so it returned having moved
    // nothing.
    expect(readout(tester), 100);
    await drain(tester);
  });

  testWidgets('the compare readout moves with the shared transform', (
    tester,
  ) async {
    final root = await seedRecipe();
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);
    await tester.tap(find.text('Compare with…'));
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeCard, 'Warmer'));
    await settle(tester);
    await decodeFrames(tester);
    await settle(tester);

    // Two panes, half the width each, so the fit is further below 1:1 than the
    // single view's — which is exactly the range the readout used to spend
    // entirely on "100% of master", frozen there through every press.
    final entry = fitScale(tester);
    expect(fitPercent(tester), lessThan(100));
    expect(readout(tester), fitPercent(tester));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pump();
    }
    await tester.pump();

    expect(readout(tester), greaterThan(fitPercent(tester)));
    expect(readout(tester), (entry * 1.25 * 1.25 * 1.25 * 100).round());
    await drain(tester);
  });
}
