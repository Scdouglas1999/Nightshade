import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../widgets/remote_directory_picker_dialog.dart';
import 'settings_widgets.dart';

class Phd2GuidingSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const Phd2GuidingSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  ConsumerState<Phd2GuidingSettings> createState() =>
      _Phd2GuidingSettingsState();
}

class _Phd2GuidingSettingsState extends ConsumerState<Phd2GuidingSettings> {
  final _portController = TextEditingController();
  final _hostController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _portController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _portController.text = settings.phd2Port.toString();
      _hostController.text = settings.phd2Host;
      _initialized = true;
    }
  }

  Future<void> _selectPhd2Path() async {
    String? initialDir;
    if (!ref.read(isRemoteModeProvider) && Platform.isWindows) {
      initialDir = 'C:\\Program Files';
    } else if (!ref.read(isRemoteModeProvider) && Platform.isMacOS) {
      initialDir = '/Applications';
    }

    final settings = ref.read(appSettingsProvider).valueOrNull;
    final result = ref.read(isRemoteModeProvider)
        ? await RemoteDirectoryPickerDialog.show(
            context,
            title: 'Select host PHD2 folder',
            initialPath: settings?.phd2Path,
          )
        : await getDirectoryPath(
            initialDirectory: initialDir,
            confirmButtonText: 'Select',
          );

    if (!mounted) {
      return;
    }

    if (result != null) {
      ref.read(appSettingsProvider.notifier).setPhd2Path(result);
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
          title: 'PHD2 Guiding',
          description: 'Configure PHD2 guiding software connection',
          colors: widget.colors,
          children: [
            SettingsSection(
              title: 'PHD2 Connection',
              colors: widget.colors,
              children: [
                SettingRow(
                  icon: LucideIcons.server,
                  title: 'Host',
                  subtitle: 'PHD2 server hostname or IP address',
                  trailing: SettingsTextInput(
                    controller: _hostController,
                    hint: 'localhost',
                    onChanged: (value) {
                      ref.read(appSettingsProvider.notifier).setPhd2Host(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                SettingRow(
                  icon: LucideIcons.network,
                  title: 'Port',
                  subtitle: 'PHD2 server port (default: 4400)',
                  trailing: SettingsNumberInput(
                    controller: _portController,
                    suffix: '',
                    min: 1,
                    max: 65535,
                    decimals: 0,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPhd2Port(value.toInt());
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
                ),
                SettingRow(
                  icon: LucideIcons.folder,
                  title: 'PHD2 executable path',
                  subtitle: settings.phd2Path.isEmpty
                      ? 'Auto-detect (optional)'
                      : settings.phd2Path,
                  trailing: SettingsPathInput(
                    path: settings.phd2Path,
                    onBrowse: _selectPhd2Path,
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Information',
              colors: widget.colors,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'PHD2 will be automatically detected on common installation paths if not specified. '
                    'The connection settings are used when connecting to PHD2 for guiding operations.',
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
