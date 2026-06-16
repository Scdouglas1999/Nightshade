import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:file_selector/file_selector.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/remote_directory_picker_dialog.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class FilePathSettings extends ConsumerWidget {
  final bool isMobile;

  const FilePathSettings({super.key, this.isMobile = false});

  Future<void> _selectPath(
    BuildContext context,
    WidgetRef ref,
    String settingKey,
    String currentPath,
  ) async {
    final isRemoteMode = ref.read(isRemoteModeProvider);
    // Only `image_output_path` is carried by the remote wire model; the three
    // infra paths (sequences/database/logs) are excluded from partial
    // persistence and setting them throws UnsupportedError. Block the picker
    // up-front in remote mode so the user gets a clear message instead of an
    // unhandled exception.
    if (isRemoteMode && settingKey != 'image') {
      context.showWarningSnackBar(
          'This path can only be changed on the host machine.');
      return;
    }
    final result = isRemoteMode
        ? await RemoteDirectoryPickerDialog.show(
            context,
            title: 'Select host folder',
            initialPath: currentPath,
          )
        : await getDirectoryPath(
            confirmButtonText: 'Select',
          );

    if (!context.mounted) {
      return;
    }

    if (result != null) {
      final notifier = ref.read(appSettingsProvider.notifier);
      switch (settingKey) {
        case 'image':
          await notifier.setImageOutputPath(result);
          break;
        case 'sequences':
          // Why: the sequence file service watches settings and updates its
          // initial-directory immediately — no restart required.
          await notifier.setSequencesPath(result);
          if (context.mounted) {
            context.showSuccessSnackBar(
                'Sequences directory updated. New exports/imports will start here.');
          }
          break;
        case 'database':
          // Why: the Drift database connection is opened once at boot from
          // the path in app settings. Changing it requires a restart so
          // the next launch loads from the new location. We surface this
          // explicitly so the user knows the change is not live.
          await notifier.setDatabasePath(result);
          if (context.mounted) {
            context.showWarningSnackBar(
                'Database path saved. Restart Nightshade to load the database from this location.');
          }
          break;
        case 'logs':
          // Why: the file logger sink is initialised at startup from the
          // logs path. We instruct the user to restart; logger init
          // changes are surfaced at the next launch.
          await notifier.setLogsPath(result);
          if (context.mounted) {
            context.showWarningSnackBar(
                'Logs path saved. Restart Nightshade to begin writing logs to this folder.');
          }
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(isMobile: isMobile),
      error: (error, stack) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        final isRemoteMode = ref.watch(isRemoteModeProvider);
        final hostHint = isRemoteMode ? ' (on imaging host)' : '';
        return SettingsPage(
          key: SettingsTutorialKeys.filePaths,
          title: 'File Paths',
          description: isRemoteMode
              ? 'Storage locations on the connected imaging host'
              : 'Configure storage locations',
          children: [
            SettingsSection(
              title: 'Storage',
              children: [
                SettingRow(
                  icon: LucideIcons.image,
                  title: 'Image output$hostHint',
                  subtitle: settings.imageOutputPath.isEmpty
                      ? 'Not configured'
                      : settings.imageOutputPath,
                  trailing: SettingsPathInput(
                    path: settings.imageOutputPath,
                    onBrowse: () => _selectPath(
                        context, ref, 'image', settings.imageOutputPath),
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.listOrdered,
                  title: 'Sequences$hostHint',
                  subtitle: settings.sequencesPath.isEmpty
                      ? 'Not configured'
                      : settings.sequencesPath,
                  trailing: SettingsPathInput(
                    path: settings.sequencesPath,
                    onBrowse: () => _selectPath(
                      context,
                      ref,
                      'sequences',
                      settings.sequencesPath,
                    ),
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.database,
                  title: 'Database$hostHint',
                  subtitle: settings.databasePath.isEmpty
                      ? 'Default location'
                      : settings.databasePath,
                  trailing: SettingsPathInput(
                    path: settings.databasePath,
                    onBrowse: () => _selectPath(
                        context, ref, 'database', settings.databasePath),
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.fileText,
                  title: 'Logs$hostHint',
                  subtitle: settings.logsPath.isEmpty
                      ? 'Default location'
                      : settings.logsPath,
                  trailing: SettingsPathInput(
                    path: settings.logsPath,
                    onBrowse: () =>
                        _selectPath(context, ref, 'logs', settings.logsPath),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
