// Notifier tests for the Darkroom editor's render loop and edit journal.
//
// Every Darkroom native call goes through [DarkroomSeam], so a scripted seam
// exercises the parts that are hard to see from the outside: the debounce that
// turns a slider drag into one render, the single-flight latch that keeps two
// renders out of the engine at once, the generation counter that drops a
// superseded render's pixels, and the cancellation that is an instruction obeyed
// rather than a failure.
//
// The database is real (in-memory): the recipe row is what survives the session,
// so the debounced write is asserted against the row rather than a mock.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/mock_database.dart';

/// A Darkroom seam whose every reply the test writes.
class _ScriptedDarkroom implements DarkroomSeam {
  /// Steps the registry's draft carries.
  List<Map<String, dynamic>> draftSteps = [];

  /// Whether `validate` answers ok.
  bool validateOk = true;

  /// The whole-recipe message a refusal carries.
  String validateError = 'a linear operation cannot run after a stretch';

  /// Per-step verdicts the next validate answers with, by index.
  Map<int, String> stepErrors = {};

  /// Step indices the next preview reports as skipped, with the reason.
  Map<int, String> skipReasons = {};

  /// Completer the next preview waits on, so a test can hold a render inside
  /// the engine and act while it is there.
  Completer<void>? holdPreview;

  /// When set, the next preview throws this instead of answering.
  Object? previewError;

  /// When set, `validate` throws this instead of answering — the shape a
  /// decode fault or a poisoned engine lock takes at the seam.
  Object? validateThrows;

  final List<String> validateRecipes = [];
  final List<Map<String, dynamic>> previewContexts = [];
  final List<String> previewRecipes = [];
  final List<Map<String, dynamic>> cancelArgs = [];
  final List<Map<String, dynamic>> registryCalls = [];

