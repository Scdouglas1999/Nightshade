// ignore_for_file: invalid_use_of_protected_member

part of '../profile_editor_dialog.dart';

extension _ProfileEditorShellAndIdentity on _ProfileEditorDialogState {
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

  // ============================================================================
  // Section 1: Profile Identity
  // ============================================================================

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
            errorText: _nameController.text.isEmpty && _isSaving
                ? 'Name is required'
                : null,
          ),
          const SizedBox(height: 20),

          // Icon picker
          Text(
            'Icon',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
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
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
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
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border),
            ),
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
        ],
      ),
    );
  }

  // ============================================================================
}
