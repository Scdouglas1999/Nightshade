import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Legacy instruction-palette + timeline prototype.
///
/// Not mounted by [SequencerScreen] (the live builder uses [NodePalette],
/// [SequenceTree], and [NodePropertiesPanel]). Kept as a reference layout and
/// exercised by widget tests for responsive breakpoints.
class BuilderTab extends ConsumerWidget {
  const BuilderTab({super.key});

  /// Row layout when the viewport can fit palette + a readable timeline.
  static const double wideBreakpoint = 900;

  /// Below this width the palette stacks above the timeline.
  static const double compactBreakpoint = 600;

  static const double paletteDesignWidth = 320;
  static const double paletteMinWidth = 240;
  static const double minTimelineWidth = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final palette = _InstructionPalette(colors: colors);
        final workspace = _BuilderWorkspace(colors: colors);

        if (width >= wideBreakpoint &&
            width >= paletteMinWidth + minTimelineWidth) {
          final paletteWidth = AdaptiveDialogConstraints.clampPanelWidth(
            context,
            designWidth: paletteDesignWidth,
            minWidth: paletteMinWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: paletteWidth, child: palette),
              Expanded(child: workspace),
            ],
          );
        }

        if (width >= compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.38).clamp(200.0, 320.0),
                child: palette,
              ),
              Container(height: 1, color: colors.border),
              Expanded(child: workspace),
            ],
          );
        }

        return DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: colors.surface,
                child: TabBar(
                  labelColor: colors.primary,
                  unselectedLabelColor: colors.textMuted,
                  indicatorColor: colors.primary,
                  dividerColor: colors.border,
                  labelStyle: NightshadeTypography.h6,
                  unselectedLabelStyle: const TextStyle(fontSize: NightshadeTypography.fontSize12),
                  tabs: const [
                    Tab(text: 'Palette'),
                    Tab(text: 'Sequence'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    palette,
                    workspace,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InstructionPalette extends StatelessWidget {
  final NightshadeColors colors;

  const _InstructionPalette({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Instruction Palette',
              style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                _InstructionCategory(
                  title: 'Target',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.target, name: 'Set Target'),
                    _Instruction(
                        icon: LucideIcons.navigation,
                        name: 'Slew to Coordinates'),
                  ],
                ),
                SizedBox(height: 16),
                _InstructionCategory(
                  title: 'Imaging',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.camera,
                        name: 'Capture Exposures'),
                    _Instruction(
                        icon: LucideIcons.sparkles, name: 'Smart Exposure'),
                  ],
                ),
                SizedBox(height: 16),
                _InstructionCategory(
                  title: 'Mount',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.crosshair, name: 'Slew & Center'),
                    _Instruction(
                        icon: LucideIcons.parkingCircle,
                        name: 'Park Mount'),
                    _Instruction(
                        icon: LucideIcons.flipHorizontal,
                        name: 'Meridian Flip'),
                  ],
                ),
                SizedBox(height: 16),
                _InstructionCategory(
                  title: 'Focus',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.focus, name: 'Autofocus'),
                    _Instruction(
                        icon: LucideIcons.move, name: 'Move Focuser'),
                  ],
                ),
                SizedBox(height: 16),
                _InstructionCategory(
                  title: 'Conditions',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.clock, name: 'Wait for Time'),
                    _Instruction(
                        icon: LucideIcons.mountain,
                        name: 'Wait for Altitude'),
                    _Instruction(
                        icon: LucideIcons.cloudSun, name: 'Weather Check'),
                    _Instruction(
                        icon: LucideIcons.repeat, name: 'Loop / Repeat'),
                  ],
                ),
                SizedBox(height: 16),
                _InstructionCategory(
                  title: 'Utilities',
                  instructions: [
                    _Instruction(
                        icon: LucideIcons.code, name: 'Run Script'),
                    _Instruction(
                        icon: LucideIcons.bell, name: 'Send Notification'),
                    _Instruction(
                        icon: LucideIcons.pause, name: 'Pause Sequence'),
                  ],
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuilderWorkspace extends StatelessWidget {
  final NightshadeColors colors;

  const _BuilderWorkspace({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: colors.background,
            child: _buildSequenceTimeline(context, colors),
          ),
        ),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: _buildPropertiesPanel(context, colors),
        ),
      ],
    );
  }

  Widget _buildSequenceTimeline(BuildContext context, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sequence Timeline',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: colors.border),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.listPlus,
                      size: 48,
                      color: colors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Drag instructions here',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Or double-click an instruction to add it',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textMuted,
                      ),
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

  Widget _buildPropertiesPanel(BuildContext context, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Instruction Properties',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Select an instruction to edit its properties',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCategory extends StatefulWidget {
  final String title;
  final List<_Instruction> instructions;

  const _InstructionCategory({
    required this.title,
    required this.instructions,
  });

  @override
  State<_InstructionCategory> createState() => _InstructionCategoryState();
}

class _InstructionCategoryState extends State<_InstructionCategory> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Row(
            children: [
              Icon(
                _isExpanded
                    ? LucideIcons.chevronDown
                    : LucideIcons.chevronRight,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: NightshadeTypography.h6.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          ...widget.instructions.map((instruction) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _InstructionItem(instruction: instruction),
              )),
        ],
      ],
    );
  }
}

class _Instruction {
  final IconData icon;
  final String name;

  const _Instruction({required this.icon, required this.name});
}

class _InstructionItem extends StatefulWidget {
  final _Instruction instruction;

  const _InstructionItem({required this.instruction});

  @override
  State<_InstructionItem> createState() => _InstructionItemState();
}

class _InstructionItemState extends State<_InstructionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Draggable<_Instruction>(
        data: widget.instruction,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.instruction.icon, size: 14, color: onPrimary),
                const SizedBox(width: 8),
                Text(
                  widget.instruction.name,
                  style: NightshadeTypography.labelSm.copyWith(color: onPrimary),
                ),
              ],
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceHover : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                widget.instruction.icon,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.instruction.name,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
