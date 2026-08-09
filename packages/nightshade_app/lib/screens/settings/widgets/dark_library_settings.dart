import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/file_download_service.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/help/field_help_copy.dart';
import 'settings_widgets.dart';

class DarkLibrarySettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const DarkLibrarySettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<DarkLibrarySettings> createState() =>
      _DarkLibrarySettingsState();
}

class _DarkLibrarySettingsState extends ConsumerState<DarkLibrarySettings> {
  /// Entry id currently streaming to this device, or null. One transfer at
  /// a time keeps the UI honest about progress on a phone-grade link.
  int? _downloadingEntryId;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(darkLibraryEntriesProvider);
    final isRemote = ref.watch(backendProvider) is NetworkBackend;
    final statsAsync = ref.watch(darkLibraryStatsProvider);
    final groupsAsync = ref.watch(darkLibraryGroupsProvider);
    final librarySettingsAsync = ref.watch(darkLibrarySettingsProvider);
    final librarySettings = librarySettingsAsync.valueOrNull;
    final uiState = ref.watch(darkLibraryNotifierProvider);

    return SettingsPage(
      title: 'Dark Library',
      description: 'Manage dark and bias calibration frames',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        // Settings section
        SettingsSection(
          title: 'Auto-Calibration',
          isMobile: widget.isMobile,
          children: [
            if (librarySettings == null)
              SettingRow(
                icon: librarySettingsAsync.hasError
                    ? LucideIcons.alertTriangle
                    : LucideIcons.loader,
                title: librarySettingsAsync.hasError
                    ? 'Could not load dark-library settings'
                    : 'Loading dark-library settings',
                subtitle: librarySettingsAsync.hasError
                    ? '${librarySettingsAsync.error}'
                    : 'Reading settings from the imaging host',
                trailing: librarySettingsAsync.hasError
                    ? IconButton(
                        tooltip: 'Retry',
                        onPressed: () =>
                            ref.invalidate(darkLibrarySettingsProvider),
                        icon: const Icon(LucideIcons.refreshCw),
                      )
                    : const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                isMobile: widget.isMobile,
              ),
            if (librarySettings != null)
              // This is the shared dark, flat, and bias calibration switch.
              SettingRow(
                icon: LucideIcons.zap,
                title: 'Auto-calibrate light frames',
                subtitle:
                    'Apply dark, flat, and bias correction to captured images '
                    'automatically. Same setting as Settings > Calibration.',
                trailing: SettingsSwitch(
                  value: librarySettings.autoCalibrate,
                  onChanged: (value) {
                    return ref
                        .read(darkLibrarySettingsActionsProvider)
                        .setAutoCalibrate(value);
                  },
                ),
                isMobile: widget.isMobile,
              ),
            if (librarySettings != null)
              SettingRow(
                icon: LucideIcons.thermometer,
                title: 'Temperature tolerance',
                helpId: FieldHelpId.darkLibraryMatching,
                subtitle: 'Maximum temperature difference for dark matching',
                trailing: SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 60,
                        child: SettingsDropdown(
                          value: librarySettings.temperatureTolerance
                              .toStringAsFixed(1),
                          items: const [
                            '0.5',
                            '1.0',
                            '1.5',
                            '2.0',
                            '3.0',
                            '5.0'
                          ],
                          onChanged: (value) {
                            return ref
                                .read(darkLibrarySettingsActionsProvider)
                                .setTemperatureTolerance(double.parse(value));
                          },
                          isMobile: widget.isMobile,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '\u00b0C',
                        style: TextStyle(
                          color: NightshadeColors.of(context).textSecondary,
                          fontSize: NightshadeTypography.fontSize13,
                        ),
                      ),
                    ],
                  ),
                ),
                isMobile: widget.isMobile,
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Library statistics
        SettingsSection(
          title: 'Library Statistics',
          isMobile: widget.isMobile,
          children: [
            statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark library stats.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
              ),
              data: (stats) => Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Dark Frames',
                      value: '${stats.darkCount}',
                      icon: LucideIcons.moon,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Bias Frames',
                      value: '${stats.biasCount}',
                      icon: LucideIcons.zap,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Master Darks',
                      value: '${stats.masterCount}',
                      icon: LucideIcons.layers,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Total',
                      value: '${stats.totalEntries}',
                      icon: LucideIcons.database,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Status/Error messages
        if (uiState.statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: NightshadeDecorations.emphasisSurface(
                NightshadeColors.of(context).primary,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info,
                      size: 16, color: NightshadeColors.of(context).primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.statusMessage!,
                      style: TextStyle(
                          color: NightshadeColors.of(context).textPrimary,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14,
                        color: NightshadeColors.of(context).textMuted),
                    onPressed: () => ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .clearStatus(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        if (uiState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: NightshadeDecorations.emphasisSurface(
                NightshadeColors.of(context).error,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 16, color: NightshadeColors.of(context).error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.errorMessage!,
                      style: TextStyle(
                          color: NightshadeColors.of(context).textPrimary,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14,
                        color: NightshadeColors.of(context).textMuted),
                    onPressed: () => ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .clearError(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

        // Library actions
        SettingsSection(
          title: 'Library Management',
          isMobile: widget.isMobile,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    icon: LucideIcons.scan,
                    label: 'Clean Orphans',
                    tooltip:
                        'Remove entries whose files no longer exist on disk',
                    onPressed: uiState.isBusy
                        ? null
                        : () => ref
                            .read(darkLibraryNotifierProvider.notifier)
                            .cleanOrphans(),
                    isLoading: uiState.activeMutation ==
                        DarkLibraryMutation.cleanOrphans,
                  ),
                  _ActionButton(
                    icon: LucideIcons.trash2,
                    label: 'Clear Library',
                    tooltip: 'Remove all entries from the library',
                    onPressed:
                        uiState.isBusy ? null : () => _showClearDialog(context),
                    isDanger: true,
                    isLoading: uiState.activeMutation ==
                        DarkLibraryMutation.clearLibrary,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Frame groups
        SettingsSection(
          title: 'Frame Groups',
          isMobile: widget.isMobile,
          children: [
            groupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark frame groups.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.moon,
                              size: 48,
                              color: NightshadeColors.of(context)
                                  .textMuted
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No dark frames in library',
                            style: TextStyle(
                              color: NightshadeColors.of(context).textMuted,
                              fontSize: NightshadeTypography.fontSize14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capture dark or bias frames to populate the library',
                            style: TextStyle(
                              color: NightshadeColors.of(context)
                                  .textMuted
                                  .withValues(alpha: 0.7),
                              fontSize: NightshadeTypography.fontSize12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final group in groups)
                      _DarkGroupTile(
                        group: group,
                        onCreateMaster: uiState.isBusy
                            ? null
                            : () => _showCreateMasterDialog(context, group),
                        onDeleteGroup: uiState.isBusy
                            ? null
                            : () => _showDeleteGroupDialog(context, group),
                      ),
                  ],
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // All entries list
        SettingsSection(
          title: 'All Entries',
          isMobile: widget.isMobile,
          children: [
            entriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark library entries.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No entries',
                      style: TextStyle(
                          color: NightshadeColors.of(context).textMuted),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final entry in entries)
                      _DarkEntryTile(
                        entry: entry,
                        // Downloading only makes sense against a remote
                        // appliance — locally the file already lives on
                        // this machine (path shown in the delete dialog).
                        downloadable: isRemote,
                        isDownloading: _downloadingEntryId == entry.id,
                        onDownload: _downloadingEntryId != null
                            ? null
                            : () => _downloadEntry(entry),
                        onDelete: uiState.isBusy
                            ? null
                            : () => _showDeleteEntryDialog(context, entry),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showClearDialog(BuildContext context) {
    final authority = ref.read(backendProvider);
    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Clear Dark Library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Remove all entries from the dark library?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) =>
                    setDialogState(() => deleteFiles = v ?? false),
                title: const Text('Also delete files from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!_isCurrentAuthority(authority)) {
                  _cancelForAuthorityChange(ctx);
                  return;
                }
                Navigator.pop(ctx);
                unawaited(
                  ref
                      .read(darkLibraryNotifierProvider.notifier)
                      .clearLibrary(deleteFiles: deleteFiles),
                );
              },
              child: Text('Clear',
                  style: TextStyle(color: NightshadeColors.of(context).error)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateMasterDialog(
    BuildContext context,
    DarkGroupKey group,
  ) async {
    final authority = ref.read(backendProvider);
    final controller = TextEditingController();
    String? pathError;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Create Master Dark'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Median-combine all ${group.frameType} frames with:\n'
                  '${group.exposureTime}s / gain ${group.gain} / offset '
                  '${group.offset} / ${group.binX}x${group.binY}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  onChanged: (_) {
                    if (pathError != null) {
                      setDialogState(() => pathError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Output file path',
                    hintText: '/path/to/master_dark.fits',
                    errorText: pathError,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final path = controller.text.trim();
                  if (path.isEmpty) {
                    setDialogState(
                      () => pathError = 'Enter an output file path',
                    );
                    return;
                  }
                  if (!_isCurrentAuthority(authority)) {
                    _cancelForAuthorityChange(ctx);
                    return;
                  }
                  Navigator.pop(ctx);
                  unawaited(
                    ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .createMasterDark(
                          exposureTime: group.exposureTime,
                          gain: group.gain,
                          offset: group.offset,
                          binX: group.binX,
                          binY: group.binY,
                          outputPath: path,
                          frameType: group.frameType,
                        ),
                  );
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showDeleteGroupDialog(BuildContext context, DarkGroupKey group) {
    final authority = ref.read(backendProvider);
    bool deleteFiles = false;
    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delete all ${group.frameType} frames with:\n'
                '${group.exposureTime}s / gain ${group.gain} / offset '
                '${group.offset} / ${group.binX}x${group.binY}?',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: isDeleting
                    ? null
                    : (v) => setDialogState(() => deleteFiles = v ?? false),
                title: const Text('Also delete files from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      if (!_isCurrentAuthority(authority)) {
                        _cancelForAuthorityChange(ctx);
                        return;
                      }
                      setDialogState(() => isDeleting = true);
                      try {
                        final removed = await ref
                            .read(darkLibraryNotifierProvider.notifier)
                            .deleteGroup(
                              group,
                              deleteFiles: deleteFiles,
                            );
                        if (!ctx.mounted) return;
                        if (!_isCurrentAuthority(authority)) {
                          Navigator.pop(ctx);
                          return;
                        }
                        Navigator.pop(ctx);
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Deleted $removed ${group.frameType} '
                              '${removed == 1 ? 'entry' : 'entries'}.',
                            ),
                          ),
                        );
                      } catch (error) {
                        if (!ctx.mounted) return;
                        setDialogState(() => isDeleting = false);
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text('Failed to delete group: $error'),
                          ),
                        );
                      }
                    },
              child: isDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Delete',
                      style: TextStyle(
                        color: NightshadeColors.of(context).error,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteEntryDialog(BuildContext context, DarkLibraryEntry entry) {
    final authority = ref.read(backendProvider);
    bool deleteFile = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delete this ${entry.frameType} frame?'),
              const SizedBox(height: 4),
              Text(
                entry.filePath,
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: NightshadeColors.of(context).textMuted),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFile,
                onChanged: (v) => setDialogState(() => deleteFile = v ?? false),
                title: const Text('Also delete file from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!_isCurrentAuthority(authority)) {
                  _cancelForAuthorityChange(ctx);
                  return;
                }
                Navigator.pop(ctx);
                unawaited(
                  ref
                      .read(darkLibraryNotifierProvider.notifier)
                      .deleteEntry(entry.id, deleteFile: deleteFile),
                );
              },
              child: Text('Delete',
                  style: TextStyle(color: NightshadeColors.of(context).error)),
            ),
          ],
        ),
      ),
    );
  }

  /// Stream the on-disk file for [entry] off the appliance to this device
  /// (share sheet on mobile, save picker on desktop) via
  /// `GET /api/calibration/darks/{id}/download`.
  Future<void> _downloadEntry(DarkLibraryEntry entry) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend || _downloadingEntryId != null) return;
    setState(() => _downloadingEntryId = entry.id);
    try {
      final fileName = entry.filePath.split('/').last.split('\\').last;
      final outcome = await downloadFileToDevice(
        fileName: fileName.isEmpty ? 'dark-${entry.id}.fits' : fileName,
        tempKey: 'dark-${entry.id}',
        fetch: (localPath, onProgress) =>
            backend.downloadDark(entry.id, localPath, onProgress: onProgress),
      );
      if (!mounted || !_isCurrentAuthority(backend)) return;
      switch (outcome.status) {
        case FileDownloadStatus.saved:
          context.showSuccessSnackBar('Saved to ${outcome.savedPath}');
        case FileDownloadStatus.shared:
          context.showSuccessSnackBar('Calibration frame ready to share');
        case FileDownloadStatus.cancelled:
          break;
        case FileDownloadStatus.failed:
          context.showErrorSnackBar(outcome.error ?? 'Download failed');
      }
    } finally {
      if (mounted) setState(() => _downloadingEntryId = null);
    }
  }

  bool _isCurrentAuthority(NightshadeBackend authority) =>
      identical(ref.read(backendProvider), authority);

  void _cancelForAuthorityChange(BuildContext dialogContext) {
    if (dialogContext.mounted) Navigator.pop(dialogContext);
    if (mounted) {
      context.showErrorSnackBar(
        'Connected rig changed; dark-library action cancelled',
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Expanded(
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDanger;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.isDanger = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NightshadeButton(
        onPressed: onPressed,
        icon: icon,
        label: label,
        variant: isDanger ? ButtonVariant.destructive : ButtonVariant.outline,
        isLoading: isLoading,
      ),
    );
  }
}

class _DarkGroupTile extends StatelessWidget {
  final DarkGroupKey group;
  final VoidCallback? onCreateMaster;
  final VoidCallback? onDeleteGroup;

  const _DarkGroupTile({
    required this.group,
    required this.onCreateMaster,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isD = group.frameType == 'dark';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isD ? LucideIcons.moon : LucideIcons.zap,
              size: 18,
              color: isD ? colors.primary : colors.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${group.frameType.toUpperCase()} - ${group.exposureTime}s',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gain ${group.gain} | Offset ${group.offset} | '
                    '${group.binX}x${group.binY}',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(LucideIcons.layers, size: 16, color: colors.primary),
              tooltip: 'Create master dark',
              onPressed: onCreateMaster,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
              tooltip: 'Delete group',
              onPressed: onDeleteGroup,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkEntryTile extends StatelessWidget {
  final DarkLibraryEntry entry;

  /// Whether the download affordance is rendered at all (remote host only).
  final bool downloadable;
  final bool isDownloading;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _DarkEntryTile({
    required this.entry,
    this.downloadable = false,
    this.isDownloading = false,
    this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMaster = entry.masterDarkPath != null;
    final isDark = entry.frameType == 'dark';

    // Extract just the filename from the path
    final fileName = entry.filePath.split('/').last.split('\\').last;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMaster
            ? NightshadeDecorations.tintedBadge(
                colors.primary,
                borderRadius: BorderRadius.zero,
              ).color
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMaster
                ? LucideIcons.layers
                : isDark
                    ? LucideIcons.moon
                    : LucideIcons.zap,
            size: 14,
            color: isMaster
                ? colors.primary
                : isDark
                    ? colors.textSecondary
                    : colors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMaster ? 'MASTER: $fileName' : fileName,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    fontWeight: isMaster ? FontWeight.w600 : FontWeight.w400,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.exposureTime}s | '
                  'Gain ${entry.gain} | '
                  '${entry.binX}x${entry.binY}'
                  '${entry.temperature != null ? ' | ${entry.temperature!.toStringAsFixed(1)}\u00b0C' : ''}'
                  '${isMaster ? ' | ${entry.masterFrameCount} frames' : ''}',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (downloadable) ...[
            isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: Icon(
                      LucideIcons.download,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    onPressed: onDownload,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Download to this device',
                  ),
            const SizedBox(width: 10),
          ],
          IconButton(
            icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete entry',
          ),
        ],
      ),
    );
  }
}
