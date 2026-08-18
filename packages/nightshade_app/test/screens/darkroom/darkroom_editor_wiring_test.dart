// Widget and unit tests for the Darkroom editor seams closed in wave 4.
//
// Each of these asserts a statement the screen makes — or a control it offers —
// that a reader of the code cannot see, and that was measurably absent from the
// running app before:
//
//  * the registry's draft NOTES reach the screen, so a mono master's draft says
//    the colour calibration was left out and why (the decoder had zero callers,
//    and the notes reached only the night report on disk);
//  * a cascade delete that takes the open recipe lands on the MASTER, and the
//    load failure blames nothing that is still on disk;
//  * every step card offers a keyboard-reachable move up / move down beside the
//    pointer-only drag handle;
//  * a slider-ranged parameter carries a typed field, so a working region
//    narrower than the track can resolve is reachable exactly;
//  * parameter controls are labelled with the registry's display name;
//  * an ENABLED export option publishes its rationale in its accessible name;
//  * the branch bar and the start offer name the night's other masters;
//  * Escape and Alt+Left leave, and a Back control says so;
//  * the delete confirmation names the child branches up front;
//  * compare keeps the Recipe and History panels reachable;
//  * a `.nsrecipe` sidecar can be read back into a recipe.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_controller.dart';
import 'package:nightshade_app/screens/darkroom/darkroom_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart' show TestBackendNotifier;
import '../../harness/mock_backend.dart';
import '../../harness/mock_database.dart';

const String _masterPath = '/tmp/nightshade-test/m31_B.fits';

/// A Darkroom seam whose every reply the test writes.
class _ScriptedDarkroom implements DarkroomSeam {
  /// The `notes` array the registry answers a draft request with.
  List<Map<String, dynamic>> draftNotes = const [];

  /// Steps the drafted recipe carries.
  List<Map<String, dynamic>> draftSteps = const [];

  /// `opId@opVersion` keys this scripted build does not register.
  Set<String> unregisteredOps = {};

  /// Every `validate` recipe payload, in call order.
  final List<String> validated = [];

