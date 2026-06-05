// Part of ../templates_tab.dart -- extracted for maintainability.
//
// The per-template card with its hover state, instantiate/duplicate/edit/delete actions, body chips, and the _SmallIconButton primitive used for the card's icon-only secondary actions.
part of '../templates_tab.dart';

class _TemplateCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence template;

  const _TemplateCard({
    required this.colors,
    required this.template,
  });

  @override
  ConsumerState<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends ConsumerState<_TemplateCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  IconData _getTemplateIcon() {
    final name = widget.template.name.toLowerCase();
    // Beginner templates
    if (name.contains('first light')) return LucideIcons.sparkles;
    if (name.contains('osc') || name.contains('one-shot')) {
      return LucideIcons.camera;
    }
    if (name.contains('quick')) return LucideIcons.zap;
    if (name.contains('beginner')) return LucideIcons.graduationCap;
    // Intermediate templates
    if (name.contains('ha-oiii') || name.contains('bicolor')) {
      return LucideIcons.contrast;
    }
    if (name.contains('sho') || name.contains('hubble')) {
      return LucideIcons.waves;
    }
    if (name.contains('lrgb')) return LucideIcons.palette;
    if (name.contains('narrowband')) return LucideIcons.waves;
    if (name.contains('multi-target')) return LucideIcons.list;
    if (name.contains('mosaic')) return LucideIcons.layoutGrid;
    // Specialized templates
    if (name.contains('planetary')) return LucideIcons.orbit;
    if (name.contains('unattended') || name.contains('all-night')) {
      return LucideIcons.moon;
    }
    if (name.contains('comet') || name.contains('asteroid')) {
      return LucideIcons.move;
    }
    if (name.contains('solar')) return LucideIcons.sun;
    if (name.contains('lunar')) return LucideIcons.moonStar;
    if (name.contains('remote') || name.contains('observatory')) {
      return LucideIcons.radio;
    }
    return LucideIcons.fileStack;
  }

  Color _getTemplateColor() {
    final name = widget.template.name.toLowerCase();
    // Beginner templates - green/info
    if (name.contains('first light')) return widget.colors.success;
    if (name.contains('osc') || name.contains('one-shot')) {
      return widget.colors.info;
    }
    if (name.contains('quick')) return widget.colors.success;
    if (name.contains('beginner')) return widget.colors.info;
    // Intermediate templates - primary/accent
    if (name.contains('ha-oiii') || name.contains('bicolor')) {
      return widget.colors.accent;
    }
    if (name.contains('sho') || name.contains('hubble')) {
      return widget.colors.accent;
    }
    if (name.contains('lrgb')) return widget.colors.primary;
    if (name.contains('narrowband')) return widget.colors.accent;
    if (name.contains('multi-target')) return widget.colors.primary;
    if (name.contains('mosaic')) return widget.colors.warning;
    // Specialized templates - warning
    if (name.contains('planetary')) return widget.colors.warning;
    if (name.contains('unattended') || name.contains('all-night')) {
      return widget.colors.warning;
    }
    if (name.contains('comet') || name.contains('asteroid')) {
      return widget.colors.warning;
    }
    if (name.contains('solar')) return widget.colors.warning;
    if (name.contains('lunar')) return widget.colors.warning;
    if (name.contains('remote') || name.contains('observatory')) {
      return widget.colors.warning;
    }
    return widget.colors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    final templateColor = _getTemplateColor();
    // Trust-patch §B: "Use Template" calls mergeTemplateNodes /
    // loadSequence — both replace tree state and must be gated. "Edit"
    // also calls loadSequence, "Duplicate" goes through the repository
    // (not the editor) so it stays enabled. Delete operates on the
    // template database row, not the active sequence, so also stays
    // enabled. We grey out the whole card's primary action while
    // running so the user can't accidentally clobber their in-flight run.
    final canEdit = ref.watch(canEditSequenceProvider);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _animController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _animController.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(
              color: _isHovered
                  ? templateColor.withValues(alpha: 0.6)
                  : widget.colors.border,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: null,
          ),
          child: InkWell(
            onTap: canEdit ? () => _useTemplate(context) : null,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and actions
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: NightshadeDecorations.tintedBadge(
                          templateColor,
                          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                        ),
                        child: Icon(
                          _getTemplateIcon(),
                          size: 24,
                          color: templateColor,
                        ),
                      ),
                      const Spacer(),
                      if (_isHovered) ...[
                        // "Duplicate" operates on the template DB row,
                        // not the active sequence — stays enabled.
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.copy,
                          tooltip: 'Duplicate',
                          onPressed: () => _duplicateTemplate(context),
                        ),
                        const SizedBox(width: 4),
                        // "Edit" calls loadSequence — this replaces the
                        // active sequence and MUST be gated.
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.pencil,
                          tooltip: canEdit
                              ? 'Edit'
                              : 'Edit (locked while sequence is running)',
                          onPressed: canEdit
                              ? () => _editTemplate(context)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        // Delete removes the template from the library,
                        // not the active sequence — stays enabled.
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.trash2,
                          tooltip: 'Delete',
                          color: widget.colors.error,
                          onPressed: () => _deleteTemplate(context),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.template.name,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize16,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Description
                  Expanded(
                    child: Text(
                      widget.template.description.isEmpty
                          ? 'No description'
                          : widget.template.description,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: widget.colors.textSecondary,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Footer
                  Row(
                    children: [
                      // Stats
                      Row(
                        children: [
                          Icon(LucideIcons.layoutList,
                              size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.template.nodes.length} nodes',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          Icon(LucideIcons.calendar,
                              size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMd().format(widget.template.createdAt),
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Use button
                      AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: templateColor,
                            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.play,
                                  size: 12, color: onPrimary),
                              const SizedBox(width: 6),
                              Text(
                                'Use',
                                style: NightshadeTypography.labelStrongSm.copyWith(color: onPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _useTemplate(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);

    // Check if there are existing targets in the current sequence
    final existingTargets = currentSequence?.targetHeaders ?? [];

    if (existingTargets.length > 1) {
      // Multiple targets - prompt user to choose
      _showTargetSelectionDialog(context, existingTargets);
    } else if (existingTargets.length == 1) {
      // Single target - merge directly
      _applyTemplateToTarget(context, existingTargets.first);
    } else {
      // No existing targets - create a new sequence from template
      _createNewSequenceFromTemplate(context);
    }
  }

  void _showTargetSelectionDialog(
      BuildContext context, List<TargetHeaderNode> targets) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
        title: Row(
          children: [
            Icon(LucideIcons.target, size: 20, color: widget.colors.warning),
            const SizedBox(width: 12),
            Text(
              'Select Target',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            dialogContext,
            designMaxWidth: 480,
            designMaxHeight: 520,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which target should "${widget.template.name}" be added to?',
                  style: TextStyle(color: widget.colors.textSecondary),
                ),
                const SizedBox(height: 16),
                ...targets.map((target) => _TargetOption(
                      colors: widget.colors,
                      target: target,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _applyTemplateToTarget(context, target);
                      },
                    )),
              ],
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  void _applyTemplateToTarget(BuildContext context, TargetHeaderNode target) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    try {
      sequenceNotifier.mergeTemplateNodes(
        templateNodes: widget.template.nodes,
        templateRootId: widget.template.rootNodeId,
        targetId: target.id,
      );
    } on SequenceLockedException catch (e) {
      // Trust-patch §B: the InkWell that triggers this is gated by
      // canEditSequenceProvider, but a Start race can still slip a
      // running state under us. Surface to user instead of red overlay.
      context.showErrorSnackBar(e.message);
      return;
    }

    // Switch to the Builder tab so user can see the result
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showSuccessSnackBar(
        'Added "${widget.template.name}" to ${target.targetName}');
  }

  void _createNewSequenceFromTemplate(BuildContext context) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    // Generate new IDs for all nodes
    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    // Clone nodes with new IDs and updated references
    for (final entry in widget.template.nodes.entries) {
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

    // Get the new root node ID
    final newRootId = widget.template.rootNodeId != null
        ? idMapping[widget.template.rootNodeId]
        : null;

    final newSequence = Sequence.create(
      name: '${widget.template.name} - Copy',
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    // Load the sequence. Template instantiation is an explicit user
    // action ("Use Template" button); the editor's unsaved-changes guard
    // would be noise here, so we discard any in-flight edits.
    sequenceNotifier.loadSequence(newSequence, discardUnsaved: true);

    // Switch to the Builder tab so user can see the loaded sequence
    ref.read(sequencerTabProvider.notifier).state = 0;

    context
        .showSuccessSnackBar('Created sequence from "${widget.template.name}"');
  }

  void _editTemplate(BuildContext context) {
    // Load the template for editing and switch to Builder tab
    // Create a copy so we don't modify the original template
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    for (final entry in widget.template.nodes.entries) {
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

    final newRootId = widget.template.rootNodeId != null
        ? idMapping[widget.template.rootNodeId]
        : null;

    final editableSequence = Sequence.create(
      name: widget.template.name,
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    // "Edit Template" is a destructive switch from whatever the user was
    // working on; treat the click as confirmation per the wizard pattern.
    ref
        .read(currentSequenceProvider.notifier)
        .loadSequence(editableSequence, discardUnsaved: true);
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showInfoSnackBar('Editing "${widget.template.name}"');
  }

  Future<void> _duplicateTemplate(BuildContext context) async {
    // Check if template has a database ID
    final dbId = widget.template.databaseId;
    if (dbId != null) {
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        final duplicated = await repository.duplicateSequence(
            dbId, '${widget.template.name} (Copy)');

        if (duplicated?.databaseId != null) {
          notifySequenceCatalogChanged(
            ref,
            sequenceId: duplicated!.databaseId!,
            action: 'duplicated',
            name: duplicated.name,
            isTemplate: true,
          );
        }
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    } else {
      // Built-in template - save a copy to database
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        final newTemplate = Sequence.create(
          name: '${widget.template.name} (Copy)',
          description: widget.template.description,
          nodes: widget.template.nodes,
          rootNodeId: widget.template.rootNodeId,
          isTemplate: true,
        );
        final savedId =
            await repository.saveSequence(newTemplate, isTemplate: true);

        notifySequenceCatalogChanged(
          ref,
          sequenceId: savedId,
          action: 'created',
          name: newTemplate.name,
          isTemplate: true,
        );
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    }
  }

  void _deleteTemplate(BuildContext context) {
    // Check if this is a built-in template (no database ID)
    final dbId = widget.template.databaseId;
    if (dbId == null) {
      context.showInfoSnackBar('Built-in templates cannot be deleted');
      return;
    }

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
        title: Text(
          'Delete Template',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            dialogContext,
            designMaxWidth: 400,
          ),
          child: Text(
            'Are you sure you want to delete "${widget.template.name}"? This action cannot be undone.',
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
                  name: widget.template.name,
                  isTemplate: true,
                );
                ref.invalidate(sequenceTemplatesProvider);

                if (context.mounted) {
                  context
                      .showSuccessSnackBar('Deleted "${widget.template.name}"');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to delete template: $e');
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

class _SmallIconButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final Color? color;
  // Nullable so the template card can gray out the "Edit" pencil while
  // the sequence is running. Other callers may still pass a non-null
  // callback unchanged.
  final VoidCallback? onPressed;

  const _SmallIconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;
    final disabled = widget.onPressed == null;
    final iconColor = disabled
        ? widget.colors.textMuted.withValues(alpha: 0.4)
        : (_isHovered ? color : widget.colors.textMuted);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter:
            disabled ? null : (_) => setState(() => _isHovered = true),
        onExit:
            disabled ? null : (_) => setState(() => _isHovered = false),
        cursor: disabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: !disabled && _isHovered
                  ? NightshadeDecorations.tintedBadge(
                      color,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                    ).color
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}