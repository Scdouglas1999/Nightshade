part of '../autofocus_settings.dart';

class _FilterSettingsRow extends StatefulWidget {
  final int position;
  final String filterName;
  final FilterAutofocusConfig config;
  final List<String> allFilterNames;
  final bool isLast;
  final ValueChanged<FilterAutofocusConfig> onConfigChanged;

  const _FilterSettingsRow({
    required this.position,
    required this.filterName,
    required this.config,
    required this.allFilterNames,
    required this.isLast,
    required this.onConfigChanged,
  });

  @override
  State<_FilterSettingsRow> createState() => _FilterSettingsRowState();
}

class _FilterSettingsRowState extends State<_FilterSettingsRow> {
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
  void didUpdateWidget(_FilterSettingsRow oldWidget) {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      child: Row(
        children: [
          // Position
          SizedBox(
            width: 40,
            child: Text(
              '${widget.position}',
              style: TextStyle(
                fontSize: 12,
                color: NightshadeColors.of(context).textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Name
          Expanded(
            flex: 2,
            child: Text(
              widget.filterName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: NightshadeColors.of(context).textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Focus offset
          Expanded(
            flex: 2,
            child: _buildCompactNumberInput(
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
          // AF Exposure Time
          Expanded(
            flex: 2,
            child: _buildCompactNumberInput(
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
          // AF Filter
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SettingsDropdown(
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
              ),
            ),
          ),
          // Binning
          SizedBox(
            width: 70,
            child: SettingsDropdown(
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
            ),
          ),
          // Gain
          Expanded(
            flex: 1,
            child: _buildCompactNumberInput(
              controller: _gainController,
              hint: 'def',
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
          // Offset
          Expanded(
            flex: 1,
            child: _buildCompactNumberInput(
              controller: _offsetController,
              hint: 'def',
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
    );
  }

  Widget _buildCompactNumberInput({
    required TextEditingController controller,
    String? hint,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: NightshadeColors.of(context).surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: NightshadeColors.of(context).border),
        ),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
          style: TextStyle(
            fontSize: 11,
            color: NightshadeColors.of(context).textPrimary,
          ),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 10,
              color: NightshadeColors.of(context).textMuted,
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Mobile card for per-filter AF settings (used instead of table on small screens).
