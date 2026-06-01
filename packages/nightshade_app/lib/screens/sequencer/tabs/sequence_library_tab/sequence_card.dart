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

  int _countTargetGroups() {
    return widget.sequence.nodes.values.whereType<TargetHeaderNode>().length;
  }

  int _countExposures() {
    return widget.sequence.nodes.values.whereType<ExposureNode>().length;
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? widget.colors.primary.withValues(alpha: 0.4)
                : widget.colors.border,
            width: _isHovered ? 2 : 1,
          ),
          boxShadow: null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: NightshadeDecorations.tintedBadge(
                widget.colors.primary,
                borderRadius: BorderRadius.circular(10),
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
                            fontSize: 15,
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
                          fontSize: 11,
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
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Stats
                  Row(
                    children: [
                      _StatChip(
                        colors: widget.colors,
                        icon: LucideIcons.layers,
                        label: '${widget.sequence.nodes.length} nodes',
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        colors: widget.colors,
                        icon: LucideIcons.target,
                        label: '$targetCount targets',
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        colors: widget.colors,
                        icon: LucideIcons.camera,
                        label: '$exposureCount exposures',
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        colors: widget.colors,
                        icon: LucideIcons.timer,
                        label: _formatDuration(),
                      ),
                    ],
                  ),
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
                    icon: LucideIcons.trash2,
                    tooltip: 'Delete',
                    color: widget.colors.error,
                    onPressed: () => _deleteSequence(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  void _deleteSequence(BuildContext context) {
    final dbId = widget.sequence.databaseId;
    if (dbId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
