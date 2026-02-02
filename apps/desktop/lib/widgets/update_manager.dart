import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Widget that manages the update UI flow.
///
/// This widget should be placed near the root of the app and will show
/// update dialogs when updates are available.
class UpdateManager extends ConsumerStatefulWidget {
  final Widget child;

  const UpdateManager({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<UpdateManager> createState() => _UpdateManagerState();
}

class _UpdateManagerState extends ConsumerState<UpdateManager> {
  bool _hasShownUpdateDialog = false;
  OverlayEntry? _bannerOverlay;
  late final Stream<LanPushEvent> _lanPushStream;
  static const _disabledUpdatesLog =
      '[UpdateManager] Update server not configured, skipping update checks';

  bool _isUpdateConfigured() {
    final state = ref.read(updateProvider);
    final url = state.updateServerUrl;
    return url != null && url.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    // Check for staged updates immediately (from previous LAN push)
    Future.delayed(const Duration(seconds: 1), _checkForStagedUpdate);

    // Check for updates on startup after a short delay
    Future.delayed(const Duration(seconds: 3), _checkForUpdates);

    // Listen to LAN push events
    _lanPushStream = LanPushNotifier.stream;
    _lanPushStream.listen(_onLanPushEvent);
  }

  Future<void> _checkForStagedUpdate() async {
    if (!mounted) return;
    if (!_isUpdateConfigured()) {
      print(_disabledUpdatesLog);
      return;
    }

    print('[UpdateManager] Checking for staged updates...');
    final updateNotifier = ref.read(updateProvider.notifier);
    await updateNotifier.checkStagedUpdate();

    final state = ref.read(updateProvider);
    if (state.status == UpdateStatus.staged) {
      print('[UpdateManager] Found staged update: ${state.availableUpdate?.version}');
      _showLanPushBannerDirect(state.availableUpdate?.version ?? 'Unknown');
    } else {
      print('[UpdateManager] No staged update found');
    }
  }

  void _onLanPushEvent(LanPushEvent event) {
    if (!mounted) return;
    if (!_isUpdateConfigured()) return;

    switch (event) {
      case LanPushReceivedEvent(:final manifest, :final stagingPath):
        print('[UpdateManager] LAN push received: ${manifest.version}');
        // Update the provider state so applyUpdate() works
        ref.read(updateProvider.notifier).setStagedFromLanPush(manifest, stagingPath);
        _showLanPushBannerDirect(manifest.version);
        break;
      case LanPushProgressEvent(:final progress, :final message):
        // Could show progress indicator if desired
        break;
      case LanPushErrorEvent(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('LAN push error: $error'),
            backgroundColor: Colors.red,
          ),
        );
        break;
    }
  }

  void _showLanPushBannerDirect(String version) {
    if (!mounted) return;

    _removeBanner();

    _bannerOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        right: 16,
        child: UpdateReceivedBanner(
          version: version,
          source: 'LAN Push',
          onRestart: () {
            _removeBanner();
            ref.read(updateProvider.notifier).applyUpdate();
          },
          onDismiss: _removeBanner,
        ),
      ),
    );

    final overlay = Overlay.of(context);
    overlay.insert(_bannerOverlay!);
    print('[UpdateManager] Banner inserted into overlay');

    // Auto-dismiss after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) _removeBanner();
    });
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    if (!_isUpdateConfigured()) {
      print(_disabledUpdatesLog);
      return;
    }

    final updateNotifier = ref.read(updateProvider.notifier);
    await updateNotifier.checkForUpdates();
  }

  void _showUpdateAvailableDialog(UpdateState state) {
    if (_hasShownUpdateDialog) return;
    _hasShownUpdateDialog = true;

    final manifest = state.availableUpdate!;
    UpdateAvailableDialog.show(
      context,
      currentVersion: state.currentVersion,
      newVersion: manifest.version,
      releaseNotes: manifest.releaseNotes,
      downloadSizeMb: (manifest.compressedSize / 1024 / 1024).round(),
      onUpdate: () {
        ref.read(updateProvider.notifier).downloadUpdate();
      },
      onSkip: () {
        ref.read(updateProvider.notifier).skipUpdate();
      },
      onLater: () {
        // Just dismiss, will check again next launch
      },
    );
  }

  void _showDownloadProgressDialog(UpdateState state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final currentState = ref.watch(updateProvider);
          if (currentState.status == UpdateStatus.staged) {
            // Download complete, close this dialog and show ready dialog
            Navigator.of(context).pop();
            Future.microtask(() => _showUpdateReadyDialog(currentState));
            return const SizedBox.shrink();
          }

          return UpdateDownloadDialog(
            version: currentState.availableUpdate?.version ?? '',
            progress: currentState.downloadProgress,
            downloadedMb: (currentState.downloadedBytes / 1024 / 1024).round(),
            totalMb: (currentState.totalBytes / 1024 / 1024).round(),
            status: 'Downloading...',
            onCancel: () {
              ref.read(updateProvider.notifier).cancelDownload();
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }

  void _showUpdateReadyDialog(UpdateState state) {
    // Check if a sequence is currently running
    final sequencerState = ref.read(sequenceExecutionStateProvider);
    final isSessionActive = sequencerState == SequenceExecutionState.running ||
        sequencerState == SequenceExecutionState.paused;

    UpdateReadyDialog.show(
      context,
      version: state.availableUpdate?.version ?? '',
      isSessionActive: isSessionActive,
      onRestartNow: () {
        ref.read(updateProvider.notifier).applyUpdate();
      },
      onRestartLater: () {
        // Dismiss, update will be applied on next restart
      },
    );
  }

  void _showLanPushBanner(UpdateState state) {
    _removeBanner();

    _bannerOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        right: 16,
        child: UpdateReceivedBanner(
          version: state.availableUpdate?.version ?? '',
          source: 'LAN Push',
          onRestart: () {
            _removeBanner();
            ref.read(updateProvider.notifier).applyUpdate();
          },
          onDismiss: _removeBanner,
        ),
      ),
    );

    Overlay.of(context).insert(_bannerOverlay!);

    // Auto-dismiss after 30 seconds
    Future.delayed(const Duration(seconds: 30), _removeBanner);
  }

  void _removeBanner() {
    try {
      if (_bannerOverlay?.mounted == true) {
        _bannerOverlay?.remove();
      }
    } catch (e) {
      print('[UpdateManager] Error removing banner: $e');
    }
    _bannerOverlay = null;
  }

  @override
  void dispose() {
    _removeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateProvider, (previous, next) {
      // Handle state transitions
      if (previous?.status != next.status) {
        switch (next.status) {
          case UpdateStatus.available:
            _showUpdateAvailableDialog(next);
            break;
          case UpdateStatus.downloading:
            if (previous?.status != UpdateStatus.downloading) {
              _showDownloadProgressDialog(next);
            }
            break;
          case UpdateStatus.staged:
            // Check if this was from LAN push
            if (next.stagingPath?.contains('lan_push') == true) {
              _showLanPushBanner(next);
            } else if (previous?.status == UpdateStatus.downloading) {
              // Will be handled by download dialog
            } else {
              _showUpdateReadyDialog(next);
            }
            break;
          case UpdateStatus.error:
            if (next.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Update error: ${next.errorMessage}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          default:
            break;
        }
      }
    });

    return widget.child;
  }
}

/// Convenience method to trigger manual update check
Future<void> checkForUpdatesManually(WidgetRef ref) async {
  final notifier = ref.read(updateProvider.notifier);
  await notifier.checkForUpdates();
}

/// Get current update state
UpdateState getUpdateState(WidgetRef ref) {
  return ref.read(updateProvider);
}
