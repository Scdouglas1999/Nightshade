/// The Darkroom editor: a linear master on the left, the recipe that
/// interprets it on the right.
///
/// The screen is one rendering of one [DarkroomController] state. Nothing here
/// touches pixels or the recipe engine directly — the controller owns the
/// render loop and every native call goes through `DarkroomSeam`, so this file
/// only decides what the operator sees and which controller method a gesture
/// calls.
///
/// Reached as `/darkroom?recipe=<id>` (a recipe by row id) or
/// `/darkroom?master=<id>` (a master, whose newest recipe opens — or, when it
/// has none, an offer to create one).
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../../utils/darkroom_navigation.dart';
import '../../utils/exported_file_reveal.dart';
import '../../widgets/astro_image_viewer.dart';
import '../stack_result/stack_and_share_dialog.dart'
    show describeStackShareFailure;
import 'darkroom_branch_controller.dart';
import 'darkroom_controller.dart';

part 'darkroom_screen_parts/_viewport.dart';
part 'darkroom_screen_parts/_history_panel.dart';
part 'darkroom_screen_parts/_recipe_panel.dart';
part 'darkroom_screen_parts/_branch_bar.dart';
part 'darkroom_screen_parts/_compare.dart';
part 'darkroom_screen_parts/_export_sheet.dart';

/// The Darkroom editor screen.
class DarkroomScreen extends ConsumerStatefulWidget {
  /// What the route asked to open.
  final DarkroomScope scope;

  const DarkroomScreen({super.key, required this.scope});

  @override
  ConsumerState<DarkroomScreen> createState() => _DarkroomScreenState();
}

class _DarkroomScreenState extends ConsumerState<DarkroomScreen> {
  String? _lastShownRefusal;
  String? _lastShownSaveError;

  /// The recipe the compare pane draws beside the open one, or null when the
  /// editor is showing one recipe.
  int? _compareRecipeId;

  _DarkroomCompareMode _compareMode = _DarkroomCompareMode.sideBySide;

  DarkroomController get _controller =>
      ref.read(darkroomControllerProvider(widget.scope).notifier);

