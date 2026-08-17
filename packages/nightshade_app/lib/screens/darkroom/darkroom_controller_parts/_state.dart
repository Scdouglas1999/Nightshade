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

  /// One entry per step from the last `validate` call.
  final List<DarkroomStepIssue> issues;

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
  /// colour calibration is skipped with the engine's own reason in that case;
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
    this.issues = const [],
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

  /// The render report for the step at [index], or null when the last render
  /// carried no line for it.
  DarkroomStepReport? reportFor(int index) {
    for (final report in reports) {
      if (report.index == index) return report;
    }
    return null;
  }

  /// The validation verdict for the step at [index], or null when the last
  /// `validate` carried no entry for it.
  DarkroomStepIssue? issueFor(int index) {
    for (final issue in issues) {
      if (issue.index == index) return issue;
    }
    return null;
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
    List<DarkroomStepIssue>? issues,
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
      issues: issues ?? this.issues,
      recipeError: clearRecipeError ? null : (recipeError ?? this.recipeError),
      rendering: rendering ?? this.rendering,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      renderError: clearRenderError ? null : (renderError ?? this.renderError),
      cancelledPhase: clearCancelledPhase
          ? null
          : (cancelledPhase ?? this.cancelledPhase),
      reorderRefusal: clearReorderRefusal
          ? null
          : (reorderRefusal ?? this.reorderRefusal),
      photometryNote: photometryNote ?? this.photometryNote,
      photometryStarCount: photometryStarCount ?? this.photometryStarCount,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      savePending: savePending ?? this.savePending,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}
