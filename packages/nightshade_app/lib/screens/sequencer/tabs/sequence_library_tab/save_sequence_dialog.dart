part of '../sequence_library_tab.dart';

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

      final sequenceToSave = Sequence.create(
        databaseId: widget.sequence.databaseId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: widget.sequence.nodes,
        rootNodeId: widget.sequence.rootNodeId,
        isTemplate: false,
      );

      final savedId =
          await repository.saveSequence(sequenceToSave, isTemplate: false);

      notifySequenceCatalogChanged(
        ref,
        sequenceId: savedId,
        action: 'saved',
        name: sequenceToSave.name,
      );

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
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 450,
        ),
        child: Padding(
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
                    decoration: NightshadeDecorations.tintedBadge(
                      widget.colors.primary,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusLg),
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
                          fontSize: NightshadeTypography.fontSize18,
                          fontWeight: FontWeight.w700,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Save to your sequence library',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
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
                style: NightshadeTypography.h6
                    .copyWith(color: widget.colors.textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusLg),
                  border: Border.all(color: widget.colors.border),
                ),
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
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
                style: NightshadeTypography.h6
                    .copyWith(color: widget.colors.textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusLg),
                  border: Border.all(color: widget.colors.border),
                ),
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusLg),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: widget.colors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Saving ${widget.sequence.nodes.length} nodes',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
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
      ),
    );
  }
}
