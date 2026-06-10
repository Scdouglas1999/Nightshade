// Part of ../templates_tab.dart -- extracted for maintainability.
//
// Dialog used to save the current sequence as a template, including the target-selection option chips.
part of '../templates_tab.dart';

class _SaveTemplateDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SaveTemplateDialog({
    required this.colors,
    required this.sequence,
  });

  @override
  ConsumerState<_SaveTemplateDialog> createState() =>
      _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends ConsumerState<_SaveTemplateDialog> {
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

  Future<void> _saveTemplate() async {
    if (_nameController.text.trim().isEmpty) {
      context.showErrorSnackBar('Please enter a template name');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(sequenceRepositoryProvider);

      // Create a new sequence with the template name and description
      final templateSequence = Sequence.create(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: widget.sequence.nodes,
        rootNodeId: widget.sequence.rootNodeId,
        isTemplate: true,
      );

      final savedId =
          await repository.saveSequence(templateSequence, isTemplate: true);

      notifySequenceCatalogChanged(
        ref,
        sequenceId: savedId,
        action: 'saved',
        name: templateSequence.name,
        isTemplate: true,
      );
      ref.invalidate(sequenceTemplatesProvider);

      if (mounted) {
        Navigator.pop(context);

        context
            .showSuccessSnackBar('Template "${_nameController.text}" saved!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save template: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 450,
          designMaxHeight: 500,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: SingleChildScrollView(
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
                          'Save as Template',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize18,
                            fontWeight: FontWeight.w700,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Save this sequence for later reuse',
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
                  'Template Name',
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
                      hintText: 'Enter template name',
                      hintStyle: TextStyle(
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Description field
                Text(
                  'Description',
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
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize14,
                      color: widget.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Describe what this template is for...',
                      hintStyle: TextStyle(
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Info about current sequence
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusLg),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.info,
                          size: 16, color: widget.colors.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This will save ${widget.sequence.nodes.length} nodes from the current sequence.',
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
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      label: 'Cancel',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                    ),
                    const SizedBox(width: 12),
                    NightshadeButton(
                      label: _isSaving ? 'Saving...' : 'Save Template',
                      icon: _isSaving ? LucideIcons.loader : LucideIcons.save,
                      onPressed: _isSaving ? null : _saveTemplate,
                      size: ButtonSize.small,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable target option for the target selection dialog
class _TargetOption extends StatefulWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final VoidCallback onTap;

  const _TargetOption({
    required this.colors,
    required this.target,
    required this.onTap,
  });

  @override
  State<_TargetOption> createState() => _TargetOptionState();
}

class _TargetOptionState extends State<_TargetOption> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? NightshadeDecorations.tintedBadge(
                    widget.colors.warning,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusLg),
                  ).color
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            border: Border.all(
              color: _isHovered ? widget.colors.warning : widget.colors.border,
              width: _isHovered ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: NightshadeDecorations.statusChip(
                  widget.colors.warning,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  bordered: false,
                ),
                child: Icon(
                  LucideIcons.target,
                  size: 16,
                  color: widget.colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.target.targetName,
                      style: NightshadeTypography.labelStrong
                          .copyWith(color: widget.colors.textPrimary),
                    ),
                    Text(
                      'RA: ${_formatRA(widget.target.raHours)} · Dec: ${_formatDec(widget.target.decDegrees)}',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: _isHovered
                    ? widget.colors.warning
                    : widget.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '';
    return '$sign${decDegrees.toStringAsFixed(1)}°';
  }
}