  @override
  void didUpdateWidget(covariant DarkroomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope != oldWidget.scope) {
      // Switching branches replaces the A side, and the B side was chosen
      // against the recipe that is no longer open. Keeping it would leave a
      // compare whose labels describe a pairing the operator never asked for.
      _compareRecipeId = null;
      _lastShownRefusal = null;
      _lastShownSaveError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = ref.watch(backendProvider);
    if (backend is NetworkBackend) {
      // The Darkroom renders a linear master FITS through the native recipe
      // engine, and both the file and the engine live on the imaging host. A
      // remote client has neither, so there is nothing here it could render —
      // and a client-local recipe row would be a second, divergent history of
      // a master it cannot see.
      return Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          bottom: false,
          child: Column(
            children: [
              ScreenHeader(
                title: 'Darkroom',
                subtitle: 'Host-only processing',
                icon: NightshadeIcons.palette,
              ),
              Expanded(
                child: EmptyState(
                  icon: NightshadeIcons.device,
                  title: 'Open the Darkroom on the imaging host',
                  body:
                      'Linear masters and the recipe engine that renders them '
                      'live on the imaging computer. Open Nightshade there to '
                      'adjust, reorder, or export a recipe. Remote Darkroom '
                      'editing is unavailable in this release.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final state = ref.watch(darkroomControllerProvider(widget.scope));

    // A refused reorder and a failed write are both things the operator did
    // that did not take effect, so each is announced once per occurrence. The
    // dedupe resets when the message clears, so the same refusal on a second
    // attempt toasts again instead of going quiet.
    if (state.reorderRefusal == null) {
      _lastShownRefusal = null;
    } else if (state.reorderRefusal != _lastShownRefusal) {
      _lastShownRefusal = state.reorderRefusal;
      _toast(state.reorderRefusal!, NightshadeAlertSeverity.warning);
    }
    if (state.saveError == null) {
      _lastShownSaveError = null;
    } else if (state.saveError != _lastShownSaveError) {
      _lastShownSaveError = state.saveError;
      _toast(state.saveError!, NightshadeAlertSeverity.error);
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: state.hasRecipe ? state.recipeName : 'Darkroom',
              subtitle: _subtitle(state),
              icon: NightshadeIcons.palette,
              trailing: _headerAction(state),
            ),
            Expanded(child: _body(context, colors, state)),
          ],
        ),
      ),
    );
  }

  void _toast(String message, NightshadeAlertSeverity severity) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NightshadeToastHelper.show(
        context: context,
        message: message,
        severity: severity,
      );
    });
  }

  String _subtitle(DarkroomState state) {
    if (state.loading) return 'Loading…';
    if (state.loadError != null) return 'Nothing to open';
    if (state.offer != null) return 'No recipe yet';
    final enabled = state.steps.where((step) => step.enabled).length;
    final total = state.steps.length;
    final stack =
        total == 1 ? '1 step · $enabled on' : '$total steps · $enabled on';
    if (state.rendering) return '$stack · rendering…';
    if (state.savePending) return '$stack · saving…';
    return stack;
  }

  /// The header's single action slot.
  ///
  /// While a render is in the engine it becomes the stop, following the flat
  /// wizard: the stop is cooperative, so the button says "Stopping…" until the
  /// render answers rather than pretending the request was instant.
  Widget? _headerAction(DarkroomState state) {
    if (!state.hasRecipe && state.offer == null) return null;
    if (state.rendering) {
      return NightshadeButton(
        label: state.cancelRequested ? 'Stopping…' : 'Stop render',
        icon: NightshadeIcons.stop,
        variant: ButtonVariant.destructive,
        size: ButtonSize.small,
        onPressed: state.cancelRequested ? null : _controller.cancelRender,
      );
    }
    return NightshadeButton(
      label: 'Reload',
      icon: NightshadeIcons.refresh,
      variant: ButtonVariant.outline,
      size: ButtonSize.small,
      onPressed: _controller.refresh,
    );
  }

  Widget _body(
    BuildContext context,
    NightshadeColors colors,
    DarkroomState state,
  ) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final loadError = state.loadError;
    if (loadError != null) {
      return EmptyState(
        icon: NightshadeIcons.imageOff,
        title: 'Nothing to open in the Darkroom',
        body: loadError,
      );
    }
    final offer = state.offer;
    if (offer != null) {
      return _DarkroomStartOfferView(
        offer: offer,
        busy: state.offerBusy,
        error: state.offerError,
        onStartFromLinear: _controller.startFromLinear,
        onDraftForMe: _controller.draftForMe,
      );
    }

    // The branch bar sits above the panels because switching branches changes
    // what BOTH the viewport and the history stack describe.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DarkroomBranchBar(
          scope: DarkroomBranchScope(
            masterPath: state.baseMasterPath,
            recipeId: state.recipeId,
          ),
          recipeId: state.recipeId!,
          masterId: state.masterId,
          compareRecipeId: _compareRecipeId,
          compareMode: _compareMode,
          onCompareWith: (id) => setState(() => _compareRecipeId = id),
          onCompareModeChanged: (mode) => setState(() => _compareMode = mode),
          onExport: () => _openExportSheet(state),
        ),
        Expanded(child: _editorOrCompare(context, colors, state)),
      ],
    );
  }

  /// The editor, or the two-recipe compare when one is armed.
  Widget _editorOrCompare(
    BuildContext context,
    NightshadeColors colors,
    DarkroomState state,
  ) {
    final compareId = _compareRecipeId;
    if (compareId != null) {
      final branches = ref.watch(
        darkroomBranchControllerProvider(
          DarkroomBranchScope(
            masterPath: state.baseMasterPath,
            recipeId: state.recipeId,
          ),
        ),
      );
      final other = branches.branchFor(compareId);
      return _DarkroomCompareView(
        aState: state,
        aLabel: state.recipeName.isEmpty
            ? 'Recipe ${state.recipeId}'
            : state.recipeName,
        bRecipeId: compareId,
        bLabel: other?.label ?? 'Recipe $compareId',
        bIsAutopilotDraft: other?.author == RecipeAuthor.autopilot,
        mode: _compareMode,
      );
    }

    return AdaptivePanelLayout(
      // Segmented, not a bottom sheet: the history stack is a scrolling list of
      // cards with their own controls, and a peeking sheet would leave the
      // operator dragging a sheet up and down to reach a slider. On a phone the
      // three regions reflow into three full-width views instead.
      phoneStrategy: PhonePanelStrategy.segmented,
      primarySegmentLabel: 'Image',
      primarySegmentIcon: NightshadeIcons.image,
      initialPanelWidth: 360,
      minPanelWidth: 280,
      maxPanelWidth: 520,
      primary: _DarkroomViewport(
        state: state,
        onRerender: _controller.refreshRender,
      ),
      secondary: [
        AdaptivePanel(
          title: 'Recipe',
          icon: NightshadeIcons.sliders,
          child: _DarkroomRecipePanel(
            state: state,
            onUndo: _controller.undo,
            onRedo: _controller.redo,
            onResetToLinear: _controller.resetToLinear,
            onRerender: _controller.refreshRender,
          ),
        ),
        AdaptivePanel(
          title: 'History',
          icon: NightshadeIcons.layers,
          child: _DarkroomHistoryPanel(
            state: state,
            onToggle: _controller.toggleStep,
            onParamChanged: _controller.setParam,
            onReorder: _controller.reorderStep,
          ),
        ),
      ],
    );
  }

  /// Open the export sheet over the stack as it stands.
  ///
  /// The steps handed over are the EDITED ones, unsaved changes included, so
  /// the file matches the picture the operator is looking at rather than the
  /// last state that reached the recipe row.
  void _openExportSheet(DarkroomState state) {
    final recipeId = state.recipeId;
    if (recipeId == null) return;
    unawaited(
      _DarkroomExportSheet.show(
        context,
        recipeId: recipeId,
        recipeName:
            state.recipeName.isEmpty ? 'Recipe $recipeId' : state.recipeName,
        baseMasterPath: state.baseMasterPath,
        author: state.author,
        steps: state.steps,
        catalog: state.catalog,
        reports: state.reports,
        catalogStars: _controller.catalogStars,
      ),
    );
  }
}

