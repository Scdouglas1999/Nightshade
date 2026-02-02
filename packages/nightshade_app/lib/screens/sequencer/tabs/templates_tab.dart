import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../sequencer_screen.dart';
import 'package:nightshade_app/utils/snackbar_helper.dart';

/// Provider for templates list - loads from database with built-in fallbacks
final sequenceTemplatesProvider = FutureProvider<List<Sequence>>((ref) async {
  final repository = ref.watch(sequenceRepositoryProvider);
  
  // Load templates from database
  final dbTemplates = await repository.loadAllTemplates();
  
  // If no templates exist, return built-in templates
  if (dbTemplates.isEmpty) {
    return _getBuiltInTemplates();
  }
  
  return dbTemplates;
});

/// Built-in templates for first-time users
List<Sequence> _getBuiltInTemplates() {
  return [
    Sequence(
      id: 'template-basic-lrgb',
      name: 'Basic LRGB Sequence',
      description: 'Standard LRGB imaging sequence with autofocus and dithering',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      nodes: _createLrgbTemplateNodes(),
      rootNodeId: 'lrgb-root',
    ),
    Sequence(
      id: 'template-narrowband',
      name: 'Narrowband (SHO)',
      description: 'Hubble Palette narrowband imaging with SII, Ha, and OIII filters',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 25)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 25)),
      nodes: _createNarrowbandTemplateNodes(),
      rootNodeId: 'nb-root',
    ),
    Sequence(
      id: 'template-mosaic-panel',
      name: 'Mosaic Panel',
      description: 'Template for a single mosaic panel with multiple filters',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 20)),
      nodes: _createMosaicTemplateNodes(),
      rootNodeId: 'mosaic-root',
    ),
    Sequence(
      id: 'template-quick-capture',
      name: 'Quick Capture',
      description: 'Simple sequence for quick test shots',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 15)),
      nodes: _createQuickCaptureNodes(),
      rootNodeId: 'quick-root',
    ),
    Sequence(
      id: 'template-dso-beginner',
      name: 'DSO Beginner',
      description: 'Beginner-friendly sequence with comprehensive safety checks',
      isTemplate: true,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      modifiedAt: DateTime.now().subtract(const Duration(days: 10)),
      nodes: _createBeginnerTemplateNodes(),
      rootNodeId: 'beginner-root',
    ),
  ];
}

Map<String, SequenceNode> _createLrgbTemplateNodes() {
  const rootId = 'lrgb-root';
  const coolId = 'lrgb-cool';
  const focusId = 'lrgb-focus';
  const loopId = 'lrgb-loop';
  const lId = 'lrgb-l';
  const rId = 'lrgb-r';
  const gId = 'lrgb-g';
  const bId = 'lrgb-b';
  const warmId = 'lrgb-warm';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'LRGB Sequence',
      childIds: const [coolId, focusId, loopId, warmId],
    ),
    coolId: CoolCameraNode(id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    focusId: AutofocusNode(id: focusId, method: AutofocusMethod.vCurve, parentId: rootId, orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: LoopConditionType.forever,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [lId, rId, gId, bId],
    ),
    lId: ExposureNode(id: lId, name: 'Luminance', durationSecs: 300, count: 1, filter: 'L', binning: BinningMode.one, parentId: loopId, orderIndex: 0),
    rId: ExposureNode(id: rId, name: 'Red', durationSecs: 180, count: 1, filter: 'R', binning: BinningMode.one, parentId: loopId, orderIndex: 1),
    gId: ExposureNode(id: gId, name: 'Green', durationSecs: 180, count: 1, filter: 'G', binning: BinningMode.one, parentId: loopId, orderIndex: 2),
    bId: ExposureNode(id: bId, name: 'Blue', durationSecs: 180, count: 1, filter: 'B', binning: BinningMode.one, parentId: loopId, orderIndex: 3),
    warmId: WarmCameraNode(id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
  };
}

