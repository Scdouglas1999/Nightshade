// Coordinator-level tests for the dawn autopilot: the durable job that turns a
// night's linear masters into a first draft, a morning report and a delivery.
//
// The Darkroom FFI entry points are behind [DarkroomSeam], so every decision
// the autopilot makes — which steps enter the draft, when the background fit is
// retried, whether the colour step survives its full-resolution proof, what the
// morning report says — runs here without the Rust library. The database is
// real: job state transitions, recipe rows and the delivery journal are what the
// pipeline is judged on.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// A Darkroom seam whose every reply the test writes.
class _ScriptedDarkroom implements DarkroomSeam {
  _ScriptedDarkroom({required this.baseMasterRef});

  final String baseMasterRef;

  /// Steps the registry's draft carries, in registry order.
  List<Map<String, dynamic>> draftSteps = [
    {
      'opId': 'crop',
      'opVersion': 1,
      'params': <String, dynamic>{},
      'enabled': true,
    },
    {
      'opId': 'background_extract',
      'opVersion': 1,
      'params': <String, dynamic>{},
      'enabled': true,
    },
    {
      'opId': 'stretch',
      'opVersion': 1,
      'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
      'enabled': true,
    },
  ];

  /// Notes the registry's draft carries.
  List<Map<String, dynamic>> draftNotes = [];

  /// Step indices the next preview reports as skipped, with the reason.
  Map<int, String> skipReasons = {};

  /// Per-channel scales the preview reports as a step's own measurement, the
  /// way `color_calibrate@1` reports the balance it fitted.
  Map<int, List<double>> channelScales = {};

  /// The auto stretch parameters a `screen`-encoded preview reports having
  /// applied for display. The draft reads them as the measurement over the
  /// prefix it just rendered.
  Map<String, dynamic>? screenTransfer;

  /// When set, the next preview throws this instead of answering.
  Object? previewError;

  /// When set, a `screen`-encoded preview throws this instead of answering, so
  /// a test can fail the stretch re-measurement alone.
  Object? screenPreviewError;

  /// When set, the next export throws this instead of writing.
  Object? exportError;

  /// Whether the registry answers at all.
  bool registryAnswers = true;

  /// Runs before each preview, so a test can cancel mid-pipeline.
  Future<void> Function()? beforePreview;

  /// Runs before each registry call.
  Future<void> Function()? beforeRegistry;

  final List<Map<String, dynamic>> registryCalls = [];
  final List<Map<String, dynamic>> previewContexts = [];
  final List<String> previewRecipes = [];
  final List<Map<String, dynamic>> exportArgs = [];
  final List<Map<String, dynamic>> cancelArgs = [];

  @override
  Future<Map<String, dynamic>> registry(Map<String, dynamic> args) async {
    await beforeRegistry?.call();
    registryCalls.add(args);
    if (!registryAnswers) return {'schemaVersion': 1, 'ops': <dynamic>[]};
    return {
      'schemaVersion': 1,
      'ops': <dynamic>[],
      'draft': {
        'recipe': {
          'id': args['recipeId'],
          'schemaVersion': 1,
          'baseMasterRef': baseMasterRef,
          'createdBy': 'autopilot',
          'steps': draftSteps,
        },
        'notes': draftNotes,
        'autoParams': <String, dynamic>{},
      },
    };
  }

