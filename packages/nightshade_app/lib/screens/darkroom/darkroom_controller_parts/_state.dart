part of '../darkroom_controller.dart';

/// What the Darkroom is showing right now.
///
/// The state is rebuilt whole on every change; there is no in-place mutation,
/// so a widget that captured an earlier state keeps describing the frame it was
/// built for.
@immutable
class DarkroomState {
  /// True until the first load settles.
  final bool loading;

  /// Why nothing can be opened, in the words the empty state prints. Null when
  /// a recipe (or an offer to create one) is loaded.
  final String? loadError;

  /// A master with no recipe, and the two ways to give it one. Null once a
  /// recipe is open.
  final DarkroomStartOffer? offer;

  /// True while one of the offer's two actions is running, so a second tap
  /// cannot create a second recipe over the same master.
  final bool offerBusy;

  /// Why the last offer action produced no recipe. Null when none has failed.
  final String? offerError;

  /// `recipes.id` of the open recipe, null while none is open.
  final int? recipeId;

  /// Operator-facing recipe (branch) label.
  final String recipeName;

  /// Absolute path of the linear master this recipe replays over.
  final String baseMasterPath;

  /// Who authored the step list as it stands.
  final RecipeAuthor author;

  /// `integrated_masters.id` the recipe was framed from, or null when the
  /// master was opened by path with no library row.
  final int? masterId;

  /// The edited op stack, in application order.
  final List<DarkroomStep> steps;

  /// The operation catalogue that drives the parameter controls. Null until the
  /// registry answers.
  final DarkroomCatalog? catalog;

  /// Why the catalogue is absent, in the engine's words. With no catalogue the
  /// step cards show what the recipe stores and say that the ranges behind the
  /// controls could not be read, rather than drawing controls over guessed
  /// bounds.
  final String? catalogError;

  /// The most recent render's pixels, or null before the first one lands.
  final DarkroomPreviewImage? preview;

  /// One entry per step the last render covered.
  final List<DarkroomStepReport> reports;

  /// The [DarkroomStep.identity] of every step the last render was ASKED
  /// about, in the order the engine indexed them.
  ///
  /// A report line names an index into the list the engine was handed, which
  /// is not the position of that step in the stack the operator is now looking
  /// at: a step can be inserted in front of it, and a step the render was not
  /// asked about is not in the engine's list at all. [reportFor] joins through
  /// this list, so an outcome only ever reaches the card of the step the engine
  /// actually produced it for.
  final List<Object> reportedSteps;

  /// One entry per step from the last `validate` call.
  final List<DarkroomStepIssue> issues;

  /// The step identities [issues] index, in the order they were validated.
  final List<Object> issuedSteps;

  /// The identities of the steps the last render was NOT asked about, because
  /// they are switched off and this build cannot run them.
  ///
  /// The engine validates the whole recipe before it touches a pixel, so one
  /// unregistered step refuses the render whether or not it would have been
  /// applied. A step that is switched off contributes nothing to the picture,
  /// so it is left out of the render request instead of stopping it — and the
  /// card says so rather than the operator having to infer it.
  final List<Object> omittedFromRender;

  /// The engine's verdict on the recipe as a whole, null when it validates.
  final String? recipeError;

  /// True while a render is in flight.
  final bool rendering;

  /// True once cancellation has been asked for and before the render answers.
  final bool cancelRequested;

  /// Why the last render failed, in the engine's words. Null when the last
  /// render succeeded or was cancelled (a cancellation is not a failure).
  final String? renderError;

  /// The phase the last cancelled render stopped in, so the screen can say what
  /// the operator's stop actually interrupted. Null when nothing was cancelled.
  final String? cancelledPhase;

  /// Why the last reorder was refused, in the engine's words. Null when the
  /// last reorder was accepted or none has been attempted.
  final String? reorderRefusal;

  /// Why the field carries no catalogue photometry, when it does not. The
  /// color calibration is skipped with the engine's own reason in that case;
  /// this states the app-side half of the same fact.
  final String? photometryNote;

  /// Number of catalogue stars lent to `color_calibrate`.
  final int photometryStarCount;

  /// True when an earlier step list can be restored.
  final bool canUndo;

  /// True when an undone step list can be re-applied.
  final bool canRedo;

  /// True while an edit is waiting to be written to the recipe row.
  final bool savePending;

  /// Why the last write to the recipe row failed. Null when the row is current.
  final String? saveError;

  const DarkroomState({
    this.loading = true,
    this.loadError,
    this.offer,
    this.offerBusy = false,
    this.offerError,
    this.recipeId,
    this.recipeName = '',
    this.baseMasterPath = '',
    this.author = RecipeAuthor.user,
    this.masterId,
    this.steps = const [],
    this.catalog,
    this.catalogError,
    this.preview,
    this.reports = const [],
    this.reportedSteps = const [],
    this.issues = const [],
    this.issuedSteps = const [],
    this.omittedFromRender = const [],
    this.recipeError,
    this.rendering = false,
    this.cancelRequested = false,
    this.renderError,
    this.cancelledPhase,
    this.reorderRefusal,
    this.photometryNote,
    this.photometryStarCount = 0,
    this.canUndo = false,
    this.canRedo = false,
    this.savePending = false,
    this.saveError,
  });

  /// True when a recipe is open and editable.
  bool get hasRecipe => recipeId != null;

  /// True when every step is disabled — the state "Reset to linear" leaves
  /// behind, with every step and its parameters intact.
  bool get isLinear => steps.isNotEmpty && steps.every((s) => !s.enabled);

