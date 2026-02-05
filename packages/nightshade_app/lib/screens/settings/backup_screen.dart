import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/snackbar_helper.dart';

/// Backup and Restore settings screen
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isCreatingBackup = false;
  bool _isRestoring = false;
  bool _isLoadingBackups = true;
  List<File> _availableBackups = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableBackups();
  }

  Future<void> _loadAvailableBackups() async {
    setState(() => _isLoadingBackups = true);

    try {
      final backupService = ref.read(backupServiceProvider);
      final backups = await backupService.listBackups();

      if (mounted) {
        setState(() {
          _availableBackups = backups;
          _isLoadingBackups = false;
        });
      }
    } catch (e) {
      debugPrint('[Backup] Error loading backups: $e');
      if (mounted) {
        setState(() => _isLoadingBackups = false);
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.createBackup();

      if (mounted) {
        setState(() {
          _isCreatingBackup = false;
        });

        if (result.success) {
          _showSuccessSnackbar('Backup created successfully');
          await _loadAvailableBackups();
        } else {
          _showErrorSnackbar('Backup failed: ${result.errorMessage}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingBackup = false);
        _showErrorSnackbar('Error creating backup: $e');
      }
    }
  }

  Future<void> _restoreBackup(String filePath) async {
    // Extract backup name from file path for display
    final backupName = filePath.split('/').last.split('\\').last;

    // Confirm with user using the restore helper
    final confirmed = await ConfirmDialog.restore(
      context: context,
      backupName: backupName,
    );

    if (!confirmed) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.restoreBackup(
        filePath: filePath,
        replaceExisting: false,
      );

      if (mounted) {
        setState(() {
          _isRestoring = false;
        });

        if (result.success) {
          _showSuccessSnackbar(
            'Restored ${result.itemsRestored} items successfully',
          );
        } else {
          _showErrorSnackbar('Restore failed: ${result.errorMessage}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRestoring = false);
        _showErrorSnackbar('Error restoring backup: $e');
      }
    }
  }

  Future<void> _importBackup() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Nightshade Backup',
          extensions: ['nsbackup', 'json'],
        ),
      ],
    );

    if (file == null) return;

    await _restoreBackup(file.path);
  }

  void _showSuccessSnackbar(String message) {
    context.showSuccessSnackBar(message);
  }

  void _showErrorSnackbar(String message) {
    context.showErrorSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final autoSaveStatus = ref.watch(autoSaveStatusProvider);

    return Scaffold(
      body: Column(
        children: [
          // Header
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
                  child: Icon(LucideIcons.save, color: colors.primary, size: 24),
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
                        'Manage your Nightshade data backups',
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

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Auto-save status
                  _buildAutoSaveStatusCard(colors, autoSaveStatus),
                  const SizedBox(height: 24),

                  // Quick actions
                  _buildQuickActionsCard(colors),
                  const SizedBox(height: 24),

                  // Recent backups
                  _buildRecentBackupsCard(colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSaveStatusCard(
    NightshadeColors colors,
    AsyncValue<AutoSaveStatus> statusAsync,
  ) {
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.clock, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Auto-Save Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            statusAsync.when(
              data: (status) => Column(
                children: [
                  _buildStatusRow(
                    colors,
                    'Last Sequence Save',
                    status.lastSequenceSave != null
                        ? _formatDateTime(status.lastSequenceSave!)
                        : 'Never',
                    status.isSequenceSaving
                        ? LucideIcons.loader2
                        : LucideIcons.checkCircle2,
                    status.isSequenceSaving ? colors.warning : colors.success,
                    isSpinning: status.isSequenceSaving,
                  ),
                  const SizedBox(height: 12),
                  _buildStatusRow(
                    colors,
                    'Last Full Backup',
                    status.lastBackup != null
                        ? _formatDateTime(status.lastBackup!)
                        : 'Never',
                    status.isBackingUp
                        ? LucideIcons.loader2
                        : LucideIcons.database,
                    status.isBackingUp ? colors.warning : colors.textSecondary,
                    isSpinning: status.isBackingUp,
                  ),
                  if (status.lastError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.alertTriangle,
                              size: 16, color: colors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status.lastError!,
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text(
                'Error loading status: $error',
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    NightshadeColors colors,
    String label,
    String value,
    IconData icon,
    Color iconColor, {
    bool isSpinning = false,
  }) {
    return Row(
      children: [
        if (isSpinning)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(iconColor),
            ),
          )
        else
          Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
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

  Widget _buildQuickActionsCard(NightshadeColors colors) {
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
                    label: _isCreatingBackup ? 'Creating...' : 'Create Backup',
                    icon: LucideIcons.download,
                    variant: ButtonVariant.primary,
                    isLoading: _isCreatingBackup,
                    onPressed: _isCreatingBackup ? null : _createBackup,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NightshadeButton(
                    label: _isRestoring ? 'Restoring...' : 'Import Backup',
                    icon: LucideIcons.upload,
                    variant: ButtonVariant.outline,
                    isLoading: _isRestoring,
                    onPressed: _isRestoring ? null : _importBackup,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentBackupsCard(NightshadeColors colors) {
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
                  onPressed: _loadAvailableBackups,
                  icon: Icon(LucideIcons.refreshCw, size: 18, color: colors.textSecondary),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingBackups)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_availableBackups.isEmpty)
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
                itemCount: _availableBackups.length,
                separatorBuilder: (context, index) => Divider(color: colors.border),
                itemBuilder: (context, index) {
                  final backup = _availableBackups[index];
                  return _buildBackupTile(colors, backup);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupTile(NightshadeColors colors, File backup) {
    final stat = backup.statSync();
    final fileName = backup.uri.pathSegments.last;
    final isAutoSave = fileName.contains('autosave');

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
        fileName,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        '${_formatFileSize(stat.size)} • ${_formatDateTime(stat.modified)}',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _restoreBackup(backup.path),
            icon: Icon(LucideIcons.upload, size: 18, color: colors.primary),
            tooltip: 'Restore',
          ),
          IconButton(
            onPressed: () => _deleteBackup(backup),
            icon: Icon(LucideIcons.trash2, size: 18, color: colors.error),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBackup(File backup) async {
    final fileName = backup.uri.pathSegments.last;

    final confirmed = await ConfirmDialog.delete(
      context: context,
      itemName: 'backup "$fileName"',
    );

    if (!confirmed) return;

    try {
      await backup.delete();
      _showSuccessSnackbar('Backup deleted');
      await _loadAvailableBackups();
    } catch (e) {
      _showErrorSnackbar('Failed to delete backup: $e');
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy HH:mm').format(dateTime);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