/// The two ways to give a master its first recipe.
///
/// Both are offered rather than one being taken automatically: a draft is the
/// registry's interpretation of these pixels, and starting from the linear
/// master is the operator saying they want to make every call themselves.
class _DarkroomStartOfferView extends StatelessWidget {
  final DarkroomStartOffer offer;
  final bool busy;
  final String? error;
  final VoidCallback onStartFromLinear;
  final VoidCallback onDraftForMe;

  const _DarkroomStartOfferView({
    required this.offer,
    required this.busy,
    required this.error,
    required this.onStartFromLinear,
    required this.onDraftForMe,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final message = error;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmptyState(
                icon: NightshadeIcons.palette,
                title: '${offer.masterName} has no recipe yet',
                body: 'This linear master is ${offer.width}×${offer.height}, '
                    '${offer.channels} channel${offer.channels == 1 ? '' : 's'}. '
                    'Nothing interpretive has been applied to it. Choose where '
                    'to start — either way the master itself is untouched.',
              ),
              if (message != null) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                NightshadeAlert(
                  severity: NightshadeAlertSeverity.error,
                  message: message,
                ),
              ],
              const SizedBox(height: NightshadeTokens.spaceLg),
              NightshadeButton(
                label: 'Draft for me',
                icon: NightshadeIcons.sparkle,
                isLoading: busy,
                onPressed: busy ? null : onDraftForMe,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'The operation registry measures this master and proposes a '
                'first stack — a crop off the registration edge, a background '
                'fit, denoise, colour where there is colour to calibrate, and '
                'a stretch. Every step arrives adjustable.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              NightshadeButton(
                label: 'Start from linear',
                icon: NightshadeIcons.frame,
                variant: ButtonVariant.outline,
                onPressed: busy ? null : onStartFromLinear,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'An empty recipe over the master\'s own pixels. Nothing is '
                'proposed and nothing is applied until you add a step.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