  /// True when the stack carries a color calibration.
  ///
  /// The catalogue photometry is lent to that one operation and to no other, so
  /// it is the only step whose absence of catalogue stars is worth stating. A
  /// stack without it has nothing the missing catalogue would have changed.
  bool get hasColorCalibrateStep =>
      steps.any((step) => step.opId == kDarkroomColorCalibrateOpId);

  /// The render report for the step at [index], or null when the last render
  /// carried no line for that step.
  ///
  /// Joined on [DarkroomStep.identity], never on list position: an outcome the
  /// engine produced for one step must never be read onto the step that later
  /// took its index.
  DarkroomStepReport? reportFor(int index) =>
      _joinByIdentity(index, reports, reportedSteps, (r) => r.index);

  /// The validation verdict for the step at [index], or null when the last
  /// `validate` carried no entry for that step. Joined on identity, as
  /// [reportFor] is.
  DarkroomStepIssue? issueFor(int index) =>
      _joinByIdentity(index, issues, issuedSteps, (i) => i.index);

  T? _joinByIdentity<T>(
    int index,
    List<T> entries,
    List<Object> describes,
    int Function(T entry) indexOf,
  ) {
    if (index < 0 || index >= steps.length) return null;
    final identity = steps[index].identity;
    for (final entry in entries) {
      final at = indexOf(entry);
      if (at < 0 || at >= describes.length) continue;
      if (identical(describes[at], identity)) return entry;
    }
    return null;
  }

  /// True when the step at [index] was left out of the last render request
  /// because it is switched off and this build cannot run it.
  bool isOmittedFromRender(int index) {
    if (index < 0 || index >= steps.length) return false;
    final identity = steps[index].identity;
    for (final omitted in omittedFromRender) {
      if (identical(omitted, identity)) return true;
    }
    return false;
  }

  /// The engine's whole-stack refusal, or null when the stack renders.
  ///
  /// The engine refuses a recipe on its FIRST bad step, switched on or off, so
  /// its sentence alone would tell an operator who has already switched that
  /// step off that the stack still cannot run — which is untrue, because the
  /// render is asked without it. The refusal therefore stands only when a step
  /// the render will actually replay is the one at fault, or when the engine
  /// named a fault the per-step diagnosis does not attribute to any step (a
  /// stage-ordering rule, the schema version, the branch link) and which
  /// switching a step off cannot answer.
  String? get blockingRecipeError {
    final error = recipeError;
    if (error == null) return null;
    var attributed = false;
    for (var index = 0; index < steps.length; index++) {
      final issue = issueFor(index);
      if (issue == null || issue.isClean) continue;
      attributed = true;
      if (steps[index].enabled) return error;
    }
    return attributed ? null : error;
  }

  DarkroomState copyWith({
    bool? loading,
    String? loadError,
    bool clearLoadError = false,
    DarkroomStartOffer? offer,
    bool clearOffer = false,
    bool? offerBusy,
    String? offerError,
    bool clearOfferError = false,
    int? recipeId,
    String? recipeName,
    String? baseMasterPath,
    RecipeAuthor? author,
    int? masterId,
    List<DarkroomStep>? steps,
    DarkroomCatalog? catalog,
    String? catalogError,
    DarkroomPreviewImage? preview,
    List<DarkroomStepReport>? reports,
    List<Object>? reportedSteps,
    List<DarkroomStepIssue>? issues,
    List<Object>? issuedSteps,
    List<Object>? omittedFromRender,
    String? recipeError,
    bool clearRecipeError = false,
    bool? rendering,
    bool? cancelRequested,
    String? renderError,
    bool clearRenderError = false,
    String? cancelledPhase,
    bool clearCancelledPhase = false,
    String? reorderRefusal,
    bool clearReorderRefusal = false,
    String? photometryNote,
    int? photometryStarCount,
    bool? canUndo,
    bool? canRedo,
    bool? savePending,
    String? saveError,
    bool clearSaveError = false,
  }) {
    return DarkroomState(
      loading: loading ?? this.loading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      offer: clearOffer ? null : (offer ?? this.offer),
      offerBusy: offerBusy ?? this.offerBusy,
      offerError: clearOfferError ? null : (offerError ?? this.offerError),
      recipeId: recipeId ?? this.recipeId,
      recipeName: recipeName ?? this.recipeName,
      baseMasterPath: baseMasterPath ?? this.baseMasterPath,
      author: author ?? this.author,
      masterId: masterId ?? this.masterId,
      steps: steps ?? this.steps,
      catalog: catalog ?? this.catalog,
      catalogError: catalogError ?? this.catalogError,
      preview: preview ?? this.preview,
      reports: reports ?? this.reports,
      reportedSteps: reportedSteps ?? this.reportedSteps,
      issues: issues ?? this.issues,
      issuedSteps: issuedSteps ?? this.issuedSteps,
      omittedFromRender: omittedFromRender ?? this.omittedFromRender,
      recipeError: clearRecipeError ? null : (recipeError ?? this.recipeError),
      rendering: rendering ?? this.rendering,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      renderError: clearRenderError ? null : (renderError ?? this.renderError),
      cancelledPhase:
          clearCancelledPhase ? null : (cancelledPhase ?? this.cancelledPhase),
      reorderRefusal:
          clearReorderRefusal ? null : (reorderRefusal ?? this.reorderRefusal),
      photometryNote: photometryNote ?? this.photometryNote,
      photometryStarCount: photometryStarCount ?? this.photometryStarCount,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      savePending: savePending ?? this.savePending,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}
