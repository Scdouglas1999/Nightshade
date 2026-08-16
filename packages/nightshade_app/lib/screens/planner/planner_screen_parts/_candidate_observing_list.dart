// Observing-list dialog, rows, score badges and candidate chips.
part of '../planner_screen.dart';

/// Host-bound add/create flow for a Planner candidate.
///
/// Keeping the mutation inside the dialog means a failed host write does not
/// dismiss the only place that can explain and retry it. It also prevents a
/// numeric list ID selected on one remote host from being applied to another
/// host after the connection changes.
class _CandidateObservingListDialog extends ConsumerStatefulWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;

  const _CandidateObservingListDialog({
    required this.suggestion,
    required this.colors,
  });

  @override
  ConsumerState<_CandidateObservingListDialog> createState() =>
      _CandidateObservingListDialogState();
}

class _CandidateObservingListDialogState
    extends ConsumerState<_CandidateObservingListDialog> {
  late final TextEditingController _nameController;
  late final NightshadeBackend _authority;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  bool _creating = false;
  bool _saving = false;
  String? _error;

  /// Lists that already contain this target. Empty also means "not known yet /
  /// could not be determined", which is why membership only ever *annotates* a
  /// row — the add path still handles a duplicate gracefully on its own.
  Set<int> _listsContaining = const <int>{};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _authority = ref.read(backendProvider);
    _loadExistingMembership();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next) || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The connected host changed. Adding the target was cancelled.',
            ),
          ),
        );
        closeAuthorityBoundDialog(context);
      },
    );
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    _nameController.dispose();
    super.dispose();
  }

  bool get _isCurrentAuthority =>
      identical(ref.read(backendProvider), _authority);

  /// Mark the lists this target is already in, so the user is not invited to
  /// perform an add that can only be a no-op. Best-effort: a failure leaves
  /// the annotations off rather than blocking the dialog.
  Future<void> _loadExistingMembership() async {
    final catalogId = widget.suggestion.catalogId;
    if (catalogId == null) return;
    try {
      final lists = await ref
          .read(observingListNotifierProvider.notifier)
          .getListsContaining(catalogId);
      if (!mounted || !_isCurrentAuthority) return;
      setState(() {
        _listsContaining = lists.map((list) => list.id).toSet();
      });
    } catch (_) {
      // Membership is an affordance, not a gate — stay silent.
    }
  }

  Future<void> _addToList(int listId) async {
    if (_saving || !_isCurrentAuthority) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final id = await ref.read(observingListNotifierProvider.notifier).addItem(
          listId: listId,
          objectName: widget.suggestion.targetName,
          catalogId: widget.suggestion.catalogId,
          objectType: widget.suggestion.objectType,
          ra: widget.suggestion.raHours,
          dec: widget.suggestion.decDegrees,
          magnitude: widget.suggestion.magnitude,
          sizeArcmin: widget.suggestion.sizeArcmin,
        );
    if (!mounted || !_isCurrentAuthority) return;

    final uiState = ref.read(observingListNotifierProvider);
    if (id == null) {
      // No row was written. Two very different reasons, and they must not read
      // the same: a genuine write failure sets errorMessage, while "the target
      // is already in this list" sets only a neutral statusMessage — a harmless
      // no-op must not surface as a red Dart exception.
      final alreadyThere =
          uiState.errorMessage == null ? uiState.statusMessage : null;
      if (alreadyThere != null) {
        _showOutcomeAndClose(alreadyThere, success: false);
        return;
      }
      setState(() {
        _saving = false;
        _error =
            uiState.errorMessage ?? 'Could not add the target to this list';
      });
      return;
    }

    _showOutcomeAndClose(
      'Added ${widget.suggestion.targetName} to the list',
      success: true,
    );
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a list name');
      return;
    }
    if (_saving || !_isCurrentAuthority) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final id = await ref
        .read(observingListNotifierProvider.notifier)
        .createListWithItem(
          name: name,
          objectName: widget.suggestion.targetName,
          catalogId: widget.suggestion.catalogId,
          objectType: widget.suggestion.objectType,
          ra: widget.suggestion.raHours,
          dec: widget.suggestion.decDegrees,
          magnitude: widget.suggestion.magnitude,
          sizeArcmin: widget.suggestion.sizeArcmin,
        );
    if (!mounted || !_isCurrentAuthority) return;

    if (id == null) {
      setState(() {
        _saving = false;
        _error = ref.read(observingListNotifierProvider).errorMessage ??
            'Could not create the list and add this target';
      });
      return;
    }

    _showOutcomeAndClose(
      'Created "$name" and added ${widget.suggestion.targetName}',
      success: true,
    );
  }

  /// Close the dialog and report what actually happened. [success] only tints
  /// the toast green for a real write; a benign no-op (already in the list)
  /// gets the default neutral toast rather than a green "success" or a red
  /// "failure".
  void _showOutcomeAndClose(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? widget.colors.success : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(observingListsProvider);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: widget.colors.surface,
        title: Text(
          'Add to observing list',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: SizedBox(
          width: dialogMaxWidth(context, 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              listsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(NightshadeTokens.spaceMd),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (error, _) => Text(
                  'Could not load observing lists: $error',
                  style: TextStyle(color: widget.colors.error),
                ),
                data: (lists) => lists.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No observing lists yet. Create one to add this target.',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: widget.colors.textSecondary,
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: clampPanelWidth(
                            MediaQuery.sizeOf(context).height,
                            fraction: 0.35,
                            min: 120,
                            max: 280,
                          ),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final list in lists)
                              _ObservingListRow(
                                name: list.name,
                                colors: widget.colors,
                                alreadyContainsTarget:
                                    _listsContaining.contains(list.id),
                                onTap:
                                    _saving ? null : () => _addToList(list.id),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              if (_creating) ...[
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'New list name',
                    errorText: _error == 'Enter a list name' ? _error : null,
                  ),
                  onChanged: (_) {
                    if (_error == 'Enter a list name') {
                      setState(() => _error = null);
                    }
                  },
                  onSubmitted: (_) {
                    if (!_saving) _createAndAdd();
                  },
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                NightshadeButton(
                  label: _saving ? 'Creating…' : 'Create and add',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                  onPressed: _saving ? null : _createAndAdd,
                ),
              ] else
                NightshadeButton(
                  label: 'Create new list…',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _creating = true;
                            _error = null;
                          }),
                ),
              if (_error != null && _error != 'Enter a list name') ...[
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  _error!,
                  style: TextStyle(
                    color: widget.colors.error,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// One selectable observing list inside the add-to-list dialog.
///
/// The rows carry real chrome (icon, border, chevron) so they read as tappable
/// beside the bordered "Create new list…" button below them, and they state
/// plainly when the target is already in a list instead of inviting an add that
/// can only be a no-op.
class _ObservingListRow extends StatelessWidget {
  final String name;
  final NightshadeColors colors;
  final bool alreadyContainsTarget;
  final VoidCallback? onTap;

  const _ObservingListRow({
    required this.name,
    required this.colors,
    required this.alreadyContainsTarget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !alreadyContainsTarget;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.list,
                  size: 14,
                  color: enabled ? colors.textSecondary : colors.textMuted,
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          enabled ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                ),
                if (alreadyContainsTarget)
                  Row(
                    children: [
                      Icon(LucideIcons.check, size: 12, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Already added',
                        style: NightshadeTypography.labelQuiet.copyWith(
                          color: colors.success,
                        ),
                      ),
                    ],
                  )
                else
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: colors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  final NightshadeColors colors;

  const _ScoreBadge({required this.score, required this.colors});

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    if (score >= 75) {
      badgeColor = colors.success;
    } else if (score >= 50) {
      badgeColor = colors.warning;
    } else {
      badgeColor = colors.error;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: NightshadeDecorations.kpiBadge(badgeColor),
      child: Center(
        child: Text(
          score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize15,
            fontWeight: FontWeight.w700,
            color: badgeColor,
          ),
        ),
      ),
    );
  }
}

/// Shows filter-aware estimated integration when Smart Night context is
/// available; otherwise falls back to hours above minimum altitude.
class _IntegrationEstimateChip extends ConsumerWidget {
  final int targetId;
  final double fallbackVisibleHours;
  final NightshadeColors colors;

  const _IntegrationEstimateChip({
    required this.targetId,
    required this.fallbackVisibleHours,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync =
        ref.watch(plannerTargetIntegrationPreviewProvider(targetId));

    return previewAsync.when(
      data: (preview) {
        if (preview != null && preview.estimatedIntegrationHours > 0) {
          return _StatChip(
            icon: LucideIcons.timer,
            label:
                '~${preview.estimatedIntegrationHours.toStringAsFixed(1)}h integration',
            colors: colors,
          );
        }
        if (fallbackVisibleHours > 0) {
          return _StatChip(
            icon: LucideIcons.clock,
            label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
            colors: colors,
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => fallbackVisibleHours > 0
          ? _StatChip(
              icon: LucideIcons.clock,
              label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
              colors: colors,
            )
          : const SizedBox.shrink(),
      error: (_, __) => fallbackVisibleHours > 0
          ? _StatChip(
              icon: LucideIcons.clock,
              label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
              colors: colors,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isWarning;

  /// Optional explanation shown on hover/long-press. Used where a compact
  /// chip label alone would be ambiguous (e.g. which "peak" altitude this is).
  final String? tooltip;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.isWarning = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = isWarning ? colors.warning : colors.textSecondary;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isWarning
          ? NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            )
          : BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: NightshadeTypography.labelQuiet.copyWith(
              color: chipColor,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

class _CandidateSkeleton extends StatelessWidget {
  final NightshadeColors colors;
  const _CandidateSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SkeletonText(width: 180, height: 14),
            Spacer(),
            SkeletonBox(
              width: 44,
              height: 44,
              borderRadius: NightshadeTokens.radiusFull,
            ),
          ]),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonText(width: 240, height: 12),
          SizedBox(height: NightshadeTokens.spaceSm),
          Row(children: [
            SkeletonBox(width: 60, height: 22),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 60, height: 22),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 60, height: 22),
          ]),
          SizedBox(height: NightshadeTokens.spaceMd),
          Row(children: [
            SkeletonBox(width: 120, height: 30),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 150, height: 30),
          ]),
        ],
      ),
    );
  }
}
