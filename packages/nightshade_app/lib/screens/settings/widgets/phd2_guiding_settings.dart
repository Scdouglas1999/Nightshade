import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../widgets/remote_host_path_dialog.dart';
import 'settings_widgets.dart';

class Phd2GuidingSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const Phd2GuidingSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<Phd2GuidingSettings> createState() =>
      _Phd2GuidingSettingsState();
}

class _Phd2GuidingSettingsState extends ConsumerState<Phd2GuidingSettings> {
  final _portController = TextEditingController();
  final _hostController = TextEditingController();

  @override
  void dispose() {
    _portController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  /// Persist a PHD2 connection field and surface any failure. Mirrors the
  /// path-selector's await+report behaviour so a host/port edit that fails to
  /// persist (e.g. a remote write error) is reported instead of silently lost.
  Future<void> _save(Future<void> Function() write, String what) async {
    try {
      await write();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the PHD2 $what: $e')),
        );
      }
      rethrow;
    }
  }

  Future<void> _selectPhd2Path() async {
    final authority = ref.read(backendProvider);
    final isRemote = ref.read(isRemoteModeProvider);
    String? initialDir;
    if (!isRemote && Platform.isWindows) {
      initialDir = 'C:\\Program Files';
    } else if (!isRemote && Platform.isMacOS) {
      initialDir = '/Applications';
    }

    final settings = ref.read(appSettingsProvider).valueOrNull;
    final String? result;
    if (isRemote) {
      result = await RemoteHostPathDialog.show(
        context,
        title: 'PHD2 executable on imaging host',
        initialPath: settings?.phd2Path,
        hintText: r'C:\Program Files\PHD2\PHD2.exe or /usr/bin/phd2',
        submitLabel: 'Use host path',
        clearLabel: 'Use auto-detect',
      );
    } else {
      final typeGroup = XTypeGroup(
        label: 'PHD2 executable',
        extensions: Platform.isWindows ? const ['exe'] : null,
      );
      result = (await openFile(
        acceptedTypeGroups: [typeGroup],
        initialDirectory: initialDir,
        confirmButtonText: 'Use this PHD2 executable',
      ))
          ?.path;
    }

    if (!mounted) {
      return;
    }
    if (!identical(ref.read(backendProvider), authority)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The imaging host changed while choosing the PHD2 path. '
            'Choose it again for the current host.',
          ),
        ),
      );
      return;
    }

    if (result != null) {
      try {
        await ref.read(appSettingsProvider.notifier).setPhd2Path(result);
      } catch (e) {
        if (mounted && identical(ref.read(backendProvider), authority)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save the PHD2 path: $e')),
          );
        }
      }
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
        final authority = ref.watch(backendProvider);

        return SettingsPage(
          title: 'PHD2 Guiding',
          description: 'Configure PHD2 guiding software connection',
          children: [
            SettingsSection(
              title: 'PHD2 Connection',
              children: [
                SettingRow(
                  icon: LucideIcons.server,
                  title: 'Host',
                  subtitle: 'PHD2 server hostname or IP address',
                  trailing: SettingsTextInput(
                    controller: _hostController,
                    authoritativeValue: settings.phd2Host,
                    authorityKey: authority,
                    hint: 'localhost',
                    onChanged: (value) => _save(
                      () => ref
                          .read(appSettingsProvider.notifier)
                          .setPhd2Host(value),
                      'host',
                    ),
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.network,
                  title: 'Port',
                  subtitle: 'PHD2 server port (default: 4400)',
                  trailing: SettingsNumberInput(
                    controller: _portController,
                    authoritativeValue: settings.phd2Port.toDouble(),
                    authorityKey: authority,
                    suffix: '',
                    min: 1,
                    max: 65535,
                    decimals: 0,
                    onChanged: (value) => _save(
                      () => ref
                          .read(appSettingsProvider.notifier)
                          .setPhd2Port(value.toInt()),
                      'port',
                    ),
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.folder,
                  title: 'PHD2 executable path',
                  subtitle: settings.phd2Path.isEmpty
                      ? 'Auto-detect (optional)'
                      : settings.phd2Path,
                  trailing: SettingsPathInput(
                    key: const ValueKey('phd2_executable_path'),
                    path: settings.phd2Path,
                    authorityKey: authority,
                    onBrowse: _selectPhd2Path,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Information',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'PHD2 will be automatically detected on common installation paths if not specified. '
                    'The connection settings are used when connecting to PHD2 for guiding operations.',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: NightshadeColors.of(context).textSecondary,
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
