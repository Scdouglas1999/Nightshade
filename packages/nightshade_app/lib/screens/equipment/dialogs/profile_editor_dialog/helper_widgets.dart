part of '../profile_editor_dialog.dart';

// Helper widgets

/// Collapsible section card
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String summary;
  final Widget child;
  final NightshadeColors colors;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.summary,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        children: [
          // Header (always visible, clickable to toggle)
          InkWell(
            onTap: onToggle,
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(8))
                : BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: NightshadeDecorations.tintedBadge(
                      colors.primary,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
                    ),
                    child: Icon(icon, size: 16, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: NightshadeTypography.h5
                              .copyWith(color: colors.textPrimary),
                        ),
                        if (!isExpanded) ...[
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Content (only when expanded)
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Icon selection option
class _IconOption extends StatelessWidget {
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _IconOption({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.2)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: icon.isEmpty
              ? Icon(
                  LucideIcons.ban,
                  size: 18,
                  color: colors.textMuted,
                )
              : Text(
                  icon,
                  style: const TextStyle(
                      fontSize: NightshadeTypography.fontSize20),
                ),
        ),
      ),
    );
  }
}

/// Color selection option
class _ColorOption extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _ColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color ?? colors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? onPrimary : (color ?? colors.border),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (color ?? colors.primary).withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: color == null
            ? Icon(
                LucideIcons.ban,
                size: 14,
                color: colors.textMuted,
              )
            : null,
      ),
    );
  }
}

/// Computed value display
class _ComputedValue extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final NightshadeColors colors;

  const _ComputedValue({
    required this.label,
    required this.value,
    this.subtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: NightshadeTypography.fontSize11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: colors.primary,
            fontSize: NightshadeTypography.fontSize16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle!,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize10,
            ),
          ),
        ],
      ],
    );
  }
}

/// Device row with dropdown for selection
class _DeviceRow extends StatelessWidget {
  final String type;
  final IconData icon;
  // Null when this device type has no persisted friendly-name column, so the
  // row shows only the device id (no editable name field to silently discard).
  final TextEditingController? nameController;
  final String? deviceId;
  final List<UnifiedDevice> discoveredDevices;
  final void Function(String? id, String? name) onDeviceSelected;
  final VoidCallback onClear;
  final VoidCallback onScan;
  final NightshadeColors colors;

  const _DeviceRow({
    required this.type,
    required this.icon,
    required this.nameController,
    required this.deviceId,
    required this.discoveredDevices,
    required this.onDeviceSelected,
    required this.onClear,
    required this.onScan,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final nameController = this.nameController;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: deviceId != null
              ? colors.primary.withValues(alpha: 0.3)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device type header with dropdown
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
                child: Icon(icon, size: 14, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: NightshadeTypography.labelQuiet
                          .copyWith(color: colors.textSecondary),
                    ),
                    if (nameController != null) ...[
                      const SizedBox(height: 4),
                      // Friendly name text field
                      SizedBox(
                        height: 32,
                        child: TextField(
                          controller: nameController,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: NightshadeTypography.fontSize13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Friendly name...',
                            hintStyle: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize13,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                              borderSide: BorderSide(color: colors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                              borderSide: BorderSide(color: colors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                              borderSide: BorderSide(color: colors.primary),
                            ),
                            filled: true,
                            fillColor: colors.surface,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Device selection dropdown
              _DeviceDropdown(
                deviceId: deviceId,
                discoveredDevices: discoveredDevices,
                onSelected: onDeviceSelected,
                onScan: onScan,
                colors: colors,
              ),
              // Clear button
              if (deviceId != null)
                IconButton(
                  onPressed: onClear,
                  icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),

          // Show device ID if assigned
          if (deviceId != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Text(
                deviceId!,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: NightshadeTypography.fontSize10,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dropdown for selecting a device
class _DeviceDropdown extends StatelessWidget {
  final String? deviceId;
  final List<UnifiedDevice> discoveredDevices;
  final void Function(String? id, String? name) onSelected;
  final VoidCallback onScan;
  final NightshadeColors colors;

  const _DeviceDropdown({
    required this.deviceId,
    required this.discoveredDevices,
    required this.onSelected,
    required this.onScan,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Select device',
      onSelected: (value) {
        if (value == '_manual_') {
          _showManualEntryDialog(context);
        } else if (value == '_scan_') {
          // Trigger a real discovery refresh; the parent watches
          // unifiedDiscoveryProvider so the dropdown repopulates when it lands.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scanning for devices...')),
          );
          onScan();
        } else {
          // Find the device name
          final device = discoveredDevices
              .where((d) => d.activeDeviceId == value)
              .firstOrNull;
          onSelected(value, device?.displayName);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        // Current selection
        if (deviceId != null) {
          items.add(PopupMenuItem(
            value: deviceId,
            child: Row(
              children: [
                Icon(LucideIcons.check, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getDeviceDisplayName(deviceId!),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ));
          items.add(const PopupMenuDivider());
        }

        // Discovered devices
        if (discoveredDevices.isNotEmpty) {
          for (final device in discoveredDevices) {
            if (device.activeDeviceId == deviceId) continue;
            items.add(PopupMenuItem(
              value: device.activeDeviceId,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  Text(
                    device.activeBackend.shortLabel,
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: NightshadeTypography.fontSize11),
                  ),
                ],
              ),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // Actions
        items.add(PopupMenuItem(
          value: '_scan_',
          child: Row(
            children: [
              Icon(LucideIcons.refreshCw,
                  size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Scan...', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ));
        items.add(PopupMenuItem(
          value: '_manual_',
          child: Row(
            children: [
              Icon(LucideIcons.edit3, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Enter manually...',
                  style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ));

        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deviceId != null ? 'Selected' : 'Select...',
              style: TextStyle(
                color: deviceId != null ? colors.textPrimary : colors.textMuted,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  String _getDeviceDisplayName(String id) {
    final device =
        discoveredDevices.where((d) => d.activeDeviceId == id).firstOrNull;
    return device?.displayName ?? id;
  }

  Future<void> _showManualEntryDialog(BuildContext context) async {
    var deviceId = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Device ID'),
          content: TextFormField(
            onChanged: (value) => deviceId = value,
            decoration: const InputDecoration(
              hintText: 'Device ID or path...',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, deviceId.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      onSelected(result, null);
    }
  }
}

/// Filter row widget
class _FilterRow extends StatelessWidget {
  final int index;
  final TextEditingController nameController;
  final TextEditingController offsetController;
  final VoidCallback onRemove;
  final bool isLast;
  final NightshadeColors colors;

  const _FilterRow({
    required this.index,
    required this.nameController,
    required this.offsetController,
    required this.onRemove,
    required this.isLast,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$index',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: nameController,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize13),
                decoration: InputDecoration(
                  hintText: 'Filter name',
                  hintStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: NightshadeTypography.fontSize13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            height: 32,
            child: TextField(
              controller: offsetController,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize13),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize13),
                suffixText: 'steps',
                suffixStyle: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize10),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
                  borderSide: BorderSide(color: colors.primary),
                ),
                filled: true,
                fillColor: colors.surface,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Helper class for filter name and offset controllers
class _FilterControllerPair {
  final TextEditingController nameController;
  final TextEditingController offsetController;

  _FilterControllerPair({
    required this.nameController,
    required this.offsetController,
  });

  void dispose() {
    nameController.dispose();
    offsetController.dispose();
  }
}

/// Extension to get trimmed string or null
extension _StringTrimOrNull on String {
  String? get trimOrNull {
    final trimmed = trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
