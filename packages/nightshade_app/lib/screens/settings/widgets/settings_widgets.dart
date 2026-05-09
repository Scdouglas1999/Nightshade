// ignore_for_file: unused_element_parameter

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A full-page settings layout with title, description, and children.
class SettingsPage extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> children;
  final NightshadeColors colors;
  final bool isMobile;

  /// If true, don't show title/description (used when mobile header already shows title)
  final bool hideHeader;

  const SettingsPage({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    required this.colors,
    this.isMobile = false,
    this.hideHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding =
        isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(32);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: isMobile ? 12 : 13,
                color: colors.textSecondary,
              ),
            ),
            SizedBox(height: isMobile ? 20 : 32),
          ],
          ...children,
        ],
      ),
    );
  }
}

class SettingsLoadingState extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;
  final String message;

  const SettingsLoadingState({
    super.key,
    required this.colors,
    this.isMobile = false,
    this.message = 'Loading settings...',
  });

  @override
  Widget build(BuildContext context) {
    final padding =
        isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(32);

    return SingleChildScrollView(
      padding: padding,
      child: ShimmerLoading(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 220,
              height: isMobile ? 24 : 28,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 320,
              height: 14,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            SizedBox(height: isMobile ? 20 : 32),
            for (var i = 0; i < 2; i++) ...[
              Container(
                width: 140,
                height: 18,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: isMobile ? 164 : 188,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                  border: Border.all(color: colors.border),
                ),
              ),
              SizedBox(height: isMobile ? 20 : 28),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsErrorState extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;
  final Object error;
  final VoidCallback? onRetry;

  const SettingsErrorState({
    super.key,
    required this.colors,
    required this.error,
    this.isMobile = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = isMobile ? 16.0 : 24.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Container(
            padding: EdgeInsets.all(isMobile ? 20 : 24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.alertTriangle,
                    color: colors.error,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    color: colors.textSecondary,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  NightshadeButton(
                    label: 'Retry',
                    icon: LucideIcons.refreshCw,
                    onPressed: onRetry,
                    size: isMobile ? ButtonSize.small : ButtonSize.medium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section container with a title and grouped settings rows.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final NightshadeColors colors;
  final bool isMobile;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    required this.colors,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        SizedBox(height: isMobile ? 12 : 16),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: children,
          ),
        ),
        SizedBox(height: isMobile ? 20 : 28),
      ],
    );
  }
}

/// A single row in a settings section with an icon, title, optional subtitle, and trailing widget.
class SettingRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool isLast;
  final NightshadeColors colors;
  final bool isMobile;

  /// If true, stack the trailing widget below the title on mobile
  final bool stackOnMobile;

  const SettingRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.isLast = false,
    required this.colors,
    this.isMobile = false,
    this.stackOnMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final shouldStack = isMobile && stackOnMobile;
    final horizontalPadding = isMobile ? 12.0 : 16.0;
    final verticalPadding = isMobile ? 12.0 : 14.0;
    final iconSize = isMobile ? 32.0 : 36.0;
    final iconInnerSize = isMobile ? 14.0 : 16.0;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: verticalPadding),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
              ),
      ),
      child: shouldStack
          ? _buildStackedLayout(iconSize, iconInnerSize)
          : _buildRowLayout(iconSize, iconInnerSize),
    );
  }

  Widget _buildRowLayout(double iconSize, double iconInnerSize) {
    return Row(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: iconInnerSize, color: iconColor ?? colors.textSecondary),
        ),
        SizedBox(width: isMobile ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: isMobile ? 10 : 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildStackedLayout(double iconSize, double iconInnerSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: iconInnerSize,
                  color: iconColor ?? colors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.only(left: iconSize + 10),
          child: trailing,
        ),
      ],
    );
  }
}

