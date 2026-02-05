import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Provides descriptions for each stretch method, used in tooltips.
const Map<AutoStretchMethod, String> _methodDescriptions = {
  AutoStretchMethod.stf:
      'Screen Transfer Function - adaptive stretch preserving detail',
  AutoStretchMethod.histogram:
      'Histogram equalization for even distribution',
  AutoStretchMethod.asinh:
      'Arcsinh stretch - good for high dynamic range',
  AutoStretchMethod.log:
      'Logarithmic stretch - reveals faint detail',
  AutoStretchMethod.gamma:
      'Simple gamma correction',
};

/// Display names for each stretch method.
const Map<AutoStretchMethod, String> _methodNames = {
  AutoStretchMethod.stf: 'STF',
  AutoStretchMethod.histogram: 'Histogram',
  AutoStretchMethod.asinh: 'Asinh',
  AutoStretchMethod.log: 'Log',
  AutoStretchMethod.gamma: 'Gamma',
};

/// Auto-stretch controls for the imaging screen.
///
/// Can display in compact mode (for toolbar) or expanded mode (for panel/dialog).
/// Compact mode shows a toggle, method dropdown, and settings button.
/// Expanded mode shows all parameters including sliders for fine-tuning.
class StretchControls extends ConsumerWidget {
  /// When true, shows minimal toolbar-friendly controls.
  /// When false, shows full expanded controls with all sliders.
  final bool compact;

  const StretchControls({
    super.key,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settings = ref.watch(autoStretchSettingsProvider);

    if (compact) {
      return _CompactStretchControls(
        settings: settings,
        colors: colors,
        onSettingsChanged: (newSettings) {
          ref.read(autoStretchSettingsProvider.notifier).update(newSettings);
        },
      );
    }

    return _ExpandedStretchControls(
      settings: settings,
      colors: colors,
      onSettingsChanged: (newSettings) {
        ref.read(autoStretchSettingsProvider.notifier).update(newSettings);
      },
    );
  }
}

/// Compact controls for toolbar display.
class _CompactStretchControls extends StatelessWidget {
  final AutoStretchSettings settings;
  final NightshadeColors colors;
  final ValueChanged<AutoStretchSettings> onSettingsChanged;

  const _CompactStretchControls({
    required this.settings,
    required this.colors,
    required this.onSettingsChanged,
  });

