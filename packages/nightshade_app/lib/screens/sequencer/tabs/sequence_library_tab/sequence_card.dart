part of '../sequence_library_tab.dart';

class _SequenceCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SequenceCard({
    required this.colors,
    required this.sequence,
  });

  @override
  ConsumerState<_SequenceCard> createState() => _SequenceCardState();
}

class _SequenceCardState extends ConsumerState<_SequenceCard> {
  bool _isHovered = false;
  bool _expanded = false;

  int _countTargetGroups() {
    return widget.sequence.nodes.values.whereType<TargetHeaderNode>().length;
  }

  int _countExposures() {
    return widget.sequence.nodes.values.whereType<ExposureNode>().length;
  }

  /// First target header's name, used as the card's primary-target label.
  String? _primaryTargetName() {
    for (final node in widget.sequence.nodes.values) {
      if (node is TargetHeaderNode && node.targetName.isNotEmpty) {
        return node.targetName;
      }
    }
    return null;
  }

  String _formatDuration() {
    final totalSecs = widget.sequence.totalIntegrationSecs;
    if (totalSecs <= 0) return 'N/A';

    final hours = (totalSecs / 3600).floor();
    final mins = ((totalSecs % 3600) / 60).floor();

    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final targetCount = _countTargetGroups();
    final exposureCount = _countExposures();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.colors.surface,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color: _isHovered
                ? widget.colors.primary.withValues(alpha: 0.4)
                : widget.colors.border,
            width: _isHovered ? 2 : 1,
          ),
          boxShadow: null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMainRow(targetCount, exposureCount),
            if (_expanded) _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRow(int targetCount, int exposureCount) {
    final primaryTarget = _primaryTargetName();
    return Row(
      children: [
        // Icon
        Container(
          width: 48,
          height: 48,
          decoration: NightshadeDecorations.tintedBadge(
            widget.colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          ),
          child: Icon(
            LucideIcons.workflow,
            size: 24,
            color: widget.colors.primary,
          ),
        ),

        const SizedBox(width: 16),

        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.sequence.name,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize15,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDate(widget.sequence.modifiedAt),
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted,
                    ),
                  ),
                ],
              ),
              if (widget.sequence.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.sequence.description,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: widget.colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              // Stats
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (primaryTarget != null)
                    _StatChip(
                      colors: widget.colors,
                      icon: LucideIcons.star,
                      label: primaryTarget,
                    ),
                  _StatChip(
                    colors: widget.colors,
                    icon: LucideIcons.layers,
                    label: '${widget.sequence.nodes.length} nodes',
                  ),
                  _StatChip(
                    colors: widget.colors,
                    icon: LucideIcons.target,
                    label: '$targetCount targets',
                  ),
                  _StatChip(
                    colors: widget.colors,
                    icon: LucideIcons.camera,
                    label: '$exposureCount exposures',
                  ),
                  _StatChip(
                    colors: widget.colors,
                    icon: LucideIcons.timer,
                    label: _formatDuration(),
                  ),
                ],
              ),
              _buildRunRollup(),
            ],
          ),
        ),

        // Actions
        AnimatedOpacity(
          opacity: _isHovered ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconButton(
                colors: widget.colors,
                icon:
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                tooltip: _expanded ? 'Hide preview' : 'Preview',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              const SizedBox(width: 4),
              if (widget.sequence.databaseId != null) ...[
                _IconButton(
                  colors: widget.colors,
                  icon: LucideIcons.history,
                  tooltip: 'View run history',
                  onPressed: () => _openHistory(context),
                ),
                const SizedBox(width: 4),
              ],
              _IconButton(
                colors: widget.colors,
                icon: LucideIcons.folderOpen,
                tooltip: 'Load',
                onPressed: () => _loadSequence(context),
              ),
              const SizedBox(width: 4),
              _IconButton(
                colors: widget.colors,
                icon: LucideIcons.copy,
                tooltip: 'Duplicate',
                onPressed: () => _duplicateSequence(context),
              ),
              const SizedBox(width: 4),
              _IconButton(
                colors: widget.colors,
                icon: LucideIcons.upload,
                tooltip: 'Export',
                onPressed: () => _exportSequence(context),
              ),
              const SizedBox(width: 4),
              _IconButton(
                colors: widget.colors,
                icon: LucideIcons.trash2,
                tooltip: 'Delete',
                color: widget.colors.error,
                onPressed: () => _deleteSequence(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Run-history rollup row ("N runs · last DATE"). Hidden for unsaved
  /// sequences and for sequences that have never run.
  Widget _buildRunRollup() {
    final dbId = widget.sequence.databaseId;
    if (dbId == null) return const SizedBox.shrink();
    final summaryAsync = ref.watch(sequenceRunSummaryProvider(dbId));
    return summaryAsync.maybeWhen(
      data: (summary) {
        if (summary.runCount == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _StatChip(
                colors: widget.colors,
                icon: LucideIcons.play,
                label: '${summary.runCount} '
                    'run${summary.runCount == 1 ? '' : 's'}',
              ),
              if (summary.lastRunAt != null)
                _StatChip(
                  colors: widget.colors,
                  icon: LucideIcons.history,
                  label: 'Last run ${_formatDate(summary.lastRunAt!)}',
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  /// Read-only preview: target list with per-target exposure breakdown,
  /// derived from the node tree. Distinct from the Load action.
  Widget _buildPreview() {
    final headers =
        widget.sequence.nodes.values.whereType<TargetHeaderNode>().toList();
    final exposures =
        widget.sequence.nodes.values.whereType<ExposureNode>().toList();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: widget.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: NightshadeTypography.h6
                .copyWith(color: widget.colors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (headers.isEmpty)
            Text(
              'No targets — ${exposures.length} exposure '
              'node${exposures.length == 1 ? '' : 's'}.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: widget.colors.textMuted,
              ),
            )
          else
            for (final header in headers) ...[
              _buildTargetPreviewRow(header),
              const SizedBox(height: 4),
            ],
        ],
      ),
    );
  }

  Widget _buildTargetPreviewRow(TargetHeaderNode header) {
    // Sum exposure seconds per filter for the exposures descended from
    // this target header (direct + nested children).
    final byFilter = <String, double>{};
    final visited = <String>{};
    void walk(String nodeId) {
      if (!visited.add(nodeId)) return;
      final node = widget.sequence.nodes[nodeId];
      if (node == null) return;
      if (node is ExposureNode) {
        final filter = (node.filter == null || node.filter!.isEmpty)
            ? 'No filter'
            : node.filter!;
        byFilter[filter] =
            (byFilter[filter] ?? 0) + node.durationSecs * node.count;
      }
      for (final childId in node.childIds) {
        walk(childId);
      }
    }

    for (final childId in header.childIds) {
      walk(childId);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.target, size: 12, color: widget.colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                header.targetName.isEmpty ? 'Target' : header.targetName,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (byFilter.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 2),
            child: Text(
              'No exposures',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: widget.colors.textMuted,
              ),
            ),
          )
        else
          for (final entry in byFilter.entries)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Text(
                '${entry.key}: ${_formatSecs(entry.value)}',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: widget.colors.textSecondary,
                ),
              ),
            ),
      ],
    );
  }

  String _formatSecs(double secs) {
    if (secs <= 0) return '0m';
    final hours = (secs / 3600).floor();
    final mins = ((secs % 3600) / 60).round();
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  /// Switch to the History tab pre-filtered to this sequence's runs.
  void _openHistory(BuildContext context) {
    final dbId = widget.sequence.databaseId;
    if (dbId == null) return;
    ref.read(historyFilterSequenceIdProvider.notifier).state = dbId;
    ref.read(sequencerTabProvider.notifier).state = SequencerTab.history.index;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${DateFormat.jm().format(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return DateFormat.yMd().format(date);
    }
  }

  Future<void> _loadSequence(BuildContext context) async {
    // Create a copy with new IDs so we don't modify the saved one
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    for (final entry in widget.sequence.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    for (final entry in widget.sequence.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId =
          oldNode.parentId != null ? idMapping[oldNode.parentId] : null;
      final newChildIds =
          oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    final newRootId = widget.sequence.rootNodeId != null
        ? idMapping[widget.sequence.rootNodeId]
        : null;

    final loadedSequence = Sequence.create(
      name: widget.sequence.name,
      description: widget.sequence.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
      databaseId: widget.sequence.databaseId, // Keep reference to original
    );

    final editor = ref.read(currentSequenceProvider.notifier);
    try {
      editor.loadSequence(loadedSequence);
    } on UnsavedChangesException catch (e) {
      // Prompt before clobbering — clicking a library item is a user
      // action so we know they meant to switch sequences, but we still
      // give them a chance to save first.
      if (!context.mounted) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              ctx,
              designMaxWidth: 440,
            ),
            child: Text('"${e.currentSequenceName}" has unsaved changes. '
                'Loading "${widget.sequence.name}" will discard them.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard and load'),
            ),
          ],
        ),
      );
      if (discard != true) return;
      editor.loadSequence(loadedSequence, discardUnsaved: true);
    }

    ref.read(sequencerTabProvider.notifier).state = 0;

    if (context.mounted) {
      context.showSuccessSnackBar('Loaded "${widget.sequence.name}"');
    }
  }

  Future<void> _duplicateSequence(BuildContext context) async {
    final dbId = widget.sequence.databaseId;
    if (dbId != null) {
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        final duplicated = await repository.duplicateSequence(
            dbId, '${widget.sequence.name} (Copy)');

        if (duplicated?.databaseId != null) {
          notifySequenceCatalogChanged(
            ref,
            sequenceId: duplicated!.databaseId!,
            action: 'duplicated',
            name: duplicated.name,
          );
        } else {
          ref.invalidate(savedSequencesProvider);
        }

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.sequence.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate: $e');
        }
      }
    }
  }

  /// Export the saved sequence to a JSON file. Mirrors the toolbar's
  /// export path: on a blocking validation failure, surface the structured
  /// issue dialog with a "force export anyway" escape hatch.
  Future<void> _exportSequence(BuildContext context) async {
    final fileService = ref.read(sequenceFileServiceProvider);
    final sequence = widget.sequence;
    try {
      await fileService.exportSequence(sequence);
      if (context.mounted) {
        context.showSuccessSnackBar('Exported "${sequence.name}"');
      }
    } on SequenceValidationFailedException catch (e) {
      if (!context.mounted) return;
      final force = await showValidationIssueDialog(
        context,
        issues: e.issues,
        operationName: 'Export Sequence',
        forceLabel: 'Force export anyway',
      );
      if (!force || !context.mounted) return;
      try {
        await fileService.exportSequence(sequence, forceExport: true);
        if (context.mounted) {
          context.showSuccessSnackBar('Exported "${sequence.name}" (forced)');
        }
      } catch (err) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to export: $err');
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to export: $e');
      }
    }
  }

  void _deleteSequence(BuildContext context) {
    final dbId = widget.sequence.databaseId;
    if (dbId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(NightshadeTokens.radiusInline8)),
        title: Text(
          'Delete Sequence',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            dialogContext,
            designMaxWidth: 400,
          ),
          child: Text(
            'Are you sure you want to delete "${widget.sequence.name}"? This action cannot be undone.',
            style: TextStyle(color: widget.colors.textSecondary),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              try {
                final repository = ref.read(sequenceRepositoryProvider);
                await repository.deleteSequence(dbId);

                notifySequenceCatalogChanged(
                  ref,
                  sequenceId: dbId,
                  action: 'deleted',
                  name: widget.sequence.name,
                );

                if (context.mounted) {
                  context
                      .showSuccessSnackBar('Deleted "${widget.sequence.name}"');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to delete: $e');
                }
              }
            },
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}
