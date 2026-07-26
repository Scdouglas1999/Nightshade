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
  bool _captureInFlight = false;
  int _loopGeneration = 0;
  ProviderSubscription<ImagingService>? _imagingSubscription;
  ProviderSubscription<DeviceService>? _deviceSubscription;

  @override
  void initState() {
    super.initState();
    _imagingSubscription = ref.listenManual<ImagingService>(
      imagingServiceProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        _loopGeneration++;
        if (mounted && (_isLooping || _captureInFlight)) {
          setState(() {
            _isLooping = false;
            _captureInFlight = false;
          });
        }
      },
    );
    _deviceSubscription = ref.listenManual<DeviceService>(
      deviceServiceProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        if (mounted && _isChangingFilter) {
          setState(() => _isChangingFilter = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _loopGeneration++;
    _imagingSubscription?.close();
    _deviceSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final autofocusRunning = ref.watch(
      sessionStateProvider.select((session) => session.isAutofocusing),
    );
    final binningOptions = ref.watch(
      cameraBinningOptionsProvider(cameraState.deviceId ?? ''),
    );

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isCapturing = _captureInFlight ||
        cameraState.isExposing ||
        exposureProgress.percent > 0 ||
        exposureProgress.isDownloading;
    final captureBlocked = isCapturing ||
        _isChangingFilter ||
        filterWheelState.isMoving ||
        autofocusRunning;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.camera,
            title: 'Capture',
            accent: colors.primary,
          ),
          const SizedBox(height: DashboardCardStyle.headerGap),
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
                    _markExposureSettingsDirty();
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
                    _markExposureSettingsDirty();
                  }
                },
              ),
              // Binning dropdown
              _CompactDropdown(
                label: 'Bin',
                value: binningOptions.contains(exposureSettings.binning)
                    ? exposureSettings.binning
                    : binningOptions.first,
                items: binningOptions,
                colors: colors,
                onChanged: (v) {
                  if (v != null) {
                    final parts = v.split('x');
                    ref.read(exposureSettingsProvider.notifier).state =
                        exposureSettings.copyWith(
                      binningX: int.parse(parts[0]),
                      binningY: int.parse(parts[1]),
                    );
                    _markExposureSettingsDirty();
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
                onChanged: (_isChangingFilter ||
                        filterWheelState.isMoving ||
                        autofocusRunning ||
                        isCapturing ||
                        _isLooping)
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
                    _markExposureSettingsDirty();
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
                        value: (exposureProgress.percent / 100).clamp(0.0, 1.0),
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${exposureProgress.percent.clamp(0.0, 100.0).toInt()}%',
                      style: NightshadeTypography.labelStrongSm.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                )
              else if (!isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: NightshadeDecorations.tintedBadge(
                    colors.warning,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                  ),
                  child: Text(
                    'No Camera',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize10,
                        color: colors.warning),
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
                      (!isConnected || captureBlocked) ? null : _captureImage,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NightshadeButton(
                  label: _isLooping ? 'Stop Loop' : 'Loop',
                  icon: LucideIcons.repeat,
                  variant: _isLooping
                      ? ButtonVariant.primary
                      : ButtonVariant.outline,
                  size: ButtonSize.small,
                  // Stopping the loop must remain available while its current
                  // exposure is in flight. Abort is the separate action that
                  // cancels that exposure immediately.
                  onPressed: _isLooping
                      ? _toggleLoop
                      : (!isConnected || captureBlocked)
                          ? null
                          : _toggleLoop,
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

  Future<bool> _captureImage({ImagingService? expectedService}) async {
    if (_captureInFlight) return false;
    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not connected')),
        );
      }
      return false;
    }
    final ImagingService imagingService =
        expectedService ?? ref.read(imagingServiceProvider);
    if (!_isCurrentImagingService(imagingService)) return false;
    setState(() => _captureInFlight = true);
    try {
      final settings = ref.read(exposureSettingsProvider);
      final result = await imagingService.captureImage(settings: settings);
      // ImagingService owns currentImage publication, including the later raw
      // pixel upgrade. Re-publishing its early return here can overwrite that
      // newer raw-ready image with a stale preview-only copy.
      return result != null && _isCurrentImagingService(imagingService);
    } catch (e) {
      if (mounted && _isCurrentImagingService(imagingService)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
      return false;
    } finally {
      if (_isCurrentImagingService(imagingService)) {
        setState(() => _captureInFlight = false);
      }
    }
  }

  void _toggleLoop() async {
    if (_isLooping) {
      _loopGeneration++;
      setState(() => _isLooping = false);
      return;
    }
    final imagingService = ref.read(imagingServiceProvider);
    final generation = ++_loopGeneration;
    setState(() => _isLooping = true);
    while (_isLooping &&
        mounted &&
        generation == _loopGeneration &&
        _isCurrentImagingService(imagingService)) {
      final captured = await _captureImage(expectedService: imagingService);
      if (!_isCurrentImagingService(imagingService) ||
          generation != _loopGeneration) {
        break;
      }
      if (!captured) {
        break;
      }
      if (_isLooping && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted && generation == _loopGeneration) {
      setState(() => _isLooping = false);
    }
  }

  void _abortCapture() {
    _loopGeneration++;
    setState(() => _isLooping = false);
    ref.read(imagingServiceProvider).cancelExposure();
  }

  void _markExposureSettingsDirty() {
    ref.read(exposureSettingsUserDirtyProvider.notifier).state = true;
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

    // If filter wheel is connected, actually move it
    final filterWheelState = ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      // Capture the long-lived controllers before awaiting hardware. The card
      // may be removed while a slow wheel is still moving; reading `ref` after
      // that point would throw and lose the metadata update for a move that
      // physically succeeded.
      final deviceService = ref.read(deviceServiceProvider);
      final providerContainer =
          ProviderScope.containerOf(context, listen: false);
      final exposureSettingsController =
          ref.read(exposureSettingsProvider.notifier);
      final dirtyController =
          ref.read(exposureSettingsUserDirtyProvider.notifier);
      setState(() => _isChangingFilter = true);
      try {
        await deviceService.setFilterWheelPosition(position);
        if (identical(
          providerContainer.read(deviceServiceProvider),
          deviceService,
        )) {
          exposureSettingsController.state =
              exposureSettingsController.state.copyWith(filter: filterName);
          dirtyController.state = true;
        }
      } catch (e) {
        if (mounted &&
            identical(
              providerContainer.read(deviceServiceProvider),
              deviceService,
            )) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to change filter: $e'),
              backgroundColor: widget.colors.error,
            ),
          );
        }
      } finally {
        if (mounted &&
            identical(
              providerContainer.read(deviceServiceProvider),
              deviceService,
            )) {
          setState(() => _isChangingFilter = false);
        }
      }
    } else {
      final exposureSettings = ref.read(exposureSettingsProvider);
      ref.read(exposureSettingsProvider.notifier).state =
          exposureSettings.copyWith(filter: filterName);
      _markExposureSettingsDirty();
    }
  }

  bool _isCurrentImagingService(ImagingService service) =>
      mounted && identical(ref.read(imagingServiceProvider), service);
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
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: widget.colors.textMuted),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          height: 28,
          child: TextField(
            controller: _controller,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: widget.colors.textPrimary),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              filled: true,
              fillColor: widget.colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                borderSide: BorderSide(color: widget.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                borderSide: BorderSide(
                    color: widget.colors.border.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                borderSide: BorderSide(color: widget.colors.primary),
              ),
            ),
            onSubmitted: widget.onChanged,
          ),
        ),
        if (widget.suffix != null) ...[
          const SizedBox(width: 2),
          Text(widget.suffix!,
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: widget.colors.textMuted)),
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
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted),
        ),
        const SizedBox(width: 4),
        Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: highlight
                ? NightshadeDecorations.emphasisSurface(
                    colors.primary,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                  )
                : BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    border: Border.all(
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                  ),
            child: DropdownButtonHideUnderline(
              child: IgnorePointer(
                ignoring: !isEnabled,
                child: DropdownButton<String>(
                  value: value,
                  isDense: true,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
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