/// Custom toggle switch for settings.
///
/// Debounces the write callback by 300ms so rapid toggles don't hammer the
/// database. If the user toggles back and forth quickly, only the final
/// value is written. The visual state is driven by the [value] prop from
/// the parent, which updates when the provider's state changes after the
/// debounced callback fires.
class SettingsSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final NightshadeColors colors;

  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    // If there's a pending write, fire it now so the last toggle isn't lost
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      // The pending value is the opposite of the current widget value,
      // since the timer was set to flip it
      widget.onChanged(!widget.value);
    }
    super.dispose();
  }

  void _onTap() {
    final newValue = !widget.value;
    // Cancel any previous pending write
    _debounceTimer?.cancel();
    // Delay the DB write by 300ms; rapid toggles coalesce to the final value
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:
              widget.value ? widget.colors.primary : widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.value ? widget.colors.primary : widget.colors.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment:
              widget.value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: widget.colors.background,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dropdown selector for settings.
class SettingsDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final NightshadeColors colors;
  final double? width;
  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)
  final bool flexible;

  /// Optional display labels for items. When provided, must have same length
  /// as [items]. The dropdown shows these labels but emits the corresponding
  /// value from [items].
  final List<String>? itemLabels;

  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.colors,
    this.width,
    this.isMobile = false,
    this.flexible = false,
    this.itemLabels,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width ?? (isMobile ? 120.0 : 140.0);

    Widget dropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 14,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: isMobile ? 11 : 12,
            color: colors.textPrimary,
          ),
          items: List.generate(items.length, (i) {
            final item = items[i];
            final label = (itemLabels != null && i < itemLabels!.length)
                ? itemLabels![i]
                : item;
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );

    if (flexible) {
      return dropdown;
    }

    return SizedBox(
      width: effectiveWidth,
      child: dropdown,
    );
  }
}

/// Text input field for settings.
class SettingsTextInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final double? width;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final NightshadeColors colors;
  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)
  final bool flexible;

  const SettingsTextInput({
    super.key,
    required this.controller,
    this.hint,
    this.width,
    this.obscure = false,
    required this.onChanged,
    required this.colors,
    this.isMobile = false,
    this.flexible = false,
  });

  @override
  State<SettingsTextInput> createState() => _SettingsTextInputState();
}

class _SettingsTextInputState extends State<SettingsTextInput> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = widget.width ?? (widget.isMobile ? 140.0 : 160.0);

    Widget input = Container(
      height: widget.isMobile ? 36 : 32,
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: widget.obscure && _obscured,
              style: TextStyle(
                fontSize: widget.isMobile ? 13 : 12,
                color: widget.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontSize: widget.isMobile ? 13 : 12,
                  color: widget.colors.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: widget.isMobile ? 10 : 8,
                ),
                isDense: true,
              ),
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.obscure)
            GestureDetector(
              onTap: () => setState(() => _obscured = !_obscured),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  _obscured ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 14,
                  color: widget.colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.flexible) {
      return input;
    }

    return SizedBox(
      width: effectiveWidth,
      child: input,
    );
  }
}

/// Number input field for settings.
class SettingsNumberInput extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;
  final double? width;
  final bool isMobile;

  const SettingsNumberInput({
    super.key,
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    required this.colors,
    this.width,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width ?? (isMobile ? 100.0 : 120.0);

    return Container(
      width: effectiveWidth,
      height: isMobile ? 36 : 32,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: decimals > 0),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: TextStyle(
                fontSize: isMobile ? 13 : 12,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: isMobile ? 10 : 8,
                ),
                isDense: true,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: isMobile ? 11 : 11,
                  color: colors.textMuted,
                ),
              ),
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  final clamped = parsed.clamp(min, max);
                  onChanged(clamped);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Color picker for accent color selection.
class SettingsColorPicker extends StatelessWidget {
  final String selectedColor;
  final ValueChanged<String> onColorSelected;
  final NightshadeColors colors;
  final bool isMobile;

