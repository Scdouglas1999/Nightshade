import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'settings_widgets.dart';

class ImagingSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const ImagingSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<ImagingSettings> createState() => _ImagingSettingsState();
}

class _ImagingSettingsState extends ConsumerState<ImagingSettings> {
  final _patternController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _patternController.text = settings.fileNamingPattern;
      _initialized = true;
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
        _initControllers(settings);

        return SettingsPage(
          title: 'Imaging',
          description: 'Default capture settings',
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: 'File Format',
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.file,
                  title: 'Image format',
                  subtitle: 'Output file format for captured images',
                  trailing: SettingsDropdown(
                    value: settings.imageFormat,
                    items: const ['FITS', 'XISF', 'TIFF'],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setImageFormat(value);
                      }
                    },
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.binary,
                  title: 'Bit depth',
                  subtitle: 'Image bit depth for output files',
                  trailing: SettingsDropdown(
                    value: settings.bitDepth,
                    items: const ['16-bit', '32-bit'],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setBitDepth(value);
                      }
                    },
                    isMobile: widget.isMobile,
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.fileText,
                  title: 'File naming pattern',
                  subtitle:
                      r'Variables: $TARGET, $FILTER, $DATE, $SEQ, $EXPOSURE',
                  trailing: SettingsTextInput(
                    controller: _patternController,
                    width: widget.isMobile ? 160 : 220,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setFileNamingPattern(value);
                    },
                    isMobile: widget.isMobile,
                  ),
                  isLast: true,
                  isMobile: widget.isMobile,
                  stackOnMobile: widget.isMobile,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
