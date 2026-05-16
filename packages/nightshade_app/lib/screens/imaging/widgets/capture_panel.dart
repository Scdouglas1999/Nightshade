import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../services/mount_command_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'panel_widgets.dart';

// Provider for park mount on end setting
final parkMountOnEndProvider = StateProvider<bool>((ref) => false);

class CapturePanel extends ConsumerWidget {
  final NightshadeColors colors;

  const CapturePanel({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final namingPattern = ref.watch(namingPatternProvider);
    final sessionState = ref.watch(sessionStateProvider);
    final sessionImages = ref.watch(sessionImagesProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final cameraState = ref.watch(cameraStateProvider);

    // Get binning options based on connected camera's capabilities
    final binningOptions = ref.watch(
      cameraBinningOptionsProvider(cameraState.deviceId ?? ''),
    );

    // Ensure current binning value is valid for available options
    final currentBinning = binningOptions.contains(exposureSettings.binning)
        ? exposureSettings.binning
        : binningOptions.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exposure Settings
          PanelSection(
            title: 'Exposure Settings',
            colors: colors,
            child: Column(
              children: [
                InputRowEditable(
                  label: 'Exposure',
                  value: exposureSettings.exposureTime.toStringAsFixed(1),
                  suffix: 'sec',
                  colors: colors,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      ref.read(exposureSettingsProvider.notifier).state =
                          exposureSettings.copyWith(exposureTime: parsed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownRow(
                  label: 'Frame Type',
                  value: exposureSettings.frameType.displayName,
                  items: FrameType.values.map((t) => t.displayName).toList(),
                  colors: colors,
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
                const SizedBox(height: 12),
                DropdownRow(
                  label: 'Binning',
                  value: currentBinning,
                  items: binningOptions,
                  colors: colors,
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
              ],
            ),
          ),
          const SizedBox(height: 20),

          // File Settings
          PanelSection(
            title: 'File Settings',
            colors: colors,
            child: Column(
              children: [
                DropdownRow(
                  label: 'Format',
                  value: namingPattern.format.displayName,
                  items:
                      ImageFileFormat.values.map((f) => f.displayName).toList(),
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final format = ImageFileFormat.values.firstWhere(
                        (f) => f.displayName == value,
                        orElse: () => ImageFileFormat.fits,
                      );
                      ref
                          .read(appSettingsProvider.notifier)
                          .setImageFormat(format.settingsValue);
                    }
                  },
                ),
                const SizedBox(height: 12),
                // In remote mode, show text input for server path
                // In local mode, show directory picker
                if (isRemoteMode)
                  InputRowEditable(
                    label: 'Save Path (Server)',
                    value: namingPattern.baseDir,
                    colors: colors,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setImageOutputPath(value);
                    },
                  )
                else
                  InputRow(
                    label: 'Save Path',
                    value: namingPattern.baseDir,
                    colors: colors,
                    trailing: GestureDetector(
                      onTap: () async {
                        final result = await getDirectoryPath(
                          confirmButtonText: 'Select',
                          initialDirectory: namingPattern.baseDir.isNotEmpty
                              ? namingPattern.baseDir
                              : null,
                        );
                        if (result != null) {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setImageOutputPath(result);
                        }
                      },
                      child: Icon(LucideIcons.folderOpen,
                          size: 14, color: colors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Session Statistics
          PanelSection(
            title: 'Session',
            colors: colors,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Captured',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    Text(
                      '${sessionImages.length} frames',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Integration',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                    Text(
                      _formatDuration(sessionState.totalIntegrationSecs),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Session status and duration
                if (sessionState.isActive) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary)),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Active',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.success),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Duration',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary)),
                      Text(
                        sessionState.duration != null
                            ? _formatSessionDuration(sessionState.duration!)
                            : '--:--:--',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SmallButton(
                        label: 'View Gallery',
                        icon: LucideIcons.galleryHorizontal,
                        colors: colors,
                        onTap: () {
                          // Would open gallery view
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: 'Clear Session',
                        icon: LucideIcons.trash2,
                        isOutline: true,
                        colors: colors,
                        onTap: () {
                          ref
                              .read(sessionImagesProvider.notifier)
                              .clearSession();
                        },
                      ),
                    ),
                  ],
                ),
                if (sessionState.isActive) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SmallButton(
                      label: 'End Session',
                      icon: LucideIcons.stopCircle,
                      colors: colors,
                      onTap: () => _showEndSessionDialog(context, ref, colors),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).round();

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatSessionDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _showEndSessionDialog(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    final sessionState = ref.read(sessionStateProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.stopCircle, color: colors.warning),
            const SizedBox(width: 12),
            const Text('End Session'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to end the current imaging session?',
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Images Captured:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text('${sessionState.completedExposures}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Integration:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text(_formatDuration(sessionState.totalIntegrationSecs),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Duration:',
                          style: TextStyle(color: colors.textSecondary)),
                      Text(
                          sessionState.duration != null
                              ? _formatSessionDuration(sessionState.duration!)
                              : '--:--:--',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, child) {
                final parkOnEnd = ref.watch(parkMountOnEndProvider);
                final mountState = ref.watch(mountStateProvider);
                final mountConnected = mountState.connectionState ==
                    DeviceConnectionState.connected;

                return CheckboxListTile(
                  value: parkOnEnd,
                  onChanged: mountConnected
                      ? (value) {
                          ref.read(parkMountOnEndProvider.notifier).state =
                              value ?? false;
                        }
                      : null,
                  title: Text(
                    'Park mount after ending session',
                    style: TextStyle(
                      fontSize: 14,
                      color: mountConnected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  enabled: mountConnected,
                );
              },
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          GradientDialogButton(
            onPressed: () async {
              // Capture context before closing dialog
              final dialogContext = context;
              Navigator.of(context).pop();
              await _endSession(ref, dialogContext);
            },
            color: colors.warning,
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  Future<void> _endSession(WidgetRef ref, BuildContext context) async {
    final logger = ref.read(loggingServiceProvider);
    try {
      final parkOnEnd = ref.read(parkMountOnEndProvider);

      // End the session
      await ref.read(sessionStateProvider.notifier).endSession();

      // Park mount if requested (service handles connection check)
      if (parkOnEnd) {
        logger.info('[Imaging] Parking mount after session end...',
            source: 'CapturePanel');
        final result = await ref.read(mountCommandServiceProvider).park();
        if (context.mounted) {
          context.showCommandActionResult(result);
        }
        if (result.isSuccess) {
          logger.info('[Imaging] Mount parked successfully',
              source: 'CapturePanel');
        } else {
          logger.warning('[Imaging] Mount park failed: ${result.message}',
              source: 'CapturePanel');
        }
      }
    } catch (e) {
      logger.error('[Imaging] Error ending session: $e',
          source: 'CapturePanel', fields: {'error': e.toString()});
    }
  }
}
