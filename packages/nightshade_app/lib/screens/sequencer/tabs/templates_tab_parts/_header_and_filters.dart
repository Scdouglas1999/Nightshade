// Part of ../templates_tab.dart -- extracted for maintainability.
//
// Top-of-tab chrome and primary action chip: snippet summary card, header with search box, category filter chips, and the _ActionButton primitive.
part of '../templates_tab.dart';

class _SnippetSummaryCard extends ConsumerWidget {
  final NightshadeColors colors;
  final int snippetCount;

  const _SnippetSummaryCard({
    required this.colors,
    required this.snippetCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: NightshadeDecorations.iconChip(
        colors.accent,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        borderAlpha: 0.2,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: NightshadeDecorations.statusChip(
              colors.accent,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              bordered: false,
            ),
            child: Icon(
              LucideIcons.bookMarked,
              size: 20,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reusable Snippets',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$snippetCount snippets available. Switch to Builder tab and use the Snippets panel (Ctrl+T) to add them.',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            colors: colors,
            icon: LucideIcons.arrowRight,
            label: 'Go to Builder',
            onPressed: () {
              // Switch to Builder tab and show snippets
              ref.read(sequencerTabProvider.notifier).state = 0;
              ref.read(snippetPaletteVisibleProvider.notifier).state = true;
            },
          ),
        ],
      ),
    );
  }
}

class _TemplatesHeader extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _TemplatesHeader({required this.colors});

  @override
  ConsumerState<_TemplatesHeader> createState() => _TemplatesHeaderState();
}

class _TemplatesHeaderState extends ConsumerState<_TemplatesHeader> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 600;

    if (isMobile || isNarrow) {
      return _buildMobileHeader();
    }
    return _buildDesktopHeader();
  }

  Widget _buildMobileHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row with save button
        Row(
          children: [
            Expanded(
              child: Text(
                'Templates',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize20,
                  fontWeight: FontWeight.w700,
                  color: widget.colors.textPrimary,
                ),
              ),
            ),
            // Quick-start wizard
            NightshadeButton(
              label: 'Wizard',
              icon: LucideIcons.wand2,
              size: ButtonSize.small,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const QuickStartWizardDialog(),
                );
              },
            ),
            const SizedBox(width: 8),
            // Save current as template button
            NightshadeButton(
              label: 'Save',
              icon: LucideIcons.save,
              size: ButtonSize.small,
              onPressed: () => _showSaveTemplateDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search field - full width on mobile
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search,
                  size: 16, color: widget.colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    ref.read(templateSearchProvider.notifier).state = value;
                  },
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search templates...',
                    hintStyle: TextStyle(
                      fontSize: NightshadeTypography.fontSize14,
                      color: widget.colors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    ref.read(templateSearchProvider.notifier).state = '';
                  },
                  child: Icon(LucideIcons.x,
                      size: 16, color: widget.colors.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _CategoryFilterChips(colors: widget.colors),
      ],
    );
  }

  Widget _buildDesktopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Title
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sequence Templates',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize24,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Start with a template or save your sequences for reuse',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: widget.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Search - flexible width based on available space
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 250),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search,
                          size: 16, color: widget.colors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            ref.read(templateSearchProvider.notifier).state =
                                value;
                          },
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize13,
                            color: widget.colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(
                              fontSize: NightshadeTypography.fontSize13,
                              color: widget.colors.textMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            ref.read(templateSearchProvider.notifier).state =
                                '';
                          },
                          child: Icon(LucideIcons.x,
                              size: 16, color: widget.colors.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Quick-start wizard button
            _ActionButton(
              colors: widget.colors,
              icon: LucideIcons.wand2,
              label: 'Quick-Start Wizard',
              isPrimary: false,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const QuickStartWizardDialog(),
                );
              },
            ),

            const SizedBox(width: 8),

            // Save current as template button
            _ActionButton(
              colors: widget.colors,
              icon: LucideIcons.save,
              label: 'Save as Template',
              isPrimary: true,
              onPressed: () => _showSaveTemplateDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CategoryFilterChips(colors: widget.colors),
      ],
    );
  }

  void _showSaveTemplateDialog(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);
    if (currentSequence == null) {
      context.showErrorSnackBar('No sequence to save as template');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _SaveTemplateDialog(
        colors: widget.colors,
        sequence: currentSequence,
      ),
    );
  }
}

class _CategoryFilterChips extends ConsumerWidget {
  final NightshadeColors colors;

  const _CategoryFilterChips({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(templateCategoryProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _templateCategoryOptions.map((option) {
          final value = option.key;
          final label = option.value;
          final selected = value == null
              ? selectedCategory == null
              : selectedCategory == value;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              label: Text(label),
              onSelected: (_) {
                ref.read(templateCategoryProvider.notifier).state = value;
              },
              selectedColor: NightshadeDecorations.statusChip(
                colors.primary,
                bordered: false,
              ).color,
              backgroundColor: colors.surfaceAlt,
              side: BorderSide(
                color: selected ? colors.primary : colors.border,
              ),
              labelStyle: TextStyle(
                color: selected ? colors.primary : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              checkmarkColor: colors.primary,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? _isHovered
                    ? widget.colors.primary.withValues(alpha: 0.9)
                    : widget.colors.primary
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: widget.isPrimary
                ? null
                : Border.all(color: widget.colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color:
                    widget.isPrimary ? onPrimary : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? onPrimary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}