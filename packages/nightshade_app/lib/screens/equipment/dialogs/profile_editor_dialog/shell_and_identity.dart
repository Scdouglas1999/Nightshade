// ignore_for_file: invalid_use_of_protected_member

part of '../profile_editor_dialog.dart';

extension _ProfileEditorShellAndIdentity on _ProfileEditorDialogState {
  /// Persistent validation summary rendered INSIDE the dialog, above the
  /// sections.
  ///
  /// Replaces relying on a transient snackbar that appeared ~150 px below the
  /// Save button at the bottom edge of the window, dimmed by the modal barrier to
  /// a measured 2.00:1 contrast ratio, and disappeared after a few seconds. The
  /// banner stays until the form validates, sits where the user is already
  /// looking, and is not subject to the scrim.
  Widget _buildValidationBanner(NightshadeColors colors) {
    final messages = <String>[
      if (_nameError != null) _nameError!,
      ..._fieldErrors.values.whereType<String>(),
      ..._formErrors,
    ];
    if (messages.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(color: colors.error.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messages.length == 1
                        ? 'Fix 1 problem before saving'
                        : 'Fix ${messages.length} problems before saving',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.error),
                  ),
                  const SizedBox(height: 4),
                  for (final message in messages)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $message',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      NightshadeColors colors, ThemeData theme, bool isEditing) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: NightshadeDecorations.emphasisSurface(
              colors.primary,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            ),
            child: Icon(
              isEditing ? LucideIcons.edit : LucideIcons.plus,
              color: colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Profile' : 'New Profile',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEditing
                      ? 'Modify your equipment configuration'
                      : 'Create a new equipment configuration',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _isSaving ? null : () => Navigator.of(context).pop(false),
            icon: Icon(LucideIcons.x, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          NightshadeButton(
            onPressed:
                _isSaving ? null : () => Navigator.of(context).pop(false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            onPressed: _isSaving ? null : _save,
            label: 'Save Changes',
            icon: LucideIcons.check,
            variant: ButtonVariant.primary,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  // Section 1: profile identity

  Widget _buildIdentitySection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Profile Identity',
      icon: LucideIcons.user,
      isExpanded: _expandedSections['identity']!,
      onToggle: () => setState(() =>
          _expandedSections['identity'] = !_expandedSections['identity']!),
      summary: _nameController.text.isEmpty ? 'Unnamed' : _nameController.text,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          NightshadeTextField(
            label: 'Profile Name *',
            controller: _nameController,
            hint: 'e.g., Main Imaging Rig, Widefield Setup',
            errorText: _nameError,
            onChanged: (_) {
              // Clear a standing validation error the moment the user edits,
              // and refresh the section summary that mirrors the name.
              if (_nameError != null) {
                setState(() => _nameError = null);
              } else {
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 20),

          // Icon picker
          Text(
            'Icon',
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ProfileEditorDialogState._availableIcons.map((icon) {
              final isSelected = _selectedIcon == icon;
              return _IconOption(
                icon: icon,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedIcon = icon),
                colors: colors,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Color picker
          Text(
            'Accent Color',
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // None option
              _ColorOption(
                color: null,
                isSelected: _selectedColor == null,
                onTap: () => setState(() => _selectedColor = null),
                colors: colors,
              ),
              ..._ProfileEditorDialogState._accentColors.map((color) {
                final isSelected = _selectedColor == color;
                return _ColorOption(
                  color: color,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedColor = color),
                  colors: colors,
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // Default checkbox
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                title: Text(
                  'Default profile',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize14,
                  ),
                ),
                subtitle: Text(
                  'Set as active profile on startup',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
                activeColor: colors.primary,
                checkColor: Theme.of(context).colorScheme.onPrimary,
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
