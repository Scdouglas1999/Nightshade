part of '../snippet_palette.dart';

class _DraggableSnippetItem extends StatefulWidget {
  final TemplateSnippet snippet;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;
  final bool isMobile;
  final bool platformHasShareSheet;
  final Function(TemplateSnippet)? onSnippetDragStart;
  final Function(TemplateSnippet)? onSnippetTap;
  final Function(TemplateSnippet)? onDelete;
  final Function(TemplateSnippet)? onExport;
  final Function(TemplateSnippet)? onShare;

  const _DraggableSnippetItem({
    required this.snippet,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
    this.isMobile = false,
    this.platformHasShareSheet = false,
    this.onSnippetDragStart,
    this.onSnippetTap,
    this.onDelete,
    this.onExport,
    this.onShare,
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: NightshadeDecorations.tintedBadge(
                  widget.categoryColor,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusLg),
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
                            style: NightshadeTypography.h5
                                .copyWith(color: widget.colors.textPrimary),
                          ),
                        ),
                        if (widget.snippet.isBuiltIn)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: NightshadeDecorations.tintedBadge(
                              widget.colors.info,
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'Built-in',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
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
                        fontSize: NightshadeTypography.fontSize12,
                        color: widget.colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildOverflowMenu(iconSize: 18),
              if (widget.snippet.isBuiltIn)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    LucideIcons.plus,
                    size: 18,
                    color: widget.categoryColor,
                  ),
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                style: NightshadeTypography.labelSm
                    .copyWith(color: widget.colors.textPrimary),
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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                  decoration: NightshadeDecorations.tintedBadge(
                    widget.categoryColor,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusMd),
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
                              style: NightshadeTypography.labelQuiet.copyWith(
                                  color: _isHovered
                                      ? widget.colors.textPrimary
                                      : widget.colors.textSecondary),
                            ),
                          ),
                          if (widget.snippet.isBuiltIn)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: NightshadeDecorations.tintedBadge(
                                widget.colors.info,
                                borderRadius: BorderRadius.circular(
                                    NightshadeTokens.radiusXs),
                              ),
                              child: Text(
                                'Built-in',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize8,
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
                          fontSize: NightshadeTypography.fontSize9,
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
                      _buildOverflowMenu(iconSize: 14),
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

  /// Compact context menu offering Export / Share / Delete actions.
  ///
  /// Built-in snippets get Export (so the user can share a copy of a
  /// preset) but not Delete (built-ins are not user-owned). When the
  /// running platform has no system share sheet, the Share entry is
  /// hidden — desktop users get Export which produces the same file
  /// they can attach to anything manually.
  Widget _buildOverflowMenu({required double iconSize}) {
    return PopupMenuButton<_SnippetAction>(
      tooltip: 'Snippet actions',
      icon: Icon(
        LucideIcons.moreVertical,
        size: iconSize,
        color: widget.colors.textMuted,
      ),
      padding: EdgeInsets.zero,
      iconSize: iconSize,
      splashRadius: iconSize + 4,
      color: widget.colors.surfaceOverlay,
      onSelected: (action) {
        switch (action) {
          case _SnippetAction.export:
            widget.onExport?.call(widget.snippet);
            break;
          case _SnippetAction.share:
            widget.onShare?.call(widget.snippet);
            break;
          case _SnippetAction.delete:
            widget.onDelete?.call(widget.snippet);
            break;
        }
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<_SnippetAction>>[
          PopupMenuItem(
            value: _SnippetAction.export,
            child: _menuRow(
              LucideIcons.download,
              'Export…',
              widget.colors.textPrimary,
            ),
          ),
        ];
        if (widget.platformHasShareSheet) {
          items.add(
            PopupMenuItem(
              value: _SnippetAction.share,
              child: _menuRow(
                LucideIcons.share2,
                'Share…',
                widget.colors.textPrimary,
              ),
            ),
          );
        }
        if (!widget.snippet.isBuiltIn) {
          items.add(const PopupMenuDivider());
          items.add(
            PopupMenuItem(
              value: _SnippetAction.delete,
              child: _menuRow(
                LucideIcons.trash2,
                'Delete',
                widget.colors.error,
              ),
            ),
          );
        }
        return items;
      },
    );
  }

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: color, fontSize: NightshadeTypography.fontSize13)),
      ],
    );
  }
}

enum _SnippetAction { export, share, delete }
