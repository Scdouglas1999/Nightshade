/// Drives the Darkroom editor: the recipe as data, the render loop over it, and
/// the account of what every step did.
///
/// **Where the work happens.** Every Darkroom native call goes through
/// [DarkroomSeam], never through the generated bridge — the UI package must not
/// import it, and a scripted seam is what makes the render loop testable without
/// the Rust library loaded.
///
/// **The render loop.** A render is one synchronous descent into the engine, so
/// it cannot be pre-empted and Dart cannot abort it; it can only be asked to
/// stop. Three mechanisms hold the loop honest:
///
///  * a **debounce** ([kDarkroomRenderDebounce]) so a parameter drag renders
///    once at its end rather than once per frame;
///  * a **single-flight latch** so two renders never enter the engine at once;
///  * a **generation counter** that rides inside the render id, so a superseded
///    render is cancelled by that id and its pixels — which describe a recipe
///    the operator has already changed — are dropped rather than painted.
///
/// Because the generation is part of the render id, a cancellation flag left
/// armed by a render that finished before it was polled cannot reach into the
/// next render: that one asks under a different id.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

part 'darkroom_controller_parts/_models.dart';
part 'darkroom_controller_parts/_state.dart';
part 'darkroom_controller_parts/_helpers.dart';

/// The most step lists the undo journal keeps.
///
/// A recipe is data and a step list is small, so the cap is about bounding a
/// long session's memory, not about the operator running out of undo in
/// practice.
const int kDarkroomJournalDepth = 100;

/// Drives one Darkroom scope.
class DarkroomController extends StateNotifier<DarkroomState> {
  /// Collaborators are resolved once, here, rather than read from [ref] on each
  /// use: [dispose] issues the last write and the stop request for a render
  /// that is still inside the engine, and by then the container that owns
  /// [ref] may already be tearing down.
  DarkroomController(Ref ref, this._scope)
    : _darkroom = ref.read(darkroomSeamProvider),
      _recipes = ref.read(recipesDaoProvider),
      _masters = ref.read(integratedMastersDaoProvider),
      _photometry = ref.read(dawnPhotometryResolverProvider),
      super(const DarkroomState()) {
    unawaited(_load());
  }

  final DarkroomScope _scope;
  final DarkroomSeam _darkroom;
  final RecipesDao _recipes;
  final IntegratedMastersDao _masters;
  final DawnPhotometryResolver _photometry;

  Timer? _renderDebounce;
  Timer? _saveDebounce;

  /// Bumped once per requested render. A render whose generation is no longer
  /// the newest is superseded: its pixels describe a recipe the operator has
  /// already edited.
  int _renderGeneration = 0;

  /// Bumped once per requested validation, for the same reason.
  int _validateGeneration = 0;

  /// True while a render is inside the engine.
  bool _renderInFlight = false;

  /// The id the in-flight render is cancellable under, null when none is
  /// running.
  String? _inFlightRenderId;

  /// The step lists an undo restores, oldest first.
  final List<List<DarkroomStep>> _undoJournal = [];

  /// The step lists a redo re-applies, oldest first.
  final List<List<DarkroomStep>> _redoJournal = [];

  /// The catalogue stars `color_calibrate` regresses against. Empty when the
  /// field could not be placed on the sky, which the operation then reports as
  /// its own stated skip reason.
  List<Map<String, dynamic>> _catalogStars = const [];

  /// True when an edit has not yet reached the recipe row.
  bool _savePending = false;

  /// Which control the last edit came from, and when.
  ///
  /// A slider emits a value per frame, so a drag is one intent and sixty edits.
  /// Journalling each of them would make undo walk back through the drag one
  /// frame at a time; folding consecutive edits from the same control inside
  /// [kDarkroomEditCoalesceWindow] makes one undo step out of one gesture.
  String? _lastEditKey;
  DateTime? _lastEditAt;

  /// The catalogue stars every render of this recipe lends `color_calibrate`.
  ///
  /// Read by the export, which replays the same stack at full resolution: an
  /// export that dropped the photometry would record the colour step as skipped
  /// for want of a catalogue the editor plainly had, and write a file whose
  /// HISTORY says so.
  List<Map<String, dynamic>> get catalogStars =>
      List.unmodifiable(_catalogStars);

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------

