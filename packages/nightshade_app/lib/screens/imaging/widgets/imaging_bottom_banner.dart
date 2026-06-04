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
class ImagingBottomBanner extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isLooping;
  final bool isSingleCapture;
  final VoidCallback onSnapshot;
  final VoidCallback onToggleLoop;

  /// Whether the Stats readout (temp / RMS / HFR) should be shown. Hidden on
  /// narrow/mobile widths to match the previous behaviour that dropped the
  /// stats section there.
  final bool showStats;

  const ImagingBottomBanner({
    super.key,
    required this.colors,
    required this.isLooping,
    required this.isSingleCapture,
    required this.onSnapshot,
    required this.onToggleLoop,
    this.showStats = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing = isSingleCapture || isLooping;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final hostSuffix = isRemoteMode ? ' (host)' : '';
    final hasFilters =
        ref.watch(filterWheelStateProvider).filterNames.isNotEmpty;

    void setDuration(double parsed) {
      ref.read(exposureSettingsProvider.notifier).state =
          exposureSettings.copyWith(exposureTime: parsed);
    }

    final capture = _CaptureGroup(
      colors: colors,
      hostSuffix: hostSuffix,
      isConnected: isConnected,
      isCapturing: isCapturing,
      isSingleCapture: isSingleCapture,
      isLooping: isLooping,
      onSnapshot: onSnapshot,
      onToggleLoop: onToggleLoop,
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
          ref.read(exposureSettingsProvider.notifier).state = next,
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
          // Wide enough to give the filter strip the slack (Expanded) with the
          // stats + display controls pinned trailing. Below this the whole bar
          // scrolls horizontally so nothing is clipped.
          const wideEnough = 720.0;
          final stats = showStats ? _BannerStats(colors: colors) : null;
          const display = StretchControls(compact: true);

          if (constraints.maxWidth >= wideEnough) {
            return Row(
              children: [
                capture,
                _divider(),
                duration,
                const SizedBox(width: NightshadeTokens.spaceSm),
                exposurePopover,
                _divider(),
                Expanded(
                  child: hasFilters
                      ? Align(alignment: Alignment.centerLeft, child: filters)
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
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                capture,
                _divider(),
                duration,
                const SizedBox(width: NightshadeTokens.spaceSm),
                exposurePopover,
                if (hasFilters) ...[
                  _divider(),
                  filters,
                ],
                if (stats != null) ...[
                  _divider(),
                  stats,
                ],
                _divider(),
                display,
              ],
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

/// Snapshot + Loop, grouped as the primary capture cluster.
class _CaptureGroup extends StatelessWidget {
  final NightshadeColors colors;
  final String hostSuffix;
  final bool isConnected;
  final bool isCapturing;
  final bool isSingleCapture;
  final bool isLooping;
  final VoidCallback onSnapshot;
  final VoidCallback onToggleLoop;

  const _CaptureGroup({
    required this.colors,
    required this.hostSuffix,
    required this.isConnected,
    required this.isCapturing,
    required this.isSingleCapture,
    required this.isLooping,
    required this.onSnapshot,
    required this.onToggleLoop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SmallButton(
          key: ImagingTutorialKeys.snapshotBtn,
          label: isSingleCapture ? 'Taking…' : 'Snapshot$hostSuffix',
          icon: isSingleCapture ? LucideIcons.loader2 : LucideIcons.camera,
          colors: colors,
          isEnabled: isConnected && !isCapturing,
          onTap: onSnapshot,
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        SmallButton(
          key: ImagingTutorialKeys.loopBtn,
          label: isLooping ? 'Stop' : 'Loop',
          icon: isLooping ? LucideIcons.square : LucideIcons.video,
          colors: colors,
          isOutline: !isLooping,
          isEnabled: isConnected && !isSingleCapture,
          onTap: onToggleLoop,
        ),
      ],
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
                        fontSize: 13,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.textPrimary,
                      ),
                    ),
            ),
            const SizedBox(width: 2),
            Text('s', style: TextStyle(fontSize: 11, color: colors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Compact "Exposure" popover for the less-used Gain / Offset / Binning fields,
/// keeping them reachable without the old always-expanded Exposure row.
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
            Icon(LucideIcons.sliders, size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'G${settings.gain}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(LucideIcons.chevronDown, size: 13, color: colors.textMuted),
          ],
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
class _BannerFilterStrip extends StatelessWidget {
  final NightshadeColors colors;

  const _BannerFilterStrip({required this.colors});

  @override
  Widget build(BuildContext context) {
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
        _segment(LucideIcons.thermometer, tempValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _segment(LucideIcons.activity, rmsValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _segment(LucideIcons.target, hfrValue),
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
