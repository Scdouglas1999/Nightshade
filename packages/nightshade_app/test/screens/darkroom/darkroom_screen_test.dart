// Widget tests for the Darkroom editor screen.
//
// The screen is one rendering of one controller state, so these assert the
// things a reader of the code cannot see: that a remote client is told where
// the work lives instead of being shown an empty canvas, that a bad deep link
// explains itself, that every step card states what the render DID with it, and
// that a skip reason is on the card rather than behind the expander.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_database.dart';
import '../../harness/pump_app_screen.dart';

/// A Darkroom seam whose every reply the test writes.
class _ScriptedDarkroom implements DarkroomSeam {
  bool validateOk = true;
  String validateError = 'a linear operation cannot run after a stretch';
  Map<int, String> skipReasons = {};
  Completer<void>? holdPreview;

  /// `opId@opVersion` keys this scripted build does not register, keyed on the
  /// operation the way the engine's registry is. Both entry points then behave
  /// as the engine does: `validate` diagnoses every step and refuses the recipe,
  /// and `renderPreview` refuses before it touches a pixel.
  Set<String> unregisteredOps = {};

  /// When set, the next preview throws this instead of answering — the shape a
  /// master that moved off disk takes at the seam.
  Object? previewError;

  final List<Map<String, dynamic>> cancelArgs = [];

  static String _opKey(Map<String, dynamic> step) =>
      '${step['opId']}@${step['opVersion']}';

