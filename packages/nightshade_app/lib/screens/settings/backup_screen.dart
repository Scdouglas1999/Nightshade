import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/snackbar_helper.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isCreatingBackup = false;
  bool _isRestoring = false;
  bool _isLoadingBackups = true;
  List<_BackupEntry> _availableBackups = const [];

  @override
  void initState() {
    super.initState();
    _loadAvailableBackups();
  }

  Future<void> _loadAvailableBackups() async {
    setState(() => _isLoadingBackups = true);
    try {
      final backend = ref.read(backendProvider);
      final entries = backend is NetworkBackend
          ? (await backend.listBackups()).map(_BackupEntry.fromRemote).toList()
          : await Future.wait(
              (await ref.read(backupServiceProvider).listBackups())
                  .map(_BackupEntry.fromLocalFile),
            );
      if (!mounted) return;
      setState(() {
        _availableBackups = entries;
        _isLoadingBackups = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBackups = false);
      context.showErrorSnackBar('Failed to load backups: $e');
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isCreatingBackup = true);
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final result = await backend.createBackup();
        if ((result['status'] as String?) != 'created') {
          throw Exception(result['error'] ?? 'Backup failed');
        }
      } else {
        final result = await ref.read(backupServiceProvider).createBackup();
        if (!result.success) {
          throw Exception(result.errorMessage ?? 'Backup failed');
        }
      }

      if (!mounted) return;
      context.showSuccessSnackBar('Backup created successfully');
      await _loadAvailableBackups();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Error creating backup: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreatingBackup = false);
      }
    }
  }

  Future<void> _restoreBackup(_BackupEntry backup) async {
    final confirmed = await ConfirmDialog.restore(
      context: context,
      backupName: backup.fileName,
    );
    if (!confirmed) return;

    setState(() => _isRestoring = true);
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final result = await backend.restoreBackup(backup.filePath);
        if ((result['status'] as String?) != 'restored') {
          throw Exception(result['error'] ?? 'Restore failed');
        }
        final restored = result['itemsRestored'] as int? ?? 0;
        if (!mounted) return;
        context.showSuccessSnackBar('Restored $restored items successfully');
      } else {
        final result = await ref.read(backupServiceProvider).restoreBackup(
              filePath: backup.filePath,
              replaceExisting: false,
            );
        if (!result.success) {
          throw Exception(result.errorMessage ?? 'Restore failed');
        }
        if (!mounted) return;
        context.showSuccessSnackBar(
            'Restored ${result.itemsRestored} items successfully');
      }
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Restore failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _importBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Nightshade Backup',
          extensions: ['nsbackup', 'json'],
        ),
      ],
    );
    if (file == null) return;

    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      await _restoreBackup(_BackupEntry(
        id: file.path.hashCode.toString(),
        filePath: file.path,
        fileName: path.basename(file.path),
        createdAt: DateTime.now(),
        fileSize: await File(file.path).length(),
      ));
      return;
    }

    setState(() => _isRestoring = true);
    try {
      final bytes = await File(file.path).readAsBytes();
      final result = await backend.uploadBackupAndRestore(
        bytes,
        path.basename(file.path),
      );
      if ((result['status'] as String?) != 'restored') {
        throw Exception(result['error'] ?? 'Restore failed');
      }
      final restored = result['itemsRestored'] as int? ?? 0;
      if (!mounted) return;
      context.showSuccessSnackBar('Restored $restored items successfully');
      await _loadAvailableBackups();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Import failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _deleteBackup(_BackupEntry backup) async {
    final confirmed = await ConfirmDialog.delete(
      context: context,
      itemName: 'backup "${backup.fileName}"',
    );
    if (!confirmed) return;

    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.deleteBackup(backup.id);
      } else {
        await File(backup.filePath).delete();
      }
      if (!mounted) return;
      context.showSuccessSnackBar('Backup deleted');
      await _loadAvailableBackups();
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to delete backup: $e');
    }
  }

  Future<void> _downloadBackup(_BackupEntry backup) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) return;

    try {
      final bytes = await backend.downloadBackup(backup.id);
      final docsDir = await getApplicationDocumentsDirectory();
      final downloadDir =
          Directory(path.join(docsDir.path, 'Nightshade', 'downloads'));
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final filePath = path.join(downloadDir.path, backup.fileName);
      await File(filePath).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      context.showSuccessSnackBar('Downloaded backup to $filePath');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Download failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final autoSaveStatus = ref.watch(autoSaveStatusProvider);

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(LucideIcons.save, color: colors.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup & Restore',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRemoteMode
                            ? 'Manage backups stored on the connected Nightshade host'
                            : 'Manage your Nightshade data backups',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isRemoteMode) ...[
                    _AutoSaveStatusCard(statusAsync: autoSaveStatus),
                    const SizedBox(height: 24),
                  ],
                  _QuickActionsCard(
                    isCreatingBackup: _isCreatingBackup,
                    isRestoring: _isRestoring,
                    onCreateBackup: _isCreatingBackup ? null : _createBackup,
                    onImportBackup: _isRestoring ? null : _importBackup,
                  ),
                  const SizedBox(height: 24),
                  _RecentBackupsCard(
                    isLoading: _isLoadingBackups,
                    backups: _availableBackups,
                    onRefresh: _loadAvailableBackups,
                    onRestore: _restoreBackup,
                    onDelete: _deleteBackup,
                    onDownload: _downloadBackup,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _BackupEntry {
  final String id;
  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final int fileSize;

  const _BackupEntry({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.fileSize,
  });

  static Future<_BackupEntry> fromLocalFile(File file) async {
    final stat = await file.stat();
    return _BackupEntry(
      id: file.path.hashCode.toString(),
      filePath: file.path,
      fileName: file.uri.pathSegments.last,
      createdAt: stat.modified,
      fileSize: stat.size,
    );
  }

  factory _BackupEntry.fromRemote(Map<String, dynamic> json) {
    return _BackupEntry(
      id: json['id'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'Backup',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int? ?? 0,
      ),
      fileSize: json['fileSize'] as int? ?? 0,
    );
  }
}

class _AutoSaveStatusCard extends ConsumerWidget {
  final AsyncValue<AutoSaveStatus> statusAsync;

  const _AutoSaveStatusCard({required this.statusAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: statusAsync.when(
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Auto-Save Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _StatusRow(
                label: 'Last Sequence Save',
                value: status.lastSequenceSave == null
                    ? 'Never'
                    : DateFormat('MMM d, yyyy HH:mm')
                        .format(status.lastSequenceSave!),
              ),
              const SizedBox(height: 12),
              _StatusRow(
                label: 'Last Full Backup',
                value: status.lastBackup == null
                    ? 'Never'
                    : DateFormat('MMM d, yyyy HH:mm').format(status.lastBackup!),
              ),
              if (status.lastError != null) ...[
                const SizedBox(height: 12),
                Text(
                  status.lastError!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            'Error loading status: $error',
            style: TextStyle(color: colors.error),
          ),
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  final bool isCreatingBackup;
  final bool isRestoring;
  final VoidCallback? onCreateBackup;
  final VoidCallback? onImportBackup;

  const _QuickActionsCard({
    required this.isCreatingBackup,
    required this.isRestoring,
    required this.onCreateBackup,
    required this.onImportBackup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    label: isCreatingBackup ? 'Creating...' : 'Create Backup',
                    icon: LucideIcons.download,
                    variant: ButtonVariant.primary,
                    isLoading: isCreatingBackup,
                    onPressed: onCreateBackup,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NightshadeButton(
                    label: isRestoring ? 'Restoring...' : 'Import Backup',
                    icon: LucideIcons.upload,
                    variant: ButtonVariant.outline,
                    isLoading: isRestoring,
                    onPressed: onImportBackup,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentBackupsCard extends StatelessWidget {
  final bool isLoading;
  final List<_BackupEntry> backups;
  final VoidCallback onRefresh;
  final Future<void> Function(_BackupEntry backup) onRestore;
  final Future<void> Function(_BackupEntry backup) onDelete;
  final Future<void> Function(_BackupEntry backup) onDownload;

  const _RecentBackupsCard({
    required this.isLoading,
    required this.backups,
    required this.onRefresh,
    required this.onRestore,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Recent Backups',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onRefresh,
                  icon: Icon(LucideIcons.refreshCw,
                      size: 18, color: colors.textSecondary),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (backups.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(LucideIcons.inbox, size: 48, color: colors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No backups found',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: backups.length,
                separatorBuilder: (context, index) =>
                    Divider(color: colors.border),
                itemBuilder: (context, index) {
                  final backup = backups[index];
                  return _BackupTile(
                    backup: backup,
                    onRestore: () => onRestore(backup),
                    onDelete: () => onDelete(backup),
                    onDownload: () => onDownload(backup),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  final _BackupEntry backup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _BackupTile({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isAutoSave = backup.fileName.contains('autosave');
    final timestamp = DateFormat('MMM d, yyyy HH:mm').format(backup.createdAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isAutoSave
              ? colors.warning.withValues(alpha: 0.1)
              : colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isAutoSave ? LucideIcons.clock : LucideIcons.database,
          size: 20,
          color: isAutoSave ? colors.warning : colors.primary,
        ),
      ),
      title: Text(
        backup.fileName,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        '${_formatFileSize(backup.fileSize)} | $timestamp',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onRestore,
            icon: Icon(LucideIcons.upload, size: 18, color: colors.primary),
            tooltip: 'Restore',
          ),
          IconButton(
            onPressed: onDownload,
            icon:
                Icon(LucideIcons.download, size: 18, color: colors.textSecondary),
            tooltip: 'Download',
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(LucideIcons.trash2, size: 18, color: colors.error),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
