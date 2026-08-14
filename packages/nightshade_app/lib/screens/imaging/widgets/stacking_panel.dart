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
// summary the launcher dialog renders before a run starts. (Matches the
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

typedef StackingReferencePicker = Future<XFile?> Function();

Future<XFile?> _pickStackingReference() {
  const typeGroup = XTypeGroup(
    label: 'Image files',
    extensions: ['fits', 'fit', 'fts', 'xisf', 'tif', 'tiff', 'png'],
  );
  return openFile(acceptedTypeGroups: [typeGroup]);
}

final stackingReferencePickerProvider =
    Provider<StackingReferencePicker>((ref) => _pickStackingReference);

/// Picks the destination for a stacked master, returning null when the
/// operator cancels.
typedef StackingMasterDestinationPicker = Future<String?> Function(
    String suggestedName);

Future<String?> _pickStackingMasterDestination(String suggestedName) async {
  // Named for what is actually written: a 16-bit PNG of the integration (or
  // the stretched RGBA render for a colour stack). The chooser cannot stop an
  // operator typing another extension, so `LiveStackingService.saveMaster`
  // refuses it rather than renaming the file behind their back.
  const typeGroup = XTypeGroup(
    label: 'Stacked master (16-bit PNG)',
    extensions: ['png'],
  );
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [typeGroup],
  );
  return location?.path;
}

final stackingMasterDestinationPickerProvider =
    Provider<StackingMasterDestinationPicker>(
        (ref) => _pickStackingMasterDestination);

/// What the operator chose when asked to end a session that has stacked
/// frames in it.
enum _StopDecision { saveMaster, discard, cancel }

class StackingPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const StackingPanel({super.key, required this.colors});

  @override
  ConsumerState<StackingPanel> createState() => _StackingPanelState();
}

class _StackingPanelState extends ConsumerState<StackingPanel> {
  bool _isStarting = false;
  bool _isStopping = false;
  bool _isResetting = false;

  /// True from the moment Stop is pressed on a stack that has frames in it
  /// until the save/discard decision is resolved.
  bool _isEndingStack = false;
  int _startGeneration = 0;
  int _stopGeneration = 0;
  int _resetGeneration = 0;

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
    if (_isStarting) return;
    final generation = ++_startGeneration;
    final authority = ref.read(backendProvider);
    final isRemote = ref.read(isRemoteModeProvider);
    setState(() => _isStarting = true);

