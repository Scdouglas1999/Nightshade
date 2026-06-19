part of '../sequence_library_tab.dart';

/// Add / remove library tags for a saved sequence.
///
/// Persists through [SequenceRepository.setTags] (which trims, drops blanks and
/// de-duplicates) and invalidates the summaries provider so the card, the
/// filter row and the tag universe all refresh.
class _TagEditorDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final int sequenceId;
  final String sequenceName;
  final List<String> initialTags;

  const _TagEditorDialog({
    required this.colors,
    required this.sequenceId,
    required this.sequenceName,
    required this.initialTags,
  });

  @override
  ConsumerState<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends ConsumerState<_TagEditorDialog> {
  late final List<String> _tags;
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tags = [...widget.initialTags];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    if (!_tags.any((t) => t.toLowerCase() == value.toLowerCase())) {
      setState(() => _tags.add(value));
    }
    _controller.clear();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(sequenceRepositoryProvider).setTags(
            widget.sequenceId,
            _tags,
          );
      ref.invalidate(savedSequenceSummariesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showSuccessSnackBar('Updated tags for "${widget.sequenceName}"');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showErrorSnackBar('Failed to save tags: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: [
          Icon(LucideIcons.tags, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit Tags',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 440,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.sequenceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addTag(),
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add a tag',
                      isDense: true,
                      prefixIcon: Icon(LucideIcons.tag,
                          size: 16, color: colors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Add',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: _addTag,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_tags.isEmpty)
              Text(
                'No tags yet.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in _tags)
                    Container(
                      padding: const EdgeInsets.only(
                          left: 10, right: 4, top: 4, bottom: 4),
                      decoration: NightshadeDecorations.tintedBadge(
                        colors.primary,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tag,
                            style: NightshadeTypography.labelStrongSm
                                .copyWith(color: colors.primary),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() => _tags.remove(tag)),
                            child: Icon(LucideIcons.x,
                                size: 14, color: colors.primary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
        NightshadeButton(
          label: _saving ? 'Saving…' : 'Save',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
