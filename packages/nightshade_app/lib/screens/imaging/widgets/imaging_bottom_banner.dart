import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/filter_wheel_selector.dart';
import '../../../widgets/tutorial_keys/imaging_keys.dart';
import 'panel_widgets.dart';
import 'stretch_controls.dart';

/// The Imaging screen's bottom control area, reworked into a single THIN
/// horizontal banner so the live preview keeps the vertical room.
///
/// It replaces the previous three always-expanded collapsible sections
/// (Quick Capture / Stats / Display), each of which carried its own header bar
/// plus a tall body, with one toolbar row:
///
///   [ Snapshot ][ Loop ] │ [ Dur ][ Gain ▾ ] │ filters (scroll) ┄┄ stats │ Display ▾
///
/// Everything the old panel reached stays reachable:
///   * Snapshot + Loop are inline buttons.
///   * Duration is an inline field; Gain / Offset / Binning move into a compact
///     "Exposure" popover (less-used, so they no longer claim a permanent row).
///   * Filters use the same horizontally-scrolling [FilterWheelSelector].
///   * Temp / RMS / HFR render as a compact inline readout (was its own section).
///   * Auto-stretch keeps the compact [StretchControls] (toggle + method +
///     advanced dialog) on the trailing edge.
///
/// The whole bar scrolls horizontally on narrow widths so no control is ever
/// clipped, mirroring [ImagingPreviewToolbar]'s behaviour above the preview.
class ImagingBottomBanner extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isLooping;
  final bool isSingleCapture;
  final bool isSavingCapture;
  final bool isStoppingCapture;
  final VoidCallback onSnapshot;
  final VoidCallback onToggleLoop;

  /// Whether the Stats readout (temp / RMS / HFR) should be shown. Hidden on
  /// narrow/mobile widths, where the stats section has no room.
  final bool showStats;

  const ImagingBottomBanner({
    super.key,
    required this.colors,
    required this.isLooping,
    required this.isSingleCapture,
    required this.isSavingCapture,
    required this.isStoppingCapture,
    required this.onSnapshot,
    required this.onToggleLoop,
    this.showStats = true,
  });

  @override
  ConsumerState<ImagingBottomBanner> createState() =>
      _ImagingBottomBannerState();
}

class _ImagingBottomBannerState extends ConsumerState<ImagingBottomBanner> {
  /// Owns the bar's horizontal scroll so the scrollbar has something to track.
  final ScrollController _barScrollController = ScrollController();

  @override
  void dispose() {
    _barScrollController.dispose();
    super.dispose();
  }

  NightshadeColors get colors => widget.colors;

