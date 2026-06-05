import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
// The selector provider is not re-exported through the core barrel; the
// Stack-and-Share entry point needs it directly to pre-compute the selection
// summary the launcher dialog (C9) renders before a run starts. (Matches the
// established precedent in screens/framing/widgets/framing_canvas.dart.)
// ignore: implementation_imports
import 'package:nightshade_core/src/services/stack_light_selector.dart'
    show stackLightSelectorProvider, NoLightsToStackException;
import '../../stack_result/stack_and_share_dialog.dart';
import 'osc_stacking_controls.dart';
import 'panel_widgets.dart';

part 'stacking_panel/stack_and_share_entry.dart';
part 'stacking_panel/status_widgets.dart';
part 'stacking_panel/stacked_preview.dart';
part 'stacking_panel/osc_stacking_section.dart';

class StackingPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const StackingPanel({super.key, required this.colors});

  @override
  ConsumerState<StackingPanel> createState() => _StackingPanelState();
}

class _StackingPanelState extends ConsumerState<StackingPanel> {
  bool _isStarting = false;
  bool _isStopping = false;

  /// Whether the OSC config has already been seeded from the connected camera's
  /// capabilities. Guards the one-time camera-aware defaulting so a user who
  /// turns the colour switch back OFF is not overridden on the next rebuild.
  bool _oscDefaultsSeeded = false;