  /// Reload everything this scope names.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    state = state.copyWith(
      loading: true,
      clearLoadError: true,
      clearOffer: true,
      clearOfferError: true,
    );
    unawaited(_loadCatalog());

    if (_scope.isEmpty) {
      _fail(
        'This link named neither a recipe nor a master, so there is nothing to '
        'open. Reach the Darkroom from a master in the session review, or from '
        'the morning notification for a finished draft.',
      );
      return;
    }

    try {
      final recipeId = _scope.recipeId;
      if (recipeId != null) {
        final recipe = await _recipes.getById(recipeId);
        if (!mounted) return;
        if (recipe == null) {
          _fail(
            'Recipe $recipeId does not exist. It may have been deleted along '
            'with the master it was written for.',
          );
          return;
        }
        await _openRecipe(recipe);
        return;
      }

      final masterId = _scope.masterId!;
      final master = await _masters.getById(masterId);
      if (!mounted) return;
      if (master == null) {
        _fail(
          'Master $masterId does not exist. It may have been deleted from the '
          'library.',
        );
        return;
      }
      final path = master.masterFitsPath;
      if (path == null || path.trim().isEmpty) {
        _fail(
          '"${master.name}" is still accumulating and has not written a linear '
          'master yet, so there are no pixels to interpret. Finalize it in the '
          'session review first.',
        );
        return;
      }
      final existing = await _recipes.listForMaster(path);
      if (!mounted) return;
      if (existing.isNotEmpty) {
        // listForMaster orders newest first, so this is the most recent recipe
        // written over these pixels.
        await _openRecipe(existing.first);
        return;
      }
      state = state.copyWith(
        loading: false,
        offer: DarkroomStartOffer(
          masterId: masterId,
          targetId: master.targetId,
          masterName: master.name,
          masterFitsPath: path,
          channels: master.channels,
          width: master.width,
          height: master.height,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _fail('The Darkroom could not read this master or its recipes: $error');
    }
  }

  void _fail(String message) {
    state = state.copyWith(loading: false, loadError: message);
  }

  Future<void> _loadCatalog() async {
    try {
      final reply = await _darkroom.registry(const <String, dynamic>{});
      if (!mounted) return;
      state = state.copyWith(catalog: decodeDarkroomCatalog(reply));
    } on DarkroomSeamException catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        catalogError:
            'The operation catalogue could not be read, so the parameter '
            'ranges behind these controls are unknown: ${error.message}',
      );
    } on DarkroomRecipeFormatException catch (error) {
      if (!mounted) return;
      state = state.copyWith(catalogError: error.message);
    }
  }

  Future<void> _openRecipe(DarkroomRecipe recipe) async {
    final List<DarkroomStep> steps;
    try {
      steps = decodeDarkroomSteps(recipe.stepsJson);
    } on DarkroomRecipeFormatException catch (error) {
      _fail('${error.message}. The recipe row was not changed.');
      return;
    }

    _undoJournal.clear();
    _redoJournal.clear();
    state = state.copyWith(
      loading: false,
      clearLoadError: true,
      clearOffer: true,
      recipeId: recipe.id,
      recipeName: recipe.name.isEmpty ? 'Recipe ${recipe.id}' : recipe.name,
      baseMasterPath: recipe.baseMasterPath,
      author: recipe.createdBy,
      masterId: recipe.masterId,
      steps: List.unmodifiable(steps),
      canUndo: false,
      canRedo: false,
      savePending: false,
      clearSaveError: true,
    );

    _lastEditKey = null;
    _lastEditAt = null;
    await _resolvePhotometry(recipe.masterId);
    if (!mounted) return;
    unawaited(_refreshNow());
  }

  /// Resolve the catalogue stars `color_calibrate` needs, or state why there
  /// are none.
  ///
  /// The colour fit regresses against stars the CALLER supplies; with none
  /// attached the operation records itself as skipped with that reason. Naming
  /// the app-side half of the same fact is what turns the step card's skip
  /// badge into an explanation instead of a failure.
  Future<void> _resolvePhotometry(int? masterId) async {
    if (masterId == null) {
      _catalogStars = const [];
      state = state.copyWith(
        photometryStarCount: 0,
        photometryNote:
            'This recipe carries no library row for its master, so the field '
            'cannot be placed on the sky and the colour calibration has no '
            'catalogue stars to regress against.',
      );
      return;
    }
    try {
      final master = await _masters.getById(masterId);
      if (!mounted) return;
      if (master == null) {
        _catalogStars = const [];
        state = state.copyWith(
          photometryStarCount: 0,
          photometryNote:
              'The library row for this master is gone, so its solved '
              'astrometry cannot be read and the colour calibration has no '
              'catalogue stars.',
        );
        return;
      }
      final wcs = overlayFromMasterWcs(
        crval1: master.wcsCrval1,
        crval2: master.wcsCrval2,
        crpix1: master.wcsCrpix1,
        crpix2: master.wcsCrpix2,
        cd11: master.wcsCd1_1,
        cd12: master.wcsCd1_2,
        cd21: master.wcsCd2_1,
        cd22: master.wcsCd2_2,
      );
      final masterPath = master.masterFitsPath;
      final photometry = await _photometry.resolve(
        master: DawnMaster(
          masterId: master.id,
          targetId: master.targetId,
          name: master.name,
          filter: master.filter,
          masterFitsPath: masterPath == null || masterPath.isEmpty
              ? state.baseMasterPath
              : masterPath,
          channels: master.channels,
          width: master.width,
          height: master.height,
          frameCount: master.frameCount,
          totalIntegrationSeconds: master.totalIntegrationSeconds,
        ),
        wcs: wcs,
      );
      if (!mounted) return;
      _catalogStars = photometry.stars;
      state = state.copyWith(
        photometryStarCount: photometry.stars.length,
        photometryNote: photometry.unavailableReason,
      );
    } catch (error) {
      if (!mounted) return;
      _catalogStars = const [];
      state = state.copyWith(
        photometryStarCount: 0,
        photometryNote:
            'The star catalogue could not be read, so the colour calibration '
            'has nothing to regress against: $error',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Creating a recipe for a master that has none
  // ---------------------------------------------------------------------

  /// Create an empty user recipe over the offered master: the master's own
  /// linear pixels, with nothing interpreted yet.
  Future<void> startFromLinear() async {
    final offer = state.offer;
    if (offer == null || state.offerBusy) return;
    state = state.copyWith(offerBusy: true, clearOfferError: true);
    await _createRecipe(offer: offer, steps: const [], name: 'Linear');
  }

  /// Ask the operation registry for a first draft measured from the offered
  /// master, and open a user recipe carrying it.
  Future<void> draftForMe() async {
    final offer = state.offer;
    if (offer == null || state.offerBusy) return;
    state = state.copyWith(offerBusy: true, clearOfferError: true);

    final List<DarkroomStep> steps;
    try {
      final reply = await _darkroom.registry({
        'masterPath': offer.masterFitsPath,
        'baseMasterRef': offer.masterFitsPath,
      });
      if (!mounted) return;
      steps = decodeDarkroomDraft(reply);
    } on DarkroomCancelledOutcome catch (cancelled) {
      if (!mounted) return;
      state = state.copyWith(
        offerBusy: false,
        offerError:
            'The draft was stopped during ${cancelled.phase}; no recipe was '
            'created.',
      );
      return;
    } on DarkroomSeamException catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        offerBusy: false,
        offerError:
            'The registry could not measure a draft from this master, so no '
            'recipe was created: ${error.message}',
      );
      return;
    } on DarkroomRecipeFormatException catch (error) {
      if (!mounted) return;
      state = state.copyWith(offerBusy: false, offerError: error.message);
      return;
    }

    await _createRecipe(offer: offer, steps: steps, name: 'Draft');
  }

  Future<void> _createRecipe({
    required DarkroomStartOffer offer,
    required List<DarkroomStep> steps,
    required String name,
  }) async {
    try {
      final id = await _recipes.create(
        targetId: offer.targetId,
        masterId: offer.masterId,
        baseMasterPath: offer.masterFitsPath,
        name: name,
        stepsJson: jsonEncode([for (final step in steps) step.toJson()]),
        createdBy: RecipeAuthor.user,
        schemaVersion: kDarkroomRecipeSchemaVersion,
      );
      if (!mounted) return;
      final created = await _recipes.getById(id);
      if (!mounted) return;
      if (created == null) {
        state = state.copyWith(
          offerBusy: false,
          offerError:
              'The recipe row was written as id $id but could not be read '
              'back, so the editor has nothing to open.',
        );
        return;
      }
      state = state.copyWith(offerBusy: false);
      await _openRecipe(created);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        offerBusy: false,
        offerError: 'The recipe could not be created: $error',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------

  /// Toggle whether the step at [index] renders. Nothing is destroyed: the step
  /// and its parameters survive the disable.
  void toggleStep(int index) {
    final steps = state.steps;
    if (index < 0 || index >= steps.length) return;
    final next = List<DarkroomStep>.from(steps);
    next[index] = next[index].copyWith(enabled: !next[index].enabled);
    _applyEdit(next);
  }

  /// Set one parameter of the step at [index].
  ///
  /// A null [value] removes the key, which restores the operation's own
  /// documented default rather than freezing today's value into the recipe.
  ///
  /// Consecutive changes to one parameter fold into a single undo step; see
  /// [kDarkroomEditCoalesceWindow].
  void setParam(int index, String name, Object? value) {
    final steps = state.steps;
    if (index < 0 || index >= steps.length) return;
    final next = List<DarkroomStep>.from(steps);
    next[index] = next[index].withParam(name, value);
    _applyEdit(next, coalesceKey: 'param:$index:$name');
  }

  /// Turn every step off. Nothing is destroyed — the stack is intact and one
  /// undo (or one toggle each) brings it back.
  void resetToLinear() {
    final steps = state.steps;
    if (steps.isEmpty || steps.every((step) => !step.enabled)) return;
    _applyEdit([for (final step in steps) step.copyWith(enabled: false)]);
  }

  /// Move the step at [oldIndex] to [newIndex], but only when the engine
  /// accepts the resulting order.
  ///
  /// The order carries a rule — a linear-stage operation cannot run after a
  /// stretched one — that the engine owns. Asking it BEFORE the move commits is
  /// what keeps the panel from showing an order that renders nothing; the
  /// refusal carries the engine's own sentence.
  ///
  /// [newIndex] is the destination in the list AFTER the step is lifted out of
  /// it — the index `ReorderableListView.onReorderItem` reports.
  Future<bool> reorderStep(int oldIndex, int newIndex) async {
    final steps = state.steps;
    if (oldIndex < 0 || oldIndex >= steps.length) return false;
    var target = newIndex;
    if (target < 0) target = 0;
    if (target >= steps.length) target = steps.length - 1;
    if (target == oldIndex) {
      state = state.copyWith(clearReorderRefusal: true);
      return true;
    }

    final candidate = List<DarkroomStep>.from(steps);
    candidate.insert(target, candidate.removeAt(oldIndex));

    final verdict = await _validateSteps(candidate);
    if (!mounted) return false;
    if (verdict == null) {
      state = state.copyWith(
        reorderRefusal:
            'The engine could not be asked whether that order is legal, so the '
            'move was not made.',
      );
      return false;
    }
    if (!verdict.ok) {
      // The verdict's per-step entries index the REJECTED order, so adopting
      // them here would attach each message to the wrong card. Only the
      // whole-recipe sentence describes an order that is not on screen.
      state = state.copyWith(
        reorderRefusal:
            verdict.error ??
            'The engine refused that order without naming a reason.',
      );
      return false;
    }
    _applyEdit(candidate, verdict: verdict);
    return true;
  }

  /// Restore the step list as it was before the last edit.
  void undo() {
    if (_undoJournal.isEmpty) return;
    final previous = _undoJournal.removeLast();
    _redoJournal.add(state.steps);
    _commitJournalledSteps(previous);
  }

  /// Re-apply the step list an [undo] set aside.
  void redo() {
    if (_redoJournal.isEmpty) return;
    final next = _redoJournal.removeLast();
    _undoJournal.add(state.steps);
    _commitJournalledSteps(next);
  }

  void _commitJournalledSteps(List<DarkroomStep> steps) {
    // An undo is a deliberate step, never part of the gesture that preceded it.
    _lastEditKey = null;
    _lastEditAt = null;
    state = state.copyWith(
      steps: List.unmodifiable(steps),
      canUndo: _undoJournal.isNotEmpty,
      canRedo: _redoJournal.isNotEmpty,
      clearReorderRefusal: true,
    );
    _scheduleRefresh();
    _scheduleSave();
  }

  /// Adopt [steps] as the edited stack: journal the previous list, re-check and
  /// re-render it, and schedule the write to the recipe row.
  ///
  /// [coalesceKey] names the control the edit came from. Consecutive edits from
  /// the same control inside [kDarkroomEditCoalesceWindow] extend the journal's
  /// top entry instead of adding one, so a slider drag is one undo step.
  void _applyEdit(
    List<DarkroomStep> steps, {
    DarkroomValidation? verdict,
    String? coalesceKey,
  }) {
    final now = DateTime.now();
    final lastAt = _lastEditAt;
    final continues =
        coalesceKey != null &&
        coalesceKey == _lastEditKey &&
        lastAt != null &&
        now.difference(lastAt) < kDarkroomEditCoalesceWindow;
    if (!continues) {
      _undoJournal.add(state.steps);
      if (_undoJournal.length > kDarkroomJournalDepth) {
        _undoJournal.removeAt(0);
      }
      _redoJournal.clear();
    }
    _lastEditKey = coalesceKey;
    _lastEditAt = now;

    state = state.copyWith(
      steps: List.unmodifiable(steps),
      canUndo: _undoJournal.isNotEmpty,
      canRedo: _redoJournal.isNotEmpty,
      clearReorderRefusal: true,
      // A verdict arrives only from the reorder path, which already asked the
      // engine about this exact order; every other edit re-asks on the
      // debounce rather than carrying the previous order's verdicts forward.
      issues: verdict?.steps,
      recipeError: verdict?.error,
      clearRecipeError: verdict != null && verdict.ok,
    );
    _scheduleRefresh();
    _scheduleSave();
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  /// Re-check the committed step list and adopt its per-step verdicts.
  Future<void> _revalidate() async {
    final generation = ++_validateGeneration;
    final verdict = await _validateSteps(state.steps);
    if (!mounted || generation != _validateGeneration) return;
    if (verdict == null) return;
    state = state.copyWith(
      issues: verdict.steps,
      recipeError: verdict.error,
      clearRecipeError: verdict.ok,
    );
  }

  /// Ask the engine about [steps], or return null when it could not be asked.
  Future<DarkroomValidation?> _validateSteps(List<DarkroomStep> steps) async {
    final recipeId = state.recipeId;
    if (recipeId == null) return null;
    try {
      final reply = await _darkroom.validate(
        recipeJson: encodeDarkroomRecipe(
          recipeId: recipeId,
          baseMasterRef: state.baseMasterPath,
          author: state.author,
          steps: steps,
        ),
        context: const <String, dynamic>{},
      );
      return decodeDarkroomValidation(reply);
    } on DarkroomSeamException catch (error) {
      if (!mounted) return null;
      state = state.copyWith(
        recipeError: 'The recipe could not be checked: ${error.message}',
      );
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  /// Re-check and re-render the committed stack after the edit debounce.
  ///
  /// Both halves ride one timer: `validate` touches no pixels, so asking it
  /// first costs nothing and means the inline verdicts and the picture describe
  /// the same step list.
  void _scheduleRefresh() {
    _renderDebounce?.cancel();
    _renderDebounce = Timer(kDarkroomRenderDebounce, () {
      unawaited(_refreshNow());
    });
  }

  /// Re-check and re-render now, superseding whatever is in flight.
  Future<void> refreshRender() async {
    _renderDebounce?.cancel();
    await _refreshNow();
  }

  Future<void> _refreshNow() async {
    await _revalidate();
    if (!mounted) return;
    await _startRender();
  }

  Future<void> _startRender() async {
    if (!mounted) return;
    if (state.recipeId == null || state.baseMasterPath.isEmpty) return;
    final generation = ++_renderGeneration;
    if (_renderInFlight) {
      // The engine renders one recipe at a time, so the running render is asked
      // to stop by its own id; its completion starts the newest generation.
      // This is not the operator's stop, so nothing announces "Stopping…".
      await _requestCancel(_inFlightRenderId, announce: false);
      return;
    }
    await _runRender(generation);
  }

  Future<void> _runRender(int generation) async {
    final recipeId = state.recipeId;
    final masterPath = state.baseMasterPath;
    if (recipeId == null || masterPath.isEmpty) return;

    final renderId = 'darkroom-editor-$recipeId-$generation';
    _renderInFlight = true;
    _inFlightRenderId = renderId;
    state = state.copyWith(
      rendering: true,
      cancelRequested: false,
      clearRenderError: true,
      clearCancelledPhase: true,
    );

    final recipeJson = encodeDarkroomRecipe(
      recipeId: recipeId,
      baseMasterRef: masterPath,
      author: state.author,
      steps: state.steps,
    );

    try {
      final preview = await _darkroom.renderPreview(
        recipeJson: recipeJson,
        context: {
          'masterPath': masterPath,
          'maxDimension': kDarkroomPreviewMaxDimension,
          'renderId': renderId,
          'encoding': 'auto',
          if (_catalogStars.isNotEmpty) 'catalogStars': _catalogStars,
        },
      );
      if (!mounted || generation != _renderGeneration) return;
      state = state.copyWith(
        rendering: false,
        cancelRequested: false,
        preview: DarkroomPreviewImage(
          width: preview.width,
          height: preview.height,
          isColor: preview.isColor,
          rgba: preview.rgba,
          encoding: decodeDarkroomEncoding(preview.report),
          level: decodeDarkroomLevel(preview.report),
          scaleFromMaster: decodeDarkroomScaleFromMaster(preview.report),
        ),
        reports: decodeDarkroomStepReports(preview.report),
      );
    } on DarkroomCancelledOutcome catch (cancelled) {
      if (!mounted || generation != _renderGeneration) return;
      // A stopped render is the operator's own instruction being obeyed, not a
      // failure: the previous picture stays up and the phase it stopped in is
      // named.
      state = state.copyWith(
        rendering: false,
        cancelRequested: false,
        cancelledPhase: cancelled.phase,
      );
    } on DarkroomSeamException catch (error) {
      if (!mounted || generation != _renderGeneration) return;
      state = state.copyWith(
        rendering: false,
        cancelRequested: false,
        renderError: error.message,
      );
    } finally {
      _renderInFlight = false;
      _inFlightRenderId = null;
      if (mounted && generation != _renderGeneration) {
        unawaited(_runRender(_renderGeneration));
      }
    }
  }

  /// Ask the running render to stop.
  ///
  /// Cooperative: the engine honours the request at its next step boundary or
  /// pixel-budget poll, so the button reads "Stopping…" until the render
  /// answers rather than pretending the stop was instant.
  Future<void> cancelRender() async {
    final renderId = _inFlightRenderId;
    if (renderId == null || state.cancelRequested) return;
    await _requestCancel(renderId, announce: true);
  }

  Future<void> _requestCancel(String? renderId, {required bool announce}) async {
    if (renderId == null) return;
    if (announce) state = state.copyWith(cancelRequested: true);
    try {
      await _darkroom.cancel({'op': 'cancel', 'renderId': renderId});
    } on DarkroomSeamException catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        cancelRequested: false,
        renderError: 'The stop request did not reach the render: '
            '${error.message}',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  void _scheduleSave() {
    _savePending = true;
    state = state.copyWith(savePending: true);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(kDarkroomSaveDebounce, () {
      unawaited(_commitSteps());
    });
  }

  Future<void> _commitSteps() async {
    final recipeId = state.recipeId;
    if (recipeId == null) return;
    final payload = jsonEncode([for (final step in state.steps) step.toJson()]);
    try {
      final rows = await _recipes.updateSteps(recipeId, payload);
      _savePending = false;
      if (!mounted) return;
      if (rows == 0) {
        state = state.copyWith(
          savePending: false,
          saveError:
              'Recipe $recipeId no longer has a row, so this edit was not '
              'stored.',
        );
        return;
      }
      state = state.copyWith(savePending: false, clearSaveError: true);
    } catch (error) {
      _savePending = false;
      if (!mounted) return;
      state = state.copyWith(
        savePending: false,
        saveError: 'This edit could not be written to the recipe: $error',
      );
    }
  }

  @override
  void dispose() {
    _renderDebounce?.cancel();
    _saveDebounce?.cancel();
    final renderId = _inFlightRenderId;
    if (renderId != null) {
      // The render is inside the engine and outlives this notifier; leaving it
      // running would hold the engine against the next screen that wants it.
      unawaited(
        _darkroom.cancel({'op': 'cancel', 'renderId': renderId}).then(
          (_) {},
          onError: (Object error, StackTrace stack) {
            developer.log(
              'Darkroom: the stop request for $renderId did not land: $error',
              name: 'Darkroom',
              level: 900,
              stackTrace: stack,
            );
          },
        ),
      );
    }
    final recipeId = state.recipeId;
    if (_savePending && recipeId != null) {
      // A debounced edit that is never written is an edit the operator made and
      // lost. The write is issued here and its outcome logged, because dispose
      // cannot await it.
      final payload = jsonEncode([
        for (final step in state.steps) step.toJson(),
      ]);
      unawaited(
        _recipes.updateSteps(recipeId, payload).then(
          (_) {},
          onError: (Object error, StackTrace stack) {
            developer.log(
              'Darkroom: the last edit to recipe $recipeId was not stored: '
              '$error',
              name: 'Darkroom',
              level: 1000,
              stackTrace: stack,
            );
          },
        ),
      );
    }
    super.dispose();
  }
}

/// Family provider keyed by the scope, so a recipe opened by id and a master
/// opened by id are independent controllers.
final darkroomControllerProvider =
    StateNotifierProvider.family<
      DarkroomController,
      DarkroomState,
      DarkroomScope
    >((ref, scope) => DarkroomController(ref, scope));
