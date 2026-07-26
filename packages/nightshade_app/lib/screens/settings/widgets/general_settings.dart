import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../localization/nightshade_localizations.dart';
import 'settings_widgets.dart';

class GeneralSettings extends ConsumerWidget {
  final bool isMobile;

  const GeneralSettings({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final l10n = context.l10n;

    return settingsAsync.when(
      loading: () => SettingsLoadingState(isMobile: isMobile),
      error: (error, stack) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) => SettingsPage(
        title: l10n.text('generalTitle'),
        description: l10n.text('generalDescription'),
        isMobile: isMobile,
        hideHeader: isMobile,
        children: [
          SettingsSection(
            title: l10n.text('generalStartup'),
            isMobile: isMobile,
            children: [
              // `start_minimized` is intentionally non-remotable (host-only);
              // hide the row over a remote session so it can't throw.
              if (!isRemoteMode)
                SettingRow(
                  icon: LucideIcons.power,
                  title: l10n.text('generalStartMinimized'),
                  subtitle: l10n.text('generalStartMinimizedDesc'),
                  trailing: SettingsSwitch(
                    value: settings.startMinimized,
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setStartMinimized(value);
                    },
                  ),
                  isMobile: isMobile,
                ),
              SettingRow(
                icon: LucideIcons.plug,
                title: l10n.text('generalAutoConnect'),
                subtitle: l10n.text('generalAutoConnectDesc'),
                trailing: SettingsSwitch(
                  value: settings.autoConnectEquipment,
                  onChanged: (value) {
                    return ref
                        .read(appSettingsProvider.notifier)
                        .setAutoConnectEquipment(value);
                  },
                ),
                isLast: true,
                isMobile: isMobile,
              ),
            ],
          ),
          SettingsSection(
            title: l10n.text('generalBehavior'),
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
                    return ref.read(appSettingsProvider.notifier).setLanguage(
                          value == l10n.text('languageSpanish') ? 'es' : 'en',
                        );
                  },
                  width: 150,
                ),
                isLast: isRemoteMode,
                isMobile: isMobile,
              ),
              // `confirm_before_closing` is intentionally non-remotable
              // (host-only); hide the row over a remote session.
              if (!isRemoteMode)
                SettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: l10n.text('generalConfirmBeforeClosing'),
                  subtitle: l10n.text('generalConfirmBeforeClosingDesc'),
                  trailing: SettingsSwitch(
                    value: settings.confirmBeforeClosing,
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setConfirmBeforeClosing(value);
                    },
                  ),
                  isLast: true,
                  isMobile: isMobile,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
