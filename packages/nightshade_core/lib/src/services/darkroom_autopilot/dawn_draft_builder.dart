/// Builds the first-draft recipe the operator wakes up to.
///
/// The draft is composed from the Darkroom registry's own measurements — the
/// auto crop rectangle, the auto stretch parameters, and each operation's
/// documented defaults — so the numbers come from the operations that will
/// render them rather than from a second copy kept here that drifts the first
/// time a range moves.
///
/// Three policies live on top of what the registry returns:
///
///  * **Nothing that renders nothing.** A step whose parameters are the
///    identity at its defaults (`saturation`, `curves`) is left out: it would
///    show in the history stack, change no pixel, and read as broken.
///  * **One background retry.** A dense field can leave the background lattice
///    with too few star-free samples to fit a surface. The draft retries once
///    at half the sample spacing, which doubles the lattice density per axis;
///    still failing, the step is left out and the operation's own reason is
///    recorded.
///  * **Colour is proved at full resolution.** `color_calibrate@1` detects
///    stars in the image it is handed, and a downsampled level does not hold
///    enough of them. The draft therefore renders the colour step once at level
///    0 and keeps it only when it actually applied there.
library;

import 'dart:convert';

import 'dawn_master_resolver.dart';
import 'dawn_photometry.dart';
import 'darkroom_seam.dart';

/// Wire schema version of the recipe envelope this build writes.
///
/// It matches `RECIPE_SCHEMA_VERSION` in the recipe engine; a recipe whose
/// version differs is refused by the engine rather than reinterpreted.
const int kRecipeSchemaVersion = 1;

/// The pyramid level the draft's colour step is proved at. Level 0 is the
/// master's own pixels.
const int kColorProofLevel = 0;

/// Longest edge, in pixels, of the level the background retry is probed at.
///
/// It matches the registry's own draft-measurement dimension, so a retry that
/// succeeds here succeeds under the same conditions the rest of the draft was
/// measured under.
const int kDraftMeasureMaxDimension = 1024;

/// The `sampleSpacing` a retried `background_extract@1` uses: half the
/// operation's documented 64-pixel default, which quadruples the number of
/// sample boxes and is the smallest change that can rescue a dense field.
const double kBackgroundRetrySampleSpacing = 32.0;

/// Operations whose defaults are the identity transform, so a draft that
/// carried them would list a step that changes nothing.
const Set<String> kIdentityAtDefaults = {'saturation', 'curves'};

/// The order a draft's steps are written in.
///
/// Every linear-stage operation precedes the stretch, because the engine's
/// validation refuses a linear operation after a stretched one. A step
/// re-inserted by a retry takes its place from this list rather than from
/// wherever the retry happened to run.
const List<String> kDraftStepOrder = [
  'crop',
  'background_extract',
  'denoise',
  'color_calibrate',
  'star_reduce',
  'stretch',
  'saturation',
  'curves',
];

/// What happened to one operation while the draft was composed.
class DawnDraftNote {
  /// The operation the note is about.
  final String opId;

  /// `included`, `retried`, or `omitted`.
  final String outcome;

  /// Why, in the words the morning report prints.
  final String reason;

  const DawnDraftNote({
    required this.opId,
    required this.outcome,
    required this.reason,
  });

  /// The note as report JSON.
  Map<String, dynamic> toJson() => {
    'opId': opId,
    'outcome': outcome,
    'reason': reason,
  };

  @override
  String toString() => '$opId: $outcome — $reason';
}

/// A composed first draft: the steps, and the account of how they got there.
class DawnDraft {
  /// The linear master these steps replay over.
  final String baseMasterRef;

  /// The ordered op stack, each entry `{opId, opVersion, params, enabled}`.
  final List<Map<String, dynamic>> steps;

  /// One note per operation the composition decided about.
  final List<DawnDraftNote> notes;

  const DawnDraft({
    required this.baseMasterRef,
    required this.steps,
    required this.notes,
  });

  /// True when the draft has nothing to render.
  bool get isEmpty => steps.isEmpty;

  /// Index of [opId] in the step list, or -1 when it is absent.
  int indexOfOp(String opId) =>
      steps.indexWhere((step) => step['opId'] == opId);

