import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class BuilderTab extends ConsumerWidget {
  const BuilderTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        // Left - Instruction palette (40%)
        Container(
          width: 320,
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: const [
                    _InstructionCategory(
                      title: 'Target',
                      instructions: [
                        _Instruction(icon: LucideIcons.target, name: 'Set Target'),
                        _Instruction(icon: LucideIcons.navigation, name: 'Slew to Coordinates'),
                      ],
                    ),
                    SizedBox(height: 16),
                    _InstructionCategory(
                      title: 'Imaging',
                      instructions: [
                        _Instruction(icon: LucideIcons.camera, name: 'Capture Exposures'),
                        _Instruction(icon: LucideIcons.sparkles, name: 'Smart Exposure'),
                      ],
                    ),
                    SizedBox(height: 16),
                    _InstructionCategory(
                      title: 'Mount',
                      instructions: [
                        _Instruction(icon: LucideIcons.crosshair, name: 'Slew & Center'),
                        _Instruction(icon: LucideIcons.parkingCircle, name: 'Park Mount'),
                        _Instruction(icon: LucideIcons.flipHorizontal, name: 'Meridian Flip'),
                      ],
                    ),
                    SizedBox(height: 16),
                    _InstructionCategory(
                      title: 'Focus',
                      instructions: [
                        _Instruction(icon: LucideIcons.focus, name: 'Autofocus'),
                        _Instruction(icon: LucideIcons.move, name: 'Move Focuser'),
                      ],
                    ),
                    SizedBox(height: 16),
                    _InstructionCategory(
                      title: 'Conditions',
                      instructions: [
                        _Instruction(icon: LucideIcons.clock, name: 'Wait for Time'),
                        _Instruction(icon: LucideIcons.mountain, name: 'Wait for Altitude'),
                        _Instruction(icon: LucideIcons.cloudSun, name: 'Weather Check'),
                        _Instruction(icon: LucideIcons.repeat, name: 'Loop / Repeat'),
                      ],
                    ),
                    SizedBox(height: 16),
                    _InstructionCategory(
                      title: 'Utilities',
                      instructions: [
                        _Instruction(icon: LucideIcons.code, name: 'Run Script'),
                        _Instruction(icon: LucideIcons.bell, name: 'Send Notification'),
                        _Instruction(icon: LucideIcons.pause, name: 'Pause Sequence'),
                      ],
                    ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Center - Sequence timeline (60%)
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: colors.background,
                  child: _buildSequenceTimeline(context, colors),
                ),
              ),

              // Bottom - Properties panel
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: _buildPropertiesPanel(context, colors),
              ),
            ],
          ),
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
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
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Or double-click an instruction to add it',
                      style: TextStyle(
                        fontSize: 12,
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Select an instruction to edit its properties',
              style: TextStyle(
                fontSize: 12,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Row(
            children: [
              Icon(
                _isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Draggable<_Instruction>(
        data: widget.instruction,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.instruction.icon, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  widget.instruction.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceHover : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
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
                  fontSize: 12,
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



