part of '../flat_wizard_screen.dart';

class _HistogramTargetSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// Effective, capability-resolved camera config. The target is shown as an
  /// absolute ADU against the DETECTED full scale (e.g. 4095 for a 12-bit
  /// camera) so the operator never targets an impossible level.
  final FlatCaptureConfig config;

  const _HistogramTargetSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final targetAdu = config.targetAduFor(value).round();
    final depthLabel =
        config.bitDepth != null ? ' · ${config.bitDepth}-bit' : '';
    // "of the detected range": target ADU shown against the effective full
    // scale, so the percentage's real meaning is explicit for any bit depth.
    final aduLabel = '~$targetAdu / ${config.maxAdu} ADU$depthLabel';

    return Column(
      children: [
        Row(
          children: [
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize24,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                aduLabel,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
          ),
          child: Slider(
            value: value,
            min: 10,
            max: 90,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// The gain / offset / binning the wizard will actually command, plus an
/// explicit warning when they disagree with the light-frame settings.
///
/// The flat wizard resolves its capture config from the equipment profile and
/// the camera's live values (`FlatWizardService.resolveCaptureConfig`), while
/// light frames use the app-settings exposure defaults. When those two sources
/// disagree the flats carry a different bias pedestal from the lights and the
/// library matcher rejects them outright (`flat_library_dao.dart`: "gain,
/// offset, and binning must match exactly"). The wizard used to show none of
/// these numbers, so the divergence was silent all the way to a rejected
/// calibration library.
class _CaptureConfigSummary extends ConsumerWidget {
  const _CaptureConfigSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final config = ref.watch(flatCameraConfigProvider);
    final lights = ref.watch(exposureSettingsProvider);

    final parts = <String>[
      config.canSetGain
          ? 'Gain ${config.gain?.toString() ?? 'driver default'}'
          : 'Gain n/a',
      config.canSetOffset
          ? 'Offset ${config.offset?.toString() ?? 'driver default'}'
          : 'Offset n/a',
      'Bin ${config.binX}×${config.binY}',
    ];

    final mismatches = <String>[
      if (config.canSetGain &&
          config.gain != null &&
          config.gain != lights.gain)
        'gain ${config.gain} vs ${lights.gain}',
      if (config.canSetOffset &&
          config.offset != null &&
          config.offset != lights.offset)
        'offset ${config.offset} vs ${lights.offset}',
      if (config.binX != lights.binningX || config.binY != lights.binningY)
        'binning ${config.binX}×${config.binY} vs '
            '${lights.binningX}×${lights.binningY}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join('  ·  '),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            color: colors.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
        if (mismatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: NightshadeTokens.borderRadiusInline8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(NightshadeIcons.warning, size: 14, color: colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These flats will not match your light frames '
                    '(${mismatches.join(', ')}). Flats are only usable with '
                    'lights taken at the same gain, offset and binning.',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.warning,
                    ),
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

/// A caption for one control inside a multi-control group.
///
/// Quick Capture gives Histogram Target and Tolerance a `_SectionHeader` each,
/// but the Multi-Filter Batch and Sky Flats tabs stack the same two sliders
/// under one "Global Settings" heading — where they rendered as a bare "11%"
/// above a bare "±10%", with nothing saying which was the target and which the
/// tolerance.
class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: NightshadeTypography.label.copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _ToleranceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ToleranceSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Text(
          '±${value.toStringAsFixed(0)}%',
          style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.surfaceAlt,
              thumbColor: colors.primary,
            ),
            child: Slider(
              value: value,
              min: 1,
              max: 25,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable frame count with stepper controls for small adjustments.
class _FrameCountInput extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _FrameCountInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The range `FlatWizardNotifier.setFrameCount` clamps to. Mirrored here so a
  /// typed value is corrected in the field the user is looking at rather than
  /// silently snapping somewhere else.
  static const int minFrames = 1;
  static const int maxFrames = 999;

  @override
  State<_FrameCountInput> createState() => _FrameCountInputState();
}

class _FrameCountInputState extends State<_FrameCountInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _FrameCountInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never overwrite what the user is mid-way through typing; the steppers and
    // the persisted settings still push their value in when the field is idle.
    if (_focusNode.hasFocus) return;
    if (widget.value != oldWidget.value ||
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  /// Apply the typed text, then normalise the field to whatever survived
  /// clamping — a blank or out-of-range entry snaps back visibly instead of
  /// leaving the field disagreeing with the run it will start.
  void _commit() {
    final typed = int.tryParse(_controller.text.trim());
    final resolved = typed == null
        ? widget.value
        : typed.clamp(_FrameCountInput.minFrames, _FrameCountInput.maxFrames);
    if (resolved != widget.value) widget.onChanged(resolved);
    if (_controller.text != '$resolved') _controller.text = '$resolved';
  }

  void _step(int delta) {
    final next = (widget.value + delta)
        .clamp(_FrameCountInput.minFrames, _FrameCountInput.maxFrames);
    if (next == widget.value) return;
    _controller.text = '$next';
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Keep ≥48px touch targets but let the label flex so the stepper fits a
    // narrow phone controls column without overflowing.
    return Row(
      children: [
        Flexible(
          child: Text(
            'Frames:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'One fewer frame',
          onPressed: widget.value > _FrameCountInput.minFrames
              ? () => _step(-1)
              : null,
          icon: const Icon(LucideIcons.minus, size: 18),
          color: colors.textSecondary,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        SizedBox(
          width: 62,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            onSubmitted: (_) => _commit(),
            // Flutter's default only drops focus on a tap outside on DESKTOP:
            // `_EditableTextTapOutsideAction` deliberately ignores a touch on
            // Android/iOS so a mobile keyboard stays up. That default is wrong
            // for a numeric field the operator types into and then reaches
            // straight for "Start Capture": the tap would never unfocus, the
            // commit would never fire, and the run would use the old count
            // while the field on screen showed the new one. Drop focus on every
            // platform so what the field says is what the run gets.
            onTapOutside: (_) {
              if (_focusNode.hasFocus) _focusNode.unfocus();
            },
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surfaceAlt,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'One more frame',
          onPressed:
              widget.value < _FrameCountInput.maxFrames ? () => _step(1) : null,
          icon: const Icon(LucideIcons.plus, size: 18),
          color: colors.textSecondary,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }
}

class _TwilightModeSelector extends StatelessWidget {
  final TwilightMode mode;
  final ValueChanged<TwilightMode> onChanged;

  const _TwilightModeSelector({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunrise,
            label: 'Dawn',
            description: 'Brightening sky',
            isSelected: mode == TwilightMode.dawn,
            onTap: () => onChanged(TwilightMode.dawn),
            colors: colors,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TwilightOption(
            icon: LucideIcons.sunset,
            label: 'Dusk',
            description: 'Darkening sky',
            isSelected: mode == TwilightMode.dusk,
            onTap: () => onChanged(TwilightMode.dusk),
            colors: colors,
          ),
        ),
      ],
    );
  }
}

class _TwilightOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _TwilightOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: NightshadeTypography.h5.copyWith(
                  color: isSelected ? colors.primary : colors.textPrimary),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
