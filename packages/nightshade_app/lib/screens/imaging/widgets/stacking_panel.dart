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
    final isPristine =
        config.sensorMode.toLowerCase() == 'mono' && config.bayerPattern == null;
    if (!isPristine) {
      _oscDefaultsSeeded = true;
      return;
    }

    if (ref.read(liveStackingProvider).status == LiveStackingStatus.running) {
      return; // Defer until the in-flight session ends.
    }

    final caps = _connectedCameraCapabilities();
    if (caps == null) return; // No camera-derived hint yet; try again next build.
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
            onPressed: sessionId == null
                ? null
                : () => _openStackAndShare(sessionId),
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
                            fontSize: 12,
                            color: widget.colors.textSecondary)),
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
                            fontSize: 12,
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
                        fontSize: 11,
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
                        isEnabled:
                            !isRemoteMode && !isRunning && !_isStarting,
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
                            fontSize: 12,
                            color: widget.colors.textSecondary)),
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
                          ref
                              .read(liveStackingProvider.notifier)
                              .updateConfig(
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

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// The Stack-and-Share launcher button (component C10).
///
/// A single primary [NightshadeButton] that opens [StackAndShareDialog] for the
/// current session. The button is disabled — with an explanatory
/// [NightshadeTooltip] — when there is no active/selected session, or when live
/// stacking is running (the stacking engine is a singleton, so we surface that
/// exclusivity here rather than letting the run fail at click). While the
/// selection preview is being computed the button shows its loading state.
class _StackAndShareEntry extends StatelessWidget {
  /// Current imaging session id, or null when none is active/selected.
  final int? sessionId;

  /// Whether live stacking is currently running (singleton-exclusivity gate).
  final bool liveStackingActive;

  /// Whether the selection preview is currently being computed.
  final bool isBusy;

  /// Invoked when the button is pressed; null when the action is unavailable.
  final VoidCallback? onPressed;

  const _StackAndShareEntry({
    required this.sessionId,
    required this.liveStackingActive,
    required this.isBusy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Live stacking takes precedence in the disabled reason: even with a valid
    // session, the singleton engine is busy.
    final disabledReason = liveStackingActive
        ? 'Stop live stacking to run Stack & Share'
        : sessionId == null
            ? 'Select a session to stack'
            : null;

    // Only enable when there is a session, live stacking is idle, and we are not
    // mid-preview. The reason text is mutually exclusive with an active handler.
    final enabled = disabledReason == null && !isBusy && onPressed != null;

    final button = SizedBox(
      width: double.infinity,
      child: NightshadeButton(
        label: 'Stack & Share',
        icon: LucideIcons.sparkles,
        isLoading: isBusy,
        onPressed: enabled ? onPressed : null,
      ),
    );

    if (disabledReason == null) {
      return button;
    }

    return NightshadeTooltip(
      message: disabledReason,
      child: button,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final NightshadeColors colors;

  const _ErrorBanner({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.error,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final NightshadeColors colors;

  const _StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Inline warning shown when the sigma-clipper rejected an unusually high
/// fraction of pixels on the most recent frame. The Rust engine accumulates
/// rejections silently; surfacing it here lets the observer react (refocus,
/// fix tracking, abandon the frame) instead of finding out hours later.
class _RejectionWarning extends StatelessWidget {
  final double rate;
  final NightshadeColors colors;

  const _RejectionWarning({
    required this.rate,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isError = rate >= _rejectionErrorThreshold;
    final accent = isError ? colors.error : colors.warning;
    final label = isError
        ? 'Very high sigma rejection on last frame'
        : 'Elevated sigma rejection on last frame';
    final detail = isError
        ? 'Above ${(_rejectionErrorThreshold * 100).toStringAsFixed(0)}% rejected -- '
            'check for clouds, drift, or a satellite trail.'
        : 'Above ${(_rejectionWarningThreshold * 100).toStringAsFixed(0)}% rejected -- '
            'seeing, dithering, or alignment may be off.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: NightshadeDecorations.emphasisSurface(
        accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? LucideIcons.alertOctagon : LucideIcons.alertTriangle,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual indicator of alignment quality based on stacking statistics.
class _AlignmentQualityBar extends StatelessWidget {
  final LiveStackingStats stats;
  final NightshadeColors colors;

  const _AlignmentQualityBar({
    required this.stats,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate quality from rejection ratio and alignment residual.
    // Quality = 1.0 means perfect, 0.0 means all frames rejected.
    double quality;
    String qualityLabel;
    Color qualityColor;

    if (stats.totalFramesAttempted == 0) {
      quality = 0.0;
      qualityLabel = 'No data';
      qualityColor = colors.textMuted;
    } else {
      final acceptanceRate = stats.stackedFrameCount / stats.totalFramesAttempted;
      // Residual penalty: >2px is poor, <0.5px is great
      final residualPenalty =
          (stats.avgAlignmentResidual / 2.0).clamp(0.0, 1.0);
      quality = (acceptanceRate * (1.0 - residualPenalty * 0.3)).clamp(0.0, 1.0);

      if (quality >= 0.8) {
        qualityLabel = 'Excellent';
        qualityColor = colors.success;
      } else if (quality >= 0.6) {
        qualityLabel = 'Good';
        qualityColor = colors.primary;
      } else if (quality >= 0.4) {
        qualityLabel = 'Fair';
        qualityColor = colors.warning;
      } else {
        qualityLabel = 'Poor';
        qualityColor = colors.error;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Alignment Quality',
                style:
                    TextStyle(fontSize: 11, color: colors.textSecondary)),
            Text(qualityLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: qualityColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: quality,
            minHeight: 6,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(qualityColor),
          ),
        ),
      ],
    );
  }
}

/// Displays the u16 stacked preview image, converting it to an 8-bit
/// displayable format on the fly.
///
/// [channels] selects how [previewData] is interpreted:
///   * `1` — a single luminance plane (`width * height` samples); rendered with
///     a min/max linear stretch into grayscale RGBA (the historic mono path,
///     byte-for-byte unchanged).
///   * `3` — an interleaved RGB16 buffer (`width * height * 3` samples, the
///     layout an OSC session produces); each channel is linearly stretched with
///     its own min/max so a colour stack previews in colour rather than as a
///     scrambled mono plane.
class _StackedPreview extends StatefulWidget {
  final Uint16List previewData;
  final int width;
  final int height;
  final int channels;
  final NightshadeColors colors;

  const _StackedPreview({
    required this.previewData,
    required this.width,
    required this.height,
    required this.channels,
    required this.colors,
  });

  @override
  State<_StackedPreview> createState() => _StackedPreviewState();
}

class _StackedPreviewState extends State<_StackedPreview> {
  ui.Image? _displayImage;
  bool _isDecoding = false;

  @override
  void initState() {
    super.initState();
    _buildDisplayImage();
  }

  @override
  void didUpdateWidget(_StackedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild when the data actually changes (identity check is fast)
    if (!identical(widget.previewData, oldWidget.previewData) ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.channels != oldWidget.channels) {
      _buildDisplayImage();
    }
  }

  @override
  void dispose() {
    _displayImage?.dispose();
    super.dispose();
  }

  Future<void> _buildDisplayImage() async {
    if (_isDecoding) return;
    _isDecoding = true;

    final data = widget.previewData;
    final w = widget.width;
    final h = widget.height;
    final pixelCount = w * h;

    if (pixelCount <= 0) {
      _isDecoding = false;
      return;
    }

    final Uint8List rgba;
    if (widget.channels == 3) {
      // Sanity check: an interleaved RGB16 buffer must carry 3 samples/pixel.
      if (data.length < pixelCount * 3) {
        _isDecoding = false;
        return;
      }
      rgba = stackedPreviewColorRgba(data, pixelCount);
    } else {
      // Sanity check.
      if (data.length < pixelCount) {
        _isDecoding = false;
        return;
      }
      rgba = stackedPreviewGrayRgba(data, pixelCount);
    }

    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _displayImage?.dispose();
          _displayImage = frame.image;
        });
      } else {
        frame.image.dispose();
      }

      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (e) {
      developer.log('[StackingPanel] Error building preview image: $e',
          name: 'StackingPanel', level: 900, error: e);
    } finally {
      _isDecoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayImage == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('Rendering preview...',
                  style:
                      TextStyle(fontSize: 11, color: widget.colors.textMuted)),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: widget.width / widget.height,
        child: RawImage(
          image: _displayImage,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview pixel conversion (channel-aware)
// ---------------------------------------------------------------------------

/// Linear min/max stretch of a single u16 luminance plane to grayscale RGBA.
/// Byte-for-byte identical to the historic mono preview path.
///
/// Exposed for testing the channel-branching contract of the stacked preview.
@visibleForTesting
Uint8List stackedPreviewGrayRgba(Uint16List data, int pixelCount) {
  int minVal = 65535;
  int maxVal = 0;
  for (int i = 0; i < pixelCount; i++) {
    final v = data[i];
    if (v < minVal) minVal = v;
    if (v > maxVal) maxVal = v;
  }
  final range = (maxVal - minVal).clamp(1, 65535);

  final rgba = Uint8List(pixelCount * 4);
  for (int i = 0; i < pixelCount; i++) {
    final normalized = ((data[i] - minVal) * 255 ~/ range).clamp(0, 255);
    final offset = i * 4;
    rgba[offset] = normalized;
    rgba[offset + 1] = normalized;
    rgba[offset + 2] = normalized;
    rgba[offset + 3] = 255;
  }
  return rgba;
}

/// Per-channel linear min/max stretch of an interleaved RGB16 buffer
/// (`R0,G0,B0,R1,...`) to RGBA.
///
/// Each channel is stretched against its own min/max so the colour balance is
/// preserved rather than being dominated by whichever channel happens to be
/// brightest. This is a genuine colour rendering (the live EAA preview is a
/// fast linear map; the quality-oriented STF colour stretch lives in the
/// Stack-and-Share result viewer), never a grayscale fallback.
///
/// Exposed for testing the channel-branching contract of the stacked preview.
@visibleForTesting
Uint8List stackedPreviewColorRgba(Uint16List data, int pixelCount) {
  var rMin = 65535, gMin = 65535, bMin = 65535;
  var rMax = 0, gMax = 0, bMax = 0;
  for (int i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final r = data[base];
    final g = data[base + 1];
    final b = data[base + 2];
    if (r < rMin) rMin = r;
    if (r > rMax) rMax = r;
    if (g < gMin) gMin = g;
    if (g > gMax) gMax = g;
    if (b < bMin) bMin = b;
    if (b > bMax) bMax = b;
  }
  final rRange = (rMax - rMin).clamp(1, 65535);
  final gRange = (gMax - gMin).clamp(1, 65535);
  final bRange = (bMax - bMin).clamp(1, 65535);

  final rgba = Uint8List(pixelCount * 4);
  for (int i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final offset = i * 4;
    rgba[offset] = ((data[base] - rMin) * 255 ~/ rRange).clamp(0, 255);
    rgba[offset + 1] = ((data[base + 1] - gMin) * 255 ~/ gRange).clamp(0, 255);
    rgba[offset + 2] = ((data[base + 2] - bMin) * 255 ~/ bRange).clamp(0, 255);
    rgba[offset + 3] = 255;
  }
  return rgba;
}

// ---------------------------------------------------------------------------
// OSC / Color stacking controls
// ---------------------------------------------------------------------------
//
// The OSC dropdown vocabulary (Bayer / demosaic values + labels) and the
// labelled dropdown widget are shared with the Stack-and-Share dialog via
// `osc_stacking_controls.dart` so the two surfaces never drift.

/// The 'Color (OSC)' section of the live-stacking panel.
///
/// Toggling the switch flips [LiveStackingConfig.sensorMode] between `mono` and
/// a colour mode; when ON it reveals the Bayer-pattern and demosaic-quality
/// dropdowns. Defaults are camera-aware: when a colour camera is connected, the
/// switch defaults ON, the colour mode resolves to `auto` (honour the frame's
/// declared geometry), and the Bayer dropdown's Auto entry is labelled with the
/// camera's detected pattern.
class _OscStackingSection extends StatelessWidget {
  final LiveStackingConfig config;
  final NightshadeColors colors;
  final CameraCapabilities? cameraCapabilities;
  final ValueChanged<LiveStackingConfig> onConfigChanged;

  const _OscStackingSection({
    required this.config,
    required this.colors,
    required this.cameraCapabilities,
    required this.onConfigChanged,
  });

  /// Whether OSC/colour stacking is enabled (any non-mono sensor mode).
  bool get _enabled => config.sensorMode.toLowerCase() != 'mono';

  /// The camera's detected Bayer pattern (upper-cased) when it reports one,
  /// else null.
  String? get _detectedPattern {
    final caps = cameraCapabilities;
    if (caps == null || !caps.isColor) return null;
    final raw = caps.bayerPattern?.trim().toUpperCase();
    if (raw == null || raw.isEmpty) return null;
    return oscBayerPatternValues.contains(raw) ? raw : null;
  }

  void _setEnabled(bool value) {
    if (!value) {
      onConfigChanged(config.copyWith(sensorMode: 'mono'));
      return;
    }
    // Turning colour ON: prefer `auto` so a frame that declares its own Bayer
    // geometry (or a colour camera that reports one) is honoured without
    // pinning a pattern the user did not choose. With no camera-derived hint we
    // still use `auto` — the engine debayers only when the frame actually
    // carries CFA geometry, never guessing.
    onConfigChanged(config.copyWith(sensorMode: 'auto'));
  }

  void _setBayerPattern(String? value) {
    if (value == null) return;
    onConfigChanged(
      value == oscBayerAutoValue
          ? config.copyWith(bayerPattern: null)
          : config.copyWith(bayerPattern: value),
    );
  }

  void _setDemosaicQuality(String? value) {
    if (value == null) return;
    onConfigChanged(config.copyWith(demosaicQuality: value));
  }

  @override
  Widget build(BuildContext context) {
    // The current Bayer selection: an explicit override pins the dropdown, else
    // the Auto sentinel (which still resolves the detected pattern at runtime).
    final bayerValue = config.bayerPattern?.toUpperCase() ?? oscBayerAutoValue;
    final demosaicValue = config.demosaicQuality.toLowerCase();

    return PanelSection(
      title: 'Color (OSC)',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NightshadeSwitchRow(
            label: 'OSC / Color',
            subtitle: 'Demosaic Bayer frames to RGB',
            value: _enabled,
            onChanged: _setEnabled,
          ),
          if (_enabled) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            OscDropdownField(
              label: 'Bayer pattern',
              value: bayerValue,
              items: oscBayerPatternValues,
              itemLabels: oscBayerPatternValues
                  .map((v) => oscBayerPatternLabel(v, _detectedPattern))
                  .toList(growable: false),
              onChanged: _setBayerPattern,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            OscDropdownField(
              label: 'Demosaic quality',
              value: demosaicValue,
              items: oscDemosaicQualityValues,
              itemLabels: oscDemosaicQualityValues
                  .map((v) => oscDemosaicQualityLabels[v] ?? v)
                  .toList(growable: false),
              onChanged: _setDemosaicQuality,
            ),
          ],
        ],
      ),
    );
  }
}
