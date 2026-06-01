part of '../notification_routing_settings.dart';

class _TelegramTransportSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _TelegramTransportSection({required this.isMobile});

  @override
  ConsumerState<_TelegramTransportSection> createState() =>
      _TelegramTransportSectionState();
}

class _TelegramTransportSectionState
    extends ConsumerState<_TelegramTransportSection> {
  final _bot = TextEditingController();
  final _chat = TextEditingController();
  bool _silent = false;
  bool _initialized = false;

  @override
  void dispose() {
    _bot.dispose();
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(telegramTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Telegram error: $e'),
      data: (cfg) {
        if (!_initialized) {
          _bot.text = cfg.botToken;
          _chat.text = cfg.chatId;
          _silent = cfg.disableNotification;
          _initialized = true;
        }
        return SettingsSection(
          title: 'Telegram',
          children: [
            _SecretFieldRow(
              icon: LucideIcons.key,
              title: 'Bot token',
              controller: _bot,
              hasStoredValue: cfg.botToken.isNotEmpty,
              isMobile: widget.isMobile,
              hint: '1234:abcd…',
            ),
            SettingRow(
              icon: LucideIcons.messageCircle,
              title: 'Chat ID',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _chat,
                hint: '@channel or numeric id',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.bellOff,
              title: 'Silent notification',
              trailing: SettingsSwitch(
                value: _silent,
                onChanged: (v) => setState(() => _silent = v),
              ),
            ),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save Telegram config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final cfg2 = TelegramTransportConfig(
                    botToken: _bot.text.trim(),
                    chatId: _chat.text.trim(),
                    disableNotification: _silent,
                  );
                  await ref
                      .read(telegramTransportConfigProvider.notifier)
                      .save(cfg2);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Telegram config saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test Telegram',
              trailing:
                  _TestSendButton(kind: NotificationTransportKind.telegram),
              isLast: true,
            ),
          ],
        );
      },
    );
  }
}

// ---- Discord (routing-aware) ------------------------------------------------
