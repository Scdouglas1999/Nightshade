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
//    the engine derives one;
//  * what those controls publish to assistive tech — the refusal's reason, the
//    export sheet's answer to Escape, its phone presentation, and a
//    hold-to-compare that a keyboard can work.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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
        // The engine's own shape (bridge render.rs `description`): an object,
        // never a sentence.
        'encoding': {
          'requested': 'auto',
          'applied': 'screen',
          'sourceDomain': 'linear',
          'clampedSamples': 0,
          'screenTransfer': {
            'blackPoint': 529.75,
            'whitePoint': 531.19,
            'd': 2.57,
          },
          'screenTransferAffectsRecipe': false,
        },
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
    expect(find.textContaining('cannot be deleted while 1 branch'),
        findsOneWidget);
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

  // ---------------------------------------------------------------------
  // Accessibility and the modal contract
  //
  // Driving the release build through AT-SPI turned up four things the widget
  // tree above could not see: the refused format chips announced no reason for
  // their refusal, Escape did nothing at all, the sheet stayed a 640-wide
  // centred card on a 430-wide phone, and hold-to-compare published a button
  // with no enabled state and no action — reported as `[DISABLED]`, unusable
  // from a keyboard or from assistive tech.
  // ---------------------------------------------------------------------

  SemanticsData dataFor(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  testWidgets('a refused format announces the refusal, not just a grey chip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final root = await seedRecipe([_step('background_extract')]);
    await pump(tester, root);
    await openExport(tester);

    final png = dataFor(tester, find.widgetWithText(NightshadeChip, 'PNG'));
    expect(png.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(png.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(png.hasFlag(SemanticsFlag.isEnabled), isFalse);
    // No live tap beside the disabled flag — the refusal is not a dare.
    expect(png.hasAction(SemanticsAction.tap), isFalse);
    // The reason rides the NAME, not the hint. Measured on the Linux release
    // bundle: every chip came back over AT-SPI as `'PNG' | button | desc: ''`,
    // so a hint-only reason reaches a screen reader on this platform not at
    // all. One node, still starting with the option's own word.
    expect(png.label, startsWith('PNG'));
    expect(png.label, contains('still linear ADU'));

    final fits = dataFor(tester, find.widgetWithText(NightshadeChip, 'FITS'));
    expect(fits.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(fits.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(fits.hasAction(SemanticsAction.tap), isTrue);
    expect(fits.hint, contains('Always available'));

    // Turning the auto stretch on makes the same chip readable as available.
    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);
    final pngNow = dataFor(tester, find.widgetWithText(NightshadeChip, 'PNG'));
    expect(pngNow.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(pngNow.hasAction(SemanticsAction.tap), isTrue);
    expect(pngNow.hint, contains('16-bit PNG'));

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
    handle.dispose();
  });

  testWidgets('Escape closes the export sheet when nothing is running', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);
    expect(find.textContaining('Export "Draft"'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(find.textContaining('Export "Draft"'), findsNothing);
    await drain(tester);
  });

  testWidgets('Escape mid-export keeps the sheet up and says why', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    final held = Completer<void>();
    darkroom.holdExport = held;
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.textContaining('Export "Draft"'), findsOneWidget);
    expect(
      find.text('This sheet stays up while the export runs'),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing left to report its outcome to'),
      findsOneWidget,
    );

    // And it stops saying so once the render is out of the engine.
    held.complete();
    await settle(tester);
    expect(
      find.text('This sheet stays up while the export runs'),
      findsNothing,
    );
    await drain(tester);
  });

  testWidgets('a phone gets the export sheet as a bottom sheet', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root, size: const Size(430, 932));
    await openExport(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.getRect(find.byType(BottomSheet));
    // Anchored to the bottom edge and the full width of the viewport, not a
    // 640-wide card floating in the middle of a 430-wide screen.
    expect(sheet.left, closeTo(0, 0.5));
    expect(sheet.width, closeTo(430, 0.5));
    expect(sheet.bottom, closeTo(932, 0.5));

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('a desktop window keeps the export sheet a centred dialog', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsWidgets);

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('hold-to-compare is an operable toggle, not a dead button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
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
    final node = tester.getSemantics(hold);
    final data = node.getSemanticsData();
    expect(data.label, 'Hold to see Warmer');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    // The whole defect: `Semantics(button:)` with no `enabled` and no action
    // published a node the AT-SPI bridge reported as DISABLED.
    expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hasFlag(SemanticsFlag.hasToggledState), isTrue);
    expect(data.hasFlag(SemanticsFlag.isToggled), isFalse);
    expect(data.hasFlag(SemanticsFlag.isFocusable), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(data.hint, contains('activate'));

    // Operated the way assistive tech operates it: activate pins the other
    // recipe up, activate again releases it. A press-and-hold cannot be
    // performed at all from a keyboard or a screen reader.
    final owner = tester.binding.pipelineOwner.semanticsOwner!;
    owner.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(find.text('Showing B'), findsOneWidget);
    expect(
      tester.getSemantics(hold).getSemanticsData().hasFlag(
            SemanticsFlag.isToggled,
          ),
      isTrue,
    );
    // The blink timer cannot take it away while it is pinned.
    await tester.pump(kDarkroomBlinkInterval * 2);
    expect(find.text('Showing B'), findsOneWidget);

    owner.performAction(tester.getSemantics(hold).id, SemanticsAction.tap);
    await tester.pump();
    expect(
      tester.getSemantics(hold).getSemanticsData().hasFlag(
            SemanticsFlag.isToggled,
          ),
      isFalse,
    );
    await drain(tester);
    handle.dispose();
  });

  testWidgets('side by side offers no hold control, having nothing to hold', (
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

    // Both renders are already on screen, so pinning B changes nothing — and a
    // control that publishes an on/off state while changing nothing is a lie.
    expect(find.byType(AstroImageViewer), findsNWidgets(2));
    expect(find.text('Hold to see Warmer'), findsNothing);
    await drain(tester);
  });

  // ---------------------------------------------------------------------
  // The export sheet on a recipe with nothing in it, and the auto stretch as
  // a control that stays put.
  //
  // Measured on the release bundle before these landed: a zero-step recipe
  // offered "After a step" greyed out with its reason nowhere on the sheet and
  // nowhere in its accessible name, under a stage line reading "Every enabled
  // step…" over a History panel saying the recipe carries no operations; and
  // switching the auto stretch ON deleted the switch, the alert and every
  // sentence about the transfer, leaving a sheet identical to a genuinely
  // stretched stage with no way back.
  // ---------------------------------------------------------------------

  testWidgets('a zero-step recipe states WHY "After a step" is dead', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final root = await seedRecipe(const []);
    await pump(tester, root);
    await openExport(tester);

    final after = tester.widget<NightshadeChip>(
      find.widgetWithText(NightshadeChip, 'After a step'),
    );
    expect(after.enabled, isFalse);

    // On screen for a touch screen, which has neither hover nor a pointer.
    expect(
      find.text('"After a step" is unavailable for this recipe'),
      findsOneWidget,
    );
    expect(
      find.textContaining('there is no step to stop after'),
      findsOneWidget,
    );

    // And in the accessible name for a screen reader, because the hint does
    // not survive the Linux AT-SPI bridge.
    final data =
        dataFor(tester, find.widgetWithText(NightshadeChip, 'After a step'));
    expect(data.label, startsWith('After a step'));
    expect(data.label, contains('there is no step to stop after'));
    expect(data.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
    handle.dispose();
  });

  testWidgets('the stage line counts the recipe rather than asserting steps', (
    tester,
  ) async {
    final empty = await seedRecipe(const [], name: 'Empty');
    await pump(tester, empty);
    await openExport(tester);

    expect(
      find.textContaining('Every enabled step, at the master\'s full'),
      findsNothing,
    );
    expect(
      find.textContaining('This recipe carries no steps, so the final stage '
          'applies nothing'),
      findsOneWidget,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('the stage line says so when every step is switched off', (
    tester,
  ) async {
    final off = await seedRecipe([
      _step('background_extract', enabled: false),
      _step('stretch', enabled: false),
    ], name: 'All off');
    await pump(tester, off);
    await openExport(tester);

    expect(
      find.textContaining('All 2 steps in this recipe are switched off'),
      findsOneWidget,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('the stage line counts only the enabled steps', (tester) async {
    final mixed = await seedRecipe([
      _step('background_extract'),
      _step('stretch', enabled: false),
    ], name: 'Mixed');
    await pump(tester, mixed);
    await openExport(tester);

    expect(find.textContaining('The 1 enabled step of 2'), findsOneWidget);

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('the auto stretch switch stays put and can be turned back off', (
    tester,
  ) async {
    const switchLabel = 'Render the 8/16-bit files through the auto stretch';
    final root = await seedRecipe([_step('background_extract')]);
    await pump(tester, root);
    await openExport(tester);

    expect(find.text(switchLabel), findsOneWidget);
    expect(
      find.text('PNG, JPEG and TIFF are unavailable for this stage'),
      findsOneWidget,
    );

    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);

    // The control that set it is still there, and still says what is set.
    expect(find.text(switchLabel), findsOneWidget);
    expect(
      tester.widget<NightshadeSwitch>(find.byType(NightshadeSwitch).last).value,
      isTrue,
    );
    expect(
      find.text('PNG, JPEG and TIFF are rendered through the auto stretch'),
      findsOneWidget,
    );
    expect(
      find.textContaining('rendered through the engine\'s own auto stretch'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<NightshadeChip>(find.widgetWithText(NightshadeChip, 'PNG'))
          .enabled,
      isTrue,
    );

    // Off again, in place, without touching the stage.
    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);
    expect(
      tester.widget<NightshadeSwitch>(find.byType(NightshadeSwitch).last).value,
      isFalse,
    );
    expect(
      find.text('PNG, JPEG and TIFF are unavailable for this stage'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<NightshadeChip>(find.widgetWithText(NightshadeChip, 'PNG'))
          .enabled,
      isFalse,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets(
      'turning the stretch off under a chosen raster says Export is '
      'waiting on that choice', (tester) async {
    final root = await seedRecipe([_step('background_extract')]);
    await pump(tester, root);
    await openExport(tester);

    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeChip, 'PNG'));
    await settle(tester);
    await tester.tap(find.byType(NightshadeSwitch).last);
    await settle(tester);

    // A disabled chip renders the same whether or not it is the chosen one, so
    // the sheet names the format that is holding the export.
    expect(
      find.textContaining('PNG is still the chosen format, so Export stays '
          'off'),
      findsOneWidget,
    );
    final export = tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Export'),
    );
    expect(export.onPressed, isNull);

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });

  testWidgets('a stretched stage offers no auto-stretch switch at all', (
    tester,
  ) async {
    final root = await seedRecipe([
      _step('background_extract'),
      _step('stretch'),
    ]);
    await pump(tester, root);
    await openExport(tester);

    // Nothing to opt into: these pixels already carry a display mapping.
    expect(
      find.text('Render the 8/16-bit files through the auto stretch'),
      findsNothing,
    );
    expect(
      find.text('PNG, JPEG and TIFF are rendered through the auto stretch'),
      findsNothing,
    );

    Navigator.of(tester.element(find.text('Export'))).pop();
    await settle(tester);
    await drain(tester);
  });
}
