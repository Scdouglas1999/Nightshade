import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ObservingListsSettings extends ConsumerWidget {
  const ObservingListsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final listsAsync = ref.watch(observingListsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Observing Lists',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize18,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showCreateDialog(context, ref),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New List'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Manage your curated target collections for observing sessions.',
            style: TextStyle(fontSize: NightshadeTypography.fontSize13, color: colors.textSecondary),
          ),
          const SizedBox(height: 24),

          listsAsync.when(
            data: (lists) {
              if (lists.isEmpty) {
                return _buildEmptyState(context, ref, colors);
              }
              return Column(
                children: lists.map((list) {
                  return _ObservingListManagementCard(
                    list: list,
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Error loading lists: $e',
                  style: TextStyle(color: colors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.list, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No observing lists yet',
              style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Create observing lists to organize your targets.\n'
              'You can add objects from the planetarium view.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: NightshadeTypography.fontSize13, color: colors.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Create Your First List'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Observing List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'List Name',
                hintText: 'e.g., Winter Galaxies',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final desc = descController.text.trim();
              await ref.read(observingListNotifierProvider.notifier).createList(
                    name: name,
                    description: desc.isEmpty ? null : desc,
                  );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ObservingListManagementCard extends ConsumerWidget {
  final ObservingList list;

  const _ObservingListManagementCard({
    required this.list,
    });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final itemsAsync = ref.watch(observingListItemsProvider(list.id));
    final itemCount = itemsAsync.valueOrNull?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.list, size: 18, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (list.description != null &&
                        list.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          list.description!,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '$itemCount object${itemCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ActionChip(
                icon: LucideIcons.pencil,
                label: 'Rename',
                onTap: () => _showRenameDialog(context, ref),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: LucideIcons.copy,
                label: 'Duplicate',
                onTap: () async {
                  await ref
                      .read(observingListNotifierProvider.notifier)
                      .duplicateList(list.id);
                },
              ),
              const Spacer(),
              _ActionChip(
                icon: LucideIcons.trash2,
                label: 'Delete',
                isDestructive: true,
                onTap: () => _showDeleteConfirmation(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: list.name);
    final descController = TextEditingController(text: list.description ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'List Name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final desc = descController.text.trim();
              final notifier = ref.read(observingListNotifierProvider.notifier);
              await notifier.renameList(list.id, name);
              await notifier.updateDescription(
                  list.id, desc.isEmpty ? null : desc);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: Text(
          'This will permanently delete "${list.name}" and all its items. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          NightshadeButton(
            onPressed: () async {
              await ref
                  .read(observingListNotifierProvider.notifier)
                  .deleteList(list.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            label: 'Delete',
            variant: ButtonVariant.destructive,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final color = isDestructive ? colors.error : colors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: isDestructive
            ? NightshadeDecorations.emphasisSurface(
                colors.error,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              )
            : NightshadeDecorations.iconChip(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: NightshadeTypography.labelQuiet.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