  /// The `recipes.steps_json` payload: the step list alone. The envelope's
  /// schema version lives in the row's own `schema_version` column.
  String encodeStepsJson() => jsonEncode(steps);

  /// The full recipe envelope the render entry points take, carrying [recipeId]
  /// as the recipe's identity.
  String encodeRecipeJson(String recipeId) => jsonEncode({
    'id': recipeId,
    'schemaVersion': kRecipeSchemaVersion,
    'baseMasterRef': baseMasterRef,
    'createdBy': 'autopilot',
    'steps': steps,
  });
}

/// The draft could not be composed at all.
class DawnDraftException implements Exception {
  final String message;

  const DawnDraftException(this.message);

  @override
  String toString() => 'Cannot compose a first draft: $message';
}

/// Composes the first-draft recipe for one master.
class DawnDraftBuilder {
  final DarkroomSeam _darkroom;

  const DawnDraftBuilder({required DarkroomSeam darkroom})
    : _darkroom = darkroom;

  /// Build the draft for [master].
  ///
  /// [renderId] makes every render this issues cancellable under the job's own
  /// id. [photometry] is what `color_calibrate@1` regresses against; a field
  /// with no colour-indexed star leaves the colour step out with that reason
  /// rather than carrying a step that can only skip.
  ///
  /// Throws [DawnDraftException] when the registry reply does not describe a
  /// draft, and lets a [DarkroomCancelledOutcome] out untouched.
  Future<DawnDraft> build({
    required DawnMaster master,
    required String recipeId,
    required DawnPhotometry photometry,
    required String renderId,
  }) async {
    final reply = await _darkroom.registry({
      'masterPath': master.masterFitsPath,
      'baseMasterRef': master.masterFitsPath,
      'recipeId': recipeId,
    });

    final draft = reply['draft'];
    if (draft is! Map<String, dynamic>) {
      throw DawnDraftException(
        'the registry answered for ${master.masterFitsPath} without a draft, '
        'so there are no measured parameters to build one from',
      );
    }
    final recipe = draft['recipe'];
    if (recipe is! Map<String, dynamic>) {
      throw const DawnDraftException(
        'the registry draft carries no recipe, so it names no operations',
      );
    }
    final rawSteps = recipe['steps'];
    if (rawSteps is! List) {
      throw const DawnDraftException(
        'the registry draft recipe carries no step list',
      );
    }

    final notes = <DawnDraftNote>[];
    _adoptRegistryNotes(draft['notes'], notes);

    var steps = <Map<String, dynamic>>[
      for (final step in rawSteps)
        if (step is Map<String, dynamic>) Map<String, dynamic>.from(step),
    ];
    steps = _dropIdentitySteps(steps, notes);
    steps = await _retryBackgroundExtract(
      master: master,
      recipeId: recipeId,
      steps: steps,
      notes: notes,
      renderId: renderId,
    );
    steps = await _proveColorCalibrate(
      master: master,
      recipeId: recipeId,
      steps: steps,
      notes: notes,
      photometry: photometry,
      renderId: renderId,
    );

    for (final step in steps) {
      final opId = step['opId'];
      if (opId is! String) continue;
      if (notes.any((n) => n.opId == opId && n.outcome != 'omitted')) continue;
      notes.add(
        DawnDraftNote(
          opId: opId,
          outcome: 'included',
          reason: 'measured from this master by the operation registry',
        ),
      );
    }

    return DawnDraft(
      baseMasterRef: master.masterFitsPath,
      steps: List.unmodifiable(steps),
      notes: List.unmodifiable(notes),
    );
  }

