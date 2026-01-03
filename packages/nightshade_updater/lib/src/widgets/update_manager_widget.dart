import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../nightshade_updater.dart';

/// Widget that manages the update UI flow.
///
/// This widget should be placed inside MaterialApp's builder. It uses
/// a Stack-based approach to show update banners (no Overlay required).
class UpdateManagerWidget extends ConsumerStatefulWidget {
  final Widget child;

  const UpdateManagerWidget({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<UpdateManagerWidget> createState() => _UpdateManagerWidgetState();
}

class _UpdateManagerWidgetState extends ConsumerState<UpdateManagerWidget> {
  bool _hasShownUpdateDialog = false;
  bool _showingBanner = false;
  String _bannerVersion = '';
  String? _errorMessage;
  late final Stream<LanPushEvent> _lanPushStream;

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

    switch (event) {
      case LanPushReceivedEvent(:final manifest, :final stagingPath):
        print('[UpdateManager] LAN push received: ${manifest.version}');
        // Update provider state so applyUpdate() works
        ref.read(updateProvider.notifier).setStagedFromLanPush(manifest, stagingPath);
        _showLanPushBannerDirect(manifest.version);
        break;
      case LanPushProgressEvent(:final progress, :final message):
        // Could show progress indicator if desired
        break;
      case LanPushErrorEvent(:final error):
        print('[UpdateManager] LAN push error: $error');
        _showErrorBanner('LAN push error: $error');
        break;
    }
  }

  void _showLanPushBannerDirect(String version) {
    if (!mounted) return;

    print('[UpdateManager] Showing banner for version: $version');
    setState(() {
      _showingBanner = true;
      _bannerVersion = version;
    });

    // Auto-dismiss after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted && _showingBanner) {
        setState(() => _showingBanner = false);
      }
    });
  }

  void _hideBanner() {
    if (mounted) {
      setState(() {
        _showingBanner = false;
        _errorMessage = null;
      });
    }
  }

  void _showErrorBanner(String error) {
    if (!mounted) return;
    setState(() {
      _showingBanner = true;
      _errorMessage = error;
    });

    // Auto-dismiss after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _errorMessage != null) {
        setState(() => _errorMessage = null);
      }
    });
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;

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
            onCancel: null,
          );
        },
      ),
    );
  }

  void _showUpdateReadyDialog(UpdateState state) {
    UpdateReadyDialog.show(
      context,
      version: state.availableUpdate?.version ?? '',
      isSessionActive: false,
      onRestartNow: () {
        ref.read(updateProvider.notifier).applyUpdate();
      },
      onRestartLater: () {
        // Dismiss, update will be applied on next restart
      },
    );
  }

  @override
  void dispose() {
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
            // If banner is already showing (from LAN push), don't show dialog
            if (_showingBanner) {
              print('[UpdateManager] Banner already showing, skipping dialog');
              break;
            }
            // If came from downloading, dialog handles it
            if (previous?.status == UpdateStatus.downloading) {
              // Will be handled by download dialog
            } else {
              // For non-LAN push staged updates, show banner instead of dialog
              // (dialogs don't work in MaterialApp.builder context)
              _showLanPushBannerDirect(next.availableUpdate?.version ?? 'Unknown');
            }
            break;
          case UpdateStatus.error:
            if (next.errorMessage != null) {
              print('[UpdateManager] Error: ${next.errorMessage}');
              // Show error in banner instead of snackbar (more reliable in builder context)
              _showErrorBanner(next.errorMessage!);
            }
            break;
          default:
            break;
        }
      }
    });

    // Use Stack to show banner without needing Overlay
    return Stack(
      children: [
        widget.child,
        // Show error banner
        if (_errorMessage != null)
          Positioned(
            top: 80,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 350),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _errorMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Show update banner
        if (_showingBanner && _errorMessage == null)
          Positioned(
            top: 80,
            right: 16,
            width: 320, // Fixed width to avoid unbounded constraints
            child: Material(
              color: Colors.transparent,
              child: UpdateReceivedBanner(
                version: _bannerVersion,
                source: 'LAN Push',
                onRestart: () {
                  _hideBanner();
                  ref.read(updateProvider.notifier).applyUpdate();
                },
                onDismiss: _hideBanner,
              ),
            ),
          ),
      ],
    );
  }
}
