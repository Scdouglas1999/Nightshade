import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/remote_directory_picker_dialog.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class FilePathSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const FilePathSettings(
      {super.key, required this.colors, this.isMobile = false});

  Future<void> _selectPath(
    BuildContext context,
    WidgetRef ref,
    String settingKey,
    String currentPath,
  ) async {
    final isRemoteMode = ref.read(isRemoteModeProvider);
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
      loading: () => SettingsLoadingState(colors: colors, isMobile: isMobile),
      error: (error, stack) => SettingsErrorState(
        colors: colors,
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) => SettingsPage(
        key: SettingsTutorialKeys.filePaths,
        title: 'File Paths',
        description: 'Configure storage locations',
        colors: colors,
        children: [
          SettingsSection(
            title: 'Storage',
            colors: colors,
            children: [
              SettingRow(
                icon: LucideIcons.image,
                title: 'Image output',
                subtitle: settings.imageOutputPath.isEmpty
                    ? 'Not configured'
                    : settings.imageOutputPath,
                trailing: SettingsPathInput(
                  path: settings.imageOutputPath,
                  onBrowse: () =>
                      _selectPath(context, ref, 'image', settings.imageOutputPath),
                  colors: colors,
                ),
                colors: colors,
              ),
              SettingRow(
                icon: LucideIcons.listOrdered,
                title: 'Sequences',
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
                  colors: colors,
                ),
                colors: colors,
              ),
              SettingRow(
                icon: LucideIcons.database,
                title: 'Database',
                subtitle: settings.databasePath.isEmpty
                    ? 'Default location'
                    : settings.databasePath,
                trailing: SettingsPathInput(
                  path: settings.databasePath,
                  onBrowse: () =>
                      _selectPath(context, ref, 'database', settings.databasePath),
                  colors: colors,
                ),
                colors: colors,
              ),
              SettingRow(
                icon: LucideIcons.fileText,
                title: 'Logs',
                subtitle: settings.logsPath.isEmpty
                    ? 'Default location'
                    : settings.logsPath,
                trailing: SettingsPathInput(
                  path: settings.logsPath,
                  onBrowse: () =>
                      _selectPath(context, ref, 'logs', settings.logsPath),
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