  static String _opKey(Map<String, dynamic> step) =>
      '${step['opId']}@${step['opVersion']}';

  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    validated.add(recipeJson);
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    var bad = false;
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i] as Map<String, dynamic>;
      final known = !unregisteredOps.contains(_opKey(step));
      if (!known) bad = true;
      entries.add({
        'index': i,
        'registered': known,
        'valid': known,
        if (!known) 'error': 'no operation registered as ${_opKey(step)}',
      });
    }
    return {
      'ok': !bad,
      'error': bad ? 'a step names an operation this build does not run' : null,
      'steps': entries,
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
      width: 2,
      height: 2,
      isColor: false,
      rgba: Uint8List(2 * 2 * 4),
      report: {
        'encoding': {'applied': 'unit', 'sourceDomain': 'stretched'},
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
    throw StateError('these tests do not export');
  }

  @override
  Future<Map<String, dynamic>> registry(Map<String, dynamic> args) async {
    final catalogue = {
      'schemaVersion': 1,
      'ops': [
        {
          'id': 'stretch',
          'version': 1,
          'stage': 'stretched',
          'summary': 'Generalised hyperbolic stretch.',
          'params': [
            {
              'name': 'd',
              'displayName': 'Stretch intensity',
              'kind': 'number',
              'required': false,
              'min': 0.0,
              'max': 100.0,
              'default': 1.0,
              'independent': true,
              'summary': 'Stretch intensity; 0 is the identity ramp.',
            },
            {
              'name': 'blackPoint',
              'displayName': 'Black point (ADU)',
              'kind': 'number',
              'required': true,
              'min': -1e12,
              'max': 1e12,
              'independent': false,
              'summary': 'ADU mapped to 0.',
            },
          ],
        },
        {
          'id': 'denoise',
          'version': 1,
          'stage': 'linear',
          'summary': 'Shrinks wavelet detail.',
          'params': const <dynamic>[],
        },
        {
          'id': 'crop',
          'version': 1,
          'stage': 'linear',
          'summary': 'Cuts a rectangle out of the frame.',
          'params': const <dynamic>[],
        },
      ],
    };
    if (args['masterPath'] == null) return catalogue;
    return {
      ...catalogue,
      'draft': {
        'recipe': {'steps': draftSteps},
        'notes': draftNotes,
      },
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedDarkroom darkroom;
  late NightshadeDatabase db;
  late RecipesDao recipes;
  late IntegratedMastersDao masters;
  late ImagesDao images;

  /// What the scripted `.nsrecipe` chooser answers with, or null for a
  /// dismissed chooser.
  DarkroomSidecarPick? sidecarAnswer;
  var sidecarCalls = 0;

  setUp(() {
    darkroom = _ScriptedDarkroom();
    db = mockDatabase();
    recipes = RecipesDao(db);
    masters = IntegratedMastersDao(db);
    images = ImagesDao(db);
    sidecarAnswer = null;
    sidecarCalls = 0;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedMaster({
    required String name,
    required String path,
    int channels = 1,
    String? filter,
  }) {
    return masters.insertMaster(
      targetId: null,
      name: name,
      masterFitsPath: path,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: channels,
      width: 64,
      height: 64,
      frameCount: 3,
      totalIntegrationSeconds: 6,
      settingsJson: '{}',
      statsJson: '{}',
      filter: filter,
    );
  }

  Future<int> seedRecipe(
    List<Map<String, dynamic>> steps, {
    String name = 'Draft',
    int? masterId,
    String path = _masterPath,
    RecipeAuthor by = RecipeAuthor.autopilot,
  }) {
    return recipes.create(
      masterId: masterId,
      baseMasterPath: path,
      name: name,
      stepsJson: jsonEncode(steps),
      createdBy: by,
    );
  }

  /// Fold one frame of [sessionId] into [masterId], which is the only link the
  /// night walk follows back from a master to the session that produced it.
  ///
  /// The frame carries no file path on purpose: with one, the DAO stats the
  /// file to fill `file_size`, and real filesystem I/O inside a widget test's
  /// fake-async zone never completes — the future is simply never resolved and
  /// the test sits until its own timeout.
  Future<void> foldFrame(int masterId, int sessionId, String tag) async {
    final imageId = await images.insertSequenceFrame(
      filePath: '',
      fileName: '$tag.fits',
      fileFormat: 'fits',
      exposureDuration: 2.0,
      capturedAt: DateTime.utc(2026, 8, 17),
      isAccepted: true,
      producingNodeId: 'exp_$tag',
      sessionId: sessionId,
    );
    await masters.recordFoldedFrame(masterId: masterId, imageId: imageId);
  }

  Future<GoRouter> pump(
    WidgetTester tester, {
    required String location,
    Size size = const Size(1400, 1200),
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
        darkroomSidecarReaderProvider.overrideWithValue(() async {
          sidecarCalls++;
          return sidecarAnswer;
        }),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('session review stands in here')),
          ),
        ),
        GoRoute(
          path: '/darkroom',
          builder: (context, state) {
            final rawRecipe = state.uri.queryParameters['recipe'];
            final rawMaster = state.uri.queryParameters['master'];
            final recipeId = rawRecipe == null ? null : int.tryParse(rawRecipe);
            final masterId = rawMaster == null ? null : int.tryParse(rawMaster);
            return DarkroomScreen(
              scope: recipeId != null
                  ? DarkroomScope.recipe(recipeId)
                  : (masterId != null
                      ? DarkroomScope.master(masterId)
                      : const DarkroomScope.empty()),
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
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    return router;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  // -------------------------------------------------------------------
  // D2-01 — the registry's draft notes reach the screen
  // -------------------------------------------------------------------

  test('the draft-note decoder reads the registry\'s own account', () {
    final notes = decodeDarkroomDraftNotes({
      'draft': {
        'notes': [
          {
            'opId': 'color_calibrate',
            'outcome': 'omitted',
            'reason': 'this master has 1 channel(s) and the colour fit needs '
                'three',
          },
          {'opId': 'stretch', 'outcome': 'omitted'},
          'not an object',
        ],
      },
    });
    expect(notes, hasLength(2));
    expect(notes.first.opId, 'color_calibrate');
    expect(notes.first.outcome, 'omitted');
    expect(notes.first.reason, contains('1 channel(s)'));
    // A note with no reason says the registry stated none, never invents one.
    expect(notes.last.reason, 'the operation registry stated no reason');
    // Printed, the operation is named the way its step card names it.
    expect(
      darkroomDraftNoteSentence(notes.first),
      startsWith('Color calibrate — omitted:'),
    );
  });

  test(
      'the composed account completes the registry\'s notes with the steps '
      'it did carry', () {
    final account = darkroomComposedAccount(
      [
        DarkroomStep.fromJson(_step('crop'), index: 0),
        DarkroomStep.fromJson(_step('stretch'), index: 1),
      ],
      const [
        RecipeDraftNote(
          opId: 'color_calibrate',
          outcome: 'omitted',
          reason: 'this master has 1 channel(s)',
        ),
      ],
    );
    // The omission keeps its own words, and every carried step is recorded as
    // included — which is what makes a note-carrying row a DRAFTED row even
    // when the draft left nothing out.
    expect(account.map((n) => n.opId), ['color_calibrate', 'crop', 'stretch']);
    expect(account.map((n) => n.outcome), ['omitted', 'included', 'included']);
  });

  testWidgets(
      'a mono master\'s draft states the colour step it left out, and why',
      (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    darkroom.draftSteps = [
      _step('crop'),
      _step('denoise'),
      _step('stretch', params: {'blackPoint': 529.7, 'd': 1.938}),
    ];
    darkroom.draftNotes = [
      {
        'opId': 'color_calibrate',
        'outcome': 'omitted',
        'reason': 'this master has 1 channel(s) and the colour fit needs '
            'three, so this draft covers the one channel it was given',
      },
    ];

    await pump(tester, location: '/darkroom?master=$masterId');
    expect(find.text('Master · B has no recipe yet'), findsOneWidget);
    // The offer no longer promises colour on a master that has one channel.
    expect(
      find.textContaining('no colour calibration, because the fit needs three'),
      findsOneWidget,
    );

    await tester.tap(find.text('Draft for me'));
    await settle(tester);

    // The stack the registry did carry.
    expect(find.text('Stretch'), findsOneWidget);
    // And the operation it decided about and did not carry, with its reason —
    // which used to reach the night report on disk and nothing else.
    expect(find.text('The draft left one operation out'), findsOneWidget);
    expect(
      find.textContaining('the colour fit needs three'),
      findsOneWidget,
    );
    // Named the way the step cards name operations, not as the wire id.
    expect(find.textContaining('Color calibrate — omitted:'), findsOneWidget);
    expect(find.textContaining('color_calibrate —'), findsNothing);
    // The registry composed these steps, so the tag says drafted rather than
    // crediting the operator with a stack they did not choose.
    expect(find.text('Drafted at your request'), findsOneWidget);
    expect(find.text('Written by you'), findsNothing);

    // The account rode into the row, so re-opening the recipe still carries it.
    final written = (await recipes.listForMaster(_masterPath)).single;
    expect(
      (await recipes.draftNotesOf(written.id!)).map((n) => n.opId),
      containsAll(<String>['color_calibrate', 'crop', 'denoise', 'stretch']),
    );
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-03 / D3-UI-01 — the cascade delete lands on the master
  // -------------------------------------------------------------------

  testWidgets(
      'deleting a branch line that takes the open recipe lands on the master',
      (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    final root = await seedRecipe(
      [_step('denoise')],
      name: 'Master · B draft',
      masterId: masterId,
    );
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Master · B draft variant',
    );

    // The route the app is on after the operator clicks the PARENT chip: the
    // bar switches branches with `context.go(darkroomRecipeLocation(id))`, and
    // the parent is where a delete-with-children is attempted from. Opening by
    // master would open the variant, which is the newest recipe over these
    // pixels and has no children to refuse the delete.
    await pump(tester, location: '/darkroom?recipe=$root');
    expect(find.text('Master · B draft'), findsWidgets);

    await tester.tap(find.text('Delete branch'));
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Delete'));
    await settle(tester);

    // The RESTRICT refusal, then its own destructive alternative.
    expect(find.text('That branch has branches of its own'), findsOneWidget);
    await tester.tap(
      find.textContaining('Delete "Master · B draft" and its 1 branch'),
    );
    await settle(tester);

    expect(await recipes.listForMaster(_masterPath), isEmpty);
    // The master is intact, so the editor offers a fresh start over it rather
    // than stranding on the id of a recipe that is gone.
    expect(find.text('Master · B has no recipe yet'), findsOneWidget);
    expect(find.text('Draft for me'), findsOneWidget);
    expect(find.text('Nothing to open in the Darkroom'), findsNothing);
    await drain(tester);
  });

  testWidgets('a missing recipe blames nothing that is still on disk',
      (tester) async {
    await pump(tester, location: '/darkroom?recipe=4242');
    expect(find.text('Nothing to open in the Darkroom'), findsOneWidget);
    // `recipes.master_id` is ON DELETE SET NULL, so a deleted master cannot
    // have taken the recipe row with it — the old sentence said it might have.
    expect(
      find.textContaining('may have been deleted along with the master'),
      findsNothing,
    );
    expect(
      find.textContaining('is still in the library'),
      findsOneWidget,
    );
  });

  // -------------------------------------------------------------------
  // D2-04 — the step stack reorders without a pointer
  // -------------------------------------------------------------------

  testWidgets('every step card offers move up and move down', (tester) async {
    final id = await seedRecipe([
      _step('crop'),
      _step('denoise'),
      _step('stretch', params: {'blackPoint': 0.0}),
    ]);
    await pump(tester, location: '/darkroom?recipe=$id');

    final semantics = tester.ensureSemantics();
    // The drag handle publishes a panel with no action, which is why a keyboard
    // and assistive tech could not move a step at all.
    expect(find.bySemanticsLabel('Move Denoise up'), findsOneWidget);
    expect(find.bySemanticsLabel('Move Denoise down'), findsOneWidget);
    // At the ends the control stays, disabled, and says which end it is at —
    // the controller clamps an out-of-range destination back onto the step's
    // own index, so an enabled control there would do nothing.
    expect(
      find.bySemanticsLabel(RegExp('^Move Crop up — it is already first')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Move Stretch down — it is already last')),
      findsOneWidget,
    );
    semantics.dispose();
    await drain(tester);
  });

  testWidgets('move up reorders the stored stack', (tester) async {
    final id = await seedRecipe([_step('crop'), _step('denoise')]);
    await pump(tester, location: '/darkroom?recipe=$id');

    await tester.tap(find.byTooltip('Move Denoise up'));
    // Past the save debounce, not just the render one: the row is what the
    // assertion reads.
    await settle(tester);
    await drain(tester);

    final stored = await recipes.getById(id);
    final steps = jsonDecode(stored!.stepsJson) as List;
    expect(
      [for (final step in steps) (step as Map)['opId']],
      ['denoise', 'crop'],
    );
  });

  // -------------------------------------------------------------------
  // D2-05 / D2-06 — the parameter controls
  // -------------------------------------------------------------------

  testWidgets(
      'a slider-ranged parameter carries a typed field for its working region',
      (tester) async {
    final id = await seedRecipe([
      _step('stretch', params: {'blackPoint': 529.7, 'd': 1.938}),
    ]);
    await pump(tester, location: '/darkroom?recipe=$id');
    await tester.tap(find.text('Parameters'));
    await settle(tester);

    // The slider still spans the registry's own range; the field is how the
    // region between two pixels of its travel is reached. One click a finger's
    // width along a 0…100 track moved the autopilot's 1.938 to 18.947.
    expect(find.byType(NightshadeSlider), findsOneWidget);
    final exact = find.widgetWithText(NightshadeTextField, '1.938');
    expect(exact, findsOneWidget);

    await tester.enterText(exact, '2.4');
    await settle(tester);
    await drain(tester);

    final stored = await recipes.getById(id);
    final steps = jsonDecode(stored!.stepsJson) as List;
    expect((steps.first as Map)['params']['d'], closeTo(2.4, 1e-9));
  });

  testWidgets('parameters are labelled with the registry\'s display name',
      (tester) async {
    final id = await seedRecipe([
      _step('stretch', params: {'blackPoint': 529.7, 'd': 1.938}),
    ]);
    await pump(tester, location: '/darkroom?recipe=$id');
    await tester.tap(find.text('Parameters'));
    await settle(tester);

    expect(find.text('Stretch intensity'), findsOneWidget);
    // The unit rides in the name, because the +/-1e12 bounds are the engine's
    // accepted range and not an ADU range any master occupies.
    expect(find.text('Black point (ADU)'), findsOneWidget);
    expect(find.text('d'), findsNothing);
    expect(find.text('blackPoint'), findsNothing);
    // The name is printed ONCE. The wide-ranged parameter's field sits under
    // that title and under the registry's summary of it, so it carries the
    // half neither of them states — the accepted bounds — rather than the
    // whole label a third time.
    expect(find.textContaining('Black point (ADU) (accepts'), findsNothing);
    expect(find.text('accepts -1.00e+12 … 1.00e+12'), findsOneWidget);
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-07 — an available export option states its own reason
  // -------------------------------------------------------------------

  testWidgets('an enabled export option publishes its rationale, not a hover',
      (tester) async {
    final id = await seedRecipe([
      _step('stretch', params: {'blackPoint': 0.0}),
    ]);
    await pump(tester, location: '/darkroom?recipe=$id');
    await tester.tap(find.text('Export…'));
    await settle(tester);

    final semantics = tester.ensureSemantics();
    // Before: `button: FITS`, and the sentence lived only in a tooltip — which
    // is nothing at all from a keyboard, a screen reader or a touch screen.
    final fits = find.bySemanticsLabel(RegExp('^FITS — '));
    expect(fits, findsOneWidget);
    expect(
      tester.getSemantics(fits).label,
      contains('own F32 samples'),
    );
    expect(tester.getSemantics(fits).flagsCollection.isButton, isTrue);
    // And the chosen format says what it writes on screen, with no pointer.
    expect(
      find.textContaining('FITS: The engine\'s own F32 samples'),
      findsOneWidget,
    );
    semantics.dispose();
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-10 — the night's other masters
  // -------------------------------------------------------------------

  testWidgets('the branch bar names the night\'s other drafts with links',
      (tester) async {
    // A real session row: `captured_images.session_id` is a foreign key, and
    // the fold record is the only link the night walk follows.
    final sessionId = await SessionsDao(db).startSession(name: 'D1 sim night');
    final bId = await seedMaster(
      name: 'Master · B',
      path: _masterPath,
      filter: 'B',
    );
    final lId = await seedMaster(
      name: 'Master · L',
      path: '/tmp/nightshade-test/m31_L.fits',
      filter: 'L',
    );
    final gId = await seedMaster(
      name: 'Master · G',
      path: '/tmp/nightshade-test/m31_G.fits',
      filter: 'G',
    );
    await foldFrame(bId, sessionId, 'b1');
    await foldFrame(lId, sessionId, 'l1');
    await foldFrame(gId, sessionId, 'g1');
    await seedRecipe([_step('denoise')],
        name: 'Master · B draft', masterId: bId);
    await seedRecipe(
      [_step('denoise')],
      name: 'Master · L draft',
      masterId: lId,
      path: '/tmp/nightshade-test/m31_L.fits',
    );

    await pump(tester, location: '/darkroom?master=$bId');
    await settle(tester);

    // The bar counts the night, not just this master's branches.
    expect(
        find.textContaining('This night produced 3 masters'), findsOneWidget);
    // The chip says the master once. The autopilot names a draft after the
    // master it drafted, so joining the two printed it twice on one chip.
    expect(find.textContaining('Master · L draft'), findsWidgets);
    expect(
      find.textContaining('Master · L · Master · L draft'),
      findsNothing,
    );
    // The master with no recipe is named too, and says so rather than being
    // dropped from a list the operator would then read as complete.
    expect(
      find.textContaining('Master · G — no recipe yet'),
      findsWidgets,
    );
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-11 — leaving the Darkroom
  // -------------------------------------------------------------------

  testWidgets('Escape leaves the Darkroom, and a Back control says so',
      (tester) async {
    final id = await seedRecipe([_step('denoise')]);
    final router = await pump(tester, location: '/darkroom?recipe=$id');

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('^Back to where the Darkroom was opened')),
      findsOneWidget,
    );
    semantics.dispose();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // Nothing to pop from a deep link, so it goes where the empty state goes:
    // the surface that lists the masters there are pixels for.
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/analytics',
    );
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-13 — the delete confirmation names the children up front
  // -------------------------------------------------------------------

  testWidgets('the delete confirmation names the branches that block it',
      (tester) async {
    final root = await seedRecipe([_step('denoise')], name: 'Draft');
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, location: '/darkroom?recipe=$root');

    await tester.tap(find.text('Delete branch'));
    await settle(tester);

    // Before: the dialog's whole body was "The recipe row goes; the linear
    // master it renders does not", and the child only appeared in a refusal
    // AFTER the operator confirmed a destructive action.
    expect(find.text('One branch diverges from this one'), findsOneWidget);
    expect(find.textContaining('Warmer'), findsWidgets);
    // Agreeing in number with the one branch it names, not with a plural the
    // sentence was written for.
    expect(
      find.textContaining('Warmer records the step of "Draft" it stopped '
          'matching'),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing is deleted before you choose that'),
      findsOneWidget,
    );
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D2-14 — compare keeps the panels
  // -------------------------------------------------------------------

  testWidgets('compare keeps the Recipe and History panels reachable',
      (tester) async {
    final root = await seedRecipe([_step('denoise')], name: 'Draft');
    await recipes.branchFrom(
      parentRecipeId: root,
      divergenceIndex: 1,
      name: 'Warmer',
    );
    await pump(tester, location: '/darkroom?recipe=$root');

    await tester.tap(find.text('Compare with…'));
    await settle(tester);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Warmer'));
    await settle(tester);

    // Both pictures, as before.
    expect(find.textContaining('A · Draft'), findsOneWidget);
    expect(find.textContaining('B · Warmer'), findsOneWidget);
    // And the two panels that say what differs, which compare used to remove
    // from the screen and from the accessibility tree entirely.
    expect(find.text('History stack'), findsOneWidget);
    expect(find.text('Denoise'), findsWidgets);
    expect(find.text('Reset to linear'), findsOneWidget);
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // D3DP-2 — the sidecar is readable
  // -------------------------------------------------------------------

  test('the sidecar decoder refuses a file that is not one, by name', () {
    expect(
      () => decodeDarkroomSidecar('{"kind":"something-else"}'),
      throwsA(
        isA<DarkroomRecipeFormatException>().having(
          (e) => e.message,
          'message',
          contains('"something-else"'),
        ),
      ),
    );
    expect(
      () => decodeDarkroomSidecar('{"kind":"nsrecipe"'),
      throwsA(
        isA<DarkroomRecipeFormatException>().having(
          (e) => e.message,
          'message',
          contains('not JSON'),
        ),
      ),
    );
    // A truncated sidecar whose recipe object never arrived.
    expect(
      () => decodeDarkroomSidecar('{"kind":"nsrecipe","schemaVersion":1}'),
      throwsA(
        isA<DarkroomRecipeFormatException>().having(
          (e) => e.message,
          'message',
          contains('no recipe object'),
        ),
      ),
    );
  });

  testWidgets('an imported .nsrecipe becomes a recipe over this master',
      (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    sidecarAnswer = DarkroomSidecarPick(
      path: '/tmp/nightshade-test/job_1_master_1_draft.jpg.nsrecipe',
      text: jsonEncode({
        'kind': 'nsrecipe',
        'schemaVersion': 1,
        'fingerprint': '69dbbc0189442a0d7fb286a1bb06acb8',
        'masterPath': '/tmp/nightshade-test/somewhere_else.fits',
        'recipe': {
          'baseMasterRef': '/tmp/nightshade-test/somewhere_else.fits',
          'createdBy': 'autopilot',
          'steps': [
            _step('crop'),
            _step('stretch', params: {'blackPoint': 529.7, 'd': 2.04}),
          ],
        },
      }),
    );

    await pump(tester, location: '/darkroom?master=$masterId');
    expect(find.text('Import .nsrecipe'), findsOneWidget);

    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    expect(sidecarCalls, 1);
    final rows = await recipes.listForMaster(_masterPath);
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Imported: job_1_master_1_draft');
    // Over THIS master's pixels, not the sidecar's own.
    expect(rows.single.baseMasterPath, _masterPath);
    final steps = jsonDecode(rows.single.stepsJson) as List;
    expect([for (final s in steps) (s as Map)['opId']], ['crop', 'stretch']);

    // The receipt says what was read and that the pixels are not the ones the
    // sidecar was written over.
    expect(find.text('Imported from a .nsrecipe sidecar'), findsOneWidget);
    expect(find.textContaining('Imported 2 steps from'), findsOneWidget);
    expect(find.textContaining('somewhere_else.fits'), findsOneWidget);
    expect(find.textContaining('Every step validates'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an imported step this build cannot run is kept and said',
      (tester) async {
    darkroom.unregisteredOps = {'wavelet_sharpen@3'};
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    sidecarAnswer = DarkroomSidecarPick(
      path: '/tmp/nightshade-test/future.fits.nsrecipe',
      text: jsonEncode({
        'kind': 'nsrecipe',
        'schemaVersion': 1,
        'masterPath': _masterPath,
        'recipe': {
          'steps': [
            _step('denoise'),
            _step('wavelet_sharpen', opVersion: 3),
          ],
        },
      }),
    );

    await pump(tester, location: '/darkroom?master=$masterId');
    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    // Nothing was dropped on the way in: the row holds what the file held.
    final rows = await recipes.listForMaster(_masterPath);
    final steps = jsonDecode(rows.single.stepsJson) as List;
    expect(
      [for (final s in steps) (s as Map)['opId']],
      ['denoise', 'wavelet_sharpen'],
    );
    expect(find.textContaining('This build refuses 1 of them'), findsOneWidget);
    // And the card renders it the way the editor already renders an
    // unregistered operation.
    expect(
      find.textContaining('This build registers no wavelet_sharpen@3'),
      findsWidgets,
    );
    await drain(tester);
  });

  testWidgets('a dismissed import chooser writes nothing', (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    sidecarAnswer = null;

    await pump(tester, location: '/darkroom?master=$masterId');
    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    expect(sidecarCalls, 1);
    expect(await recipes.listForMaster(_masterPath), isEmpty);
    // Still the offer, with its controls live again.
    expect(find.text('Master · B has no recipe yet'), findsOneWidget);
    expect(find.text('Import .nsrecipe'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a sidecar with no steps is refused by name', (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    sidecarAnswer = const DarkroomSidecarPick(
      path: '/tmp/nightshade-test/empty.nsrecipe',
      text: '{"kind":"nsrecipe","recipe":{"steps":[]}}',
    );

    await pump(tester, location: '/darkroom?master=$masterId');
    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    expect(await recipes.listForMaster(_masterPath), isEmpty);
    expect(
      find.textContaining('carries a recipe with no steps'),
      findsOneWidget,
    );
    await drain(tester);
  });

  // -------------------------------------------------------------------
  // The import refusal on the OTHER entry point
  //
  // Every test above imports from the start offer, which is the layout that
  // renders `offerError`. `Import .nsrecipe` also sits in the branch bar over
  // an open recipe, and that layout rendered nothing at all: the chooser
  // closed, the recipe count did not move, and the sentence the controller had
  // already composed went nowhere. These drive the branch-bar control.
  // -------------------------------------------------------------------

  testWidgets(
      'a truncated sidecar imported from the branch bar is refused on '
      'screen', (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    final recipeId = await seedRecipe(
      [_step('denoise')],
      name: 'Master · B draft',
      masterId: masterId,
    );
    // The first 900 bytes of a real sidecar: the JSON ends mid-string.
    sidecarAnswer = const DarkroomSidecarPick(
      path: '/tmp/nightshade-test/truncated.nsrecipe',
      text: '{"kind":"nsrecipe","schemaVersion":1,"masterPath":"/tmp/night',
    );

    await pump(tester, location: '/darkroom?recipe=$recipeId');
    await settle(tester);
    // The editor is open, so this is the branch bar's control, not the offer's.
    expect(find.text('Master · B has no recipe yet'), findsNothing);
    expect(find.text('Import .nsrecipe'), findsOneWidget);

    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    expect(sidecarCalls, 1);
    expect(
      await recipes.listForMaster(_masterPath),
      hasLength(1),
      reason: 'nothing was written, so the refusal is the whole outcome',
    );
    expect(find.textContaining('truncated.nsrecipe was not imported'),
        findsOneWidget);
    expect(find.textContaining('not JSON'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the branch-bar import refusal can be dismissed', (tester) async {
    final masterId = await seedMaster(name: 'Master · B', path: _masterPath);
    final recipeId = await seedRecipe(
      [_step('denoise')],
      name: 'Master · B draft',
      masterId: masterId,
    );
    sidecarAnswer = const DarkroomSidecarPick(
      path: '/tmp/nightshade-test/empty.nsrecipe',
      text: '{"kind":"nsrecipe","recipe":{"steps":[]}}',
    );

    await pump(tester, location: '/darkroom?recipe=$recipeId');
    await settle(tester);
    await tester.tap(find.text('Import .nsrecipe'));
    await settle(tester);

    final alert = find.byKey(const ValueKey('darkroom_import_refusal'));
    expect(alert, findsOneWidget);
    expect(
      find.textContaining('carries a recipe with no steps'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: alert, matching: find.byType(IconButton)),
    );
    await settle(tester);
    expect(alert, findsNothing);
    await drain(tester);
  });
}
