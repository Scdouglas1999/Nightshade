import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_widgets.dart';

class AboutSettings extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const AboutSettings({super.key, required this.colors, this.isMobile = false});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = isMobile ? 64.0 : 80.0;
    final logoIconSize = isMobile ? 32.0 : 40.0;

    return SettingsPage(
      title: 'About',
      description: 'Application information',
      colors: colors,
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: logoIconSize,
                  color: colors.background,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Nightshade',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 2.2.0',
                style: TextStyle(
                  fontSize: isMobile ? 13 : 14,
                  color: colors.textSecondary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Advanced astrophotography suite',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: colors.textMuted,
                ),
              ),
              SizedBox(height: isMobile ? 24 : 32),
              isMobile
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SettingsLinkButton(
                          icon: LucideIcons.github,
                          label: 'GitHub',
                          onTap: () =>
                              _launchUrl('https://github.com/nightshade-astro'),
                          colors: colors,
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Docs',
                          onTap: () =>
                              _launchUrl('https://nightshade.astro/docs'),
                          colors: colors,
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () =>
                              _launchUrl('https://discord.gg/nightshade'),
                          colors: colors,
                          compact: true,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SettingsLinkButton(
                          icon: LucideIcons.github,
                          label: 'GitHub',
                          onTap: () =>
                              _launchUrl('https://github.com/nightshade-astro'),
                          colors: colors,
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Documentation',
                          onTap: () =>
                              _launchUrl('https://nightshade.astro/docs'),
                          colors: colors,
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () =>
                              _launchUrl('https://discord.gg/nightshade'),
                          colors: colors,
                        ),
                      ],
                    ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      'System Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsInfoRow(
                        label: 'Platform',
                        value: Platform.operatingSystem,
                        colors: colors),
                    SettingsInfoRow(
                        label: 'OS Version',
                        value: Platform.operatingSystemVersion,
                        colors: colors),
                    SettingsInfoRow(
                        label: 'Dart Version',
                        value: Platform.version.split(' ').first,
                        colors: colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
