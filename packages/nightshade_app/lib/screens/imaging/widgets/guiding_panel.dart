import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/help/field_help_copy.dart';
import '../../../widgets/help/field_help_label.dart';
import 'panel_widgets.dart';

class GuidingPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const GuidingPanel({super.key, required this.colors});

  @override
  ConsumerState<GuidingPanel> createState() => _GuidingPanelState();
}

class _GuidingPanelState extends ConsumerState<GuidingPanel> {
  // UI-only transient state (doesn't need to persist)
  bool _isStartingGuiding = false;
  bool _isDithering = false;
  bool _configExpanded = false;

  Future<void> _startGuiding() async {
    setState(() => _isStartingGuiding = true);
    final ditherSettings = ref.read(ditherSettingsProvider);
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.startGuiding(
        settlePixels: ditherSettings.settlePixels,
        settleTime: ditherSettings.settleTime,
      );
      ref.read(sessionStateProvider.notifier).setGuiding(true);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to start guiding: $e');
    } finally {
      if (mounted) setState(() => _isStartingGuiding = false);
    }
  }

  Future<void> _stopGuiding() async {
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.stopGuiding();
      ref.read(sessionStateProvider.notifier).setGuiding(false);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to stop guiding: $e');
    }
  }

  Future<void> _dither() async {
    setState(() => _isDithering = true);
    ref.read(sessionStateProvider.notifier).setDithering(true);
    final ditherSettings = ref.read(ditherSettingsProvider);
    try {
      final deviceService = ref.read(deviceServiceProvider);
      await deviceService.dither(
        amount: ditherSettings.ditherAmount,
        settlePixels: ditherSettings.settlePixels,
        settleTime: ditherSettings.settleTime,
      );
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Dither failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isDithering = false);
        ref.read(sessionStateProvider.notifier).setDithering(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guiderState = ref.watch(guiderStateProvider);
    final ditherSettings = ref.watch(ditherSettingsProvider);
    final isConnected =
        guiderState.connectionState == DeviceConnectionState.connected;
    final isGuiding = guiderState.isGuiding;
    final isBuiltinGuider = ref.watch(isBuiltinGuiderProvider);

    final rmsRa = guiderState.rmsRa?.toStringAsFixed(2) ?? '---';
    final rmsDec = guiderState.rmsDec?.toStringAsFixed(2) ?? '---';
    final rmsTotal = guiderState.rmsTotal?.toStringAsFixed(2) ?? '---';

    // Per-axis PEAK guide error. These are already tracked in the rolling
    // guide stats (Phd2GuideStats.peakRa/peakDec) but, until now, only the RMS
    // tiles were surfaced. Peak is the worst single-frame excursion over the
    // window — a useful complement to RMS for spotting transient seeing spikes
    // or a flexing/bumped axis that an averaged figure would smooth away.
    final guideStats = ref.watch(guideStatsProvider);
    final peakRa = guideStats.peakRa.toStringAsFixed(2);
    final peakDec = guideStats.peakDec.toStringAsFixed(2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: NightshadeDecorations.emphasisSurface(
                widget.colors.warning,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No guider connected',
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Guiding graph with real data
          CompactGuidingGraph(
            colors: widget.colors,
            data: ref.watch(guideGraphProvider),
            isGuiding: isGuiding,
            isConnected: isConnected,
          ),
          const SizedBox(height: 16),

          // RMS Stats
          Row(
            children: [
              GuideStat(
                  label: 'RA RMS', value: '$rmsRa"', colors: widget.colors),
              GuideStat(
                  label: 'Dec RMS', value: '$rmsDec"', colors: widget.colors),
              GuideStat(
                  label: 'Total', value: '$rmsTotal"', colors: widget.colors),
            ],
          ),
          const SizedBox(height: 12),

          // Peak Stats — per-axis worst-case excursion over the rolling window.
          // The trailing spacer keeps both axes left-aligned under their RMS
          // counterparts instead of stretching across the full row.
          Row(
            children: [
              GuideStat(
                  label: 'RA Peak', value: '$peakRa"', colors: widget.colors),
              GuideStat(
                  label: 'Dec Peak', value: '$peakDec"', colors: widget.colors),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 20),

          // Tracked-star list — only the built-in multi-star guider reports a
          // per-star list (PHD2 tracks a single lock star). Reuses the same
          // guiding status path that feeds the graph above.
          if (isBuiltinGuider) ...[
            GuideStarList(colors: widget.colors),
            const SizedBox(height: 20),
          ],

          // Control Section
          PanelSection(
            title: 'Control',
            colors: widget.colors,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SmallButton(
                        label: _isStartingGuiding
                            ? 'Starting...'
                            : isGuiding
                                ? 'Guiding'
                                : 'Start',
                        icon: isGuiding
                            ? NightshadeIcons.activity
                            : NightshadeIcons.play,
                        colors: widget.colors,
                        isEnabled:
                            isConnected && !isGuiding && !_isStartingGuiding,
                        onTap: _startGuiding,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: 'Stop',
                        icon: NightshadeIcons.stop,
                        isOutline: true,
                        colors: widget.colors,
                        isEnabled: isConnected && isGuiding,
                        onTap: _stopGuiding,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SmallButton(
                    label: _isDithering ? 'Dithering...' : 'Dither',
                    icon: _isDithering
                        ? NightshadeIcons.loading
                        : LucideIcons.shuffle,
                    isOutline: true,
                    colors: widget.colors,
                    isEnabled: isConnected && isGuiding && !_isDithering,
                    onTap: _dither,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Built-in Guider Configuration (only when built-in guider is active)
          if (isBuiltinGuider) ...[
            _BuiltinGuiderConfigSection(
              colors: widget.colors,
              isExpanded: _configExpanded,
              onToggle: () =>
                  setState(() => _configExpanded = !_configExpanded),
            ),
            const SizedBox(height: 20),
          ],

          // Dithering Settings
          PanelSection(
            title: 'Dither Settings',
            colors: widget.colors,
            child: Column(
              children: [
                SliderRowInteractive(
                  label: 'Amount',
                  helpId: FieldHelpId.ditherAmount,
                  value: ditherSettings.ditherAmount,
                  min: 1,
                  max: 20,
                  suffix: 'px',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(ditherAmount: value),
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Settle Threshold',
                  helpId: FieldHelpId.settleThreshold,
                  value: ditherSettings.settlePixels,
                  min: 0.3,
                  max: 3.0,
                  suffix: '"',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(settlePixels: value),
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Settle Time',
                  helpId: FieldHelpId.settleTime,
                  value: ditherSettings.settleTime,
                  min: 5,
                  max: 30,
                  suffix: 's',
                  colors: widget.colors,
                  onChanged: (value) => ref
                      .read(ditherSettingsProvider.notifier)
                      .state = ditherSettings.copyWith(settleTime: value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible configuration panel for the built-in multi-star guider.
/// Only displayed when the built-in guider is the active guider device.
class _BuiltinGuiderConfigSection extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _BuiltinGuiderConfigSection({
    required this.colors,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(builtinGuiderConfigProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with collapse toggle
        GestureDetector(
          onTap: onToggle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? NightshadeIcons.chevronDown
                      : NightshadeIcons.chevronRight,
                  size: 14,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Guider Configuration',
                  style: NightshadeTypography.h6
                      .copyWith(color: colors.textPrimary),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: NightshadeDecorations.tintedBadge(
                    colors.primary,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                  ),
                  child: Text(
                    'Built-in',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize9,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 12),
          configAsync.when(
            loading: () => NightshadeCard(
              padding: const EdgeInsets.all(14),
              borderRadius: NightshadeTokens.radiusLg,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            error: (error, _) => Container(
              padding: const EdgeInsets.all(14),
              decoration: NightshadeDecorations.emphasisSurface(
                colors.error,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              ),
              child: Text(
                'Failed to load guider config: $error',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.error),
              ),
            ),
            data: (config) => _BuiltinGuiderConfigForm(
              colors: colors,
              config: config,
            ),
          ),
        ],
      ],
    );
  }
}

/// The actual config form with editable fields.
class _BuiltinGuiderConfigForm extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final BuiltinGuiderConfig config;

  const _BuiltinGuiderConfigForm({
    required this.colors,
    required this.config,
  });

  @override
  ConsumerState<_BuiltinGuiderConfigForm> createState() =>
      _BuiltinGuiderConfigFormState();
}

class _BuiltinGuiderConfigFormState
    extends ConsumerState<_BuiltinGuiderConfigForm> {
  late TextEditingController _exposureController;
  late TextEditingController _gainController;
  late TextEditingController _calibrationMsController;
  late TextEditingController _minPulseController;
  late TextEditingController _maxPulseController;
  late TextEditingController _settleSleepController;

  @override
  void initState() {
    super.initState();
    _exposureController =
        TextEditingController(text: widget.config.exposureSecs.toString());
    _gainController =
        TextEditingController(text: widget.config.gain.toString());
    _calibrationMsController =
        TextEditingController(text: widget.config.calibrationMs.toString());
    _minPulseController =
        TextEditingController(text: widget.config.minPulseMs.toString());
    _maxPulseController =
        TextEditingController(text: widget.config.maxPulseMs.toString());
    _settleSleepController =
        TextEditingController(text: widget.config.settleSleepMs.toString());
  }

  @override
  void didUpdateWidget(_BuiltinGuiderConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _exposureController.text = widget.config.exposureSecs.toString();
      _gainController.text = widget.config.gain.toString();
      _calibrationMsController.text = widget.config.calibrationMs.toString();
      _minPulseController.text = widget.config.minPulseMs.toString();
      _maxPulseController.text = widget.config.maxPulseMs.toString();
      _settleSleepController.text = widget.config.settleSleepMs.toString();
    }
  }

  @override
  void dispose() {
    _exposureController.dispose();
    _gainController.dispose();
    _calibrationMsController.dispose();
    _minPulseController.dispose();
    _maxPulseController.dispose();
    _settleSleepController.dispose();
    super.dispose();
  }

  /// Default pulse-guide bounds used when the connected mount does not report
  /// a min/max pulse-guide capability (or when no mount is connected).
  ///
  /// These mirror the conservative defaults the built-in guider assumes when a
  /// mount cannot describe its own pulse-guide envelope.
  static const double _defaultPulseMinMs = 75.0;
  static const double _defaultPulseMaxMs = 1200.0;

  /// Resolves the active mount's pulse-guide bounds from its reported
  /// capabilities, falling back to [_defaultPulseMinMs]/[_defaultPulseMaxMs]
  /// when the mount is absent or does not advertise the range.
  ///
  /// These bounds constrain ONLY the editor inputs — they never mutate the
  /// [BuiltinGuiderConfig], which carries the guider's real operating clamps
  /// from Rust.
  ({double min, double max}) _pulseBounds(MountCapabilities? caps) {
    final pulseMin = caps?.minPulseGuideMs ?? _defaultPulseMinMs;
    final pulseMax = caps?.maxPulseGuideMs ?? _defaultPulseMaxMs;
    return (min: pulseMin, max: pulseMax);
  }

  void _applyConfig(MountCapabilities? mountCaps) {
    final exposure = double.tryParse(_exposureController.text);
    final gain = int.tryParse(_gainController.text);
    final calibrationMs = int.tryParse(_calibrationMsController.text);
    final minPulse = double.tryParse(_minPulseController.text);
    final maxPulse = double.tryParse(_maxPulseController.text);
    final settleSleep = int.tryParse(_settleSleepController.text);

    if (exposure == null ||
        gain == null ||
        calibrationMs == null ||
        minPulse == null ||
        maxPulse == null ||
        settleSleep == null) {
      context.showErrorSnackBar('Invalid config value');
      return;
    }

    // Bound the entered pulse range to the connected mount's reported
    // pulse-guide envelope. Errors are a feature: surface and block the save
    // rather than silently clamping a value the mount cannot honor.
    final bounds = _pulseBounds(mountCaps);
    if (minPulse < bounds.min) {
      context.showErrorSnackBar(
        'Min pulse ${minPulse.toStringAsFixed(0)} ms is below the mount '
        'minimum of ${bounds.min.toStringAsFixed(0)} ms',
      );
      return;
    }
    if (maxPulse > bounds.max) {
      context.showErrorSnackBar(
        'Max pulse ${maxPulse.toStringAsFixed(0)} ms exceeds the mount '
        'maximum of ${bounds.max.toStringAsFixed(0)} ms',
      );
      return;
    }
    if (minPulse > maxPulse) {
      context.showErrorSnackBar(
        'Min pulse ${minPulse.toStringAsFixed(0)} ms cannot exceed max pulse '
        '${maxPulse.toStringAsFixed(0)} ms',
      );
      return;
    }

    final newConfig = widget.config.copyWith(
      exposureSecs: exposure,
      gain: gain,
      calibrationMs: calibrationMs,
      minPulseMs: minPulse,
      maxPulseMs: maxPulse,
      settleSleepMs: settleSleep,
    );

    ref.read(builtinGuiderConfigProvider.notifier).updateConfig(newConfig);
  }

  void _resetDefaults() {
    ref.read(builtinGuiderConfigProvider.notifier).resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the connected mount's pulse-guide capability envelope. When no
    // mount is connected (or it reports no device id), capabilities resolve to
    // null and the conservative built-in defaults apply.
    final mountState = ref.watch(mountStateProvider);
    final mountDeviceId =
        mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : null;
    final MountCapabilities? mountCaps =
        (mountDeviceId != null && mountDeviceId.isNotEmpty)
            ? ref.watch(mountCapabilitiesProvider(mountDeviceId)).valueOrNull
            : null;
    final pulseBounds = _pulseBounds(mountCaps);

    // Helper hint shown on the pulse fields only when the mount actually
    // reports a range (honest-None: don't fabricate a range from defaults).
    final String? pulseRangeHint =
        mountCaps?.minPulseGuideMs != null && mountCaps?.maxPulseGuideMs != null
            ? 'Mount supports ${pulseBounds.min.toStringAsFixed(0)}-'
                '${pulseBounds.max.toStringAsFixed(0)} ms'
            : null;

    return NightshadeCard(
      padding: const EdgeInsets.all(14),
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ConfigInputRow(
            label: 'Exposure',
            controller: _exposureController,
            suffix: 's',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Gain',
            controller: _gainController,
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Cal. Pulse',
            controller: _calibrationMsController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Min Pulse',
            controller: _minPulseController,
            suffix: 'ms',
            helperText: pulseRangeHint,
            helpId: FieldHelpId.guideMinPulse,
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Max Pulse',
            controller: _maxPulseController,
            suffix: 'ms',
            helperText: pulseRangeHint,
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Settle Sleep',
            controller: _settleSleepController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(mountCaps),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SmallButton(
                  label: 'Apply',
                  icon: NightshadeIcons.check,
                  colors: widget.colors,
                  onTap: () => _applyConfig(mountCaps),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmallButton(
                  label: 'Reset Defaults',
                  icon: NightshadeIcons.undo,
                  isOutline: true,
                  colors: widget.colors,
                  onTap: _resetDefaults,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single config input row with label, text field, and optional suffix.
class _ConfigInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? suffix;

  /// Optional helper hint rendered beneath the input (e.g. the supported
  /// pulse-guide range reported by the connected mount).
  final String? helperText;

  /// Optional field-level help. When supplied, a [helpAffordance] icon hugs the
  /// label text showing the rich tooltip from [helpFor]. Used for genuinely
  /// non-obvious built-in-guider parameters (e.g. the millisecond min-pulse).
  final FieldHelpId? helpId;
  final NightshadeColors colors;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _ConfigInputRow({
    required this.label,
    required this.controller,
    this.suffix,
    this.helperText,
    this.helpId,
    required this.colors,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: NightshadeTypography.fontSize12,
      color: colors.textSecondary,
    );
    final id = helpId;
    final Widget labelWidget = id == null
        ? Text(label, style: labelStyle)
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: Text(label, style: labelStyle)),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Builder(
                builder: (context) {
                  final copy = helpFor(id);
                  return helpAffordance(
                    context,
                    title: copy.title,
                    body: copy.body,
                  );
                },
              ),
            ],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: labelWidget,
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: TextField(
                  controller: controller,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                    isDense: true,
                    suffixText: suffix,
                    suffixStyle: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: colors.textMuted,
                    ),
                  ),
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onSubmitted: onSubmitted,
                ),
              ),
              if (helperText != null) ...[
                const SizedBox(height: 4),
                Text(
                  helperText!,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact guiding graph widget for the imaging screen overview panel.
/// Displays real RA/Dec error data from guideGraphProvider, or a
/// empty-state message when no guide data is available.
class CompactGuidingGraph extends StatelessWidget {
  final NightshadeColors colors;
  final List<GuideGraphPoint> data;
  final bool isGuiding;
  final bool isConnected;

  const CompactGuidingGraph({
    super.key,
    required this.colors,
    required this.data,
    required this.isGuiding,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = data.isNotEmpty;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          // Draw the real graph when we have data
          if (hasData)
            Positioned.fill(
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline9),
                child: CustomPaint(
                  painter: _CompactGuidingGraphPainter(
                    data: data,
                    colors: colors,
                  ),
                ),
              ),
            ),
          // Show empty state when no data
          if (!hasData)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGuiding
                        ? NightshadeIcons.activity
                        : NightshadeIcons.crosshair,
                    size: 24,
                    color: isGuiding ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isGuiding
                        ? 'Waiting for guide data...'
                        : isConnected
                            ? 'Ready to guide'
                            : 'No guide data',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: isGuiding ? colors.success : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          // Legend (always visible)
          Positioned(
            bottom: 8,
            left: 8,
            child: Row(
              children: [
                Container(
                    width: 12,
                    height: 2,
                    color: NightshadeChartColors.seriesRed),
                const SizedBox(width: 4),
                Text('RA',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize9,
                        color: colors.textMuted)),
                const SizedBox(width: 12),
                Container(
                    width: 12,
                    height: 2,
                    color: NightshadeChartColors.seriesBlue),
                const SizedBox(width: 4),
                Text('Dec',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize9,
                        color: colors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders real RA/Dec guide error data.
/// Matches the rendering approach from the guiding_tab.dart _GraphPainter
/// but is simplified for the compact 120px overview panel.
class _CompactGuidingGraphPainter extends CustomPainter {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;

  _CompactGuidingGraphPainter({
    required this.data,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // Draw center zero-line
    final zeroPaint = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), zeroPaint);

    if (data.isEmpty) return;

    final raPaint = Paint()
      ..color = NightshadeChartColors.seriesRed.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final decPaint = Paint()
      ..color = NightshadeChartColors.seriesBlue.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Scale: +/- 4 arcsec range (same as the full guiding graph)
    const range = 4.0;
    final scaleY = size.height / (range * 2);
    // Show last 100 points spread across the width
    final stepX = size.width / 100;

    final raPath = Path();
    final decPath = Path();

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final x = size.width - ((data.length - 1 - i) * stepX);

      if (x < 0) continue;

      final raY = centerY - (point.ra.clamp(-range, range) * scaleY);
      final decY = centerY - (point.dec.clamp(-range, range) * scaleY);

      if (i == 0 || x < stepX) {
        raPath.moveTo(x, raY);
        decPath.moveTo(x, decY);
      } else {
        raPath.lineTo(x, raY);
        decPath.lineTo(x, decY);
      }
    }

    canvas.drawPath(raPath, raPaint);
    canvas.drawPath(decPath, decPaint);
  }

  @override
  bool shouldRepaint(covariant _CompactGuidingGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

/// Per-star tracked-star list for the built-in multi-star guider.
///
/// The internal guider tracks up to 8 reference stars; this surfaces each
/// star's SNR, lock highlight, and per-star residual so the panel is no longer
/// empty when the built-in guider is active. Driven by [guideStarsProvider],
/// which rides the same guiding status path that feeds [CompactGuidingGraph]
/// above. Renders an honest empty-state (not an error) when no stars are
/// tracked yet — e.g. before looping starts.
class GuideStarList extends ConsumerWidget {
  final NightshadeColors colors;

  const GuideStarList({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stars = ref.watch(guideStarsProvider);

    return PanelSection(
      title: 'Tracked Stars (${stars.length})',
      colors: colors,
      child: stars.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(NightshadeIcons.star, size: 14, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No stars tracked yet',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Column header.
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 3,
                        child: Text('Star', style: _headerStyle(colors)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('SNR',
                            textAlign: TextAlign.end,
                            style: _headerStyle(colors)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('Resid',
                            textAlign: TextAlign.end,
                            style: _headerStyle(colors)),
                      ),
                    ],
                  ),
                ),
                for (final star in stars)
                  _GuideStarRow(star: star, colors: colors),
              ],
            ),
    );
  }

  static TextStyle _headerStyle(NightshadeColors colors) => TextStyle(
        fontSize: NightshadeTypography.fontSize9,
        fontWeight: FontWeight.w600,
        color: colors.textMuted,
      );
}

class _GuideStarRow extends StatelessWidget {
  final GuideStar star;
  final NightshadeColors colors;

  const _GuideStarRow({required this.star, required this.colors});

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: NightshadeTypography.fontSize11,
      color: colors.textPrimary,
    );
    final residual = star.residual;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Lock indicator: the active lock star gets a filled accent dot, the
          // rest a hollow muted marker so the lock star reads at a glance.
          SizedBox(
            width: 18,
            child: Icon(
              star.isLock ? NightshadeIcons.crosshair : LucideIcons.circle,
              size: 12,
              color: star.isLock ? colors.primary : colors.textMuted,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              star.isLock
                  ? 'Star ${star.id + 1} (lock)'
                  : 'Star ${star.id + 1}',
              style: valueStyle.copyWith(
                color: star.isLock ? colors.primary : colors.textPrimary,
                fontWeight: star.isLock ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              star.snr.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: valueStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              residual == null ? '—' : '${residual.toStringAsFixed(2)}px',
              textAlign: TextAlign.end,
              style: valueStyle.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class GuideStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const GuideStat({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
