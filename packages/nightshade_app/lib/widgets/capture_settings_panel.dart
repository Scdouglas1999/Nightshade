import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../utils/snackbar_helper.dart';

class CaptureSettingsPanel extends ConsumerStatefulWidget {
  final bool compact;
  final bool showHeader;
  final bool showConnectionBadge;
  final String title;

  const CaptureSettingsPanel({
    super.key,
    this.compact = false,
    this.showHeader = true,
    this.showConnectionBadge = true,
    this.title = 'Capture Controls',
  });

  @override
  ConsumerState<CaptureSettingsPanel> createState() =>
      _CaptureSettingsPanelState();
}

class _CaptureSettingsPanelState extends ConsumerState<CaptureSettingsPanel> {
  bool _isLooping = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    // Binning options reflect the connected camera's real maxBinX/Y (+ async
    // bin support) instead of a fixed list; falls back to defaults when no
    // camera/capabilities are available.
    final binningOptions =
        ref.watch(cameraBinningOptionsProvider(cameraState.deviceId ?? ''));

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;

    final spacing = widget.compact ? 8.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          Row(
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: widget.compact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (widget.showConnectionBadge && !isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: NightshadeDecorations.emphasisSurface(
                    colors.warning,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.alertCircle,
                          size: 12, color: colors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'No camera',
                        style: TextStyle(fontSize: 10, color: colors.warning),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (widget.showHeader) SizedBox(height: spacing + 4),

        _ControlRow(
          label: 'Exposure',
          compact: widget.compact,
          child: Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  initialValue: exposureSettings.exposureTime.toString(),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(exposureTime: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'sec',
                style: TextStyle(
                  fontSize: widget.compact ? 11 : 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: spacing),

        _ControlRow(
          label: 'Gain',
          compact: widget.compact,
          child: NightshadeTextField(
            initialValue: exposureSettings.gain.toString(),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 0) {
                ref.read(exposureSettingsProvider.notifier).state =
                    exposureSettings.copyWith(gain: parsed);
              }
            },
          ),
        ),

        SizedBox(height: spacing),

        _ControlRow(
          label: 'Offset',
          compact: widget.compact,
          child: NightshadeTextField(
            initialValue: exposureSettings.offset.toString(),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 0) {
                ref.read(exposureSettingsProvider.notifier).state =
                    exposureSettings.copyWith(offset: parsed);
              }
            },
          ),
        ),

        SizedBox(height: spacing),

        _ControlRow(
          label: 'Binning',
          compact: widget.compact,
          child: NightshadeDropdown(
            // Guard against a stored binning the connected camera doesn't
            // support (e.g. profile says 4x4 but the wheel maxes at 2x2).
            value: binningOptions.contains(exposureSettings.binning)
                ? exposureSettings.binning
                : (binningOptions.isNotEmpty ? binningOptions.first : '1x1'),
            items: binningOptions,
            onChanged: (value) {
              if (value != null) {
                final parts = value.split('x');
                ref.read(exposureSettingsProvider.notifier).state =
                    exposureSettings.copyWith(
                  binningX: int.parse(parts[0]),
                  binningY: int.parse(parts[1]),
                );
              }
            },
          ),
        ),

        SizedBox(height: spacing),

        _ControlRow(
          label: 'Frame',
          compact: widget.compact,
          child: NightshadeDropdown(
            value: exposureSettings.frameType.displayName,
            items: FrameType.values.map((t) => t.displayName).toList(),
            onChanged: (value) {
              if (value != null) {
                final type = FrameType.values.firstWhere(
                  (t) => t.displayName == value,
                  orElse: () => FrameType.light,
                );
                ref.read(exposureSettingsProvider.notifier).state =
                    exposureSettings.copyWith(frameType: type);
              }
            },
          ),
        ),

        SizedBox(height: spacing),

        _buildFilterControl(colors, exposureSettings),

        SizedBox(height: widget.compact ? 16 : 24),

        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                label: isCapturing
                    ? (exposureProgress.isDownloading
                        ? 'Downloading...'
                        : 'Capturing...')
                    : 'Capture',
                icon: isCapturing ? LucideIcons.loader2 : LucideIcons.camera,
                size: widget.compact ? ButtonSize.medium : ButtonSize.large,
                onPressed: (!isConnected || isCapturing) ? null : _captureImage,
              ),
            ),
          ],
        ),

        SizedBox(height: widget.compact ? 6 : 8),

        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                label: _isLooping ? 'Looping...' : 'Loop',
                icon: LucideIcons.repeat,
                variant:
                    _isLooping ? ButtonVariant.primary : ButtonVariant.outline,
                size: widget.compact ? ButtonSize.medium : ButtonSize.large,
                onPressed: (!isConnected || isCapturing) ? null : _toggleLoop,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NightshadeButton(
                label: 'Abort',
                icon: LucideIcons.x,
                variant: ButtonVariant.outline,
                size: widget.compact ? ButtonSize.medium : ButtonSize.large,
                onPressed: (isCapturing || _isLooping) ? _abortCapture : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Fallback filter labels used when no filter wheel is connected (or it
  /// reports no named slots). The connected wheel's real slot names take
  /// precedence so the dropdown commands the physical positions 1:1.
  static const List<String> _defaultFilters = [
    'L',
    'R',
    'G',
    'B',
    'Ha',
    'OIII',
    'SII',
  ];

  /// Filter row: when a filter wheel is connected with named slots the
  /// dropdown drives the physical wheel ([DeviceService.setFilterWheelPosition])
  /// and shows a current-position indicator; otherwise it falls back to the
  /// static label list and only tags the exposure metadata.
  Widget _buildFilterControl(
    NightshadeColors colors,
    ExposureSettings exposureSettings,
  ) {
    final wheel = ref.watch(filterWheelStateProvider);
    final wheelConnected =
        wheel.connectionState == DeviceConnectionState.connected &&
            wheel.filterNames.isNotEmpty;
    // Connected wheel slot names (resolved against the active profile) win over
    // the static fallback so a selection maps to a real wheel position.
    final filterNames =
        wheelConnected ? ref.watch(effectiveFiltersProvider) : _defaultFilters;

    final selected = exposureSettings.filter ?? filterNames.first;
    final currentFilterName = wheel.currentFilterName;
    // A mismatch warning fires when the wheel is connected, idle, and the
    // physical filter at the wheel differs from the filter the capture is
    // tagged with (e.g. selection in flight or stale exposure metadata).
    final hasMismatch = wheelConnected &&
        !wheel.isMoving &&
        currentFilterName != null &&
        currentFilterName != selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ControlRow(
          label: 'Filter',
          compact: widget.compact,
          child: NightshadeDropdown(
            value: filterNames.contains(selected) ? selected : filterNames.first,
            items: filterNames,
            onChanged: (value) {
              if (value == null) return;
              ref.read(exposureSettingsProvider.notifier).state =
                  exposureSettings.copyWith(filter: value);
              if (wheelConnected) {
                final position = filterNames.indexOf(value);
                if (position >= 0) {
                  _commandFilterWheel(position);
                }
              }
            },
          ),
        ),
        if (wheelConnected) ...[
          SizedBox(height: widget.compact ? 4 : 6),
          _ControlRow(
            label: '',
            compact: widget.compact,
            child: Row(
              children: [
                Icon(
                  wheel.isMoving ? LucideIcons.loader2 : LucideIcons.disc3,
                  size: 12,
                  color: hasMismatch ? colors.warning : colors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    wheel.isMoving
                        ? 'Moving filter wheel...'
                        : 'At wheel: ${currentFilterName ?? 'Unknown'}',
                    style: TextStyle(
                      fontSize: widget.compact ? 10 : 11,
                      color: hasMismatch ? colors.warning : colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hasMismatch) ...[
          SizedBox(height: widget.compact ? 4 : 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertTriangle, size: 12, color: colors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Wheel is on $currentFilterName, not $selected',
                    style: TextStyle(fontSize: 10, color: colors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _commandFilterWheel(int position) async {
    try {
      await ref.read(deviceServiceProvider).setFilterWheelPosition(position);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not change the filter. Please try again.');
      }
    }
  }

  Future<void> _captureImage() async {
    try {
      final imagingService = ref.read(imagingServiceProvider);
      final settings = ref.read(exposureSettingsProvider);

      final result = await imagingService.captureImage(settings: settings);

      if (result != null && mounted) {
        ref.read(currentImageProvider.notifier).state = result;
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Capture failed: $e');
      }
    }
  }

  void _toggleLoop() async {
    if (_isLooping) {
      setState(() => _isLooping = false);
      return;
    }

    setState(() => _isLooping = true);

    while (_isLooping && mounted) {
      await _captureImage();
      if (_isLooping && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (mounted) {
      setState(() => _isLooping = false);
    }
  }

  void _abortCapture() {
    setState(() {
      _isLooping = false;
    });
    ref.read(imagingServiceProvider).cancelExposure();
  }
}

class _ControlRow extends StatelessWidget {
  final String label;
  final Widget child;
  final bool compact;

  const _ControlRow({
    required this.label,
    required this.child,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: compact ? 70 : 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
