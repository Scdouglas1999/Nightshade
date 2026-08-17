part of '../darkroom_screen.dart';

/// What this recipe is, what the last render did with it, and the edits that
/// act on the stack as a whole.
///
/// The panel is taller than the slot it is given, so it scrolls — and a scroll
/// region whose only cue is a line sliced in half at the fold reads as a bug
/// rather than as an invitation. Its scrollbar is therefore always drawn, and
/// the one thing on the panel that reports something NOT happening — the
/// color calibration having no catalogue stars — is placed above the fold
/// instead of a scroll away.
class _DarkroomRecipePanel extends StatefulWidget {
  final DarkroomState state;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onResetToLinear;
  final Future<void> Function() onRerender;

  const _DarkroomRecipePanel({
    required this.state,
    required this.onUndo,
    required this.onRedo,
    required this.onResetToLinear,
    required this.onRerender,
  });

  @override
  State<_DarkroomRecipePanel> createState() => _DarkroomRecipePanelState();
}

class _DarkroomRecipePanelState extends State<_DarkroomRecipePanel> {
  /// Owned here because an always-visible scrollbar needs the controller its
  /// scroll view uses; there is no ambient one in a side panel.
  final ScrollController _scroll = ScrollController();

  DarkroomState get state => widget.state;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Recipe'),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                NightshadeTokens.spaceMd,
                NightshadeTokens.spaceMd,
                NightshadeTokens.spaceLg,
                NightshadeTokens.spaceLg,
              ),
              // Ordered by what has to be readable without scrolling: the
              // controls, then the account of the last render (its status and
              // the reason a step did NOT run). The base master and the two
              // paragraphs about it are reference — true, worth keeping, and
              // the right thing to put below the fold, since they were what
              // pushed the skip reason off the bottom of the card.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _editActions(colors),
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  _renderStatus(colors),
                  // Both halves of the photometry account — the stars there
                  // are, and the reason there are none — belong to one step. A
                  // stack that does not carry that step is not waiting on a
                  // catalogue for anything, so neither half is stated.
                  if (state.hasColorCalibrateStep &&
                      state.photometryStarCount > 0) ...[
                    const SizedBox(height: NightshadeTokens.spaceMd),
                    Text(
                      '${state.photometryStarCount} catalogue stars are lent '
                      'to the color calibration on every render. It solves '
                      'the balance from them each time rather than storing '
                      'fitted channel scales, so a coarse preview level can '
                      'detect too few stars and record the step as skipped.',
                      style: NightshadeTypography.captionSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  _identity(colors),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _identity(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: NightshadeTokens.spaceXs,
          runSpacing: NightshadeTokens.spaceXs,
          children: [
            _DarkroomTag(
              label: state.author == RecipeAuthor.autopilot
                  ? 'Drafted by the autopilot'
                  : 'Written by you',
              tooltip:
                  'Who authored the step list as it stands. An autopilot draft '
                  'is a first interpretation, not a finished decision.',
            ),
            if (state.isLinear)
              const _DarkroomTag(
                label: 'Linear',
                tooltip: 'Every step is switched off, so the viewport is the '
                    'master\'s own pixels. Nothing was destroyed — each step '
                    'and its parameters are intact.',
              ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          'Base master',
          style: NightshadeTypography.labelSm.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Tooltip(
          message: state.baseMasterPath,
          child: Text(
            state.baseMasterPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NightshadeTypography.monoSm.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Nothing in this screen writes to that file. Every step is stored as '
          'data and replayed over it.',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _editActions(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                label: 'Undo',
                icon: NightshadeIcons.undo,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: state.canUndo ? widget.onUndo : null,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: NightshadeButton(
                label: 'Redo',
                icon: NightshadeIcons.repeat,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: state.canRedo ? widget.onRedo : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeButton(
          label: 'Reset to linear',
          icon: NightshadeIcons.frame,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: state.steps.isEmpty || state.isLinear
              ? null
              : widget.onResetToLinear,
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Switches every step off. Nothing is deleted, and one undo brings '
          'the whole stack back.',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _renderStatus(NightshadeColors colors) {
    final children = <Widget>[
      Text(
        'Render',
        style: NightshadeTypography.labelSm.copyWith(
          color: colors.textSecondary,
        ),
      ),
      const SizedBox(height: NightshadeTokens.spaceXs),
    ];

    if (state.rendering) {
      children.add(
        NightshadeProgressBar(
          // The engine reports no fraction for a preview render, so the bar is
          // indeterminate rather than inventing progress.
          value: 0.0,
          indeterminate: true,
          style: NightshadeProgressStyle.standard,
          state: NightshadeProgressState.normal,
          label: state.cancelRequested
              ? 'Stopping at the next step boundary…'
              : 'Rendering the stack…',
        ),
      );
    } else {
      final error = state.renderError;
      final cancelled = state.cancelledPhase;
      if (error != null) {
        children.add(
          NightshadeAlert(
            severity: NightshadeAlertSeverity.error,
            title: 'The render did not finish',
            message: error,
            compact: true,
          ),
        );
      } else if (cancelled != null) {
        children.add(
          NightshadeAlert(
            severity: NightshadeAlertSeverity.info,
            message:
                'You stopped the render during $cancelled. The picture above '
                'is the one before it.',
            compact: true,
          ),
        );
      } else {
        children.add(
          Text(
            state.preview == null
                ? 'Nothing has been rendered yet.'
                : 'Up to date with the stack.',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        );
      }
      // Before the button, not after it: this is part of the account of what
      // the last render did, and every row it sits below is a row that can
      // push it past the fold of a fixed-height panel.
      //
      // It is stated only when the stack carries the step it is about. The
      // catalogue is lent to `color_calibrate` and to nothing else, so on a
      // stack without that step — an autopilot draft of a mono master, a recipe
      // with no steps at all — this alert reports the absence of something no
      // step was going to use, in the panel's most prominent slot.
      final photometryNote = state.photometryNote;
      if (photometryNote != null && state.hasColorCalibrateStep) {
        children
          ..add(const SizedBox(height: NightshadeTokens.spaceSm))
          ..add(
            NightshadeAlert(
              severity: NightshadeAlertSeverity.info,
              title: 'Color calibration has no catalogue stars',
              message: photometryNote,
              compact: true,
            ),
          );
      }
      children
        ..add(const SizedBox(height: NightshadeTokens.spaceSm))
        ..add(
          NightshadeButton(
            label: 'Render again',
            icon: NightshadeIcons.refresh,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => widget.onRerender(),
          ),
        );
    }

    if (state.savePending) {
      children
        ..add(const SizedBox(height: NightshadeTokens.spaceSm))
        ..add(
          Text(
            'Saving this edit to the recipe…',
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textMuted,
            ),
          ),
        );
    }
    final saveError = state.saveError;
    if (saveError != null) {
      children
        ..add(const SizedBox(height: NightshadeTokens.spaceSm))
        ..add(
          NightshadeAlert(
            severity: NightshadeAlertSeverity.error,
            message: saveError,
            compact: true,
          ),
        );
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
