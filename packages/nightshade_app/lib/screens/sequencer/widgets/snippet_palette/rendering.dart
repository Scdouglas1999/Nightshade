part of '../snippet_palette.dart';

extension _SnippetPaletteRendering on _SnippetPaletteState {
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
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
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
                  Expanded(
                    child: Text(
                      'Templates',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize18,
                        fontWeight: FontWeight.w700,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Import snippet from file…',
                    child: IconButton(
                      onPressed: _handleImportSnippet,
                      icon: Icon(
                        LucideIcons.fileInput,
                        size: 20,
                        color: widget.colors.primary,
                      ),
                      tooltip: 'Import snippet from file',
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
                  platformHasShareSheet: _platformHasShareSheet,
                  onSnippetDragStart: widget.onSnippetDragStart,
                  onSnippetTap: widget.onSnippetTap,
                  onDeleteSnippet: _handleDeleteSnippet,
                  onExportSnippet: _handleExportSnippet,
                  onShareSnippet: _handleShareSnippet,
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
                          fontSize: NightshadeTypography.fontSize13,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Import snippet from file…',
                      child: InkWell(
                        onTap: _handleImportSnippet,
                        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            LucideIcons.fileInput,
                            size: 16,
                            color: widget.colors.textMuted,
                          ),
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
                          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
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
                    platformHasShareSheet: _platformHasShareSheet,
                    onSnippetDragStart: widget.onSnippetDragStart,
                    onSnippetTap: widget.onSnippetTap,
                    onDeleteSnippet: _handleDeleteSnippet,
                    onExportSnippet: _handleExportSnippet,
                    onShareSnippet: _handleShareSnippet,
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
            decoration: NightshadeDecorations.iconChip(
              widget.colors.info,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
              borderAlpha: 0.2,
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
                      fontSize: NightshadeTypography.fontSize10,
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
        borderRadius: BorderRadius.circular(isMobile ? NightshadeTokens.radiusLg : NightshadeTokens.radiusInline8),
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
              onChanged: (value) => _update(() => _searchQuery = value),
              style: TextStyle(
                fontSize: isMobile ? NightshadeTypography.fontSize14 : NightshadeTypography.fontSize12,
                color: widget.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search templates...',
                hintStyle: TextStyle(
                  fontSize: isMobile ? NightshadeTypography.fontSize14 : NightshadeTypography.fontSize12,
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
                _update(() => _searchQuery = '');
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 12,
                vertical: isMobile ? 14 : 10,
              ),
              decoration: hasSelection
                  ? NightshadeDecorations.emphasisSurface(
                      widget.colors.primary,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                    )
                  : BoxDecoration(
                      color: widget.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      border: Border.all(color: widget.colors.border),
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
                      fontSize: isMobile ? NightshadeTypography.fontSize14 : NightshadeTypography.fontSize12,
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
}