  /// Seed the OSC config once from a connected colour camera.
  ///
  /// When the camera reports a Bayer CFA and the colour config is still at its
  /// pristine mono default (the user has not touched it), default the colour
  /// mode to `auto` and preselect the camera's detected pattern. Runs at most
  /// once per panel lifetime and only while live stacking is idle (so it never
  /// rewrites the config of a session already in flight). The state mutation is
  /// deferred out of the build phase via a post-frame callback.
  void _maybeSeedOscDefaultsFromCamera(LiveStackingConfig config) {
    if (_oscDefaultsSeeded) return;

    // Only seed a pristine config: respect any explicit user choice.
    final isPristine = config.sensorMode.toLowerCase() == 'mono' &&
        config.bayerPattern == null;
    if (!isPristine) {
      _oscDefaultsSeeded = true;
      return;
    }

    if (ref.read(liveStackingProvider).status == LiveStackingStatus.running) {
      return; // Defer until the in-flight session ends.
    }

    final caps = _connectedCameraCapabilities();
    if (caps == null) {
      return; // No camera-derived hint yet; try again next build.
    }
    if (!caps.isColor) {
      // A mono camera is a definitive "no colour default" signal — stop trying.
      _oscDefaultsSeeded = true;
      return;
    }

    // Enable the colour path in `auto` mode and leave the Bayer override unset:
    // `auto` honours the pattern the reference frame declares via its FITS
    // BAYERPAT geometry (which the camera's reported pattern should agree with),
    // and the Bayer dropdown's Auto entry surfaces the detected pattern in its
    // label. Pinning an explicit override here would silently override the
    // frame's own geometry — the operator can still do so manually.
    _oscDefaultsSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Re-check the live config: if the user toggled something between the
      // build and this callback, do not clobber their choice.
      final current = ref.read(liveStackingProvider).config;
      if (current.sensorMode.toLowerCase() != 'mono' ||
          current.bayerPattern != null) {
        return;
      }
      ref.read(liveStackingProvider.notifier).updateConfig(
            current.copyWith(sensorMode: 'auto'),
          );
    });
  }

  Future<void> _startStacking() async {
    // Let user pick a reference image file
    const typeGroup = XTypeGroup(
      label: 'Image files',
      extensions: ['fits', 'fit', 'fts', 'xisf', 'tif', 'tiff', 'png'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _isStarting = true);

    try {
      final notifier = ref.read(liveStackingProvider.notifier);
      final config = ref.read(liveStackingProvider).config;
      await notifier.startFromFile(file.path, config: config);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopStacking() async {
    setState(() => _isStopping = true);
    try {
      await ref.read(liveStackingProvider.notifier).stop();
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _resetStack() async {
    await ref.read(liveStackingProvider.notifier).reset();
  }

  /// True while the Stack-and-Share selection preview is being computed (between
  /// the button press and the launcher dialog opening). Guards against a second
  /// concurrent press while the DB query is in flight.
  bool _isOpeningStackAndShare = false;

  /// Entry point for the **Stack-and-Share Loop** (component C10).
  ///
  /// Resolves the selection summary for [sessionId] up front so the launcher
  /// dialog (C9) can render the per-filter / integration preview the operator
  /// confirms, then opens [StackAndShareDialog]. Selection runs against the
  /// shared Drift instance via [stackLightSelectorProvider]; the dialog's own
  /// orchestrator re-selects internally when the run starts.
  ///
  /// Errors are surfaced, never swallowed: a session with no qualifying lights
  /// ([NoLightsToStackException]) or any other selection failure is shown via an
  /// [ErrorDialog] rather than silently opening an empty launcher.
  Future<void> _openStackAndShare(int sessionId) async {
    if (_isOpeningStackAndShare) return;
    setState(() => _isOpeningStackAndShare = true);

    StackSelectionSummary? selection;
    Object? selectionError;
    try {
      selection = await ref.read(stackLightSelectorProvider).selectForSession(
            sessionId: sessionId,
            config: StackAndShareConfig.defaults,
          );
    } catch (e) {
      // Captured (not rethrown) so we can tear down the loading state in the
      // `finally` before presenting; the type is discriminated below to give the
      // "no lights" case its own actionable message.
      selectionError = e;
    } finally {
      if (mounted) setState(() => _isOpeningStackAndShare = false);
    }

    if (!mounted) return;

    if (selectionError is NoLightsToStackException) {
      await ErrorDialog.show(
        context,
        title: 'Nothing to stack',
        message: 'No light frames in this session qualify for stacking. '
            'Capture some lights (and pass any quality gates) before running '
            'Stack & Share.',
        technicalDetails: selectionError.toString(),
      );
      return;
    }
    if (selectionError != null) {
      await ErrorDialog.show(
        context,
        title: 'Could not prepare stack',
        message: 'Selecting the light frames for this session failed.',
        technicalDetails: selectionError.toString(),
      );
      return;
    }

    if (!mounted || selection == null) return;
    await StackAndShareDialog.show(
      context,
      sessionId: sessionId,
      selection: selection,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final stackState = ref.watch(liveStackingProvider);
    final isRunning = stackState.status == LiveStackingStatus.running;
    final isError = stackState.status == LiveStackingStatus.error;
    final stats = stackState.stats;
    final config = stackState.config;

    // Seed the OSC defaults from a connected colour camera: when the camera
    // reports a Bayer mosaic and the user has not yet touched the colour config,
    // default the colour mode ON and preselect the detected pattern. Wired here
    // (not in the OSC section's build) so the seeding never mutates state during
    // a descendant's build.
    _maybeSeedOscDefaultsFromCamera(config);

    // Resolve the current imaging session from the same authoritative state the
    // rest of the imaging screen uses. The Stack-and-Share entry point operates
    // on this session; with no active/selected session the button is disabled.
    final sessionState = ref.watch(sessionStateProvider);
    final sessionId = sessionState.dbSessionId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stack-and-Share entry point (C10): one-button launcher for the
          // post-capture stacking + share pipeline on the current session.
          _StackAndShareEntry(
            sessionId: sessionId,
            liveStackingActive: isRunning,
            isBusy: _isOpeningStackAndShare,
            onPressed:
                sessionId == null ? null : () => _openStackAndShare(sessionId),
          ),
          const SizedBox(height: 20),

          // Error banner
          if (isError && stackState.errorMessage != null)
            _ErrorBanner(
              message: stackState.errorMessage!,
              colors: widget.colors,
            ),

          // Status and controls
          PanelSection(
            title: 'Live Stacking',
            colors: widget.colors,
            child: Column(
              children: [
                // Status indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Status',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12, color: widget.colors.textSecondary)),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isRunning
                                ? widget.colors.success
                                : isError
                                    ? widget.colors.error
                                    : widget.colors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRunning
                              ? 'Stacking'
                              : isError
                                  ? 'Error'
                                  : 'Idle',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            fontWeight: FontWeight.w500,
                            color: isRunning
                                ? widget.colors.success
                                : isError
                                    ? widget.colors.error
                                    : widget.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (isRemoteMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Live stacking from a local file is only available on the '
                      'imaging host. Capture frames on the host to stack remotely.',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ),

                // Start/Stop buttons
                Row(
                  children: [
                    Expanded(
                      child: SmallButton(
                        label: _isStarting ? 'Starting...' : 'Start',
                        icon: _isStarting
                            ? LucideIcons.loader2
                            : LucideIcons.layers,
                        colors: widget.colors,
                        isEnabled: !isRemoteMode && !isRunning && !_isStarting,
                        onTap: _startStacking,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: _isStopping ? 'Stopping...' : 'Stop',
                        icon: LucideIcons.square,
                        isOutline: true,
                        colors: widget.colors,
                        isEnabled: isRunning && !_isStopping,
                        onTap: _stopStacking,
                      ),
                    ),
                  ],
                ),
                if (isRunning) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SmallButton(
                      label: 'Reset Stack',
                      icon: LucideIcons.refreshCw,
                      isOutline: true,
                      colors: widget.colors,
                      onTap: _resetStack,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statistics
          PanelSection(
            title: 'Statistics',
            colors: widget.colors,
            child: Column(
              children: [
                _StatRow(
                  label: 'Stacked Frames',
                  value: '${stats.stackedFrameCount}',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Total Attempted',
                  value: '${stats.totalFramesAttempted}',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Rejected (Alignment)',
                  value: '${stats.rejectedAlignmentFailures}',
                  valueColor: stats.rejectedAlignmentFailures > 0
                      ? widget.colors.warning
                      : null,
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Matched Pairs',
                  value: stats.avgMatchedPairs.toStringAsFixed(1),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Alignment Residual',
                  value: '${stats.avgAlignmentResidual.toStringAsFixed(2)} px',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Sigma-Rejected (Total)',
                  value: _formatLargeNumber(stats.totalSigmaRejectedPixels),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Sigma-Rejected (Last Frame)',
                  value: _formatLargeNumber(
                      stackState.lastFrameSigmaRejectedPixels),
                  valueColor: _rejectionRateColor(
                      stackState.lastFrameSigmaRejectionRate, widget.colors),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Rejection Rate (Last Frame)',
                  value: stackState.lastFrameTotalPixels > 0
                      ? '${(stackState.lastFrameSigmaRejectionRate * 100).toStringAsFixed(2)}%'
                      : '--',
                  valueColor: _rejectionRateColor(
                      stackState.lastFrameSigmaRejectionRate, widget.colors),
                  colors: widget.colors,
                ),
                if (stackState.lastFrameTotalPixels > 0 &&
                    stackState.lastFrameSigmaRejectionRate >
                        _rejectionWarningThreshold) ...[
                  const SizedBox(height: 10),
                  _RejectionWarning(
                    rate: stackState.lastFrameSigmaRejectionRate,
                    colors: widget.colors,
                  ),
                ],
                const SizedBox(height: 12),
                // Alignment quality indicator
                _AlignmentQualityBar(
                  stats: stats,
                  colors: widget.colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stacked preview
          if (stackState.previewData != null &&
              stackState.previewWidth > 0 &&
              stackState.previewHeight > 0)
            PanelSection(
              title: 'Stacked Preview',
              colors: widget.colors,
              child: _StackedPreview(
                previewData: stackState.previewData!,
                width: stackState.previewWidth,
                height: stackState.previewHeight,
                channels: _previewChannels(stackState),
                colors: widget.colors,
              ),
            ),

          if (stackState.previewData != null) const SizedBox(height: 20),

          // Sigma Clipping config
          PanelSection(
            title: 'Sigma Clipping',
            colors: widget.colors,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Enabled',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12, color: widget.colors.textSecondary)),
                    NightshadeSwitch(
                      value: config.sigmaClipEnabled,
                      onChanged: (value) {
                        ref.read(liveStackingProvider.notifier).updateConfig(
                              config.copyWith(sigmaClipEnabled: value),
                            );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Threshold',
                  value: config.sigmaClipThreshold,
                  min: 1.0,
                  max: 5.0,
                  suffix: '\u03c3',
                  colors: widget.colors,
                  onChanged: config.sigmaClipEnabled
                      ? (value) {
                          ref.read(liveStackingProvider.notifier).updateConfig(
                                config.copyWith(sigmaClipThreshold: value),
                              );
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Color (OSC) config — debayer Bayer CFA frames to RGB before
          // integrating. Defaults are camera-aware: a connected colour camera
          // pre-selects the switch ON and the detected Bayer pattern.
          _OscStackingSection(
            config: config,
            colors: widget.colors,
            cameraCapabilities: _connectedCameraCapabilities(),
            onConfigChanged: (next) =>
                ref.read(liveStackingProvider.notifier).updateConfig(next),
          ),
          const SizedBox(height: 20),

          // Star Matching config
          PanelSection(
            title: 'Star Matching',
            colors: widget.colors,
            child: Column(
              children: [
                InputRowEditable(
                  label: 'Max Stars',
                  value: config.maxMatchStars.toString(),
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(liveStackingProvider.notifier).updateConfig(
                            config.copyWith(maxMatchStars: parsed),
                          );
                    }
                  },
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Match Radius',
                  value: config.matchRadiusPx,
                  min: 5.0,
                  max: 200.0,
                  suffix: 'px',
                  colors: widget.colors,
                  onChanged: (value) {
                    ref.read(liveStackingProvider.notifier).updateConfig(
                          config.copyWith(matchRadiusPx: value),
                        );
                  },
                ),
                const SizedBox(height: 12),
                SliderRowInteractive(
                  label: 'Flux Tolerance',
                  value: config.matchFluxTolerance,
                  min: 0.1,
                  max: 1.0,
                  suffix: '',
                  colors: widget.colors,
                  onChanged: (value) {
                    ref.read(liveStackingProvider.notifier).updateConfig(
                          config.copyWith(matchFluxTolerance: value),
                        );
                  },
                ),
                const SizedBox(height: 12),
                InputRowEditable(
                  label: 'Min Pairs',
                  value: config.minMatchedPairs.toString(),
                  colors: widget.colors,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(liveStackingProvider.notifier).updateConfig(
                            config.copyWith(minMatchedPairs: parsed),
                          );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Channel layout of the current stacked preview, derived from the buffer
  /// length relative to the pixel count.
  ///
  /// The live stacker emits a single luminance plane (`width * height` u16
  /// samples) for a mono session and an interleaved RGB16 buffer
  /// (`width * height * 3`) for an OSC session. `LiveStackingState` does not
  /// carry the channel count separately, so we recover it from the geometry the
  /// same way the Stack-and-Share orchestrator validates it. Any length that is
  /// neither 1- nor 3-channel returns `1` so the grayscale path renders the
  /// luminance the engine actually produced rather than misreading bytes as RGB.
  int _previewChannels(LiveStackingState state) {
    final pixelCount = state.previewWidth * state.previewHeight;
    if (pixelCount <= 0) return 1;
    final data = state.previewData;
    if (data != null && data.length == pixelCount * 3) return 3;
    return 1;
  }

  /// Capabilities of the currently connected camera, or null when none is
  /// connected / the query is still in flight / the driver did not report.
  ///
  /// Used by the OSC section to default the colour switch ON for a colour
  /// camera and to pre-select its detected Bayer pattern. A null result simply
  /// means "no camera-derived default" — the controls fall back to the config's
  /// own (mono) defaults, never a guessed colour layout.
  CameraCapabilities? _connectedCameraCapabilities() {
    final deviceId = ref.watch(connectedCameraIdProvider);
    if (deviceId == null || deviceId.isEmpty) return null;
    final caps = ref.watch(equipmentCameraCapabilitiesProvider(deviceId));
    return caps.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
  }

  String _formatLargeNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  /// Resolve the value-color for a sigma-rejection rate based on the
  /// per-frame thresholds (`_rejectionWarningThreshold` /
  /// `_rejectionErrorThreshold`). Returns `null` for healthy rates so the
  /// stat row uses the default text color.
  Color? _rejectionRateColor(double rate, NightshadeColors colors) {
    if (rate >= _rejectionErrorThreshold) return colors.error;
    if (rate >= _rejectionWarningThreshold) return colors.warning;
    return null;
  }
}

/// Per-frame sigma-rejection rate at which we paint the stat in the warning
/// color. Above ~5% on a single frame usually indicates drift, a satellite
/// trail, clouds, or a tracking glitch -- worth flagging to the user.
const double _rejectionWarningThreshold = 0.05;

/// Per-frame sigma-rejection rate at which we escalate to the error color
/// and show the alert banner. Above ~15% the frame is contributing far more
/// noise than signal -- typically a stale or fundamentally unusable frame.
const double _rejectionErrorThreshold = 0.15;
