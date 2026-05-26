// ignore_for_file: unused_element_parameter

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:lucide_icons/lucide_icons.dart';

import 'package:nightshade_ui/nightshade_ui.dart';

/// Whether a [SettingRow] trailing control should use flexible width.
bool settingsTrailingIsNarrow(
  BuildContext context, {
  bool isMobile = false,
  BoxConstraints? constraints,
  double fixedWidth = 260,
}) {
  if (isMobile || Responsive.isMobile(context)) return true;
  if (constraints != null &&
      constraints.hasBoundedWidth &&
      constraints.maxWidth < fixedWidth + 48) {
    return true;
  }
  return false;
}

/// Layout parameters for trailing settings inputs on [SettingRow].
({bool flexible, double? width}) settingsTrailingLayout(
  BuildContext context, {
  double designWidth = 260,
  bool isMobile = false,
  BoxConstraints? constraints,
}) {
  final narrow = settingsTrailingIsNarrow(
    context,
    isMobile: isMobile,
    constraints: constraints,
    fixedWidth: designWidth,
  );
  return (flexible: narrow, width: narrow ? null : designWidth);
}

/// [SettingsTextInput] that shrinks on narrow setting rows / mobile viewports.
Widget settingsTrailingTextInput({
  required BuildContext context,
  required TextEditingController controller,
  ValueChanged<String>? onChanged,
  String? hint,
  double designWidth = 260,
  bool isMobile = false,
  bool obscure = false,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final layout = settingsTrailingLayout(
        context,
        designWidth: designWidth,
        isMobile: isMobile,
        constraints: constraints,
      );
      return SettingsTextInput(
        controller: controller,
        hint: hint,
        width: layout.width,
        flexible: layout.flexible,
        obscure: obscure,
        isMobile: isMobile,
        onChanged: onChanged,
      );
    },
  );
}

/// [SettingsDropdown] that shrinks on narrow setting rows / mobile viewports.
Widget settingsTrailingDropdown({
  required BuildContext context,
  required String value,
  required List<String> items,
  required ValueChanged<String?> onChanged,
  double designWidth = 200,
  bool isMobile = false,
  List<String>? itemLabels,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final layout = settingsTrailingLayout(
        context,
        designWidth: designWidth,
        isMobile: isMobile,
        constraints: constraints,
      );
      return SettingsDropdown(
        value: value,
        items: items,
        itemLabels: itemLabels,
        onChanged: onChanged,
        width: layout.width,
        flexible: layout.flexible,
        isMobile: isMobile,
      );
    },
  );
}

/// A full-page settings layout with title, description, and children.

class SettingsPage extends StatelessWidget {
  final String title;

  final String description;

  final List<Widget> children;

  final bool isMobile;

  /// If true, don't show title/description (used when mobile header already shows title)

  final bool hideHeader;

  const SettingsPage({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.isMobile = false,
    this.hideHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final padding = isMobile
        ? NightshadeTokens.paddingLg
        : const EdgeInsets.all(NightshadeTokens.space3xl);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader) ...[
            Text(
              title,
              style:
                  (isMobile ? NightshadeTypography.h3 : NightshadeTypography.h2)
                      .copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              description,
              style: (isMobile
                      ? NightshadeTypography.caption
                      : NightshadeTypography.bodySm)
                  .copyWith(color: colors.textSecondary),
            ),
            SizedBox(
                height: isMobile
                    ? NightshadeTokens.spaceXl
                    : NightshadeTokens.space3xl),
          ],
          ...children,
        ],
      ),
    );
  }
}

class SettingsLoadingState extends StatelessWidget {
  final bool isMobile;

  final String message;