  void _showAdvancedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _StretchSettingsDialog(
        settings: settings,
        colors: colors,
        onSettingsChanged: onSettingsChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle switch with label
        NightshadeTooltip(
          message: 'Enable auto-stretch to enhance faint details in linear data',
          position: NightshadeTooltipPosition.bottom,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stretch',
                style: TextStyle(
                  fontSize: 12,
                  color: settings.enabled
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              NightshadeSwitch(
                value: settings.enabled,
                onChanged: (value) {
                  onSettingsChanged(settings.copyWith(enabled: value));
                },
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Method dropdown
        if (settings.enabled) ...[
          NightshadeTooltip(
            message: _methodDescriptions[settings.method] ?? '',
            position: NightshadeTooltipPosition.bottom,
            child: _MethodDropdown(
              value: settings.method,
              colors: colors,
              onChanged: (method) {
                if (method != null) {
                  onSettingsChanged(settings.copyWith(method: method));
                }
              },
            ),
          ),

          const SizedBox(width: 8),

          // Settings button
          NightshadeTooltip(
            message: 'Advanced stretch settings',
            position: NightshadeTooltipPosition.bottom,
            child: _CompactIconButton(
              icon: LucideIcons.settings2,
              colors: colors,
              onPressed: () => _showAdvancedDialog(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Full expanded controls for panel or dialog.
class _ExpandedStretchControls extends StatelessWidget {
  final AutoStretchSettings settings;
  final NightshadeColors colors;
  final ValueChanged<AutoStretchSettings> onSettingsChanged;

  const _ExpandedStretchControls({
    required this.settings,
    required this.colors,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Enable toggle and method selection
        Row(
          children: [
            Text(
              'Auto-Stretch',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            NightshadeSwitch(
              value: settings.enabled,
              onChanged: (value) {
                onSettingsChanged(settings.copyWith(enabled: value));
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Method selection
        _SettingRow(
          label: 'Method',
          tooltip: 'Select the stretch algorithm to use',
          colors: colors,
          child: _MethodDropdown(
            value: settings.method,
            colors: colors,
            isExpanded: true,
            onChanged: settings.enabled
                ? (method) {
                    if (method != null) {
                      onSettingsChanged(settings.copyWith(method: method));
                    }
                  }
                : null,
          ),
        ),

        const SizedBox(height: 12),

        // Shadow clip slider
        _SliderSetting(
          label: 'Shadow Clip',
          tooltip:
              'Controls shadow clipping in standard deviations from median. '
              'Lower values clip more shadows.',
          value: settings.shadowClip,
          min: -5.0,
          max: 0.0,
          divisions: 50,
          enabled: settings.enabled,
          colors: colors,
          formatValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            onSettingsChanged(settings.copyWith(shadowClip: value));
          },
        ),

        const SizedBox(height: 12),

        // Highlight clip slider
        _SliderSetting(
          label: 'Highlight Clip',
          tooltip:
              'Controls highlight clipping in standard deviations from median. '
              'Lower values clip more highlights.',
          value: settings.highlightClip,
          min: -3.0,
          max: 0.0,
          divisions: 30,
          enabled: settings.enabled,
          colors: colors,
          formatValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            onSettingsChanged(settings.copyWith(highlightClip: value));
          },
        ),

        const SizedBox(height: 12),

        // Target median slider
        _SliderSetting(
          label: 'Target Median',
          tooltip:
              'Target brightness level for the stretched image midtones. '
              'Higher values produce brighter images.',
          value: settings.targetMedian,
          min: 0.1,
          max: 0.5,
          divisions: 40,
          enabled: settings.enabled,
          colors: colors,
          formatValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            onSettingsChanged(settings.copyWith(targetMedian: value));
          },
        ),

        const SizedBox(height: 12),

        // Linked channels toggle
        _SettingRow(
          label: 'Linked Channels',
          tooltip:
              'When enabled, uses the same stretch for all RGB channels to preserve color balance. '
              'Disable for independent channel stretching.',
          colors: colors,
          child: NightshadeSwitch(
            value: settings.linkedChannels,
            enabled: settings.enabled,
            onChanged: settings.enabled
                ? (value) {
                    onSettingsChanged(settings.copyWith(linkedChannels: value));
                  }
                : null,
          ),
        ),

        // Gamma value slider (only shown for gamma method)
        if (settings.method == AutoStretchMethod.gamma) ...[
          const SizedBox(height: 12),
          _SliderSetting(
            label: 'Gamma Value',
            tooltip:
                'Gamma correction factor. Standard display gamma is 2.2. '
                'Lower values brighten the image, higher values darken it.',
            value: settings.gammaValue,
            min: 1.0,
            max: 4.0,
            divisions: 30,
            enabled: settings.enabled,
            colors: colors,
            formatValue: (v) => v.toStringAsFixed(1),
            onChanged: (value) {
              onSettingsChanged(settings.copyWith(gammaValue: value));
            },
          ),
        ],

        const SizedBox(height: 16),

        // Reset to defaults button
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _TextButton(
              label: 'Reset to Defaults',
              colors: colors,
              enabled: settings.enabled,
              onPressed: () {
                onSettingsChanged(AutoStretchSettings.defaults().copyWith(
                  enabled: settings.enabled,
                ));
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Dialog for advanced stretch settings.
class _StretchSettingsDialog extends StatefulWidget {
  final AutoStretchSettings settings;
  final NightshadeColors colors;
  final ValueChanged<AutoStretchSettings> onSettingsChanged;

  const _StretchSettingsDialog({
    required this.settings,
    required this.colors,
    required this.onSettingsChanged,
  });

  @override
  State<_StretchSettingsDialog> createState() => _StretchSettingsDialogState();
}

class _StretchSettingsDialogState extends State<_StretchSettingsDialog> {
  late AutoStretchSettings _localSettings;

  @override
  void initState() {
    super.initState();
    _localSettings = widget.settings;
  }

  void _updateSettings(AutoStretchSettings newSettings) {
    setState(() {
      _localSettings = newSettings;
    });
    // Update the provider immediately for live preview
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    LucideIcons.sliders,
                    size: 20,
                    color: widget.colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Auto-Stretch Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: widget.colors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Text(
                'Configure how auto-stretch processes your images',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colors.textMuted,
                ),
              ),

              const SizedBox(height: 20),

              Divider(color: widget.colors.border, height: 1),

              const SizedBox(height: 20),

              // Expanded controls
              _ExpandedStretchControls(
                settings: _localSettings,
                colors: widget.colors,
                onSettingsChanged: _updateSettings,
              ),

              const SizedBox(height: 20),

              // Close button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  NightshadeButton(
                    label: 'Done',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Method dropdown with custom styling.
class _MethodDropdown extends StatelessWidget {
  final AutoStretchMethod value;
  final NightshadeColors colors;
  final ValueChanged<AutoStretchMethod?>? onChanged;
  final bool isExpanded;

  const _MethodDropdown({
    required this.value,
    required this.colors,
    this.onChanged,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<AutoStretchMethod>(
            value: value,
            isExpanded: isExpanded,
            isDense: true,
            icon: Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: colors.textSecondary,
            ),
            dropdownColor: colors.surface,
            borderRadius: BorderRadius.circular(8),
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
            ),
            items: AutoStretchMethod.values.map((method) {
              return DropdownMenuItem<AutoStretchMethod>(
                value: method,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _methodNames[method] ?? method.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: isEnabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

/// A compact icon button for the toolbar.
class _CompactIconButton extends StatefulWidget {
  final IconData icon;
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _CompactIconButton({
    required this.icon,
    required this.colors,
    required this.onPressed,
  });

  @override
  State<_CompactIconButton> createState() => _CompactIconButtonState();
}

class _CompactIconButtonState extends State<_CompactIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered
                ? widget.colors.textPrimary
                : widget.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A row with label, optional tooltip, and a child widget.
class _SettingRow extends StatelessWidget {
  final String label;
  final String? tooltip;
  final NightshadeColors colors;
  final Widget child;

  const _SettingRow({
    required this.label,
    this.tooltip,
    required this.colors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: 4),
          NightshadeTooltip(
            message: tooltip!,
            position: NightshadeTooltipPosition.top,
            child: Icon(
              LucideIcons.helpCircle,
              size: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );

    return Row(
      children: [
        Expanded(child: labelWidget),
        const SizedBox(width: 12),
        child,
      ],
    );
  }
}

/// A slider setting with label, tooltip, and value display.
class _SliderSetting extends StatelessWidget {
  final String label;
  final String? tooltip;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final NightshadeColors colors;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    this.tooltip,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.enabled,
    required this.colors,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              if (tooltip != null) ...[
                const SizedBox(width: 4),
                NightshadeTooltip(
                  message: tooltip!,
                  position: NightshadeTooltipPosition.top,
                  child: Icon(
                    LucideIcons.helpCircle,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  formatValue(value),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: enabled ? colors.primary : colors.textMuted,
              inactiveTrackColor: colors.surfaceAlt,
              thumbColor: enabled ? colors.primary : colors.textMuted,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: colors.primary.withValues(alpha: 0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple text button.
class _TextButton extends StatefulWidget {
  final String label;
  final NightshadeColors colors;
  final bool enabled;
  final VoidCallback onPressed;

  const _TextButton({
    required this.label,
    required this.colors,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovered = false) : null,
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered ? widget.colors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: _isHovered
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
