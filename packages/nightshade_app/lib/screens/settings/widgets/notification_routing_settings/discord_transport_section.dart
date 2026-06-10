part of '../notification_routing_settings.dart';

class _DiscordRoutingSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _DiscordRoutingSection({required this.isMobile});

  @override
  ConsumerState<_DiscordRoutingSection> createState() =>
      _DiscordRoutingSectionState();
}

class _DiscordRoutingSectionState
    extends ConsumerState<_DiscordRoutingSection> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(discordTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const NightshadeInlineBanner(
        message: 'Could not load Discord routing configuration.',
        severity: NightshadeAlertSeverity.error,
      ),
      data: (cfg) {
        if (!_initialized) {
          _url.text = cfg.webhookUrl;
          _user.text = cfg.username ?? '';
          _initialized = true;
        }
        return SettingsSection(
          title: 'Discord (routing matrix)',
          children: [
            _SecretFieldRow(
              icon: LucideIcons.link,
              title: 'Webhook URL',
              subtitle:
                  'The URL itself authenticates the request, so it is stored securely.',
              controller: _url,
              hasStoredValue: cfg.webhookUrl.isNotEmpty,
              isMobile: widget.isMobile,
              hint: 'https://discord.com/api/webhooks/…',
            ),
            SettingRow(
              icon: LucideIcons.user,
              title: 'Username override',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _user,
                hint: 'Nightshade',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save Discord config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final cfg2 = DiscordTransportConfig(
                    webhookUrl: _url.text.trim(),
                    username:
                        _user.text.trim().isEmpty ? null : _user.text.trim(),
                  );
                  await ref
                      .read(discordTransportConfigProvider.notifier)
                      .save(cfg2);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Discord (routing) saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test Discord',
              trailing:
                  _TestSendButton(kind: NotificationTransportKind.discord),
              isLast: true,
            ),
          ],
        );
      },
    );
  }
}

// ---- MQTT --------------------------------------------------------------------
