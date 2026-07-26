// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Candidate list with cursor-driven pagination, the per-target row (info + altitude panel), score/integration/stat chips, and the skeleton placeholder used while suggestions are loading.
part of '../planner_screen.dart';

// ============================================================================
// Candidate list with pagination
// ============================================================================

class _CandidateList extends ConsumerWidget {
  final List<TargetSuggestion> candidates;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateList({
    required this.candidates,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCount =
        ref.watch(_plannerVisibleCountProvider).clamp(0, candidates.length);
    final visible = candidates.take(visibleCount).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final candidate in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
            child: _CandidateRow(
              key: ValueKey('candidate-${candidate.targetId}'),
              suggestion: candidate,
              colors: colors,
              isMobile: isMobile,
            ),
          ),
        if (visibleCount < candidates.length)
          Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
            child: Align(
              alignment: Alignment.center,
              child: NightshadeButton(
                label:
                    'Load more (${candidates.length - visibleCount} remaining)',
                icon: LucideIcons.chevronDown,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () {
                  final next = (visibleCount + _kPlannerPageSize)
                      .clamp(0, candidates.length);
                  ref.read(_plannerVisibleCountProvider.notifier).state = next;
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Target metadata and actions for a planner candidate card.
class _CandidateRowInfo extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final VoidCallback onReviewInSequencer;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToObservingList;

  const _CandidateRowInfo({
    required this.suggestion,
    required this.colors,
    required this.onReviewInSequencer,
    required this.onSendToFraming,
    required this.onAddToObservingList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peakAlt = suggestion.visibility.peakAltitude ??
        suggestion.visibility.currentAltitude;
    final hoursAbove = suggestion.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = suggestion.visibility.moonDistance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.targetName,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (suggestion.catalogId != null &&
                      suggestion.catalogId != suggestion.targetName)
                    Text(
                      suggestion.catalogId!,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            _ScoreBadge(score: suggestion.totalScore, colors: colors),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: 4,
          children: [
            if (suggestion.objectType != null)
              _StatChip(
                icon: LucideIcons.shapes,
                label: suggestion.objectType!,
                colors: colors,
              ),
            _StatChip(
              icon: LucideIcons.arrowUp,
              label: 'Peak ${peakAlt.toStringAsFixed(0)}°',
              colors: colors,
            ),
            _IntegrationEstimateChip(
              targetId: suggestion.targetId,
              fallbackVisibleHours: hoursAbove,
              colors: colors,
            ),
            _StatChip(
              icon: LucideIcons.moon,
              label: 'Moon ${moonDist.toStringAsFixed(0)}°',
              colors: colors,
              isWarning: moonDist < 45,
            ),
            if (suggestion.magnitude != null)
              _StatChip(
                icon: LucideIcons.sparkles,
                label: 'Mag ${suggestion.magnitude!.toStringAsFixed(1)}',
                colors: colors,
              ),
            // Why major-axis only: the DB Target schema does not store a
            // minor axis, so plumbing one through from OpenNGC would touch
            // out-of-scope files for this branch.
            if (suggestion.sizeArcmin != null && suggestion.sizeArcmin! > 0)
              _StatChip(
                icon: LucideIcons.ruler,
                label: _formatSizeLabel(suggestion.sizeArcmin),
                colors: colors,
              ),
            if (suggestion.constellation != null)
              _StatChip(
                icon: LucideIcons.star,
                label: suggestion.constellation!,
                colors: colors,
              ),
          ],
        ),
        if (suggestion.reasoning.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            suggestion.reasoning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            NightshadeButton(
              label: context.l10n.text('plannerReviewInSequencer'),
              icon: LucideIcons.listOrdered,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onReviewInSequencer,
            ),
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.frame,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onSendToFraming,
            ),
            NightshadeButton(
              label: 'Add to observing list',
              icon: LucideIcons.listPlus,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onAddToObservingList,
            ),
          ],
        ),
      ],
    );
  }
}

/// Altitude visibility chart shown beside (or below on narrow) candidate info.
class _CandidateAltitudePanel extends StatelessWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;

  const _CandidateAltitudePanel({
    required this.suggestion,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      child: AltitudeChart(
        raHours: suggestion.raHours,
        decDegrees: suggestion.decDegrees,
        targetName: suggestion.targetName,
      ),
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateRow({
    super.key,
    required this.suggestion,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoSection = _CandidateRowInfo(
      suggestion: suggestion,
      colors: colors,
      onReviewInSequencer: () => _reviewInSequencer(context, ref),
      onSendToFraming: () => _sendToFraming(context, ref),
      onAddToObservingList: () => _addToObservingList(context, ref),
    );
    final chartPanel = _CandidateAltitudePanel(
      suggestion: suggestion,
      colors: colors,
    );

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusLg,
      padding: NightshadeTokens.cardPadding,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoSection,
                const SizedBox(height: NightshadeTokens.spaceMd),
                chartPanel,
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = clampPanelWidth(
                  constraints.maxWidth,
                  fraction: 0.32,
                  min: 300,
                  max: 380,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: infoSection),
                    const SizedBox(width: NightshadeTokens.spaceLg),
                    SizedBox(
                      width: panelWidth,
                      child: chartPanel,
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Build a Smart Night sequence for this single candidate and load it into
  /// the editor, replacing the current draft (mirrors the primary card's
  /// "Review in Sequencer"). The helper surfaces any
  /// [SmartNightBuildException] via snackbar and returns false; we only act on
  /// a true result.
  Future<void> _reviewInSequencer(BuildContext context, WidgetRef ref) async {
    final loaded = await addPlanTonightTargetToSequencer(
      context: context,
      ref: ref,
      target: suggestion,
      replaceSequence: true,
      includeSessionPreamble: true,
    );
    if (!loaded || !context.mounted) return;

    final colorsLocal = NightshadeColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded ${suggestion.targetName} into the sequencer'),
        backgroundColor: colorsLocal.success,
      ),
    );
    context.go('/sequencer');
  }

  void _sendToFraming(BuildContext context, WidgetRef ref) {
    ref.read(framingProvider.notifier).setTargetSuggestion(suggestion);
    context.goNamed('framing');
  }

  Future<void> _addToObservingList(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CandidateObservingListDialog(
        suggestion: suggestion,
        colors: colors,
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _authority = ref.read(backendProvider);
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

    if (id == null) {
      setState(() {
        _saving = false;
        _error = ref.read(observingListNotifierProvider).errorMessage ??
            'Could not add the target to this list';
      });
      return;
    }

    _showSuccessAndClose(
      'Added ${widget.suggestion.targetName} to the list',
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

    _showSuccessAndClose(
      'Created "$name" and added ${widget.suggestion.targetName}',
    );
  }

  void _showSuccessAndClose(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: widget.colors.success,
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
                              ListTile(
                                dense: true,
                                enabled: !_saving,
                                title: Text(
                                  list.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: widget.colors.textPrimary,
                                  ),
                                ),
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

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = isWarning ? colors.warning : colors.textSecondary;
    return Container(
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