  const SettingsLoadingState({
    super.key,
    this.isMobile = false,
    this.message = 'Loading settings...',
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final padding = isMobile
        ? NightshadeTokens.paddingLg
        : const EdgeInsets.all(NightshadeTokens.space3xl);

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
                borderRadius: NightshadeTokens.borderRadiusMd,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Container(
              width: 320,
              height: 14,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              ),
            ),
            SizedBox(
                height: isMobile
                    ? NightshadeTokens.spaceXl
                    : NightshadeTokens.space3xl),
            for (var i = 0; i < 2; i++) ...[
              Container(
                width: 140,
                height: 18,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusSm),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Container(
                width: double.infinity,
                height: isMobile ? 164 : 188,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(
                      isMobile ? 10 : NightshadeTokens.radiusLg),
                  border: Border.all(color: colors.border),
                ),
              ),
              SizedBox(height: isMobile ? NightshadeTokens.spaceXl : 28),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
                child: Text(
                  message,
                  style: (isMobile
                          ? NightshadeTypography.caption
                          : NightshadeTypography.bodySm)
                      .copyWith(color: colors.textMuted),
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
  final bool isMobile;

  final Object error;

  final VoidCallback? onRetry;

  const SettingsErrorState({
    super.key,
    required this.error,
    this.isMobile = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final horizontalPadding =
        isMobile ? NightshadeTokens.spaceLg : NightshadeTokens.space2xl;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth(context, 520),
        ),
        child: Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Container(
            padding: EdgeInsets.all(isMobile
                ? NightshadeTokens.spaceXl
                : NightshadeTokens.space2xl),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: NightshadeTokens.borderRadiusMd,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: NightshadeDecorations.iconChip(
                    colors.error,
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    LucideIcons.alertTriangle,
                    color: colors.error,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                Text(
                  'Failed to load settings',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.bold(
                    isMobile
                        ? NightshadeTypography.bodyLg
                        : NightshadeTypography.bodyLg.copyWith(fontSize: 18),
                  ).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: (isMobile
                          ? NightshadeTypography.caption
                          : NightshadeTypography.bodySm)
                      .copyWith(color: colors.textSecondary),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
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

  final bool isMobile;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              (isMobile ? NightshadeTypography.label : NightshadeTypography.h5)
                  .copyWith(color: colors.textPrimary),
        ),
        SizedBox(
            height:
                isMobile ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(
                isMobile ? 10 : NightshadeTokens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: children,
          ),
        ),
        SizedBox(height: isMobile ? NightshadeTokens.spaceXl : 28),
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
    this.isMobile = false,
    this.stackOnMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final shouldStack = isMobile && stackOnMobile;

    final horizontalPadding = isMobile ? 12.0 : NightshadeTokens.spaceLg;

    final verticalPadding = isMobile ? 12.0 : 14.0;

    final iconSize = isMobile ? 32.0 : 36.0;

    final iconInnerSize = isMobile ? 14.0 : NightshadeTokens.iconSm;

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
          ? _buildStackedLayout(colors, iconSize, iconInnerSize)
          : _buildRowLayout(colors, iconSize, iconInnerSize),
    );
  }

  Widget _buildRowLayout(
      NightshadeColors colors, double iconSize, double iconInnerSize) {
    return Row(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusMd,
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
                style: (isMobile
                        ? NightshadeTypography.labelSm
                        : NightshadeTypography.label)
                    .copyWith(color: colors.textPrimary),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: NightshadeTypography.captionSm.copyWith(
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

  Widget _buildStackedLayout(
      NightshadeColors colors, double iconSize, double iconInnerSize) {
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
                borderRadius: NightshadeTokens.borderRadiusMd,
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
                    style: NightshadeTypography.labelSm
                        .copyWith(color: colors.textPrimary),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: NightshadeTypography.captionSm
                          .copyWith(fontSize: 10, color: colors.textMuted),
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

/// Debounced toggle for settings rows backed by [SettingRow].

///

/// Use inside [SettingRow.trailing] when the row already supplies icon, title,

/// and subtitle. Wraps [NightshadeSwitch] with a 300 ms debounce so rapid

/// toggles coalesce to the final value before persisting.

///

/// For a self-contained label + switch row (no icon column), use

/// [NightshadeSwitchRow] instead. For a bare toggle with no label (toolbar,

/// table cell), use [NightshadeSwitch] directly.

class SettingsSwitch extends StatefulWidget {
  final bool value;

  final ValueChanged<bool> onChanged;

  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
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
    return NightshadeSwitch(
      value: widget.value,
      onChanged: (_) => _onTap(),
    );
  }
}

/// Dropdown selector for settings.

///

/// Compact trailing control sized for [SettingRow]. Styling mirrors

/// [NightshadeDropdown] / theme [InputDecorationTheme] but uses fixed widths

/// for settings layout — migrate to [NightshadeDropdown] when row sizing allows.

/// Dropdown selector for settings rows.
///
/// Compact trailing control for [SettingRow]. Styling mirrors
/// [NightshadeDropdown] (surfaceAlt fill, border, chevron) with fixed widths
/// and optional [itemLabels] for value/label pairs.
class SettingsDropdown extends StatelessWidget {
  final String value;

  final List<String> items;

  final ValueChanged<String?> onChanged;

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
    this.width,
    this.isMobile = false,
    this.flexible = false,
    this.itemLabels,
  });

  @override
  Widget build(BuildContext context) {
    final designWidth = width ?? (isMobile ? 120.0 : 140.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);
    final effectiveValue = items.contains(value) ? value : items.first;

    Widget dropdown = NightshadeDropdown(
      value: effectiveValue,
      items: items,
      itemLabels: itemLabels,
      onChanged: onChanged,
      isExpanded: true,
      isDense: true,
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

///

/// Compact trailing control for [SettingRow]. Styling mirrors

/// [NightshadeTextField] / theme [InputDecorationTheme] with fixed widths.

class SettingsTextInput extends StatefulWidget {
  final TextEditingController controller;

  final String? hint;

  final double? width;

  final bool obscure;

  final ValueChanged<String>? onChanged;

  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)

  final bool flexible;

  const SettingsTextInput({
    super.key,
    required this.controller,
    this.hint,
    this.width,
    this.obscure = false,
    this.onChanged,
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
    final designWidth = widget.width ?? (widget.isMobile ? 140.0 : 160.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);

    Widget input = NightshadeTextField(
      controller: widget.controller,
      hint: widget.hint,
      onChanged: widget.onChanged,
      obscureText: widget.obscure && _obscured,
      suffixWidget: widget.obscure
          ? GestureDetector(
              onTap: () => setState(() => _obscured = !_obscured),
              child: Padding(
                padding: const EdgeInsets.only(right: NightshadeTokens.spaceSm),
                child: Icon(
                  _obscured ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: NightshadeTokens.iconXs,
                  color: context.nightshadeColors.textMuted,
                ),
              ),
            )
          : null,
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
    this.width,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final designWidth = width ?? (isMobile ? 100.0 : 120.0);
    final effectiveWidth = dialogMaxWidth(context, designWidth);

    return SizedBox(
      width: effectiveWidth,
      child: NightshadeTextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        textAlign: TextAlign.right,
        suffix: suffix,
        onChanged: (value) {
          final parsed = double.tryParse(value);

          if (parsed != null) {
            final clamped = parsed.clamp(min, max);

            onChanged(clamped);
          }
        },
      ),
    );
  }
}

/// Color picker for accent color selection.

class SettingsColorPicker extends StatelessWidget {
  final String selectedColor;

  final ValueChanged<String> onColorSelected;

  final bool isMobile;

  const SettingsColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    this.isMobile = false,
  });

  static const accentColors = [
    ('#5B9EC4', 'Cyan-blue'),
    ('#10B981', 'Emerald'),
    ('#F59E0B', 'Amber'),
    ('#EF4444', 'Red'),
    ('#2878A8', 'Deep sky'),
    ('#EC4899', 'Pink'),
    ('#06B6D4', 'Cyan'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final circleSize = isMobile ? 28.0 : 24.0;

    final spacing =
        isMobile ? NightshadeTokens.spaceSm : NightshadeTokens.radiusSm;

    // Use Wrap for mobile to allow colors to wrap to next line if needed

    if (isMobile) {
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: accentColors.map((colorData) {
          final (hex, _) = colorData;

          return _buildColorCircle(colors, hex, circleSize);
        }).toList(),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: accentColors.map((colorData) {
        final (hex, _) = colorData;

        return Padding(
          padding: EdgeInsets.only(left: spacing),
          child: _buildColorCircle(colors, hex, circleSize),
        );
      }).toList(),
    );
  }

  Widget _buildColorCircle(NightshadeColors colors, String hex, double size) {
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
          border: Border.all(
            color: isSelected ? colors.textPrimary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// Path input with browse button for file/directory selection.

class SettingsPathInput extends StatelessWidget {
  final String path;

  final VoidCallback onBrowse;

  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)

  final bool flexible;

  const SettingsPathInput({
    super.key,
    required this.path,
    required this.onBrowse,
    this.isMobile = false,
    this.flexible = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    Widget pathContainer = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical:
            isMobile ? NightshadeTokens.spaceSm : NightshadeTokens.radiusSm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        path.isEmpty ? 'Not set' : path,
        style: (isMobile
                ? NightshadeTypography.caption
                : NightshadeTypography.captionSm)
            .copyWith(
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
        const SizedBox(width: NightshadeTokens.spaceSm),
        GestureDetector(
          onTap: onBrowse,
          child: Container(
            padding: EdgeInsets.all(isMobile
                ? NightshadeTokens.spaceSm
                : NightshadeTokens.radiusSm),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              LucideIcons.folderOpen,
              size:
                  isMobile ? NightshadeTokens.iconSm : NightshadeTokens.iconXs,
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

  final bool compact;

  const SettingsLinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<SettingsLinkButton> createState() => _SettingsLinkButtonState();
}

class _SettingsLinkButtonState extends State<SettingsLinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final horizontalPad =
        widget.compact ? NightshadeTokens.spaceMd : NightshadeTokens.spaceLg;

    final verticalPad = widget.compact ? NightshadeTokens.spaceSm : 10.0;

    final iconSize =
        widget.compact ? NightshadeTokens.iconXs : NightshadeTokens.iconSm;

    final labelStyle = widget.compact
        ? NightshadeTypography.captionSm
        : NightshadeTypography.caption;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          padding: EdgeInsets.symmetric(
              horizontal: horizontalPad, vertical: verticalPad),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceAlt : colors.background,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: iconSize,
                color: colors.textSecondary,
              ),
              SizedBox(
                  width: widget.compact
                      ? NightshadeTokens.radiusSm
                      : NightshadeTokens.spaceSm),
              Text(
                widget.label,
                style: labelStyle.copyWith(color: colors.textSecondary),
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

  const SettingsInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textMuted),
            ),
          ),
          Text(
            value,
            style: NightshadeTypography.monoSm
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Compact slider widget for settings.

///

/// Relies on theme [SliderThemeData] from [NightshadeTheme] for track/thumb

/// styling; only adds fixed width and value label for [SettingRow] layout.

class SettingsCompactSlider extends StatelessWidget {
  final double value;

  final double min;

  final double max;

  final int divisions;

  final String label;

  final ValueChanged<double> onChanged;

  final bool isMobile;

  const SettingsCompactSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final sliderWidth = isMobile ? 100.0 : 120.0;

    final labelWidth = isMobile ? 45.0 : 50.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: sliderWidth,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: (isMobile
                    ? NightshadeTypography.captionSm
                    : NightshadeTypography.caption)
                .copyWith(
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

  final bool isMobile;

  const ObjectTypeToggle({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.isEnabled,
    required this.onChanged,
    this.isLast = false,
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
      ),
      isLast: isLast,
      isMobile: isMobile,
    );
  }
}
