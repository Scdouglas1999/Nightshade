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
import 'dart:developer' as developer;
import 'dart:io' show Directory;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../../utils/darkroom_navigation.dart';
import '../../utils/exported_file_reveal.dart';
import '../stack_result/stack_and_share_dialog.dart'
    show describeStackShareFailure;
import 'darkroom_branch_controller.dart';
import 'darkroom_controller.dart';

part 'darkroom_screen_parts/_image_surface.dart';
part 'darkroom_screen_parts/_viewport.dart';
part 'darkroom_screen_parts/_history_panel.dart';
part 'darkroom_screen_parts/_add_step.dart';
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
  /// The attempt number of the refusal this screen has already announced, so a
  /// rebuild does not toast the same occurrence twice. Zero when there is none.
  ///
  /// The attempt, not the sentence: two refusals of the same move for the same
  /// reason are byte-identical, and deduping on the string swallowed the second
  /// one. The controller stamps each refusal with the attempt that raised it.
  int _lastShownRefusal = 0;
  int _lastShownInsertRefusal = 0;
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
      _lastShownRefusal = 0;
      _lastShownInsertRefusal = 0;
      _lastShownSaveError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    if (ref.watch(isRemoteClientProvider)) {
      // The Darkroom renders a linear master FITS through the native recipe
      // engine, and both the file and the engine live on the imaging host. A
      // remote client has neither, so there is nothing here it could render —
      // and a client-local recipe row would be a second, divergent history of
      // a master it cannot see.
      //
      // Gated on the client ROLE, not on the connection, exactly as Delivery
      // settings is. A desktop launched with `--remote-host` that has not
      // reached its rig yet has a `Disconnected` backend, not a
      // `NetworkBackend`: `backend is NetworkBackend` read false for the whole
      // pre-handshake window and after every drop, so the full editor opened
      // over the client's OWN database — recipes no dawn job on the rig will
      // ever read — while Delivery on the same launch correctly refused.
      //
      // Reached by deep link now that every in-app control refuses first, so it
      // is a screen an operator lands on with no route in mind — which is why
      // it takes the same shell as the editor. Returning its own Scaffold here
      // put it OUTSIDE the shortcuts and the header actions below: no Back, no
      // action on the empty state, and Escape and Alt+Left both dead, on the
      // one branch whose whole job is to send the operator somewhere else.
      return _shell(
        colors: colors,
        title: 'Darkroom',
        subtitle: 'Host-only processing',
        trailing: _backControl(savePending: false),
        body: EmptyState(
          icon: NightshadeIcons.device,
          title: 'Open the Darkroom on the imaging host',
          body: 'Linear masters and the recipe engine that renders them live '
              'on the imaging computer. Open Nightshade there to adjust, '
              'reorder, or export a recipe. Remote Darkroom editing is '
              'unavailable in this release.',
          action: NightshadeButton(
            key: const ValueKey('darkroom_remote_gate_back'),
            label: 'Go back',
            icon: NightshadeIcons.arrowLeft,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: _leave,
          ),
        ),
      );
    }

    final state = ref.watch(darkroomControllerProvider(widget.scope));

    // A refused reorder and a failed write are both things the operator did
    // that did not take effect, so each is announced once per OCCURRENCE — the
    // attempt the controller stamped on it, not the words it carries. Deduping
    // on the words made a second press of the same enabled control, refused for
    // the same reason, produce nothing at all: the sentence matched the one
    // already shown, so the toast was suppressed and the operator's second
    // attempt went unacknowledged.
    if (state.reorderRefusal == null) {
      _lastShownRefusal = 0;
    } else if (state.reorderRefusalAttempt != _lastShownRefusal) {
      _lastShownRefusal = state.reorderRefusalAttempt;
      _toast(state.reorderRefusal!, NightshadeAlertSeverity.warning);
    }
    // Announced as well as printed, for the same reason: the chooser closes on
    // the choice, so a refused insert leaves a stack that looks untouched and
    // an alert one panel away from where the operator was looking.
    if (state.insertRefusal == null) {
      _lastShownInsertRefusal = 0;
    } else if (state.insertRefusalAttempt != _lastShownInsertRefusal) {
      _lastShownInsertRefusal = state.insertRefusalAttempt;
      _toast(state.insertRefusal!, NightshadeAlertSeverity.warning);
    }
    if (state.saveError == null) {
      _lastShownSaveError = null;
    } else if (state.saveError != _lastShownSaveError) {
      _lastShownSaveError = state.saveError;
      _toast(state.saveError!, NightshadeAlertSeverity.error);
    }

    return _shell(
      colors: colors,
      title: state.hasRecipe ? state.recipeName : 'Darkroom',
      subtitle: _subtitle(state),
      trailing: _headerActions(state),
      body: _body(context, colors, state),
    );
  }

  /// The screen every branch of this route renders inside.
  ///
  /// The Darkroom is a PUSHED route with no destination of its own on the nav
  /// rail: the rail keeps highlighting whatever the operator came from, and
  /// until this binding existed the only way out was to press a different rail
  /// destination — Escape and Alt+Left both did nothing at all, which reads as
  /// a broken window rather than as a screen with no back. The rail's claim
  /// becomes true once leaving returns to what it is pointing at.
  ///
  /// Every branch, because a branch that opted out of the shell opted out of
  /// the whole way-out contract at the same time.
  Widget _shell({
    required NightshadeColors colors,
    required String title,
    required String subtitle,
    required Widget trailing,
    required Widget body,
  }) {
    return Scaffold(
      backgroundColor: colors.background,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _leave,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              _leave,
        },
        child: Focus(
          autofocus: true,
          // Publishing this node annotates the whole screen as a focusable
          // control with no enabled state, which the AT-SPI bridge reports as a
          // disabled button wrapping the editor — the same trap the export
          // sheet's own Escape host documents.
          includeSemantics: false,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ScreenHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: NightshadeIcons.palette,
                  trailing: trailing,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Leave the Darkroom the way it was entered.
  ///
  /// Popping is what a pushed route deserves: it returns to the screen the nav
  /// rail is still highlighting. A Darkroom reached by a deep link has nothing
  /// to pop to, and goes to the session review — the same destination the
  /// screen's own empty state offers, because that is the surface that lists
  /// the masters there are pixels for.
  ///
  /// Nothing is refused and nothing is lost on the way out. A render inside the
  /// engine is asked to stop by the controller's own dispose, and a debounced
  /// edit that has not reached the recipe row is issued there too; the back
  /// control says which of those is happening rather than blocking on it.
  void _leave() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    context.go('/analytics?tab=history');
  }

  /// The way out, in the header.
  ///
  /// [savePending] is stated on the control itself, because it is the state
  /// that decides what leaving does: the pending write is issued by the
  /// controller's dispose, and an operator who cannot see that a write is
  /// outstanding has no way to know whether leaving costs them the edit. The
  /// host-only branch has no controller and therefore nothing outstanding.
  Widget _backControl({required bool savePending}) {
    final pending = savePending
        ? 'Back — this edit is still being written to the recipe, and leaving '
            'issues that write'
        : 'Back to where the Darkroom was opened from';
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: pending,
      excludeSemantics: true,
      onTap: _leave,
      child: Tooltip(
        message: '$pending. Escape and Alt+Left do the same.',
        child: NightshadeButton(
          label: 'Back',
          icon: NightshadeIcons.arrowLeft,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: _leave,
        ),
      ),
    );
  }

  /// The header's action slot: the way out, and the render control.
  Widget _headerActions(DarkroomState state) {
    final render = _headerAction(state);
    return Wrap(
      spacing: NightshadeTokens.spaceXs,
      runSpacing: NightshadeTokens.spaceXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _backControl(savePending: state.savePending),
        // The same boundary the Back control carries, for the same reason. The
        // `CallbackShortcuts` above publishes one focusable node over the whole
        // screen, and every unbounded fragment under it merges in — so in a
        // layout whose BODY offers no competing action, this one's tap and role
        // landed on the node holding the header's own words: the start offer
        // reached AT-SPI as a single button named "Darkroom / No recipe yet /
        // Reload", with the screen's title readable only as part of a control's
        // name. The editor layout escaped it purely because its body has
        // actions of its own to be incompatible with.
        if (render != null) Semantics(container: true, child: render),
      ],
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
      // The header's own action is suppressed here — there is no recipe to
      // reload — so this empty state is the whole screen. Without a way out of
      // it the only route back is the nav rail, and the reason it names (a
      // recipe or master that is gone) is one the session review can answer:
      // it lists the masters that DO have pixels to interpret.
      return EmptyState(
        icon: NightshadeIcons.imageOff,
        title: 'Nothing to open in the Darkroom',
        body: loadError,
        action: NightshadeButton(
          label: 'Back to session review',
          icon: NightshadeIcons.history,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => context.go('/analytics?tab=history'),
        ),
      );
    }
    final offer = state.offer;
    if (offer != null) {
      return _DarkroomStartOfferView(
        offer: offer,
        busy: state.offerBusy,
        error: state.offerError,
        siblings: state.siblings,
        siblingsError: state.siblingsError,
        onStartFromLinear: _controller.startFromLinear,
        onDraftForMe: _controller.draftForMe,
        onImportRecipe: () => unawaited(_controller.importRecipe()),
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
          editorScope: widget.scope,
          recipeId: state.recipeId!,
          masterId: state.masterId,
          compareRecipeId: _compareRecipeId,
          compareMode: _compareMode,
          onCompareWith: (id) => setState(() => _compareRecipeId = id),
          onCompareModeChanged: (mode) => setState(() => _compareMode = mode),
          onExport: () => _openExportSheet(state),
          siblings: state.siblings,
          siblingsError: state.siblingsError,
          onImportRecipe: () => unawaited(_controller.importRecipe()),
          importBusy: state.offerBusy,
        ),
        // The branch bar's `Import .nsrecipe` writes its refusals into
        // `offerError`, the same field the start offer's copy of that control
        // uses — and this layout has no offer, so until this alert existed
        // every refusal on this path (a file that is not JSON, a sidecar with
        // no steps, an unreadable path) was composed and then thrown away. A
        // chooser that closed and did nothing is indistinguishable from a
        // broken button, and the operator's recipe count silently did not move.
        if (state.offerError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NightshadeTokens.spaceMd,
              0,
              NightshadeTokens.spaceMd,
              NightshadeTokens.spaceSm,
            ),
            child: NightshadeAlert(
              key: const ValueKey('darkroom_import_refusal'),
              severity: NightshadeAlertSeverity.error,
              message: state.offerError!,
              compact: true,
              onDismiss: _controller.dismissOfferError,
            ),
          ),
        Expanded(child: _editorOrCompare(context, colors, state)),
      ],
    );
  }

  /// The editor, or the two-recipe compare when one is armed.
  ///
  /// Compare replaces the PRIMARY region and nothing else. It used to replace
  /// the whole panel layout, which took the Recipe and History panels off the
  /// screen and out of the accessibility tree — so the one thing an A/B compare
  /// is for, reading what differs between two interpretations, was reduced to
  /// two pictures with no way to see which steps differ, beside a picker whose
  /// own copy promises "what differs on screen is the interpretation". The
  /// panels are collapsible on every layout this screen takes, so keeping them
  /// costs the comparator nothing: a phone still segments, and a desktop panel
  /// still drags down to 280 pixels or across to give the two panes the width.
  Widget _editorOrCompare(
    BuildContext context,
    NightshadeColors colors,
    DarkroomState state,
  ) {
    final compareId = _compareRecipeId;
    final aLabel = state.recipeName.isEmpty
        ? 'Recipe ${state.recipeId}'
        : state.recipeName;
    Widget primary = _DarkroomViewport(
      state: state,
      onRerender: _controller.refreshRender,
    );
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
      primary = _DarkroomCompareView(
        aState: state,
        aLabel: aLabel,
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
      primarySegmentLabel: compareId == null ? 'Image' : 'A | B',
      primarySegmentIcon:
          compareId == null ? NightshadeIcons.image : NightshadeIcons.layers,
      initialPanelWidth: 360,
      minPanelWidth: 280,
      maxPanelWidth: 520,
      primary: primary,
      secondary: [
        AdaptivePanel(
          title: compareId == null ? 'Recipe' : 'Recipe · A',
          icon: NightshadeIcons.sliders,
          child: _compareOwner(
            colors,
            comparing: compareId != null,
            aLabel: aLabel,
            child: _DarkroomRecipePanel(
              state: state,
              onUndo: _controller.undo,
              onRedo: _controller.redo,
              onResetToLinear: _controller.resetToLinear,
              onRerender: _controller.refreshRender,
            ),
          ),
        ),
        AdaptivePanel(
          title: compareId == null ? 'History' : 'History · A',
          icon: NightshadeIcons.layers,
          child: _compareOwner(
            colors,
            comparing: compareId != null,
            aLabel: aLabel,
            child: _DarkroomHistoryPanel(
              state: state,
              onToggle: _controller.toggleStep,
              onParamChanged: _controller.setParam,
              onRemove: _controller.removeStep,
              onReorder: _controller.reorderStep,
              onInsert: _controller.insertStep,
            ),
          ),
        ),
      ],
    );
  }

  /// Name the branch a secondary panel is showing, while a compare is armed.
  ///
  /// Both panels render the A recipe — A is the open editor, B is rendered from
  /// its own row and is not editable here — and while comparing they said so
  /// nowhere. A stack of four steps sat beside two panes captioned "A · …" and
  /// "B · …" belonging, as far as anything on screen or in the accessibility
  /// tree went, to neither: the one question the compare exists to answer had
  /// an unlabelled answer.
  ///
  /// Labelled at this seam because the panel titles do not reach a desktop
  /// screen reader — [AdaptivePanelLayout] renders them only on the phone
  /// segments — so the sentence has to be inside the panel body to be read.
  Widget _compareOwner(
    NightshadeColors colors, {
    required bool comparing,
    required String aLabel,
    required Widget child,
  }) {
    if (!comparing) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('darkroom_compare_owner'),
          container: true,
          label: 'Showing pane A, $aLabel. These are pane A\'s steps; pane B '
              'renders its own recipe and is not edited here.',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // "Pane A · …", not the pane's own "A · …" caption: this
                  // strip is read beside that caption, and repeating it word
                  // for word would leave the two indistinguishable to anyone
                  // searching the screen for which one owns the stack.
                  'Pane A · $aLabel',
                  style: NightshadeTypography.labelStrongSm.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'B renders its own recipe and is not edited here.',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
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
    // What the viewport is showing, when what it is showing is that the base
    // master itself cannot be read. The export replays the stack over that same
    // file, so the sheet opens already knowing it cannot succeed.
    final renderError = state.renderError;
    final masterFailure = renderError != null &&
            darkroomMasterFailureNextStep(renderError, state.baseMasterPath) !=
                null
        ? renderError
        : null;
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
        baseMasterFailure: masterFailure,
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

  /// The other masters of the same night, so the offer says the night produced
  /// more than the one master this route resolved to.
  final List<DarkroomSiblingDraft> siblings;

  /// Why the night's other masters could not be listed.
  final String? siblingsError;

  final VoidCallback onStartFromLinear;
  final VoidCallback onDraftForMe;

  /// The third way to give a master a recipe: read one back out of a
  /// `.nsrecipe` sidecar an export wrote.
  final VoidCallback onImportRecipe;

  const _DarkroomStartOfferView({
    required this.offer,
    required this.busy,
    required this.error,
    required this.siblings,
    required this.siblingsError,
    required this.onStartFromLinear,
    required this.onDraftForMe,
    required this.onImportRecipe,
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
                'fit, denoise, ${offer.isColor ? 'a colour calibration' : ''
                    'no colour calibration, because the fit needs three '
                    'channels and this master has '
                    '${offer.channels}'}, and a stretch. Every step arrives '
                'adjustable, and the draft states anything else it left out '
                'and why.',
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
                'proposed and nothing is applied until you add a step — the '
                'History stack\'s "Add step" lists every operation this build '
                'registers, with the stage each one runs in.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              NightshadeButton(
                label: 'Import .nsrecipe',
                icon: NightshadeIcons.upload,
                variant: ButtonVariant.outline,
                onPressed: busy ? null : onImportRecipe,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'Read back the sidecar an export writes beside its file. The '
                'steps arrive exactly as the file stores them, checked against '
                'this build — an operation this build does not register is '
                'kept and its card says so, rather than being dropped on the '
                'way in.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              ..._siblingsBlock(context, colors),
            ],
          ),
        ),
      ),
    );
  }

  /// The night's other masters, stated here as well as on the branch bar.
  ///
  /// This view is where a night with four masters most often lands after a
  /// delete, and a master with no recipe carries no branch bar at all — so
  /// without this the offer is the one screen in the Darkroom that could not
  /// say the other three drafts exist.
  List<Widget> _siblingsBlock(
    BuildContext context,
    NightshadeColors colors,
  ) {
    final error = siblingsError;
    if (error != null) {
      return [
        const SizedBox(height: NightshadeTokens.spaceLg),
        NightshadeAlert(
          severity: NightshadeAlertSeverity.info,
          message: error,
          compact: true,
        ),
      ];
    }
    if (siblings.isEmpty) return const [];
    return [
      const SizedBox(height: NightshadeTokens.spaceLg),
      Text(
        'This night produced ${siblings.length + 1} masters. The others:',
        style: NightshadeTypography.captionSm.copyWith(color: colors.textMuted),
      ),
      const SizedBox(height: NightshadeTokens.spaceXs),
      Wrap(
        spacing: NightshadeTokens.spaceXs,
        runSpacing: NightshadeTokens.spaceXs,
        children: [
          for (final sibling in siblings)
            NightshadeChip(
              label: sibling.recipeId == null
                  ? '${sibling.label} — no recipe yet'
                  : sibling.label,
              icon: darkroomSiblingIcon(sibling),
              onTap: () => context.go(darkroomMasterLocation(sibling.masterId)),
            ),
        ],
      ),
    ];
  }
}
