part of '../equipment_profiles_screen.dart';

// ============================================================================
// Helper Widgets
// ============================================================================

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  final bool isMobile;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final sectionPadding = isMobile ? 16.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: isMobile ? 16 : 18, color: colors.primary),
            SizedBox(width: isMobile ? 6 : 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        SizedBox(height: isMobile ? 12 : 16),
        Container(
          padding: EdgeInsets.all(sectionPadding),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final String label;
  final String? value;
  final TextEditingController? controller;
  final String? suffix;
  final String? hint;
  final bool readOnly;

  const _FieldCard({
    required this.label,
    this.value,
    this.controller,
    this.suffix,
    this.hint,
    this.readOnly = false,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        if (controller != null && !readOnly)
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                hintText: hint,
                hintStyle: TextStyle(color: colors.textMuted),
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                ),
              ),
            ),
          )
        else
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value ?? 'Not set',
                style: NightshadeTypography.h5.copyWith(color: value != null && value != 'Not set' && value != 'N/A'
                      ? colors.textPrimary
                      : colors.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _BinningSelector extends StatelessWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _BinningSelector({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              for (int i = 1; i <= 4; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: enabled ? () => onChanged(i) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: value == i ? colors.primary : Colors.transparent,
                        borderRadius: BorderRadius.horizontal(
                          left: i == 1 ? const Radius.circular(5) : Radius.zero,
                          right:
                              i == 4 ? const Radius.circular(5) : Radius.zero,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$i',
                          style: NightshadeTypography.h6.copyWith(color: value == i
                                ? colors.background
                                : colors.textSecondary),
                        ),
                      ),
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

class _FilterChip extends StatelessWidget {
  final String name;

  const _FilterChip({
    required this.name,
    });

  Color _getFilterColor(NightshadeColors colors, String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('red') ||
        lowerName == 'r' ||
        lowerName == 'ha' ||
        lowerName.contains('h-alpha')) {
      return colors.error;
    } else if (lowerName.contains('green') || lowerName == 'g') {
      return colors.success;
    } else if (lowerName.contains('blue') || lowerName == 'b') {
      return colors.info;
    } else if (lowerName.contains('lum') || lowerName == 'l') {
      return colors.textMuted;
    } else if (lowerName.contains('oiii') || lowerName.contains('o3')) {
      return colors.accent;
    } else if (lowerName.contains('sii') || lowerName.contains('s2')) {
      return colors.warning;
    }
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final filterColor = _getFilterColor(colors, name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: NightshadeDecorations.statusChip(
        filterColor,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: filterColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: NightshadeTypography.h6.copyWith(color: filterColor),
          ),
        ],
      ),
    );
  }
}

class _EditableFilterChip extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;

  const _EditableFilterChip({
    required this.controller,
    required this.onRemove,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Filter name',
                hintStyle: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              LucideIcons.x,
              size: 14,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String type;
  final String id;

  const _DeviceChip({
    required this.type,
    required this.id,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.link, size: 12, color: colors.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.textMuted,
                ),
              ),
              Text(
                id,
                style: NightshadeTypography.labelSm.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditableDeviceChip extends StatelessWidget {
  final String type;
  final String id;
  final String fullId;
  final VoidCallback onClear;

  const _EditableDeviceChip({
    required this.type,
    required this.id,
    required this.fullId,
    required this.onClear,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.link, size: 12, color: colors.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.textMuted,
                ),
              ),
              Tooltip(
                message: fullId,
                child: Text(
                  id,
                  style: NightshadeTypography.labelSm.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                size: 12,
                color: colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextStyle style;

  const _EditableField({
    required this.controller,
    this.hint,
    required this.style,
    });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return TextField(
      controller: controller,
      style: style,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: hint,
        hintStyle: style.copyWith(color: colors.textMuted),
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
