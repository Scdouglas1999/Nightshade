import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../sequencer_screen.dart';
import 'package:nightshade_app/utils/snackbar_helper.dart';
import '../widgets/quick_start_wizard_dialog.dart';

// ---------------------------------------------------------------------------
// File split: the rest of this library lives in `templates_tab_parts/`.
// Built-in template data (large hand-built node-tree literals) is kept in
// `_builtin_templates.dart` because it is data, not widgets; the remaining
// part files group widgets by purpose. All parts share this file's library
// scope via the `part` mechanism.
// ---------------------------------------------------------------------------

part 'templates_tab_parts/_builtin_templates.dart';
part 'templates_tab_parts/_header_and_filters.dart';
part 'templates_tab_parts/_template_card.dart';
part 'templates_tab_parts/_save_template_dialog.dart';


/// Provider for templates list - loads from database with built-in fallbacks
// autoDispose: list is only consumed by TemplatesTab; refetching the DB on
// revisit is cheap and reflects any templates the user just saved or
// imported elsewhere (audit-dart §1b).
final sequenceTemplatesProvider =
    FutureProvider.autoDispose<List<Sequence>>((ref) async {
  final repository = ref.watch(sequenceRepositoryProvider);

  // Load templates from database
  final dbTemplates = await repository.loadAllTemplates();

  // If no templates exist, return built-in templates
  if (dbTemplates.isEmpty) {
    return _getBuiltInTemplates();
  }

  return dbTemplates;
});

/// Search provider for templates
// autoDispose: filter input is tab-scoped (audit-dart §1b).
final templateSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Selected template category
// autoDispose: category filter is tab-scoped; default (All / null) is
// appropriate on each visit (audit-dart §1b).
final templateCategoryProvider =
    StateProvider.autoDispose<String?>((ref) => null);

const _templateCategoryOptions = <MapEntry<String?, String>>[
  MapEntry<String?, String>(null, 'All'),
  MapEntry<String?, String>('beginner', 'Beginner'),
  MapEntry<String?, String>('intermediate', 'Intermediate'),
  MapEntry<String?, String>('advanced', 'Advanced'),
  MapEntry<String?, String>('specialized', 'Specialized'),
];

String _inferTemplateCategory(Sequence template) {
  final name = template.name.toLowerCase();

  if (name.contains('first light') ||
      name.contains('one-shot') ||
      name.contains('osc') ||
      name.contains('quick') ||
      name.contains('beginner')) {
    return 'beginner';
  }

  if (name.contains('unattended') ||
      name.contains('all-night') ||
      name.contains('remote observatory') ||
      name.contains('mosaic multi-panel')) {
    return 'advanced';
  }

  if (name.contains('planetary') ||
      name.contains('solar') ||
      name.contains('lunar') ||
      name.contains('comet') ||
      name.contains('asteroid')) {
    return 'specialized';
  }

  return 'intermediate';
}

class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final templatesAsync = ref.watch(sequenceTemplatesProvider);
    final searchQuery = ref.watch(templateSearchProvider);
    final category = ref.watch(templateCategoryProvider);
    final isMobile = Responsive.isMobile(context);
    final snippets = ref.watch(allSnippetsProvider);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        children: [
          // Header
          _TemplatesHeader(colors: colors),

          const SizedBox(height: 24),

          // Snippet summary card (shows count and quick access hint)
          if (!isMobile && snippets.isNotEmpty)
            _SnippetSummaryCard(colors: colors, snippetCount: snippets.length),

          if (!isMobile && snippets.isNotEmpty) const SizedBox(height: 16),

          // Content
          Expanded(
            child: templatesAsync.when(
              data: (templates) {
                var filtered = templates;

                // Apply search filter
                if (searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((t) =>
                          t.name
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()) ||
                          t.description
                              .toLowerCase()
                              .contains(searchQuery.toLowerCase()))
                      .toList();
                }

                // Apply category filter
                if (category != null && category.isNotEmpty) {
                  filtered = filtered
                      .where((template) =>
                          _inferTemplateCategory(template) == category)
                      .toList();
                }

                if (filtered.isEmpty) {
                  final hasSearch = searchQuery.isNotEmpty;
                  return EmptyState(
                    icon: hasSearch ? LucideIcons.searchX : LucideIcons.fileStack,
                    title: hasSearch ? 'No templates found' : 'No templates yet',
                    body: hasSearch
                        ? 'Try a different search term'
                        : 'Save your sequences as templates for easy reuse',
                  );
                }

                // Adapt grid for different screen sizes
                final gridSpacing = isMobile ? 12.0 : 20.0;
                final maxExtent = isMobile ? 320.0 : 400.0;

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxExtent,
                    childAspectRatio: isMobile ? 1.2 : 1.3,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: gridSpacing,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _TemplateCard(
                      colors: colors,
                      template: filtered[index],
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
                      'Failed to load templates',
                      style: TextStyle(color: colors.textPrimary, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
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
