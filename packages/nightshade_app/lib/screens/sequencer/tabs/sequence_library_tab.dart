import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../sequencer_screen.dart';
import '../../../utils/snackbar_helper.dart';

/// Provider for sequences list - loads from database
final savedSequencesProvider = FutureProvider<List<Sequence>>((ref) async {
  final repository = ref.watch(sequenceRepositoryProvider);
  return await repository.loadAllSequences();
});

/// Search provider for sequences
final sequenceSearchProvider = StateProvider<String>((ref) => '');

/// Sort order for sequences
enum SequenceSortOrder { name, dateModified, dateCreated, nodeCount }

/// Provider for sort order
final sequenceSortOrderProvider = StateProvider<SequenceSortOrder>(
  (ref) => SequenceSortOrder.dateModified,
);

class SequenceLibraryTab extends ConsumerWidget {
  const SequenceLibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sequencesAsync = ref.watch(savedSequencesProvider);
    final searchQuery = ref.watch(sequenceSearchProvider);
    final sortOrder = ref.watch(sequenceSortOrderProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          _LibraryHeader(colors: colors),

          const SizedBox(height: 24),

          // Content
          Expanded(
            child: sequencesAsync.when(
              data: (sequences) {
                var filtered = sequences.where((s) => !s.isTemplate).toList();

                // Apply search filter
                if (searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((s) =>
                          s.name
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()) ||
                          s.description
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()))
                      .toList();
                }

                // Apply sort
                switch (sortOrder) {
                  case SequenceSortOrder.name:
                    filtered.sort((a, b) => a.name.compareTo(b.name));
                    break;
                  case SequenceSortOrder.dateModified:
                    filtered
                        .sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
                    break;
                  case SequenceSortOrder.dateCreated:
                    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    break;
                  case SequenceSortOrder.nodeCount:
                    filtered.sort(
                        (a, b) => b.nodes.length.compareTo(a.nodes.length));
                    break;
                }

                if (filtered.isEmpty) {
                  return _EmptyState(
                      colors: colors, hasSearch: searchQuery.isNotEmpty);
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _SequenceCard(
                      colors: colors,
                      sequence: filtered[index],
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 48, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load sequences',
                      style: TextStyle(color: colors.textPrimary, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    NightshadeButton(
                      label: 'Retry',
                      icon: LucideIcons.refreshCw,
                      onPressed: () => ref.invalidate(savedSequencesProvider),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _LibraryHeader({required this.colors});

  @override
  ConsumerState<_LibraryHeader> createState() => _LibraryHeaderState();
}

class _LibraryHeaderState extends ConsumerState<_LibraryHeader> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortOrder = ref.watch(sequenceSortOrderProvider);

    return Row(
      children: [
        // Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sequence Library',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: widget.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Browse and load your saved imaging sequences',
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.textMuted,
              ),
            ),
          ],
        ),

        const Spacer(),

        // Sort dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.colors.border),
          ),
          child: PopupMenuButton<SequenceSortOrder>(
            initialValue: sortOrder,
            onSelected: (value) {
              ref.read(sequenceSortOrderProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              _buildSortMenuItem(SequenceSortOrder.dateModified,
                  'Last Modified', LucideIcons.clock, sortOrder),
              _buildSortMenuItem(SequenceSortOrder.dateCreated, 'Date Created',
                  LucideIcons.calendar, sortOrder),
              _buildSortMenuItem(SequenceSortOrder.name, 'Name',
                  LucideIcons.arrowUpAZ, sortOrder),
              _buildSortMenuItem(SequenceSortOrder.nodeCount, 'Node Count',
                  LucideIcons.layers, sortOrder),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.arrowUpDown,
                    size: 14, color: widget.colors.textMuted),
                const SizedBox(width: 8),
                Text(
                  _getSortLabel(sortOrder),
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(LucideIcons.chevronDown,
                    size: 14, color: widget.colors.textMuted),
              ],
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Search
        Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search,
                  size: 16, color: widget.colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    ref.read(sequenceSearchProvider.notifier).state = value;
                  },
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search sequences...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: widget.colors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    ref.read(sequenceSearchProvider.notifier).state = '';
                  },
                  child: Icon(LucideIcons.x,
                      size: 16, color: widget.colors.textMuted),
                ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // Save current sequence button
        _ActionButton(
          colors: widget.colors,
          icon: LucideIcons.save,
          label: 'Save Current',
          isPrimary: true,
          onPressed: () => _showSaveSequenceDialog(context),
        ),
      ],
    );
  }

  PopupMenuItem<SequenceSortOrder> _buildSortMenuItem(
    SequenceSortOrder value,
    String label,
    IconData icon,
    SequenceSortOrder current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: value == current
                  ? widget.colors.primary
                  : widget.colors.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: value == current
                  ? widget.colors.primary
                  : widget.colors.textPrimary,
              fontWeight:
                  value == current ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          if (value == current)
            Icon(LucideIcons.check, size: 14, color: widget.colors.primary),
        ],
      ),
    );
  }

  String _getSortLabel(SequenceSortOrder order) {
    switch (order) {
      case SequenceSortOrder.name:
        return 'Name';
      case SequenceSortOrder.dateModified:
        return 'Last Modified';
      case SequenceSortOrder.dateCreated:
        return 'Date Created';
      case SequenceSortOrder.nodeCount:
        return 'Node Count';
    }
  }

  void _showSaveSequenceDialog(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);
    if (currentSequence == null) {
      context.showErrorSnackBar('No sequence to save');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _SaveSequenceDialog(
        colors: widget.colors,
        sequence: currentSequence,
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? _isHovered
                    ? widget.colors.primary.withValues(alpha: 0.9)
                    : widget.colors.primary
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(color: widget.colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color:
                    widget.isPrimary ? onPrimary : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? onPrimary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: widget.colors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.colors.primary.withValues(alpha: 0.1),
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

  void _loadSequence(BuildContext context) {
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

    final loadedSequence = Sequence(
      name: widget.sequence.name,
      description: widget.sequence.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
      databaseId: widget.sequence.databaseId, // Keep reference to original
    );

    ref.read(currentSequenceProvider.notifier).loadSequence(loadedSequence);
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showSuccessSnackBar('Loaded "${widget.sequence.name}"');
  }

  Future<void> _duplicateSequence(BuildContext context) async {
    final dbId = widget.sequence.databaseId;
    if (dbId != null) {
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        await repository.duplicateSequence(
            dbId, '${widget.sequence.name} (Copy)');

        ref.invalidate(savedSequencesProvider);

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
        content: Text(
          'Are you sure you want to delete "${widget.sequence.name}"? This action cannot be undone.',
          style: TextStyle(color: widget.colors.textSecondary),
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

                ref.invalidate(savedSequencesProvider);

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

class _StatChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;

  const _StatChip({
    required this.colors,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;

  const _IconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isHovered
                  ? color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovered ? color : widget.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;
  final bool hasSearch;

  const _EmptyState({
    required this.colors,
    this.hasSearch = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              hasSearch ? LucideIcons.searchX : LucideIcons.folderOpen,
              size: 48,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            hasSearch ? 'No sequences found' : 'No saved sequences',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term'
                : 'Save your sequences to access them later',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lightbulb, size: 14, color: colors.warning),
                  const SizedBox(width: 8),
                  Text(
                    'Tip: Use "Save Current" to save your sequence',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SaveSequenceDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SaveSequenceDialog({
    required this.colors,
    required this.sequence,
  });

  @override
  ConsumerState<_SaveSequenceDialog> createState() =>
      _SaveSequenceDialogState();
}

class _SaveSequenceDialogState extends ConsumerState<_SaveSequenceDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sequence.name);
    _descriptionController =
        TextEditingController(text: widget.sequence.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveSequence() async {
    if (_nameController.text.trim().isEmpty) {
      context.showErrorSnackBar('Please enter a sequence name');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(sequenceRepositoryProvider);

      final sequenceToSave = Sequence(
        databaseId: widget.sequence.databaseId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: widget.sequence.nodes,
        rootNodeId: widget.sequence.rootNodeId,
        isTemplate: false,
      );

      await repository.saveSequence(sequenceToSave, isTemplate: false);

      ref.invalidate(savedSequencesProvider);

      if (mounted) {
        Navigator.pop(context);

        context
            .showSuccessSnackBar('Sequence "${_nameController.text}" saved!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save sequence: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.save,
                    size: 20,
                    color: widget.colors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save Sequence',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Save to your sequence library',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Name field
            Text(
              'Sequence Name',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.colors.border),
              ),
              child: TextField(
                controller: _nameController,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter sequence name',
                  hintStyle: TextStyle(color: widget.colors.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Description field
            Text(
              'Description (optional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.colors.border),
              ),
              child: TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Add a description...',
                  hintStyle: TextStyle(color: widget.colors.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: widget.colors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Saving ${widget.sequence.nodes.length} nodes',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NightshadeButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: _isSaving ? 'Saving...' : 'Save',
                  icon: _isSaving ? LucideIcons.loader : LucideIcons.save,
                  onPressed: _isSaving ? null : _saveSequence,
                  size: ButtonSize.small,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
