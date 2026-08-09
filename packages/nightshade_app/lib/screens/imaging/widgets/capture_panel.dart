import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../services/mount_command_service.dart';
import '../../../utils/confirm_dialog.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/help/field_help_copy.dart';
import '../../../widgets/remote_directory_picker_dialog.dart';
import 'panel_widgets.dart';

// Provider for park mount on end setting
final parkMountOnEndProvider = StateProvider<bool>((ref) => false);

typedef CaptureSavePathPicker = Future<String?> Function(
  BuildContext context, {
  required bool isRemote,
  required String? initialPath,
});

typedef CaptureSavePathWriter = Future<void> Function(String path);

Future<String?> _pickCaptureSavePath(
  BuildContext context, {
  required bool isRemote,
  required String? initialPath,
}) {
  if (isRemote) {
    return RemoteDirectoryPickerDialog.show(
      context,
      title: 'Select host capture folder',
      initialPath: initialPath,
    );
  }
  return getDirectoryPath(
    confirmButtonText: 'Select',
    initialDirectory: initialPath,
  );
}

final captureSavePathPickerProvider =
    Provider<CaptureSavePathPicker>((ref) => _pickCaptureSavePath);

final captureSavePathWriterProvider = Provider<CaptureSavePathWriter>((ref) {
  return ref.read(appSettingsProvider.notifier).setImageOutputPath;
});

class CapturePanel extends ConsumerWidget {
  final NightshadeColors colors;

  /// Duration / Snapshot / Loop cluster, pinned above the scrolling settings.
  ///
  /// Supplied only by the layouts that omit the persistent bottom capture bar
  /// (the landscape side-by-side split, where that bar would overflow the short
  /// height). This panel used to carry no exposure-start control at all, so in
  /// that band the Imaging screen had no shutter anywhere — the comment
  /// suppressing the bar claimed these buttons were "already visible beside the
  /// image", and they were not.
  final Widget? captureActions;