  int get previewCount => previewRecipes.length;

  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    validateRecipes.add(recipeJson);
    final thrown = validateThrows;
    if (thrown != null) {
      validateThrows = null;
      throw thrown;
    }
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
            'opVersion': (steps[i] as Map<String, dynamic>)['opVersion'],
            'enabled': (steps[i] as Map<String, dynamic>)['enabled'],
            'registered': true,
            'valid': !stepErrors.containsKey(i),
            if (stepErrors.containsKey(i)) 'error': stepErrors[i],
          },
      ],
    };
  }

  @override
  Future<DarkroomRenderedPreview> renderPreview({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    previewRecipes.add(recipeJson);
    previewContexts.add(context);
    final hold = holdPreview;
    if (hold != null) {
      holdPreview = null;
      await hold.future;
    }
    final error = previewError;
    if (error != null) {
      previewError = null;
      throw error;
    }
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
        'level': {
          'level': 1,
          'levelCount': 3,
          'width': 4,
          'height': 4,
          'channels': 1,
          'scaleFromMaster': 0.5,
        },
        'report': {
          'steps': [
            for (var i = 0; i < steps.length; i++)
              {
                'index': i,
                'opId': (steps[i] as Map<String, dynamic>)['opId'],
                'opVersion': 1,
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
    registryCalls.add(args);
    final reply = <String, dynamic>{
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
              'example': 64.0,
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
        {
          'id': 'stretch',
          'version': 1,
          'stage': 'stretched',
          'summary': 'Generalized hyperbolic stretch.',
          'params': [
            {
              'name': 'blackPoint',
              'kind': 'number',
              'required': true,
              'min': -1e12,
              'max': 1e12,
              'example': 0.0,
              'independent': false,
              'summary': 'Input level mapped to black.',
            },
          ],
        },
      ],
    };
    if (args['masterPath'] != null) {
      reply['draft'] = {
        'recipe': {
          'id': 'draft',
          'schemaVersion': 1,
          'baseMasterRef': args['masterPath'],
          'createdBy': 'autopilot',
          'steps': draftSteps,
        },
        'notes': const <dynamic>[],
        'autoParams': const <String, dynamic>{},
      };
    }
    return reply;
  }

  @override
  Future<Map<String, dynamic>> cancel(Map<String, dynamic> args) async {
    cancelArgs.add(args);
    return {
      'renderId': args['renderId'],
      'op': args['op'],
      'running': true,
      'cancelRequested': true,
    };
  }
}

/// A photometry resolver bound to an empty catalogue, so no test reaches the
/// on-disk star catalogue.
DawnPhotometryResolver _emptyPhotometry() {
  return DawnPhotometryResolver(
    coneSearch: (center, radiusDegrees, {maxMagnitude}) async => const [],
  );
}

const String _masterPath = '/tmp/nightshade-test/m31_L.fits';

Map<String, dynamic> _step(
  String opId, {
  bool enabled = true,
  Map<String, dynamic> params = const {},
}) {
  return {
    'opId': opId,
    'opVersion': 1,
    'params': params,
    'enabled': enabled,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedDarkroom darkroom;
  late ProviderContainer container;
  late NightshadeDatabase db;
  late RecipesDao recipes;

  setUp(() {
    darkroom = _ScriptedDarkroom();
    container = ProviderContainer(
      overrides: [
        inMemoryDatabaseOverride(),
        darkroomSeamProvider.overrideWithValue(darkroom),
        dawnPhotometryResolverProvider.overrideWithValue(_emptyPhotometry()),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    recipes = container.read(recipesDaoProvider);
  });

  Future<int> seedRecipe({
    List<Map<String, dynamic>> steps = const [],
    String name = 'Draft',
  }) {
    return recipes.create(
      masterId: null,
      baseMasterPath: _masterPath,
      name: name,
      stepsJson: jsonEncode(steps),
      createdBy: RecipeAuthor.autopilot,
    );
  }

  /// Read the state after the load, the catalogue fetch and the first render
  /// have all settled.
  Future<DarkroomState> settle(DarkroomScope scope) async {
    container.read(darkroomControllerProvider(scope).notifier);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(darkroomControllerProvider(scope));
  }

  test('a link that names nothing loads an explanation, not a crash', () async {
    final state = await settle(const DarkroomScope.empty());
    expect(state.loading, isFalse);
    expect(state.loadError, contains('named neither a recipe nor a master'));
    expect(state.hasRecipe, isFalse);
  });

  test('a recipe id with no row says so', () async {
    final state = await settle(const DarkroomScope.recipe(4242));
    expect(state.loadError, contains('Recipe 4242 does not exist'));
  });

  test('loading a recipe renders it once and reports every step', () async {
    final id = await seedRecipe(
      steps: [_step('background_extract'), _step('stretch')],
    );
    final state = await settle(DarkroomScope.recipe(id));

    expect(state.loadError, isNull);
    expect(state.steps, hasLength(2));
    expect(state.baseMasterPath, _masterPath);
    expect(darkroom.previewCount, 1);
    expect(state.preview, isNotNull);
    expect(state.preview!.scaleFromMaster, 0.5);
    expect(state.reports.map((r) => r.outcome), [
      DarkroomStepOutcome.applied,
      DarkroomStepOutcome.applied,
    ]);
    // The render is asked for under a cancellable id and at a preview level.
    expect(darkroom.previewContexts.single['renderId'], isA<String>());
    expect(
      darkroom.previewContexts.single['maxDimension'],
      kDarkroomPreviewMaxDimension,
    );
  });

  test('a skipped step keeps its reason on the state', () async {
    darkroom.skipReasons = {
      0: 'no catalogue star was resolved for this field, so the colour fit has '
          'nothing to regress against',
    };
    final id = await seedRecipe(steps: [_step('color_calibrate')]);
    final state = await settle(DarkroomScope.recipe(id));

    final report = state.reportFor(0);
    expect(report, isNotNull);
    expect(report!.outcome, DarkroomStepOutcome.skipped);
    expect(report.reason, contains('nothing to regress against'));
  });

  test('a toggle renders once after the debounce, not once per edit', () async {
    final id = await seedRecipe(
      steps: [_step('background_extract'), _step('stretch')],
    );
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final baseline = darkroom.previewCount;

    final controller =
        container.read(darkroomControllerProvider(scope).notifier)
          ..toggleStep(0)
          ..toggleStep(1)
          ..toggleStep(0);
    expect(controller.state.steps[0].enabled, isTrue);

    // Nothing has rendered yet: the debounce is still open.
    await Future<void>.delayed(Duration.zero);
    expect(darkroom.previewCount, baseline);

    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(darkroom.previewCount, baseline + 1);
    expect(controller.state.steps[1].enabled, isFalse);
    expect(
        controller.state.reportFor(1)!.outcome, DarkroomStepOutcome.disabled);
  });

  test('a superseded render is cancelled by its own id and dropped', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    // Hold the next render inside the engine, then edit again underneath it.
    final held = Completer<void>();
    darkroom.holdPreview = held;
    controller.toggleStep(0);
    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.rendering, isTrue);
    final inFlightRenders = darkroom.previewCount;

    controller.toggleStep(0);
    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    // The superseded render was asked to stop by its own id; no second render
    // entered the engine beside it.
    expect(darkroom.cancelArgs, isNotEmpty);
    expect(darkroom.cancelArgs.last['op'], 'cancel');
    expect(darkroom.cancelArgs.last['renderId'], isA<String>());
    expect(darkroom.previewCount, inFlightRenders);

    held.complete();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // Exactly one further render ran, and it carried the newest step list.
    expect(darkroom.previewCount, inFlightRenders + 1);
    expect(controller.state.rendering, isFalse);
    expect(controller.state.steps[0].enabled, isTrue);
  });

  test('a cancelled render is an instruction obeyed, not a failure', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );
    final firstPixels = controller.state.preview;

    final held = Completer<void>();
    darkroom.holdPreview = held;
    darkroom.previewError = const DarkroomCancelledOutcome(
      id: 'darkroom-editor',
      phase: 'render',
      payload: {'kind': 'cancelled'},
    );
    controller.toggleStep(0);
    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.rendering, isTrue);

    await controller.cancelRender();
    expect(controller.state.cancelRequested, isTrue);
    expect(darkroom.cancelArgs.last['op'], 'cancel');

    held.complete();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.state.rendering, isFalse);
    expect(controller.state.cancelRequested, isFalse);
    expect(controller.state.renderError, isNull);
    expect(controller.state.cancelledPhase, 'render');
    // The previous picture is still on screen.
    expect(identical(controller.state.preview, firstPixels), isTrue);
  });

  test('a render failure is surfaced with the engine\'s own words', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    darkroom.previewError = const DarkroomSeamException(
      'renderPreview',
      'the master could not be read: no such file',
      'boom',
    );
    controller.toggleStep(0);
    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.state.rendering, isFalse);
    expect(controller.state.renderError, contains('no such file'));
  });

  test('an illegal reorder is refused before it is applied', () async {
    final id = await seedRecipe(
      steps: [_step('background_extract'), _step('stretch')],
    );
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );
    final renders = darkroom.previewCount;

    darkroom.validateOk = false;
    final accepted = await controller.reorderStep(1, 0);

    expect(accepted, isFalse);
    expect(controller.state.steps.map((s) => s.opId), [
      'background_extract',
      'stretch',
    ]);
    expect(
      controller.state.reorderRefusal,
      contains('linear operation cannot run after a stretch'),
    );
    // A refused order never reaches the engine's renderer.
    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    expect(darkroom.previewCount, renders);
  });

  test('a legal reorder commits and re-renders', () async {
    final id = await seedRecipe(
      steps: [_step('background_extract'), _step('color_calibrate')],
    );
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );
    final renders = darkroom.previewCount;

    final accepted = await controller.reorderStep(1, 0);
    expect(accepted, isTrue);
    expect(controller.state.steps.map((s) => s.opId), [
      'color_calibrate',
      'background_extract',
    ]);

    await Future<void>.delayed(
      kDarkroomRenderDebounce + const Duration(milliseconds: 60),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(darkroom.previewCount, renders + 1);
  });

  test('reset to linear turns every step off and destroys nothing', () async {
    final id = await seedRecipe(
      steps: [
        _step('background_extract', params: {'sampleSpacing': 32.0}),
        _step('stretch'),
      ],
    );
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    controller.resetToLinear();
    expect(controller.state.isLinear, isTrue);
    expect(controller.state.steps, hasLength(2));
    expect(
      controller.state.steps.first.params['sampleSpacing'],
      32.0,
    );

    controller.undo();
    expect(controller.state.steps.every((s) => s.enabled), isTrue);
    controller.redo();
    expect(controller.state.isLinear, isTrue);
  });

  test('consecutive drags of one slider are a single undo step', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    for (final value in [70.0, 80.0, 90.0, 120.0]) {
      controller.setParam(0, 'sampleSpacing', value);
    }
    expect(controller.state.steps.first.params['sampleSpacing'], 120.0);

    controller.undo();
    // One undo goes back past the whole drag, not one frame of it.
    expect(
      controller.state.steps.first.params.containsKey('sampleSpacing'),
      isFalse,
    );
    expect(controller.state.canUndo, isFalse);
  });

  test('an edit reaches the recipe row after the save debounce', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    controller.toggleStep(0);
    expect(controller.state.savePending, isTrue);

    await Future<void>.delayed(
      kDarkroomSaveDebounce + const Duration(milliseconds: 80),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.state.savePending, isFalse);

    final stored = await recipes.getById(id);
    final steps = jsonDecode(stored!.stepsJson) as List;
    expect((steps.single as Map<String, dynamic>)['enabled'], isFalse);
  });

  test('a master with no recipe offers both starting points', () async {
    final masters = IntegratedMastersDao(db);
    final targetId = await TargetsDao(db).createTarget(
      const TargetsCompanion(
        name: Value('M31'),
        ra: Value(0.712),
        dec: Value(41.27),
      ),
    );
    final masterId = await masters.insertMaster(
      targetId: targetId,
      name: 'M31 L',
      masterFitsPath: _masterPath,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: 1,
      width: 4096,
      height: 3096,
      frameCount: 41,
      totalIntegrationSeconds: 12300,
      settingsJson: '{}',
      statsJson: '{}',
    );

    final scope = DarkroomScope.master(masterId);
    final state = await settle(scope);
    expect(state.offer, isNotNull);
    expect(state.offer!.masterName, 'M31 L');
    expect(state.hasRecipe, isFalse);

    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );
    darkroom.draftSteps = [_step('background_extract'), _step('stretch')];
    await controller.draftForMe();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.state.offer, isNull);
    expect(controller.state.hasRecipe, isTrue);
    expect(controller.state.author, RecipeAuthor.user);
    expect(controller.state.steps.map((s) => s.opId), [
      'background_extract',
      'stretch',
    ]);
    final stored = await recipes.listForMaster(_masterPath);
    expect(stored, hasLength(1));
    expect(stored.single.masterId, masterId);
    expect(stored.single.targetId, targetId);
  });

  test('start from linear creates an empty user recipe', () async {
    final masters = IntegratedMastersDao(db);
    final masterId = await masters.insertMaster(
      targetId: null,
      name: 'NGC 7000 Ha',
      masterFitsPath: _masterPath,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: 1,
      width: 1024,
      height: 1024,
      frameCount: 12,
      totalIntegrationSeconds: 3600,
      settingsJson: '{}',
      statsJson: '{}',
    );
    final scope = DarkroomScope.master(masterId);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    await controller.startFromLinear();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.state.hasRecipe, isTrue);
    expect(controller.state.steps, isEmpty);
    expect(controller.state.recipeName, 'Linear');
  });

  test('the operation catalogue drives the parameter specs', () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final state = await settle(DarkroomScope.recipe(id));

    final catalog = state.catalog;
    expect(catalog, isNotNull);
    final spec = catalog!.specFor(state.steps.single);
    expect(spec, isNotNull);
    expect(spec!.stage, DarkroomOpStage.linear);
    final param = spec.param('sampleSpacing');
    expect(param, isNotNull);
    expect(param!.min, 8.0);
    expect(param.max, 1024.0);
    expect(param.defaultValue, 64.0);
    expect(param.isSliderRanged, isTrue);

    // A ±1e12 range is not something a slider can resolve, so it takes a field.
    final stretch = catalog.ops.firstWhere((op) => op.id == 'stretch');
    expect(stretch.stage, DarkroomOpStage.stretched);
    expect(stretch.param('blackPoint')!.isSliderRanged, isFalse);
    expect(stretch.param('blackPoint')!.independent, isFalse);
  });

  test('the render report\'s encoding object is read, not stringified',
      () async {
    final id = await seedRecipe(steps: [_step('background_extract')]);
    final state = await settle(DarkroomScope.recipe(id));

    final encoding = state.preview!.encoding;
    expect(encoding.applied, 'screen');
    expect(encoding.sourceDomain, 'linear');
    expect(encoding.screenTransfer, isNotNull);
    expect(encoding.screenTransfer!['blackPoint'], 529.75);
    // Both halves are named, so the strip never blames the engine for an
    // omission it did not make.
    expect(encoding.sentence, contains('screen transfer'));
    expect(encoding.sentence, contains('still-linear pixels'));
    expect(encoding.sentence, isNot(contains('did not name')));
  });

  test('an encoding block the reply omits is reported as unstated', () {
    final encoding = decodeDarkroomEncoding(const <String, dynamic>{});
    expect(encoding.applied, isNull);
    expect(encoding.sourceDomain, isNull);
    expect(encoding.screenTransfer, isNull);
    expect(
      encoding.sentence,
      'the engine did not name the display transfer it applied',
    );
  });

  test('an encoding block naming only the transfer says so for the domain', () {
    final encoding = decodeDarkroomEncoding(const <String, dynamic>{
      'encoding': <String, dynamic>{'applied': 'unit'},
    });
    expect(encoding.applied, 'unit');
    expect(encoding.sourceDomain, isNull);
    expect(encoding.sentence, contains('own samples'));
    expect(encoding.sentence, contains('domain the engine did not name'));
  });

  test('a reorder whose check throws is refused with the failure named',
      () async {
    final id = await seedRecipe(
      steps: [_step('background_extract'), _step('stretch')],
    );
    final scope = DarkroomScope.recipe(id);
    await settle(scope);
    final controller = container.read(
      darkroomControllerProvider(scope).notifier,
    );

    darkroom.validateThrows = StateError('the registry lock was poisoned');
    final accepted = await controller.reorderStep(1, 0);

    // The caller is a drag gesture that cannot await this, so a throw here
    // would have been an unobserved async error and a silently snapped-back
    // card. It is a stated refusal instead.
    expect(accepted, isFalse);
    expect(
      controller.state.reorderRefusal,
      contains('could not be checked with the engine'),
    );
    expect(
      controller.state.reorderRefusal,
      contains('the registry lock was poisoned'),
    );
    expect(controller.state.steps.map((s) => s.opId), [
      'background_extract',
      'stretch',
    ]);
  });

  test('a stored step list that is not a step list is reported', () async {
    final id = await recipes.create(
      baseMasterPath: _masterPath,
      name: 'Corrupt',
      stepsJson: '{"not":"a list"}',
      createdBy: RecipeAuthor.user,
    );
    final state = await settle(DarkroomScope.recipe(id));
    expect(state.loadError, contains('JSON array of steps'));
    expect(state.hasRecipe, isFalse);
  });
}
