import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class AppearanceSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const AppearanceSettings(
      {super.key, required this.colors, this.isMobile = false});

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
        key: SettingsTutorialKeys.appearance,
        title: 'Appearance',
        description: 'Customize how Nightshade looks',
        colors: colors,
        isMobile: isMobile,
        hideHeader: isMobile,
        children: [
          SettingsSection(
            title: 'Theme',
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.moon,
                title: 'Dark mode',
                subtitle: 'Use dark theme (recommended for night use)',
                trailing: SettingsSwitch(
                  value: settings.theme == 'dark',
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setTheme(value ? 'dark' : 'light');
                  },
                  colors: colors,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.palette,
                title: 'Accent color',
                subtitle: 'Primary accent color',
                trailing: SettingsColorPicker(
                  selectedColor: settings.accentColor,
                  onColorSelected: (color) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setAccentColor(color);
                  },
                  colors: colors,
                  isMobile: isMobile,
                ),
                isLast: true,
                colors: colors,
                isMobile: isMobile,
                stackOnMobile: isMobile,
              ),
            ],
          ),
          SettingsSection(
            title: 'Display',
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.type,
                title: 'Font size',
                subtitle: 'Interface text size',
                trailing: SettingsDropdown(
                  value: settings.fontSize,
                  items: const ['Small', 'Medium', 'Large'],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appSettingsProvider.notifier).setFontSize(value);
                    }
                  },
                  colors: colors,
                  isMobile: isMobile,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.zoomIn,
                title: 'UI scale',
                subtitle: 'Scale controls and layout density',
                trailing: SettingsDropdown(
                  value: settings.uiScale,
                  items: const [
                    'Auto',
                    'Small (0.8x)',
                    'Normal (1.0x)',
                    'Large (1.2x)',
                    'Extra Large (1.4x)',
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appSettingsProvider.notifier).setUiScale(value);
                    }
                  },
                  colors: colors,
                  isMobile: isMobile,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.panelLeft,
                title: 'Sidebar collapsed by default',
                trailing: SettingsSwitch(
                  value: settings.sidebarCollapsed,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setSidebarCollapsed(value);
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