  @override
  Future<DarkroomRenderedPreview> renderPreview({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    await beforePreview?.call();
    previewContexts.add(context);
    previewRecipes.add(recipeJson);
    final screen = context['encoding'] == 'screen';
    final error = screen ? (screenPreviewError ?? previewError) : previewError;
    if (error != null) {
      if (identical(error, screenPreviewError)) {
        screenPreviewError = null;
      } else {
        previewError = null;
      }
      throw error;
    }
    final steps =
        (jsonDecode(recipeJson) as Map<String, dynamic>)['steps'] as List;
    final stop = context['stopAfter'];
    final last = stop is int ? stop : steps.length - 1;
    return DarkroomRenderedPreview(
      width: 4,
      height: 4,
      isColor: false,
      rgba: Uint8List(4 * 4 * 4),
      report: {
        'report': {
          'steps': [
            for (var i = 0; i <= last && i < steps.length; i++)
              {
                'index': i,
                'opId': (steps[i] as Map<String, dynamic>)['opId'],
                'opVersion': 1,
                'outcome': skipReasons.containsKey(i) ? 'skipped' : 'applied',
                if (skipReasons.containsKey(i)) 'reason': skipReasons[i],
                if (!skipReasons.containsKey(i) && channelScales.containsKey(i))
                  'measured': {
                    'source': 'solved',
                    'channelScale': channelScales[i],
                  },
              },
          ],
        },
        if (screen)
          'encoding': {
            'requested': 'screen',
            'applied': 'screen',
            'sourceDomain': 'linear',
            'screenTransferAffectsRecipe': false,
            'screenTransfer': screenTransfer,
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
    final error = exportError;
    if (error != null) {
      exportError = null;
      throw error;
    }
    final outputs = args['outputs'] as List;
    for (final output in outputs) {
      final path = (output as Map<String, dynamic>)['path'] as String;
      await File(path).writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }
    return {'stage': 'final', 'outputs': outputs};
  }

  @override
  Future<Map<String, dynamic>> validate({
    required String recipeJson,
    required Map<String, dynamic> context,
  }) async {
    return {'ok': true, 'error': null, 'steps': <dynamic>[]};
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

/// A notifier that records what it was asked to announce.
class _RecordingNotifier implements DawnMorningNotifier {
  final List<DawnJobReport> announced = [];
  DawnNotificationDecision decision = const DawnNotificationDecision(
    sent: true,
    reason: 'Sent through the notification router.',
  );

  @override
  Future<DawnNotificationDecision> announce(DawnJobReport report) async {
    announced.add(report);
    return decision;
  }
}

/// A transport that refuses every destination, so delivery reports a problem
/// while the job keeps its drafts.
class _RefusingTransport implements ArtifactTransport {
  @override
  ArtifactDestinationKind get kind => ArtifactDestinationKind.watchedFolder;

  @override
  Future<void> open(List<DeliveryFile> artifacts) async {
    throw const DeliveryFailure(
      DeliveryFailureKind.destinationUnreachable,
      'the office PC did not answer',
    );
  }

  @override
  Future<TransportDeliveryOutcome> deliver(DeliveryFile artifact) async {
    throw const DeliveryFailure(
      DeliveryFailureKind.destinationUnreachable,
      'the office PC did not answer',
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  late NightshadeDatabase db;
  late Directory workspace;
  late Directory output;
  late _ScriptedDarkroom darkroom;
  late _RecordingNotifier notifier;
  late String masterPath;

  Future<int> insertSession() => db
      .into(db.imagingSessions)
      .insert(ImagingSessionsCompanion.insert(startTime: DateTime.now()));

  Future<int> insertTarget(String name) => db
      .into(db.targets)
      .insert(TargetsCompanion.insert(name: name, ra: 1.0, dec: 2.0));

  Future<int> insertSub({required int sessionId, int? targetId}) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return db
        .into(db.capturedImages)
        .insert(
          CapturedImagesCompanion.insert(
            filePath: '/l/$stamp.fits',
            fileName: '$stamp.fits',
            frameType: const Value('light'),
            exposureDuration: 120.0,
            capturedAt: DateTime.now(),
            sessionId: Value(sessionId),
            targetId: Value(targetId),
            isAccepted: const Value(true),
          ),
        );
  }

  /// A finalized master on disk, folded from [imageIds].
  Future<int> insertMaster({
    required List<int> imageIds,
    int? targetId,
    String? filter,
    int channels = 1,
    String statsJson = '{}',
    String? path,
    bool solved = false,
  }) async {
    final file = File(path ?? masterPath);
    await file.writeAsString('linear master');
    final masters = IntegratedMastersDao(db);
    final id = await masters.insertMaster(
      targetId: targetId,
      name: filter == null ? 'M42' : 'M42 · $filter',
      masterFitsPath: path ?? masterPath,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: channels,
      width: 100,
      height: 80,
      frameCount: imageIds.length,
      totalIntegrationSeconds: 3600.0,
      filter: filter,
      statsJson: statsJson,
    );
    if (solved) {
      await masters.updateWcs(
        id,
        crval1: 83.8,
        crval2: -5.4,
        crpix1: 50.0,
        crpix2: 40.0,
        cd1_1: -2.8e-4,
        cd1_2: 0.0,
        cd2_1: 0.0,
        cd2_2: 2.8e-4,
      );
    }
    for (final imageId in imageIds) {
      await masters.recordFoldedFrame(
        masterId: id,
        imageId: imageId,
        accepted: true,
      );
    }
    return id;
  }

  DawnAutopilotService buildService({
    ArtifactTransportFactory? transportFactory,
    List<Star> catalog = const [],
  }) {
    return DawnAutopilotService(
      jobs: DarkroomJobsDao(db),
      recipes: RecipesDao(db),
      masters: IntegratedMastersDao(db),
      targets: TargetsDao(db),
      resolver: DawnMasterResolver(
        images: ImagesDao(db),
        masters: IntegratedMastersDao(db),
      ),
      drafts: DawnDraftBuilder(darkroom: darkroom),
      darkroom: darkroom,
      photometry: DawnPhotometryResolver(
        coneSearch: (centre, radius, {maxMagnitude}) async => catalog,
      ),
      delivery: DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory:
            transportFactory ?? (destination, jobId) => _RefusingTransport(),
      ),
      notifier: notifier,
      outputDirectory: () async => output.path,
    );
  }

  setUp(() async {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    workspace = await Directory.systemTemp.createTemp('dawn-autopilot');
    output = Directory('${workspace.path}/out')..createSync(recursive: true);
    masterPath = '${workspace.path}/M42_master.fits';
    darkroom = _ScriptedDarkroom(baseMasterRef: masterPath);
    notifier = _RecordingNotifier();
  });

  tearDown(() async {
    await db.close();
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test(
    'a dawn job drafts, persists the recipe, renders it and finishes done',
    () async {
      final sessionId = await insertSession();
      final targetId = await insertTarget('M42');
      final imageId = await insertSub(sessionId: sessionId, targetId: targetId);
      final masterId = await insertMaster(
        imageIds: [imageId],
        targetId: targetId,
        statsJson: jsonEncode({
          'framesIntegrated': 30,
          'framesRejected': 4,
          'totalIntegrationSec': 3600.0,
        }),
      );

      final outcome = await buildService().runDawnForSession(sessionId);

      expect(outcome.succeeded, isTrue);
      final job = await DarkroomJobsDao(db).getById(outcome.jobId);
      expect(job!.state, DarkroomJobState.done);
      expect(job.kind, DarkroomJobKind.dawn);
      expect(job.progress, 1.0);
      expect(job.note, contains('draft(s) ready'));

      final recipes = await RecipesDao(db).listForMaster(masterPath);
      expect(recipes, hasLength(1));
      expect(recipes.single.createdBy, RecipeAuthor.autopilot);
      expect(recipes.single.masterId, masterId);
      expect(recipes.single.sessionId, sessionId);
      final steps = jsonDecode(recipes.single.stepsJson) as List;
      expect(steps.map((s) => (s as Map)['opId']), [
        'crop',
        'background_extract',
        'stretch',
      ]);

      // The draft image was exported under the job's own cancellation id, with
      // the recipe sidecar beside it.
      expect(darkroom.exportArgs, hasLength(1));
      expect(
        darkroom.exportArgs.single['renderId'],
        DawnAutopilotService.renderIdFor(outcome.jobId),
      );
      expect(darkroom.exportArgs.single['sidecarPath'], endsWith('.nsrecipe'));
      expect(
        File(outcome.report!.masters.single.draftRenderPath!).existsSync(),
        isTrue,
      );

      // The morning report reads the frames out of the master's own row.
      expect(outcome.report!.framesUsed, 30);
      expect(outcome.report!.framesRejected, 4);
      expect(outcome.reportPath, isNotNull);
      expect(File(outcome.reportPath!).existsSync(), isTrue);
    },
  );

  test(
    'a mono master carries no colour step and the report says why',
    () async {
      darkroom.draftNotes = [
        {
          'opId': 'color_calibrate',
          'outcome': 'omitted',
          'reason': 'this master has 1 channel(s); the colour fit needs three',
        },
      ];
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId]);

      final outcome = await buildService().runDawnForSession(sessionId);

      final draft = outcome.report!.masters.single.draft!;
      expect(draft.indexOfOp('color_calibrate'), -1);
      expect(
        draft.notes.firstWhere((n) => n.opId == 'color_calibrate').reason,
        contains('needs three'),
      );
    },
  );

  test(
    'an RGB master keeps the colour step once it applies at level 0',
    () async {
      darkroom.draftSteps = [
        {
          'opId': 'background_extract',
          'opVersion': 1,
          'params': <String, dynamic>{},
          'enabled': true,
        },
        {
          'opId': 'color_calibrate',
          'opVersion': 1,
          'params': <String, dynamic>{},
          'enabled': true,
        },
        {
          'opId': 'stretch',
          'opVersion': 1,
          'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
          'enabled': true,
        },
      ];
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId], channels: 3, solved: true);

      final outcome = await buildService(
        catalog: [
          Star(
            id: 'a',
            name: 'a',
            coordinates: const CelestialCoordinate(ra: 83.8 / 15.0, dec: -5.4),
            magnitude: 9.0,
            colorIndex: 0.6,
          ),
        ],
      ).runDawnForSession(sessionId);

      final draft = outcome.report!.masters.single.draft!;
      expect(draft.indexOfOp('color_calibrate'), 1);
      // The proof render ran at full resolution, stopping at the colour step,
      // with the catalogue attached.
      final proof = darkroom.previewContexts.single;
      expect(proof['level'], 0);
      expect(proof['stopAfter'], 1);
      expect((proof['catalogStars'] as List), hasLength(1));
      expect(
        draft.notes.firstWhere((n) => n.opId == 'color_calibrate').outcome,
        'included',
      );
      // This render reported no fitted scales, so nothing is pinned and the
      // note says the step re-solves on every render rather than implying a
      // preview will match this proof.
      expect(
        (draft.steps[1]['params'] as Map).containsKey('channelScale'),
        isFalse,
      );
      expect(
        draft.notes.firstWhere((n) => n.opId == 'color_calibrate').reason,
        contains('no fitted channel scales'),
      );
    },
  );

  test('the draft pins the channel scales the proof render fitted', () async {
    darkroom.draftSteps = [
      {
        'opId': 'background_extract',
        'opVersion': 1,
        'params': <String, dynamic>{},
        'enabled': true,
      },
      {
        'opId': 'color_calibrate',
        'opVersion': 1,
        'params': <String, dynamic>{},
        'enabled': true,
      },
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    darkroom.channelScales = {
      1: [1.25, 1.0, 0.8125],
    };
    darkroom.screenTransfer = {
      'blackPoint': 812.5,
      'whitePoint': 4200.0,
      'd': 2.75,
      'b': 0.0,
      'symmetryPoint': 0.0,
    };
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId], channels: 3, solved: true);

    final outcome = await buildService(
      catalog: [
        const Star(
          id: 'a',
          name: 'a',
          coordinates: CelestialCoordinate(ra: 83.8 / 15.0, dec: -5.4),
          magnitude: 9.0,
          colorIndex: 0.6,
        ),
      ],
    ).runDawnForSession(sessionId);

    final draft = outcome.report!.masters.single.draft!;
    expect((draft.steps[1]['params'] as Map)['channelScale'], [
      1.25,
      1.0,
      0.8125,
    ]);
    expect(
      draft.notes.firstWhere((n) => n.opId == 'color_calibrate').reason,
      contains('1.2500'),
    );

    // The pinned scales are in the recipe that was persisted, not only in the
    // report: the editor opens the row, and a preview at a coarse level replays
    // the balance from there.
    final recipes = await RecipesDao(db).listForMaster(masterPath);
    final persisted = jsonDecode(recipes.single.stepsJson) as List;
    expect(((persisted[1] as Map)['params'] as Map)['channelScale'], [
      1.25,
      1.0,
      0.8125,
    ]);

    // Pinning changes the pixels under the stretch — the registry measured with
    // the colour step skipping — so the stretch is measured again over the
    // final stack, and the recipe carries that fit.
    expect(darkroom.previewContexts, hasLength(2));
    final remeasure = darkroom.previewContexts.last;
    expect(remeasure['encoding'], 'screen');
    expect(remeasure['stopAfter'], 1);
    expect(remeasure['maxDimension'], kDraftMeasureMaxDimension);
    expect(
      jsonDecode(darkroom.previewRecipes.last),
      containsPair(
        'steps',
        contains(
          containsPair(
            'params',
            containsPair('channelScale', [1.25, 1.0, 0.8125]),
          ),
        ),
      ),
      reason: 're-measuring must render the prefix the draft actually carries',
    );
    expect((persisted[2] as Map)['params'], {
      'blackPoint': 812.5,
      'whitePoint': 4200.0,
      'd': 2.75,
      'b': 0.0,
      'symmetryPoint': 0.0,
    });
    expect(
      draft.notes.firstWhere((n) => n.opId == 'stretch').outcome,
      'remeasured',
    );
  });

  test(
    'a colour step that skips at level 0 is dropped with its own reason',
    () async {
      darkroom.draftSteps = [
        {
          'opId': 'color_calibrate',
          'opVersion': 1,
          'params': <String, dynamic>{},
          'enabled': true,
        },
        {
          'opId': 'stretch',
          'opVersion': 1,
          'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
          'enabled': true,
        },
      ];
      darkroom.skipReasons = {0: 'no photometric catalogue is installed'};
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId], channels: 3, solved: true);

      final outcome = await buildService(
        catalog: [
          Star(
            id: 'a',
            name: 'a',
            coordinates: const CelestialCoordinate(ra: 83.8 / 15.0, dec: -5.4),
            magnitude: 9.0,
            colorIndex: 0.6,
          ),
        ],
      ).runDawnForSession(sessionId);

      final draft = outcome.report!.masters.single.draft!;
      expect(draft.indexOfOp('color_calibrate'), -1);
      expect(
        draft.notes.firstWhere((n) => n.opId == 'color_calibrate').reason,
        'no photometric catalogue is installed',
      );
      expect(
        darkroom.previewContexts,
        hasLength(1),
        reason:
            'the dropped step was already skipping when the registry measured '
            'the stretch, so the prefix did not move and nothing is re-measured',
      );
    },
  );

  test('an RGB master with no colour-indexed catalogue star drops the colour '
      'step before rendering anything', () async {
    darkroom.draftSteps = [
      {
        'opId': 'color_calibrate',
        'opVersion': 1,
        'params': <String, dynamic>{},
        'enabled': true,
      },
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId], channels: 3);

    final outcome = await buildService().runDawnForSession(sessionId);

    final draft = outcome.report!.masters.single.draft!;
    expect(draft.indexOfOp('color_calibrate'), -1);
    expect(darkroom.previewContexts, isEmpty);
    expect(
      draft.notes.firstWhere((n) => n.opId == 'color_calibrate').reason,
      contains('no solved astrometry'),
    );
  });