  const SettingsColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    required this.colors,
    this.isMobile = false,
  });

  static const accentColors = [
    ('#6366F1', 'Indigo'),
    ('#10B981', 'Emerald'),
    ('#F59E0B', 'Amber'),
    ('#EF4444', 'Red'),
    ('#8B5CF6', 'Violet'),
    ('#EC4899', 'Pink'),
    ('#06B6D4', 'Cyan'),
  ];

  @override
  Widget build(BuildContext context) {
    final circleSize = isMobile ? 28.0 : 24.0;
    final spacing = isMobile ? 8.0 : 6.0;

    // Use Wrap for mobile to allow colors to wrap to next line if needed
    if (isMobile) {
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: accentColors.map((colorData) {
          final (hex, _) = colorData;
          return _buildColorCircle(hex, circleSize);
        }).toList(),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: accentColors.map((colorData) {
        final (hex, _) = colorData;
        return Padding(
          padding: EdgeInsets.only(left: spacing),
          child: _buildColorCircle(hex, circleSize),
        );
      }).toList(),
    );
  }

  Widget _buildColorCircle(String hex, double size) {
    final color = Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
    final isSelected = selectedColor.toLowerCase() == hex.toLowerCase();

    return GestureDetector(
      onTap: () => onColorSelected(hex),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: colors.background, width: 2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Path input with browse button for file/directory selection.
class SettingsPathInput extends StatelessWidget {
  final String path;
  final VoidCallback onBrowse;
  final NightshadeColors colors;
  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)
  final bool flexible;

  const SettingsPathInput({
    super.key,
    required this.path,
    required this.onBrowse,
    required this.colors,
    this.isMobile = false,
    this.flexible = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget pathContainer = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: isMobile ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        path.isEmpty ? 'Not set' : path,
        style: TextStyle(
          fontSize: isMobile ? 12 : 11,
          color: path.isEmpty ? colors.textMuted : colors.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (!flexible) {
      pathContainer = SizedBox(
        width: isMobile ? 140.0 : 180.0,
        child: pathContainer,
      );
    }

    return Row(
      mainAxisSize: flexible ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (flexible) Expanded(child: pathContainer) else pathContainer,
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onBrowse,
          child: Container(
            padding: EdgeInsets.all(isMobile ? 8 : 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              LucideIcons.folderOpen,
              size: isMobile ? 16 : 14,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A clickable link-style button with an icon and label.
class SettingsLinkButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final NightshadeColors colors;
  final bool compact;

  const SettingsLinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    this.compact = false,
  });

  @override
  State<SettingsLinkButton> createState() => _SettingsLinkButtonState();
}

class _SettingsLinkButtonState extends State<SettingsLinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final horizontalPad = widget.compact ? 12.0 : 16.0;
    final verticalPad = widget.compact ? 8.0 : 10.0;
    final iconSize = widget.compact ? 14.0 : 16.0;
    final fontSize = widget.compact ? 11.0 : 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPad, vertical: verticalPad),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.surfaceAlt
                : widget.colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: iconSize,
                color: widget.colors.textSecondary,
              ),
              SizedBox(width: widget.compact ? 6 : 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label-value pair row for the About screen.
class SettingsInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const SettingsInfoRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact slider widget for settings.
class SettingsCompactSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final NightshadeColors colors;
  final bool isMobile;

  const SettingsCompactSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    required this.colors,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final sliderWidth = isMobile ? 100.0 : 120.0;
    final labelWidth = isMobile ? 45.0 : 50.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: sliderWidth,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// Toggle widget for object type filters in annotation settings.
class ObjectTypeToggle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;
  final bool isLast;
  final NightshadeColors colors;
  final bool isMobile;

  const ObjectTypeToggle({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.isEnabled,
    required this.onChanged,
    this.isLast = false,
    required this.colors,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: isEnabled ? 'Visible' : 'Hidden',
      trailing: SettingsSwitch(
        value: isEnabled,
        onChanged: onChanged,
        colors: colors,
      ),
      isLast: isLast,
      colors: colors,
      isMobile: isMobile,
    );
  }
}
