import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/remote_directory_picker_dialog.dart';
import 'panel_widgets.dart';

typedef DefectMapLocalDarkPicker = Future<List<String>> Function();
typedef DefectMapHostDarkPicker = Future<String?> Function(
  BuildContext context,
);

Future<List<String>> _pickLocalDarkFrames() async {
  const typeGroup = XTypeGroup(
    label: 'Dark frames',
    extensions: ['fits', 'fit', 'fts', 'xisf'],
  );
  final files = await openFiles(acceptedTypeGroups: [typeGroup]);
  return files.map((file) => file.path).toList(growable: false);
}

Future<String?> _pickHostDarkDirectory(BuildContext context) {
  return RemoteDirectoryPickerDialog.show(
    context,
    title: 'Select the host folder containing dark frames',
  );
}

final defectMapLocalDarkPickerProvider =
    Provider<DefectMapLocalDarkPicker>((ref) => _pickLocalDarkFrames);

final defectMapHostDarkPickerProvider =
    Provider<DefectMapHostDarkPicker>((ref) => _pickHostDarkDirectory);

/// Image-calibration controls for the imaging screen.
///
/// Surfaces the per-camera defect map (W6-DEFECT) pipeline:
/// - status line ("1,243 pixels, built 2 days ago at -10C")
/// - build-from-darks button
/// - apply-during-capture toggle
/// - clear-map button
///
/// All controls are disabled when the camera is not connected, with a
/// tooltip explaining why. The defect map is keyed by camera id, sensor
/// width / height and a 5C temperature bucket; those four values come
/// from [cameraStateProvider] + [cameraCapabilitiesProvider].
class CalibrationSection extends ConsumerWidget {
  final NightshadeColors colors;

  const CalibrationSection({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final cameraId = cameraState.deviceId;
    final cameraName = cameraState.deviceName ?? cameraId;
    final temperatureC = cameraState.temperature;

    final capabilitiesAsync =
        ref.watch(cameraCapabilitiesProvider(cameraId ?? ''));
    final capabilities = capabilitiesAsync.valueOrNull;

    // The defect map is keyed by the sensor's full size, not by any
    // user-selected subframe. Use the capability max which mirrors the
    // sensor dimensions reported by the driver.
    final sensorWidth = capabilities?.maxWidth ?? 0;
    final sensorHeight = capabilities?.maxHeight ?? 0;

    // Reasons the controls might be unavailable, in priority order.
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final String? disabledReason = _resolveDisabledReason(
      isConnected: isConnected,
      cameraId: cameraId,
      sensorWidth: sensorWidth,
      sensorHeight: sensorHeight,
      temperatureC: temperatureC,
    );
    final controlsEnabled = disabledReason == null;
    final noCameraConnected =
        !isConnected || cameraId == null || cameraId.isEmpty;

    return PanelSection(
      title: 'Image Calibration',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBlock(
            colors: colors,
            cameraId: cameraId,
            cameraName: cameraName,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            temperatureC: temperatureC,
            disabledReason: disabledReason,
          ),
          if (noCameraConnected) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: NightshadeButton(
                label: 'Go to Equipment',
                icon: NightshadeIcons.connected,
                size: ButtonSize.small,
                onPressed: () => context.go('/equipment'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          DefectMapBuildButton(
            colors: colors,
            enabled: controlsEnabled,
            disabledReason: disabledReason,
            cameraId: cameraId,
            temperatureC: temperatureC,
            isRemoteMode: isRemoteMode,
          ),
          const SizedBox(height: 12),
          _ApplyToggle(
            colors: colors,
            enabled: controlsEnabled,
            disabledReason: disabledReason,
            cameraId: cameraId,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            temperatureC: temperatureC,
          ),
          const SizedBox(height: 12),
          _ClearButton(
            colors: colors,
            enabled: controlsEnabled,
            disabledReason: disabledReason,
            cameraId: cameraId,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            temperatureC: temperatureC,
          ),
          const SizedBox(height: 16),
          _CorrectionSettings(
            colors: colors,
            cameraId: cameraId,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            temperatureC: temperatureC,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: 'Flat Wizard',
              icon: LucideIcons.sun,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => context.push('/flat-wizard'),
            ),
          ),
        ],
      ),
    );
  }

