import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../widgets/remote_directory_picker_dialog.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class PlateSolvingSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const PlateSolvingSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  ConsumerState<PlateSolvingSettings> createState() =>
      _PlateSolvingSettingsState();
}

class _PlateSolvingSettingsState extends ConsumerState<PlateSolvingSettings> {
  final _timeoutController = TextEditingController();
  final _radiusController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _timeoutController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettings settings) {
    if (!_initialized) {
      _timeoutController.text = settings.plateSolveTimeout.toString();
      _radiusController.text =
          settings.plateSolveSearchRadius.toStringAsFixed(1);
      _initialized = true;
    }
  }

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
        colors: widget.colors,
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _initControllers(settings);

        return SettingsPage(
          key: SettingsTutorialKeys.plateSolving,
          title: 'Plate Solving',
          description: 'Configure plate solving backends',
          colors: widget.colors,
          children: [
            SettingsSection(
              title: 'Solver',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Solve Parameters',
              colors: widget.colors,
              children: [
                SettingRow(
                  icon: LucideIcons.timer,
                  title: 'Timeout',
                  subtitle: 'Maximum time to attempt solving',
                  trailing: SettingsNumberInput(
                    controller: _timeoutController,
                    suffix: 'sec',
                    min: 10,
                    max: 300,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPlateSolveTimeout(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                SettingRow(
                  icon: LucideIcons.search,
                  title: 'Search radius',
                  subtitle: 'Area to search around expected position',
                  trailing: SettingsNumberInput(
                    controller: _radiusController,
                    suffix: '\u00B0',
                    min: 1,
                    max: 180,
                    decimals: 1,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPlateSolveSearchRadius(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                SettingRow(
                  icon: LucideIcons.compass,
                  title: 'Blind solve',
                  subtitle: 'Solve without position hint (slower)',
                  trailing: SettingsSwitch(
                    value: settings.blindSolve,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setBlindSolve(value);
                    },
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
