part of '../notification_routing_settings.dart';

class _EmailTransportSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _EmailTransportSection({required this.isMobile});

  @override
  ConsumerState<_EmailTransportSection> createState() =>
      _EmailTransportSectionState();
}

class _EmailTransportSectionState
    extends ConsumerState<_EmailTransportSection> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _useTls = true;
  bool _initialized = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(emailTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const NightshadeInlineBanner(
        message: 'Could not load email routing configuration.',
        severity: NightshadeAlertSeverity.error,
      ),
      data: (cfg) {
        if (!_initialized) {
          _host.text = cfg.smtpHost;
          _port.text = cfg.smtpPort.toString();
          _user.text = cfg.username;
          _pass.text = cfg.password;
          _from.text = cfg.fromAddress;
          _to.text = cfg.toAddress;
          _useTls = cfg.useTls;
          _initialized = true;
        }
        return SettingsSection(
          title: 'Email (SMTP)',
          children: [
            _textRow(LucideIcons.server, 'SMTP host', _host,
                hint: 'smtp.gmail.com'),
            _textRow(LucideIcons.hash, 'SMTP port', _port,
                hint: '587', isNumber: true),
            _textRow(LucideIcons.user, 'Username', _user, hint: 'optional'),
            _SecretFieldRow(
              icon: LucideIcons.key,
              title: 'Password',
              subtitle: 'Stored securely in the OS keyring.',
              controller: _pass,
              hasStoredValue: cfg.password.isNotEmpty,
              isMobile: widget.isMobile,
              hint: 'app password / SMTP password',
            ),
            SettingRow(
              icon: LucideIcons.lock,
              title: 'Use STARTTLS',
              subtitle: 'Recommended for ports 25/587',
              trailing: SettingsSwitch(
                value: _useTls,
                onChanged: (v) => setState(() => _useTls = v),
              ),
            ),
            _textRow(LucideIcons.atSign, 'From address', _from,
                hint: 'you@example.com'),
            _textRow(LucideIcons.send, 'To address', _to,
                hint: 'you@example.com'),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save SMTP settings',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final updated = EmailTransportConfig(
                    smtpHost: _host.text.trim(),
                    smtpPort: int.tryParse(_port.text) ?? 587,
                    username: _user.text,
                    password: _pass.text,
                    useTls: _useTls,
                    fromAddress: _from.text.trim(),
                    toAddress: _to.text.trim(),
                  );
                  await ref
                      .read(emailTransportConfigProvider.notifier)
                      .save(updated);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email config saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test email',
              subtitle: 'Send a test email through the configured SMTP server',
              trailing: _TestSendButton(kind: NotificationTransportKind.email),
              isLast: true,
            ),
          ],
        );
      },
    );
  }

  Widget _textRow(IconData icon, String title, TextEditingController c,
      {String? hint, bool obscure = false, bool isNumber = false}) {
    return SettingRow(
      icon: icon,
      title: title,
      trailing: settingsTrailingTextInput(
        context: context,
        controller: c,
        hint: hint ?? '',
        isMobile: widget.isMobile,
        obscure: obscure,
      ),
    );
  }
}

// ---- Webhook ----------------------------------------------------------------
