import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';

class NodePropertiesPanel extends ConsumerWidget {
  final NightshadeColors colors;
  final ScrollController? scrollController;
  final bool isMobileSheet;
  final VoidCallback? onClose;
  final VoidCallback? onCollapse;

  const NodePropertiesPanel({
    super.key,
    required this.colors,
    this.scrollController,
    this.isMobileSheet = false,
    this.onClose,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNode = ref.watch(selectedNodeProvider);

    if (isMobileSheet) {
      return _buildMobileSheetContent(context, ref, selectedNode);
    }
    return _buildDesktopSidebarContent(context, ref, selectedNode);
  }

  Widget _buildMobileSheetContent(
      BuildContext context, WidgetRef ref, SequenceNode? selectedNode) {
    return Column(
      children: [
        // Handle bar
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header with close button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                LucideIcons.settings2,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Properties',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        Divider(color: colors.border, height: 1),

        // Content
        Expanded(
          child: selectedNode == null
              ? _EmptySelection(colors: colors, isMobile: true)
              : _NodeEditor(
                  colors: colors,
                  node: selectedNode,
                  scrollController: scrollController,
                  isMobile: true,
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarContent(
      BuildContext context, WidgetRef ref, SequenceNode? selectedNode) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.settings2,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Properties',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: onCollapse,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          LucideIcons.panelRightClose,
                          size: 16,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: selectedNode == null
                ? _EmptySelection(colors: colors)
                : _NodeEditor(
                    colors: colors,
                    node: selectedNode,
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickTimeButton extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final VoidCallback onPressed;

  const _QuickTimeButton({
    required this.colors,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const _EmptySelection({required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mousePointer,
            size: isMobile ? 40 : 32,
            color: colors.textMuted,
          ),
          SizedBox(height: isMobile ? 16 : 12),
          Text(
            'Select a node',
            style: TextStyle(
              fontSize: isMobile ? 16 : 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'to view its properties',
            style: TextStyle(
              fontSize: isMobile ? 14 : 11,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeEditor extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final ScrollController? scrollController;
  final bool isMobile;

  const _NodeEditor({
    required this.colors,
    required this.node,
    this.scrollController,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.all(isMobile ? 20 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node type badge
          _NodeTypeBadge(colors: colors, node: node),
          const SizedBox(height: 16),

          // Name field
          _PropertyField(
            colors: colors,
            label: 'Name',
            child: _TextInput(
              colors: colors,
              value: node.name,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(name: value),
                    );
              },
            ),
          ),

          // Enabled toggle
          _PropertyField(
            colors: colors,
            label: 'Enabled',
            child: _ToggleSwitch(
              colors: colors,
              value: node.isEnabled,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(isEnabled: value),
                    );
              },
            ),
          ),

          const Divider(height: 32),

          // Type-specific properties
          _buildTypeSpecificProperties(ref),

          const SizedBox(height: 24),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: _DangerButton(
              colors: colors,
              label: 'Delete Node',
              icon: LucideIcons.trash2,
              onPressed: () {
                ref.read(currentSequenceProvider.notifier).removeNode(node.id);
                ref.read(selectedNodeIdProvider.notifier).state = null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSpecificProperties(WidgetRef ref) {
    // Build the main properties widget
    Widget propertiesWidget;

    if (node is ExposureNode) {
      propertiesWidget =
          _ExposureProperties(colors: colors, node: node as ExposureNode);
    } else if (node is TargetHeaderNode) {
      propertiesWidget = _TargetGroupProperties(
          colors: colors, node: node as TargetHeaderNode);
    } else if (node is LoopNode) {
      propertiesWidget =
          _LoopProperties(colors: colors, node: node as LoopNode);
    } else if (node is CenterNode) {
      propertiesWidget =
          _CenterProperties(colors: colors, node: node as CenterNode);
    } else if (node is AutofocusNode) {
      propertiesWidget =
          _AutofocusProperties(colors: colors, node: node as AutofocusNode);
    } else if (node is CoolCameraNode) {
      propertiesWidget =
          _CoolCameraProperties(colors: colors, node: node as CoolCameraNode);
    } else if (node is FilterChangeNode) {
      propertiesWidget = _FilterChangeProperties(
          colors: colors, node: node as FilterChangeNode);
    } else if (node is DelayNode) {
      propertiesWidget =
          _DelayProperties(colors: colors, node: node as DelayNode);
    } else if (node is DitherNode) {
      propertiesWidget =
          _DitherProperties(colors: colors, node: node as DitherNode);
    } else if (node is WarmCameraNode) {
      propertiesWidget =
          _WarmCameraProperties(colors: colors, node: node as WarmCameraNode);
    } else if (node is RotatorNode) {
      propertiesWidget =
          _RotatorProperties(colors: colors, node: node as RotatorNode);
    } else if (node is SlewNode) {
      propertiesWidget =
          _SlewProperties(colors: colors, node: node as SlewNode);
    } else if (node is WaitTimeNode) {
      propertiesWidget =
          _WaitTimeProperties(colors: colors, node: node as WaitTimeNode);
    } else if (node is ConditionalNode) {
      propertiesWidget =
          _ConditionalProperties(colors: colors, node: node as ConditionalNode);
    } else if (node is ParallelNode) {
      propertiesWidget =
          _ParallelProperties(colors: colors, node: node as ParallelNode);
    } else if (node is RecoveryNode) {
      propertiesWidget =
          _RecoveryProperties(colors: colors, node: node as RecoveryNode);
    } else if (node is NotificationNode) {
      propertiesWidget = _NotificationProperties(
          colors: colors, node: node as NotificationNode);
    } else if (node is ScriptNode) {
      propertiesWidget =
          _ScriptProperties(colors: colors, node: node as ScriptNode);
    } else if (node is ParkNode || node is UnparkNode) {
      propertiesWidget = _SimpleInstructionInfo(colors: colors, node: node);
    } else if (node is MeridianFlipNode) {
      propertiesWidget = _MeridianFlipProperties(
          colors: colors, node: node as MeridianFlipNode);
    } else if (node is OpenDomeNode) {
      propertiesWidget = _DomeProperties(colors: colors, node: node);
    } else if (node is CloseDomeNode) {
      propertiesWidget = _DomeProperties(colors: colors, node: node);
    } else if (node is ParkDomeNode) {
      propertiesWidget = _DomeProperties(colors: colors, node: node);
    } else if (node is PolarAlignmentNode) {
      propertiesWidget = _PolarAlignmentProperties(
          colors: colors, node: node as PolarAlignmentNode);
    } else if (node is InstructionSetNode) {
      propertiesWidget =
          _InstructionSetInfo(colors: colors, node: node as InstructionSetNode);
    } else {
      propertiesWidget = Text(
        'No additional properties',
        style: TextStyle(
          fontSize: 12,
          color: colors.textMuted,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Add timing section for nodes with meaningful duration
    if (_hasMeaningfulDuration(node)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          propertiesWidget,
          const SizedBox(height: 16),
          _TimingSection(colors: colors, node: node),
        ],
      );
    }

    return propertiesWidget;
  }
}

class _NodeTypeBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _NodeTypeBadge({required this.colors, required this.node});

  Color _getCategoryColor() {
    switch (node.category) {
      case NodeCategory.instruction:
        return colors.primary;
      case NodeCategory.trigger:
        return colors.warning;
      case NodeCategory.logic:
        return colors.accent;
      case NodeCategory.target:
        return colors.warning;
    }
  }

  IconData _getIcon() {
    switch (node.iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      default:
        return LucideIcons.box;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getIcon(), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.nodeType,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  node.category.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.5,
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

// Property field wrapper
class _PropertyField extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final Widget child;

  const _PropertyField({
    required this.colors,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

// Input widgets
class _TextInput extends StatefulWidget {
  final NightshadeColors colors;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  const _TextInput({
    required this.colors,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: 13,
          color: widget.colors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: widget.colors.textMuted,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _NumberInput extends StatefulWidget {
  final NightshadeColors colors;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final double? min;
  final double? max;
  final int decimals;

  const _NumberInput({
    required this.colors,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min,
    this.max,
    this.decimals = 0,
  });

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final hadFocus = _hasFocus;
    _hasFocus = _focusNode.hasFocus;

    // When losing focus, update to the canonical value format
    if (hadFocus && !_hasFocus) {
      final newText = widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals);
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void didUpdateWidget(_NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the field doesn't have focus (user isn't typing)
    if (!_hasFocus && oldWidget.value != widget.value) {
      final newText = widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals);
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  var clamped = parsed;
                  if (widget.min != null)
                    clamped = clamped.clamp(widget.min!, double.infinity);
                  if (widget.max != null)
                    clamped =
                        clamped.clamp(double.negativeInfinity, widget.max!);
                  widget.onChanged(clamped);
                }
              },
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: TextStyle(
                fontSize: 12,
                color: widget.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final NightshadeColors colors;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.primary : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? colors.primary : colors.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final NightshadeColors colors;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.colors,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: 13,
            color: colors.textPrimary,
          ),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(labelBuilder(item)),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ),
    );
  }
}

class _DangerButton extends StatefulWidget {
  final NightshadeColors colors;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _DangerButton({
    required this.colors,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.error.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? widget.colors.error : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered
                    ? widget.colors.error
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isHovered
                      ? widget.colors.error
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

// Type-specific property editors
class _ExposureProperties extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ExposureNode node;

  const _ExposureProperties({required this.colors, required this.node});

  @override
  ConsumerState<_ExposureProperties> createState() =>
      _ExposurePropertiesState();
}

class _ExposurePropertiesState extends ConsumerState<_ExposureProperties> {
  // Track whether values are using profile defaults (not explicitly set)
  bool _gainIsProfileDefault = false;
  bool _offsetIsProfileDefault = false;
  bool _binningIsProfileDefault = false;

  @override
  void initState() {
    super.initState();
    _checkProfileDefaults();
  }

  @override
  void didUpdateWidget(_ExposureProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _checkProfileDefaults();
    }
  }

  void _checkProfileDefaults() {
    final profile = ref.read(activeEquipmentProfileProvider);
    final node = widget.node;

    // Check if gain matches profile default (or is null/0 and profile has a default)
    _gainIsProfileDefault = node.gain == null ||
        (profile?.defaultGain != null && node.gain == profile!.defaultGain);

    // Check if offset matches profile default
    _offsetIsProfileDefault = node.offset == null ||
        (profile?.defaultOffset != null &&
            node.offset == profile!.defaultOffset);

    // Check if binning matches profile default
    final profileBinning = profile?.defaultBinX ?? 1;
    final nodeBinningValue = _binningModeToInt(node.binning);
    _binningIsProfileDefault = nodeBinningValue == profileBinning;
  }

  int _binningModeToInt(BinningMode mode) {
    switch (mode) {
      case BinningMode.one:
        return 1;
      case BinningMode.two:
        return 2;
      case BinningMode.three:
        return 3;
      case BinningMode.four:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;
    final profile = ref.watch(activeEquipmentProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exposure Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        _PropertyField(
          colors: colors,
          label: 'Duration',
          child: _NumberInput(
            colors: colors,
            value: node.durationSecs,
            suffix: 's',
            min: 0.001,
            max: 3600,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(durationSecs: value),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    duration: value,
                  );
            },
          ),
        ),

        _PropertyField(
          colors: colors,
          label: 'Count',
          child: _NumberInput(
            colors: colors,
            value: node.count.toDouble(),
            min: 1,
            max: 9999,
            onChanged: (value) {
              final count = value.toInt();
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(count: count),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    count: count,
                  );
            },
          ),
        ),

        _PropertyField(
          colors: colors,
          label: 'Frame Type',
          child: _Dropdown<FrameType>(
            colors: colors,
            value: node.frameType,
            items: FrameType.values,
            labelBuilder: (t) => t.name.toUpperCase(),
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(frameType: value),
                  );
            },
          ),
        ),

        _buildFilterDropdown(context),

        // Binning with profile default indicator
        _PropertyField(
          colors: colors,
          label: _binningIsProfileDefault
              ? 'Binning (profile default)'
              : 'Binning',
          child: _Dropdown<BinningMode>(
            colors: colors,
            value: node.binning,
            items: BinningMode.values,
            labelBuilder: (b) => b.label,
            onChanged: (value) {
              setState(() => _binningIsProfileDefault = false);
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(binning: value),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    binning: value,
                  );
            },
          ),
        ),

        // Gain and Offset with profile default indicators
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: _gainIsProfileDefault
                    ? 'Gain (profile default)'
                    : 'Gain',
                child: _NumberInputWithHint(
                  colors: colors,
                  value: (node.gain ?? profile?.defaultGain ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  hintText: _gainIsProfileDefault && profile?.defaultGain != null
                      ? '(profile: ${profile!.defaultGain})'
                      : null,
                  onChanged: (value) {
                    final gain = value.toInt();
                    setState(() => _gainIsProfileDefault = false);
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(gain: gain),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          gain: gain,
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: _offsetIsProfileDefault
                    ? 'Offset (profile default)'
                    : 'Offset',
                child: _NumberInputWithHint(
                  colors: colors,
                  value: (node.offset ?? profile?.defaultOffset ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  hintText:
                      _offsetIsProfileDefault && profile?.defaultOffset != null
                          ? '(profile: ${profile!.defaultOffset})'
                          : null,
                  onChanged: (value) {
                    final offset = value.toInt();
                    setState(() => _offsetIsProfileDefault = false);
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(offset: offset),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          offset: offset,
                        );
                  },
                ),
              ),
            ),
          ],
        ),

        _PropertyField(
          colors: colors,
          label: 'Dither Every',
          child: _NumberInput(
            colors: colors,
            value: (node.ditherEvery ?? 0).toDouble(),
            suffix: ' frames',
            min: 0,
            max: 100,
            onChanged: (value) {
              final ditherEvery = value.toInt();
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(ditherEvery: ditherEvery),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    ditherEvery: ditherEvery,
                  );
            },
          ),
        ),

        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, size: 14, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Total: ${_formatDuration(node.totalDurationSecs)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;

    // Get filter names from active profile
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? <String>[];

    // Build list of filter options with their indices
    final filterOptions = <({int index, String name})>[
      (index: -1, name: ''), // No filter option
      for (int i = 0; i < filterNames.length; i++)
        (index: i, name: filterNames[i]),
    ];

    // Find current selection
    final currentFilter = filterOptions.firstWhere(
      (f) =>
          (node.filterIndex != null && f.index == node.filterIndex) ||
          (node.filterIndex == null && f.name == (node.filter ?? '')),
      orElse: () => filterOptions.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PropertyField(
          colors: colors,
          label: 'Filter',
          child: filterNames.isEmpty
              ? _TextInput(
                  colors: colors,
                  value: node.filter ?? '',
                  hint: 'No filters in profile',
                  onChanged: (value) {
                    final filter = value.isEmpty ? null : value;
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(filter: filter),
                        );
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          filter: filter,
                        );
                  },
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<({int index, String name})>(
                      value: currentFilter,
                      isExpanded: true,
                      icon: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      items: filterOptions.map((filter) {
                        return DropdownMenuItem(
                          value: filter,
                          child: Text(filter.index < 0 ? '(None)' : filter.name),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          final filter =
                              newValue.index < 0 ? null : newValue.name;
                          final filterIndex =
                              newValue.index < 0 ? null : newValue.index;
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(
                                  filter: filter,
                                  filterIndex: filterIndex,
                                ),
                              );
                          ref
                              .read(sequencerDefaultsProvider.notifier)
                              .updateExposureDefaults(
                                filter: filter,
                              );
                        }
                      },
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ProfileEditorDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.settings, size: 12, color: colors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Edit filters...',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toStringAsFixed(1)}s';
    if (secs < 3600) return '${(secs / 60).toStringAsFixed(1)}m';
    return '${(secs / 3600).toStringAsFixed(1)}h';
  }
}

/// Number input for integer values (gain/offset)
/// Simplified version of _NumberInput for integer inputs only.
class _NumberInputWithHint extends StatefulWidget {
  final NightshadeColors colors;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final String? hintText;

  const _NumberInputWithHint({
    required this.colors,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.hintText,
  });

  @override
  State<_NumberInputWithHint> createState() => _NumberInputWithHintState();
}

class _NumberInputWithHintState extends State<_NumberInputWithHint> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.toInt().toString(),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final hadFocus = _hasFocus;
    _hasFocus = _focusNode.hasFocus;

    // When losing focus, update to the canonical value format
    if (hadFocus && !_hasFocus) {
      final newText = widget.value.toInt().toString();
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void didUpdateWidget(_NumberInputWithHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the field doesn't have focus (user isn't typing)
    if (!_hasFocus && oldWidget.value != widget.value) {
      final newText = widget.value.toInt().toString();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        onChanged: (value) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            var clamped = parsed;
            if (widget.min != null) {
              clamped = clamped.clamp(widget.min!, double.infinity);
            }
            if (widget.max != null) {
              clamped = clamped.clamp(double.negativeInfinity, widget.max!);
            }
            widget.onChanged(clamped);
          }
        },
        style: TextStyle(
          fontSize: 13,
          color: widget.colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _TargetGroupProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;

  const _TargetGroupProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Name',
          child: _TextInput(
            colors: colors,
            value: node.targetName,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetName: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'RA (hours)',
                child: _NumberInput(
                  colors: colors,
                  value: node.raHours,
                  suffix: 'h',
                  min: 0,
                  max: 24,
                  decimals: 4,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(raHours: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Dec (degrees)',
                child: _NumberInput(
                  colors: colors,
                  value: node.decDegrees,
                  suffix: '°',
                  min: -90,
                  max: 90,
                  decimals: 4,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(decDegrees: value),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        _PropertyField(
          colors: colors,
          label: 'Rotation (optional)',
          child: _NumberInput(
            colors: colors,
            value: node.rotation ?? 0,
            suffix: '°',
            min: 0,
            max: 360,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(rotation: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Min Altitude',
          child: _NumberInput(
            colors: colors,
            value: node.minAltitude ?? 30,
            suffix: '°',
            min: 0,
            max: 90,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(minAltitude: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _LoopProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final LoopNode node;

  const _LoopProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Loop Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Condition Type',
          child: _Dropdown<LoopConditionType>(
            colors: colors,
            value: node.conditionType,
            items: LoopConditionType.values,
            labelBuilder: (t) {
              switch (t) {
                case LoopConditionType.count:
                  return 'Fixed Count';
                case LoopConditionType.untilTime:
                  return 'Until Time';
                case LoopConditionType.untilAltitude:
                  return 'Until Altitude';
                case LoopConditionType.forever:
                  return 'Forever';
                case LoopConditionType.whileDark:
                  return 'While Dark';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(conditionType: value),
                  );
            },
          ),
        ),
        if (node.conditionType == LoopConditionType.count)
          _PropertyField(
            colors: colors,
            label: 'Repeat Count',
            child: _NumberInput(
              colors: colors,
              value: (node.repeatCount ?? 1).toDouble(),
              min: 1,
              max: 9999,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatCount: value.toInt()),
                    );
              },
            ),
          ),
        if (node.conditionType == LoopConditionType.untilTime)
          _PropertyField(
            colors: colors,
            label: 'Stop Time',
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                          node.repeatUntil ?? DateTime.now()),
                    );
                    if (time != null) {
                      final now = DateTime.now();
                      var targetDate = DateTime(
                          now.year, now.month, now.day, time.hour, time.minute);
                      if (targetDate.isBefore(now)) {
                        targetDate = targetDate.add(const Duration(days: 1));
                      }
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(repeatUntil: targetDate),
                          );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.clock,
                            size: 14, color: colors.textMuted),
                        const SizedBox(width: 8),
                        Text(
                          node.repeatUntil != null
                              ? '${node.repeatUntil!.hour.toString().padLeft(2, '0')}:${node.repeatUntil!.minute.toString().padLeft(2, '0')}'
                              : 'Select time...',
                          style: TextStyle(
                            fontSize: 13,
                            color: node.repeatUntil != null
                                ? colors.textPrimary
                                : colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Quick set buttons for common times
                Row(
                  children: [
                    _QuickTimeButton(
                      colors: colors,
                      label: 'Civil Dawn',
                      onPressed: () {
                        final location = ref.read(observerLocationProvider);
                        final now = DateTime.now();

                        // Calculate for today first
                        var twilight =
                            AstronomyCalculations.calculateTwilightTimes(
                          date: now,
                          latitudeDeg: location.latitude,
                          longitudeDeg: location.longitude,
                        );

                        var target = twilight.civilDawn;

                        // If dawn passed or not available today, try tomorrow
                        if (target == null || target.isBefore(now)) {
                          twilight =
                              AstronomyCalculations.calculateTwilightTimes(
                            date: now.add(const Duration(days: 1)),
                            latitudeDeg: location.latitude,
                            longitudeDeg: location.longitude,
                          );
                          target = twilight.civilDawn;
                        }

                        if (target != null) {
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(repeatUntil: target),
                              );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _QuickTimeButton(
                      colors: colors,
                      label: 'Nautical Dawn',
                      onPressed: () {
                        final location = ref.read(observerLocationProvider);
                        final now = DateTime.now();

                        // Calculate for today first
                        var twilight =
                            AstronomyCalculations.calculateTwilightTimes(
                          date: now,
                          latitudeDeg: location.latitude,
                          longitudeDeg: location.longitude,
                        );

                        var target = twilight.nauticalDawn;

                        // If dawn passed or not available today, try tomorrow
                        if (target == null || target.isBefore(now)) {
                          twilight =
                              AstronomyCalculations.calculateTwilightTimes(
                            date: now.add(const Duration(days: 1)),
                            latitudeDeg: location.latitude,
                            longitudeDeg: location.longitude,
                          );
                          target = twilight.nauticalDawn;
                        }

                        if (target != null) {
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(repeatUntil: target),
                              );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (node.conditionType == LoopConditionType.untilAltitude)
          _PropertyField(
            colors: colors,
            label: 'Stop Below Altitude',
            child: _NumberInput(
              colors: colors,
              value: node.repeatUntilAltitude ?? 30,
              suffix: '°',
              min: 0,
              max: 90,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatUntilAltitude: value),
                    );
              },
            ),
          ),
      ],
    );
  }
}

class _CenterProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CenterNode node;

  const _CenterProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Centering Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Accuracy',
          child: _NumberInput(
            colors: colors,
            value: node.accuracyArcsec,
            suffix: '"',
            min: 0.1,
            max: 60,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(accuracyArcsec: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Attempts',
          child: _NumberInput(
            colors: colors,
            value: node.maxAttempts.toDouble(),
            min: 1,
            max: 20,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxAttempts: value.toInt()),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _AutofocusProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final AutofocusNode node;

  const _AutofocusProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Autofocus Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Method',
          child: _Dropdown<AutofocusMethod>(
            colors: colors,
            value: node.method,
            items: AutofocusMethod.values,
            labelBuilder: (m) {
              switch (m) {
                case AutofocusMethod.vCurve:
                  return 'V-Curve';
                case AutofocusMethod.hyperbolic:
                  return 'Hyperbolic';
                case AutofocusMethod.parabolic:
                  return 'Parabolic';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(method: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Step Size',
                child: _NumberInput(
                  colors: colors,
                  value: node.stepSize.toDouble(),
                  min: 1,
                  max: 1000,
                  onChanged: (value) {
                    final stepSize = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepSize: stepSize),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepSize: stepSize,
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Steps Out',
                child: _NumberInput(
                  colors: colors,
                  value: node.stepsOut.toDouble(),
                  min: 3,
                  max: 15,
                  onChanged: (value) {
                    final stepsOut = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepsOut: stepsOut),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepsOut: stepsOut,
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        _PropertyField(
          colors: colors,
          label: 'Exposure Duration',
          child: _NumberInput(
            colors: colors,
            value: node.exposureDuration,
            suffix: 's',
            min: 0.5,
            max: 30,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(exposureDuration: value),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateAutofocusDefaults(
                    exposureDuration: value,
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _CoolCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CoolCameraNode node;

  const _CoolCameraProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cooling Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Temperature',
          child: _NumberInput(
            colors: colors,
            value: node.targetTemp,
            suffix: '°C',
            min: -50,
            max: 30,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetTemp: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Duration',
          child: _NumberInput(
            colors: colors,
            value: node.durationMins ?? 10,
            suffix: 'min',
            min: 1,
            max: 60,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(durationMins: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChangeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final FilterChangeNode node;

  const _FilterChangeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get filter names from active profile
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? <String>[];

    // Build list of filter options with their indices
    // Each item is a record of (index, name)
    final filterOptions = <({int index, String name})>[
      for (int i = 0; i < filterNames.length; i++)
        (index: i, name: filterNames[i]),
    ];

    // Find current selection, or default to first if not found
    final currentFilter = filterOptions.isEmpty
        ? null
        : filterOptions.firstWhere(
            (f) => f.name == node.filterName || f.index == node.filterPosition,
            orElse: () => filterOptions.first,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Filter',
          child: filterOptions.isEmpty
              ? _TextInput(
                  colors: colors,
                  value: node.filterName,
                  hint: 'No filters in profile',
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(filterName: value),
                        );
                  },
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<({int index, String name})>(
                      value: currentFilter,
                      isExpanded: true,
                      icon: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      items: filterOptions.map((filter) {
                        return DropdownMenuItem(
                          value: filter,
                          child: Text(filter.name),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          // Set BOTH name and position for reliable filter changes
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(
                                  filterName: newValue.name,
                                  filterPosition: newValue.index,
                                ),
                              );
                        }
                      },
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ProfileEditorDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.settings, size: 12, color: colors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Edit filters...',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DelayProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DelayNode node;

  const _DelayProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delay Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Duration',
          child: _NumberInput(
            colors: colors,
            value: node.seconds,
            suffix: 's',
            min: 0.1,
            max: 3600,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(seconds: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _DitherProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DitherNode node;

  const _DitherProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dither Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Dither Amount',
          child: _NumberInput(
            colors: colors,
            value: node.pixels,
            suffix: 'px',
            min: 1,
            max: 50,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(pixels: value),
                  );
              // Save as default for future nodes
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    pixels: value,
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Time',
          child: _NumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 5,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTime: value),
                  );
              // Save as default for future nodes
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    settleTime: value,
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Threshold',
          child: _NumberInput(
            colors: colors,
            value: node.settlePixels,
            suffix: 'px',
            min: 0.1,
            max: 5,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settlePixels: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _WarmCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WarmCameraNode node;

  const _WarmCameraProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Warming Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Warming Rate',
          child: _NumberInput(
            colors: colors,
            value: node.ratePerMin,
            suffix: '°C/min',
            min: 0.5,
            max: 10,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(ratePerMin: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gradual warming prevents thermal shock to the sensor',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.warning,
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

class _RotatorProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RotatorNode node;

  const _RotatorProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotator Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Angle',
          child: _NumberInput(
            colors: colors,
            value: node.targetAngle,
            suffix: '°',
            min: 0,
            max: 360,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetAngle: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Relative Movement',
          child: _ToggleSwitch(
            colors: colors,
            value: node.relative,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(relative: value),
                  );
            },
          ),
        ),
        Text(
          node.relative
              ? 'Rotates relative to current position'
              : 'Moves to absolute position angle',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _SlewProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SlewNode node;

  const _SlewProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slew Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Use Target Coordinates',
          child: _ToggleSwitch(
            colors: colors,
            value: node.useTargetCoords,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(useTargetCoords: value),
                  );
            },
          ),
        ),
        if (!node.useTargetCoords) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PropertyField(
                  colors: colors,
                  label: 'RA (hours)',
                  child: _NumberInput(
                    colors: colors,
                    value: node.customRa ?? 0,
                    suffix: 'h',
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customRa: value),
                          );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PropertyField(
                  colors: colors,
                  label: 'Dec (degrees)',
                  child: _NumberInput(
                    colors: colors,
                    value: node.customDec ?? 0,
                    suffix: '°',
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customDec: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        if (node.useTargetCoords) ...[
          Builder(
            builder: (context) {
              final sequence = ref.watch(currentSequenceProvider);
              TargetHeaderNode? targetGroup;

              if (sequence != null) {
                // Try to find parent target group first
                try {
                  targetGroup = sequence.nodes.values
                      .whereType<TargetHeaderNode>()
                      .where((n) => n.childIds.contains(node.id))
                      .first;
                } catch (e) {
                  // No direct parent found
                }

                // If no direct parent, use first target group in sequence
                if (targetGroup == null && sequence.targetHeaders.isNotEmpty) {
                  targetGroup = sequence.targetHeaders.first;
                }
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: targetGroup != null
                      ? colors.success.withValues(alpha: 0.1)
                      : colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      targetGroup != null
                          ? LucideIcons.checkCircle
                          : LucideIcons.alertCircle,
                      size: 14,
                      color:
                          targetGroup != null ? colors.success : colors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetGroup != null
                            ? 'Will use target: ${targetGroup.targetName}\nRA: ${targetGroup.raHours.toStringAsFixed(4)}h, Dec: ${targetGroup.decDegrees.toStringAsFixed(4)}°'
                            : 'No target group found in sequence',
                        style: TextStyle(
                          fontSize: 11,
                          color: targetGroup != null
                              ? colors.success
                              : colors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _WaitTimeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WaitTimeNode node;

  const _WaitTimeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wait Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Wait For',
          child: _Dropdown<String>(
            colors: colors,
            value: node.waitForTwilight != null ? 'twilight' : 'time',
            items: const ['time', 'twilight'],
            labelBuilder: (v) => v == 'time' ? 'Specific Time' : 'Twilight',
            onChanged: (value) {
              if (value == 'twilight') {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(
                          waitForTwilight: TwilightType.astronomical,
                          waitUntil: null),
                    );
              } else {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(waitForTwilight: null),
                    );
              }
            },
          ),
        ),
        if (node.waitForTwilight != null) ...[
          _PropertyField(
            colors: colors,
            label: 'Twilight Type',
            child: _Dropdown<TwilightType>(
              colors: colors,
              value: node.waitForTwilight!,
              items: TwilightType.values,
              labelBuilder: (t) {
                switch (t) {
                  case TwilightType.civil:
                    return 'Civil (-6°)';
                  case TwilightType.nautical:
                    return 'Nautical (-12°)';
                  case TwilightType.astronomical:
                    return 'Astronomical (-18°)';
                }
              },
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(waitForTwilight: value),
                    );
              },
            ),
          ),
        ],
        if (node.waitForTwilight == null) ...[
          _PropertyField(
            colors: colors,
            label: 'Wait Until',
            child: GestureDetector(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var targetDate = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  if (targetDate.isBefore(now)) {
                    targetDate = targetDate.add(const Duration(days: 1));
                  }
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(waitUntil: targetDate),
                      );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      node.waitUntil != null
                          ? '${node.waitUntil!.hour.toString().padLeft(2, '0')}:${node.waitUntil!.minute.toString().padLeft(2, '0')}'
                          : 'Select time...',
                      style: TextStyle(
                        fontSize: 13,
                        color: node.waitUntil != null
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConditionalProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ConditionalNode node;

  const _ConditionalProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Condition Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Condition Type',
          child: _Dropdown<ConditionalType>(
            colors: colors,
            value: node.conditionType,
            items: ConditionalType.values,
            labelBuilder: (t) {
              switch (t) {
                case ConditionalType.always:
                  return 'Always Execute';
                case ConditionalType.altitudeAbove:
                  return 'Altitude Above';
                case ConditionalType.timeAfter:
                  return 'Time After';
                case ConditionalType.guidingRmsBelow:
                  return 'Guiding RMS Below';
                case ConditionalType.hfrBelow:
                  return 'HFR Below';
                case ConditionalType.weatherSafe:
                  return 'Weather is Safe';
                case ConditionalType.moonSeparationAbove:
                  return 'Moon Separation Above';
                case ConditionalType.safetyMonitorSafe:
                  return 'Safety Monitor Safe';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(conditionType: value),
                  );
            },
          ),
        ),
        if (node.conditionType == ConditionalType.altitudeAbove ||
            node.conditionType == ConditionalType.moonSeparationAbove)
          _PropertyField(
            colors: colors,
            label: 'Threshold (degrees)',
            child: _NumberInput(
              colors: colors,
              value: node.thresholdValue ?? 30,
              suffix: '°',
              min: 0,
              max: 90,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
        if (node.conditionType == ConditionalType.guidingRmsBelow)
          _PropertyField(
            colors: colors,
            label: 'Max RMS (arcsec)',
            child: _NumberInput(
              colors: colors,
              value: node.thresholdValue ?? 1.5,
              suffix: '"',
              min: 0.1,
              max: 10,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
        if (node.conditionType == ConditionalType.hfrBelow)
          _PropertyField(
            colors: colors,
            label: 'Max HFR (pixels)',
            child: _NumberInput(
              colors: colors,
              value: node.thresholdValue ?? 3.0,
              suffix: 'px',
              min: 0.5,
              max: 20,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
      ],
    );
  }
}

class _ParallelProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ParallelNode node;

  const _ParallelProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parallel Execution',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Required Successes',
          child: _NumberInput(
            colors: colors,
            value: (node.requiredSuccesses ?? 1).toDouble(),
            min: 1,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(requiredSuccesses: value.toInt()),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All child nodes will execute simultaneously. Node succeeds when required number of children complete.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.info,
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

class _RecoveryProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RecoveryNode node;

  const _RecoveryProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Trigger Type',
          child: _Dropdown<TriggerType?>(
            colors: colors,
            value: node.triggerType,
            items: const [null, ...TriggerType.values],
            labelBuilder: (t) {
              if (t == null) return 'Any Error';
              switch (t) {
                case TriggerType.hfrDegraded:
                  return 'HFR Degraded';
                case TriggerType.meridianFlip:
                  return 'Meridian Flip Needed';
                case TriggerType.guidingFailed:
                  return 'Guiding Failed';
                case TriggerType.altitudeLimit:
                  return 'Altitude Limit';
                case TriggerType.weatherUnsafe:
                  return 'Weather Unsafe';
                case TriggerType.temperatureShift:
                  return 'Temperature Shift';
                case TriggerType.filterChange:
                  return 'Filter Change';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(triggerType: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Recovery Action',
          child: _Dropdown<RecoveryActionType>(
            colors: colors,
            value: node.recoveryAction,
            items: RecoveryActionType.values,
            labelBuilder: (a) {
              switch (a) {
                case RecoveryActionType.continueExecution:
                  return 'Continue';
                case RecoveryActionType.pause:
                  return 'Pause Sequence';
                case RecoveryActionType.autofocus:
                  return 'Run Autofocus';
                case RecoveryActionType.nextTarget:
                  return 'Skip to Next Target';
                case RecoveryActionType.retry:
                  return 'Retry Operation';
                case RecoveryActionType.parkAndAbort:
                  return 'Park & Abort';
                case RecoveryActionType.customBranch:
                  return 'Custom Branch';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(recoveryAction: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Retries',
          child: _NumberInput(
            colors: colors,
            value: node.maxRetries.toDouble(),
            min: 1,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxRetries: value.toInt()),
                  );
            },
          ),
        ),
        if (node.triggerType == TriggerType.hfrDegraded)
          _PropertyField(
            colors: colors,
            label: 'HFR Threshold',
            child: _NumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 4.0,
              suffix: 'px',
              min: 1,
              max: 20,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(triggerThreshold: value),
                    );
              },
            ),
          ),
        if (node.triggerType == TriggerType.altitudeLimit)
          _PropertyField(
            colors: colors,
            label: 'Min Altitude',
            child: _NumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 30,
              suffix: '°',
              min: 0,
              max: 90,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(triggerThreshold: value),
                    );
              },
            ),
          ),
      ],
    );
  }
}

class _NotificationProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final NotificationNode node;

  const _NotificationProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Title',
          child: _TextInput(
            colors: colors,
            value: node.title,
            hint: 'Notification title',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(title: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Message',
          child: _TextInput(
            colors: colors,
            value: node.message,
            hint: 'Notification message',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(message: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Level',
          child: _Dropdown<NotificationLevel>(
            colors: colors,
            value: node.level,
            items: NotificationLevel.values,
            labelBuilder: (l) {
              switch (l) {
                case NotificationLevel.info:
                  return 'Info';
                case NotificationLevel.warning:
                  return 'Warning';
                case NotificationLevel.error:
                  return 'Error';
                case NotificationLevel.success:
                  return 'Success';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(level: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _ScriptProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ScriptNode node;

  const _ScriptProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Script Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Script Path',
          child: _TextInput(
            colors: colors,
            value: node.scriptPath,
            hint: 'Path to script file',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(scriptPath: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Arguments',
          child: _TextInput(
            colors: colors,
            value: node.arguments.join(' '),
            hint: 'Space-separated arguments',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(
                        arguments: value
                            .split(' ')
                            .where((s) => s.isNotEmpty)
                            .toList()),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Timeout',
          child: _NumberInput(
            colors: colors,
            value: (node.timeoutSecs ?? 300).toDouble(),
            suffix: 's',
            min: 1,
            max: 3600,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.toInt()),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scripts run with sequence context variables available as environment variables',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.warning,
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

class _SimpleInstructionInfo extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _SimpleInstructionInfo({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final String description;
    final IconData icon;

    if (node is ParkNode) {
      description =
          'Parks the mount at its home position. The mount will not track after parking.';
      icon = LucideIcons.parkingCircle;
    } else if (node is UnparkNode) {
      description =
          'Unparks the mount and enables tracking. Required before slewing or imaging.';
      icon = LucideIcons.unlock;
    } else {
      description = 'This instruction has no additional settings.';
      icon = LucideIcons.settings;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeridianFlipProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final MeridianFlipNode node;

  const _MeridianFlipProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meridian Flip Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Minutes Past Meridian',
          child: _NumberInput(
            colors: colors,
            value: node.minutesPastMeridian,
            suffix: 'min',
            min: 0,
            max: 60,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(minutesPastMeridian: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Pause Guiding',
          child: _ToggleSwitch(
            colors: colors,
            value: node.pauseGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(pauseGuiding: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Auto Center After Flip',
          child: _ToggleSwitch(
            colors: colors,
            value: node.autoCenter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(autoCenter: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Time',
          child: _NumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 0,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTime: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Performs pier flip when target crosses meridian. Pauses guiding, flips, then optionally re-centers.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.info,
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

class _DomeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _DomeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title;
    final String description;
    final IconData icon;
    final bool shutterOnly;

    if (node is OpenDomeNode) {
      title = 'Open Dome Settings';
      description =
          'Opens the dome shutter to allow imaging. If not using shutter-only mode, will also rotate dome to tracking position.';
      icon = LucideIcons.doorOpen;
      shutterOnly = (node as OpenDomeNode).shutterOnly;
    } else if (node is CloseDomeNode) {
      title = 'Close Dome Settings';
      description =
          'Closes the dome shutter to protect equipment. Typically used at end of session or when weather becomes unsafe.';
      icon = LucideIcons.doorClosed;
      shutterOnly = (node as CloseDomeNode).shutterOnly;
    } else {
      title = 'Park Dome Settings';
      description =
          'Parks the dome at its home position. The dome will stop tracking the telescope.';
      icon = LucideIcons.parkingCircle;
      shutterOnly = (node as ParkDomeNode).shutterOnly;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Shutter Only',
          child: _ToggleSwitch(
            colors: colors,
            value: shutterOnly,
            onChanged: (value) {
              if (node is OpenDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as OpenDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is CloseDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as CloseDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is ParkDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as ParkDomeNode).copyWith(shutterOnly: value),
                    );
              }
            },
          ),
        ),
        Text(
          shutterOnly
              ? 'Only operates the shutter, dome will not rotate'
              : 'Will operate both shutter and dome rotation',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PolarAlignmentProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final PolarAlignmentNode node;

  const _PolarAlignmentProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polar Alignment Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Hemisphere',
          child: _Dropdown<bool>(
            colors: colors,
            value: node.isNorth,
            items: const [true, false],
            labelBuilder: (v) => v ? 'Northern' : 'Southern',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(isNorth: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Exposure Duration',
                child: _NumberInput(
                  colors: colors,
                  value: node.exposureDuration,
                  suffix: 's',
                  min: 0.5,
                  max: 30,
                  decimals: 1,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(exposureDuration: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Binning',
                child: _NumberInput(
                  colors: colors,
                  value: node.binning.toDouble(),
                  min: 1,
                  max: 4,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(binning: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        _PropertyField(
          colors: colors,
          label: 'Start Altitude',
          child: _NumberInput(
            colors: colors,
            value: node.startAltitude,
            suffix: '°',
            min: 20,
            max: 80,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startAltitude: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Rotation Step',
          child: _NumberInput(
            colors: colors,
            value: node.rotationStep,
            suffix: '°',
            min: 10,
            max: 45,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(rotationStep: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Gain',
                child: _NumberInput(
                  colors: colors,
                  value: (node.gain ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(gain: value.toInt()),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Offset',
                child: _NumberInput(
                  colors: colors,
                  value: (node.offset ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(offset: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        _PropertyField(
          colors: colors,
          label: 'Start From Current Position',
          child: _ToggleSwitch(
            colors: colors,
            value: node.startFromCurrent,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startFromCurrent: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Manual Slew Mode',
          child: _ToggleSwitch(
            colors: colors,
            value: node.manualSlew,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(manualSlew: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.compass, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Three-point polar alignment using plate solving. Calculates polar error and guides adjustments.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.info,
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

class _InstructionSetInfo extends StatelessWidget {
  final NightshadeColors colors;
  final InstructionSetNode node;

  const _InstructionSetInfo({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.listTree, size: 32, color: colors.accent),
          const SizedBox(height: 12),
          Text(
            'Container for sequential instructions. All children execute in order from top to bottom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${node.childIds.length} children',
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TIMING SECTION
// ============================================================================

/// Formats a Duration into a human-readable string like "5m 30s", "1h 20m", etc.
String _formatDurationNice(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s';
  }
  if (duration.inMinutes < 60) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (secs == 0) {
      return '${mins}m';
    }
    return '${mins}m ${secs}s';
  }
  final hours = duration.inHours;
  final mins = duration.inMinutes % 60;
  if (mins == 0) {
    return '${hours}h';
  }
  return '${hours}h ${mins}m';
}

/// Checks if a node type has a meaningful duration that should be displayed.
bool _hasMeaningfulDuration(SequenceNode node) {
  return node is ExposureNode ||
      node is AutofocusNode ||
      node is DelayNode ||
      node is WaitTimeNode ||
      node is SlewNode ||
      node is CenterNode ||
      node is MeridianFlipNode ||
      node is DitherNode ||
      node is FilterChangeNode ||
      node is RotatorNode ||
      node is ParkNode ||
      node is UnparkNode ||
      node is CoolCameraNode ||
      node is WarmCameraNode ||
      node is StartGuidingNode ||
      node is StopGuidingNode ||
      node is OpenDomeNode ||
      node is CloseDomeNode ||
      node is ParkDomeNode ||
      node is PolarAlignmentNode ||
      node is ScriptNode;
}

/// Widget that displays timing information for a sequence node.
class _TimingSection extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _TimingSection({
    required this.colors,
    required this.node,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    if (sequence == null) return const SizedBox.shrink();

    // Calculate timing for this node
    final estimator = SequenceTimeEstimator();
    final timings = estimator.estimateSequenceTiming(sequence, DateTime.now());
    final nodeTiming = timings.where((t) => t.nodeId == node.id).firstOrNull;

    // Calculate total sequence duration for percentage
    final totalDuration =
        estimator.estimateTotalDuration(sequence, DateTime.now());

    // Get node-specific duration details
    final durationDetails = _getDurationDetails();

    // If we have no timing info and no details, don't show the section
    if (nodeTiming == null && durationDetails == null) {
      return const SizedBox.shrink();
    }

    final duration = nodeTiming?.duration ?? Duration.zero;
    final percentage = totalDuration.inSeconds > 0
        ? (duration.inSeconds / totalDuration.inSeconds * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with divider line
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: colors.border,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Timing',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: colors.border,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Node-specific duration details (if any)
        if (durationDetails != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final detail in durationDetails)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          detail.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        Text(
                          detail.value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Summary timing info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 14, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Duration:',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDurationNice(duration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              if (totalDuration.inSeconds > 0 && percentage > 0.1) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(LucideIcons.pieChart,
                        size: 14, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      'Contributes:',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${percentage.toStringAsFixed(1)}% of total',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  /// Returns node-specific duration breakdown details, or null if not applicable.
  List<_DurationDetail>? _getDurationDetails() {
    if (node is ExposureNode) {
      final exposure = node as ExposureNode;
      final exposureTotal = exposure.durationSecs * exposure.count;
      // Estimate download overhead at ~2 seconds per frame
      final downloadOverhead = exposure.count * 2.0;
      final total = exposureTotal + downloadOverhead;

      return [
        _DurationDetail(
          label: 'Exposures',
          value:
              '${exposure.count} x ${exposure.durationSecs.toStringAsFixed(exposure.durationSecs == exposure.durationSecs.truncate() ? 0 : 1)}s',
        ),
        _DurationDetail(
          label: 'Download overhead',
          value: '~${downloadOverhead.toStringAsFixed(0)}s',
        ),
        _DurationDetail(
          label: 'Total',
          value: _formatDurationNice(Duration(seconds: total.round())),
        ),
      ];
    }

    if (node is AutofocusNode) {
      final autofocus = node as AutofocusNode;
      // Calculate: (stepsOut * 2 + 1) data points, each with exposuresPerPoint exposures
      final dataPoints = autofocus.stepsOut * 2 + 1;
      final totalExposures = dataPoints * autofocus.exposuresPerPoint;
      final totalSecs = totalExposures * autofocus.exposureDuration;

      return [
        _DurationDetail(
          label: 'Data points',
          value: '$dataPoints',
        ),
        _DurationDetail(
          label: 'Exposures/point',
          value:
              '${autofocus.exposuresPerPoint} x ${autofocus.exposureDuration}s',
        ),
        _DurationDetail(
          label: 'Est. duration',
          value: _formatDurationNice(Duration(seconds: totalSecs.round())),
        ),
      ];
    }

    if (node is DelayNode) {
      final delay = node as DelayNode;
      return [
        _DurationDetail(
          label: 'Delay',
          value: _formatDurationNice(
              Duration(milliseconds: (delay.seconds * 1000).round())),
        ),
      ];
    }

    if (node is WaitTimeNode) {
      final wait = node as WaitTimeNode;
      if (wait.waitUntil != null) {
        return [
          _DurationDetail(
            label: 'Wait until',
            value:
                '${wait.waitUntil!.hour.toString().padLeft(2, '0')}:${wait.waitUntil!.minute.toString().padLeft(2, '0')}',
          ),
        ];
      } else if (wait.waitForTwilight != null) {
        final twilightName = switch (wait.waitForTwilight!) {
          TwilightType.civil => 'Civil twilight',
          TwilightType.nautical => 'Nautical twilight',
          TwilightType.astronomical => 'Astronomical twilight',
        };
        return [
          _DurationDetail(
            label: 'Wait for',
            value: twilightName,
          ),
        ];
      }
    }

    if (node is SlewNode) {
      return const [
        _DurationDetail(
          label: 'Est. slew time',
          value: '~30s',
        ),
      ];
    }

    if (node is CenterNode) {
      final center = node as CenterNode;
      return [
        const _DurationDetail(
          label: 'Est. centering time',
          value: '~30s',
        ),
        _DurationDetail(
          label: 'Max attempts',
          value: '${center.maxAttempts}',
        ),
      ];
    }

    if (node is MeridianFlipNode) {
      final flip = node as MeridianFlipNode;
      var totalSecs = 120.0; // Base flip time
      if (flip.autoCenter) {
        totalSecs += 30; // Add centering time
      }
      totalSecs += flip.settleTime;

      return [
        const _DurationDetail(
          label: 'Flip duration',
          value: '~2m',
        ),
        if (flip.autoCenter)
          const _DurationDetail(
            label: 'Auto-center',
            value: '~30s',
          ),
        _DurationDetail(
          label: 'Settle time',
          value: '${flip.settleTime.toStringAsFixed(0)}s',
        ),
        _DurationDetail(
          label: 'Est. total',
          value: _formatDurationNice(Duration(seconds: totalSecs.round())),
        ),
      ];
    }

    if (node is CoolCameraNode) {
      final cool = node as CoolCameraNode;
      return [
        _DurationDetail(
          label: 'Max cooling time',
          value: '${(cool.durationMins ?? 10).toStringAsFixed(0)}m',
        ),
      ];
    }

    if (node is WarmCameraNode) {
      final warm = node as WarmCameraNode;
      // Estimate: 30C delta at given rate
      final mins = 30.0 / warm.ratePerMin;
      return [
        _DurationDetail(
          label: 'Warming rate',
          value: '${warm.ratePerMin}C/min',
        ),
        _DurationDetail(
          label: 'Est. duration',
          value: '~${mins.round()}m',
        ),
      ];
    }

    if (node is DitherNode) {
      final dither = node as DitherNode;
      return [
        _DurationDetail(
          label: 'Settle time',
          value: '${dither.settleTime.toStringAsFixed(0)}s',
        ),
      ];
    }

    if (node is FilterChangeNode) {
      return const [
        _DurationDetail(
          label: 'Est. change time',
          value: '~10s',
        ),
      ];
    }

    if (node is RotatorNode) {
      return const [
        _DurationDetail(
          label: 'Est. rotation time',
          value: '~15s',
        ),
      ];
    }

    if (node is ParkNode || node is UnparkNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~30s',
        ),
      ];
    }

    if (node is StartGuidingNode) {
      final guiding = node as StartGuidingNode;
      return [
        _DurationDetail(
          label: 'Settle timeout',
          value: '${guiding.settleTimeout.toStringAsFixed(0)}s',
        ),
      ];
    }

    if (node is StopGuidingNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~2s',
        ),
      ];
    }

    if (node is OpenDomeNode || node is CloseDomeNode || node is ParkDomeNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~1m',
        ),
      ];
    }

    if (node is PolarAlignmentNode) {
      return const [
        _DurationDetail(
          label: 'Est. time',
          value: '~5m',
        ),
        _DurationDetail(
          label: 'Note',
          value: '3 plate solves + adjustment',
        ),
      ];
    }

    if (node is ScriptNode) {
      final script = node as ScriptNode;
      return [
        _DurationDetail(
          label: 'Timeout',
          value: '${script.timeoutSecs ?? 30}s',
        ),
      ];
    }

    return null;
  }
}

/// Helper class for duration detail display.
class _DurationDetail {
  final String label;
  final String value;

  const _DurationDetail({
    required this.label,
    required this.value,
  });
}
