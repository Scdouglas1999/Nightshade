import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../sequencer_screen.dart';
import '../../../utils/snackbar_helper.dart';

part 'sequence_library_tab/library_header.dart';
part 'sequence_library_tab/action_button.dart';
part 'sequence_library_tab/sequence_card.dart';
part 'sequence_library_tab/supporting_widgets.dart';
part 'sequence_library_tab/save_sequence_dialog.dart';

/// Provider for sequences list - loads from database
// autoDispose: list is only consumed by SequenceLibraryTab; refetching the
// DB on revisit is cheap and ensures we never show stale entries after the
// user edited a sequence elsewhere (audit-dart §1b).
// Defined in nightshade_core: savedSequencesProvider (sequence_catalog_sync.dart)

/// Search provider for sequences
// autoDispose: filter input is tab-scoped; clearing it on revisit matches
// user expectation (audit-dart §1b).
final sequenceSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Sort order for sequences
enum SequenceSortOrder { name, dateModified, dateCreated, nodeCount }

/// Provider for sort order
// autoDispose: tab-scoped preference; default (dateModified) is appropriate
// on each visit (audit-dart §1b).
final sequenceSortOrderProvider = StateProvider.autoDispose<SequenceSortOrder>(
  (ref) => SequenceSortOrder.dateModified,
);

class SequenceLibraryTab extends ConsumerWidget {
  const SequenceLibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
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
                  final hasSearch = searchQuery.isNotEmpty;
                  return EmptyState(
                    icon: hasSearch
                        ? LucideIcons.searchX
                        : LucideIcons.folderOpen,
                    title:
                        hasSearch ? 'No sequences found' : 'No saved sequences',
                    body: hasSearch
                        ? 'Try a different search term'
                        : 'Save your sequences to access them later',
                    action: hasSearch
                        ? null
                        : NightshadeCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            borderRadius: NightshadeTokens.radiusInline8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.lightbulb,
                                    size: 14, color: colors.warning),
                                const SizedBox(width: 8),
                                Text(
                                  'Tip: Use "Save Current" to save your sequence',
                                  style: TextStyle(
                                    fontSize: NightshadeTypography.fontSize12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  );
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
                      style: TextStyle(color: colors.textPrimary, fontSize: NightshadeTypography.fontSize16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize12),
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
