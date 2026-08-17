// Widget tests for the Darkroom's branch bar, A/B compare and export sheet.
//
// These assert what a reader of the code cannot see:
//
//  * the branch bar names who wrote each branch and refuses a parent delete out
//    loud, with the branches that blocked it on screen;
//  * an A/B compare hands BOTH viewers the same TransformationController, which
//    is what keeps a drag-pan in sync — `onTransformChanged` fires only on
//    wheel zoom, so a sync built on it would come apart on the first drag;
//  * the export sheet shows the engine's raster refusal as readable text, not
//    just a greyed chip, and one switch turns it into a choice;
//  * a FITS export names its `.nsrecipe` sidecar on the wire rather than hoping
//    the engine derives one.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_screen.dart';
import 'package:nightshade_app/widgets/astro_image_viewer.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:go_router/go_router.dart';

import '../../harness/mock_backend.dart';
import '../../harness/mock_database.dart';
import '../../harness/pump_app_screen.dart';

/// A Darkroom seam whose every reply the test writes.
class _ScriptedDarkroom implements DarkroomSeam {
  /// Every `renderExport` args map, in call order.
  final List<Map<String, dynamic>> exportArgs = [];

  /// Every `cancel` args map, in call order.
  final List<Map<String, dynamic>> cancelArgs = [];

  /// Held open to keep an export inside the engine.
  Completer<void>? holdExport;

