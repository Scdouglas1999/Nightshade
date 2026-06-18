part of '../sequencer_screen.dart';

class _NodePaletteContent extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _NodePaletteContent({required this.colors});

  @override
  ConsumerState<_NodePaletteContent> createState() =>
      _NodePaletteContentState();
}

class _NodePaletteContentState extends ConsumerState<_NodePaletteContent> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getIcon(String iconName) => nodePaletteIconFor(iconName);

  Color _getCategoryColor(String categoryName) =>
      nodePaletteCategoryColor(categoryName, widget.colors);

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(nodePaletteProvider);

    // Filter based on search. Lower-case the query once up front rather
    // than per-item, and reuse it across name + description checks.
    final filteredCategories = categories
        .map((category) {
          if (_searchQuery.isEmpty) return category;

          final q = _searchQuery.toLowerCase();
          final filteredItems = category.items
              .where((item) =>
                  item.name.toLowerCase().contains(q) ||
                  item.description.toLowerCase().contains(q))
              .toList();

          return NodePaletteCategory(
            name: category.name,
            icon: category.icon,
            items: filteredItems,
          );
        })
        .where((c) => c.items.isNotEmpty)
        .toList();

    final searchFontSize = Responsive.fontSize(context, 13);
    final searchIconSize = Responsive.iconSize(context, 15);
    final searchPadding = Responsive.spacing(context, 12);

    return Column(
      children: [
        // Search field
        Padding(
          padding: EdgeInsets.all(searchPadding),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: searchPadding),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: searchIconSize,
                  color: widget.colors.textMuted,
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(
                      fontSize: searchFontSize,
                      color: widget.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search nodes...',
                      hintStyle: TextStyle(
                        fontSize: searchFontSize,
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: Responsive.spacing(context, 10),
                      ),
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
                      size: searchIconSize,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
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
              padding: EdgeInsets.only(bottom: Responsive.spacing(context, 8)),
              itemCount: filteredCategories.length,
              itemBuilder: (context, index) {
                final category = filteredCategories[index];
                return _NodeCategorySection(
                  category: category,
                  colors: widget.colors,
                  categoryColor: _getCategoryColor(category.name),
                  getIcon: _getIcon,
                );
              },
            ),
          ),
        ),

        // Help tip
        Container(
          padding: EdgeInsets.all(Responsive.spacing(context, 10)),
          margin: EdgeInsets.all(Responsive.spacing(context, 10)),
          decoration: NightshadeDecorations.iconChip(
            widget.colors.info,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            borderAlpha: 0.2,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: Responsive.iconSize(context, 13),
                color: widget.colors.info,
              ),
              SizedBox(width: Responsive.spacing(context, 6)),
              Expanded(
                child: Text(
                  'Drag nodes or double-click to add',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: widget.colors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Node category section for the palette content
class _NodeCategorySection extends ConsumerStatefulWidget {
  final NodePaletteCategory category;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;

  const _NodeCategorySection({
    required this.category,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
  });

  @override
  ConsumerState<_NodeCategorySection> createState() =>
      _NodeCategorySectionState();
}

class _NodeCategorySectionState extends ConsumerState<_NodeCategorySection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final badgeSize = Responsive.spacing(context, 26);
    final badgeIconSize = Responsive.iconSize(context, 13);
    final categoryFontSize = Responsive.fontSize(context, 12);
    final chevronSize = Responsive.iconSize(context, 14);
    final hPadding = Responsive.spacing(context, 12);
    final vPadding = Responsive.spacing(context, 8);
    final itemPadding = Responsive.spacing(context, 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
            child: Row(
              children: [
                Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: NightshadeDecorations.statusChip(
                    widget.categoryColor,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
                    bordered: false,
                  ),
                  child: Icon(
                    widget.getIcon(widget.category.icon),
                    size: badgeIconSize,
                    color: widget.categoryColor,
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: Text(
                    widget.category.name,
                    style: TextStyle(
                      fontSize: categoryFontSize,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: chevronSize,
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Padding(
            padding: EdgeInsets.only(
                left: itemPadding, right: itemPadding, bottom: 4),
            child: Column(
              children: widget.category.items.map((item) {
                return _DraggableNodeItemCompact(
                  item: item,
                  colors: widget.colors,
                  categoryColor: widget.categoryColor,
                  getIcon: widget.getIcon,
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

/// Compact draggable node item for the toolbox
class _DraggableNodeItemCompact extends ConsumerStatefulWidget {
  final NodePaletteItem item;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;

  const _DraggableNodeItemCompact({
    required this.item,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
  });

  @override
  ConsumerState<_DraggableNodeItemCompact> createState() =>
      _DraggableNodeItemCompactState();
}

class _DraggableNodeItemCompactState
    extends ConsumerState<_DraggableNodeItemCompact> {
  bool _isHovered = false;

  void _addNode() {
    // Refuse the click while the executor owns the tree; the editor still
    // throws SequenceLockedException as a last line of defense.
    if (!ref.read(canEditSequenceProvider)) return;
    final node = widget.item.createNode();
    final selectedId = ref.read(selectedNodeIdProvider);
    final notifier = ref.read(currentSequenceProvider.notifier);
    notifier.addNode(
      node,
      parentId: selectedId,
    );

    // Add any pre-configured children (e.g. Autofocus inside HFR Triggered AF)
    final children = widget.item.createChildren?.call();
    if (children != null) {
      for (final child in children) {
        notifier.addNode(child, parentId: node.id);
      }
    }

    ref.read(selectedNodeIdProvider.notifier).state = node.id;
  }

  @override
  Widget build(BuildContext context) {
    final nameFontSize = Responsive.fontSize(context, 12);
    final descFontSize = Responsive.fontSize(context, 10);
    final feedbackFontSize = Responsive.fontSize(context, 12);
    final iconBoxSize = Responsive.spacing(context, 28);
    final itemIconSize = Responsive.iconSize(context, 14);
    final feedbackIconSize = Responsive.iconSize(context, 13);
    final plusIconSize = Responsive.iconSize(context, 12);
    final hPadding = Responsive.spacing(context, 10);
    final vPadding = Responsive.spacing(context, 8);

    return Draggable<NodePaletteItem>(
      data: widget.item,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 6),
          decoration: NightshadeDecorations.selectedSurface(
            widget.categoryColor,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            fillAlpha: 0.2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.getIcon(widget.item.icon),
                  size: feedbackIconSize, color: widget.categoryColor),
              const SizedBox(width: 6),
              Text(
                widget.item.name,
                style: TextStyle(
                  fontSize: feedbackFontSize,
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
          onDoubleTap: _addNode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(top: 3),
            padding:
                EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.colors.surfaceAlt
                  : widget.colors.background,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(
                color: _isHovered
                    ? widget.categoryColor.withValues(alpha: 0.5)
                    : widget.colors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: NightshadeDecorations.tintedBadge(
                    widget.categoryColor,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
                  ),
                  child: Icon(
                    widget.getIcon(widget.item.icon),
                    size: itemIconSize,
                    color: widget.categoryColor,
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: TextStyle(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w500,
                          color: _isHovered
                              ? widget.colors.textPrimary
                              : widget.colors.textSecondary,
                        ),
                      ),
                      Text(
                        widget.item.description,
                        style: TextStyle(
                          fontSize: descFontSize,
                          color: widget.colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Always-visible single-tap add button (drag still works on
                // the tile). The hidden double-tap was undiscoverable.
                Tooltip(
                  message: 'Add to sequence',
                  child: GestureDetector(
                    onTap: _addNode,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        LucideIcons.plus,
                        size: plusIconSize,
                        color: _isHovered
                            ? widget.categoryColor
                            : widget.categoryColor.withValues(alpha: 0.6),
                      ),
                    ),
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

/// Snippet palette content for the toolbox
