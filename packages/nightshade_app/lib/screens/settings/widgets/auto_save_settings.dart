import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

/// Auto-save configuration settings page.
class AutoSaveSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const AutoSaveSettings({
    super.key,
    required this.colors,
    this.isMobile = false,
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
    final service = ref.read(autoSaveServiceProvider);
    final config = service.config;
    _currentStatus = service.status;

    _sequenceIntervalController = TextEditingController(
        text: config.sequenceInterval.inMinutes.toString());
    _backupIntervalController =
        TextEditingController(text: config.backupInterval.inHours.toString());
    _maxBackupsController =
        TextEditingController(text: config.maxBackups.toString());

    _statusSubscription = service.statusStream.listen((status) {
      if (mounted) {
        setState(() => _currentStatus = status);
      }
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
    Duration? backupInterval,
    bool? sequenceEnabled,
    bool? backupEnabled,
    int? maxBackups,
  }) async {
    final service = ref.read(autoSaveServiceProvider);
    final newConfig = service.config.copyWith(
      sequenceInterval: sequenceInterval,
      backupInterval: backupInterval,
      sequenceEnabled: sequenceEnabled,
      backupEnabled: backupEnabled,
      maxBackups: maxBackups,
    );
    await service.updateConfig(newConfig);
    if (mounted) setState(() {});
  }

  Future<void> _saveNow() async {
    setState(() => _isSavingNow = true);
    try {
      final service = ref.read(autoSaveServiceProvider);
      await service.saveNow();
      await service.backupNow();
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
    final colors = widget.colors;
    final isMobile = widget.isMobile;
    final service = ref.watch(autoSaveServiceProvider);
    final config = service.config;

    return SettingsPage(
      title: 'Auto-Save',
      description: 'Configure automatic sequence saving and backups',
      colors: colors,
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        // Sequence auto-save section
        SettingsSection(
          title: 'Sequence Auto-Save',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.save,
              title: 'Enable sequence auto-save',
              subtitle:
                  'Automatically save sequence changes at regular intervals',
              trailing: SettingsSwitch(
                value: config.sequenceEnabled,
                onChanged: (value) => _updateConfig(sequenceEnabled: value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.clock,
              title: 'Save interval',
              subtitle: 'How often to auto-save sequences (minutes)',
              trailing: SettingsNumberInput(
                controller: _sequenceIntervalController,
                suffix: 'min',
                min: 1,
                max: 60,
                decimals: 0,
                onChanged: (value) => _updateConfig(
                  sequenceInterval: Duration(minutes: value.round()),
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),

        // Backup section
        SettingsSection(
          title: 'Automatic Backups',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.hardDrive,
              title: 'Enable automatic backups',
              subtitle: 'Periodically create full database backups',
              trailing: SettingsSwitch(
                value: config.backupEnabled,
                onChanged: (value) => _updateConfig(backupEnabled: value),
                colors: colors,
              ),
              colors: colors,
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
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
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
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),

        // Status section
        SettingsSection(
          title: 'Status',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.checkCircle,
              title: 'Last sequence save',
              subtitle: _formatDateTime(_currentStatus.lastSequenceSave),
              trailing: _currentStatus.isSequenceSaving
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
                        _currentStatus.lastSequenceSave,
                        config.sequenceInterval,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
              colors: colors,
              isMobile: isMobile,
            ),
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
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
              colors: colors,
              isMobile: isMobile,
            ),
            if (_currentStatus.lastError != null)
              SettingRow(
                icon: LucideIcons.alertTriangle,
                iconColor: colors.error,
                title: 'Last error',
                subtitle: _currentStatus.lastError,
                trailing: const SizedBox.shrink(),
                colors: colors,
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
                    label: 'Save Now',
                    icon: LucideIcons.save,
                    size: isMobile ? ButtonSize.small : ButtonSize.medium,
                    isLoading: _isSavingNow,
                    onPressed: _isSavingNow ? null : _saveNow,
                  ),
                  const SizedBox(width: 12),
                  if (ref.read(autoSaveServiceProvider).hasUnsavedChanges)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.alertCircle,
                          size: 14,
                          color: colors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Unsaved changes pending',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.warning,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'All changes saved',
                      style: TextStyle(
                        fontSize: 12,
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