  static String? _resolveDisabledReason({
    required bool isConnected,
    required String? cameraId,
    required int sensorWidth,
    required int sensorHeight,
    required double? temperatureC,
  }) {
    // Remote mode is fully supported: the host owns the dark frames and the
    // stored defect map. BUILD picks a host directory via the remote picker;
    // APPLY and CLEAR route to the host over REST. The camera-state gates
    // below still apply (they describe the host camera, mirrored to the
    // remote client over the WS).
    if (!isConnected || cameraId == null || cameraId.isEmpty) {
      return 'Connect a camera to manage its defect map.';
    }
    if (sensorWidth <= 0 || sensorHeight <= 0) {
      return 'Waiting for sensor dimensions from the connected camera.';
    }
    if (temperatureC == null) {
      return 'Camera has not reported a sensor temperature yet; '
          'wait for the first cooler telemetry reading.';
    }
    return null;
  }
}

class _StatusBlock extends ConsumerWidget {
  final NightshadeColors colors;
  final String? cameraId;
  final String? cameraName;
  final int sensorWidth;
  final int sensorHeight;
  final double? temperatureC;
  final String? disabledReason;

  const _StatusBlock({
    required this.colors,
    required this.cameraId,
    required this.cameraName,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.temperatureC,
    required this.disabledReason,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (disabledReason != null) {
      return _StatusLine(
        colors: colors,
        icon: LucideIcons.alertCircle,
        iconColor: colors.warning,
        message: disabledReason!,
      );
    }

    final statusAsync = ref.watch(defectMapStatusProvider(
      DefectMapQuery(
        cameraId: cameraId!,
        width: sensorWidth,
        height: sensorHeight,
        sensorTemperatureCelsius: temperatureC!,
      ),
    ));

    return statusAsync.when(
      data: (status) {
        if (status == null) {
          return _NoMapForBucketBlock(
            colors: colors,
            cameraId: cameraId!,
            cameraName: cameraName ?? cameraId!,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            currentTemperatureC: temperatureC!,
          );
        }
        final pixels = _formatThousands(status.defectivePixelCount);
        final age = _relativeAge(status.lastRebuiltAt);
        return _StatusLine(
          colors: colors,
          icon: LucideIcons.checkCircle2,
          iconColor: colors.success,
          message:
              'Defect map: $pixels pixels (built $age at ${status.temperatureBucket.label})',
        );
      },
      loading: () => _StatusLine(
        colors: colors,
        icon: NightshadeIcons.loading,
        iconColor: colors.textSecondary,
        message: 'Loading defect map status...',
      ),
      error: (err, _) => _StatusLine(
        colors: colors,
        icon: NightshadeIcons.warning,
        iconColor: colors.error,
        message: 'Failed to load defect map status: $err',
      ),
    );
  }
}

/// Empty-state block shown when no defect map exists for the current
/// (camera, sensor, temperature bucket) tuple. Falls back to scanning
/// neighbouring temperature buckets so the user is offered the nearest
/// existing map as a one-click alternative — this covers the common
/// case where the cooler set-point drifted by 5C from the temperature
/// the user originally captured darks at.
class _NoMapForBucketBlock extends ConsumerWidget {
  /// Range of buckets to probe around the current temperature when
  /// looking for an existing map at a neighbouring set-point. 9 buckets
  /// at 5C each spans 40C of cooler range, which covers everything from
  /// a -25C uncooled CMOS at one extreme to a TEC running at +15C on a
  /// hot night at the other.
  static const int _maxBucketOffsetSteps = 9;
  static const double _bucketStepCelsius = 5.0;

  final NightshadeColors colors;
  final String cameraId;
  final String cameraName;
  final int sensorWidth;
  final int sensorHeight;
  final double currentTemperatureC;

