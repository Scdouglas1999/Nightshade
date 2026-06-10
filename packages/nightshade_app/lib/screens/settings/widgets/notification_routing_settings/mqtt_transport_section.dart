part of '../notification_routing_settings.dart';

class _MqttTransportSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _MqttTransportSection({required this.isMobile});

  @override
  ConsumerState<_MqttTransportSection> createState() =>
      _MqttTransportSectionState();
}

class _MqttTransportSectionState extends ConsumerState<_MqttTransportSection> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _topic = TextEditingController();
  final _clientId = TextEditingController();
  int _qos = 0;
  bool _retain = false;
  bool _tls = false;
  bool _initialized = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _topic.dispose();
    _clientId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(mqttTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const NightshadeInlineBanner(
        message: 'Could not load MQTT routing configuration.',
        severity: NightshadeAlertSeverity.error,
      ),
      data: (cfg) {
        if (!_initialized) {
          _host.text = cfg.host;
          _port.text = cfg.port.toString();
          _user.text = cfg.username ?? '';
          _pass.text = cfg.password ?? '';
          _topic.text = cfg.topic;
          _clientId.text = cfg.clientId;
          _qos = cfg.qos;
          _retain = cfg.retain;
          _tls = cfg.useTls;
          _initialized = true;
        }
        return SettingsSection(
          title: 'MQTT broker',
          children: [
            _row(LucideIcons.server, 'Broker host', _host, 'mqtt.example.com'),
            _row(LucideIcons.hash, 'Port', _port, '1883', isNumber: true),
            _row(LucideIcons.user, 'Username (optional)', _user, ''),
            _SecretFieldRow(
              icon: LucideIcons.key,
              title: 'Password (optional)',
              controller: _pass,
              hasStoredValue: (cfg.password ?? '').isNotEmpty,
              isMobile: widget.isMobile,
              hint: 'broker password',
            ),
            _row(LucideIcons.hash, 'Topic', _topic, 'nightshade/notifications'),
            _row(LucideIcons.tag, 'Client ID', _clientId, 'nightshade'),
            SettingRow(
              icon: LucideIcons.lock,
              title: 'Use TLS',
              trailing: SettingsSwitch(
                value: _tls,
                onChanged: (v) => setState(() => _tls = v),
              ),
            ),
            SettingRow(
              icon: LucideIcons.shield,
              title: 'QoS',
              trailing: DropdownButton<int>(
                value: _qos,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('0 (at most once)')),
                  DropdownMenuItem(value: 1, child: Text('1 (at least once)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _qos = v);
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.archive,
              title: 'Retain',
              trailing: SettingsSwitch(
                value: _retain,
                onChanged: (v) => setState(() => _retain = v),
              ),
            ),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save MQTT config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final cfg2 = MqttTransportConfig(
                    host: _host.text.trim(),
                    port: int.tryParse(_port.text) ?? 1883,
                    username:
                        _user.text.trim().isEmpty ? null : _user.text.trim(),
                    password: _pass.text.trim().isEmpty ? null : _pass.text,
                    topic: _topic.text.trim(),
                    qos: _qos,
                    retain: _retain,
                    useTls: _tls,
                    clientId: _clientId.text.trim().isEmpty
                        ? 'nightshade'
                        : _clientId.text.trim(),
                  );
                  await ref
                      .read(mqttTransportConfigProvider.notifier)
                      .save(cfg2);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('MQTT config saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test MQTT publish',
              trailing: _TestSendButton(kind: NotificationTransportKind.mqtt),
              isLast: true,
            ),
          ],
        );
      },
    );
  }

  Widget _row(IconData icon, String title, TextEditingController c, String hint,
      {bool obscure = false, bool isNumber = false}) {
    return SettingRow(
      icon: icon,
      title: title,
      trailing: settingsTrailingTextInput(
        context: context,
        controller: c,
        hint: hint,
        isMobile: widget.isMobile,
        obscure: obscure,
      ),
    );
  }
}
