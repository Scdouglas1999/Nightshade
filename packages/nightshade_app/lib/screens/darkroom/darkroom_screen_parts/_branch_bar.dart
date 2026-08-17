part of '../darkroom_screen.dart';

/// The branch switcher: every recipe written over this master, which one is
/// open, and the actions that change the set.
///
/// The bar is deliberately above the panel layout rather than inside a panel:
/// switching branches changes what BOTH the viewport and the history stack
/// describe, so it cannot live inside either of them.
///
/// Three separate statements, never folded into one:
///
///  * who wrote a branch — an autopilot draft is a first interpretation, a user
///    recipe is a decision;
///  * where a branch diverged — the step of its parent it stopped matching;
///  * why a delete was refused — named branches, not a greyed-out button.
class _DarkroomBranchBar extends ConsumerStatefulWidget {
  /// The family this bar draws, and the recipe inside it that is open.
  final DarkroomBranchScope scope;

  /// The open recipe's row id.
  final int recipeId;

  /// `integrated_masters.id` the open recipe was framed from, when it carries
  /// one. Deleting the last recipe over a master goes back to it, which is what
  /// offers a fresh start; a recipe with no library row has nowhere to go and
  /// the screen is left to report the empty family instead.
  final int? masterId;

  /// The recipe the compare pane is showing beside the open one, or null when
  /// compare is off.
  final int? compareRecipeId;

  /// How the compare pane draws its two sides.
  final _DarkroomCompareMode compareMode;

  /// Switch the compare pane on against [recipeId], or off when null.
  final void Function(int? recipeId) onCompareWith;

  /// Change how the compare pane draws its two sides.
  final ValueChanged<_DarkroomCompareMode> onCompareModeChanged;

  /// Open the export sheet for the open recipe.
  final VoidCallback onExport;

  const _DarkroomBranchBar({
    required this.scope,
    required this.recipeId,
    required this.masterId,
    required this.compareRecipeId,
    required this.compareMode,
    required this.onCompareWith,
    required this.onCompareModeChanged,
    required this.onExport,
  });

  @override
  ConsumerState<_DarkroomBranchBar> createState() => _DarkroomBranchBarState();
}