Map<String, SequenceNode> _createNarrowbandTemplateNodes() {
  const rootId = 'nb-root';
  const coolId = 'nb-cool';
  const focusId = 'nb-focus';
  const loopId = 'nb-loop';
  const haId = 'nb-ha';
  const oiiiId = 'nb-oiii';
  const siiId = 'nb-sii';
  const warmId = 'nb-warm';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Narrowband Sequence',
      childIds: const [coolId, focusId, loopId, warmId],
    ),
    coolId: CoolCameraNode(id: coolId, targetTemp: -15, parentId: rootId, orderIndex: 0),
    focusId: AutofocusNode(id: focusId, method: AutofocusMethod.vCurve, parentId: rootId, orderIndex: 1),
    loopId: LoopNode(
      id: loopId,
      name: 'Narrowband Loop',
      conditionType: LoopConditionType.forever,
      parentId: rootId,
      orderIndex: 2,
      childIds: const [haId, oiiiId, siiId],
    ),
    haId: ExposureNode(id: haId, name: 'H-alpha', durationSecs: 600, count: 1, filter: 'Ha', binning: BinningMode.one, parentId: loopId, orderIndex: 0),
    oiiiId: ExposureNode(id: oiiiId, name: 'OIII', durationSecs: 600, count: 1, filter: 'OIII', binning: BinningMode.one, parentId: loopId, orderIndex: 1),
    siiId: ExposureNode(id: siiId, name: 'SII', durationSecs: 600, count: 1, filter: 'SII', binning: BinningMode.one, parentId: loopId, orderIndex: 2),
    warmId: WarmCameraNode(id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 3),
  };
}

Map<String, SequenceNode> _createMosaicTemplateNodes() {
  const rootId = 'mosaic-root';
  const slewId = 'mosaic-slew';
  const centerId = 'mosaic-center';
  const focusId = 'mosaic-focus';
  const loopId = 'mosaic-loop';
  const lId = 'mosaic-l';
  const haId = 'mosaic-ha';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Mosaic Panel',
      childIds: const [slewId, centerId, focusId, loopId],
    ),
    slewId: SlewNode(id: slewId, name: 'Slew to Panel', parentId: rootId, orderIndex: 0),
    centerId: CenterNode(id: centerId, name: 'Plate Solve & Center', parentId: rootId, orderIndex: 1),
    focusId: AutofocusNode(id: focusId, method: AutofocusMethod.vCurve, parentId: rootId, orderIndex: 2),
    loopId: LoopNode(
      id: loopId,
      name: 'Panel Capture',
      conditionType: LoopConditionType.count,
      repeatCount: 10,
      parentId: rootId,
      orderIndex: 3,
      childIds: const [lId, haId],
    ),
    lId: ExposureNode(id: lId, name: 'Luminance', durationSecs: 300, count: 1, filter: 'L', binning: BinningMode.one, parentId: loopId, orderIndex: 0),
    haId: ExposureNode(id: haId, name: 'H-alpha', durationSecs: 300, count: 1, filter: 'Ha', binning: BinningMode.one, parentId: loopId, orderIndex: 1),
  };
}

Map<String, SequenceNode> _createQuickCaptureNodes() {
  const rootId = 'quick-root';
  const expId = 'quick-exp';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Quick Capture',
      childIds: const [expId],
    ),
    expId: ExposureNode(id: expId, name: 'Test Shot', durationSecs: 10, count: 5, filter: 'L', binning: BinningMode.one, parentId: rootId, orderIndex: 0),
  };
}

Map<String, SequenceNode> _createBeginnerTemplateNodes() {
  const rootId = 'beginner-root';
  const coolId = 'beginner-cool';
  const slewId = 'beginner-slew';
  const centerId = 'beginner-center';
  const focusId = 'beginner-focus';
  const loopId = 'beginner-loop';
  const lId = 'beginner-l';
  const ditherAfter = 'beginner-dither';
  const warmId = 'beginner-warm';
  const parkId = 'beginner-park';

  return {
    rootId: InstructionSetNode(
      id: rootId,
      name: 'Beginner DSO Sequence',
      childIds: const [coolId, slewId, centerId, focusId, loopId, warmId, parkId],
    ),
    coolId: CoolCameraNode(id: coolId, targetTemp: -10, parentId: rootId, orderIndex: 0),
    slewId: SlewNode(id: slewId, name: 'Slew to Target', parentId: rootId, orderIndex: 1),
    centerId: CenterNode(id: centerId, name: 'Plate Solve & Center', parentId: rootId, orderIndex: 2),
    focusId: AutofocusNode(id: focusId, method: AutofocusMethod.vCurve, parentId: rootId, orderIndex: 3),
    loopId: LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: LoopConditionType.count,
      repeatCount: 20,
      parentId: rootId,
      orderIndex: 4,
      childIds: const [lId, ditherAfter],
    ),
    lId: ExposureNode(id: lId, name: 'Luminance', durationSecs: 120, count: 1, filter: 'L', binning: BinningMode.one, parentId: loopId, orderIndex: 0),
    ditherAfter: DitherNode(id: ditherAfter, name: 'Dither', pixels: 5.0, settleTime: 30, parentId: loopId, orderIndex: 1),
    warmId: WarmCameraNode(id: warmId, ratePerMin: 5, parentId: rootId, orderIndex: 5),
    parkId: ParkNode(id: parkId, name: 'Park Mount', parentId: rootId, orderIndex: 6),
  };
}

