import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../imaging/widgets/osc_stacking_controls.dart';

/// Launcher dialog for the **Stack-and-Share Loop** (component C9).
///
/// Summarises the lights selected for [sessionId] (target, per-filter frame
/// counts, total integration, frame count), lets the operator tune the run
/// (calibration, auto-stretch, quality gate), and drives
/// [stackAndShareProvider] end-to-end. While the run is in flight it renders a
/// live [NightshadeProgressBar] with the current phase and frame counters. On
/// success it auto-pops and navigates to the result viewer
/// (`/stack-result?id=<resultId>`); on failure it surfaces the error inline as a
/// [NightshadeAlert] (errors are a feature — never silently swallowed).
///
/// Show it with [StackAndShareDialog.show], which wires the dialog into a
/// [NightshadeDialog] scaffold via `showDialog`.
class StackAndShareDialog extends ConsumerStatefulWidget {
  /// Imaging session whose lights are stacked.
  final int sessionId;

  /// Pre-computed selection summary for [sessionId], used to render the summary
  /// well (target, per-filter counts, integration, frame count) before the run
  /// starts. The orchestrator re-selects internally; this is purely the
  /// human-facing preview the operator confirms.
  final StackSelectionSummary selection;

  const StackAndShareDialog({
    super.key,
    required this.sessionId,
    required this.selection,
  });

  /// Show the Stack-and-Share launcher for [sessionId] with its [selection]
  /// preview. Resolves when the dialog is dismissed.
  static Future<void> show(
    BuildContext context, {
    required int sessionId,
    required StackSelectionSummary selection,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StackAndShareDialog(
        sessionId: sessionId,
        selection: selection,
      ),
    );
  }

  @override
  ConsumerState<StackAndShareDialog> createState() =>
      _StackAndShareDialogState();
}

class _StackAndShareDialogState extends ConsumerState<StackAndShareDialog> {
  late bool _applyCalibration;
  late bool _autoStretch;
  late final TextEditingController _qualityController;

  /// Sensor acquisition mode for the run: `'auto'`, `'mono'`, or `'osc'`.
  /// Folded into [StackAndShareConfig.sensorMode] by [_buildConfig].
  late String _sensorMode;

  /// Bayer-pattern override dropdown value ([oscBayerAutoValue] → no override),
  /// folded into [StackAndShareConfig.bayerPatternOverride].
  late String _bayerPattern;

  /// Demosaic-quality dropdown value, folded into
  /// [StackAndShareConfig.demosaicQuality].
  late String _demosaicQuality;

  /// Whether the manual OSC override controls are expanded. Only relevant when
  /// a colour camera is auto-detected (otherwise the controls are always shown).
  bool _oscOverrideExpanded = false;

  /// Parse error for the quality field, surfaced inline. Null when the field
  /// holds a valid (or empty → "no gate") value.
  String? _qualityError;

