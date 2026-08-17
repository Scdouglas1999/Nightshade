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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_screen.dart';
import 'package:nightshade_app/widgets/astro_image_viewer.dart';
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

  final List<Map<String, dynamic>> cancelArgs = [];

  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    return {
      'ok': validateOk,
      'error': validateOk ? null : validateError,
      'steps': [
        for (var i = 0; i < steps.length; i++)
          {
            'index': i,
            'opId': (steps[i] as Map<String, dynamic>)['opId'],
            'registered': true,
            'valid': true,
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
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    return DarkroomRenderedPreview(
      width: 2,
      height: 2,
      isColor: false,
      rgba: Uint8List(2 * 2 * 4),
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

Map<String, dynamic> _step(String opId, {bool enabled = true}) => {
      'opId': opId,
      'opVersion': 1,
      'params': <String, dynamic>{},
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
    expect(find.byType(AstroImageViewer), findsNothing);
  });

  testWidgets('a link that names nothing explains itself', (tester) async {
    await pump(tester, const DarkroomScope.empty());
    expect(find.text('Nothing to open in the Darkroom'), findsOneWidget);
    expect(
      find.textContaining('named neither a recipe nor a master'),
      findsOneWidget,
    );
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
    expect(find.byType(AstroImageViewer), findsOneWidget);
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
    expect(find.text('Off — the render skipped it'), findsOneWidget);
    await drain(tester);
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
    expect(find.byType(AstroImageViewer), findsOneWidget);
  });
}
