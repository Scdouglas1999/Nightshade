// Part of ../quick_start_wizard_dialog.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../quick_start_wizard_dialog.dart';

extension _FilterStep on _QuickStartWizardDialogState {
  // ===========================================================================
  // STEP 2: FILTERS & EXPOSURES
  // ===========================================================================

  Widget _buildFiltersStep(NightshadeColors colors) {
    final hasFilters = ref.watch(profileFiltersProvider).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasFilters) ...[
          Text(
            'Quick Presets',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ExposurePreset.values.map((preset) {
              final isSelected = _selectedPreset == preset;
              return InkWell(
                onTap: () => _applyPreset(preset),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NightshadeDecorations.statusChip(
                            colors.primary,
                            borderRadius: BorderRadius.circular(8),
                            bordered: false,
                          ).color
                        : colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? colors.primary : colors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.label,
                        style: TextStyle(
                          color:
                              isSelected ? colors.primary : colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        preset.description,
                        style: TextStyle(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        Text(
          hasFilters ? 'Filter Exposures' : 'Exposure Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        // Column headers
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Filter',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Exposure',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Count',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Binning',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              const SizedBox(width: 60),
            ],
          ),
        ),
        const SizedBox(height: 4),

        ...List.generate(_filterConfigs.length, (index) {
          final config = _filterConfigs[index];
          return _buildFilterRow(config, colors);
        }),

        const SizedBox(height: 20),

        // Loop settings
        Text(
          'Loop Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<LoopConditionType>(
                initialValue: _loopType,
                dropdownColor: colors.surfaceAlt,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Loop Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  LoopConditionType.count,
                  LoopConditionType.forever,
                  LoopConditionType.whileDark,
                ].map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(
                      type == LoopConditionType.count
                          ? 'Fixed Count'
                          : type == LoopConditionType.forever
                              ? 'Run Forever'
                              : 'While Dark',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) _update(() => _loopType = value);
                },
              ),
            ),
            if (_loopType == LoopConditionType.count) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  controller:
                      TextEditingController(text: _loopCount.toString()),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Iterations',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    labelStyle: TextStyle(color: colors.textSecondary),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      _update(() => _loopCount = parsed);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFilterRow(
      _FilterExposureConfig config, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: NightshadeCheckbox(
              value: config.enabled,
              onChanged: (value) {
                _update(() {
                  config.enabled = value ?? false;
                  _selectedPreset = _ExposurePreset.custom;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              config.filterName,
              style: TextStyle(
                color: config.enabled ? colors.textPrimary : colors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: TextEditingController(
                    text: config.exposureSecs.round().toString()),
                enabled: config.enabled,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: 's',
                  suffixStyle: TextStyle(color: colors.textMuted, fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    config.exposureSecs = parsed;
                    config.exposureEdited = true;
                    _selectedPreset = _ExposurePreset.custom;
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller:
                    TextEditingController(text: config.count.toString()),
                enabled: config.enabled,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    config.count = parsed;
                    _selectedPreset = _ExposurePreset.custom;
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: DropdownButtonFormField<BinningMode>(
                initialValue: config.binning,
                dropdownColor: colors.surfaceAlt,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                items: BinningMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(mode.label,
                        style: TextStyle(color: colors.textPrimary)),
                  );
                }).toList(),
                onChanged: config.enabled
                    ? (value) {
                        if (value != null) {
                          _update(() {
                            config.binning = value;
                            _selectedPreset = _ExposurePreset.custom;
                          });
                        }
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _formatFilterTotal(config),
              style: TextStyle(
                color: config.enabled ? colors.textSecondary : colors.textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFilterTotal(_FilterExposureConfig config) {
    if (!config.enabled) return '';
    final totalMins = (config.totalSecs / 60).round();
    return '${totalMins}m';
  }
}