  const CapturePanel({
    super.key,
    required this.colors,
    this.captureActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final namingPattern = ref.watch(namingPatternProvider);
    final sessionState = ref.watch(sessionStateProvider);
    final sessionImages = ref.watch(recentSessionFramesProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final hostSuffix = isRemoteMode ? ' (host)' : '';

    // The Session card's "Captured" and "Integration" lines must come from the
    // SAME record or they can contradict each other. `recentSessionFramesProvider`
    // only holds frames captured in THIS app run, so after resuming an
    // interrupted session the card read "Captured 0 frames" directly above
    // "Integration 40m 0s". SessionService.recoverSession restores
    // completedExposures from the DB row alongside totalIntegrationSecs, so
    // prefer it whenever a session row is open; the in-run frame list is only
    // the fallback for captures taken with no session (dbSessionId == null).
    final capturedCount = sessionState.dbSessionId != null
        ? sessionState.completedExposures
        : sessionImages.length;

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
          if (captureActions != null) ...[
            captureActions!,
            const SizedBox(height: 20),
          ],
          // Exposure Settings
          PanelSection(
            title: 'Exposure Settings$hostSuffix',
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
                      ref.read(manualExposureSettingsUpdaterProvider).update(
                            exposureSettings.copyWith(exposureTime: parsed),
                          );
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownRow(
                  label: 'Frame Type',
                  helpId: FieldHelpId.captureFrameType,
                  value: exposureSettings.frameType.displayName,
                  items: FrameType.values.map((t) => t.displayName).toList(),
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final type = FrameType.values.firstWhere(
                        (t) => t.displayName == value,
                        orElse: () => FrameType.light,
                      );
                      ref.read(manualExposureSettingsUpdaterProvider).update(
                            exposureSettings.copyWith(frameType: type),
                          );
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownRow(
                  label: 'Binning',
                  helpId: FieldHelpId.captureBinning,
                  value: currentBinning,
                  items: binningOptions,
                  colors: colors,
                  onChanged: (value) {
                    if (value != null) {
                      final parts = value.split('x');
                      ref.read(manualExposureSettingsUpdaterProvider).update(
                            exposureSettings.copyWith(
                              binningX: int.parse(parts[0]),
                              binningY: int.parse(parts[1]),
                            ),
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
                InputRow(
                  label: 'Format',
                  value: '$kCaptureImageFormat · $kCaptureBitDepth',
                  colors: colors,
                ),
                const SizedBox(height: 12),
                // Remote paths live on the imaging host; browse via the API.
                InputRow(
                  label: isRemoteMode ? 'Save Path (Host)' : 'Save Path',
                  // An unset capture directory persists as '.' — surface it
                  // as an actionable prompt instead of a bare dot.
                  value: namingPattern.baseDir.trim().isEmpty ||
                          namingPattern.baseDir.trim() == '.'
                      ? 'Not set — choose a folder'
                      : namingPattern.baseDir,
                  colors: colors,
                  trailing: CaptureSavePathButton(
                    colors: colors,
                    currentPath: namingPattern.baseDir,
                    isRemote: isRemoteMode,
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
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary)),
                    Flexible(
                      child: Text(
                        '$capturedCount '
                        '${capturedCount == 1 ? 'frame' : 'frames'}',
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Integration',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary)),
                    Flexible(
                      child: Text(
                        _formatDuration(sessionState.totalIntegrationSecs),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.textPrimary),
                      ),
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
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textSecondary)),
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
                            style: NightshadeTypography.labelSm
                                .copyWith(color: colors.success),
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
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textSecondary)),
                      Text(
                        sessionState.duration != null
                            ? _formatSessionDuration(sessionState.duration!)
                            : '--:--:--',
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      // Ad-hoc Snapshot/Loop captures never open a database
                      // session — only the sequencer calls startSession — so
                      // gating this button on dbSessionId made it assert "no
                      // active session" while the counter above it reported a
                      // real, non-zero frame count. Those frames are not
                      // stranded: they are persisted as standalone rows and
                      // Analytics renders them under "Quick Capture". Route
                      // there instead of denying they exist, and when there is
                      // genuinely nothing to show, disable the button rather
                      // than offer an action that cannot work.
                      child: SmallButton(
                        label: sessionState.dbSessionId != null
                            ? 'View Gallery'
                            : 'View Quick Captures',
                        icon: LucideIcons.galleryHorizontal,
                        colors: colors,
                        isEnabled: sessionState.dbSessionId != null ||
                            sessionImages.isNotEmpty,
                        onTap: () {
                          final sessionId = sessionState.dbSessionId;
                          if (sessionId != null) {
                            context.push('/session-review?session=$sessionId');
                          } else {
                            context.push('/analytics?tab=session');
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SmallButton(
                        label: 'Clear Session',
                        icon: NightshadeIcons.delete,
                        isOutline: true,
                        colors: colors,
                        // Confirm before wiping: clearing drops the in-memory
                        // frame strip and integration stats shown here, which
                        // cannot be reconstructed from the UI. Captured files
                        // on disk are untouched.
                        onTap: () async {
                          final confirmed = await ConfirmDialog.show(
                            context: context,
                            title: 'Clear Session View?',
                            message: 'This clears the session frame list and '
                                'integration stats shown here. Your captured '
                                'files stay on disk.',
                            confirmLabel: 'Clear',
                            isDestructive: true,
                          );
                          if (!confirmed || !context.mounted) return;
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
                      icon: NightshadeIcons.stopCircle,
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
    var isEnding = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !isEnding,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(NightshadeIcons.stopCircle, color: colors.warning),
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
                NightshadeCard(
                  variant: CardVariant.subtle,
                  padding: const EdgeInsets.all(12),
                  borderRadius: NightshadeTokens.radiusInline8,
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
                          Text(
                              _formatDuration(
                                  sessionState.totalIntegrationSecs),
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
                                  ? _formatSessionDuration(
                                      sessionState.duration!)
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
                          fontSize: NightshadeTypography.fontSize14,
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
                onPressed:
                    isEnding ? null : () => Navigator.of(dialogContext).pop(),
                label: 'Cancel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
              NightshadeButton(
                onPressed: isEnding
                    ? null
                    : () async {
                        setDialogState(() => isEnding = true);
                        final ended = await _endSession(ref, context);
                        if (!dialogContext.mounted) return;
                        if (ended) {
                          Navigator.of(dialogContext).pop();
                        } else {
                          setDialogState(() => isEnding = false);
                        }
                      },
                label: 'End Session',
                variant: ButtonVariant.destructive,
                size: ButtonSize.small,
                isLoading: isEnding,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _endSession(WidgetRef ref, BuildContext context) async {
    final logger = ref.read(loggingServiceProvider);
    try {
      final parkOnEnd = ref.read(parkMountOnEndProvider);

      // End the session
      await ref.read(sessionStateProvider.notifier).endSession();

      // Park mount if requested (service handles connection check)
      if (parkOnEnd) {
        try {
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
        } catch (e) {
          logger.error('[Imaging] Session ended but mount park failed: $e',
              source: 'CapturePanel', fields: {'error': e.toString()});
          if (context.mounted) {
            context.showErrorSnackBar('Session ended, but parking failed: $e');
          }
        }
      }
      return true;
    } catch (e) {
      logger.error('[Imaging] Error ending session: $e',
          source: 'CapturePanel', fields: {'error': e.toString()});
      if (context.mounted) {
        context.showErrorSnackBar('Failed to end session: $e');
      }
      return false;
    }
  }
}

/// Host-authoritative browse action for the capture output folder.
///
/// The picker can remain open while the operator reconnects to another host.
/// Its result therefore belongs to the backend that opened it, not whichever
/// backend happens to be active when the platform dialog eventually returns.
class CaptureSavePathButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final String currentPath;
  final bool isRemote;

  const CaptureSavePathButton({
    super.key,
    required this.colors,
    required this.currentPath,
    required this.isRemote,
  });

  @override
  ConsumerState<CaptureSavePathButton> createState() =>
      _CaptureSavePathButtonState();
}

class _CaptureSavePathButtonState extends ConsumerState<CaptureSavePathButton> {
  bool _busy = false;
  int _operationGeneration = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(backendProvider);
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (_busy && previous != null && !identical(previous, next)) {
        _operationGeneration++;
        setState(() => _busy = false);
      }
    });

    return IconButton(
      tooltip: widget.isRemote
          ? 'Choose host capture folder'
          : 'Choose capture folder',
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      onPressed: _busy ? null : _choosePath,
      icon: _busy
          ? const NightshadeCircularProgress(
              value: 0,
              indeterminate: true,
              size: 14,
            )
          : Icon(
              NightshadeIcons.folderOpen,
              size: 14,
              color: widget.colors.textSecondary,
            ),
    );
  }

  Future<void> _choosePath() async {
    final generation = ++_operationGeneration;
    final authority = ref.read(backendProvider);
    final initialPath = widget.currentPath.trim();
    setState(() => _busy = true);
    try {
      final result = await ref.read(captureSavePathPickerProvider)(
        context,
        isRemote: widget.isRemote,
        initialPath: initialPath.isEmpty ? null : initialPath,
      );
      if (result == null || !_isCurrent(generation, authority)) return;

      await ref.read(captureSavePathWriterProvider)(result);
    } catch (error) {
      if (!mounted ||
          generation != _operationGeneration ||
          !identical(ref.read(backendProvider), authority)) {
        return;
      }
      context.showErrorSnackBar('Could not update the capture folder: $error');
    } finally {
      if (mounted && generation == _operationGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isCurrent(int generation, NightshadeBackend authority) {
    return mounted &&
        generation == _operationGeneration &&
        identical(ref.read(backendProvider), authority);
  }
}