  test('a background extraction the registry dropped is retried once at half '
      'the sample spacing', () async {
    darkroom.draftSteps = [
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    darkroom.draftNotes = [
      {
        'opId': 'background_extract',
        'outcome': 'omitted',
        'reason': 'too few background samples survived the star mask',
      },
    ];
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    final draft = outcome.report!.masters.single.draft!;
    final index = draft.indexOfOp('background_extract');
    expect(index, 0, reason: 'the retried step takes its canonical place');
    expect(
      (draft.steps[index]['params'] as Map)['sampleSpacing'],
      kBackgroundRetrySampleSpacing,
    );
    expect(
      draft.notes.where((n) => n.opId == 'background_extract').last.outcome,
      'retried',
    );
    // The probe ran at the registry's own measurement dimension.
    expect(
      darkroom.previewContexts.first['maxDimension'],
      kDraftMeasureMaxDimension,
    );
  });

  test('a restored background fit has the stretch measured again over the '
      'stack it ends up on', () async {
    darkroom.draftSteps = [
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    darkroom.draftNotes = [
      {
        'opId': 'background_extract',
        'outcome': 'omitted',
        'reason': 'too few background samples survived the star mask',
      },
    ];
    darkroom.screenTransfer = {
      'blackPoint': 96.5,
      'whitePoint': 1850.0,
      'd': 3.5,
      'b': 0.0,
      'symmetryPoint': 0.0,
    };
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    // Two renders: the retry probe, then the measurement over the restored
    // prefix. The second stops one step below the stretch and asks the engine
    // for its own auto transfer over those pixels.
    expect(darkroom.previewContexts, hasLength(2));
    final remeasure = darkroom.previewContexts.last;
    expect(remeasure['encoding'], 'screen');
    expect(remeasure['stopAfter'], 0);
    expect(remeasure['maxDimension'], kDraftMeasureMaxDimension);

    final draft = outcome.report!.masters.single.draft!;
    final stretch = draft.steps[draft.indexOfOp('stretch')];
    expect(stretch['params'], {
      'blackPoint': 96.5,
      'whitePoint': 1850.0,
      'd': 3.5,
      'b': 0.0,
      'symmetryPoint': 0.0,
    });
    final note = draft.notes.firstWhere((n) => n.opId == 'stretch');
    expect(note.outcome, 'remeasured');
    expect(note.reason, contains('denser lattice'));
  });

  test('a stretch re-measurement that fails keeps the measured parameters and '
      'says they are a starting point', () async {
    darkroom.draftSteps = [
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    darkroom.draftNotes = [
      {
        'opId': 'background_extract',
        'outcome': 'omitted',
        'reason': 'too few background samples survived the star mask',
      },
    ];
    darkroom.screenPreviewError = const DarkroomSeamException(
      'renderPreview',
      'the master moved under the render',
      'remeasure',
    );
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    expect(
      outcome.succeeded,
      isTrue,
      reason:
          'a measurement that could not be repeated is a note, not a '
          'failed job',
    );
    final draft = outcome.report!.masters.single.draft!;
    expect(draft.indexOfOp('background_extract'), 0);
    expect(draft.steps[draft.indexOfOp('stretch')]['params'], {
      'blackPoint': 0.0,
      'whitePoint': 1.0,
    });
    final note = draft.notes.firstWhere((n) => n.opId == 'stretch');
    expect(note.outcome, 'included');
    expect(note.reason, contains('starting point'));
    expect(note.reason, contains('the master moved under the render'));
  });

  test('a background retry that also fails leaves the step out and records '
      'both attempts', () async {
    darkroom.draftSteps = [
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
    ];
    darkroom.draftNotes = [
      {
        'opId': 'background_extract',
        'outcome': 'omitted',
        'reason': 'too few background samples survived the star mask',
      },
    ];
    darkroom.previewError = const DarkroomSeamException(
      'renderPreview',
      'the background lattice is still too sparse',
      'probe',
    );
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    final draft = outcome.report!.masters.single.draft!;
    expect(draft.indexOfOp('background_extract'), -1);
    final notes = draft.notes
        .where((n) => n.opId == 'background_extract')
        .toList();
    expect(notes, hasLength(2));
    expect(notes.first.reason, contains('star mask'));
    expect(notes.last.reason, contains('still too sparse'));
    expect(
      outcome.succeeded,
      isTrue,
      reason: 'a dropped step is a note, not a failed job',
    );
  });

  test('saturation and curves never enter the draft', () async {
    darkroom.draftSteps = [
      {
        'opId': 'stretch',
        'opVersion': 1,
        'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
        'enabled': true,
      },
      {
        'opId': 'saturation',
        'opVersion': 1,
        'params': <String, dynamic>{},
        'enabled': true,
      },
      {
        'opId': 'curves',
        'opVersion': 1,
        'params': <String, dynamic>{},
        'enabled': true,
      },
    ];
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    final draft = outcome.report!.masters.single.draft!;
    expect(draft.steps.map((s) => s['opId']), ['stretch']);
    for (final opId in ['saturation', 'curves']) {
      expect(
        draft.notes.firstWhere((n) => n.opId == opId).reason,
        contains('identity transform'),
      );
    }
  });

  test('cancellation mid-pipeline stops before the next master', () async {
    final sessionId = await insertSession();
    final imageA = await insertSub(sessionId: sessionId);
    final imageB = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageA], filter: 'L');
    await insertMaster(
      imageIds: [imageB],
      filter: 'Ha',
      path: '${workspace.path}/M42_Ha_master.fits',
    );

    final jobId = await DarkroomJobsDao(db).enqueue(sessionId: sessionId);
    final service = buildService();
    darkroom.beforeRegistry = () async {
      if (darkroom.registryCalls.isNotEmpty) return;
      await service.requestCancel(jobId, reason: 'operator stopped the rig');
    };

    final outcome = await service.runJob(jobId);

    expect(outcome.state, DarkroomJobState.cancelled);
    final job = await DarkroomJobsDao(db).getById(jobId);
    expect(job!.state, DarkroomJobState.cancelled);
    expect(job.errorText, contains('Stopped on request'));
    // Exactly one master was drafted before the stop; the second never began.
    expect(darkroom.exportArgs, hasLength(1));
    // The engine's own flag was raised under the job's render id.
    expect(
      darkroom.cancelArgs.single['renderId'],
      DawnAutopilotService.renderIdFor(jobId),
    );
    expect(darkroom.cancelArgs.single['op'], 'cancel');
  });

  test(
    'a cancelled render is decoded by its payload kind, not its prose',
    () async {
      darkroom.previewError = const DarkroomCancelledOutcome(
        id: 'darkroom-job-1',
        phase: 'render',
        payload: {'kind': 'cancelled'},
      );
      darkroom.draftSteps = [
        {
          'opId': 'stretch',
          'opVersion': 1,
          'params': {'blackPoint': 0.0, 'whitePoint': 1.0},
          'enabled': true,
        },
      ];
      darkroom.draftNotes = [
        {
          'opId': 'background_extract',
          'outcome': 'omitted',
          'reason': 'too few background samples survived the star mask',
        },
      ];
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId]);

      final outcome = await buildService().runDawnForSession(sessionId);

      expect(outcome.state, DarkroomJobState.cancelled);
      final job = await DarkroomJobsDao(db).getById(outcome.jobId);
      expect(job!.errorText, contains('render phase'));
    },
  );

  test(
    'a manual job produces the draft and sends no morning notification',
    () async {
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId]);

      final outcome = await buildService().processSessionNow(sessionId);

      expect(outcome.succeeded, isTrue);
      final job = await DarkroomJobsDao(db).getById(outcome.jobId);
      expect(job!.kind, DarkroomJobKind.manual);
      expect(notifier.announced, isEmpty);
      expect(outcome.report!.notification!.sent, isFalse);
      expect(outcome.report!.notification!.reason, contains('started by hand'));
      expect(outcome.report!.draftsRendered, 1);
    },
  );

  test('a dawn job records the gate that silenced its notification', () async {
    notifier.decision = const DawnNotificationDecision(
      sent: false,
      reason:
          'The "Sequence Complete" event alert is switched off, so the morning '
          'message was not sent.',
    );
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    await insertMaster(imageIds: [imageId]);

    final outcome = await buildService().runDawnForSession(sessionId);

    expect(notifier.announced, hasLength(1));
    expect(outcome.report!.notification!.sent, isFalse);
    expect(outcome.report!.notification!.reason, contains('switched off'));
    expect(
      outcome.succeeded,
      isTrue,
      reason: 'a silenced notification is not a failed job',
    );
  });

  test(
    'a destination that refuses is a report line, not a failed job',
    () async {
      await DeliveryTargetsDao(db).create(
        name: 'office-pc',
        kind: ArtifactDestinationKind.watchedFolder,
        configJson: '{"path":"/mnt/office"}',
        content: ArtifactContent.values.toSet(),
      );
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(imageIds: [imageId]);

      final outcome = await buildService().runDawnForSession(sessionId);

      expect(outcome.succeeded, isTrue);
      expect(outcome.report!.delivery, isNotNull);
      expect(outcome.report!.deliveryProblems, isNotEmpty);
      expect(outcome.report!.body, contains('office-pc'));
    },
  );

  test('a master with no linear FITS is reported, never dropped', () async {
    final sessionId = await insertSession();
    final imageId = await insertSub(sessionId: sessionId);
    final masters = IntegratedMastersDao(db);
    final accumulating = await masters.insertMaster(
      name: 'M42 · L',
      sidecarPath: '${workspace.path}/M42.nsmaster',
      status: IntegratedMasterStatus.accumulating,
      accumulationMode: AccumulationMode.runningWeightedMean,
    );
    await masters.recordFoldedFrame(
      masterId: accumulating,
      imageId: imageId,
      accepted: true,
    );

    final outcome = await buildService().runDawnForSession(sessionId);

    expect(outcome.succeeded, isTrue);
    expect(outcome.report!.masters, isEmpty);
    expect(outcome.report!.withoutFile, hasLength(1));
    expect(
      outcome.report!.withoutFile.single.reason,
      contains('still accumulating'),
    );
    expect(outcome.report!.body, contains('still accumulating'));
  });

  test(
    'the report states the calibration warnings the integration recorded',
    () async {
      final sessionId = await insertSession();
      final imageId = await insertSub(sessionId: sessionId);
      await insertMaster(
        imageIds: [imageId],
        statsJson: jsonEncode({
          'framesIntegrated': 12,
          'framesRejected': 1,
          'calibration': {
            'anchorUnreadable': false,
            'cosmeticCorrection': true,
            'masters': [
              {
                'kind': 'dark',
                'path': '/cal/dark.fits',
                'applied': true,
                'quality': 'fallback',
                'stale': true,
                'mismatches': [
                  {
                    'dimension': 'EXPTIME',
                    'light': '120',
                    'master': '300',
                    'withinTolerance': false,
                  },
                ],
                'unverified': <String>[],
              },
              {
                'kind': 'flat',
                'path': null,
                'applied': false,
                'quality': 'missing',
                'stale': false,
                'mismatches': <dynamic>[],
                'unverified': <String>[],
              },
              {
                'kind': 'bias',
                'path': null,
                'applied': false,
                'quality': 'notRequired',
                'stale': false,
                'mismatches': <dynamic>[],
                'unverified': <String>[],
              },
            ],
          },
          'calibrationWarnings': ['The matched dark was shot 140 days ago.'],
        }),
      );

      final outcome = await buildService().runDawnForSession(sessionId);

      final report = outcome.report!;
      expect(report.calibrationWarned, isTrue);
      expect(report.body, contains('EXPTIME'));
      expect(report.body, contains('No master flat was applied'));
      expect(report.body, contains('140 days ago'));
      expect(
        report.body,
        isNot(contains('bias was applied')),
        reason: 'a not-required bias is not a warning',
      );
    },
  );

  test('a job left running by a dead process is re-queued at open and drained '
      'on the next start', () async {
    final crashDir = await Directory.systemTemp.createTemp('dawn-crash');
    addTearDown(() => crashDir.delete(recursive: true));
    final file = File('${crashDir.path}/nightshade.sqlite');
    final crashedMaster = '${crashDir.path}/M42_master.fits';
    await File(crashedMaster).writeAsString('linear master');

    final first = NightshadeDatabase.forTesting(NativeDatabase(file));
    final sessionId = await first
        .into(first.imagingSessions)
        .insert(ImagingSessionsCompanion.insert(startTime: DateTime.now()));
    final imageId = await first
        .into(first.capturedImages)
        .insert(
          CapturedImagesCompanion.insert(
            filePath: '/l/crash.fits',
            fileName: 'crash.fits',
            frameType: const Value('light'),
            exposureDuration: 120.0,
            capturedAt: DateTime.now(),
            sessionId: Value(sessionId),
            isAccepted: const Value(true),
          ),
        );
    final firstMasters = IntegratedMastersDao(first);
    final masterId = await firstMasters.insertMaster(
      name: 'M42',
      masterFitsPath: crashedMaster,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: 1,
      width: 100,
      height: 80,
      frameCount: 1,
      totalIntegrationSeconds: 120.0,
    );
    await firstMasters.recordFoldedFrame(
      masterId: masterId,
      imageId: imageId,
      accepted: true,
    );
    final jobId = await DarkroomJobsDao(first).enqueue(sessionId: sessionId);
    // The executor took the job and the process died before it finished.
    await DarkroomJobsDao(first).markRunning(jobId);
    await first.close();

    final second = NightshadeDatabase.forTesting(NativeDatabase(file));
    addTearDown(second.close);
    final recovered = await DarkroomJobsDao(second).getById(jobId);
    expect(recovered!.state, DarkroomJobState.queued);
    expect(recovered.note, contains('Re-queued'));
    expect(recovered.startedAt, isNull);

    final crashDarkroom = _ScriptedDarkroom(baseMasterRef: crashedMaster);
    final service = DawnAutopilotService(
      jobs: DarkroomJobsDao(second),
      recipes: RecipesDao(second),
      masters: IntegratedMastersDao(second),
      targets: TargetsDao(second),
      resolver: DawnMasterResolver(
        images: ImagesDao(second),
        masters: IntegratedMastersDao(second),
      ),
      drafts: DawnDraftBuilder(darkroom: crashDarkroom),
      darkroom: crashDarkroom,
      photometry: DawnPhotometryResolver(
        coneSearch: (centre, radius, {maxMagnitude}) async => const [],
      ),
      delivery: DeliveryService(
        targets: DeliveryTargetsDao(second),
        journal: DeliveryJournalDao(second),
        transportFactory: (destination, jobId) => _RefusingTransport(),
      ),
      notifier: notifier,
      outputDirectory: () async => crashDir.path,
    );

    final outcomes = await service.drainQueue();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.jobId, jobId);
    expect(outcomes.single.succeeded, isTrue);
    final finished = await DarkroomJobsDao(second).getById(jobId);
    expect(finished!.state, DarkroomJobState.done);
    expect(finished.attempts, 2, reason: 'the restart is a second start');
    expect(await RecipesDao(second).listForMaster(crashedMaster), hasLength(1));
  });

  test(
    'a job that names no session fails instead of drafting nothing quietly',
    () async {
      final jobId = await DarkroomJobsDao(db).enqueue();
      final outcome = await buildService().runJob(jobId);

      expect(outcome.state, DarkroomJobState.failed);
      expect(outcome.failure, contains('names no imaging session'));
    },
  );
}
