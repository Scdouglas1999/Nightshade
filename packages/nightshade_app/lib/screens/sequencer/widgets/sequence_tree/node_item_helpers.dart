// ignore_for_file: invalid_use_of_protected_member
// Part of ../sequence_tree.dart -- extracted for maintainability.
//
// Save-as-snippet dialog plus icon, colour and accessibility helpers of _NodeItemState.
part of '../sequence_tree.dart';

extension _NodeItemHelpers on _NodeItemState {
  void _showSaveAsSnippetDialog(
      BuildContext context, WidgetRef ref, SequenceNode node) {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    final nameController = TextEditingController(text: node.name);
    final descController = TextEditingController();
    SnippetCategory selectedCategory = SnippetCategory.custom;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: widget.colors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          ),
          title: Row(
            children: [
              Icon(LucideIcons.bookmark,
                  size: 20, color: widget.colors.primary),
              const SizedBox(width: 12),
              Text(
                'Save as Template',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 360,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name',
                    style: NightshadeTypography.labelSm
                        .copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize14,
                      color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Template name',
                    hintStyle: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Description',
                    style: NightshadeTypography.labelSm
                        .copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize14,
                      color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'What does this template do?',
                    hintStyle: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Category',
                    style: NightshadeTypography.labelSm
                        .copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: AccessibleDropdown<SnippetCategory>(
                      value: selectedCategory,
                      isExpanded: true,
                      dropdownColor: widget.colors.surfaceOverlay,
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14,
                          color: widget.colors.textPrimary),
                      items: SnippetCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.name[0].toUpperCase() +
                              cat.name.substring(1)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedCategory = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
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
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a template name'),
                      backgroundColor: widget.colors.error,
                    ),
                  );
                  return;
                }

                final messenger = ScaffoldMessenger.of(context);
                try {
                  // Capture the full multi-selection when present, else just
                  // this node. createSnippetFromSelection requires the nodes
                  // share a parent / be contiguous; failures land in catch.
                  final multi = ref.read(multiSelectedNodeIdsProvider);
                  final nodeIds = multi.isNotEmpty ? multi.toList() : [node.id];
                  final snippet = createSnippetFromSelection(
                    name: name,
                    description: descController.text.trim().isEmpty
                        ? 'Custom template from ${node.nodeType}'
                        : descController.text.trim(),
                    category: selectedCategory,
                    iconName: node.iconName,
                    nodeIds: nodeIds,
                    sequence: sequence,
                  );

                  await ref
                      .read(customSnippetsProvider.notifier)
                      .addSnippet(snippet);

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }

                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Template "$name" created successfully'),
                        backgroundColor: widget.colors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Failed to create template: $e'),
                        backgroundColor: widget.colors.error,
                      ),
                    );
                  }
                }
              },
              label: 'Save',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (widget.node.iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      case 'list':
        return LucideIcons.list;
      // SmartExposure uses the layered-stack glyph.
      case 'layers':
        return LucideIcons.layers;
      default:
        return LucideIcons.box;
    }
  }

  Color _getCategoryColor() {
    switch (widget.node.category) {
      case NodeCategory.instruction:
        return widget.colors.primary;
      case NodeCategory.trigger:
        return widget.colors.warning;
      case NodeCategory.logic:
        return widget.colors.accent;
      case NodeCategory.target:
        return widget.colors.warning;
    }
  }

  Color _getStatusColor() {
    switch (widget.nodeStatus) {
      case NodeStatus.running:
        return widget.colors.info;
      case NodeStatus.success:
        return widget.colors.success;
      case NodeStatus.failure:
        return widget.colors.error;
      case NodeStatus.skipped:
        return widget.colors.textMuted;
      case NodeStatus.cancelled:
        return widget.colors.warning;
      default:
        return Colors.transparent;
    }
  }

  /// Build the plain-text accessibility string for the at-a-glance summary by
  /// joining each fragment's user-visible value. [EditableFragment]s expose
  /// their current [EditableFragment.displayValue]; [StaticFragment]s expose
  /// their text. Fragments are separated by a middle dot so screen readers
  /// announce a single, scannable phrase (e.g. "10 · × · 120s · Ha").
  String _summaryA11yText(List<SummaryFragment> fragments) {
    return fragments
        .map((f) => switch (f) {
              StaticFragment(text: final t) => t.trim(),
              EditableFragment(displayValue: final v) => v.trim(),
            })
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }
}
