import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_widgets.dart';

class AboutSettings extends StatelessWidget {
  final bool isMobile;

  const AboutSettings({super.key, this.isMobile = false});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final logoSize = isMobile ? 64.0 : 80.0;
    final logoIconSize = isMobile ? 32.0 : 40.0;

    return SettingsPage(
      title: 'About',
      description: 'Application information',
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                decoration: NightshadeDecorations.iconChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: logoIconSize,
                  color: colors.primary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Nightshade',
                style: TextStyle(
                  fontSize: isMobile ? NightshadeTypography.fontSize20 : NightshadeTypography.fontSize24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 2.2.0',
                style: TextStyle(
                  fontSize: isMobile ? NightshadeTypography.fontSize13 : NightshadeTypography.fontSize14,
                  color: colors.textSecondary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Advanced astrophotography suite',
                style: TextStyle(
                  fontSize: isMobile ? NightshadeTypography.fontSize12 : NightshadeTypography.fontSize13,
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
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Docs',
                          onTap: () =>
                              _launchUrl('https://nightshade.astro/docs'),
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () =>
                              _launchUrl('https://discord.gg/nightshade'),
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
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Documentation',
                          onTap: () =>
                              _launchUrl('https://nightshade.astro/docs'),
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () =>
                              _launchUrl('https://discord.gg/nightshade'),
                        ),
                      ],
                    ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      'System Information',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsInfoRow(
                        label: 'Platform',
                        value: Platform.operatingSystem),
                    SettingsInfoRow(
                        label: 'OS Version',
                        value: Platform.operatingSystemVersion),
                    SettingsInfoRow(
                        label: 'Dart Version',
                        value: Platform.version.split(' ').first),
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