  /// Guards against double-navigation if the provider emits `complete` more than
  /// once (e.g. a rebuild after the post-frame callback is already scheduled).
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    const defaults = StackAndShareConfig.defaults;
    _applyCalibration = defaults.applyCalibration;
    _autoStretch = defaults.autoStretch;
    _sensorMode = defaults.sensorMode;
    _bayerPattern =
        defaults.bayerPatternOverride?.toUpperCase() ?? oscBayerAutoValue;
    _demosaicQuality = defaults.demosaicQuality.toLowerCase();
    _qualityController = TextEditingController(
      text: defaults.minQualityScore > 0
          ? _trimNum(defaults.minQualityScore)
          : '',
    );
  }

  @override
  void dispose() {
    _qualityController.dispose();
    super.dispose();
  }

  /// Parse the quality field. An empty field means "no quality gate" (`0`); a
  /// non-numeric or negative value is a hard input error we surface rather than
  /// silently coercing to a default.
  double? _parseQuality() {
    final text = _qualityController.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (value == null) {
      setState(
          () => _qualityError = 'Enter a number (or leave blank for none)');
      return null;
    }
    if (value < 0) {
      setState(() => _qualityError = 'Quality threshold cannot be negative');
      return null;
    }
    if (_qualityError != null) {
      setState(() => _qualityError = null);
    }
    return value;
  }

  StackAndShareConfig _buildConfig(double quality) {
    // The Auto sentinel means "no override" — let the engine resolve the
    // pattern from the reference frame's FITS BAYERPAT geometry. Because the
    // model's copyWith treats a null `bayerPatternOverride` as "leave unchanged"
    // (not "clear"), the Auto case is expressed by constructing directly with
    // null rather than copying.
    final override = _bayerPattern == oscBayerAutoValue ? null : _bayerPattern;
    return StackAndShareConfig(
      applyCalibration: _applyCalibration,
      autoStretch: _autoStretch,
      minQualityScore: quality,
      sensorMode: _sensorMode,
      bayerPatternOverride: override,
      demosaicQuality: _demosaicQuality,
    );
  }

  /// The detected Bayer pattern of the currently connected colour camera
  /// (upper-cased, e.g. `'RGGB'`), or null when no colour camera is connected /
  /// the query is in flight / the driver reported no pattern.
  ///
  /// Drives the auto-detected read-only summary in the OSC options. A null
  /// result means "no live OSC hint" — the manual controls are shown directly
  /// rather than a guessed pattern (errors/uncertainty surface, never a
  /// silent colour assumption).
  String? _detectedOscPattern() {
    final deviceId = ref.watch(connectedCameraIdProvider);
    if (deviceId == null || deviceId.isEmpty) return null;
    final caps = ref.watch(equipmentCameraCapabilitiesProvider(deviceId));
    final value = caps.maybeWhen(
      data: (c) => c,
      orElse: () => null,
    );
    if (value == null || !value.isColor) return null;
    final raw = value.bayerPattern?.trim().toUpperCase();
    if (raw == null || raw.isEmpty) return null;
    return oscBayerPatternValues.contains(raw) ? raw : null;
  }

  Future<void> _start() async {
    final quality = _parseQuality();
    if (quality == null) return; // Inline error already surfaced.

    final config = _buildConfig(quality);
    // Fire-and-forget: the notifier owns failure presentation and never
    // rethrows, so the dialog just listens to state transitions below.
    await ref
        .read(stackAndShareProvider.notifier)
        .runForSession(widget.sessionId, config: config);
  }

  void _onComplete(StackAndShareResult result) {
    if (_navigated) return;
    final id = result.id;
    if (id == null) {
      // A completed run without a persisted id cannot be opened in the viewer.
      // Rather than navigate to a broken route, surface it: the notifier marks
      // the run complete only after the DAO insert, so a null id here is a real
      // invariant break worth showing.
      return;
    }
    _navigated = true;
    // Defer navigation/pop out of the build/listener frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/stack-result?id=$id');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stackAndShareProvider);

    // Navigate to the result viewer as soon as a run completes successfully.
    ref.listen<StackAndShareState>(stackAndShareProvider, (prev, next) {
      if (next.isComplete && next.result != null) {
        _onComplete(next.result!);
      }
    });

    final running = state.isRunning;

    return NightshadeDialog(
      title: 'Stack & Share',
      icon: NightshadeIcons.layers,
      width: 600,
      // Block the close button while a run is active so we never tear the
      // dialog down mid-pipeline.
      showCloseButton: !running,
      actions: [
        NightshadeButton(
          label: 'Close',
          variant: ButtonVariant.ghost,
          onPressed: running ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: running ? 'Stacking…' : 'Start',
          icon: NightshadeIcons.play,
          isLoading: running,
          onPressed: running ? null : _start,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectionSummary(selection: widget.selection),
          if (state.errorMessage != null) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            _buildError(context, state.errorMessage!),
          ],
          const SizedBox(height: NightshadeTokens.spaceLg),
          _buildOptions(running),
          if (running) ...[
            const SizedBox(height: NightshadeTokens.spaceXl),
            _RunProgress(progress: state.progress),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    // The orchestrator surfaces the raw exception string. When it is a
    // live-stacking conflict, give the operator the concrete next step.
    final isBusy = message.contains('LiveStackBusyException') ||
        message.contains('Stop live stacking');
    if (isBusy) {
      return NightshadeAlert(
        severity: NightshadeAlertSeverity.error,
        title: 'Live stacking is active',
        message: 'The stacking engine is busy with a live session. Stop live '
            'stacking before running Stack & Share.',
        action: NightshadeButton(
          label: 'Stop live stacking',
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          icon: NightshadeIcons.stopCircle,
          onPressed: _stopLiveStacking,
        ),
      );
    }
    return NightshadeAlert(
      severity: NightshadeAlertSeverity.error,
      title: 'Stack & Share failed',
      message: message,
    );
  }

  Future<void> _stopLiveStacking() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(liveStackingProvider.notifier).stop();
      if (!mounted) return;
      // Clear the prior error so the user can immediately retry.
      ref.read(stackAndShareProvider.notifier).reset();
    } catch (e) {
      if (!mounted) return;
      // Surface the stop failure rather than leaving the user stuck.
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not stop live stacking: $e')),
      );
    }
  }

  Widget _buildOptions(bool running) {
    return SectionWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionHeader(title: 'Options'),
          const SizedBox(height: NightshadeTokens.spaceSm),
          NightshadeSwitchRow(
            label: 'Apply calibration',
            subtitle: 'Subtract matched dark / flat / bias before stacking',
            value: _applyCalibration,
            onChanged:
                running ? null : (v) => setState(() => _applyCalibration = v),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeSwitchRow(
            label: 'Auto-stretch',
            subtitle:
                'Apply the screen-transfer (STF) stretch to the integrated '
                'result for display and export',
            value: _autoStretch,
            onChanged: running ? null : (v) => setState(() => _autoStretch = v),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _buildOscOptions(running),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _buildQualityField(running),
        ],
      ),
    );
  }

  /// The OSC / colour options.
  ///
  /// When a live colour camera is detected, the section leads with a read-only
  /// "Auto-detected" summary (so the common case needs no interaction) and
  /// tucks the manual override controls behind an expansion. With no live
  /// colour hint the controls are shown directly.
  Widget _buildOscOptions(bool running) {
    final colors = context.nightshadeColors;
    final detected = _detectedOscPattern();
    final oscEnabled = _sensorMode.toLowerCase() != 'mono';

    final toggle = NightshadeSwitchRow(
      label: 'OSC / Color',
      subtitle: 'Demosaic Bayer frames to RGB',
      value: oscEnabled,
      onChanged: running
          ? null
          : (v) => setState(() => _sensorMode = v ? 'auto' : 'mono'),
    );

    if (!oscEnabled) {
      return toggle;
    }

    final manualControls = <Widget>[
      OscDropdownField(
        label: 'Bayer pattern',
        value: _bayerPattern,
        items: oscBayerPatternValues,
        itemLabels: oscBayerPatternValues
            .map((v) => oscBayerPatternLabel(v, detected))
            .toList(growable: false),
        enabled: !running,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _bayerPattern = v);
        },
      ),
      const SizedBox(height: NightshadeTokens.spaceMd),
      OscDropdownField(
        label: 'Demosaic quality',
        value: _demosaicQuality,
        items: oscDemosaicQualityValues,
        itemLabels: oscDemosaicQualityValues
            .map((v) => oscDemosaicQualityLabels[v] ?? v)
            .toList(growable: false),
        enabled: !running,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _demosaicQuality = v);
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        toggle,
        const SizedBox(height: NightshadeTokens.spaceMd),
        if (detected != null) ...[
          // Live colour camera detected: surface the auto-detection read-only,
          // with the manual override behind an expander.
          NightshadeInlineBanner(
            severity: NightshadeAlertSeverity.info,
            message: 'Auto-detected: OSC $detected',
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _OverrideDisclosure(
            expanded: _oscOverrideExpanded,
            colors: colors,
            onToggle: running
                ? null
                : () => setState(
                    () => _oscOverrideExpanded = !_oscOverrideExpanded),
          ),
          if (_oscOverrideExpanded) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            ...manualControls,
          ],
        ] else
          ...manualControls,
      ],
    );
  }

  Widget _buildQualityField(bool running) {
    return NightshadeTextField(
      label: 'Quality threshold',
      hint: 'e.g. 0.5 (blank = no gate)',
      controller: _qualityController,
      enabled: !running,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      errorText: _qualityError,
      onChanged: (_) {
        if (_qualityError != null) {
          setState(() => _qualityError = null);
        }
      },
    );
  }
}

