import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'panel_widgets.dart';

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
                icon: LucideIcons.plug,
                size: ButtonSize.small,
                onPressed: () => context.go('/equipment'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _BuildButton(
            colors: colors,
            enabled: controlsEnabled,
            disabledReason: disabledReason,
            cameraId: cameraId,
            temperatureC: temperatureC,
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
        icon: LucideIcons.loader2,
        iconColor: colors.textSecondary,
        message: 'Loading defect map status...',
      ),
      error: (err, _) => _StatusLine(
        colors: colors,
        icon: LucideIcons.alertTriangle,
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
          icon: LucideIcons.info,
          iconColor: colors.textSecondary,
          message: 'No defect map for $cameraName at ${currentBucket.label}.',
        ),
        const SizedBox(height: 6),
        Text(
          'Capture 20+ dark frames at this temperature, then click Build '
          'to generate one.',
          style: TextStyle(
            fontSize: 11,
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
    final signedDelta = alternateBucket.celsius >= currentBucket.celsius
        ? '+$delta'
        : delta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.thermometer, size: 14, color: colors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A map exists for ${alternateBucket.label} ($signedDelta C '
              'from current).',
              style: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            label: 'Use ${alternateBucket.label} map',
            icon: LucideIcons.check,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
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

class _BuildButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool enabled;
  final String? disabledReason;
  final String? cameraId;
  final double? temperatureC;

  const _BuildButton({
    required this.colors,
    required this.enabled,
    required this.disabledReason,
    required this.cameraId,
    required this.temperatureC,
  });

  @override
  ConsumerState<_BuildButton> createState() => _BuildButtonState();
}

class _BuildButtonState extends ConsumerState<_BuildButton> {
  Future<void> _pickAndBuild() async {
    final cameraId = widget.cameraId;
    final temperatureC = widget.temperatureC;
    if (cameraId == null || temperatureC == null) {
      // Defense in depth: the button is disabled when these are missing,
      // but guard anyway so the bridge call never sees nulls.
      return;
    }

    const typeGroup = XTypeGroup(
      label: 'Dark frames',
      extensions: ['fits', 'fit', 'fts', 'xisf'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;

    if (files.length < DefectMapService.minRequiredDarkFrames) {
      if (!mounted) return;
      context.showWarningSnackBar(
        'Defect detection requires at least '
        '${DefectMapService.minRequiredDarkFrames} dark frames; '
        'you selected ${files.length}.',
      );
      return;
    }

    final paths = files.map((f) => f.path).toList(growable: false);

    final notifier = ref.read(defectMapNotifierProvider.notifier);
    await notifier.build(
      cameraId: cameraId,
      darkFramePaths: paths,
      sensorTemperatureCelsius: temperatureC,
    );

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
    final uiState = ref.watch(defectMapNotifierProvider);
    final isBuilding = uiState.isBuilding;
    final buttonEnabled = widget.enabled && !isBuilding && !uiState.isClearing;

    final button = SmallButton(
      label: isBuilding
          ? 'Building defect map...'
          : 'Build defect map from current darks',
      icon: isBuilding ? LucideIcons.loader2 : LucideIcons.cog,
      colors: widget.colors,
      isEnabled: buttonEnabled,
      onTap: buttonEnabled ? _pickAndBuild : null,
    );

    return _MaybeTooltip(
      message: widget.enabled ? null : widget.disabledReason,
      child: button,
    );
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
    if (enabled) {
      final statusAsync = ref.watch(defectMapStatusProvider(
        DefectMapQuery(
          cameraId: cameraId!,
          width: sensorWidth,
          height: sensorHeight,
          sensorTemperatureCelsius: temperatureC!,
        ),
      ));
      currentValue = statusAsync.valueOrNull?.applyDuringCapture ?? false;
    }

    final row = Row(
      children: [
        Expanded(
          child: Text(
            'Apply during capture',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
        ),
        Switch(
          value: currentValue,
          activeThumbColor: colors.primary,
          onChanged: enabled
              ? (value) async {
                  final notifier =
                      ref.read(defectMapNotifierProvider.notifier);
                  await notifier.setApplyDuringCapture(
                    cameraId: cameraId!,
                    apply: value,
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
      message: enabled ? null : disabledReason,
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
            GradientDialogButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              color: Theme.of(dialogContext).extension<NightshadeColors>()!.error,
              child: const Text('Clear'),
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
    final buttonEnabled =
        enabled && !uiState.isClearing && !uiState.isBuilding;

    final button = SmallButton(
      label: uiState.isClearing
          ? 'Clearing...'
          : 'Clear defect map for this camera at this temperature',
      icon: uiState.isClearing ? LucideIcons.loader2 : LucideIcons.trash2,
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
