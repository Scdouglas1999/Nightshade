// Part of ../quick_start_wizard_dialog.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../quick_start_wizard_dialog.dart';

extension _SafetyStep on _QuickStartWizardDialogState {
  // ===========================================================================
  // STEP 4: SAFETY
  // ===========================================================================

  Widget _buildSafetyStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure safety and shutdown behavior.',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13),
        ),
        if (_populatedFromSavedDefaults) ...[
          const SizedBox(height: 8),
          _buildSavedDefaultsHint(colors),
        ],
        const SizedBox(height: 16),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.snowflake,
          title: 'Cool Camera',
          subtitle: 'Cool the camera sensor before imaging and warm after',
          value: _coolCamera,
          onChanged: (v) => _update(() => _coolCamera = v),
        ),
        if (_coolCamera) ...[
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                Text('Target temperature:',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: TextField(
                    controller: _coolingTempController,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: NightshadeTypography.fontSize12),
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true),
                    decoration: InputDecoration(
                      suffixText: 'C',
                      suffixStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: NightshadeTypography.fontSize11),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(NightshadeTokens.radiusMd),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(NightshadeTokens.radiusMd),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      filled: true,
                      fillColor: colors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null) {
                        _update(() => _coolingTemp = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.parkingCircle,
          title: 'Park on Error',
          subtitle: 'Park the mount if an unrecoverable error occurs',
          value: _parkOnError,
          onChanged: (v) => _update(() => _parkOnError = v),
        ),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.cloudRain,
          title: 'Weather Abort',
          subtitle: 'Park and abort if the weather becomes unsafe',
          value: _weatherAbort,
          onChanged: (v) => _update(() => _weatherAbort = v),
        ),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.sunrise,
          title: 'Dawn Shutdown',
          subtitle: 'Warm camera and park mount at the end of the session',
          value: _dawnShutdown,
          onChanged: (v) => _update(() => _dawnShutdown = v),
        ),
      ],
    );
  }
}