/// The selection-summary well: target name, per-filter pill rows, total
/// integration, and frame count.
class _SelectionSummary extends StatelessWidget {
  final StackSelectionSummary selection;

  const _SelectionSummary({required this.selection});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final filterEntries = selection.perFilterCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SectionWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selection.targetName ?? 'Stacked result',
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (filterEntries.isNotEmpty) ...[
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: NightshadeTokens.spaceSm,
              children: [
                for (final e in filterEntries)
                  StatusPill(
                    icon: NightshadeIcons.filter,
                    label: e.key,
                    value: '${e.value}',
                    status: StatusPillStatus.active,
                  ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
          ],
          Row(
            children: [
              Expanded(
                child: _MetricColumn(
                  label: 'Integration',
                  value: formatHms(selection.totalIntegrationSecs),
                ),
              ),
              Expanded(
                child: _MetricColumn(
                  label: 'Frames',
                  value: '${selection.selectedCount}',
                ),
              ),
            ],
          ),
          if (selection.excludedCount > 0) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              '${selection.excludedCount} frame'
              '${selection.excludedCount == 1 ? '' : 's'} excluded by quality / '
              'filter gates',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label-over-value metric using tabular telemetry type for the value.
class _MetricColumn extends StatelessWidget {
  final String label;
  final String value;

  const _MetricColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: NightshadeTypography.labelSm.copyWith(
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          value,
          style: NightshadeTypography.telemetryMd.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Live progress display while a run is in flight: a bar bound to
/// [StackAndShareProgress.fraction], the current phase label, and the
/// `frame X/Y, Z rejected` counter.
class _RunProgress extends StatelessWidget {
  final StackAndShareProgress progress;

  const _RunProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _phaseLabel(progress.phase),
                style: NightshadeTypography.telemetryMd.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Text(
              '${(progress.fraction * 100).round()}%',
              style: NightshadeTypography.monoSm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeProgressBar(value: progress.fraction),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          'frame ${progress.framesProcessed}/${progress.framesTotal}, '
          '${progress.framesRejected} rejected',
          style: NightshadeTypography.monoSm.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  static String _phaseLabel(StackAndSharePhase phase) {
    return switch (phase) {
      StackAndSharePhase.idle => 'Idle',
      StackAndSharePhase.selectingLights => 'Selecting lights…',
      StackAndSharePhase.calibrating => 'Calibrating…',
      StackAndSharePhase.stacking => 'Stacking…',
      StackAndSharePhase.stretching => 'Stretching…',
      StackAndSharePhase.exporting => 'Exporting…',
      StackAndSharePhase.complete => 'Complete',
      StackAndSharePhase.error => 'Failed',
    };
  }
}

/// Formats a number without a trailing `.0` for whole values, otherwise with a
/// single decimal place (mirrors the model helper, kept private to the UI).
String _trimNum(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

/// The "Override auto-detection" disclosure row that expands the manual OSC
/// controls when a colour camera was auto-detected.
class _OverrideDisclosure extends StatelessWidget {
  final bool expanded;
  final NightshadeColors colors;
  final VoidCallback? onToggle;

  const _OverrideDisclosure({
    required this.expanded,
    required this.colors,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onToggle != null;
    final tint = enabled ? colors.primary : colors.textMuted;
    return InkWell(
      onTap: onToggle,
      borderRadius: NightshadeTokens.borderRadiusSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: NightshadeTokens.spaceXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded
                  ? NightshadeIcons.chevronDown
                  : NightshadeIcons.chevronRight,
              size: NightshadeTokens.iconSm,
              color: tint,
            ),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              'Override auto-detection',
              style: NightshadeTypography.label.copyWith(color: tint),
            ),
          ],
        ),
      ),
    );
  }
}
