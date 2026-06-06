part of '../autofocus_settings.dart';

class _FilterSettingsMobileCard extends StatefulWidget {
  final int position;
  final String filterName;
  final FilterAutofocusConfig config;
  final List<String> allFilterNames;
  final bool isLast;
  final ValueChanged<FilterAutofocusConfig> onConfigChanged;

  const _FilterSettingsMobileCard({
    required this.position,
    required this.filterName,
    required this.config,
    required this.allFilterNames,
    required this.isLast,
    required this.onConfigChanged,
  });

  @override
  State<_FilterSettingsMobileCard> createState() =>
      _FilterSettingsMobileCardState();
}

class _FilterSettingsMobileCardState extends State<_FilterSettingsMobileCard> {
  late TextEditingController _focusOffsetController;
  late TextEditingController _afExpTimeController;
  late TextEditingController _gainController;
  late TextEditingController _offsetController;

  @override
  void initState() {
    super.initState();
    _focusOffsetController = TextEditingController(
      text: widget.config.focusOffset.toString(),
    );
    _afExpTimeController = TextEditingController(
      text: widget.config.afExposureTime?.toString() ?? '',
    );
    _gainController = TextEditingController(
      text: widget.config.gain?.toString() ?? '',
    );
    _offsetController = TextEditingController(
      text: widget.config.offset?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_FilterSettingsMobileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _focusOffsetController.text = widget.config.focusOffset.toString();
      _afExpTimeController.text =
          widget.config.afExposureTime?.toString() ?? '';
      _gainController.text = widget.config.gain?.toString() ?? '';
      _offsetController.text = widget.config.offset?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _focusOffsetController.dispose();
    _afExpTimeController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final afFilterName = widget.config.afFilterName ?? 'Default';
    final binningStr = '${widget.config.binning}x${widget.config.binning}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: NightshadeColors.of(context)
                      .border
                      .withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: position + name
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: NightshadeDecorations.tintedBadge(
                  NightshadeColors.of(context).primary,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
                child: Center(
                  child: Text(
                    '${widget.position}',
                    style: NightshadeTypography.h6.copyWith(color: NightshadeColors.of(context).primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.filterName,
                style: NightshadeTypography.h5.copyWith(color: NightshadeColors.of(context).textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Settings grid (2 columns)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildMobileField(
                'Focus Offset',
                _buildCompactNumberInput(
                  controller: _focusOffsetController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      widget.onConfigChanged(
                        widget.config.copyWith(focusOffset: parsed),
                      );
                    }
                  },
                ),
              ),
              _buildMobileField(
                'AF Exp Time',
                _buildCompactNumberInput(
                  controller: _afExpTimeController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearAfExposureTime: true),
                      );
                    } else {
                      final parsed = double.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(afExposureTime: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
              _buildMobileField(
                'AF Filter',
                SettingsDropdown(
                  value: afFilterName,
                  items: ['Default', ...widget.allFilterNames],
                  onChanged: (value) {
                    if (value != null) {
                      if (value == 'Default') {
                        widget.onConfigChanged(
                          widget.config.copyWith(clearAfFilterName: true),
                        );
                      } else {
                        widget.onConfigChanged(
                          widget.config.copyWith(afFilterName: value),
                        );
                      }
                    }
                  },
                  isMobile: true,
                  flexible: true,
                ),
              ),
              _buildMobileField(
                'Binning',
                SettingsDropdown(
                  value: binningStr,
                  items: const ['1x1', '2x2', '3x3', '4x4'],
                  onChanged: (value) {
                    if (value != null) {
                      final binVal = int.tryParse(value.split('x').first) ?? 1;
                      widget.onConfigChanged(
                        widget.config.copyWith(binning: binVal),
                      );
                    }
                  },
                  isMobile: true,
                  flexible: true,
                ),
              ),
              _buildMobileField(
                'Gain',
                _buildCompactNumberInput(
                  controller: _gainController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearGain: true),
                      );
                    } else {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(gain: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
              _buildMobileField(
                'Offset',
                _buildCompactNumberInput(
                  controller: _offsetController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearOffset: true),
                      );
                    } else {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(offset: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileField(String label, Widget input) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w600,
              color: NightshadeColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          input,
        ],
      ),
    );
  }

  Widget _buildCompactNumberInput({
    required TextEditingController controller,
    String? hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: NightshadeColors.of(context).surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
        border: Border.all(color: NightshadeColors.of(context).border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: NightshadeColors.of(context).textPrimary,
        ),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: NightshadeColors.of(context).textMuted,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
