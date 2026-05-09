import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/snackbar_helper.dart';
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
              decoration: BoxDecoration(
                color: widget.colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No guider connected',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
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
          const SizedBox(height: 20),

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
                        icon:
                            isGuiding ? LucideIcons.activity : LucideIcons.play,
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
                        icon: LucideIcons.square,
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
                        ? LucideIcons.loader2
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
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  size: 14,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Guider Configuration',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Built-in',
                    style: TextStyle(
                      fontSize: 9,
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
            loading: () => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
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
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Failed to load guider config: $error',
                style: TextStyle(fontSize: 11, color: colors.error),
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

  void _applyConfig() {
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ConfigInputRow(
            label: 'Exposure',
            controller: _exposureController,
            suffix: 's',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Gain',
            controller: _gainController,
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Cal. Pulse',
            controller: _calibrationMsController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Min Pulse',
            controller: _minPulseController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Max Pulse',
            controller: _maxPulseController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _ConfigInputRow(
            label: 'Settle Sleep',
            controller: _settleSleepController,
            suffix: 'ms',
            colors: widget.colors,
            onSubmitted: (_) => _applyConfig(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SmallButton(
                  label: 'Apply',
                  icon: LucideIcons.check,
                  colors: widget.colors,
                  onTap: _applyConfig,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmallButton(
                  label: 'Reset Defaults',
                  icon: LucideIcons.rotateCcw,
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
  final NightshadeColors colors;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _ConfigInputRow({
    required this.label,
    required this.controller,
    this.suffix,
    required this.colors,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onSubmitted: onSubmitted,
            ),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          // Draw the real graph when we have data
          if (hasData)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
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
                    isGuiding ? LucideIcons.activity : LucideIcons.crosshair,
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
                      fontSize: 11,
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
                Container(width: 12, height: 2, color: Colors.redAccent),
                const SizedBox(width: 4),
                Text('RA',
                    style: TextStyle(fontSize: 9, color: colors.textMuted)),
                const SizedBox(width: 12),
                Container(width: 12, height: 2, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text('Dec',
                    style: TextStyle(fontSize: 9, color: colors.textMuted)),
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
      ..color = Colors.redAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final decPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.8)
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