  const _NoMapForBucketBlock({
    required this.colors,
    required this.cameraId,
    required this.cameraName,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.currentTemperatureC,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentBucket =
        DefectMapTemperatureBucket.fromCelsius(currentTemperatureC);
    final fallback = _findNearestExistingBucket(ref, currentBucket);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusLine(
          colors: colors,
          icon: NightshadeIcons.info,
          iconColor: colors.textSecondary,
          message: 'No defect map for $cameraName at ${currentBucket.label}.',
        ),
        const SizedBox(height: 6),
        Text(
          'Capture 20+ dark frames at this temperature, then click Build '
          'to generate one.',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        if (fallback != null) ...[
          const SizedBox(height: 10),
          _AlternateBucketChip(
            colors: colors,
            cameraId: cameraId,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            currentBucket: currentBucket,
            alternateBucket: fallback,
          ),
        ],
      ],
    );
  }

  /// Probe neighbouring temperature buckets (alternating outward from the
  /// current bucket) and return the closest one that has a stored map.
  /// Returns null if no map exists anywhere within the probed range.
  ///
  /// Implementation note: this synchronously reads cached
  /// `defectMapStatusProvider` values for each probed bucket. Riverpod's
  /// FutureProvider.family lazily computes on read and the widget rebuilds
  /// when each future resolves, so the first frame may show no fallback
  /// and a follow-up frame may surface one once the probes complete.
  DefectMapTemperatureBucket? _findNearestExistingBucket(
    WidgetRef ref,
    DefectMapTemperatureBucket currentBucket,
  ) {
    for (var step = 1; step <= _maxBucketOffsetSteps; step++) {
      for (final sign in const [-1, 1]) {
        final candidateCelsius =
            currentBucket.celsius + (sign * step * _bucketStepCelsius);
        final status = ref.watch(defectMapStatusProvider(
          DefectMapQuery(
            cameraId: cameraId,
            width: sensorWidth,
            height: sensorHeight,
            sensorTemperatureCelsius: candidateCelsius,
          ),
        ));
        final existing = status.valueOrNull;
        if (existing != null && existing.storedOnDisk) {
          return existing.temperatureBucket;
        }
      }
    }
    return null;
  }
}

class _AlternateBucketChip extends ConsumerWidget {
  final NightshadeColors colors;
  final String cameraId;
  final int sensorWidth;
  final int sensorHeight;
  final DefectMapTemperatureBucket currentBucket;
  final DefectMapTemperatureBucket alternateBucket;

