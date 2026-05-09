import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Toolbar shown when multi-select mode is active.
/// Provides batch operations: Copy, Paste, Delete, Enable, Disable.
class BatchOperationsToolbar extends ConsumerWidget {
  final NightshadeColors colors;

  const BatchOperationsToolbar({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(multiSelectedNodeIdsProvider);
    final clipboard = ref.watch(nodeCopyClipboardProvider);
    final hasClipboard = clipboard != null && clipboard.isNotEmpty;
    final count = selectedIds.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Selection count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Copy
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.copy,
            label: 'Copy',
            onPressed: () {
              ref.read(multiSelectedNodeIdsProvider.notifier).copySelected();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$count node(s) copied'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: colors.info,
                ),
              );
            },
          ),

          const SizedBox(width: 4),

          // Paste
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.clipboardPaste,
            label: 'Paste',
            enabled: hasClipboard,
            onPressed: hasClipboard
                ? () {
                    ref
                        .read(multiSelectedNodeIdsProvider.notifier)
                        .pasteFromClipboard();
                  }
                : null,
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: 8),

          // Enable
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.eye,
            label: 'Enable',
            onPressed: () {
              ref.read(multiSelectedNodeIdsProvider.notifier).enableSelected();
            },
          ),

          const SizedBox(width: 4),

          // Disable
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.eyeOff,
            label: 'Disable',
            onPressed: () {
              ref.read(multiSelectedNodeIdsProvider.notifier).disableSelected();
            },
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: 8),

          // Delete
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.trash2,
            label: 'Delete',
            color: colors.error,
            onPressed: () {
              _confirmDelete(context, ref, count);
            },
          ),

          const Spacer(),

          // Clear selection
          _ToolbarButton(
            colors: colors,
            icon: LucideIcons.x,
            label: 'Clear',
            onPressed: () {
              ref.read(multiSelectedNodeIdsProvider.notifier).clear();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, int count) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Delete $count node(s)?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'This will remove the selected nodes and all their children. This action can be undone with Ctrl+Z.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              ref
                  .read(multiSelectedNodeIdsProvider.notifier)
                  .deleteSelected();
              Navigator.pop(context);
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

class _ToolbarButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? color;

  const _ToolbarButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.onPressed,
    this.enabled = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? colors.textSecondary;
    final isEnabled = enabled && onPressed != null;

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isEnabled
                      ? effectiveColor
                      : colors.textMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                        ? effectiveColor
                        : colors.textMuted.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
