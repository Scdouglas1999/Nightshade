part of '../notification_routing_settings.dart';

class _PushoverRoutingSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _PushoverRoutingSection({required this.isMobile});

  @override
  ConsumerState<_PushoverRoutingSection> createState() =>
      _PushoverRoutingSectionState();
}

class _PushoverRoutingSectionState
    extends ConsumerState<_PushoverRoutingSection> {
  final _token = TextEditingController();
  final _user = TextEditingController();
  final _device = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _token.dispose();
    _user.dispose();
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(pushoverTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Pushover error: $e'),
      data: (cfg) {
        if (!_initialized) {
          _token.text = cfg.apiToken;
          _user.text = cfg.userKey;
          _device.text = cfg.device ?? '';
          _initialized = true;
        }
        return SettingsSection(
          title: 'Pushover (routing matrix)',
          children: [
            _SecretFieldRow(
              icon: LucideIcons.key,
              title: 'API token',
              controller: _token,
              hasStoredValue: cfg.apiToken.isNotEmpty,
              isMobile: widget.isMobile,
              hint: 'Pushover application token',
            ),
            _SecretFieldRow(
              icon: LucideIcons.user,
              title: 'User key',
              controller: _user,
              hasStoredValue: cfg.userKey.isNotEmpty,
              isMobile: widget.isMobile,
              hint: 'Pushover user / group key',
            ),
            _row(LucideIcons.smartphone, 'Device (optional)', _device),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save Pushover config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final cfg2 = PushoverTransportConfig(
                    apiToken: _token.text.trim(),
                    userKey: _user.text.trim(),
                    device: _device.text.trim().isEmpty
                        ? null
                        : _device.text.trim(),
                  );
                  await ref
                      .read(pushoverTransportConfigProvider.notifier)
                      .save(cfg2);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pushover (routing) saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test Pushover',
              trailing:
                  _TestSendButton(kind: NotificationTransportKind.pushover),
              isLast: true,
            ),
          ],
        );
      },
    );
  }

  Widget _row(IconData icon, String title, TextEditingController c,
      {bool obscure = false}) {
    return SettingRow(
      icon: icon,
      title: title,
      trailing: settingsTrailingTextInput(
        context: context,
        controller: c,
        isMobile: widget.isMobile,
        obscure: obscure,
      ),
    );
  }
}

// ---- Telegram ----------------------------------------------------------------
