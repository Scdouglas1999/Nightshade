part of '../darkroom_screen.dart';

/// What this recipe is, what the last render did with it, and the edits that
/// act on the stack as a whole.
class _DarkroomRecipePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Recipe'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identity(colors),
                const SizedBox(height: NightshadeTokens.spaceLg),
                _editActions(colors),
                const SizedBox(height: NightshadeTokens.spaceLg),
                _renderStatus(colors),
                if (state.photometryNote != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceMd),
                  NightshadeAlert(
                    severity: NightshadeAlertSeverity.info,
                    title: 'Colour calibration has no catalogue stars',
                    message: state.photometryNote!,
                    compact: true,
                  ),
                ],
                if (state.photometryStarCount > 0) ...[
                  const SizedBox(height: NightshadeTokens.spaceMd),
                  Text(
                    '${state.photometryStarCount} catalogue stars are lent to '
                    'the colour calibration on every render. It solves the '
                    'balance from them each time rather than storing fitted '
                    'channel scales, so a coarse preview level can detect too '
                    'few stars and record the step as skipped.',
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
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
                tooltip:
                    'Every step is switched off, so the viewport is the '
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
                onPressed: state.canUndo ? onUndo : null,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: NightshadeButton(
                label: 'Redo',
                icon: NightshadeIcons.repeat,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: state.canRedo ? onRedo : null,
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
              : onResetToLinear,
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
      children
        ..add(const SizedBox(height: NightshadeTokens.spaceSm))
        ..add(
          NightshadeButton(
            label: 'Render again',
            icon: NightshadeIcons.refresh,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => onRerender(),
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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
