import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'glass_card.dart';

class CaptureSettingsCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const CaptureSettingsCard({super.key, required this.colors});

  @override
  ConsumerState<CaptureSettingsCard> createState() =>
      _CaptureSettingsCardState();
}

class _CaptureSettingsCardState extends ConsumerState<CaptureSettingsCard> {
  bool _isLooping = false;
  bool _isChangingFilter = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;
    final isFilterWheelConnected =
        filterWheelState.connectionState == DeviceConnectionState.connected;

    // Get actual filter names from connected filter wheel, or use defaults
    final filterNames = filterWheelState.filterNames.isNotEmpty
        ? filterWheelState.filterNames
        : const ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];

    // Current filter - use filter wheel position if connected, else from settings
    final currentFilterIndex = filterWheelState.currentPosition;
    final currentFilterName = isFilterWheelConnected &&
            currentFilterIndex != null &&
            currentFilterIndex >= 0 &&
            currentFilterIndex < filterNames.length
        ? filterNames[currentFilterIndex]
        : (exposureSettings.filter != null &&
                filterNames.contains(exposureSettings.filter)
            ? exposureSettings.filter!
            : filterNames.first);

    return DashboardGlassCard(
      colors: colors,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Settings - use Wrap for responsive layout
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Exposure
              _CompactSettingField(
                label: 'Exp',
                value: exposureSettings.exposureTime.toString(),
                suffix: 's',
                colors: colors,
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed > 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(exposureTime: parsed);
                  }
                },
              ),
              // Gain
              _CompactSettingField(
                label: 'Gain',
                value: exposureSettings.gain.toString(),
                colors: colors,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null && parsed >= 0) {
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(gain: parsed);
                  }
                },
              ),
              // Binning dropdown
              _CompactDropdown(
                label: 'Bin',
                value: exposureSettings.binning,
                items: const ['1x1', '2x2', '3x3', '4x4'],
                colors: colors,
                onChanged: (v) {
                  if (v != null) {
                    final parts = v.split('x');
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(
                      binningX: int.parse(parts[0]),
                      binningY: int.parse(parts[1]),
                    );
                  }
                },
              ),
              // Filter dropdown - uses actual filter names from connected filter wheel
              _CompactDropdown(
                label: 'Filter',
                value: currentFilterName,
                items: filterNames,
                colors: colors,
                highlight: true,
                onChanged: (_isChangingFilter || filterWheelState.isMoving)
                    ? null
                    : (v) => _onFilterChanged(v, filterNames),
              ),
              // Frame type dropdown
              _CompactDropdown(
                label: 'Frame',
                value: exposureSettings.frameType.displayName,
                items: FrameType.values.map((t) => t.displayName).toList(),
                colors: colors,
                onChanged: (v) {
                  if (v != null) {
                    final type = FrameType.values.firstWhere(
                      (t) => t.displayName == v,
                      orElse: () => FrameType.light,
                    );
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(frameType: type);
                  }
                },
              ),
              // Progress indicator when capturing
              if (isCapturing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: exposureProgress.percent,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(exposureProgress.percent * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                )
              else if (!isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'No Camera',
                    style: TextStyle(fontSize: 10, color: colors.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Capture buttons row - compact
          Row(
            children: [
              Expanded(
                flex: 2,
                child: NightshadeButton(
                  label: isCapturing
                      ? (exposureProgress.isDownloading
                          ? 'Downloading...'
                          : 'Capturing...')
                      : 'Capture',
                  icon: isCapturing ? LucideIcons.loader2 : LucideIcons.camera,
                  size: ButtonSize.small,
                  onPressed:
                      (!isConnected || isCapturing) ? null : _captureImage,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NightshadeButton(
                  label: _isLooping ? 'Stop' : 'Loop',
                  icon: LucideIcons.repeat,
                  variant: _isLooping
                      ? ButtonVariant.primary
                      : ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: (!isConnected || isCapturing) ? null : _toggleLoop,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NightshadeButton(
                  label: 'Abort',
                  icon: LucideIcons.x,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: (isCapturing || _isLooping) ? _abortCapture : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool> _captureImage() async {
    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not connected')),
        );
      }
      return false;
    }

    try {
      final imagingService = ref.read(imagingServiceProvider);
      final settings = ref.read(exposureSettingsProvider);
      final result = await imagingService.captureImage(settings: settings);
      if (result != null && mounted) {
        ref.read(currentImageProvider.notifier).state = result;
      }
      return result != null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
      return false;
    }
  }

  void _toggleLoop() async {
    if (_isLooping) {
      setState(() => _isLooping = false);
      return;
    }
    setState(() => _isLooping = true);
    while (_isLooping && mounted) {
      final captured = await _captureImage();
      if (!captured) {
        break;
      }
      if (_isLooping && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted) {
      setState(() => _isLooping = false);
    }
  }

  void _abortCapture() {
    setState(() => _isLooping = false);
    ref.read(imagingServiceProvider).cancelExposure();
  }

  /// Handle filter selection - updates settings AND moves the physical filter wheel
  Future<void> _onFilterChanged(
    String? filterName,
    List<String> filterNames,
  ) async {
    if (filterName == null) return;

    // Find the position index for this filter name
    final position = filterNames.indexOf(filterName);
    if (position < 0) return;

    // Always update exposure settings so filter is recorded in FITS headers
    final exposureSettings = ref.read(exposureSettingsProvider);
    ref.read(exposureSettingsProvider.notifier).state =
        exposureSettings.copyWith(filter: filterName);

    // If filter wheel is connected, actually move it
    final filterWheelState = ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      setState(() => _isChangingFilter = true);
      try {
        final deviceService = ref.read(deviceServiceProvider);
        await deviceService.setFilterWheelPosition(position);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to change filter: $e'),
              backgroundColor: widget.colors.error,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isChangingFilter = false);
        }
      }
    }
  }
}

/// Compact text field for inline settings editing
class _CompactSettingField extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  const _CompactSettingField({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.suffix,
  });

  @override
  State<_CompactSettingField> createState() => _CompactSettingFieldState();
}

class _CompactSettingFieldState extends State<_CompactSettingField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CompactSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if the value changed externally (not from user input)
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.label}:',
          style: TextStyle(fontSize: 11, color: widget.colors.textMuted),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          height: 28,
          child: TextField(
            controller: _controller,
            style: TextStyle(fontSize: 12, color: widget.colors.textPrimary),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              filled: true,
              fillColor: widget.colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                    color: widget.colors.border.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.colors.primary),
              ),
            ),
            onSubmitted: widget.onChanged,
          ),
        ),
        if (widget.suffix != null) ...[
          const SizedBox(width: 2),
          Text(widget.suffix!,
              style: TextStyle(fontSize: 10, color: widget.colors.textMuted)),
        ],
      ],
    );
  }
}

/// Compact dropdown for inline settings
class _CompactDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final NightshadeColors colors;
  final bool highlight;
  final ValueChanged<String?>? onChanged;

  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.colors,
    this.onChanged,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
        const SizedBox(width: 4),
        Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: highlight
                  ? colors.primary.withValues(alpha: 0.1)
                  : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: highlight
                    ? colors.primary.withValues(alpha: 0.3)
                    : colors.border.withValues(alpha: 0.5),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: IgnorePointer(
                ignoring: !isEnabled,
                child: DropdownButton<String>(
                  value: value,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    color: highlight ? colors.primary : colors.textPrimary,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                  ),
                  dropdownColor: colors.surface,
                  icon: Icon(
                    LucideIcons.chevronDown,
                    size: 12,
                    color: colors.textMuted,
                  ),
                  items: items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