  /// Thrown out of the next `renderExport` when set.
  Object? exportFailure;

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
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    return DarkroomRenderedPreview(
      width: 4,
      height: 4,
      isColor: false,
      rgba: Uint8List(4 * 4 * 4),
      report: {
        'encoding': 'auto stretch applied for display only',
        'level': {'level': 0, 'scaleFromMaster': 1.0},
        'report': {
          'steps': [
            for (var i = 0; i < steps.length; i++)
              {
                'index': i,
                'opId': (steps[i] as Map<String, dynamic>)['opId'],
                'outcome':
                    ((steps[i] as Map<String, dynamic>)['enabled'] as bool)
                    ? 'applied'
                    : 'disabled',
              },
          ],
        },
      },
    );
  }

  @override
  Future<Map<String, dynamic>> renderExport({
    required String recipeJson,
    required Map<String, dynamic> args,
  }) async {
    exportArgs.add(args);
    final hold = holdExport;
    if (hold != null) {
      holdExport = null;
      await hold.future;
    }
    final failure = exportFailure;
    if (failure != null) {
      exportFailure = null;
      throw failure;
    }
    final outputs = args['outputs'] as List;
    final first = outputs.first as Map<String, dynamic>;
    return {
      'stage': args['stage'],
      'outputs': [
        {
          'format': first['format'],
          'path': first['path'],
          'bytes': 4096,
          'width': 4,
          'height': 4,
          'clampedSamples': 0,
        },
      ],
      'sidecarPath': args['sidecarPath'],
      'sidecarSkippedReason': null,
      'sourceDomain': 'linear',
      'screenTransfer': null,
      'recipeFingerprint': 'abc123',
    };
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
        {
          'id': 'stretch',
          'version': 1,
          'stage': 'stretched',
          'summary': 'Generalised hyperbolic stretch.',
          'params': const <dynamic>[],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> cancel(Map<String, dynamic> args) async {
    cancelArgs.add(args);
    return {'renderId': args['renderId'], 'running': true};
  }
}

DawnPhotometryResolver _emptyPhotometry() {
  return DawnPhotometryResolver(
    coneSearch: (center, radiusDegrees, {maxMagnitude}) async => const [],
  );
}

const String _masterPath = '/tmp/nightshade-test/m31_L.fits';

Map<String, dynamic> _step(String opId, {bool enabled = true}) => {
  'opId': opId,
  'opVersion': 1,
  'params': <String, dynamic>{},
  'enabled': enabled,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedDarkroom darkroom;
  late NightshadeDatabase db;
  late RecipesDao recipes;
  late List<Map<String, Object?>> pickerCalls;
  String? pickerAnswer;

  setUp(() {
    darkroom = _ScriptedDarkroom();
    db = mockDatabase();
    recipes = RecipesDao(db);
    pickerCalls = [];
    pickerAnswer = '/tmp/nightshade-test/out.fits';
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedRecipe(
    List<Map<String, dynamic>> steps, {
    String name = 'Draft',
    RecipeAuthor by = RecipeAuthor.autopilot,
  }) {
    return recipes.create(
      baseMasterPath: _masterPath,
      name: name,
      stepsJson: jsonEncode(steps),
      createdBy: by,
    );
  }

  /// Pump the Darkroom behind a real router.
  ///
  /// Not `pumpAppScreen`: the branch bar switches branches with `context.go`,
  /// so a tree with no router would make every one of those controls throw in
  /// the test while working in the app — the opposite of what a widget test is
  /// for. The route shape mirrors `app_router.dart`'s own `/darkroom`.
  Future<GoRouter> pump(
    WidgetTester tester,
    int recipeId, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
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
        darkroomSeamProvider.overrideWithValue(darkroom),
        dawnPhotometryResolverProvider.overrideWithValue(_emptyPhotometry()),
        darkroomSavePickerProvider.overrideWithValue(({
          required String suggestedName,
          required List<String> allowedExtensions,
          required String confirmButtonText,
        }) async {
          pickerCalls.add({
            'suggestedName': suggestedName,
            'allowedExtensions': allowedExtensions,
            'confirmButtonText': confirmButtonText,
          });
          return pickerAnswer;
        }),
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
    return router;
  }

  /// Pump enough frames for a dialog route and one round of controller work to
  /// land. Deliberately NOT `pumpAndSettle`: the editor keeps an indeterminate
  /// progress animation up while a render is in the engine, so a settle never
  /// converges.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Pump past every timer the screen arms so teardown finds none pending.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  // ---------------------------------------------------------------------
  // Branch bar
  // ---------------------------------------------------------------------

  testWidgets('the bar names every branch and who wrote it', (tester) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);

    expect(find.widgetWithText(NightshadeChip, 'Draft'), findsOneWidget);
    expect(find.widgetWithText(NightshadeChip, 'Warmer'), findsOneWidget);
    // The autopilot's draft and the operator's variant carry different marks.
    expect(find.byIcon(NightshadeIcons.sparkle), findsWidgets);
    expect(find.byIcon(NightshadeIcons.user), findsWidgets);
    expect(find.textContaining('Lineage:'), findsNothing);
    await drain(tester);
  });

  testWidgets('a branch states the lineage it came from', (tester) async {
    final root = await seedRecipe([_step('background_extract')]);
    final variant = await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, variant);

    expect(
      find.textContaining('Lineage: Draft → Warmer (from step 1)'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('duplicate as variant writes a branch of the open recipe', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await pump(tester, root);

    await tester.tap(find.text('Duplicate as variant'));
    await settle(tester);

    expect(find.text('Duplicate as variant'), findsWidgets);
    await tester.tap(find.text('Create variant'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final rows = await recipes.listForMaster(_masterPath);
    expect(rows, hasLength(2));
    final variant = rows.firstWhere((r) => r.id != root);
    expect(variant.parentRecipeId, root);
    expect(variant.divergenceIndex, 1);
    expect(variant.createdBy, RecipeAuthor.user);
    await drain(tester);
  });

  testWidgets('deleting a parent explains itself with the branches named', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);

    await tester.tap(find.text('Delete branch'));
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Delete'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(find.text('That branch has branches of its own'), findsOneWidget);
    expect(find.textContaining('Warmer'), findsWidgets);
    expect(find.textContaining('cannot be deleted while 1 branch'), findsOneWidget);
    // The refusal offers the one destructive alternative the DAO actually has.
    expect(
      find.textContaining('Delete "Draft" and its 1 branch'),
      findsOneWidget,
    );
    // Nothing was deleted.
    expect(await recipes.listForMaster(_masterPath), hasLength(2));
    await drain(tester);
  });

  // ---------------------------------------------------------------------
  // A/B compare
  // ---------------------------------------------------------------------

  Future<void> enterCompare(WidgetTester tester) async {
    await tester.tap(find.text('Compare with…'));
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Warmer'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('both compare panes share ONE transform controller', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);
    await enterCompare(tester);

    final viewers = tester
        .widgetList<AstroImageViewer>(find.byType(AstroImageViewer))
        .toList();
    expect(viewers, hasLength(2));
    final shared = viewers.first.transformationController;
    expect(shared, isNotNull);
    // Identity, not equality: the sync IS the shared controller. A drag-pan or
    // a pinch never reaches `onTransformChanged`, so two controllers kept in
    // step by that callback would diverge on the first drag.
    expect(identical(viewers[1].transformationController, shared), isTrue);

    // Driving it from outside moves both panes, because both read it.
    final before = shared!.value.clone();
    shared.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0);
    await tester.pump();
    expect(shared.value, isNot(before));
    for (final viewer in tester.widgetList<AstroImageViewer>(
      find.byType(AstroImageViewer),
    )) {
      expect(identical(viewer.transformationController, shared), isTrue);
    }
    await drain(tester);
  });

  testWidgets('blink mounts one pane at a time', (tester) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);
    await enterCompare(tester);

    await tester.tap(find.widgetWithText(NightshadeChip, 'Blink'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // Exactly one viewer: hiding the other instead of not building it would
    // mount the same subtree twice and keep two decoded images alive.
    expect(find.byType(AstroImageViewer), findsOneWidget);
    expect(find.text('Showing A'), findsOneWidget);

    await tester.pump(kDarkroomBlinkInterval);
    expect(find.text('Showing B'), findsOneWidget);
    expect(find.byType(AstroImageViewer), findsOneWidget);

    // Pausing stops the alternation rather than merely hiding the label.
    await tester.tap(find.text('Pause blink'));
    await tester.pump();
    final showing = find.text('Showing B').evaluate().isNotEmpty;
    await tester.pump(kDarkroomBlinkInterval * 3);
    expect(find.text(showing ? 'Showing B' : 'Showing A'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('hold-to-compare pins the other recipe up while held', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root);
    await enterCompare(tester);
    await tester.tap(find.widgetWithText(NightshadeChip, 'Blink'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final hold = find.text('Hold to see Warmer');
    expect(hold, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump();
    expect(find.text('Showing B'), findsOneWidget);
    // The blink timer cannot take the B side away while it is held.
    await tester.pump(kDarkroomBlinkInterval * 2);
    expect(find.text('Showing B'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await drain(tester);
  });

  testWidgets('a phone stacks the two panes instead of shrinking them', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, root, size: const Size(390, 844));
    await enterCompare(tester);

    final viewers = find.byType(AstroImageViewer);
    expect(viewers, findsNWidgets(2));
    final first = tester.getRect(viewers.at(0));
    final second = tester.getRect(viewers.at(1));
    // Stacked, not side by side: two 180-pixel-wide renders compare nothing.
    expect(second.top, greaterThanOrEqualTo(first.bottom - 1));
    expect(first.width, closeTo(second.width, 1));
    await drain(tester);
  });

  // ---------------------------------------------------------------------
  // Export sheet
  // ---------------------------------------------------------------------

  Future<void> openExport(WidgetTester tester) async {
    await tester.tap(find.text('Export…'));
    await settle(tester);
  }

  testWidgets('a still-linear stage says WHY the rasters are unavailable', (
    tester,
  ) async {
    final root = await seedRecipe([_step('background_extract')]);
    await pump(tester, root);
    await openExport(tester);

    expect(
      find.text('PNG, JPEG and TIFF are unavailable for this stage'),
      findsOneWidget,
    );
    // The reason is READ, not hovered: a tooltip says nothing on a touch
    // screen, and this refusal is the whole point of the stage picker.
    expect(
      find.textContaining('still linear ADU and has no display mapping'),
      findsOneWidget,
    );
    final png = tester.widget<NightshadeChip>(
      find.widgetWithText(NightshadeChip, 'PNG'),
    );
    expect(png.enabled, isFalse);
    final fits = tester.widget<NightshadeChip>(
      find.widgetWithText(NightshadeChip, 'FITS'),
    );
    expect(fits.enabled, isTrue);

    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);
    expect(
      tester
          .widget<NightshadeChip>(find.widgetWithText(NightshadeChip, 'PNG'))
          .enabled,
      isTrue,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('a stack that ends stretched offers the rasters directly', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    expect(
      find.text('PNG, JPEG and TIFF are unavailable for this stage'),
      findsNothing,
    );
    expect(
      tester
          .widget<NightshadeChip>(find.widgetWithText(NightshadeChip, 'JPEG'))
          .enabled,
      isTrue,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('a FITS export names its sidecar and its stage on the wire', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    await tester.tap(find.text('Export'));
    await settle(tester);

    expect(pickerCalls, hasLength(1));
    expect(pickerCalls.single['allowedExtensions'], contains('fits'));
    expect(darkroom.exportArgs, hasLength(1));
    final args = darkroom.exportArgs.single;
    expect(args['masterPath'], _masterPath);
    expect((args['stage'] as Map)['kind'], 'final');
    expect(args['writeSidecar'], isTrue);
    expect(args['sidecarPath'], '/tmp/nightshade-test/out.fits.nsrecipe');
    expect(args['screenTransfer'], isFalse);
    expect((args['outputs'] as List).single, {
      'format': 'fits',
      'path': '/tmp/nightshade-test/out.fits',
    });
    expect((args['renderId'] as String), startsWith('darkroom-export-$root-'));

    // The reply's own numbers are reported back, sidecar included.
    expect(find.text('Written'), findsOneWidget);
    expect(
      find.textContaining('/tmp/nightshade-test/out.fits.nsrecipe'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('an after-step export carries the index it stops at', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    await tester.tap(find.widgetWithText(NightshadeChip, 'After a step'));
    await settle(tester);
    await tester.tap(find.text('Export'));
    await settle(tester);

    final stage = darkroom.exportArgs.single['stage'] as Map;
    expect(stage['kind'], 'afterStep');
    expect(stage['index'], 1);
    await drain(tester);
  });

  testWidgets('a cancelled export says so and reports no file', (tester) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    final held = Completer<void>();
    darkroom.holdExport = held;
    darkroom.exportFailure = const DarkroomCancelledOutcome(
      id: 'darkroom-export',
      phase: 'render',
      payload: {'kind': 'cancelled'},
    );
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    expect(darkroom.cancelArgs.last['op'], 'cancel');

    held.complete();
    await settle(tester);
    expect(
      find.textContaining('stopped during render. No file was written.'),
      findsOneWidget,
    );
    expect(find.text('Written'), findsNothing);
    await drain(tester);
  });

  testWidgets('a cancelled save picker exports nothing at all', (tester) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    pickerAnswer = null;
    await pump(tester, root);
    await openExport(tester);

    await tester.tap(find.text('Export'));
    await settle(tester);

    expect(pickerCalls, hasLength(1));
    expect(darkroom.exportArgs, isEmpty);
    expect(find.text('Written'), findsNothing);
    await drain(tester);
  });
}