  int? _firstUnregistered(List<dynamic> steps) {
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i] as Map<String, dynamic>;
      if (unregisteredOps.contains(_opKey(step))) return i;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    final unknown = _firstUnregistered(steps);
    return {
      'ok': validateOk && unknown == null,
      'error': unknown != null
          ? 'step $unknown: no operation registered as '
              '${_opKey(steps[unknown] as Map<String, dynamic>)}'
          : (validateOk ? null : validateError),
      'steps': [
        for (var i = 0; i < steps.length; i++)
          {
            'index': i,
            'opId': (steps[i] as Map<String, dynamic>)['opId'],
            'opVersion': (steps[i] as Map<String, dynamic>)['opVersion'],
            'registered': !unregisteredOps
                .contains(_opKey(steps[i] as Map<String, dynamic>)),
            'valid': !unregisteredOps
                .contains(_opKey(steps[i] as Map<String, dynamic>)),
            if (unregisteredOps
                .contains(_opKey(steps[i] as Map<String, dynamic>)))
              'error': 'no operation registered as '
                  '${_opKey(steps[i] as Map<String, dynamic>)}',
          },
      ],
    };
  }

  @override
  Future<DarkroomRenderedPreview> renderPreview({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    final hold = holdPreview;
    if (hold != null) {
      holdPreview = null;
      await hold.future;
    }
    final failure = previewError;
    if (failure != null) {
      previewError = null;
      throw failure;
    }
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    final unknown = _firstUnregistered(steps);
    if (unknown != null) {
      throw DarkroomSeamException(
        'renderPreview',
        'step $unknown: no operation registered as '
            '${_opKey(steps[unknown] as Map<String, dynamic>)}',
        StateError('unregistered op'),
      );
    }
    return DarkroomRenderedPreview(
      width: 2,
      height: 2,
      isColor: false,
      rgba: Uint8List(2 * 2 * 4),
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
                    ((steps[i] as Map<String, dynamic>)['enabled'] as bool) ==
                            false
                        ? 'disabled'
                        : (skipReasons.containsKey(i) ? 'skipped' : 'applied'),
                if (skipReasons.containsKey(i)) 'reason': skipReasons[i],
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
    throw StateError('the editor does not export in these tests');
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
          'params': [
            {
              'name': 'sampleSpacing',
              'kind': 'number',
              'required': false,
              'min': 8.0,
              'max': 1024.0,
              'default': 64.0,
              'independent': true,
              'summary': 'Spacing between background sample boxes.',
            },
          ],
        },
        {
          'id': 'color_calibrate',
          'version': 1,
          'stage': 'linear',
          'summary': 'Fits a B−V colour-versus-flux regression.',
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

Map<String, dynamic> _step(
  String opId, {
  bool enabled = true,
  int opVersion = 1,
  Map<String, dynamic> params = const <String, dynamic>{},
}) =>
    {
      'opId': opId,
      'opVersion': opVersion,
      'params': params,
      'enabled': enabled,
    };

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) {
    // ignore: invalid_use_of_protected_member
    state = backend;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedDarkroom darkroom;
  late NightshadeDatabase db;

  setUp(() {
    darkroom = _ScriptedDarkroom();
    db = mockDatabase();
  });

  Future<int> seedRecipe(List<Map<String, dynamic>> steps) {
    return RecipesDao(db).create(
      baseMasterPath: _masterPath,
      name: 'Draft',
      stepsJson: jsonEncode(steps),
      createdBy: RecipeAuthor.autopilot,
    );
  }

  Future<HarnessHandle> pump(
    WidgetTester tester,
    DarkroomScope scope, {
    Size size = const Size(1280, 800),
  }) async {
    final handle = await pumpAppScreen(
      tester,
      DarkroomScreen(scope: scope),
      size: size,
      database: db,
      settle: false,
      extraOverrides: [
        darkroomSeamProvider.overrideWithValue(darkroom),
        dawnPhotometryResolverProvider.overrideWithValue(_emptyPhotometry()),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return handle;
  }

  /// Pump past every timer the screen arms — the render debounce, the write
  /// debounce and a toast's own dismissal — so teardown finds none pending.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  testWidgets('a remote client is told where the work lives', (tester) async {
    final backend = NetworkBackend(
      serverHost: '10.0.0.8',
      serverPort: 8080,
      webSocketPort: 8080,
      autoConnectWebSocket: false,
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          darkroomSeamProvider.overrideWithValue(darkroom),
          dawnPhotometryResolverProvider.overrideWithValue(_emptyPhotometry()),
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
        child: const MaterialApp(
          home: DarkroomScreen(scope: DarkroomScope.recipe(1)),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Open the Darkroom on the imaging host'),
      findsOneWidget,
    );
    expect(find.byKey(kDarkroomPreviewSurfaceKey), findsNothing);
  });

  testWidgets(
    'a --remote-host client that has not reached its rig is told where the '
    'work lives',
    (tester) async {
      // Launched as a client, backend still `Disconnected`: the pre-handshake
      // window, and again after every drop. Gating the editor on
      // `backendProvider is NetworkBackend` read false here, so the full editor
      // opened over the CLIENT's own database — recipes no dawn job on the rig
      // will ever read — while Delivery settings on the same launch correctly
      // refused, because it gates on the role.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            darkroomSeamProvider.overrideWithValue(darkroom),
            dawnPhotometryResolverProvider
                .overrideWithValue(_emptyPhotometry()),
            remoteClientLaunchProvider.overrideWithValue(true),
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, DisconnectedBackend()),
            ),
          ],
          child: const MaterialApp(
            home: DarkroomScreen(scope: DarkroomScope.recipe(1)),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Open the Darkroom on the imaging host'),
        findsOneWidget,
      );
      expect(find.byKey(kDarkroomPreviewSurfaceKey), findsNothing);
    },
  );

  testWidgets('a link that names nothing explains itself and offers a way out',
      (tester) async {
    await pump(tester, const DarkroomScope.empty());
    expect(find.text('Nothing to open in the Darkroom'), findsOneWidget);
    expect(
      find.textContaining('named neither a recipe nor a master'),
      findsOneWidget,
    );
    // The header action is suppressed here, so without this the only route out
    // of the sentinel is the nav rail.
    expect(find.text('Back to session review'), findsOneWidget);
  });

  testWidgets('a recipe id with no row names the row AND a route back', (
    tester,
  ) async {
    await pump(tester, const DarkroomScope.recipe(4242));
    expect(find.text('Nothing to open in the Darkroom'), findsOneWidget);
    expect(
      find.textContaining('Recipe 4242 no longer has a row'),
      findsOneWidget,
    );
    expect(find.text('Back to session review'), findsOneWidget);
  });

  testWidgets('a recipe renders its stack, its picture and its outcomes', (
    tester,
  ) async {
    final id = await seedRecipe([
      _step('background_extract'),
      _step('color_calibrate'),
    ]);
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('Background extract'), findsOneWidget);
    expect(find.text('Color calibrate'), findsOneWidget);
    expect(find.byKey(kDarkroomPreviewSurfaceKey), findsOneWidget);
    expect(find.text('Applied by the last render'), findsNWidgets(2));
    // The zoom readout is about the master, never about the pyramid level.
    expect(find.textContaining('% of master'), findsOneWidget);
  });

  testWidgets('a skipped step shows its reason without being expanded', (
    tester,
  ) async {
    darkroom.skipReasons = {
      0: 'no photometric catalogue is installed, so the colour fit has nothing '
          'to regress against',
    };
    final id = await seedRecipe([_step('color_calibrate')]);
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('Skipped, and here is why'), findsOneWidget);
    expect(
      find.textContaining('nothing to regress against'),
      findsOneWidget,
    );
    // The reason is on the card, not behind the expander.
    expect(find.text('Parameters'), findsNothing);
  });

  testWidgets('the enable switch turns a step off without destroying it', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    await tester.tap(find.byType(NightshadeSwitch).first);
    await tester.pump();

    final state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.steps.single.enabled, isFalse);
    expect(state.steps, hasLength(1));

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    // The CARD, not only the header: the screen once repainted its step count
    // while every card kept the state before the toggle.
    expect(
      tester
          .widget<NightshadeSwitch>(find.byType(NightshadeSwitch).first)
          .value,
      isFalse,
    );
    expect(find.text('Off — the render skipped it'), findsOneWidget);
    expect(find.text('1 step · 0 on'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the viewport names the transfer the engine applied', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    await pump(tester, DarkroomScope.recipe(id));

    // The engine names it; the strip must not claim otherwise.
    expect(
      find.textContaining('the engine did not name the display transfer'),
      findsNothing,
    );
    expect(
      find.textContaining('a screen transfer, applied for display only'),
      findsOneWidget,
    );
    expect(find.textContaining('over still-linear pixels'), findsOneWidget);
    // The lift's own numbers ride behind the tag beside it.
    expect(find.text('Screen transfer'), findsOneWidget);
  });

  testWidgets(
      'a refused reorder states itself on the panel, not only in a '
      'toast', (tester) async {
    final id = await seedRecipe([
      _step('background_extract'),
      _step('color_calibrate'),
    ]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    darkroom.validateOk = false;
    await handle.container
        .read(darkroomControllerProvider(scope).notifier)
        .reorderStep(1, 0);
    await tester.pump();
    await tester.pump();

    // The card snaps back on its own, which reads as a dropped gesture; the
    // engine's sentence stays beside the stack it is about.
    expect(find.text('That move was refused'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NightshadeAlert),
        matching: find.textContaining('linear operation cannot run after a '
            'stretch'),
      ),
      findsWidgets,
    );
    await drain(tester);
  });

  testWidgets('compare with no sibling publishes disabled and why', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    await pump(tester, DarkroomScope.recipe(id));

    final handle = tester.ensureSemantics();
    final compare = find.bySemanticsLabel(RegExp('^Compare — '));
    expect(compare, findsOneWidget);
    final flags = tester.getSemantics(compare).flagsCollection;
    expect(flags.isButton, isTrue);
    // Tristate.isFalse, not Tristate.none: a control that publishes no enabled
    // state at all reads to assistive tech — and to the audit harness — as a
    // live button, however dimly it is painted.
    expect(flags.isEnabled, Tristate.isFalse);
    expect(
      tester.getSemantics(compare).label,
      contains('Duplicate this one as a variant'),
    );
    handle.dispose();
  });

  testWidgets(
      'the recipe panel scrolls visibly and keeps the skip reason '
      'above the fold', (tester) async {
    final id = await seedRecipe([_step('color_calibrate')]);
    await pump(tester, DarkroomScope.recipe(id));

    // An always-drawn scrollbar is what turns the card's cut-off last line
    // into "there is more below" rather than into a rendering fault.
    expect(
      find.descendant(
        of: find.byType(AdaptivePanelLayout),
        matching: find.byType(Scrollbar),
      ),
      findsWidgets,
    );
    final alert = find.text('Color calibration has no catalogue stars');
    expect(alert, findsOneWidget);
    // Above the recipe's own identity block, which is the reference material
    // that pushed the reason past the fold at desktop width.
    expect(
      tester.getTopLeft(alert).dy,
      lessThan(tester.getTopLeft(find.text('Base master')).dy),
    );
  });

  testWidgets('the parameter controls come from the registry schema', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('Parameters'), findsOneWidget);
    await tester.tap(find.text('Parameters'));
    await tester.pump();

    expect(find.text('sampleSpacing'), findsOneWidget);
    expect(
      find.text('Spacing between background sample boxes.'),
      findsOneWidget,
    );
    // 8…1024 is a range a slider can resolve, so it gets one.
    expect(find.byType(NightshadeSlider), findsOneWidget);
    // No stored value: the operation's own default is what renders.
    expect(find.text('default'), findsOneWidget);
  });

  testWidgets('a refused reorder says why and leaves the order alone', (
    tester,
  ) async {
    final id = await seedRecipe([
      _step('background_extract'),
      _step('color_calibrate'),
    ]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    darkroom.validateOk = false;
    await handle.container
        .read(darkroomControllerProvider(scope).notifier)
        .reorderStep(1, 0);
    await tester.pump();
    await tester.pump();

    final state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.steps.map((s) => s.opId), [
      'background_extract',
      'color_calibrate',
    ]);
    expect(
      find.textContaining('linear operation cannot run after a stretch'),
      findsWidgets,
    );
    await drain(tester);
  });

  testWidgets('a long render offers a cooperative stop', (tester) async {
    final id = await seedRecipe([_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    final held = Completer<void>();
    darkroom.holdPreview = held;
    final handle = await pump(tester, scope);

    expect(find.text('Stop render'), findsOneWidget);
    await tester.tap(find.text('Stop render'));
    await tester.pump();
    await tester.pump();

    // The stop is cooperative, so the button says so until the render answers.
    expect(find.text('Stopping…'), findsOneWidget);
    expect(darkroom.cancelArgs.single['op'], 'cancel');

    held.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      handle.container.read(darkroomControllerProvider(scope)).rendering,
      isFalse,
    );
  });

  testWidgets('reset to linear switches every step off, and undo restores it', (
    tester,
  ) async {
    final id = await seedRecipe([
      _step('background_extract'),
      _step('color_calibrate'),
    ]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    await tester.tap(find.text('Reset to linear'));
    await tester.pump();

    var state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.isLinear, isTrue);
    expect(state.steps, hasLength(2));

    await tester.tap(find.text('Undo'));
    await tester.pump();
    state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.steps.every((s) => s.enabled), isTrue);
    await drain(tester);
  });

  testWidgets('a phone reflows into segments instead of miniaturising', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    await pump(
      tester,
      DarkroomScope.recipe(id),
      size: const Size(390, 844),
    );

    // The three regions become three segments; the image is the default one.
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Recipe'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.byKey(kDarkroomPreviewSurfaceKey), findsOneWidget);
  });

  testWidgets('a failed render labels the picture it left up, on the picture',
      (tester) async {
    final id =
        await seedRecipe([_step('background_extract'), _step('stretch')]);
    final scope = DarkroomScope.recipe(id);
    // Tall enough that the Recipe panel's own "Render again" is on screen: a
    // tap aimed at a control below the fold hits nothing at all.
    final handle = await pump(tester, scope, size: const Size(1280, 1400));

    // A render landed, so there are pixels on screen.
    expect(find.byKey(kDarkroomPreviewSurfaceKey), findsOneWidget);
    expect(find.textContaining('The render did not finish'), findsNothing);

    // The master moves off disk and the next render fails. The preview is NOT
    // dropped — an editor that blanks on a failure loses the last picture the
    // operator could trust — so the picture that stays up has to say what it
    // is.
    darkroom.previewError = DarkroomSeamException(
      'renderPreview',
      "cannot read '$_masterPath': No such file or directory (os error 2)",
      StateError('missing master'),
    );
    await tester.tap(find.widgetWithText(NightshadeButton, 'Render again'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.preview, isNotNull, reason: 'the previous frame stays up');
    expect(state.renderError, isNotNull);

    // On the viewport itself, not only in the Recipe panel: the tag, the
    // engine's own sentence, and a strip that stops describing the stale frame
    // as the current stack's.
    expect(find.text('Stale — the render did not finish'), findsOneWidget);
    expect(
      find.textContaining('No such file or directory'),
      findsWidgets,
    );
    expect(
      find.textContaining('Display transfer of the last render that finished'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('at phone width the failure is in the Image segment too',
      (tester) async {
    final id =
        await seedRecipe([_step('background_extract'), _step('stretch')]);
    final scope = DarkroomScope.recipe(id);
    await pump(tester, scope, size: const Size(430, 900));

    // Fail a render from the Recipe segment, then go back to the picture. At
    // this width the Recipe panel is a segment the operator is not looking at,
    // so a failure stated only there leaves the Image segment showing a stale
    // picture with nothing to say it is one.
    await tester.tap(find.text('Recipe').last);
    await tester.pump();
    darkroom.previewError = DarkroomSeamException(
      'renderPreview',
      "cannot read '$_masterPath': No such file or directory (os error 2)",
      StateError('missing master'),
    );
    final rerender = find.widgetWithText(NightshadeButton, 'Render again');
    await tester.ensureVisible(rerender);
    await tester.pump();
    await tester.tap(rerender);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await tester.tap(find.text('Image'));
    await tester.pump();
    expect(find.byKey(kDarkroomPreviewSurfaceKey), findsOneWidget);
    expect(find.text('Stale — the render did not finish'), findsOneWidget);
    expect(find.textContaining('No such file or directory'), findsWidgets);
    await drain(tester);
  });

  testWidgets('a parameter slider follows the whole drag, not just its start',
      (tester) async {
    final id = await seedRecipe([_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    // Tall enough that the expanded control is on screen: a gesture aimed
    // outside the window hits nothing at all.
    final handle = await pump(tester, scope, size: const Size(1280, 1400));

    await tester.tap(find.text('Parameters'));
    await tester.pump();
    final slider = find.byType(NightshadeSlider);
    expect(slider, findsOneWidget);

    // Press on the middle of the track and sweep right in held steps, the way
    // a finger or a mouse does. Every update in the gesture has to land: the
    // card used to be re-keyed by the first one, which tore its subtree down
    // and took the drag recognizer with it — the slider then took the value
    // under the pointer at press and ignored the rest of the sweep.
    num storedValue() => handle.container
        .read(darkroomControllerProvider(scope))
        .steps[0]
        .params['sampleSpacing'] as num;

    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(
      Offset(box.left + 32, box.center.dy),
    );
    // The first move has to clear the drag slop before the slider hears
    // anything at all; everything after it is the rest of the gesture.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final afterFirstUpdate = storedValue();

    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    // Under the defect these two are equal: the first update re-keyed the card,
    // the subtree was rebuilt, and the recognizer that would have delivered the
    // rest of the sweep went with it.
    expect(storedValue(), greaterThan(afterFirstUpdate));
    await drain(tester);
  });

  testWidgets('the catalogue note is absent from a stack with no colour step',
      (tester) async {
    // The resolver is bound to an empty catalogue, so the photometry note is
    // set on every recipe. It is about `color_calibrate` and nothing else.
    final id = await seedRecipe([_step('background_extract')]);
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('Color calibration has no catalogue stars'), findsNothing);
    expect(find.textContaining('no catalogue star'), findsNothing);
  });

  testWidgets('a zero-step recipe reports no missing catalogue either', (
    tester,
  ) async {
    final id = await seedRecipe(const []);
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('Nothing interpreted yet'), findsOneWidget);
    expect(find.text('Color calibration has no catalogue stars'), findsNothing);
  });

  testWidgets('every step card names its own controls to a screen reader', (
    tester,
  ) async {
    final id = await seedRecipe([
      _step('background_extract'),
      _step('color_calibrate'),
    ]);
    await pump(tester, DarkroomScope.recipe(id));

    final semantics = tester.ensureSemantics();
    // Four sibling nodes all reading "Parameters, button" name no operation.
    expect(
      find.bySemanticsLabel('Background extract parameters'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Remove Background extract'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove Color calibrate'), findsOneWidget);
    // color_calibrate publishes no parameters in this registry, so its card has
    // no expander to name — and still has its own remove control.
    expect(find.bySemanticsLabel('Color calibrate parameters'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a parameter slider says its name and its value', (tester) async {
    final id = await seedRecipe([
      _step('background_extract', params: {'sampleSpacing': 100.0}),
    ]);
    await pump(tester, DarkroomScope.recipe(id), size: const Size(1280, 1400));
    await tester.tap(find.text('Parameters'));
    await tester.pump();

    final semantics = tester.ensureSemantics();
    // The slider used to publish an empty name, no value and no value
    // interface: a screen-reader walk of a card with three of them heard
    // "slider" three times and learned nothing. The label and the readout were
    // sighted-only.
    final node = tester.getSemantics(find.byType(NightshadeSlider));
    expect(node.label, contains('sampleSpacing'));
    expect(node.label, contains('100'));
    expect(node.value, '100');
    // Assistive tech can move it, and is told where each step lands.
    expect(node.increasedValue, isNotEmpty);
    expect(node.decreasedValue, isNotEmpty);
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    semantics.dispose();
    await drain(tester);
  });

  testWidgets('"Use default" names the parameter it resets', (tester) async {
    final id = await seedRecipe([
      _step('background_extract', params: {'sampleSpacing': 100.0}),
    ]);
    await pump(tester, DarkroomScope.recipe(id), size: const Size(1280, 1400));
    await tester.tap(find.text('Parameters'));
    await tester.pump();

    final semantics = tester.ensureSemantics();
    // Unqualified, this is three words repeated once per parameter, and only
    // reading order says which one each belongs to — the defect this file's
    // Remove and Parameters controls were already fixed for.
    expect(
      find.bySemanticsLabel('Use default for sampleSpacing'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Use default'), findsNothing);
    semantics.dispose();
    await drain(tester);
  });

  testWidgets('a re-render keeps the previous frame instead of a spinner', (
    tester,
  ) async {
    final id = await seedRecipe([_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    // The first frame has to be decoded before "kept" means anything.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // A second render lands with a buffer the surface has not decoded yet.
    await handle.container
        .read(darkroomControllerProvider(scope).notifier)
        .refreshRender();
    await tester.pump();

    // The picture is still on screen, with a tag saying a newer frame is on its
    // way — rather than the canvas dropping to a spinner, which is what made a
    // parameter drag strobe.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('New frame…'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('New frame…'), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an unregistered step keeps its controls as separate nodes', (
    tester,
  ) async {
    darkroom.unregisteredOps = {'stretch@99'};
    final id = await seedRecipe([_step('stretch', opVersion: 99)]);
    await pump(tester, DarkroomScope.recipe(id));

    final semantics = tester.ensureSemantics();
    // The error case is exactly where the card used to collapse into one
    // ~200-character toggle: with no registered spec it had a single focusable
    // descendant and the whole card merged into it.
    expect(find.bySemanticsLabel('Stretch enabled'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove Stretch'), findsOneWidget);
    // The card's own node opens with the reorder label, exactly as a
    // well-formed card's does, rather than the whole card being one control.
    expect(find.bySemanticsLabel(RegExp('^Reorder Stretch')), findsOneWidget);
    semantics.dispose();
    await drain(tester);
  });

  testWidgets('a step switched off stops blocking the stack', (tester) async {
    darkroom.unregisteredOps = {'stretch@99'};
    final id = await seedRecipe([
      _step('background_extract'),
      _step('stretch', opVersion: 99),
    ]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope);

    expect(find.text('This stack does not validate'), findsOneWidget);

    handle.container
        .read(darkroomControllerProvider(scope).notifier)
        .toggleStep(1);
    await drain(tester);

    // The render replays enabled steps only, so a step that is off cannot make
    // the stack unrenderable — and the panel stops saying it does.
    expect(find.text('This stack does not validate'), findsNothing);
    expect(find.text('The render did not finish'), findsNothing);
    // The step itself still says what this build cannot do with it.
    expect(
      find.textContaining('This build registers no stretch@99'),
      findsWidgets,
    );
    expect(
      find.textContaining('left out of the render'),
      findsOneWidget,
    );
  });

  testWidgets(
      'a missing master names the next step; a step failure is left alone',
      (tester) async {
    final id = await seedRecipe([_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    final handle = await pump(tester, scope, size: const Size(1280, 1400));

    // The master moves off disk. Every base-master refusal the engine raises
    // quotes the path, and that is the one failure the operator can act on —
    // outside this screen, which is why the failure card's own "Render again"
    // cannot be the whole answer.
    darkroom.previewError = DarkroomSeamException(
      'renderPreview',
      "cannot read '$_masterPath': No such file or directory (os error 2)",
      StateError('missing master'),
    );
    await tester.tap(find.widgetWithText(NightshadeButton, 'Render again'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    var state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.renderError, contains('No such file or directory'));
    expect(state.renderError, contains('restore the master at that path'));
    expect(state.renderError, contains('re-integrate this night in Session'));

    // A step failure names no file, so it keeps the engine's sentence and is
    // not sent off to rebuild a master that is perfectly fine.
    darkroom.previewError = DarkroomSeamException(
      'renderPreview',
      'step 0: background_extract refused sampleSpacing=0',
      StateError('bad parameter'),
    );
    // Through the controller: the failure card above the button has grown by a
    // sentence, so the button it used to sit beside is now off the window.
    await handle.container
        .read(darkroomControllerProvider(scope).notifier)
        .refreshRender();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    state = handle.container.read(darkroomControllerProvider(scope));
    expect(state.renderError, contains('refused sampleSpacing=0'));
    expect(state.renderError, isNot(contains('re-integrate this night')));
    await drain(tester);
  });

  testWidgets('a long draft account collapses at a word, with a way to open it',
      (tester) async {
    const reason =
        'this master has 1 channel(s) and the colour fit needs three, so this '
        'draft covers the one channel it was given; to calibrate colour, '
        'combine the per-filter masters into a single three-channel master and '
        'draft that composite';
    final id = await RecipesDao(db).create(
      baseMasterPath: _masterPath,
      name: 'Draft',
      stepsJson: jsonEncode([_step('background_extract')]),
      createdBy: RecipeAuthor.autopilot,
      draftNotes: const [
        RecipeDraftNote(
          opId: 'color_calibrate',
          outcome: 'omitted',
          reason: reason,
        ),
      ],
    );
    await pump(tester, DarkroomScope.recipe(id));

    expect(find.text('The draft left one operation out'), findsOneWidget);
    // Collapsed: whole words and an explicit mark, never a clause cut in half
    // by wherever the panel's scroll fold happens to land.
    final collapsed = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .firstWhere((data) => data.startsWith('Color calibrate — omitted:'));
    expect(collapsed.endsWith('…'), isTrue, reason: collapsed);
    expect(collapsed, isNot(contains('draft that composite')));
    expect(collapsed.length, lessThan(reason.length));
    expect(
      RegExp(r'\S…$').hasMatch(collapsed) &&
          !RegExp(r'\s…$').hasMatch(collapsed),
      isTrue,
      reason: 'the cut lands after a whole word: $collapsed',
    );

    // The control that completes the sentence is INSIDE the alert that carries
    // it. Under the alert it was a separate row in the panel's scroll view, so
    // the truncated text sat above the fold and the button that said the rest
    // existed sat below it; sharing the alert's box is what makes them share a
    // viewport whatever the panel's height.
    final alert = find.ancestor(
      of: find.textContaining('Color calibrate — omitted:'),
      matching: find.byType(NightshadeAlert),
    );
    expect(alert, findsOneWidget);
    final expand = find.descendant(
      of: alert,
      matching: find.widgetWithText(NightshadeButton, 'Show more'),
    );
    expect(expand, findsOneWidget);
    // Where inside the alert depends on the alert's width, and this panel is a
    // ~330px column: under that breakpoint [NightshadeAlert] lays its action
    // under the TITLE and above the message, at the alert's own width, because
    // beside the text it would be squeezed to half a phone-width alert and the
    // message would wrap down the whole screen. The panel viewport is 256px and
    // the account is longer than that in either arrangement, so the control is
    // scrolled to the way an operator scrolls to it — what this case is about
    // is that it travels WITH the sentence it completes rather than sitting in
    // a row of its own somewhere else in the panel, which is what the
    // `find.descendant(of: alert)` above pins.
    await tester.ensureVisible(expand);
    await tester.pump();
    await tester.tap(expand);
    await tester.pump();

    expect(find.textContaining('draft that composite'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.textContaining('draft that composite'),
          matching: find.byType(NightshadeAlert),
        ),
        matching: find.widgetWithText(NightshadeButton, 'Show less'),
      ),
      findsOneWidget,
    );
    await drain(tester);
  });
}
