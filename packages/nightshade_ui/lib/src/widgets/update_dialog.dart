import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../components/nightshade_button.dart';
import '../utils/responsive_utils.dart';

/// Dialog shown when an update is available.
class UpdateAvailableDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final String? releaseNotes;
  final int downloadSizeMb;
  final VoidCallback onUpdate;
  final VoidCallback onSkip;
  final VoidCallback onLater;

  const UpdateAvailableDialog({
    super.key,
    required this.currentVersion,
    required this.newVersion,
    this.releaseNotes,
    required this.downloadSizeMb,
    required this.onUpdate,
    required this.onSkip,
    required this.onLater,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentVersion,
    required String newVersion,
    String? releaseNotes,
    required int downloadSizeMb,
    required VoidCallback onUpdate,
    required VoidCallback onSkip,
    required VoidCallback onLater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateAvailableDialog(
        currentVersion: currentVersion,
        newVersion: newVersion,
        releaseNotes: releaseNotes,
        downloadSizeMb: downloadSizeMb,
        onUpdate: () {
          Navigator.pop(context);
          onUpdate();
        },
        onSkip: () {
          Navigator.pop(context);
          onSkip();
        },
        onLater: () {
          Navigator.pop(context);
          onLater();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.download,
              color: colors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 480,
          minWidth: 320,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Version',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentVersion,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.arrowRight,
                    color: colors.primary,
                    size: 20,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'New Version',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          newVersion,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Download size
            Row(
              children: [
                Icon(
                  LucideIcons.hardDrive,
                  color: colors.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Download size: ~$downloadSizeMb MB',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            // Release notes
            if (releaseNotes != null) ...[
              const SizedBox(height: 16),
              Text(
                'What\'s New:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onSkip,
          style: TextButton.styleFrom(
            foregroundColor: colors.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Skip This Version'),
        ),
        TextButton(
          onPressed: onLater,
          style: TextButton.styleFrom(
            foregroundColor: colors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Later'),
        ),
        NightshadeButton(
          label: 'Update Now',
          icon: LucideIcons.download,
          onPressed: onUpdate,
          variant: ButtonVariant.primary,
          size: ButtonSize.medium,
        ),
      ],
    );
  }
}

/// Dialog shown during update download with progress.
class UpdateDownloadDialog extends StatelessWidget {
  final String version;
  final double progress;
  final int downloadedMb;
  final int totalMb;
  final String status;
  final VoidCallback? onCancel;

  const UpdateDownloadDialog({
    super.key,
    required this.version,
    required this.progress,
    required this.downloadedMb,
    required this.totalMb,
    required this.status,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final percent = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(colors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Downloading Update',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 400,
          minWidth: 300,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version $version',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colors.border,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            ),

            const SizedBox(height: 12),

            // Progress details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$percent% ($downloadedMb / $totalMb MB)',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (onCancel != null)
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: colors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

/// Dialog shown when update is ready to install.
class UpdateReadyDialog extends StatelessWidget {
  final String version;
  final bool isSessionActive;
  final VoidCallback onRestartNow;
  final VoidCallback onRestartLater;

  const UpdateReadyDialog({
    super.key,
    required this.version,
    required this.isSessionActive,
    required this.onRestartNow,
    required this.onRestartLater,
  });

  static Future<void> show(
    BuildContext context, {
    required String version,
    required bool isSessionActive,
    required VoidCallback onRestartNow,
    required VoidCallback onRestartLater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateReadyDialog(
        version: version,
        isSessionActive: isSessionActive,
        onRestartNow: () {
          Navigator.pop(context);
          onRestartNow();
        },
        onRestartLater: () {
          Navigator.pop(context);
          onRestartLater();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.success.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.checkCircle,
              color: colors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update Ready',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 420,
          minWidth: 320,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version $version has been downloaded and is ready to install.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            if (isSessionActive) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      color: colors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'An imaging session is in progress. It\'s recommended to wait until the session completes before restarting.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              'Nightshade will restart to complete the installation.',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onRestartLater,
          style: TextButton.styleFrom(
            foregroundColor: colors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('Restart Later'),
        ),
        NightshadeButton(
          label: isSessionActive ? 'Restart Anyway' : 'Restart Now',
          icon: LucideIcons.refreshCw,
          onPressed: onRestartNow,
          variant: isSessionActive ? ButtonVariant.outline : ButtonVariant.primary,
          size: ButtonSize.medium,
        ),
      ],
    );
  }
}

/// Small notification banner for LAN push updates received.
class UpdateReceivedBanner extends StatelessWidget {
  final String version;
  final String source;
  final VoidCallback onRestart;
  final VoidCallback onDismiss;

  const UpdateReceivedBanner({
    super.key,
    required this.version,
    required this.source,
    required this.onRestart,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.download,
                color: colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update Received',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Version $version from $source',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                'Later',
                style: TextStyle(color: colors.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            NightshadeButton(
              label: 'Restart',
              icon: LucideIcons.refreshCw,
              onPressed: onRestart,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }
}