  @override
  Widget build(BuildContext context) {
    final showStats = widget.showStats;
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isSingleCapture = widget.isSingleCapture;
    final isLooping = widget.isLooping;
    final isStoppingCapture = widget.isStoppingCapture;
    final isCapturing = isSingleCapture || isLooping;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final hostSuffix = isRemoteMode ? ' (host)' : '';
    final hasFilters =
        ref.watch(filterWheelStateProvider).filterNames.isNotEmpty;

    void setDuration(double parsed) {
      ref.read(manualExposureSettingsUpdaterProvider).update(
            exposureSettings.copyWith(exposureTime: parsed),
          );
    }

    final capture = _CaptureGroup(
      colors: colors,
      hostSuffix: hostSuffix,
      isConnected: isConnected,
      isCapturing: isCapturing,
      isSingleCapture: isSingleCapture,
      isLooping: isLooping,
      isSavingCapture: widget.isSavingCapture,
      isStoppingCapture: isStoppingCapture,
      onSnapshot: widget.onSnapshot,
      onToggleLoop: widget.onToggleLoop,
    );

    final duration = _DurationField(
      colors: colors,
      hostSuffix: hostSuffix,
      value: exposureSettings.exposureTime,
      onChanged: setDuration,
    );

    final exposurePopover = _ExposurePopover(
      colors: colors,
      settings: exposureSettings,
      onChanged: (next) =>
          ref.read(manualExposureSettingsUpdaterProvider).update(next),
    );

    final filters = hasFilters
        ? _BannerFilterStrip(colors: colors)
        : const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stats = showStats ? _BannerStats(colors: colors) : null;
          const display = StretchControls(compact: true);

          // ONE layout, and no width threshold — because no constant can be
          // right here.
          //
          // This used to fork on `constraints.maxWidth >= wideEnough`, with
          // `wideEnough` a hand-picked constant (720, later 880 when auto-stretch
          // is on). Every child of the wide Row except the filter strip is
          // intrinsically sized, so whether they fit depends on runtime content:
          // the stretch method dropdown, the stats text, filter names, the
          // locale, the user's text scale. A constant can only ever be right for
          // one combination — raising 720 to 880 did not fix the clipping, it
          // moved which widths clipped. Measured afterwards, the wide branch
          // still overflowed by 86 dp at a 1280x800 window with stretch on (the
          // advanced-settings button laid out at x=1002 in a bar ending at 950,
          // entirely unreachable), and by 36 dp at 820 dp with stretch OFF.
          //
          // Instead, let the layout answer the question it is actually asking:
          //   * IntrinsicWidth gives the Row its natural width, which both makes
          //     `Expanded` legal inside the (horizontally unbounded) scroll view
          //     and yields the real "how much room do I need" number.
          //   * ConstrainedBox(minWidth: viewport) lets it fill the viewport when
          //     there IS slack, so the stats + display cluster stays pinned
          //     trailing exactly as the wide branch did.
          //   * When the natural width exceeds the viewport the scroll view
          //     scrolls. Nothing is ever clipped, at any width, in any locale.
          //
          // Net effect: identical appearance to the old wide branch whenever it
          // was correct, and a reachable (scrollable) bar everywhere it was not.
          // The bar has always scrolled when it did not fit, but it did so
          // SILENTLY: at 900 dp with a seven-filter wheel the gain chip, the
          // filters and the Stretch toggle sit past the right edge and the
          // only hint was the filter strip's own fade. Reachable is not the
          // same as discoverable — the flat-wizard row got a scrollbar for
          // exactly this reason, and the capture bar is the one the operator
          // uses all night. `thumbVisibility` keeps it drawn while there is
          // anything off-screen, and the controller is what lets us ask.
          return Scrollbar(
            controller: _barScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _barScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: IntrinsicWidth(
                  child: Row(
                    children: [
                      capture,
                      _divider(),
                      duration,
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      exposurePopover,
                      _divider(),
                      Expanded(
                        child: hasFilters
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: filters,
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (stats != null) ...[
                        const SizedBox(width: NightshadeTokens.spaceSm),
                        stats,
                        _divider(),
                      ] else
                        const SizedBox(width: NightshadeTokens.spaceSm),
                      display,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceSm),
      color: colors.border,
    );
  }
}

/// Whether Loop keeps the frames it captures.
///
/// Loop is a live-view mode, so saving defaults off and is session-scoped.
final loopSavesFramesProvider = StateProvider<bool>((ref) => false);

/// Identifies the banner's "Save loop frames" toggle for tests.
const loopSaveFramesToggleKey = Key('imaging.loopSaveFramesToggle');

/// Snapshot + Loop, grouped as the primary capture cluster.
class _CaptureGroup extends ConsumerWidget {
  final NightshadeColors colors;
  final String hostSuffix;
  final bool isConnected;
  final bool isCapturing;
  final bool isSingleCapture;
  final bool isLooping;
  final bool isSavingCapture;
  final bool isStoppingCapture;
  final VoidCallback onSnapshot;
  final VoidCallback onToggleLoop;

  const _CaptureGroup({
    required this.colors,
    required this.hostSuffix,
    required this.isConnected,
    required this.isCapturing,
    required this.isSingleCapture,
    required this.isLooping,
    required this.isSavingCapture,
    required this.isStoppingCapture,
    required this.onSnapshot,
    required this.onToggleLoop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saveLoopFrames = ref.watch(loopSavesFramesProvider);
    final snapshotEnabled = isConnected && !isCapturing;
    final loopEnabled = isConnected && !isSingleCapture && !isStoppingCapture;
    final snapshotLabel = isSingleCapture
        ? (isStoppingCapture
            ? 'Stopping…'
            : isSavingCapture
                ? 'Saving…'
                : 'Taking…')
        : 'Snapshot$hostSuffix';
    final loopLabel = isStoppingCapture
        ? 'Stopping…'
        : isLooping
            ? 'Stop'
            : 'Loop';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The screen's two primary actions reached assistive tech as unnamed
        // generic nodes ("panel: Snapshot"), so a screen-reader user was never
        // told the shutter was a button, nor that it was unavailable while the
        // camera was disconnected or already exposing. The role and the
        // enabled state are published here rather than inside the shared
        // SmallButton so this bar's contract is pinned by its own test.
        _BannerActionSemantics(
          label: snapshotLabel,
          enabled: snapshotEnabled,
          onTap: onSnapshot,
          child: SmallButton(
            key: ImagingTutorialKeys.snapshotBtn,
            label: snapshotLabel,
            icon: isSingleCapture
                ? NightshadeIcons.loading
                : NightshadeIcons.camera,
            colors: colors,
            isEnabled: snapshotEnabled,
            onTap: onSnapshot,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        _BannerActionSemantics(
          label: loopLabel,
          enabled: loopEnabled,
          onTap: onToggleLoop,
          child: SmallButton(
            key: ImagingTutorialKeys.loopBtn,
            label: loopLabel,
            icon: isStoppingCapture
                ? NightshadeIcons.loading
                : isLooping
                    ? NightshadeIcons.stop
                    : LucideIcons.video,
            colors: colors,
            isOutline: !isLooping,
            isEnabled: loopEnabled,
            onTap: onToggleLoop,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Tooltip(
          message: saveLoopFrames
              ? 'Loop frames are saved to the image folder and counted in the '
                  'session'
              : 'Loop frames are live view only — not saved, not counted',
          child: Semantics(
            button: true,
            enabled: true,
            toggled: saveLoopFrames,
            label: 'Save loop frames',
            child: SmallButton(
              key: loopSaveFramesToggleKey,
              label: 'Save',
              icon: saveLoopFrames ? NightshadeIcons.save : LucideIcons.eye,
              colors: colors,
              isOutline: !saveLoopFrames,
              // Changing it mid-loop would split one run across two
              // destinations, so it locks while the loop is live.
              isEnabled: !isLooping && !isStoppingCapture,
              onTap: () => ref.read(loopSavesFramesProvider.notifier).state =
                  !saveLoopFrames,
            ),
          ),
        ),
      ],
    );
  }
}

/// Publishes the button role + enabled state for one bar action.
///
/// `excludeSemantics` drops the child's own (role-less) nodes so the tree
/// carries exactly one node per control, and the tap action is republished
/// here because excluding the child's semantics also drops its gesture.
class _BannerActionSemantics extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  const _BannerActionSemantics({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: child,
    );
  }
}

/// Inline duration field on a single pill — tap to edit, commit on submit/blur.
class _DurationField extends StatefulWidget {
  final NightshadeColors colors;
  final String hostSuffix;
  final double value;
  final ValueChanged<double> onChanged;

  const _DurationField({
    required this.colors,
    required this.hostSuffix,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<_DurationField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  String get _formatted => widget.value.toStringAsFixed(0);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatted);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) _commit();
    });
  }

  @override
  void didUpdateWidget(_DurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && _formatted != _controller.text) {
      _controller.text = _formatted;
    }
  }

  void _commit() {
    setState(() => _isEditing = false);
    final parsed = double.tryParse(_controller.text);
    if (parsed != null && parsed > 0) {
      widget.onChanged(parsed);
    } else {
      _controller.text = _formatted;
    }
  }

  void _beginEdit() {
    setState(() => _isEditing = true);
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return GestureDetector(
      onTap: _beginEdit,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: ImagingTutorialKeys.exposureSlider,
        height: 32,
        padding:
            const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceSm),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(
            color: _isEditing ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dur${widget.hostSuffix}',
              style: TextStyle(
                fontSize: NightshadeTokens.fontSizePanelCaption,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 34,
              child: _isEditing
                  ? TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _commit(),
                    )
                  : Text(
                      _formatted,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.textPrimary,
                      ),
                    ),
            ),
            const SizedBox(width: 2),
            Text('s',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Compact "Exposure" popover for the less-used Gain / Offset / Binning fields,
/// keeping them reachable without an always-expanded Exposure row.
class _ExposurePopover extends StatelessWidget {
  final NightshadeColors colors;
  final ExposureSettings settings;
  final ValueChanged<ExposureSettings> onChanged;

  const _ExposurePopover({
    required this.colors,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Exposure settings',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PopoverNumberRow(
                  colors: colors,
                  label: 'Gain',
                  value: settings.gain.toString(),
                  onChanged: (text) {
                    final parsed = int.tryParse(text);
                    if (parsed != null && parsed >= 0) {
                      onChanged(settings.copyWith(gain: parsed));
                    }
                  },
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                _PopoverNumberRow(
                  colors: colors,
                  label: 'Offset',
                  value: settings.offset.toString(),
                  onChanged: (text) {
                    final parsed = int.tryParse(text);
                    if (parsed != null && parsed >= 0) {
                      onChanged(settings.copyWith(offset: parsed));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
      // The chip is live — it opens the gain/offset popover — but it reached
      // assistive tech as `panel: G100 [DISABLED]`, i.e. as an inert readout,
      // because the custom child carries no role of its own.
      child: Semantics(
        container: true,
        button: true,
        enabled: true,
        label: 'Exposure settings, gain ${settings.gain}',
        child: Container(
          height: 32,
          padding:
              const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceSm),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NightshadeIcons.sliders,
                  size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'G${settings.gain}',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(NightshadeIcons.chevronDown,
                  size: 13, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled inline number field used inside the Exposure popover. Reuses the
/// same [EditableCompactInput] (label above value) the old Exposure section
/// used, so the editing behaviour is identical — just relocated into a popover.
class _PopoverNumberRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _PopoverNumberRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return EditableCompactInput(
      label: label,
      value: value,
      colors: colors,
      isMobile: true,
      onChanged: onChanged,
    );
  }
}

/// The horizontally-scrolling filter strip with a trailing fade.
class _BannerFilterStrip extends ConsumerWidget {
  final NightshadeColors colors;

  const _BannerFilterStrip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Colors.transparent],
        stops: [0.0, 0.92, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: NightshadeTokens.spaceMd),
        child: FilterWheelSelector(
          key: ImagingTutorialKeys.filterSelector,
          style: FilterSelectorStyle.buttons,
          compact: true,
          // This strip is the Imaging screen's only filter control, and it
          // shipped without this callback — so the session card and every other
          // reader of exposureSettings.filter kept showing the previous (often
          // absent) filter while the wheel sat on something else. The frame's
          // recorded filter is resolved from the live wheel inside
          // ImagingService, but the settings mirror still has to follow the
          // selection or the UI contradicts the header it just wrote.
          onFilterSelected: (position, name) {
            final settings = ref.read(exposureSettingsProvider);
            ref.read(manualExposureSettingsUpdaterProvider).update(
                  settings.copyWith(filter: name),
                );
          },
        ),
      ),
    );
  }
}

/// Compact inline temp / RMS / HFR readout — the former Stats section, reduced
/// to a single muted row of icon+value segments (no card chrome).
class _BannerStats extends ConsumerWidget {
  final NightshadeColors colors;

  const _BannerStats({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);

    String tempValue = '---';
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      tempValue = cameraState.temperature != null
          ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
          : 'N/A';
    }

    String rmsValue = '---';
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.isGuiding &&
        guiderState.rmsTotal != null) {
      rmsValue = '${guiderState.rmsTotal!.toStringAsFixed(2)}"';
    }

    String hfrValue = '---';
    if (lastStats?.hfr != null) {
      hfrValue = lastStats!.hfr!.toStringAsFixed(2);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segment(NightshadeIcons.temperature, tempValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _segment(NightshadeIcons.activity, rmsValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _segment(NightshadeIcons.target, hfrValue),
      ],
    );
  }

  Widget _segment(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
