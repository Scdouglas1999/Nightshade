import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:file_selector/file_selector.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/remote_directory_picker_dialog.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

typedef FilePathSettingsPicker = Future<String?> Function(
  BuildContext context, {
  required bool isRemote,
  required String currentPath,
});

typedef FilePathSettingsWriter = Future<void> Function(
  String settingKey,
  String path,
);

Future<String?> _pickFilePathSetting(
  BuildContext context, {
  required bool isRemote,
  required String currentPath,
}) {
  if (isRemote) {
    return RemoteDirectoryPickerDialog.show(
      context,
      title: 'Select host folder',
      initialPath: currentPath,
    );
  }
  return getDirectoryPath(confirmButtonText: 'Select');
}

final filePathSettingsPickerProvider =
    Provider<FilePathSettingsPicker>((ref) => _pickFilePathSetting);

final filePathSettingsWriterProvider = Provider<FilePathSettingsWriter>((ref) {
  return (settingKey, path) async {
    final notifier = ref.read(appSettingsProvider.notifier);
    switch (settingKey) {
      case 'image':
        await notifier.setImageOutputPath(path);
      case 'sequences':
        await notifier.setSequencesPath(path);
      default:
        throw ArgumentError.value(settingKey, 'settingKey');
    }
  };
});

class FilePathSettings extends ConsumerWidget {
  final bool isMobile;

  /// When true, render without an own scroll view / header (embedded in a
  /// merged section's single outer scroll).
  final bool embedded;

  const FilePathSettings({
    super.key,
    this.isMobile = false,
    this.embedded = false,
  });

  Future<void> _selectPath(
    BuildContext context,
    WidgetRef ref,
    String settingKey,
    String currentPath,
  ) async {
    final authority = ref.read(backendProvider);
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
    try {
      final result = await ref.read(filePathSettingsPickerProvider)(
        context,
        isRemote: isRemoteMode,
        currentPath: currentPath,
      );

      if (!context.mounted || result == null) return;
      if (!identical(ref.read(backendProvider), authority)) {
        context.showWarningSnackBar(
          'The imaging host changed while choosing that folder. Choose it '
          'again for the current host.',
        );
        return;
      }

      await ref.read(filePathSettingsWriterProvider)(settingKey, result);
      if (!context.mounted ||
          !identical(ref.read(backendProvider), authority)) {
        return;
      }
      if (settingKey == 'sequences') {
        // The sequence file service watches settings and updates its initial
        // directory immediately — no restart required.
        context.showSuccessSnackBar(
          'Sequences directory updated. New exports/imports will start here.',
        );
      }
    } catch (e) {
      if (context.mounted && identical(ref.read(backendProvider), authority)) {
        context.showErrorSnackBar('Could not update the storage path: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () =>
          SettingsLoadingState(isMobile: isMobile, scrollable: !embedded),
      error: (error, stack) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        final authority = ref.watch(backendProvider);
        final isRemoteMode = ref.watch(isRemoteModeProvider);
        final hostHint = isRemoteMode ? ' (on imaging host)' : '';
        return SettingsPage(
          key: SettingsTutorialKeys.filePaths,
          title: 'File Paths',
          description: isRemoteMode
              ? 'Storage locations on the connected imaging host'
              : 'Configure storage locations',
          isMobile: isMobile,
          hideHeader: embedded,
          scrollable: !embedded,
          children: [
            SettingsSection(
              title: 'Storage',
              children: [
                SettingRow(
                  isMobile: isMobile,
                  // A path is long and the input is a fixed-width control, so
                  // side-by-side it collided with the (wrapping) title: on a
                  // 411dp phone the Storage card overflowed RIGHT by 66px, a
                  // visible hazard stripe over the card edge. Stacked, the
                  // input gets the row's full width and the path ellipsizes
                  // inside it instead of pushing past the card.
                  stackOnMobile: true,
                  icon: LucideIcons.image,
                  title: 'Image output$hostHint',
                  subtitle: settings.imageOutputPath.isEmpty
                      ? 'Not configured'
                      : settings.imageOutputPath,
                  trailing: SettingsPathInput(
                    isMobile: isMobile,
                    flexible: isMobile,
                    path: settings.imageOutputPath,
                    authorityKey: authority,
                    onBrowse: () => _selectPath(
                        context, ref, 'image', settings.imageOutputPath),
                  ),
                ),
                SettingRow(
                  isMobile: isMobile,
                  stackOnMobile: true,
                  icon: LucideIcons.listOrdered,
                  title: 'Sequences$hostHint',
                  subtitle: settings.sequencesPath.isEmpty
                      ? 'Not configured'
                      : settings.sequencesPath,
                  trailing: SettingsPathInput(
                    isMobile: isMobile,
                    flexible: isMobile,
                    path: settings.sequencesPath,
                    authorityKey: authority,
                    onBrowse: () => _selectPath(
                      context,
                      ref,
                      'sequences',
                      settings.sequencesPath,
                    ),
                  ),
                  isLast: true,
                ),
              ],
            ),
            if (!isRemoteMode)
              const SettingsSection(
                title: 'Application Data',
                children: [
                  SettingRow(
                    icon: LucideIcons.database,
                    title: 'Database and logs',
                    subtitle:
                        'Managed automatically in Nightshade’s application '
                        'data folder',
                    trailing: SizedBox.shrink(),
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
