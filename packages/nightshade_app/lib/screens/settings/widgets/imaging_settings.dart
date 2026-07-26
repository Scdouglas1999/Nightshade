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

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
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
                  title: 'Archive format',
                  subtitle:
                      'Captured images are saved as lossless 16-bit FITS files',
                  trailing: Text(
                    '$kCaptureImageFormat · $kCaptureBitDepth',
                    style: Theme.of(context).textTheme.bodyMedium,
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
                    authoritativeValue: settings.fileNamingPattern,
                    authorityKey: authority,
                    width: widget.isMobile ? 160 : 220,
                    onChanged: (value) {
                      return ref
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
