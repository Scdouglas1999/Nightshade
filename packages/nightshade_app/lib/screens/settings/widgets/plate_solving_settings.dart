import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:file_selector/file_selector.dart';

import '../../../widgets/remote_directory_picker_dialog.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'plate_solve_parameters_section.dart';
import 'settings_widgets.dart';

class PlateSolvingSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const PlateSolvingSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<PlateSolvingSettings> createState() =>
      _PlateSolvingSettingsState();
}

class _PlateSolvingSettingsState extends ConsumerState<PlateSolvingSettings> {
  Future<void> _selectAstapPath() async {
    String? initialDir;
    if (!ref.read(isRemoteModeProvider) && Platform.isWindows) {
      initialDir = 'C:\\Program Files\\astap';
    } else if (!ref.read(isRemoteModeProvider) && Platform.isMacOS) {
      initialDir = '/Applications';
    }

    final settings = ref.read(appSettingsProvider).valueOrNull;
    final result = ref.read(isRemoteModeProvider)
        ? await RemoteDirectoryPickerDialog.show(
            context,
            title: 'Select host ASTAP folder',
            initialPath: settings?.astapPath,
          )
        : await getDirectoryPath(
            initialDirectory: initialDir,
            confirmButtonText: 'Select',
          );

    if (!mounted) {
      return;
    }

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setAstapPath(result);
    }
  }

  Future<void> _selectAstrometryPath() async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final result = ref.read(isRemoteModeProvider)
        ? await RemoteDirectoryPickerDialog.show(
            context,
            title: 'Select host Astrometry.net folder',
            initialPath: settings?.astrometryPath,
          )
        : await getDirectoryPath(
            confirmButtonText: 'Select',
          );

    if (!mounted) {
      return;
    }

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setAstrometryPath(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        return SettingsPage(
          key: SettingsTutorialKeys.plateSolving,
          title: 'Plate Solving',
          description: 'Configure plate solving backends',
          children: [
            SettingsSection(
              title: 'Solver',
              children: [
                SettingRow(
                  icon: LucideIcons.crosshair,
                  title: 'Primary solver',
                  subtitle: 'Select the plate solving engine to use',
                  trailing: SettingsDropdown(
                    value: settings.plateSolver,
                    items: const ['ASTAP', 'Astrometry.net', 'PlateSolve2'],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setPlateSolver(value);
                      }
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.folder,
                  title: 'ASTAP path',
                  subtitle: settings.astapPath.isEmpty
                      ? 'Not configured'
                      : settings.astapPath,
                  trailing: SettingsPathInput(
                    path: settings.astapPath,
                    onBrowse: _selectAstapPath,
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.folder,
                  title: 'Astrometry.net path',
                  subtitle: settings.astrometryPath.isEmpty
                      ? 'Not configured'
                      : settings.astrometryPath,
                  trailing: SettingsPathInput(
                    path: settings.astrometryPath,
                    onBrowse: _selectAstrometryPath,
                  ),
                  isLast: true,
                ),
              ],
            ),
            const PlateSolveParametersSection(),
          ],
        );
      },
    );
  }
}
