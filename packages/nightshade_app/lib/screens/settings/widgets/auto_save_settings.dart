import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';
import '../../../utils/snackbar_helper.dart';

/// Auto-save configuration settings page.
class AutoSaveSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  /// When true, render without an own scroll view / header (embedded in a
  /// merged section's single outer scroll).
  final bool embedded;

  const AutoSaveSettings({
    super.key,
    this.isMobile = false,
    this.embedded = false,
  });

  @override
  ConsumerState<AutoSaveSettings> createState() => _AutoSaveSettingsState();
}

class _AutoSaveSettingsState extends ConsumerState<AutoSaveSettings> {
  late TextEditingController _sequenceIntervalController;
  late TextEditingController _backupIntervalController;
  late TextEditingController _maxBackupsController;
  StreamSubscription<AutoSaveStatus>? _statusSubscription;
  AutoSaveStatus _currentStatus = const AutoSaveStatus();
  bool _isSavingNow = false;

  @override
  void initState() {
    super.initState();
    final isRemoteMode = ref.read(isRemoteModeProvider);
    final service = isRemoteMode ? null : ref.read(autoSaveServiceProvider);
    final config = service?.config ?? const AutoSaveConfig();
    _currentStatus = service?.status ?? const AutoSaveStatus();

    _sequenceIntervalController = TextEditingController(
      text: config.sequenceInterval.inMinutes.toString(),
    );
    _backupIntervalController =
        TextEditingController(text: config.backupInterval.inHours.toString());
    _maxBackupsController =
        TextEditingController(text: config.maxBackups.toString());

    _statusSubscription = service?.statusStream.listen((status) {
      if (mounted) setState(() => _currentStatus = status);
    });
  }

