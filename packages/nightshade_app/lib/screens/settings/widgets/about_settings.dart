import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

class AboutSettings extends ConsumerWidget {
  final bool isMobile;

  const AboutSettings({super.key, this.isMobile = false});

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    var launched = false;
    try {
      launched = await canLaunchUrl(uri) && await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      context.showErrorSnackBar('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final appVersion = ref.watch(appVersionProvider);
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
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize20
                      : NightshadeTypography.fontSize24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version ${appVersion.version}',
                style: TextStyle(
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize13
                      : NightshadeTypography.fontSize14,
                  color: colors.textSecondary,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Advanced astrophotography suite',
                style: TextStyle(
                  fontSize: isMobile
                      ? NightshadeTypography.fontSize12
                      : NightshadeTypography.fontSize13,
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
                          onTap: () => _launchUrl(
                              context, 'https://github.com/nightshade-astro'),
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Docs',
                          onTap: () => _launchUrl(
                              context, 'https://nightshade.astro/docs'),
                          compact: true,
                        ),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () => _launchUrl(
                              context, 'https://discord.gg/nightshade'),
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
                          onTap: () => _launchUrl(
                              context, 'https://github.com/nightshade-astro'),
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.bookOpen,
                          label: 'Documentation',
                          onTap: () => _launchUrl(
                              context, 'https://nightshade.astro/docs'),
                        ),
                        const SizedBox(width: 12),
                        SettingsLinkButton(
                          icon: LucideIcons.messageCircle,
                          label: 'Discord',
                          onTap: () => _launchUrl(
                              context, 'https://discord.gg/nightshade'),
                        ),
                      ],
                    ),
              const SizedBox(height: 48),
              NightshadeCard(
                variant: CardVariant.subtle,
                borderRadius: NightshadeTokens.radiusInline8,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'System Information',
                      style: NightshadeTypography.h5
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    SettingsInfoRow(
                        label: 'Platform', value: Platform.operatingSystem),
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