/// Search provider for templates
final templateSearchProvider = StateProvider<String>((ref) => '');

/// Selected template category
final templateCategoryProvider = StateProvider<String?>((ref) => null);

class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final templatesAsync = ref.watch(sequenceTemplatesProvider);
    final searchQuery = ref.watch(templateSearchProvider);
    final category = ref.watch(templateCategoryProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          _TemplatesHeader(colors: colors),

          const SizedBox(height: 24),

          // Content
          Expanded(
            child: templatesAsync.when(
              data: (templates) {
                var filtered = templates;
                
                // Apply search filter
                if (searchQuery.isNotEmpty) {
                  filtered = filtered.where((t) =>
                    t.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    t.description.toLowerCase().contains(searchQuery.toLowerCase())
                  ).toList();
                }

                // Apply category filter
                if (category != null && category.isNotEmpty) {
                  // For now, no real category filtering since we don't have categories
                  // This would filter by template category in a real implementation
                }

                if (filtered.isEmpty) {
                  return _EmptyState(colors: colors, hasSearch: searchQuery.isNotEmpty);
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
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
                    Icon(LucideIcons.alertTriangle, size: 48, color: colors.error),
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
    return Row(
      children: [
        // Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sequence Templates',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: widget.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start with a template or save your sequences for reuse',
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.textMuted,
              ),
            ),
          ],
        ),

        const Spacer(),

        // Search
        Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: widget.colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    ref.read(templateSearchProvider.notifier).state = value;
                  },
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search templates...',
                    hintStyle: TextStyle(
                      fontSize: 13,
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
                  child: Icon(LucideIcons.x, size: 16, color: widget.colors.textMuted),
                ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // Save current as template button
        _ActionButton(
          colors: widget.colors,
          icon: LucideIcons.save,
          label: 'Save as Template',
          isPrimary: true,
          onPressed: () => _showSaveTemplateDialog(context),
        ),
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
            borderRadius: BorderRadius.circular(8),
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
                color: widget.isPrimary
                    ? Colors.white
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? Colors.white
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

class _TemplateCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence template;

  const _TemplateCard({
    required this.colors,
    required this.template,
  });

  @override
  ConsumerState<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends ConsumerState<_TemplateCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  IconData _getTemplateIcon() {
    final name = widget.template.name.toLowerCase();
    if (name.contains('lrgb')) return LucideIcons.palette;
    if (name.contains('narrowband') || name.contains('sho')) return LucideIcons.waves;
    if (name.contains('mosaic')) return LucideIcons.layoutGrid;
    if (name.contains('quick')) return LucideIcons.zap;
    if (name.contains('beginner')) return LucideIcons.graduationCap;
    return LucideIcons.fileStack;
  }

  Color _getTemplateColor() {
    final name = widget.template.name.toLowerCase();
    if (name.contains('lrgb')) return widget.colors.primary;
    if (name.contains('narrowband') || name.contains('sho')) return widget.colors.accent;
    if (name.contains('mosaic')) return widget.colors.warning;
    if (name.contains('quick')) return widget.colors.success;
    if (name.contains('beginner')) return widget.colors.info;
    return widget.colors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final templateColor = _getTemplateColor();

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _animController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _animController.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? templateColor.withValues(alpha: 0.6) : widget.colors.border,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: templateColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: () => _useTemplate(context),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and actions
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: templateColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getTemplateIcon(),
                          size: 24,
                          color: templateColor,
                        ),
                      ),
                      const Spacer(),
                      if (_isHovered) ...[
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.copy,
                          tooltip: 'Duplicate',
                          onPressed: () => _duplicateTemplate(context),
                        ),
                        const SizedBox(width: 4),
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.pencil,
                          tooltip: 'Edit',
                          onPressed: () => _editTemplate(context),
                        ),
                        const SizedBox(width: 4),
                        _SmallIconButton(
                          colors: widget.colors,
                          icon: LucideIcons.trash2,
                          tooltip: 'Delete',
                          color: widget.colors.error,
                          onPressed: () => _deleteTemplate(context),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.template.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: widget.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Description
                  Expanded(
                    child: Text(
                      widget.template.description.isEmpty ? 'No description' : widget.template.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Footer
                  Row(
                    children: [
                      // Stats
                      Row(
                        children: [
                          Icon(LucideIcons.layoutList, size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.template.nodes.length} nodes',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          Icon(LucideIcons.calendar, size: 12, color: widget.colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMd().format(widget.template.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textMuted,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Use button
                      AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: templateColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.play, size: 12, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Use',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _useTemplate(BuildContext context) {
    final currentSequence = ref.read(currentSequenceProvider);

    // Check if there are existing targets in the current sequence
    final existingTargets = currentSequence?.targetHeaders ?? [];

    if (existingTargets.length > 1) {
      // Multiple targets - prompt user to choose
      _showTargetSelectionDialog(context, existingTargets);
    } else if (existingTargets.length == 1) {
      // Single target - merge directly
      _applyTemplateToTarget(context, existingTargets.first);
    } else {
      // No existing targets - create a new sequence from template
      _createNewSequenceFromTemplate(context);
    }
  }

  void _showTargetSelectionDialog(BuildContext context, List<TargetHeaderNode> targets) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(LucideIcons.target, size: 20, color: widget.colors.warning),
            const SizedBox(width: 12),
            Text(
              'Select Target',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which target should "${widget.template.name}" be added to?',
              style: TextStyle(color: widget.colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...targets.map((target) => _TargetOption(
              colors: widget.colors,
              target: target,
              onTap: () {
                Navigator.of(dialogContext).pop();
                _applyTemplateToTarget(context, target);
              },
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: widget.colors.textMuted)),
          ),
        ],
      ),
    );
  }

  void _applyTemplateToTarget(BuildContext context, TargetHeaderNode target) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);

    sequenceNotifier.mergeTemplateNodes(
      templateNodes: widget.template.nodes,
      templateRootId: widget.template.rootNodeId,
      targetId: target.id,
    );

    // Switch to the Builder tab so user can see the result
    ref.read(sequencerTabProvider.notifier).state = 0;

context.showSuccessSnackBar('Added "${widget.template.name}" to ${target.targetName}');
  }

  void _createNewSequenceFromTemplate(BuildContext context) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};

    // Generate new IDs for all nodes
    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }

    // Clone nodes with new IDs and updated references
    for (final entry in widget.template.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId = oldNode.parentId != null ? idMapping[oldNode.parentId] : null;
      final newChildIds = oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    // Get the new root node ID
    final newRootId = widget.template.rootNodeId != null
        ? idMapping[widget.template.rootNodeId]
        : null;

    final newSequence = Sequence(
      name: '${widget.template.name} - Copy',
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    // Load the sequence
    sequenceNotifier.loadSequence(newSequence);

    // Switch to the Builder tab so user can see the loaded sequence
    ref.read(sequencerTabProvider.notifier).state = 0;

context.showSuccessSnackBar('Created sequence from "${widget.template.name}"');
  }

  void _editTemplate(BuildContext context) {
    // Load the template for editing and switch to Builder tab
    // Create a copy so we don't modify the original template
    final newNodes = <String, SequenceNode>{};
    final idMapping = <String, String>{};
    
    for (final entry in widget.template.nodes.entries) {
      final newId = const Uuid().v4();
      idMapping[entry.key] = newId;
    }
    
    for (final entry in widget.template.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId = oldNode.parentId != null ? idMapping[oldNode.parentId] : null;
      final newChildIds = oldNode.childIds.map((id) => idMapping[id] ?? id).toList();
      
      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }
    
    final newRootId = widget.template.rootNodeId != null 
        ? idMapping[widget.template.rootNodeId] 
        : null;
    
    final editableSequence = Sequence(
      name: widget.template.name,
      description: widget.template.description,
      nodes: newNodes,
      rootNodeId: newRootId,
      isTemplate: false,
    );

    ref.read(currentSequenceProvider.notifier).loadSequence(editableSequence);
    ref.read(sequencerTabProvider.notifier).state = 0;

    context.showInfoSnackBar('Editing "${widget.template.name}"');
  }

  Future<void> _duplicateTemplate(BuildContext context) async {
    // Check if template has a database ID
    final dbId = widget.template.databaseId;
    if (dbId != null) {
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        await repository.duplicateSequence(dbId, '${widget.template.name} (Copy)');
        
        // Refresh the templates list
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    } else {
      // Built-in template - save a copy to database
      try {
        final repository = ref.read(sequenceRepositoryProvider);
        final newTemplate = Sequence(
          name: '${widget.template.name} (Copy)',
          description: widget.template.description,
          nodes: widget.template.nodes,
          rootNodeId: widget.template.rootNodeId,
          isTemplate: true,
        );
        await repository.saveSequence(newTemplate, isTemplate: true);
        
        // Refresh the templates list
        ref.invalidate(sequenceTemplatesProvider);

        if (context.mounted) {
          context.showSuccessSnackBar('Duplicated "${widget.template.name}"');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to duplicate template: $e');
        }
      }
    }
  }

  void _deleteTemplate(BuildContext context) {
    // Check if this is a built-in template (no database ID)
    final dbId = widget.template.databaseId;
    if (dbId == null) {
      context.showInfoSnackBar('Built-in templates cannot be deleted');
      return;
    }

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Delete Template',
          style: TextStyle(color: widget.colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.template.name}"? This action cannot be undone.',
          style: TextStyle(color: widget.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: widget.colors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              
              try {
                final repository = ref.read(sequenceRepositoryProvider);
                await repository.deleteSequence(dbId);
                
                // Refresh the templates list
                ref.invalidate(sequenceTemplatesProvider);

                if (context.mounted) {
                  context.showSuccessSnackBar('Deleted "${widget.template.name}"');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showErrorSnackBar('Failed to delete template: $e');
                }
              }
            },
            child: Text('Delete', style: TextStyle(color: widget.colors.error)),
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;

  const _SmallIconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _isHovered ? color.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? color : widget.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;
  final bool hasSearch;

  const _EmptyState({
    required this.colors,
    this.hasSearch = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              hasSearch ? LucideIcons.searchX : LucideIcons.fileStack,
              size: 48,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            hasSearch ? 'No templates found' : 'No templates yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term'
                : 'Save your sequences as templates for easy reuse',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveTemplateDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SaveTemplateDialog({
    required this.colors,
    required this.sequence,
  });

  @override
  ConsumerState<_SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends ConsumerState<_SaveTemplateDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sequence.name);
    _descriptionController = TextEditingController(text: widget.sequence.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTemplate() async {
    if (_nameController.text.trim().isEmpty) {
      context.showErrorSnackBar('Please enter a template name');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(sequenceRepositoryProvider);
      
      // Create a new sequence with the template name and description
      final templateSequence = Sequence(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        nodes: widget.sequence.nodes,
        rootNodeId: widget.sequence.rootNodeId,
        isTemplate: true,
      );

      // Save to database as a template
      await repository.saveSequence(templateSequence, isTemplate: true);

      // Refresh the templates list
      ref.invalidate(sequenceTemplatesProvider);

      if (mounted) {
        Navigator.pop(context);

        context.showSuccessSnackBar('Template "${_nameController.text}" saved!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save template: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.save,
                    size: 20,
                    color: widget.colors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save as Template',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Save this sequence for later reuse',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Name field
            Text(
              'Template Name',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.colors.border),
              ),
              child: TextField(
                controller: _nameController,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter template name',
                  hintStyle: TextStyle(
                    color: widget.colors.textMuted,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Description field
            Text(
              'Description',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.colors.border),
              ),
              child: TextField(
                controller: _descriptionController,
                maxLines: 3,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Describe what this template is for...',
                  hintStyle: TextStyle(
                    color: widget.colors.textMuted,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Info about current sequence
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: widget.colors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This will save ${widget.sequence.nodes.length} nodes from the current sequence.',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: widget.colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: _isSaving ? 'Saving...' : 'Save Template',
                  icon: _isSaving ? LucideIcons.loader : LucideIcons.save,
                  onPressed: _isSaving ? null : _saveTemplate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable target option for the target selection dialog
class _TargetOption extends StatefulWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final VoidCallback onTap;

  const _TargetOption({
    required this.colors,
    required this.target,
    required this.onTap,
  });

  @override
  State<_TargetOption> createState() => _TargetOptionState();
}

class _TargetOptionState extends State<_TargetOption> {
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.warning.withValues(alpha: 0.1)
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered
                  ? widget.colors.warning
                  : widget.colors.border,
              width: _isHovered ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.target,
                  size: 16,
                  color: widget.colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.target.targetName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    Text(
                      'RA: ${_formatRA(widget.target.raHours)} · Dec: ${_formatDec(widget.target.decDegrees)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: _isHovered ? widget.colors.warning : widget.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    return '${hours}h ${minutes}m';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '';
    return '$sign${decDegrees.toStringAsFixed(1)}°';
  }
}
