import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/help/field_help_copy.dart';
import '../../../widgets/help/field_help_label.dart';
import '../../../widgets/pill_tab.dart';

part 'panel_widgets/quick_stat.dart';

/// Builds an imaging-panel row label, optionally appending a [helpAffordance]
/// when [helpId] is supplied.
///
/// Each of [InputRow], [InputRowEditable], [DropdownRow], and
/// [SliderRowInteractive] renders its label through this helper so the help
/// icon hugs the label text inside the row's label `Expanded`, leaving the
/// existing label/control flex layout untouched. When [helpId] is null the
/// result is identical to the bare label `Text` that shipped before, so no
/// existing call site changes behaviour.
Widget _panelRowLabel(
  BuildContext context, {
  required String label,
  required TextStyle style,
  required FieldHelpId? helpId,
}) {
  final text = Text(label, style: style);
  if (helpId == null) {
    return text;
  }
  final copy = helpFor(helpId);
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Flexible(child: text),
      const SizedBox(width: NightshadeTokens.spaceXs),
      helpAffordance(
        context,
        title: copy.title,
        body: copy.body,
        position: NightshadeTooltipPosition.top,
      ),
    ],
  );
}

class PanelTabs extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NightshadeColors colors;

  const PanelTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.colors,
  });

  static const _tabs = [
    (LucideIcons.camera, 'Capture'),
    (LucideIcons.aperture, 'Camera'),
    (LucideIcons.focus, 'Focus'),
    (LucideIcons.crosshair, 'Guiding'),
    (LucideIcons.compass, 'Mount'),
    (LucideIcons.rotateCw, 'Rotator'),
    (LucideIcons.layers, 'Stack'),
    (LucideIcons.sparkle, 'Annotations'),
  ];

  /// Index of the Annotations tab
  static const int annotationsTabIndex = 7;

  /// Number of columns in the tab grid.
  static const int _columns = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotation = ref.watch(currentAnnotationProvider);
    final objectCount = annotation?.objects.length ?? 0;

    final rowCount = (_tabs.length + _columns - 1) ~/ _columns;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < rowCount; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            _buildRow(row, objectCount),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(int row, int objectCount) {
    final startIndex = row * _columns;
    return Row(
      children: List.generate(_columns, (col) {
        final tabIndex = startIndex + col;

        if (tabIndex >= _tabs.length) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: col == 0 ? 0 : 6),
              child: const SizedBox.shrink(),
            ),
          );
        }

        final (icon, label) = _tabs[tabIndex];
        final isSelected = tabIndex == selectedIndex;
        final displayLabel = tabIndex == annotationsTabIndex && objectCount > 0
            ? '$label ($objectCount)'
            : label;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: col == 0 ? 0 : 6),
            child: _PanelTab(
              icon: icon,
              label: displayLabel,
              isSelected: isSelected,
              onTap: () => onSelected(tabIndex),
              colors: colors,
            ),
          ),
        );
      }),
    );
  }
}

/// Thin wrapper around the shared [PillTab]. The imaging panel keeps its own
/// type name for grid layout in [PanelTabs]; the pill styling itself is shared.
class _PanelTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _PanelTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return PillTab(
      icon: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
      colors: colors,
    );
  }
}

class ControlSection extends StatelessWidget {
  final String title;
  final Widget child;
  final NightshadeColors colors;

  const ControlSection({
    super.key,
    required this.title,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        child,
      ],
    );
  }
}

class BigActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isEnabled;
  final bool isLoading;
  final bool isMobile;

  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.isEnabled = true,
    this.isLoading = false,
    this.isMobile = false,
  });

  @override
  State<BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<BigActionButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final effectiveColor =
        widget.isEnabled ? widget.color : widget.color.withValues(alpha: 0.4);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:
            widget.isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp:
            widget.isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            widget.isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: () {
            final scale = _isPressed && widget.isEnabled ? 0.95 : 1.0;
            return Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0);
          }(),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isMobile ? 12 : 20,
            vertical: widget.isMobile ? 12 : 16,
          ),
          decoration: NightshadeDecorations.filledButton(
            effectiveColor,
            isHovered: _isHovered && widget.isEnabled,
            isDisabled: !widget.isEnabled,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.isLoading
                  ? AnimatedBuilder(
                      animation: _loadingController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _loadingController.value * 2 * math.pi,
                          child: Icon(
                            LucideIcons.loader2,
                            size: 24,
                            color: primaryForeground.withValues(
                                alpha: widget.isEnabled ? 1.0 : 0.5),
                          ),
                        );
                      },
                    )
                  : Icon(
                      widget.icon,
                      size: widget.isMobile ? 20 : 24,
                      color: primaryForeground.withValues(
                          alpha: widget.isEnabled ? 1.0 : 0.5),
                    ),
              SizedBox(height: widget.isMobile ? 4 : 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: primaryForeground.withValues(
                        alpha: widget.isEnabled ? 1.0 : 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditableCompactInput extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;
  final bool isMobile;

  const EditableCompactInput({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
    this.isMobile = false,
  });

  @override
  State<EditableCompactInput> createState() => _EditableCompactInputState();
}

class _EditableCompactInputState extends State<EditableCompactInput> {
  late TextEditingController _controller;
  bool _isEditing = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _commitValue();
      }
    });
  }

  @override
  void didUpdateWidget(EditableCompactInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitValue() {
    setState(() => _isEditing = false);
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: NightshadeTokens.fontSizePanelCaption,
            color: widget.colors.textMuted,
          ),
        ),
        SizedBox(height: widget.isMobile ? 3 : 4),
        GestureDetector(
          onTap: () {
            setState(() => _isEditing = true);
            _focusNode.requestFocus();
            _controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controller.text.length,
            );
          },
          child: Container(
            width: widget.isMobile ? 70 : 90,
            constraints: BoxConstraints(
              minHeight: widget.isMobile ? 32 : 34,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isMobile ? 8 : 10,
              vertical: widget.isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    _isEditing ? widget.colors.primary : widget.colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _isEditing
                      ? TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: TextStyle(
                            fontSize: widget.isMobile ? 12 : 13,
                            fontWeight: FontWeight.w500,
                            color: widget.colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _commitValue(),
                        )
                      : Text(
                          widget.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                ),
                if (widget.suffix != null)
                  Text(
                    widget.suffix!,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colors.textMuted,
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

class PanelSection extends StatelessWidget {
  final String title;
  final Widget child;
  final NightshadeColors colors;

  /// A titled section with a bordered container for grouped imaging controls.
  ///
  /// For settings-style rows with a label and trailing control, compose
  /// [DropdownRow], [InputRow], or [InputRowEditable] inside this section.
  /// Those row widgets follow the same label/control flex layout as
  /// [SettingRow] in `../../settings/widgets/settings_widgets.dart`, adapted
  /// for the denser imaging side panel.
  const PanelSection({
    super.key,
    required this.title,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: NightshadeTokens.fontSizePanelLabel,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Container(
          padding: const EdgeInsets.all(NightshadeTokens.panelSectionPadding),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusButton,
            border: Border.all(color: colors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class InputRow extends StatelessWidget {
  final String label;
  final String? value;
  final NightshadeColors colors;
  final Widget? trailing;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const InputRow({
    super.key,
    required this.label,
    this.value,
    required this.colors,
    this.trailing,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: TextStyle(
              fontSize: NightshadeTokens.fontSizePanelLabel,
              color: colors.textSecondary,
            ),
            helpId: helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: NightshadeTokens.borderRadiusSm,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InputRowEditable extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const InputRowEditable({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: TextStyle(
              fontSize: NightshadeTokens.fontSizePanelLabel,
              color: colors.textSecondary,
            ),
            helpId: helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: NightshadeTokens.borderRadiusSm,
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: TextEditingController(text: value),
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
              onSubmitted: onChanged,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class DropdownRow extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final NightshadeColors colors;
  final ValueChanged<String?>? onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  /// Label + dropdown row for the imaging side panel.
  ///
  /// Layout mirrors [SettingRow] in `../../settings/widgets/settings_widgets.dart`:
  /// label on the left, control on the right. Uses [NightshadeDropdown] for the
  /// control styling.
  const DropdownRow({
    super.key,
    required this.label,
    this.value,
    required this.items,
    required this.colors,
    this.onChanged,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: TextStyle(
              fontSize: NightshadeTokens.fontSizePanelLabel,
              color: isEnabled ? colors.textSecondary : colors.textMuted,
            ),
            helpId: helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: NightshadeDropdown(
            value: items.contains(value) ? value : null,
            items: items,
            isExpanded: true,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class SliderRowInteractive extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final NightshadeColors colors;
  final ValueChanged<double>? onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const SliderRowInteractive({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.colors,
    this.onChanged,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: TextStyle(
              fontSize: 11,
              color: isEnabled ? colors.textSecondary : colors.textMuted,
            ),
            helpId: helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: isEnabled ? colors.primary : colors.textMuted,
              inactiveTrackColor: colors.border,
              thumbColor: isEnabled ? colors.primary : colors.textMuted,
              overlayColor: colors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${value.toStringAsFixed(1)}$suffix',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isEnabled ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class SmallButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isOutline;
  final bool isEnabled;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const SmallButton({
    super.key,
    required this.label,
    required this.icon,
    this.isOutline = false,
    this.isEnabled = true,
    required this.colors,
    this.onTap,
  });

  @override
  State<SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<SmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final isEnabled = widget.isEnabled;
    final primaryColor =
        isEnabled ? widget.colors.primary : widget.colors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: widget.isOutline
              ? BoxDecoration(
                  color: _isHovered && isEnabled
                      ? primaryColor.withValues(
                          alpha: NightshadeTokens.opacitySubtle,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primaryColor),
                )
              : NightshadeDecorations.filledButton(
                  primaryColor,
                  isHovered: _isHovered && isEnabled,
                  isDisabled: !isEnabled,
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isOutline
                    ? primaryColor
                    : isEnabled
                        ? primaryForeground
                        : widget.colors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isOutline
                        ? primaryColor
                        : isEnabled
                            ? primaryForeground
                            : widget.colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickStatsPanel extends ConsumerWidget {
  final NightshadeColors colors;

  const QuickStatsPanel({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);

    // Format temperature
    String tempValue = '---';
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      if (cameraState.temperature != null) {
        tempValue = '${cameraState.temperature!.toStringAsFixed(1)}°C';
      } else {
        tempValue = 'N/A';
      }
    }

    // Format RMS
    String rmsValue = '---';
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.isGuiding &&
        guiderState.rmsTotal != null) {
      rmsValue = '${guiderState.rmsTotal!.toStringAsFixed(2)}"';
    }

    // Format HFR
    String hfrValue = '---';
    if (lastStats?.hfr != null) {
      hfrValue = lastStats!.hfr!.toStringAsFixed(2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _QuickStat(
            icon: LucideIcons.thermometer,
            label: 'Sensor',
            value: tempValue,
            colors: colors,
          ),
          const SizedBox(width: 24),
          _QuickStat(
            icon: LucideIcons.activity,
            label: 'RMS',
            value: rmsValue,
            colors: colors,
          ),
          const SizedBox(width: 24),
          _QuickStat(
            icon: LucideIcons.target,
            label: 'HFR',
            value: hfrValue,
            colors: colors,
          ),
        ],
      ),
    );
  }
}
