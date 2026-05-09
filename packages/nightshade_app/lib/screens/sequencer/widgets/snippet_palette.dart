import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Palette widget for displaying and managing template snippets.
///
/// Allows users to drag-and-drop pre-built or custom snippet templates
/// into their sequence, as well as create new snippets from selected nodes.
class SnippetPalette extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final Function(TemplateSnippet)? onSnippetDragStart;
  final Function(TemplateSnippet)? onSnippetTap;
  final ScrollController? scrollController;
  final bool isMobileSheet;

  const SnippetPalette({
    super.key,
    required this.colors,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onSnippetDragStart,
    this.onSnippetTap,
    this.scrollController,
    this.isMobileSheet = false,
  });

  @override
  ConsumerState<SnippetPalette> createState() => _SnippetPaletteState();
}

class _SnippetPaletteState extends ConsumerState<SnippetPalette> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'focus':
        return LucideIcons.focus;
      case 'palette':
        return LucideIcons.palette;
      case 'move':
        return LucideIcons.move;
      case 'shield':
        return LucideIcons.shield;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'filter':
        return LucideIcons.filter;
      case 'camera':
        return LucideIcons.camera;
      case 'target':
        return LucideIcons.target;
      case 'clock':
        return LucideIcons.clock;
      case 'settings':
        return LucideIcons.settings;
      case 'star':
        return LucideIcons.star;
      case 'zap':
        return LucideIcons.zap;
      case 'layers':
        return LucideIcons.layers;
      case 'repeat':
        return LucideIcons.repeat;
      case 'grid':
        return LucideIcons.grid;
      default:
        return LucideIcons.puzzle;
    }
  }

  String _getCategoryDisplayName(SnippetCategory category) {
    switch (category) {
      case SnippetCategory.autofocus:
        return 'Autofocus';
      case SnippetCategory.dithering:
        return 'Dithering';
      case SnippetCategory.filterSequence:
        return 'Filter Sequences';
      case SnippetCategory.calibration:
        return 'Calibration';
      case SnippetCategory.safety:
        return 'Safety';
      case SnippetCategory.custom:
        return 'Custom';
    }
  }

  IconData _getCategoryIcon(SnippetCategory category) {
    switch (category) {
      case SnippetCategory.autofocus:
        return LucideIcons.focus;
      case SnippetCategory.dithering:
        return LucideIcons.move;
      case SnippetCategory.filterSequence:
        return LucideIcons.palette;
      case SnippetCategory.calibration:
        return LucideIcons.rotateCw;
      case SnippetCategory.safety:
        return LucideIcons.shield;
      case SnippetCategory.custom:
        return LucideIcons.puzzle;
    }
  }

  Color _getCategoryColor(SnippetCategory category) {
    switch (category) {
      case SnippetCategory.autofocus:
        return widget.colors.accent;
      case SnippetCategory.dithering:
        return widget.colors.info;
      case SnippetCategory.filterSequence:
        return widget.colors.primary;
      case SnippetCategory.calibration:
        return widget.colors.warning;
      case SnippetCategory.safety:
        return widget.colors.success;
      case SnippetCategory.custom:
        return widget.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snippetsByCategory = ref.watch(snippetsByCategoryProvider);

    // Filter snippets based on search query
    final filteredByCategory = <SnippetCategory, List<TemplateSnippet>>{};
    for (final entry in snippetsByCategory.entries) {
      if (_searchQuery.isEmpty) {
        filteredByCategory[entry.key] = entry.value;
      } else {
        final filtered = entry.value
            .where((snippet) =>
                snippet.name
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                snippet.description
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
            .toList();
        if (filtered.isNotEmpty) {
          filteredByCategory[entry.key] = filtered;
        }
      }
    }

    // Order categories in a logical sequence
    final orderedCategories = [
      SnippetCategory.autofocus,
      SnippetCategory.dithering,
      SnippetCategory.filterSequence,
      SnippetCategory.calibration,
      SnippetCategory.safety,
      SnippetCategory.custom,
    ].where((c) => filteredByCategory.containsKey(c)).toList();

    if (widget.isMobileSheet) {
      return _buildMobileSheetContent(filteredByCategory, orderedCategories);
    }

    return _buildDesktopSidebarContent(filteredByCategory, orderedCategories);
  }

  Widget _buildMobileSheetContent(
    Map<SnippetCategory, List<TemplateSnippet>> filteredByCategory,
    List<SnippetCategory> orderedCategories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: widget.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header with search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.bookMarked,
                    size: 18,
                    color: widget.colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Templates',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Search
              _buildSearchField(isMobile: true),
            ],
          ),
        ),

        Divider(color: widget.colors.border, height: 1),

        // Categories list
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: orderedCategories.length + 1, // +1 for create button
              itemBuilder: (context, index) {
                if (index == orderedCategories.length) {
                  return _buildCreateFromSelectionButton(isMobile: true);
                }
                final category = orderedCategories[index];
                return _SnippetCategorySection(
                  category: category,
                  snippets: filteredByCategory[category]!,
                  colors: widget.colors,
                  categoryColor: _getCategoryColor(category),
                  categoryName: _getCategoryDisplayName(category),
                  categoryIcon: _getCategoryIcon(category),
                  getIcon: _getIcon,
                  isMobile: true,
                  onSnippetDragStart: widget.onSnippetDragStart,
                  onSnippetTap: widget.onSnippetTap,
                  onDeleteSnippet: _handleDeleteSnippet,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarContent(
    Map<SnippetCategory, List<TemplateSnippet>> filteredByCategory,
    List<SnippetCategory> orderedCategories,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surface,
        border: Border(right: BorderSide(color: widget.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: widget.colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.bookMarked,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Templates',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.onToggleCollapse != null)
                      Tooltip(
                        message: widget.isCollapsed
                            ? 'Expand panel'
                            : 'Collapse panel',
                        child: InkWell(
                          onTap: widget.onToggleCollapse,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              widget.isCollapsed
                                  ? LucideIcons.panelLeftOpen
                                  : LucideIcons.panelLeftClose,
                              size: 16,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search
                _buildSearchField(isMobile: false),
              ],
            ),
          ),

          // Categories
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: orderedCategories.length,
                itemBuilder: (context, index) {
                  final category = orderedCategories[index];
                  return _SnippetCategorySection(
                    category: category,
                    snippets: filteredByCategory[category]!,
                    colors: widget.colors,
                    categoryColor: _getCategoryColor(category),
                    categoryName: _getCategoryDisplayName(category),
                    categoryIcon: _getCategoryIcon(category),
                    getIcon: _getIcon,
                    isMobile: false,
                    onSnippetDragStart: widget.onSnippetDragStart,
                    onSnippetTap: widget.onSnippetTap,
                    onDeleteSnippet: _handleDeleteSnippet,
                  );
                },
              ),
            ),
          ),

          // Create from selection button
          _buildCreateFromSelectionButton(isMobile: false),

          // Help tip
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: widget.colors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 14,
                  color: widget.colors.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Drag templates to the sequence tree or tap to insert',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.colors.info,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(isMobile ? 10 : 8),
        border: Border.all(color: widget.colors.border),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: isMobile ? 16 : 14,
            color: widget.colors.textMuted,
          ),
          SizedBox(width: isMobile ? 10 : 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(
                fontSize: isMobile ? 14 : 12,
                color: widget.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search templates...',
                hintStyle: TextStyle(
                  fontSize: isMobile ? 14 : 12,
                  color: widget.colors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(vertical: isMobile ? 12 : 10),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Icon(
                LucideIcons.x,
                size: isMobile ? 16 : 14,
                color: widget.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCreateFromSelectionButton({required bool isMobile}) {
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final sequence = ref.watch(currentSequenceProvider);
    final hasSelection = selectedNodeId != null && sequence != null;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 12),
      child: Tooltip(
        message: hasSelection
            ? 'Create a reusable template from the selected node'
            : 'Select a node in the sequence to create a template',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasSelection ? () => _showCreateSnippetDialog() : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 12,
                vertical: isMobile ? 14 : 10,
              ),
              decoration: BoxDecoration(
                color: hasSelection
                    ? widget.colors.primary.withValues(alpha: 0.1)
                    : widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasSelection
                      ? widget.colors.primary.withValues(alpha: 0.3)
                      : widget.colors.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.plus,
                    size: isMobile ? 18 : 14,
                    color: hasSelection
                        ? widget.colors.primary
                        : widget.colors.textMuted,
                  ),
                  SizedBox(width: isMobile ? 10 : 8),
                  Text(
                    'Create from Selection',
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 12,
                      fontWeight: FontWeight.w500,
                      color: hasSelection
                          ? widget.colors.primary
                          : widget.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateSnippetDialog() {
    final selectedNodeId = ref.read(selectedNodeIdProvider);
    final sequence = ref.read(currentSequenceProvider);

    if (selectedNodeId == null || sequence == null) return;

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    SnippetCategory selectedCategory = SnippetCategory.custom;
    String selectedIconName = 'puzzle';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.colors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          title: Row(
            children: [
              Icon(
                LucideIcons.bookmark,
                size: 20,
                color: widget.colors.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Create Template',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                _buildDialogLabel('Name'),
                const SizedBox(height: 8),
                _buildDialogTextField(
                  controller: nameController,
                  hintText: 'Enter template name',
                ),
                const SizedBox(height: 16),

                // Description field
                _buildDialogLabel('Description'),
                const SizedBox(height: 8),
                _buildDialogTextField(
                  controller: descriptionController,
                  hintText: 'Describe what this template does',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Category dropdown
                _buildDialogLabel('Category'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SnippetCategory>(
                      value: selectedCategory,
                      isExpanded: true,
                      dropdownColor: widget.colors.surfaceOverlay,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.colors.textPrimary,
                      ),
                      items: SnippetCategory.values.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Row(
                            children: [
                              Icon(
                                _getCategoryIcon(category),
                                size: 16,
                                color: _getCategoryColor(category),
                              ),
                              const SizedBox(width: 8),
                              Text(_getCategoryDisplayName(category)),
                            ],
                          ),
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
                const SizedBox(height: 16),

                // Icon selection
                _buildDialogLabel('Icon'),
                const SizedBox(height: 8),
                _buildIconSelector(
                  selectedIconName: selectedIconName,
                  onIconSelected: (iconName) {
                    setDialogState(() => selectedIconName = iconName);
                  },
                ),
              ],
            ),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () {
                final name = nameController.text.trim();
                final description = descriptionController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a template name'),
                      backgroundColor: widget.colors.error,
                    ),
                  );
                  return;
                }

                _createSnippetFromSelection(
                  name: name,
                  description:
                      description.isEmpty ? 'Custom template' : description,
                  category: selectedCategory,
                  iconName: selectedIconName,
                  nodeIds: [selectedNodeId],
                  sequence: sequence,
                );

                Navigator.of(context).pop();
              },
              label: 'Create',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: widget.colors.textSecondary,
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 14,
        color: widget.colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 14,
          color: widget.colors.textMuted,
        ),
        filled: true,
        fillColor: widget.colors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildIconSelector({
    required String selectedIconName,
    required Function(String) onIconSelected,
  }) {
    final iconOptions = [
      ('focus', LucideIcons.focus),
      ('palette', LucideIcons.palette),
      ('move', LucideIcons.move),
      ('shield', LucideIcons.shield),
      ('rotate-cw', LucideIcons.rotateCw),
      ('filter', LucideIcons.filter),
      ('camera', LucideIcons.camera),
      ('target', LucideIcons.target),
      ('clock', LucideIcons.clock),
      ('star', LucideIcons.star),
      ('zap', LucideIcons.zap),
      ('layers', LucideIcons.layers),
      ('repeat', LucideIcons.repeat),
      ('grid', LucideIcons.grid),
      ('puzzle', LucideIcons.puzzle),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: iconOptions.map((option) {
        final (name, icon) = option;
        final isSelected = name == selectedIconName;
        return InkWell(
          onTap: () => onIconSelected(name),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? widget.colors.primary.withValues(alpha: 0.2)
                  : widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isSelected ? widget.colors.primary : widget.colors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? widget.colors.primary
                  : widget.colors.textSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _createSnippetFromSelection({
    required String name,
    required String description,
    required SnippetCategory category,
    required String iconName,
    required List<String> nodeIds,
    required Sequence sequence,
  }) {
    try {
      final snippet = createSnippetFromSelection(
        name: name,
        description: description,
        category: category,
        iconName: iconName,
        nodeIds: nodeIds,
        sequence: sequence,
      );

      ref.read(customSnippetsProvider.notifier).addSnippet(snippet);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "$name" created successfully'),
            backgroundColor: widget.colors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create template: $e'),
            backgroundColor: widget.colors.error,
          ),
        );
      }
    }
  }

  void _handleDeleteSnippet(TemplateSnippet snippet) {
    if (snippet.isBuiltIn) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.colors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: Row(
          children: [
            Icon(
              LucideIcons.trash2,
              size: 20,
              color: widget.colors.error,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Template',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: widget.colors.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${snippet.name}"? This action cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: widget.colors.textSecondary,
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              ref
                  .read(customSnippetsProvider.notifier)
                  .removeSnippet(snippet.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Template "${snippet.name}" deleted'),
                  backgroundColor: widget.colors.info,
                ),
              );
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

class _SnippetCategorySection extends StatefulWidget {
  final SnippetCategory category;
  final List<TemplateSnippet> snippets;
  final NightshadeColors colors;
  final Color categoryColor;
  final String categoryName;
  final IconData categoryIcon;
  final IconData Function(String) getIcon;
  final bool isMobile;
  final Function(TemplateSnippet)? onSnippetDragStart;
  final Function(TemplateSnippet)? onSnippetTap;
  final Function(TemplateSnippet)? onDeleteSnippet;

  const _SnippetCategorySection({
    required this.category,
    required this.snippets,
    required this.colors,
    required this.categoryColor,
    required this.categoryName,
    required this.categoryIcon,
    required this.getIcon,
    this.isMobile = false,
    this.onSnippetDragStart,
    this.onSnippetTap,
    this.onDeleteSnippet,
  });

  @override
  State<_SnippetCategorySection> createState() =>
      _SnippetCategorySectionState();
}

class _SnippetCategorySectionState extends State<_SnippetCategorySection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.isMobile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 16,
              vertical: isMobile ? 12 : 8,
            ),
            child: Row(
              children: [
                Container(
                  width: isMobile ? 32 : 24,
                  height: isMobile ? 32 : 24,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(isMobile ? 8 : 6),
                  ),
                  child: Icon(
                    widget.categoryIcon,
                    size: isMobile ? 16 : 12,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.categoryName,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 12,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${widget.snippets.length}',
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 10,
                    color: widget.colors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isExpanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: isMobile ? 18 : 14,
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Snippet items
        AnimatedCrossFade(
          firstChild: Padding(
            padding: EdgeInsets.only(
              left: isMobile ? 16 : 12,
              right: isMobile ? 16 : 12,
              bottom: 8,
            ),
            child: Column(
              children: widget.snippets.map((snippet) {
                return _DraggableSnippetItem(
                  snippet: snippet,
                  colors: widget.colors,
                  categoryColor: widget.categoryColor,
                  getIcon: widget.getIcon,
                  isMobile: isMobile,
                  onSnippetDragStart: widget.onSnippetDragStart,
                  onSnippetTap: widget.onSnippetTap,
                  onDelete: widget.onDeleteSnippet,
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _DraggableSnippetItem extends StatefulWidget {
  final TemplateSnippet snippet;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;
  final bool isMobile;
  final Function(TemplateSnippet)? onSnippetDragStart;
  final Function(TemplateSnippet)? onSnippetTap;
  final Function(TemplateSnippet)? onDelete;

  const _DraggableSnippetItem({
    required this.snippet,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
    this.isMobile = false,
    this.onSnippetDragStart,
    this.onSnippetTap,
    this.onDelete,
  });

  @override
  State<_DraggableSnippetItem> createState() => _DraggableSnippetItemState();
}

class _DraggableSnippetItemState extends State<_DraggableSnippetItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.isMobile;

    // On mobile, use tap instead of drag
    if (isMobile) {
      return _buildMobileItem();
    }

    return _buildDesktopItem();
  }

  Widget _buildMobileItem() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSnippetTap?.call(widget.snippet),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.getIcon(widget.snippet.iconName),
                  size: 20,
                  color: widget.categoryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.snippet.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                            ),
                          ),
                        ),
                        if (widget.snippet.isBuiltIn)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.colors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Built-in',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: widget.colors.info,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.snippet.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!widget.snippet.isBuiltIn)
                IconButton(
                  onPressed: () => widget.onDelete?.call(widget.snippet),
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: widget.colors.textMuted,
                  ),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                )
              else
                Icon(
                  LucideIcons.plus,
                  size: 18,
                  color: widget.categoryColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopItem() {
    return Draggable<TemplateSnippet>(
      data: widget.snippet,
      onDragStarted: () => widget.onSnippetDragStart?.call(widget.snippet),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.categoryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: widget.categoryColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: widget.categoryColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.getIcon(widget.snippet.iconName),
                size: 14,
                color: widget.categoryColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.snippet.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onDoubleTap: () => widget.onSnippetTap?.call(widget.snippet),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.colors.surfaceAlt
                  : widget.colors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered
                    ? widget.categoryColor.withValues(alpha: 0.5)
                    : widget.colors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.getIcon(widget.snippet.iconName),
                    size: 14,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.snippet.name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _isHovered
                                    ? widget.colors.textPrimary
                                    : widget.colors.textSecondary,
                              ),
                            ),
                          ),
                          if (widget.snippet.isBuiltIn)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    widget.colors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'Built-in',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w500,
                                  color: widget.colors.info,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        widget.snippet.description,
                        style: TextStyle(
                          fontSize: 9,
                          color: widget.colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isHovered)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.snippet.isBuiltIn)
                        InkWell(
                          onTap: () => widget.onDelete?.call(widget.snippet),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              LucideIcons.trash2,
                              size: 12,
                              color: widget.colors.error,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.plus,
                        size: 12,
                        color: widget.categoryColor,
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