class _DarkroomBranchBarState extends ConsumerState<_DarkroomBranchBar> {
  DarkroomBranchController get _branches =>
      ref.read(darkroomBranchControllerProvider(widget.scope).notifier);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(darkroomBranchControllerProvider(widget.scope));

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chips(colors, state),
          if (state.lineage.length > 1) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            _lineage(colors, state),
          ],
          if (state.lineageError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.warning,
              message: state.lineageError!,
              compact: true,
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceSm),
          _actions(state),
          if (state.loadError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.error,
              message: state.loadError!,
              compact: true,
            ),
          ],
          if (state.actionError != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.error,
              message: state.actionError!,
              compact: true,
            ),
          ],
          if (state.deleteRefusal != null) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            _refusal(state.deleteRefusal!),
          ],
        ],
      ),
    );
  }

  /// One chip per recipe over this master.
  ///
  /// Horizontally scrollable rather than wrapped: a long family would otherwise
  /// push the viewport down the screen a row at a time.
  Widget _chips(NightshadeColors colors, DarkroomBranchState state) {
    if (state.loading) {
      return Text(
        'Reading the branches written over this master…',
        style: NightshadeTypography.captionSm.copyWith(
          color: colors.textMuted,
        ),
      );
    }
    if (state.branches.isEmpty) {
      return Text(
        'This is the only recipe over this master.',
        style: NightshadeTypography.captionSm.copyWith(
          color: colors.textMuted,
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final branch in state.branches) ...[
            _branchChip(colors, branch),
            const SizedBox(width: NightshadeTokens.spaceXs),
          ],
        ],
      ),
    );
  }

  Widget _branchChip(NightshadeColors colors, DarkroomBranch branch) {
    final current = branch.id == widget.recipeId;
    final comparing = branch.id == widget.compareRecipeId;
    final author = branch.author == RecipeAuthor.autopilot
        ? 'drafted by the autopilot'
        : 'written by you';
    final steps = branch.stepCount == null
        ? 'its stored step list could not be read'
        : '${branch.stepCount} step${branch.stepCount == 1 ? '' : 's'}';
    final diverged = branch.divergenceIndex == null
        ? 'a root recipe'
        : 'diverges from recipe ${branch.parentRecipeId} after step '
            '${branch.divergenceIndex}';
    return Tooltip(
      message: '${branch.label} — $author, $steps, $diverged.'
          '${comparing ? ' Shown as B in the compare pane.' : ''}',
      child: Semantics(
        button: true,
        selected: current,
        child: NightshadeChip(
          label: comparing ? '${branch.label} (B)' : branch.label,
          icon: branch.author == RecipeAuthor.autopilot
              ? NightshadeIcons.sparkle
              : NightshadeIcons.user,
          selected: current,
          onTap: current
              ? null
              : () => context.go(darkroomRecipeLocation(branch.id)),
        ),
      ),
    );
  }

  /// The open recipe's ancestry, so a branch says where it came from.
  Widget _lineage(NightshadeColors colors, DarkroomBranchState state) {
    final parts = <String>[];
    for (final entry in state.lineage) {
      parts.add(
        entry.divergenceIndex == null
            ? entry.label
            : '${entry.label} (from step ${entry.divergenceIndex})',
      );
    }
    return Text(
      'Lineage: ${parts.join(' → ')}',
      style: NightshadeTypography.captionSm.copyWith(color: colors.textMuted),
    );
  }

  Widget _actions(DarkroomBranchState state) {
    final compareTargets = state.branches
        .where((branch) => branch.id != widget.recipeId)
        .toList(growable: false);
    final comparing = widget.compareRecipeId != null;

    return Wrap(
      spacing: NightshadeTokens.spaceXs,
      runSpacing: NightshadeTokens.spaceXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NightshadeButton(
          label: 'Duplicate as variant',
          icon: NightshadeIcons.copy,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: state.busy ? null : _promptDuplicate,
        ),
        NightshadeButton(
          label: 'Rename',
          icon: NightshadeIcons.edit,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: state.busy ? null : _promptRename,
        ),
        NightshadeButton(
          label: 'Delete branch',
          icon: NightshadeIcons.delete,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: state.busy ? null : _promptDelete,
        ),
        if (comparing)
          NightshadeButton(
            label: 'Stop comparing',
            icon: NightshadeIcons.close,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => widget.onCompareWith(null),
          )
        else if (compareTargets.isEmpty)
          const Tooltip(
            message: 'A compare needs a second recipe over these same pixels. '
                'Duplicate this one as a variant to make one.',
            child: NightshadeButton(
              label: 'Compare',
              icon: NightshadeIcons.layers,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: null,
            ),
          )
        else
          NightshadeButton(
            label: 'Compare with…',
            icon: NightshadeIcons.layers,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => _promptCompare(compareTargets),
          ),
        if (comparing) ...[
          NightshadeChip(
            label: 'Side by side',
            selected: widget.compareMode == _DarkroomCompareMode.sideBySide,
            onTap: () => widget.onCompareModeChanged(
              _DarkroomCompareMode.sideBySide,
            ),
          ),
          NightshadeChip(
            label: 'Blink',
            selected: widget.compareMode == _DarkroomCompareMode.blink,
            onTap: () =>
                widget.onCompareModeChanged(_DarkroomCompareMode.blink),
          ),
        ],
        NightshadeButton(
          label: 'Export…',
          icon: NightshadeIcons.download,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: widget.onExport,
        ),
      ],
    );
  }

  Widget _refusal(DarkroomBranchDeleteRefusal refusal) {
    return NightshadeAlert(
      severity: NightshadeAlertSeverity.warning,
      title: 'That branch has branches of its own',
      message: refusal.explanation,
      compact: true,
      action: Wrap(
        spacing: NightshadeTokens.spaceXs,
        runSpacing: NightshadeTokens.spaceXs,
        children: [
          NightshadeButton(
            label: 'Delete "${refusal.label}" and its '
                '${refusal.childIds.length} '
                '${refusal.childIds.length == 1 ? 'branch' : 'branches'}',
            icon: NightshadeIcons.delete,
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => _deleteLine(refusal),
          ),
          NightshadeButton(
            label: 'Keep them',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: _branches.dismissRefusal,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  Future<void> _promptDuplicate() async {
    final state = ref.read(darkroomBranchControllerProvider(widget.scope));
    final current = state.branchFor(widget.recipeId);
    final suggested =
        '${current?.label ?? 'Recipe ${widget.recipeId}'} variant';
    final name = await _promptForName(
      title: 'Duplicate as variant',
      body:
          'A variant is a second recipe over the same linear master. It starts '
          'as a copy of this stack and records that it branched from it, so '
          'editing the variant never touches this one.',
      initial: suggested,
      confirmLabel: 'Create variant',
    );
    if (name == null) return;
    final id = await _branches.duplicateAsVariant(
      sourceRecipeId: widget.recipeId,
      name: name,
    );
    if (id == null || !mounted) return;
    _branches.acknowledgeCreatedBranch();
    if (!context.mounted) return;
    context.go(darkroomRecipeLocation(id));
  }

  Future<void> _promptRename() async {
    final state = ref.read(darkroomBranchControllerProvider(widget.scope));
    final current = state.branchFor(widget.recipeId);
    if (current == null) {
      // A blank rename field would propose erasing a name that has not been
      // loaded; refuse until the branch list is read.
      NightshadeToastHelper.show(
        context: context,
        message:
            'The branches over this master have not been read yet, so this '
            'recipe\'s current name is unknown. Reload and try again.',
        severity: NightshadeAlertSeverity.warning,
      );
      return;
    }
    final name = await _promptForName(
      title: 'Rename this branch',
      body:
          'The name is the label on the branch bar. It says nothing about the '
          'stack, so renaming changes no step and re-renders nothing.',
      initial: current.label,
      confirmLabel: 'Rename',
    );
    if (name == null) return;
    await _branches.renameBranch(widget.recipeId, name);
  }

  Future<void> _promptDelete() async {
    final state = ref.read(darkroomBranchControllerProvider(widget.scope));
    final current = state.branchFor(widget.recipeId);
    final label = current?.label ?? 'Recipe ${widget.recipeId}';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => NightshadeDialog(
        title: 'Delete "$label"?',
        icon: NightshadeIcons.delete,
        width: 480,
        actions: [
          NightshadeButton(
            label: 'Keep it',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          NightshadeButton(
            label: 'Delete',
            icon: NightshadeIcons.delete,
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Text(
          'The recipe row goes; the linear master it renders does not. Nothing '
          'in the Darkroom has ever written to those pixels, so deleting this '
          'branch loses only the interpretation.',
          style: NightshadeTypography.bodySm.copyWith(
            color: NightshadeColors.of(dialogContext).textSecondary,
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    final before = ref.read(darkroomBranchControllerProvider(widget.scope));
    final parentId = before.branchFor(widget.recipeId)?.parentRecipeId;
    final deleted = await _branches.deleteBranch(widget.recipeId);
    if (!deleted || !mounted || !context.mounted) return;
    // The open recipe is gone, so the screen cannot stay on it: go to the
    // branch it came from, or to the master, which offers a fresh start.
    final after = ref.read(darkroomBranchControllerProvider(widget.scope));
    final fallback = parentId ?? _firstBranchId(after);
    if (fallback != null) {
      context.go(darkroomRecipeLocation(fallback));
      return;
    }
    final masterId = widget.masterId;
    if (masterId != null) context.go(darkroomMasterLocation(masterId));
  }

  /// The id of the first recipe still in the family, or null when none is left.
  static int? _firstBranchId(DarkroomBranchState state) =>
      state.branches.isEmpty ? null : state.branches.first.id;

  Future<void> _deleteLine(DarkroomBranchDeleteRefusal refusal) async {
    final deleted = await _branches.deleteBranchLine(refusal.recipeId);
    if (deleted == null || !mounted || !context.mounted) return;
    NightshadeToastHelper.show(
      context: context,
      message: '$deleted recipe${deleted == 1 ? '' : 's'} deleted. The linear '
          'master is untouched.',
      severity: NightshadeAlertSeverity.success,
    );
    final after = ref.read(darkroomBranchControllerProvider(widget.scope));
    final fallback = _firstBranchId(after);
    if (fallback != null && context.mounted) {
      context.go(darkroomRecipeLocation(fallback));
    }
  }

  Future<void> _promptCompare(List<DarkroomBranch> targets) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final colors = NightshadeColors.of(dialogContext);
        return NightshadeDialog(
          title: 'Compare with',
          icon: NightshadeIcons.layers,
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Both sides render the same linear master, so what differs on '
                'screen is the interpretation and nothing else. Zoom and pan '
                'stay locked together.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              for (final branch in targets)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: NightshadeTokens.spaceSm,
                  ),
                  child: NightshadeButton(
                    label: branch.author == RecipeAuthor.autopilot
                        ? '${branch.label} — the autopilot draft'
                        : branch.label,
                    icon: branch.author == RecipeAuthor.autopilot
                        ? NightshadeIcons.sparkle
                        : NightshadeIcons.user,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () => Navigator.of(dialogContext).pop(branch.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return;
    widget.onCompareWith(chosen);
  }

  /// A one-field dialog for a branch name.
  ///
  /// Answers null when the operator backed out, and the trimmed text otherwise;
  /// an empty field cannot be confirmed, so a branch never loses its label to a
  /// stray return key.
  Future<String?> _promptForName({
    required String title,
    required String body,
    required String initial,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DarkroomNameDialog(
        title: title,
        body: body,
        initial: initial,
        confirmLabel: confirmLabel,
      ),
    );
  }
}

/// The name field behind "duplicate as variant" and "rename".
///
/// A widget with its own state rather than a `StatefulBuilder` over a captured
/// controller: the dialog route keeps rebuilding through its exit transition,
/// and a controller disposed when the future completed would be read after
/// disposal on the way out.
class _DarkroomNameDialog extends StatefulWidget {
  final String title;
  final String body;
  final String initial;
  final String confirmLabel;

  const _DarkroomNameDialog({
    required this.title,
    required this.body,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_DarkroomNameDialog> createState() => _DarkroomNameDialogState();
}

class _DarkroomNameDialogState extends State<_DarkroomNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final text = _controller.text.trim();
    return NightshadeDialog(
      title: widget.title,
      icon: NightshadeIcons.edit,
      width: 480,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: widget.confirmLabel,
          size: ButtonSize.small,
          onPressed: text.isEmpty ? null : _confirm,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.body,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeTextField(
            controller: _controller,
            label: 'Branch name',
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
            errorText: text.isEmpty
                ? 'A branch needs a name to be told apart from the others on '
                    'the bar.'
                : null,
          ),
        ],
      ),
    );
  }
}