  @override
  void dispose() {
    _sequenceIntervalController.dispose();
    _backupIntervalController.dispose();
    _maxBackupsController.dispose();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _updateConfig({
    Duration? sequenceInterval,
    bool? sequenceEnabled,
    Duration? backupInterval,
    bool? backupEnabled,
    int? maxBackups,
  }) async {
    final service = ref.read(autoSaveServiceProvider);
    final newConfig = service.config.copyWith(
      sequenceInterval: sequenceInterval,
      sequenceEnabled: sequenceEnabled,
      backupInterval: backupInterval,
      backupEnabled: backupEnabled,
      maxBackups: maxBackups,
    );
    try {
      await service.updateConfig(newConfig);
      if (mounted) setState(() {});
    } catch (error) {
      // updateConfig persists before restarting timers. A timer-restart error
      // can therefore occur after the new object has become authoritative;
      // only ask the shared control to roll back when the service rejected the
      // configuration itself.
      final wasApplied = identical(service.config, newConfig);
      if (mounted) {
        setState(() {});
        context.showErrorSnackBar(
          wasApplied
              ? 'Backup schedule saved, but the auto-save service reported: '
                  '$error'
              : 'Could not save backup schedule: $error',
        );
      }
      if (!wasApplied) rethrow;
    }
  }

  Future<void> _saveNow() async {
    setState(() => _isSavingNow = true);
    try {
      final service = ref.read(autoSaveServiceProvider);
      final result = await service.backupNow();
      if (!result.success) {
        throw StateError(result.errorMessage ?? 'Backup failed');
      }
      if (mounted) context.showSuccessSnackBar('Backup created successfully');
    } catch (error) {
      if (mounted) context.showErrorSnackBar('Backup failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSavingNow = false);
      }
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatNextSave(DateTime? lastSave, Duration interval) {
    if (lastSave == null) return 'Pending';
    final next = lastSave.add(interval);
    final now = DateTime.now();
    if (next.isBefore(now)) return 'Imminent';
    final diff = next.difference(now);
    if (diff.inSeconds < 60) return 'In ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes}m';
    return 'In ${diff.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = widget.isMobile;
    final isRemoteMode = ref.watch(isRemoteModeProvider);

    if (isRemoteMode) {
      return SettingsPage(
        title: 'Automatic Backups',
        description: 'Backups run on the connected imaging host',
        isMobile: isMobile,
        hideHeader: isMobile || widget.embedded,
        scrollable: !widget.embedded,
        children: [
          SettingsSection(
            title: 'Host-owned setting',
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.server,
                title: 'Configure on the host',
                subtitle:
                    'Automatic backup scheduling is stored and executed on '
                    'the computer connected to your equipment.',
                trailing: const SizedBox.shrink(),
                isLast: true,
                isMobile: isMobile,
              ),
            ],
          ),
        ],
      );
    }

    final service = ref.watch(autoSaveServiceProvider);
    final config = service.config;

    return SettingsPage(
      title: 'Automatic Backups',
      description: 'Schedule recurring backups of Nightshade data',
      isMobile: isMobile,
      hideHeader: isMobile || widget.embedded,
      scrollable: !widget.embedded,
      children: [
        SettingsSection(
          title: 'Sequence Auto-Save',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.fileCheck,
              title: 'Enable sequence auto-save',
              subtitle: 'Persist local sequence edits in the background',
              trailing: SettingsSwitch(
                value: config.sequenceEnabled,
                onChanged: (value) => _updateConfig(sequenceEnabled: value),
              ),
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.clock,
              title: 'Sequence save interval',
              subtitle: 'How often to save pending sequence edits',
              trailing: SettingsNumberInput(
                controller: _sequenceIntervalController,
                suffix: 'min',
                min: 1,
                max: 60,
                decimals: 0,
                onChanged: (value) => _updateConfig(
                  sequenceInterval: Duration(minutes: value.round()),
                ),
                isMobile: isMobile,
              ),
              isLast: true,
              isMobile: isMobile,
            ),
          ],
        ),

        // Backup section
        SettingsSection(
          title: 'Automatic Backups',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.hardDrive,
              title: 'Enable automatic backups',
              subtitle: 'Periodically create full database backups',
              trailing: SettingsSwitch(
                value: config.backupEnabled,
                onChanged: (value) => _updateConfig(backupEnabled: value),
              ),
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.clock,
              title: 'Backup interval',
              subtitle: 'How often to create backups (hours)',
              trailing: SettingsNumberInput(
                controller: _backupIntervalController,
                suffix: 'hrs',
                min: 1,
                max: 168,
                decimals: 0,
                onChanged: (value) => _updateConfig(
                  backupInterval: Duration(hours: value.round()),
                ),
                isMobile: isMobile,
              ),
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.archive,
              title: 'Maximum backups',
              subtitle: 'Number of auto-save backups to retain',
              trailing: SettingsNumberInput(
                controller: _maxBackupsController,
                suffix: '',
                min: 1,
                max: 50,
                decimals: 0,
                onChanged: (value) => _updateConfig(
                  maxBackups: value.round(),
                ),
                isMobile: isMobile,
              ),
              isLast: true,
              isMobile: isMobile,
            ),
          ],
        ),

        // Status section
        SettingsSection(
          title: 'Status',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.checkCircle,
              title: 'Last backup',
              subtitle: _formatDateTime(_currentStatus.lastBackup),
              trailing: _currentStatus.isBackingUp
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : Text(
                      _formatNextSave(
                        _currentStatus.lastBackup,
                        config.backupInterval,
                      ),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textMuted,
                      ),
                    ),
              isMobile: isMobile,
            ),
            if (_currentStatus.lastError != null)
              SettingRow(
                icon: LucideIcons.alertTriangle,
                iconColor: colors.error,
                title: 'Last error',
                subtitle: _currentStatus.lastError,
                trailing: const SizedBox.shrink(),
                isMobile: isMobile,
              ),
            // Save Now button row
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12.0 : 16.0,
                vertical: isMobile ? 12.0 : 14.0,
              ),
              child: Row(
                children: [
                  NightshadeButton(
                    label: 'Back Up Now',
                    icon: LucideIcons.save,
                    size: isMobile ? ButtonSize.small : ButtonSize.medium,
                    isLoading: _isSavingNow,
                    onPressed: _isSavingNow ? null : _saveNow,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Creates a full backup immediately',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
