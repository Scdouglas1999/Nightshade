part of '../settings_widgets.dart';

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
