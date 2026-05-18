import 'dart:ui';

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
  final VoidCallback? onCollapse;

  const NodePalette({
    super.key,
    required this.colors,
    this.scrollController,
    this.isMobileSheet = false,
    this.onNodeAdded,
    this.onCollapse,
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
      case 'door-open': return LucideIcons.doorOpen;
      case 'door-closed': return LucideIcons.doorClosed;
      case 'lightbulb': return LucideIcons.lightbulb;
      case 'lightbulb-off': return LucideIcons.lightbulbOff;
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
      case 'Flat Panel': return widget.colors.warning;
      case 'Dome': return widget.colors.info;
      case 'Guiding': return widget.colors.primary;
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
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarContent(List<NodePaletteCategory> filteredCategories) {
    return Builder(builder: (context) {
      final headerFontSize = Responsive.fontSize(context, 14);
      final searchFontSize = Responsive.fontSize(context, 13);
      final tipFontSize = Responsive.fontSize(context, 11);
      final headerIconSize = Responsive.iconSize(context, 16);
      final searchIconSize = Responsive.iconSize(context, 15);
      final tipIconSize = Responsive.iconSize(context, 14);
      final headerPadding = Responsive.spacing(context, 16);
      final searchPadding = Responsive.spacing(context, 12);
      final tipPadding = Responsive.spacing(context, 12);

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
              padding: EdgeInsets.all(headerPadding),
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
                        size: headerIconSize,
                        color: widget.colors.textMuted,
                      ),
                      SizedBox(width: Responsive.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          'Node Palette',
                          style: TextStyle(
                            fontSize: headerFontSize,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.onCollapse != null)
                        Tooltip(
                          message: 'Collapse panel',
                          child: InkWell(
                            onTap: widget.onCollapse,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                LucideIcons.panelLeftClose,
                                size: headerIconSize,
                                color: widget.colors.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: Responsive.spacing(context, 12)),
                  // Search
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: searchPadding),
                    decoration: BoxDecoration(
                      color: widget.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
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
                  padding: EdgeInsets.symmetric(
                    vertical: Responsive.spacing(context, 8),
                  ),
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
            ),

            // Help tip
            Container(
              padding: EdgeInsets.all(tipPadding),
              margin: EdgeInsets.all(tipPadding),
              decoration: BoxDecoration(
                color: widget.colors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.info.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: tipIconSize,
                    color: widget.colors.info,
                  ),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'Drag nodes to the sequence tree or double-click to add',
                      style: TextStyle(
                        fontSize: tipFontSize,
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
    });
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

    final badgeSize = isMobile ? 32.0 : Responsive.spacing(context, 28);
    final badgeIconSize = isMobile ? 16.0 : Responsive.iconSize(context, 14);
    final categoryFontSize = isMobile ? 14.0 : Responsive.fontSize(context, 13);
    final chevronSize = isMobile ? 18.0 : Responsive.iconSize(context, 15);
    final hPadding = isMobile ? 16.0 : Responsive.spacing(context, 16);
    final vPadding = isMobile ? 12.0 : Responsive.spacing(context, 10);
    final itemPadding = isMobile ? 16.0 : Responsive.spacing(context, 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: hPadding,
              vertical: vPadding,
            ),
            child: Row(
              children: [
                Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(isMobile ? 8 : 6),
                  ),
                  child: Icon(
                    widget.getIcon(widget.category.icon),
                    size: badgeIconSize,
                    color: widget.categoryColor,
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 10)),
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

        // Items
        AnimatedCrossFade(
          firstChild: Padding(
            padding: EdgeInsets.only(
              left: itemPadding,
              right: itemPadding,
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
    // Trust-patch §B: refuse the click while the executor owns the
    // tree. Editor still throws SequenceLockedException as a last line
    // of defense; this just keeps the affordance honest.
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
    widget.onNodeAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(canEditSequenceProvider);
    final isMobile = widget.isMobile;

    final inner = isMobile ? _buildMobileItem() : _buildDesktopItem();

    if (!canEdit) {
      // Disable taps, dragging, and visually wash out the palette item.
      // Wrap in Tooltip so hovering explains why the tile is inert.
      return Tooltip(
        message: 'Cannot edit while sequence is running',
        child: IgnorePointer(
          ignoring: true,
          child: Opacity(opacity: 0.45, child: inner),
        ),
      );
    }
    return inner;
  }

  Widget _buildMobileItem() {
    // FocusRing wraps the InkWell so keyboard nav lands here with a visible
    // accent ring; the InkWell only paints a ripple on pointer events.
    return FocusRing(
      borderRadius: BorderRadius.circular(10),
      child: Material(
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
    ),
    );
  }

  Widget _buildDesktopItem() {
    return Builder(builder: (context) {
      final nameFontSize = Responsive.fontSize(context, 12);
      final descFontSize = Responsive.fontSize(context, 10);
      final feedbackFontSize = Responsive.fontSize(context, 12);
      final iconBoxSize = Responsive.spacing(context, 30);
      final itemIconSize = Responsive.iconSize(context, 15);
      final feedbackIconSize = Responsive.iconSize(context, 14);
      final plusIconSize = Responsive.iconSize(context, 13);
      final hPadding = Responsive.spacing(context, 10);
      final vPadding = Responsive.spacing(context, 8);

      return Draggable<NodePaletteItem>(
        data: widget.item,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
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
                  size: feedbackIconSize,
                  color: widget.categoryColor,
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
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
        // FocusRing surfaces keyboard focus on the otherwise mouse-only
        // GestureDetector (double-tap activator), keeping the node palette
        // navigable for keyboard-only users.
        child: FocusRing(
          borderRadius: BorderRadius.circular(8),
          child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onDoubleTap: _addNode,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(top: 4),
              padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
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
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      widget.getIcon(widget.item.icon),
                      size: itemIconSize,
                      color: widget.categoryColor,
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 10)),
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
                  if (_isHovered)
                    Icon(
                      LucideIcons.plus,
                      size: plusIconSize,
                      color: widget.categoryColor,
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      );
    });
  }
}



