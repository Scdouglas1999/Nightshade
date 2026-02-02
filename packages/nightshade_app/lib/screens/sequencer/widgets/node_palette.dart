import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class NodePalette extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ScrollController? scrollController;
  final bool isMobileSheet;
  final VoidCallback? onNodeAdded;

  const NodePalette({
    super.key,
    required this.colors,
    this.scrollController,
    this.isMobileSheet = false,
    this.onNodeAdded,
  });

  @override
  ConsumerState<NodePalette> createState() => _NodePaletteState();
}

class _NodePaletteState extends ConsumerState<NodePalette> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'target': return LucideIcons.target;
      case 'camera': return LucideIcons.camera;
      case 'circle': return LucideIcons.circle;
      case 'shuffle': return LucideIcons.shuffle;
      case 'compass': return LucideIcons.compass;
      case 'crosshair': return LucideIcons.crosshair;
      case 'parking-circle': return LucideIcons.parkingCircle;
      case 'unlock': return LucideIcons.unlock;
      case 'focus': return LucideIcons.focus;
      case 'snowflake': return LucideIcons.snowflake;
      case 'flame': return LucideIcons.flame;
      case 'rotate-cw': return LucideIcons.rotateCw;
      case 'workflow': return LucideIcons.workflow;
      case 'repeat': return LucideIcons.repeat;
      case 'git-merge': return LucideIcons.gitMerge;
      case 'git-branch': return LucideIcons.gitBranch;
      case 'shield-check': return LucideIcons.shieldCheck;
      case 'clock': return LucideIcons.clock;
      case 'timer': return LucideIcons.timer;
      case 'wrench': return LucideIcons.wrench;
      case 'bell': return LucideIcons.bell;
      case 'code': return LucideIcons.code;
      case 'aperture': return LucideIcons.aperture;
      default: return LucideIcons.box;
    }
  }

  Color _getCategoryColor(String categoryName) {
    switch (categoryName) {
      case 'Target': return widget.colors.warning;
      case 'Imaging': return widget.colors.primary;
      case 'Mount': return widget.colors.info;
      case 'Focus': return widget.colors.accent;
      case 'Camera': return widget.colors.primary;
      case 'Logic': return widget.colors.accent;
      case 'Timing': return widget.colors.warning;
      case 'Utilities': return widget.colors.textMuted;
      default: return widget.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(nodePaletteProvider);

    // Filter based on search
    final filteredCategories = categories.map((category) {
      if (_searchQuery.isEmpty) return category;

      final filteredItems = category.items
          .where((item) =>
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              item.description.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();

      return NodePaletteCategory(
        name: category.name,
        icon: category.icon,
        items: filteredItems,
      );
    }).where((c) => c.items.isNotEmpty).toList();

    // Mobile bottom sheet layout
    if (widget.isMobileSheet) {
      return _buildMobileSheetContent(filteredCategories);
    }

    // Desktop sidebar layout
    return _buildDesktopSidebarContent(filteredCategories);
  }

  Widget _buildMobileSheetContent(List<NodePaletteCategory> filteredCategories) {
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
                    LucideIcons.layoutGrid,
                    size: 18,
                    color: widget.colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Add Node',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.search,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _searchQuery = value),
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search nodes...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: widget.colors.textMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                          size: 16,
                          color: widget.colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Divider(color: widget.colors.border, height: 1),

        // Categories list - using provided scroll controller for DraggableScrollableSheet
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: filteredCategories.length,
            itemBuilder: (context, index) {
              final category = filteredCategories[index];
              return _CategorySection(
                category: category,
                colors: widget.colors,
                categoryColor: _getCategoryColor(category.name),
                getIcon: _getIcon,
                isMobile: true,
                onNodeAdded: widget.onNodeAdded,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarContent(List<NodePaletteCategory> filteredCategories) {
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
                      LucideIcons.layoutGrid,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Node Palette',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.search,
                        size: 14,
                        color: widget.colors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _searchQuery = value),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search nodes...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                            size: 14,
                            color: widget.colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Categories
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filteredCategories.length,
              itemBuilder: (context, index) {
                final category = filteredCategories[index];
                return _CategorySection(
                  category: category,
                  colors: widget.colors,
                  categoryColor: _getCategoryColor(category.name),
                  getIcon: _getIcon,
                );
              },
            ),
          ),

          // Help tip
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.info.withValues(alpha: 0.2)),
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
                    'Drag nodes to the sequence tree or double-click to add',
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
}

class _CategorySection extends ConsumerStatefulWidget {
  final NodePaletteCategory category;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;
  final bool isMobile;
  final VoidCallback? onNodeAdded;

  const _CategorySection({
    required this.category,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
    this.isMobile = false,
    this.onNodeAdded,
  });

  @override
  ConsumerState<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends ConsumerState<_CategorySection> {
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
                    widget.getIcon(widget.category.icon),
                    size: isMobile ? 16 : 12,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.category.name,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 12,
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
                    size: isMobile ? 18 : 14,
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Items
        AnimatedCrossFade(
          firstChild: Padding(
            padding: EdgeInsets.only(
              left: isMobile ? 16 : 12,
              right: isMobile ? 16 : 12,
              bottom: 8,
            ),
            child: Column(
              children: widget.category.items.map((item) {
                return _DraggableNodeItem(
                  item: item,
                  colors: widget.colors,
                  categoryColor: widget.categoryColor,
                  getIcon: widget.getIcon,
                  isMobile: isMobile,
                  onNodeAdded: widget.onNodeAdded,
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

class _DraggableNodeItem extends ConsumerStatefulWidget {
  final NodePaletteItem item;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;
  final bool isMobile;
  final VoidCallback? onNodeAdded;

  const _DraggableNodeItem({
    required this.item,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
    this.isMobile = false,
    this.onNodeAdded,
  });

  @override
  ConsumerState<_DraggableNodeItem> createState() => _DraggableNodeItemState();
}

class _DraggableNodeItemState extends ConsumerState<_DraggableNodeItem> {
  bool _isHovered = false;

  void _addNode() {
    final node = widget.item.createNode();
    final selectedId = ref.read(selectedNodeIdProvider);
    ref.read(currentSequenceProvider.notifier).addNode(
      node,
      parentId: selectedId,
    );
    ref.read(selectedNodeIdProvider.notifier).state = node.id;
    widget.onNodeAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.isMobile;

    // On mobile, use tap instead of double-tap and skip dragging
    if (isMobile) {
      return _buildMobileItem();
    }

    return _buildDesktopItem();
  }

  Widget _buildMobileItem() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _addNode,
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
                  widget.getIcon(widget.item.icon),
                  size: 20,
                  color: widget.categoryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.description,
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
    return Draggable<NodePaletteItem>(
      data: widget.item,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.categoryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.categoryColor.withValues(alpha: 0.5)),
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
                widget.getIcon(widget.item.icon),
                size: 14,
                color: widget.categoryColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.item.name,
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
          onDoubleTap: _addNode,
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
                    widget.getIcon(widget.item.icon),
                    size: 14,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _isHovered
                              ? widget.colors.textPrimary
                              : widget.colors.textSecondary,
                        ),
                      ),
                      Text(
                        widget.item.description,
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
                  Icon(
                    LucideIcons.plus,
                    size: 12,
                    color: widget.categoryColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