  /// Carry the registry's own omission notes into the draft's account, so a
  /// step the measurement dropped is explained by the words the operation used.
  static void _adoptRegistryNotes(Object? raw, List<DawnDraftNote> notes) {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final opId = entry['opId'];
      final reason = entry['reason'];
      final outcome = entry['outcome'];
      if (opId is! String) continue;
      notes.add(
        DawnDraftNote(
          opId: opId,
          outcome: outcome is String ? outcome : 'omitted',
          reason: reason is String
              ? reason
              : 'the operation registry omitted it without stating a reason',
        ),
      );
    }
  }

  /// Drop the steps whose defaults are the identity transform.
  static List<Map<String, dynamic>> _dropIdentitySteps(
    List<Map<String, dynamic>> steps,
    List<DawnDraftNote> notes,
  ) {
    final kept = <Map<String, dynamic>>[];
    for (final step in steps) {
      final opId = step['opId'];
      if (opId is String && kIdentityAtDefaults.contains(opId)) {
        notes.add(
          DawnDraftNote(
            opId: opId,
            outcome: 'omitted',
            reason:
                'at its defaults this operation is the identity transform, so '
                'a first draft carrying it would list a step that changes no '
                'pixel',
          ),
        );
        continue;
      }
      kept.add(step);
    }
    return kept;
  }

  /// Retry a background extraction the registry's measurement dropped.
  ///
  /// The one documented failure is a field too dense for the star-rejected
  /// lattice to leave enough samples; halving the spacing quadruples the sample
  /// count, which is the change that rescues it. The retry is probed at the
  /// same level the registry measured at, so a pass here means a pass there.
  Future<List<Map<String, dynamic>>> _retryBackgroundExtract({
    required DawnMaster master,
    required String recipeId,
    required List<Map<String, dynamic>> steps,
    required List<DawnDraftNote> notes,
    required String renderId,
  }) async {
    const opId = 'background_extract';
    if (steps.any((step) => step['opId'] == opId)) return steps;
    final omission = notes
        .where((n) => n.opId == opId && n.outcome == 'omitted')
        .toList(growable: false);
    if (omission.isEmpty) return steps;

    final candidate = <String, dynamic>{
      'opId': opId,
      'opVersion': 1,
      'params': {'sampleSpacing': kBackgroundRetrySampleSpacing},
      'enabled': true,
    };
    final probed = _insertInDraftOrder(steps, candidate);
    final index = probed.indexWhere((step) => step['opId'] == opId);

    final String? failure;
    try {
      final preview = await _darkroom.renderPreview(
        recipeJson: _envelope(recipeId, master.masterFitsPath, probed),
        context: {
          'masterPath': master.masterFitsPath,
          'maxDimension': kDraftMeasureMaxDimension,
          'stopAfter': index,
          'renderId': renderId,
          'encoding': 'unit',
        },
      );
      failure = _skipReasonFor(preview.report, index);
    } on DarkroomSeamException catch (error) {
      notes.add(
        DawnDraftNote(
          opId: opId,
          outcome: 'omitted',
          reason:
              'the retry at half the sample spacing '
              '(${kBackgroundRetrySampleSpacing.toStringAsFixed(0)} px) also '
              'failed: ${error.message}. The draft leaves the background fit '
              'out; the gradient is still in the master and can be removed by '
              'hand in the editor.',
        ),
      );
      return steps;
    }

    if (failure != null) {
      notes.add(
        DawnDraftNote(
          opId: opId,
          outcome: 'omitted',
          reason:
              'the retry at half the sample spacing '
              '(${kBackgroundRetrySampleSpacing.toStringAsFixed(0)} px) was '
              'skipped: $failure',
        ),
      );
      return steps;
    }

    notes.add(
      DawnDraftNote(
        opId: opId,
        outcome: 'retried',
        reason:
            'the background fit failed at its default 64 px sample spacing and '
            'succeeded at '
            '${kBackgroundRetrySampleSpacing.toStringAsFixed(0)} px, so the '
            'draft carries the denser lattice. The auto stretch was measured '
            'before this step was restored, so its black and white points are '
            'a starting point rather than a fit of these pixels.',
      ),
    );
    return probed;
  }

  /// Prove the colour step at full resolution and keep it only when it applied.
  ///
  /// `color_calibrate@1` needs three channels, a plate solve, and stars it can
  /// both detect and cross-match. A step that can only skip belongs in the
  /// report, not in the history stack.
  Future<List<Map<String, dynamic>>> _proveColorCalibrate({
    required DawnMaster master,
    required String recipeId,
    required List<Map<String, dynamic>> steps,
    required List<DawnDraftNote> notes,
    required DawnPhotometry photometry,
    required String renderId,
  }) async {
    const opId = 'color_calibrate';
    final index = steps.indexWhere((step) => step['opId'] == opId);
    if (index < 0) return steps;

    if (!master.isColor) {
      return _dropAt(
        steps,
        index,
        notes,
        opId,
        'this master has ${master.channels} channel(s) and the colour fit needs '
        'three, so the per-filter masters are combined before it can run',
      );
    }
    if (!photometry.hasStars) {
      final reason = photometry.unavailableReason;
      return _dropAt(
        steps,
        index,
        notes,
        opId,
        reason ??
            'no catalogue star was resolved for this field, so the colour '
                'fit has nothing to regress against',
      );
    }

    final DarkroomRenderedPreview preview;
    try {
      preview = await _darkroom.renderPreview(
        recipeJson: _envelope(recipeId, master.masterFitsPath, steps),
        context: {
          'masterPath': master.masterFitsPath,
          'level': kColorProofLevel,
          'stopAfter': index,
          'renderId': renderId,
          'encoding': 'unit',
          'catalogStars': photometry.stars,
        },
      );
    } on DarkroomSeamException catch (error) {
      return _dropAt(steps, index, notes, opId, error.message);
    }

    final skipped = _skipReasonFor(preview.report, index);
    if (skipped != null) {
      return _dropAt(steps, index, notes, opId, skipped);
    }

    notes.add(
      DawnDraftNote(
        opId: opId,
        outcome: 'included',
        reason:
            'the colour fit applied at full resolution against '
            '${photometry.stars.length} catalogue stars. It solves the balance '
            'from that catalogue on every render — this build reads back no '
            'fitted channel scales to write into the step — so a preview at a '
            'reduced level can detect too few stars and record the step as '
            'skipped with that reason.',
      ),
    );
    return steps;
  }

  /// Remove the step at [index], recording why.
  static List<Map<String, dynamic>> _dropAt(
    List<Map<String, dynamic>> steps,
    int index,
    List<DawnDraftNote> notes,
    String opId,
    String reason,
  ) {
    notes.add(DawnDraftNote(opId: opId, outcome: 'omitted', reason: reason));
    final kept = List<Map<String, dynamic>>.from(steps)..removeAt(index);
    return kept;
  }

  /// The skip reason the render report records for step [index], or null when
  /// the step applied.
  ///
  /// A step the report does not mention at all is treated as un-run and
  /// reported as such: claiming it applied because no reason was printed is
  /// exactly the silent pass this pipeline refuses.
  static String? _skipReasonFor(Map<String, dynamic> report, int index) {
    final inner = report['report'];
    final steps = inner is Map<String, dynamic> ? inner['steps'] : null;
    if (steps is! List) {
      return 'the render answered without a step report, so nothing states '
          'whether the operation ran';
    }
    for (final entry in steps) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['index'] != index) continue;
      final outcome = entry['outcome'];
      if (outcome == 'applied') return null;
      final reason = entry['reason'];
      if (reason is String && reason.isNotEmpty) return reason;
      return 'the render recorded the step as "$outcome"';
    }
    return 'the render report carries no entry for step $index, so nothing '
        'states whether the operation ran';
  }

  /// Insert [candidate] into [steps] at its place in [kDraftStepOrder].
  static List<Map<String, dynamic>> _insertInDraftOrder(
    List<Map<String, dynamic>> steps,
    Map<String, dynamic> candidate,
  ) {
    final rank = kDraftStepOrder.indexOf(candidate['opId'] as String);
    final out = List<Map<String, dynamic>>.from(steps);
    for (var i = 0; i < out.length; i++) {
      final other = out[i]['opId'];
      final otherRank = other is String ? kDraftStepOrder.indexOf(other) : -1;
      if (otherRank > rank) {
        out.insert(i, candidate);
        return out;
      }
    }
    out.add(candidate);
    return out;
  }

  static String _envelope(
    String recipeId,
    String baseMasterRef,
    List<Map<String, dynamic>> steps,
  ) {
    return jsonEncode({
      'id': recipeId,
      'schemaVersion': kRecipeSchemaVersion,
      'baseMasterRef': baseMasterRef,
      'createdBy': 'autopilot',
      'steps': steps,
    });
  }
}
