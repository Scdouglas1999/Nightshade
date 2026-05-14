import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart';

class ListsTab extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const ListsTab({super.key, required this.colors});

  @override
  ConsumerState<ListsTab> createState() => _ListsTabState();
}

class _ListsTabState extends ConsumerState<ListsTab> {
  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(observingListsProvider);
    final activeListId = ref.watch(activeObservingListIdProvider);

    return listsAsync.when(
      data: (lists) {
        if (lists.isEmpty) {
          return _buildEmptyState();
        }

        // If an active list is selected, show its items
        if (activeListId != null) {
          final activeList =
              lists.where((l) => l.id == activeListId).firstOrNull;
          if (activeList != null) {
            return _buildListItems(activeList);
          }
        }

        // Show all lists
        return _buildListSelector(lists, activeListId);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: widget.colors.error)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.list, size: 48, color: widget.colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No observing lists',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a list to organize your targets for tonight\'s session.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: widget.colors.textMuted),
            ),
            const SizedBox(height: 16),
            _CreateListButton(colors: widget.colors),
          ],
        ),
      ),
    );
  }

  Widget _buildListSelector(List<ObservingList> lists, int? activeListId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Observing Lists',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
              _CreateListButton(colors: widget.colors, compact: true),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: lists.length,
            itemBuilder: (context, index) {
              final list = lists[index];
              return _ObservingListCard(
                list: list,
                colors: widget.colors,
                onTap: () {
                  ref.read(activeObservingListIdProvider.notifier).state =
                      list.id;
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListItems(ObservingList activeList) {
    final itemsAsync = ref.watch(observingListItemsProvider(activeList.id));

    return Column(
      children: [
        // Back button + list name header
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: widget.colors.border),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(LucideIcons.chevronLeft,
                    size: 18, color: widget.colors.textPrimary),
                onPressed: () {
                  ref.read(activeObservingListIdProvider.notifier).state = null;
                },
                tooltip: 'Back to lists',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeList.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (activeList.description != null &&
                        activeList.description!.isNotEmpty)
                      Text(
                        activeList.description!,
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _ExportToSequenceButton(
                listId: activeList.id,
                listName: activeList.name,
                colors: widget.colors,
              ),
            ],
          ),
        ),

        // List items
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus,
                            size: 32, color: widget.colors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'List is empty',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Click objects on the sky and use\n"Add to List" to populate it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ObservingListItemCard(
                    item: item,
                    colors: widget.colors,
                    onTap: () => _lookAtItem(item),
                    onRemove: () => _removeItem(item),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: TextStyle(color: widget.colors.error)),
            ),
          ),
        ),
      ],
    );
  }

  void _lookAtItem(ObservingListItem item) {
    final coords = CelestialCoordinate(ra: item.ra, dec: item.dec);
    ref.read(skyViewStateProvider.notifier).lookAt(coords);
  }

  void _removeItem(ObservingListItem item) {
    ref.read(observingListNotifierProvider.notifier).removeItem(item.id);
  }
}

class _CreateListButton extends ConsumerWidget {
  final NightshadeColors colors;
  final bool compact;

  const _CreateListButton({required this.colors, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) {
      return IconButton(
        icon: Icon(LucideIcons.plus, size: 16, color: colors.primary),
        onPressed: () => _showCreateDialog(context, ref),
        tooltip: 'Create new list',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      );
    }

    return GestureDetector(
      onTap: () => _showCreateDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'Create List',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

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
              onSubmitted: (_) =>
                  _submit(context, ref, nameController, descriptionController),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g., Best galaxies visible in winter',
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
            onPressed: () =>
                _submit(context, ref, nameController, descriptionController),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    TextEditingController nameController,
    TextEditingController descriptionController,
  ) async {
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final description = descriptionController.text.trim();
    final id =
        await ref.read(observingListNotifierProvider.notifier).createList(
              name: name,
              description: description.isEmpty ? null : description,
            );

    if (context.mounted) {
      Navigator.of(context).pop();
      if (id != null) {
        ref.read(activeObservingListIdProvider.notifier).state = id;
      }
    }
  }
}

class _ObservingListCard extends ConsumerWidget {
  final ObservingList list;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _ObservingListCard({
    required this.list,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(observingListItemsProvider(list.id));
    final itemCount = itemsAsync.valueOrNull?.length ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.list, size: 16, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    list.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount object${itemCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 14, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ObservingListItemCard extends StatefulWidget {
  final ObservingListItem item;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ObservingListItemCard({
    required this.item,
    required this.colors,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_ObservingListItemCard> createState() => _ObservingListItemCardState();
}

class _ObservingListItemCardState extends State<_ObservingListItemCard> {
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
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.surfaceAlt
                : widget.colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? widget.colors.primary.withValues(alpha: 0.5)
                  : widget.colors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.item.objectName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                        if (widget.item.catalogId != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  widget.colors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              widget.item.catalogId!,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: widget.colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.item.objectType != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.item.objectType!,
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.item.magnitude != null)
                Text(
                  'mag ${widget.item.magnitude!.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.colors.textMuted,
                  ),
                ),
              if (_isHovered) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.colors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(LucideIcons.x,
                        size: 12, color: widget.colors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportToSequenceButton extends ConsumerWidget {
  final int listId;
  final String listName;
  final NightshadeColors colors;

  const _ExportToSequenceButton({
    required this.listId,
    required this.listName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: 'Export to Sequence',
      child: GestureDetector(
        onTap: () => _exportToSequence(context, ref),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(LucideIcons.listPlus, size: 14, color: colors.primary),
        ),
      ),
    );
  }

  Future<void> _exportToSequence(BuildContext context, WidgetRef ref) async {
    final dao = ref.read(observingListsDaoProvider);
    final items = await dao.getItemsForList(listId);

    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('List is empty, nothing to export.')),
        );
      }
      return;
    }

    // Create a new sequence with target nodes for each item
    final sequencesDao = ref.read(sequencesDaoProvider);
    final sequenceId = await sequencesDao.createSequence(
      SequencesCompanion.insert(
        name: listName,
        isTemplate: const Value(false),
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      // Create a target node for each list item
      final nodeId = 'target_${DateTime.now().microsecondsSinceEpoch}_$i';
      await sequencesDao.createNode(
        SequenceNodesCompanion.insert(
          nodeId: nodeId,
          sequenceId: sequenceId,
          nodeType: 'target',
          specificType: 'target',
          name: item.objectName,
          properties: Value(
            '{"ra": ${item.ra}, "dec": ${item.dec}'
            '${item.catalogId != null ? ', "catalogId": "${item.catalogId}"' : ''}'
            '}',
          ),
          orderIndex: Value(i),
        ),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Created sequence "$listName" with ${items.length} targets'),
        ),
      );
    }
  }
}
