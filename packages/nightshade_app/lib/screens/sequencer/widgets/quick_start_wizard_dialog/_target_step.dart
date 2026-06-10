// Part of ../quick_start_wizard_dialog.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../quick_start_wizard_dialog.dart';

extension _TargetStep on _QuickStartWizardDialogState {
  // ===========================================================================
  // STEP 1: TARGET
  // ===========================================================================

  Widget _buildTargetStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search for a target or enter coordinates manually.',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13),
        ),
        const SizedBox(height: 16),

        // Target name / search
        TextField(
          controller: _targetNameController,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Target Name',
            hintText: 'e.g., M42, NGC 7000, Orion Nebula',
            prefixIcon: Icon(LucideIcons.search, color: colors.textMuted),
            suffixIcon: _isSearching
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surfaceAlt,
            labelStyle: TextStyle(color: colors.textSecondary),
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onChanged: _onTargetSearch,
        ),

        // Search results
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final target = _searchResults[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    target.name,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: NightshadeTypography.fontSize13),
                  ),
                  subtitle: Text(
                    '${target.catalogId ?? ""} | RA: ${_formatRa(target.ra)} Dec: ${_formatDec(target.dec)}',
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: NightshadeTypography.fontSize11),
                  ),
                  trailing: target.magnitude != null
                      ? Text(
                          'mag ${target.magnitude!.toStringAsFixed(1)}',
                          style: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize11),
                        )
                      : null,
                  onTap: () => _selectTarget(target),
                );
              },
            ),
          ),

        const SizedBox(height: 20),

        // Coordinates
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _raController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Right Ascension',
                  hintText: '12h 30m 0s or 12.5',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
                onChanged: (_) => _update(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _decController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Declination',
                  hintText: "+45d 30' 0\" or 45.5",
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
                onChanged: (_) => _update(() {}),
              ),
            ),
          ],
        ),

        if (_selectedTarget != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.primary,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: colors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: ${_selectedTarget!.name}'
                    '${_selectedTarget!.objectType != null ? " (${_selectedTarget!.objectType})" : ""}',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: NightshadeTypography.fontSize13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
