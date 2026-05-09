import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import 'settings_widgets.dart';

class GeneralSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const GeneralSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final l10n = context.l10n;

    return settingsAsync.when(
      loading: () => SettingsLoadingState(colors: colors, isMobile: isMobile),
      error: (error, stack) => SettingsErrorState(
        colors: colors,
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) => SettingsPage(
        title: l10n.text('generalTitle'),
        description: l10n.text('generalDescription'),
        colors: colors,
        isMobile: isMobile,
        hideHeader: isMobile,
        children: [
          SettingsSection(
            title: l10n.text('generalStartup'),
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.power,
                title: l10n.text('generalStartMinimized'),
                subtitle: l10n.text('generalStartMinimizedDesc'),
                trailing: SettingsSwitch(
                  value: settings.startMinimized,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setStartMinimized(value);
                  },
                  colors: colors,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.plug,
                title: l10n.text('generalAutoConnect'),
                subtitle: l10n.text('generalAutoConnectDesc'),
                trailing: SettingsSwitch(
                  value: settings.autoConnectEquipment,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setAutoConnectEquipment(value);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
                isMobile: isMobile,
              ),
            ],
          ),
          SettingsSection(
            title: l10n.text('generalBehavior'),
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.languages,
                title: l10n.text('generalLanguage'),
                subtitle: l10n.text('generalLanguageDesc'),
                trailing: SettingsDropdown(
                  value: settings.language == 'es'
                      ? l10n.text('languageSpanish')
                      : l10n.text('languageEnglish'),
                  items: [
                    l10n.text('languageEnglish'),
                    l10n.text('languageSpanish'),
                  ],
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setLanguage(
                          value == l10n.text('languageSpanish') ? 'es' : 'en',
                        );
                  },
                  colors: colors,
                  width: 150,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.save,
                title: l10n.text('generalAutoSaveSequences'),
                subtitle: l10n.text('generalAutoSaveSequencesDesc'),
                trailing: SettingsSwitch(
                  value: settings.autoSaveSequences,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setAutoSaveSequences(value);
                  },
                  colors: colors,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.alertTriangle,
                title: l10n.text('generalConfirmBeforeClosing'),
                subtitle: l10n.text('generalConfirmBeforeClosingDesc'),
                trailing: SettingsSwitch(
                  value: settings.confirmBeforeClosing,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setConfirmBeforeClosing(value);
                  },
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
                isMobile: isMobile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