    // Remote (appliance) mode: there is no local reference file to pick — the
    // host stacks the frames IT captures. Arm the host; the next captured frame
    // becomes the reference and subsequent frames auto-feed.
    try {
      if (isRemote) {
        await ref.read(liveStackingProvider.notifier).startRemote(
              config: ref.read(liveStackingProvider).config,
            );
        return;
      }

      // Local mode: let the user pick a reference image file. The selection
      // belongs to the backend that opened the native dialog; reconnecting
      // while it is open must never send that local path to the new host.
      final file = await ref.read(stackingReferencePickerProvider)();
      if (file == null || !_isCurrentStart(generation, authority)) return;

      await ref.read(liveStackingProvider.notifier).startFromFile(
            file.path,
            config: ref.read(liveStackingProvider).config,
          );
    } catch (error) {
      if (!mounted || !_isCurrentStart(generation, authority)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start live stacking: $error')),
      );
    } finally {
      if (_isCurrentStart(generation, authority)) {
        setState(() => _isStarting = false);
      }
    }
  }

  /// Ends the session. Stopping releases the native stacker and with it every
  /// stacked pixel, so a session that has frames in it is never released
  /// silently: the operator is asked, and can write the master out first.
  Future<void> _stopStacking() async {
    if (_isStopping || _isEndingStack) return;
    final frames = ref.read(liveStackingProvider).stats.stackedFrameCount;
    if (frames <= 0) {
      await _releaseStack();
      return;
    }

    setState(() => _isEndingStack = true);
    try {
      final decision = await _askBeforeDiscardingStack(frames);
      if (!mounted || decision != _StopDecision.saveMaster) {
        if (decision == _StopDecision.discard) await _releaseStack();
        return;
      }
      // Keep the stack running until the master is safely on disk: a cancelled
      // picker or a failed write must not cost the operator the integration.
      if (!await _saveStackedMaster(frames)) return;
      if (!mounted) return;
      await _releaseStack();
    } finally {
      if (mounted) setState(() => _isEndingStack = false);
    }
  }

  /// Confirmation shown before Stop releases a stack that has frames in it.
  Future<_StopDecision> _askBeforeDiscardingStack(int frames) async {
    final colors = widget.colors;
    final decision = await showDialog<_StopDecision>(
      context: context,
      builder: (dialogContext) => NightshadeDialog(
        title: 'Keep this stack?',
        icon: NightshadeIcons.layers,
        width: 460,
        actions: [
          SmallButton(
            label: 'Cancel',
            icon: NightshadeIcons.close,
            isOutline: true,
            colors: colors,
            onTap: () => Navigator.of(dialogContext).pop(_StopDecision.cancel),
          ),
          const SizedBox(width: 8),
          SmallButton(
            label: 'Discard',
            icon: NightshadeIcons.delete,
            isOutline: true,
            colors: colors,
            onTap: () => Navigator.of(dialogContext).pop(_StopDecision.discard),
          ),
          const SizedBox(width: 8),
          SmallButton(
            label: 'Save master',
            icon: NightshadeIcons.save,
            colors: colors,
            onTap: () =>
                Navigator.of(dialogContext).pop(_StopDecision.saveMaster),
          ),
        ],
        child: Text(
          'Stopping releases the stacker, and the '
          '${frames == 1 ? '1 stacked frame' : '$frames stacked frames'} '
          'accumulated so far cannot be recovered afterwards. Save the '
          'stacked master first — as a 16-bit PNG of the integration, which '
          'carries no FITS header or WCS — or discard it and stop.',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
    return decision ?? _StopDecision.cancel;
  }

  /// Writes the accumulated master out. Returns true only when a file was
  /// actually written (so the caller knows it is safe to release the stack).
  Future<bool> _saveStackedMaster(int frames) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final destination = await ref.read(
      stackingMasterDestinationPickerProvider,
    )('live_stack_${stamp}Z_${frames}frames.png');
    if (!mounted || destination == null || destination.trim().isEmpty) {
      return false;
    }

    try {
      final saved = await ref
          .read(liveStackingServiceProvider)
          .saveMaster(filePath: destination);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stacked master (${saved.stackedFrameCount} frames) saved to '
            '${saved.filePath}',
          ),
        ),
      );
      return true;
    } on LiveStackingMasterFormatUnsupported catch (error) {
      // The operator typed a name in another format. Say so instead of writing
      // a PNG under their .fits name and letting them find out later.
      if (!mounted) return false;
      await ErrorDialog.show(
        context,
        title: 'Live-stack masters are saved as PNG',
        message: 'The live stacker writes a 16-bit PNG of the integration, so '
            'a "${error.requestedExtension}" master cannot be written here — '
            'the format carries no FITS header, WCS or integration metadata. '
            'Save it as .png, or use Stack & Share for a processed export. '
            'The stack is still running and was not discarded.',
        technicalDetails: error.toString(),
      );
      return false;
    } catch (error) {
      if (!mounted) return false;
      await ErrorDialog.show(
        context,
        title: 'Could not save the stacked master',
        message: 'The stack is still running and was not discarded. Try a '
            'different destination, or discard the stack deliberately.',
        technicalDetails: error.toString(),
      );
      return false;
    }
  }

  Future<void> _releaseStack() async {
    if (_isStopping) return;
    final generation = ++_stopGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _isStopping = true);
    try {
      await ref.read(liveStackingProvider.notifier).stop();
    } catch (error) {
      if (!mounted ||
          !_isCurrentOperation(generation, _stopGeneration, authority)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop live stacking: $error')),
      );
    } finally {
      if (_isCurrentOperation(generation, _stopGeneration, authority)) {
        setState(() => _isStopping = false);
      }
    }
  }

  Future<void> _resetStack() async {
    if (_isResetting) return;
    final generation = ++_resetGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _isResetting = true);
    try {
      await ref.read(liveStackingProvider.notifier).reset();
    } catch (error) {
      if (!mounted ||
          !_isCurrentOperation(generation, _resetGeneration, authority)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reset live stacking: $error')),
      );
    } finally {
      if (_isCurrentOperation(generation, _resetGeneration, authority)) {
        setState(() => _isResetting = false);
      }
    }
  }

  bool _isCurrentStart(int generation, NightshadeBackend authority) {
    return _isCurrentOperation(generation, _startGeneration, authority);
  }

  bool _isCurrentOperation(
    int generation,
    int currentGeneration,
    NightshadeBackend authority,
  ) {
    return mounted &&
        generation == currentGeneration &&
        identical(ref.read(backendProvider), authority);
  }

  /// True while the Stack-and-Share selection preview is being computed (between
  /// the button press and the launcher dialog opening). Guards against a second
  /// concurrent press while the DB query is in flight.
  bool _isOpeningStackAndShare = false;
  int _stackAndShareGeneration = 0;

  /// Entry point for the **Stack-and-Share Loop** (component C10).
  ///
  /// Resolves the selection summary for [sessionId] up front so the launcher
  /// dialog can render the per-filter / integration preview the operator
  /// confirms, then opens [StackAndShareDialog]. Selection runs against the
  /// shared Drift instance via [stackLightSelectorProvider]; the dialog's own
  /// orchestrator re-selects internally when the run starts.
  ///
  /// Errors are surfaced, never swallowed: a session with no qualifying lights
  /// ([NoLightsToStackException]) or any other selection failure is shown via an
  /// [ErrorDialog] rather than silently opening an empty launcher.
  Future<void> _openStackAndShare(int sessionId) async {
    if (_isOpeningStackAndShare) return;
    if (ref.read(isRemoteModeProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stack & Share must be run on the imaging host in this release.',
          ),
        ),
      );
      return;
    }
    final generation = ++_stackAndShareGeneration;
    final authority = ref.read(backendProvider);
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
      if (_isCurrentStackAndShare(generation, authority, sessionId)) {
        setState(() => _isOpeningStackAndShare = false);
      }
    }

    if (!mounted ||
        !_isCurrentStackAndShare(generation, authority, sessionId)) {
      return;
    }

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

  bool _isCurrentStackAndShare(
    int generation,
    NightshadeBackend authority,
    int sessionId,
  ) {
    return mounted &&
        generation == _stackAndShareGeneration &&
        identical(ref.read(backendProvider), authority) &&
        ref.read(sessionStateProvider).dbSessionId == sessionId;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (previous == null || identical(previous, next)) return;
      final hadPendingOperation = _isStarting ||
          _isStopping ||
          _isResetting ||
          _isEndingStack ||
          _isOpeningStackAndShare;
      if (!hadPendingOperation) return;
      _startGeneration++;
      _stopGeneration++;
      _resetGeneration++;
      _stackAndShareGeneration++;
      setState(() {
        _isStarting = false;
        _isStopping = false;
        _isResetting = false;
        _isEndingStack = false;
        _isOpeningStackAndShare = false;
      });
    });
    ref.listen<int?>(
      sessionStateProvider.select((state) => state.dbSessionId),
      (previous, next) {
        if (!_isOpeningStackAndShare || previous == next) return;
        _stackAndShareGeneration++;
        setState(() => _isOpeningStackAndShare = false);
      },
    );
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final stackState = ref.watch(liveStackingProvider);
    final isRunning = stackState.status == LiveStackingStatus.running;
    final isError = stackState.status == LiveStackingStatus.error;
    final stats = stackState.stats;
    final config = stackState.config;

    // `avgMatchedPairs` / `avgAlignmentResidual` are per-ALIGNED-frame metrics:
    // the stacker (imaging/src/stacking.rs) averages them over
    // `stacked_frame_count - 1`, because the reference frame is not matched
    // against itself and has zero residual by construction. So with no stack
    // running, or with only the reference frame in, both fields still hold
    // their 0.0 initialiser — and "Avg Alignment Residual 0.00 px" reads as
    // sub-pixel-perfect registration rather than "nothing measured yet".
    final hasAlignedFrames = stats.stackedFrameCount > 1;

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
            isRemoteMode: isRemoteMode,
            onPressed: sessionId == null || isRemoteMode
                ? null
                : () => _openStackAndShare(sessionId),
          ),
          const SizedBox(height: 20),

          // Error banner
          if (stackState.errorMessage != null)
            _ErrorBanner(
              message: stackState.errorMessage!,
              colors: widget.colors,
              onRetry: isRemoteMode && isRunning
                  ? () => ref
                      .read(liveStackingProvider.notifier)
                      .retryRemotePolling()
                  : null,
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
                            fontSize: NightshadeTypography.fontSize12,
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
                          style: NightshadeTypography.labelSm.copyWith(
                              color: isRunning
                                  ? widget.colors.success
                                  : isError
                                      ? widget.colors.error
                                      : widget.colors.textSecondary),
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
                      'Stacking runs on the imaging host. Press Start to arm it — '
                      'the next captured frame becomes the reference and every '
                      'frame after is stacked automatically, even while this '
                      'tablet is asleep.',
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
                            ? NightshadeIcons.loading
                            : NightshadeIcons.layers,
                        colors: widget.colors,
                        isEnabled: !isRunning && !_isStarting,
                        onTap: _startStacking,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: _isStopping ? 'Stopping...' : 'Stop',
                        icon: NightshadeIcons.stop,
                        isOutline: true,
                        colors: widget.colors,
                        isEnabled: isRunning && !_isStopping && !_isEndingStack,
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
                      label: _isResetting ? 'Resetting...' : 'Reset Stack',
                      icon: _isResetting
                          ? NightshadeIcons.loading
                          : NightshadeIcons.refresh,
                      isOutline: true,
                      colors: widget.colors,
                      isEnabled: !_isResetting,
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
                _StatGroupHeader(
                  label: 'Frames',
                  colors: widget.colors,
                  isFirst: true,
                ),
                _StatRow(
                  label: 'Stacked Frames',
                  value: _frames(stats.stackedFrameCount),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Total Attempted',
                  value: _frames(stats.totalFramesAttempted),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Rejected (Alignment)',
                  value: _frames(stats.rejectedAlignmentFailures),
                  valueColor: stats.rejectedAlignmentFailures > 0
                      ? widget.colors.warning
                      : null,
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Matched Pairs',
                  value: hasAlignedFrames
                      ? '${stats.avgMatchedPairs.toStringAsFixed(1)} stars'
                      : '—',
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Avg Alignment Residual',
                  value: hasAlignedFrames
                      ? '${stats.avgAlignmentResidual.toStringAsFixed(2)} px'
                      : '—',
                  colors: widget.colors,
                ),
                // The rows below count PIXELS, not frames. Without the break
                // and the units, "Sigma-Rejected 7.3M" under "Stacked Frames
                // 36" reads as 7.3 million discarded frames.
                _StatGroupHeader(
                  label: 'Pixels rejected by sigma clipping',
                  colors: widget.colors,
                ),
                _StatRow(
                  label: 'Sigma-Rejected (Total)',
                  value: _pixels(stats.totalSigmaRejectedPixels),
                  colors: widget.colors,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Sigma-Rejected (Last Frame)',
                  value: _pixels(stackState.lastFrameSigmaRejectedPixels),
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
                stretch: ref.watch(stackedPreviewStretchProvider),
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
                            fontSize: NightshadeTypography.fontSize12,
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

  /// A frame count, carrying its unit so it cannot be read as pixels.
  String _frames(int value) => '$value frames';

  /// A pixel count, carrying its unit so it cannot be read as frames.
  String _pixels(int value) => '${_formatLargeNumber(value)} px';

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
