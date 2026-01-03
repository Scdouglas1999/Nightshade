import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/nightshade_colors.dart';

/// A parameter value in the PHD2 Brain
class BrainParam {
  final String name;
  final double value;
  final double? min;
  final double? max;
  final String? description;

  const BrainParam({
    required this.name,
    required this.value,
    this.min,
    this.max,
    this.description,
  });

  BrainParam copyWith({double? value}) {
    return BrainParam(
      name: name,
      value: value ?? this.value,
      min: min,
      max: max,
      description: description,
    );
  }
}

/// Panel for viewing and editing PHD2 Brain guide algorithm parameters
class BrainSettingsPanel extends StatefulWidget {
  /// RA axis parameters
  final List<BrainParam> raParams;

  /// Dec axis parameters
  final List<BrainParam> decParams;

  /// Whether the panel is in edit mode
  final bool isEditing;

  /// Callback when a parameter value is changed
  final void Function(String axis, String name, double value)? onParamChanged;

  /// Callback when Apply is pressed
  final VoidCallback? onApply;

  /// Callback when Reset is pressed
  final VoidCallback? onReset;

  /// Whether changes are being applied
  final bool isApplying;

  const BrainSettingsPanel({
    super.key,
    required this.raParams,
    required this.decParams,
    this.isEditing = false,
    this.onParamChanged,
    this.onApply,
    this.onReset,
    this.isApplying = false,
  });

  @override
  State<BrainSettingsPanel> createState() => _BrainSettingsPanelState();
}

class _BrainSettingsPanelState extends State<BrainSettingsPanel> {
  final Map<String, TextEditingController> _controllers = {};
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    for (final param in widget.raParams) {
      _controllers['ra_${param.name}'] = TextEditingController(
        text: param.value.toStringAsFixed(2),
      );
    }
    for (final param in widget.decParams) {
      _controllers['dec_${param.name}'] = TextEditingController(
        text: param.value.toStringAsFixed(2),
      );
    }
  }

  @override
  void didUpdateWidget(BrainSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers if params changed externally
    if (!_hasChanges) {
      for (final param in widget.raParams) {
        _controllers['ra_${param.name}']?.text = param.value.toStringAsFixed(2);
      }
      for (final param in widget.decParams) {
        _controllers['dec_${param.name}']?.text = param.value.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(colors),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAxisSection('RA', widget.raParams, 'ra', colors),
                  const SizedBox(height: 20),
                  _buildAxisSection('Dec', widget.decParams, 'dec', colors),
                ],
              ),
            ),
          ),
          // Actions
          if (_hasChanges) _buildActions(colors),
        ],
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(LucideIcons.brain, color: colors.warning, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            'PHD2 Brain',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (widget.isApplying)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAxisSection(String label, List<BrainParam> params, String axis, NightshadeColors colors) {
    final axisColor = axis == 'ra' ? Colors.redAccent : colors.info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: axisColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$label Axis',
              style: TextStyle(
                color: axisColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceAlt.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: params.map((param) => _buildParamRow(param, axis, colors)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildParamRow(BrainParam param, String axis, NightshadeColors colors) {
    final controller = _controllers['${axis}_${param.name}']!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Tooltip(
              message: param.description ?? param.name,
              child: Text(
                _formatParamName(param.name),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: controller,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                  fillColor: colors.surface,
                  filled: true,
                ),
                onChanged: (value) {
                  setState(() => _hasChanges = true);
                  final doubleValue = double.tryParse(value);
                  if (doubleValue != null) {
                    widget.onParamChanged?.call(axis, param.name, doubleValue);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildActionButton(
            label: 'Reset',
            icon: LucideIcons.rotateCcw,
            color: colors.textSecondary,
            colors: colors,
            isOutline: true,
            onPressed: widget.isApplying ? null : () {
              setState(() => _hasChanges = false);
              widget.onReset?.call();
            },
          ),
          const SizedBox(width: 10),
          _buildActionButton(
            label: 'Apply',
            icon: LucideIcons.check,
            color: colors.primary,
            colors: colors,
            isPrimary: true,
            onPressed: widget.isApplying ? null : () {
              setState(() => _hasChanges = false);
              widget.onApply?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required NightshadeColors colors,
    VoidCallback? onPressed,
    bool isOutline = false,
    bool isPrimary = false,
  }) {
    final isDisabled = onPressed == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isPrimary
                ? (isDisabled ? colors.surfaceHover : color)
                : (isOutline ? Colors.transparent : colors.surfaceHover),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOutline ? colors.border : (isPrimary ? color : Colors.transparent),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isPrimary
                    ? (isDisabled ? colors.textMuted : Colors.white)
                    : (isDisabled ? colors.textMuted : color),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPrimary
                      ? (isDisabled ? colors.textMuted : Colors.white)
                      : (isDisabled ? colors.textMuted : color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatParamName(String name) {
    // Convert camelCase or PascalCase to readable format
    return name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
  }
}