  const _AlternateBucketChip({
    required this.colors,
    required this.cameraId,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.currentBucket,
    required this.alternateBucket,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delta =
        (alternateBucket.celsius - currentBucket.celsius).toStringAsFixed(0);
    final signedDelta =
        alternateBucket.celsius >= currentBucket.celsius ? '+$delta' : delta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.accent,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(NightshadeIcons.temperature, size: 14, color: colors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A map exists for ${alternateBucket.label} ($signedDelta C '
              'from current).',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            label: 'Use ${alternateBucket.label} map',
            icon: NightshadeIcons.check,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: () async {
              final notifier = ref.read(defectMapNotifierProvider.notifier);
              // Enable the existing alternate-bucket map for capture-time
              // application. The notifier scopes the apply flag to the
              // camera id, not the bucket, so this is exactly the same
              // call the user would have flipped via the Apply switch.
              await notifier.setApplyDuringCapture(
                cameraId: cameraId,
                apply: true,
                width: sensorWidth,
                height: sensorHeight,
                sensorTemperatureCelsius: alternateBucket.celsius,
              );
              if (!context.mounted) return;
              final state = ref.read(defectMapNotifierProvider);
              if (state.errorMessage != null) {
                context.showErrorSnackBar(state.errorMessage!);
              } else {
                context.showSuccessSnackBar(
                  'Using ${alternateBucket.label} defect map for this '
                  'camera until you build one at ${currentBucket.label}.',
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final Color iconColor;
  final String message;

  const _StatusLine({
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      backgroundColor: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DefectMapBuildButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool enabled;
  final String? disabledReason;
  final String? cameraId;
  final double? temperatureC;
  final bool isRemoteMode;

  const DefectMapBuildButton({
    super.key,
    required this.colors,
    required this.enabled,
    required this.disabledReason,
    required this.cameraId,
    required this.temperatureC,
    required this.isRemoteMode,
  });

  @override
  ConsumerState<DefectMapBuildButton> createState() =>
      _DefectMapBuildButtonState();
}

class _DefectMapBuildButtonState extends ConsumerState<DefectMapBuildButton> {
  bool _picking = false;
  int _operationGeneration = 0;

  @override
  void didUpdateWidget(covariant DefectMapBuildButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraId != widget.cameraId ||
        oldWidget.temperatureC != widget.temperatureC ||
        oldWidget.isRemoteMode != widget.isRemoteMode) {
      _operationGeneration++;
      _picking = false;
    }
  }

  Future<void> _pickAndBuild() async {
    final cameraId = widget.cameraId;
    final temperatureC = widget.temperatureC;
    if (cameraId == null || temperatureC == null) {
      // Defense in depth: the button is disabled when these are missing,
      // but guard anyway so the bridge call never sees nulls.
      return;
    }

    final generation = ++_operationGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _picking = true);
    try {
      if (widget.isRemoteMode) {
        await _pickHostDirectoryAndBuild(
          generation,
          authority,
          cameraId,
          temperatureC,
        );
      } else {
        await _pickLocalFilesAndBuild(
          generation,
          authority,
          cameraId,
          temperatureC,
        );
      }
    } catch (error) {
      if (!mounted ||
          generation != _operationGeneration ||
          !identical(ref.read(backendProvider), authority) ||
          widget.cameraId != cameraId) {
        return;
      }
      context.showErrorSnackBar('Could not select dark frames: $error');
    } finally {
      if (mounted && generation == _operationGeneration) {
        setState(() => _picking = false);
      }
    }
  }

  /// Local path: pick the dark FITS/XISF files with the OS file picker and
  /// build from their absolute paths.
  Future<void> _pickLocalFilesAndBuild(
    int generation,
    NightshadeBackend authority,
    String cameraId,
    double temperatureC,
  ) async {
    final paths = await ref.read(defectMapLocalDarkPickerProvider)();
    if (paths.isEmpty || !_isCurrent(generation, authority, cameraId)) return;

    if (paths.length < DefectMapService.minRequiredDarkFrames) {
      if (!mounted) return;
      context.showWarningSnackBar(
        'Defect detection requires at least '
        '${DefectMapService.minRequiredDarkFrames} dark frames; '
        'you selected ${paths.length}.',
      );
      return;
    }

    final notifier = ref.read(defectMapNotifierProvider.notifier);
    await notifier.build(
      cameraId: cameraId,
      darkFramePaths: paths,
      sensorTemperatureCelsius: temperatureC,
    );
    if (_isCurrent(generation, authority, cameraId)) _reportResult();
  }

  /// Remote path: the host owns the dark frames, so the operator picks a host
  /// directory. The host enumerates the FITS/XISF darks under it and builds
  /// the map there — no frame data crosses the wire.
  Future<void> _pickHostDirectoryAndBuild(
    int generation,
    NightshadeBackend authority,
    String cameraId,
    double temperatureC,
  ) async {
    final directory = await ref.read(defectMapHostDarkPickerProvider)(context);
    if (directory == null || !_isCurrent(generation, authority, cameraId)) {
      return;
    }

    final notifier = ref.read(defectMapNotifierProvider.notifier);
    await notifier.build(
      cameraId: cameraId,
      darkFramePaths: const [],
      darkFramesDirectory: directory,
      sensorTemperatureCelsius: temperatureC,
    );
    if (_isCurrent(generation, authority, cameraId)) _reportResult();
  }

  void _reportResult() {
    if (!mounted) return;
    final state = ref.read(defectMapNotifierProvider);
    if (state.errorMessage != null) {
      context.showErrorSnackBar(state.errorMessage!);
    } else if (state.statusMessage != null) {
      context.showSuccessSnackBar(state.statusMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (_picking && previous != null && !identical(previous, next)) {
        _operationGeneration++;
        setState(() => _picking = false);
      }
    });
    final uiState = ref.watch(defectMapNotifierProvider);
    final isBuilding = uiState.isBuilding;
    final buttonEnabled =
        widget.enabled && !_picking && !isBuilding && !uiState.isClearing;

    final button = SmallButton(
      label: _picking
          ? 'Selecting dark frames...'
          : isBuilding
              ? 'Building defect map...'
              : 'Build defect map from current darks',
      icon: _picking || isBuilding ? NightshadeIcons.loading : LucideIcons.cog,
      colors: widget.colors,
      isEnabled: buttonEnabled,
      onTap: buttonEnabled ? _pickAndBuild : null,
    );

    return _MaybeTooltip(
      message: widget.enabled ? null : widget.disabledReason,
      child: button,
    );
  }

  bool _isCurrent(
    int generation,
    NightshadeBackend authority,
    String cameraId,
  ) {
    return mounted &&
        generation == _operationGeneration &&
        identical(ref.read(backendProvider), authority) &&
        widget.cameraId == cameraId;
  }
}

class _ApplyToggle extends ConsumerWidget {
  final NightshadeColors colors;
  final bool enabled;
  final String? disabledReason;
  final String? cameraId;
  final int sensorWidth;
  final int sensorHeight;
  final double? temperatureC;

  const _ApplyToggle({
    required this.colors,
    required this.enabled,
    required this.disabledReason,
    required this.cameraId,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.temperatureC,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The toggle reflects the persisted status when we have one; otherwise
    // it defaults to off and the user can flip it once a map is built.
    bool currentValue = false;
    var toggleEnabled = false;
    String? mapDisabledReason;
    if (enabled) {
      final statusAsync = ref.watch(defectMapStatusProvider(
        DefectMapQuery(
          cameraId: cameraId!,
          width: sensorWidth,
          height: sensorHeight,
          sensorTemperatureCelsius: temperatureC!,
        ),
      ));
      final status = statusAsync.valueOrNull;
      currentValue = status?.applyDuringCapture ?? false;
      toggleEnabled = status?.storedOnDisk == true;
      if (statusAsync.isLoading) {
        mapDisabledReason = 'Loading defect map status...';
      } else if (statusAsync.hasError) {
        mapDisabledReason = 'Could not verify the current defect map.';
      } else if (!toggleEnabled) {
        mapDisabledReason =
            'Build a defect map for this camera and temperature first.';
      }
    }

    final row = Row(
      children: [
        Expanded(
          child: Text(
            'Apply during capture',
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary),
          ),
        ),
        NightshadeSwitch(
          value: currentValue,
          enabled: toggleEnabled,
          onChanged: toggleEnabled
              ? (value) async {
                  final notifier = ref.read(defectMapNotifierProvider.notifier);
                  await notifier.setApplyDuringCapture(
                    cameraId: cameraId!,
                    apply: value,
                    width: sensorWidth,
                    height: sensorHeight,
                    sensorTemperatureCelsius: temperatureC!,
                  );
                  if (!context.mounted) return;
                  final state = ref.read(defectMapNotifierProvider);
                  if (state.errorMessage != null) {
                    context.showErrorSnackBar(state.errorMessage!);
                  }
                }
              : null,
        ),
      ],
    );

    return _MaybeTooltip(
      message:
          toggleEnabled ? null : (enabled ? mapDisabledReason : disabledReason),
      child: row,
    );
  }
}

class _ClearButton extends ConsumerWidget {
  final NightshadeColors colors;
  final bool enabled;
  final String? disabledReason;
  final String? cameraId;
  final int sensorWidth;
  final int sensorHeight;
  final double? temperatureC;

  const _ClearButton({
    required this.colors,
    required this.enabled,
    required this.disabledReason,
    required this.cameraId,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.temperatureC,
  });

  Future<void> _confirmAndClear(BuildContext context, WidgetRef ref) async {
    final bucket = DefectMapTemperatureBucket.fromCelsius(temperatureC!).label;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear defect map?'),
          content: Text(
            'This deletes the stored defect map for $cameraId at '
            '${sensorWidth}x$sensorHeight at $bucket. You can rebuild it '
            'from darks at any time.',
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: 'Clear',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
            ),
          ],
        );
      },
    );

    if (shouldClear != true) return;

    final notifier = ref.read(defectMapNotifierProvider.notifier);
    await notifier.clear(
      cameraId: cameraId!,
      width: sensorWidth,
      height: sensorHeight,
      sensorTemperatureCelsius: temperatureC!,
    );

    if (!context.mounted) return;
    final state = ref.read(defectMapNotifierProvider);
    if (state.errorMessage != null) {
      context.showErrorSnackBar(state.errorMessage!);
    } else if (state.statusMessage != null) {
      context.showSuccessSnackBar(state.statusMessage!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(defectMapNotifierProvider);
    final buttonEnabled = enabled && !uiState.isClearing && !uiState.isBuilding;

    final button = SmallButton(
      label: uiState.isClearing
          ? 'Clearing...'
          : 'Clear defect map for this camera at this temperature',
      icon:
          uiState.isClearing ? NightshadeIcons.loading : NightshadeIcons.delete,
      isOutline: true,
      colors: colors,
      isEnabled: buttonEnabled,
      onTap: buttonEnabled ? () => _confirmAndClear(context, ref) : null,
    );

    return _MaybeTooltip(
      message: enabled ? null : disabledReason,
      child: button,
    );
  }
}

class _MaybeTooltip extends StatelessWidget {
  final String? message;
  final Widget child;

  const _MaybeTooltip({required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    if (message == null) return child;
    return Tooltip(message: message!, child: child);
  }
}

/// Settings sub-section: method / kernel / save-original /
/// auto-apply. Each change is persisted via [defectMapSettingsProvider]
/// AND pushed to the running sequencer (when the camera is connected and
/// has a known temperature) so the next captured frame uses the new
/// settings without requiring a sequencer restart.
class _CorrectionSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final String? cameraId;
  final int sensorWidth;
  final int sensorHeight;
  final double? temperatureC;

  const _CorrectionSettings({
    required this.colors,
    required this.cameraId,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.temperatureC,
  });

  bool get _canPushToSequencer =>
      cameraId != null &&
      cameraId!.isNotEmpty &&
      sensorWidth > 0 &&
      sensorHeight > 0 &&
      temperatureC != null;

  Future<void> _runSettingsChange(
    BuildContext context,
    Future<void> Function() change,
  ) async {
    try {
      await change();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update defect-map settings: $error'),
          backgroundColor: colors.error,
        ),
      );
    }
  }

  Future<void> _pushIfActive(WidgetRef ref) async {
    // Reconcile even when the new setting is OFF. The native sequencer owns a
    // pre-loaded runtime slot; merely persisting autoApply=false would leave a
    // previously loaded map active for subsequent frames.
    if (!_canPushToSequencer) return;
    final notifier = ref.read(defectMapNotifierProvider.notifier);
    await notifier.syncCurrentSettingsToSequencer(
      cameraId: cameraId!,
      width: sensorWidth,
      height: sensorHeight,
      sensorTemperatureCelsius: temperatureC!,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(defectMapSettingsProvider);
    if (settings.isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading correction settings…',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
            ),
          ),
        ],
      );
    }
    final loadError = settings.loadError;
    if (loadError != null) {
      return Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not load correction settings from the imaging host.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(defectMapSettingsProvider),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final notifier = ref.read(defectMapSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correction settings',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        // Auto-apply: enables defect correction whenever a map exists for
        // the connected camera at the current temperature bucket.
        Row(
          children: [
            Expanded(
              child: Text(
                'Auto-apply when map exists',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textPrimary),
              ),
            ),
            NightshadeSwitch(
              value: settings.autoApply,
              onChanged: (value) async {
                await _runSettingsChange(context, () async {
                  await notifier.setAutoApply(value);
                  // Toggling auto-apply with a map present should
                  // propagate to the sequencer immediately.
                  await _pushIfActive(ref);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Method. The imaging side pane can be narrower than the dropdown's
        // intrinsic label width, so stack the control below its label locally
        // instead of letting the row clip offscreen.
        _ResponsiveDropdownSetting(
          label: 'Replacement method',
          colors: colors,
          value: settings.method.label,
          items: DefectMapMethod.values.map((m) => m.label).toList(),
          onChanged: (value) async {
            if (value == null) return;
            final method = DefectMapMethod.values.firstWhere(
              (m) => m.label == value,
            );
            await _runSettingsChange(context, () async {
              await notifier.setMethod(method);
              await _pushIfActive(ref);
            });
          },
        ),
        const SizedBox(height: 6),
        // Kernel.
        _ResponsiveDropdownSetting(
          label: 'Kernel size',
          colors: colors,
          value: settings.kernel.label,
          items: DefectMapKernelSize.values.map((k) => k.label).toList(),
          onChanged: (value) async {
            if (value == null) return;
            final kernel = DefectMapKernelSize.values.firstWhere(
              (k) => k.label == value,
            );
            await _runSettingsChange(context, () async {
              await notifier.setKernel(kernel);
              await _pushIfActive(ref);
            });
          },
        ),
        const SizedBox(height: 6),
        // Save original — when on, the original uncorrected frame is
        // archived to a `Raw/` sibling directory.
        Row(
          children: [
            Expanded(
              child: Text(
                'Save original to Raw/ subdir',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textPrimary),
              ),
            ),
            NightshadeSwitch(
              value: settings.saveOriginal,
              onChanged: (value) async {
                await _runSettingsChange(context, () async {
                  await notifier.setSaveOriginal(value);
                  await _pushIfActive(ref);
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ResponsiveDropdownSetting extends StatelessWidget {
  const _ResponsiveDropdownSetting({
    required this.label,
    required this.colors,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final NightshadeColors colors;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: NightshadeTypography.fontSize12,
        color: colors.textPrimary,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final dropdown = NightshadeDropdown(
          value: value,
          items: items,
          isExpanded: constraints.maxWidth < 360,
          onChanged: onChanged,
        );

        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelWidget,
              const SizedBox(height: 6),
              dropdown,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 12),
            dropdown,
          ],
        );
      },
    );
  }
}

/// Insert thousands separators into a non-negative integer's decimal
/// representation. We deliberately avoid the `intl` NumberFormat machinery
/// here because it would force a locale dependency for a single grouping
/// rule.
String _formatThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Format a build timestamp as a coarse "x time ago" string. Returns
/// "(unknown date)" when the source had no usable mtime.
String _relativeAge(DateTime? at) {
  if (at == null) return '(unknown date)';
  final delta = DateTime.now().toUtc().difference(at.toUtc());
  if (delta.isNegative) {
    // Clock skew. Treat as "just now" rather than reporting a negative age.
    return 'just now';
  }
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) {
    final m = delta.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (delta.inDays < 1) {
    final h = delta.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  if (delta.inDays < 30) {
    final d = delta.inDays;
    return '$d day${d == 1 ? '' : 's'} ago';
  }
  if (delta.inDays < 365) {
    final months = (delta.inDays / 30).floor();
    return '$months month${months == 1 ? '' : 's'} ago';
  }
  final years = (delta.inDays / 365).floor();
  return '$years year${years == 1 ? '' : 's'} ago';
}
