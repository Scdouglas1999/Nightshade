import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class AppearanceSettings extends ConsumerWidget {
  final bool isMobile;

  const AppearanceSettings({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(isMobile: isMobile),
      error: (error, stack) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) => SettingsPage(
        key: SettingsTutorialKeys.appearance,
        title: 'Appearance',
        description: 'Customize how Nightshade looks',
        isMobile: isMobile,
        hideHeader: isMobile,
        children: [
          SettingsSection(
            title: 'Theme',
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.moon,
                title: 'Theme',
                // Describe the SETTING, then the non-obvious option. The old
                // subtitle was only the Red-night rationale, so on a Dark or
                // Light rig the row read as if that sentence described the
                // current selection.
                subtitle: 'Dark, Light, or Red night — red night preserves '
                    'dark adaptation at the telescope',
                // A three-way selector, not the old Dark on/off switch: the
                // theme engine has shipped a red-night mode all along
                // (`resolveNightshadeThemeData`), but no settings surface
                // ever offered it — the one theme built for a dark site was
                // unreachable, especially on the phone in your hand at 2 AM.
                trailing: SettingsDropdown(
                  value: switch (settings.theme) {
                    'light' => 'Light',
                    'redNight' => 'Red night',
                    _ => 'Dark',
                  },
                  items: const ['Dark', 'Light', 'Red night'],
                  onChanged: (value) {
                    return ref.read(appSettingsProvider.notifier).setTheme(
                          switch (value) {
                            'Light' => 'light',
                            'Red night' => 'redNight',
                            _ => 'dark',
                          },
                        );
                  },
                  isMobile: isMobile,
                ),
                isMobile: isMobile,
              ),
              // In red night the swatch row was two defects at once. The
              // picker is INERT — `resolveNightshadeThemeData` returns the
              // fixed `NightshadeTheme.redNight` before it ever looks at the
              // accent — and it painted seven full-saturation circles
              // (emerald, amber, cyan, magenta) onto a page whose every other
              // pixel is red-shifted, so checking the theme at the telescope
              // was the thing that ruined your dark adaptation. State the
              // scope instead of rendering a control that does nothing.
              if (settings.theme == 'redNight')
                SettingRow(
                  icon: LucideIcons.palette,
                  title: 'Accent color',
                  subtitle: 'Red night is monochrome red, so the accent has '
                      'no effect while it is selected. ${settings.accentColor} '
                      'applies again on the Dark and Light themes.',
                  trailing: const SizedBox.shrink(),
                  isLast: true,
                  isMobile: isMobile,
                )
              else
                SettingRow(
                  icon: LucideIcons.palette,
                  title: 'Accent color',
                  subtitle: 'Primary accent color',
                  trailing: SettingsColorPicker(
                    selectedColor: settings.accentColor,
                    onColorSelected: (color) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setAccentColor(color);
                    },
                    isMobile: isMobile,
                  ),
                  isLast: true,
                  isMobile: isMobile,
                  stackOnMobile: isMobile,
                ),
            ],
          ),
          SettingsSection(
            title: 'Display',
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
                    return ref
                        .read(appSettingsProvider.notifier)
                        .setFontSize(value);
                  },
                  isMobile: isMobile,
                ),
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
                    return ref
                        .read(appSettingsProvider.notifier)
                        .setUiScale(value);
                  },
                  isMobile: isMobile,
                ),
                isLast: isRemoteMode,
                isMobile: isMobile,
              ),
              // `sidebar_collapsed` is intentionally non-remotable (host-only);
              // hide the row over a remote session so it can't throw.
              if (!isRemoteMode)
                SettingRow(
                  icon: LucideIcons.panelLeft,
                  title: 'Sidebar collapsed by default',
                  trailing: SettingsSwitch(
                    value: settings.sidebarCollapsed,
                    onChanged: (value) {
                      return ref
                          .read(appSettingsProvider.notifier)
                          .setSidebarCollapsed(value);
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
