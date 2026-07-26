part of '../sequence_library_tab.dart';

/// One row in the sequence library, rendered from a lightweight
/// [SequenceSummary] (no node-tree hydration).
///
/// The summary carries everything the collapsed card shows — name, primary
/// target, node/target/exposure counts, estimated duration, run roll-up, tags
/// and the favorite flag. Actions that genuinely need the full node graph
/// (Load, Duplicate, Export, Preview) lazily load the [Sequence] from the
/// repository on demand, so opening the library never pays the N+1 full-load
/// cost.
class _SequenceCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final SequenceSummary summary;

  const _SequenceCard({
    required this.colors,
    required this.summary,
  });

  @override
  ConsumerState<_SequenceCard> createState() => _SequenceCardState();
}

class _SequenceCardState extends ConsumerState<_SequenceCard> {
  bool _isHovered = false;
  bool _expanded = false;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  /// Lazily-loaded full sequence for the expandable preview. Loaded the first
  /// time the user expands the card and reused afterwards.
  Sequence? _previewSequence;
  bool _previewLoading = false;
  Object? _previewError;

  SequenceSummary get _summary => widget.summary;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next) || !mounted) return;
        setState(() {
          _expanded = false;
          _previewSequence = null;
          _previewLoading = false;
          _previewError = null;
        });
      },
    );
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  bool _isCurrentAuthority(NightshadeBackend authority) =>
      identical(ref.read(backendProvider), authority);

  String _formatDuration() {
    final totalSecs = _summary.totalIntegrationSecs;
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
            _buildMainRow(),
            if (_expanded) _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRow() {
    final primaryTarget = _summary.primaryTargetName;
    final info = _buildInfo(primaryTarget);
    final actions = _buildActions();

    if (Responsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FavoriteToggle(
                colors: widget.colors,
                isFavorite: _summary.isFavorite,
                onPressed: _toggleFavorite,
              ),
              const SizedBox(width: 8),
              _buildSequenceIcon(size: 40),
              const SizedBox(width: 12),
              Expanded(child: info),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 150),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: actions,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        // Favorite star (also acts as the favorite toggle).
        _FavoriteToggle(
          colors: widget.colors,
          isFavorite: _summary.isFavorite,
          onPressed: _toggleFavorite,
        ),

        const SizedBox(width: 8),

        // Icon
        _buildSequenceIcon(),

        const SizedBox(width: 16),

        // Info
        Expanded(child: info),

        // Actions
        AnimatedOpacity(
          opacity: _isHovered ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                actions[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceIcon({double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: NightshadeDecorations.tintedBadge(
        widget.colors.primary,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: Icon(
        LucideIcons.workflow,
        size: size / 2,
        color: widget.colors.primary,
      ),
    );
  }

  Widget _buildInfo(String? primaryTarget) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _summary.name,
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
              _formatDate(_summary.modifiedAt),
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: widget.colors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (primaryTarget != null && primaryTarget.isNotEmpty)
              _StatChip(
                colors: widget.colors,
                icon: LucideIcons.star,
                label: primaryTarget,
              ),
            _StatChip(
              colors: widget.colors,
              icon: LucideIcons.layers,
              label: '${_summary.nodeCount} nodes',
            ),
            _StatChip(
              colors: widget.colors,
              icon: LucideIcons.target,
              label: '${_summary.targetCount} targets',
            ),
            _StatChip(
              colors: widget.colors,
              icon: LucideIcons.camera,
              label: '${_summary.exposureCount} exposures',
            ),
            _StatChip(
              colors: widget.colors,
              icon: LucideIcons.timer,
              label: _formatDuration(),
            ),
          ],
        ),
        _buildRunRollup(),
        _buildTagRow(),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      _IconButton(
        colors: widget.colors,
        icon: _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        tooltip: _expanded ? 'Hide preview' : 'Preview',
        onPressed: _togglePreview,
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.history,
        tooltip: 'View run history',
        onPressed: () => _openHistory(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.gitBranch,
        tooltip: 'Version history',
        onPressed: () => _openVersionHistory(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.tags,
        tooltip: 'Edit tags',
        onPressed: () => _editTags(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.folderOpen,
        tooltip: 'Load',
        onPressed: () => _loadSequence(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.copy,
        tooltip: 'Duplicate',
        onPressed: () => _duplicateSequence(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.upload,
        tooltip: 'Export',
        onPressed: () => _exportSequence(context),
      ),
      _IconButton(
        colors: widget.colors,
        icon: LucideIcons.trash2,
        tooltip: 'Delete',
        color: widget.colors.error,
        onPressed: () => _deleteSequence(context),
      ),
    ];
  }

  /// Run-history rollup row ("N runs · last DATE"), straight from the summary.
  /// Hidden for sequences that have never run.
  Widget _buildRunRollup() {
    if (_summary.runCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _StatChip(
            colors: widget.colors,
            icon: LucideIcons.play,
            label: '${_summary.runCount} '
                'run${_summary.runCount == 1 ? '' : 's'}',
          ),
          if (_summary.lastRunAt != null)
            _StatChip(
              colors: widget.colors,
              icon: LucideIcons.history,
              label: 'Last run ${_formatDate(_summary.lastRunAt!)}',
            ),
        ],
      ),
    );
  }

  /// Tag chips for the sequence. Hidden when the sequence carries no tags.
  Widget _buildTagRow() {
    if (_summary.tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tag in _summary.tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: NightshadeDecorations.tintedBadge(
                widget.colors.primary,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.tag, size: 10, color: widget.colors.primary),
                  const SizedBox(width: 4),
                  Text(
                    tag,
                    style: NightshadeTypography.labelStrongSm
                        .copyWith(color: widget.colors.primary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Read-only preview: lazily loads the full sequence, then shows the target
  /// list with per-target exposure breakdown derived from the node tree.
  Widget _buildPreview() {
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
          _buildPreviewBody(),
        ],
      ),
    );
  }

  Widget _buildPreviewBody() {
    if (_previewLoading) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.colors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading preview…',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: widget.colors.textMuted,
            ),
          ),
        ],
      );
    }

    if (_previewError != null) {
      return Text(
        'Could not load preview: $_previewError',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: widget.colors.error,
        ),
      );
    }

    final sequence = _previewSequence;
    if (sequence == null) {
      return Text(
        'Preview unavailable.',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: widget.colors.textMuted,
        ),
      );
    }

    final headers =
        sequence.nodes.values.whereType<TargetHeaderNode>().toList();
    final exposures = sequence.nodes.values.whereType<ExposureNode>().toList();

    if (headers.isEmpty) {
      return Text(
        'No targets — ${exposures.length} exposure '
        'node${exposures.length == 1 ? '' : 's'}.',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: widget.colors.textMuted,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final header in headers) ...[
          _buildTargetPreviewRow(sequence, header),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildTargetPreviewRow(Sequence sequence, TargetHeaderNode header) {
    // Sum exposure seconds per filter for the exposures descended from
    // this target header (direct + nested children).
    final byFilter = <String, double>{};
    final visited = <String>{};
    void walk(String nodeId) {
      if (!visited.add(nodeId)) return;
      final node = sequence.nodes[nodeId];
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

  /// Load the full sequence from the repository, used by every tree-requiring
  /// action. Returns null and surfaces an error snackbar on failure.
  Future<Sequence?> _loadFullSequence(
    BuildContext context, {
    required NightshadeBackend authority,
    required SequenceRepository repository,
  }) async {
    try {
      final sequence = await repository.loadSequence(_summary.id);
      if (!_isCurrentAuthority(authority)) return null;
      if (sequence == null && context.mounted) {
        context.showErrorSnackBar('Sequence is no longer available');
      }
      return sequence;
    } catch (e) {
      if (context.mounted && _isCurrentAuthority(authority)) {
        context.showErrorSnackBar('Failed to load sequence: $e');
      }
      return null;
    }
  }

  void _togglePreview() {
    final willExpand = !_expanded;
    setState(() => _expanded = willExpand);
    if (willExpand && _previewSequence == null && !_previewLoading) {
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final authority = ref.read(backendProvider);
    final repository = ref.read(sequenceRepositoryProvider);
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final sequence = await repository.loadSequence(_summary.id);
      if (!mounted || !_isCurrentAuthority(authority)) return;
      setState(() {
        _previewSequence = sequence;
        _previewLoading = false;
        if (sequence == null) {
          _previewError = 'Sequence is no longer available';
        }
      });
    } catch (e) {
      if (!mounted || !_isCurrentAuthority(authority)) return;
      setState(() {
        _previewLoading = false;
        _previewError = e;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final authority = ref.read(backendProvider);
    final repository = ref.read(sequenceRepositoryProvider);
    try {
      await repository.toggleFavorite(_summary.id);
      if (!_isCurrentAuthority(authority)) return;
      ref.invalidate(savedSequenceSummariesProvider);
    } catch (e) {
      if (mounted && _isCurrentAuthority(authority)) {
        context.showErrorSnackBar('Failed to update favorite: $e');
      }
    }
  }

  /// Switch to the History tab pre-filtered to this sequence's runs.
  void _openHistory(BuildContext context) {
    ref.read(historyFilterSequenceIdProvider.notifier).state = _summary.id;
    ref.read(sequencerTabProvider.notifier).state = SequencerTab.history.index;
  }

  void _openVersionHistory(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _VersionHistoryDialog(
        colors: widget.colors,
        sequenceId: _summary.id,
        sequenceName: _summary.name,
      ),
    );
  }

  void _editTags(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _TagEditorDialog(
        colors: widget.colors,
        sequenceId: _summary.id,
        sequenceName: _summary.name,
        initialTags: _summary.tags,
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
    final authority = ref.read(backendProvider);
    final repository = ref.read(sequenceRepositoryProvider);
    final source = await _loadFullSequence(
      context,
      authority: authority,
      repository: repository,
    );
    if (source == null || !context.mounted || !_isCurrentAuthority(authority)) {
      return;
    }

    // Create a copy with new IDs so we don't modify the saved one
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    for (final entry in source.nodes.entries) {
      idMapping[entry.key] = const Uuid().v4();
    }

    for (final entry in source.nodes.entries) {
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

    final newRootId =
        source.rootNodeId != null ? idMapping[source.rootNodeId] : null;

    final loadedSequence = Sequence.create(
      name: source.name,
      description: source.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
      databaseId: source.databaseId, // Keep reference to original
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
                'Loading "${_summary.name}" will discard them.'),
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
      if (discard != true || !_isCurrentAuthority(authority)) return;
      editor.loadSequence(loadedSequence, discardUnsaved: true);
    }

    if (!_isCurrentAuthority(authority)) return;

    ref.read(sequencerTabProvider.notifier).state = 0;

    if (context.mounted) {
      context.showSuccessSnackBar('Loaded "${_summary.name}"');
    }
  }

  Future<void> _duplicateSequence(BuildContext context) async {
    final authority = ref.read(backendProvider);
    final repository = ref.read(sequenceRepositoryProvider);
    try {
      final duplicated = await repository.duplicateSequence(
          _summary.id, '${_summary.name} (Copy)');

      if (!_isCurrentAuthority(authority)) return;

      if (duplicated?.databaseId != null) {
        notifySequenceCatalogChanged(
          ref,
          sequenceId: duplicated!.databaseId!,
          action: 'duplicated',
          name: duplicated.name,
        );
      } else {
        ref.invalidate(savedSequenceSummariesProvider);
      }

      if (context.mounted && _isCurrentAuthority(authority)) {
        context.showSuccessSnackBar('Duplicated "${_summary.name}"');
      }
    } catch (e) {
      if (context.mounted && _isCurrentAuthority(authority)) {
        context.showErrorSnackBar('Failed to duplicate: $e');
      }
    }
  }

  /// Export the saved sequence to a JSON file. Mirrors the toolbar's
  /// export path: on a blocking validation failure, surface the structured
  /// issue dialog with a "force export anyway" escape hatch.
  Future<void> _exportSequence(BuildContext context) async {
    final authority = ref.read(backendProvider);
    final repository = ref.read(sequenceRepositoryProvider);
    final sequence = await _loadFullSequence(
      context,
      authority: authority,
      repository: repository,
    );
    if (sequence == null ||
        !context.mounted ||
        !_isCurrentAuthority(authority)) {
      return;
    }
    final fileService = ref.read(sequenceFileServiceProvider);
    try {
      final exportedPath = await fileService.exportSequence(sequence);
      if (exportedPath != null &&
          context.mounted &&
          _isCurrentAuthority(authority)) {
        // On a phone the file landed in the app sandbox, so a snackbar naming
        // it would be a file the user can never open — hand it to the share
        // sheet instead. Live before this: "Failed to export:
        // UnimplementedError: getSavePath() has not been implemented."
        await revealExportedFile(
          context,
          exportedPath,
          subject: 'Nightshade sequence: ${sequence.name}',
          desktopMessage: 'Exported "${sequence.name}"',
        );
      }
    } on SequenceValidationFailedException catch (e) {
      if (!context.mounted || !_isCurrentAuthority(authority)) return;
      final force = await showValidationIssueDialog(
        context,
        issues: e.issues,
        operationName: 'Export Sequence',
        forceLabel: 'Force export anyway',
      );
      if (!force || !context.mounted || !_isCurrentAuthority(authority)) {
        return;
      }
      try {
        final exportedPath = await fileService.exportSequence(
          sequence,
          forceExport: true,
        );
        if (exportedPath != null &&
            context.mounted &&
            _isCurrentAuthority(authority)) {
          await revealExportedFile(
            context,
            exportedPath,
            subject: 'Nightshade sequence: ${sequence.name}',
            desktopMessage: 'Exported "${sequence.name}" (forced)',
          );
        }
      } catch (err) {
        if (context.mounted && _isCurrentAuthority(authority)) {
          context.showErrorSnackBar('Failed to export: $err');
        }
      }
    } catch (e) {
      if (context.mounted && _isCurrentAuthority(authority)) {
        context.showErrorSnackBar('Failed to export: $e');
      }
    }
  }

  void _deleteSequence(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _DeleteSequenceDialog(
        colors: widget.colors,
        sequenceId: _summary.id,
        sequenceName: _summary.name,
      ),
    );
  }
}

class _DeleteSequenceDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final int sequenceId;
  final String sequenceName;

  const _DeleteSequenceDialog({
    required this.colors,
    required this.sequenceId,
    required this.sequenceName,
  });

  @override
  ConsumerState<_DeleteSequenceDialog> createState() =>
      _DeleteSequenceDialogState();
}

class _DeleteSequenceDialogState extends ConsumerState<_DeleteSequenceDialog> {
  late final NightshadeBackend _authority;
  late final SequenceRepository _repository;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _authority = ref.read(backendProvider);
    _repository = ref.read(sequenceRepositoryProvider);
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next) || !mounted) return;
        context.showWarningSnackBar(
          'The connected host changed. Sequence deletion cancelled.',
        );
        closeAuthorityBoundDialog(context);
      },
    );
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!identical(ref.read(backendProvider), _authority)) return;
    setState(() => _isDeleting = true);
    try {
      await _repository.deleteSequence(widget.sequenceId);
      if (!mounted || !identical(ref.read(backendProvider), _authority)) return;

      notifySequenceCatalogChanged(
        ref,
        sequenceId: widget.sequenceId,
        action: 'deleted',
        name: widget.sequenceName,
      );
      context.showSuccessSnackBar('Deleted "${widget.sequenceName}"');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted || !identical(ref.read(backendProvider), _authority)) return;
      setState(() => _isDeleting = false);
      context.showErrorSnackBar('Failed to delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDeleting,
      child: AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        title: Text(
          'Delete Sequence',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            context,
            designMaxWidth: 400,
          ),
          child: Text(
            'Are you sure you want to delete "${widget.sequenceName}"? '
            'This action cannot be undone.',
            style: TextStyle(color: widget.colors.textSecondary),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: _isDeleting ? null : _delete,
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            isLoading: _isDeleting,
          ),
        ],
      ),
    );
  }
}

/// Star toggle that flips the favorite flag for a sequence. Filled (warning
/// color) when favorited, outline-muted otherwise.
class _FavoriteToggle extends StatelessWidget {
  final NightshadeColors colors;
  final bool isFavorite;
  final VoidCallback onPressed;

  const _FavoriteToggle({
    required this.colors,
    required this.isFavorite,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          LucideIcons.star,
          size: 18,
          color: isFavorite ? colors.warning : colors.textMuted,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}
