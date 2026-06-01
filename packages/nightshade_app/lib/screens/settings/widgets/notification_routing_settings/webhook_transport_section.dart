part of '../notification_routing_settings.dart';

class _WebhookTransportSection extends ConsumerStatefulWidget {
  final bool isMobile;
  const _WebhookTransportSection({required this.isMobile});

  @override
  ConsumerState<_WebhookTransportSection> createState() =>
      _WebhookTransportSectionState();
}

class _WebhookTransportSectionState
    extends ConsumerState<_WebhookTransportSection> {
  final _url = TextEditingController();
  final _body = TextEditingController();
  final _headers = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _url.dispose();
    _body.dispose();
    _headers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(webhookTransportConfigProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Webhook config error: $e'),
      data: (cfg) {
        if (!_initialized) {
          _url.text = cfg.url;
          _body.text = cfg.bodyTemplate ?? '';
          _headers.text =
              cfg.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
          _initialized = true;
        }
        return SettingsSection(
          title: 'Generic webhook',
          children: [
            SettingRow(
              icon: LucideIcons.link,
              title: 'URL',
              subtitle: 'POST target (Home Assistant, n8n, etc.)',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _url,
                hint: 'https://example.com/webhook',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.fileText,
              title: 'Body template',
              subtitle: r'Variables: ${title} ${body} ${category} ${timestamp}',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _body,
                hint: '{"text":"\${title}"}',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.list,
              title: 'Headers',
              subtitle: 'One per line, format: Name: value',
              trailing: settingsTrailingTextInput(
                context: context,
                controller: _headers,
                hint: 'Authorization: Bearer …',
                isMobile: widget.isMobile,
              ),
            ),
            SettingRow(
              icon: LucideIcons.save,
              title: 'Save webhook config',
              trailing: NightshadeButton(
                label: 'Save',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () async {
                  final headers = <String, String>{};
                  for (final line in _headers.text.split('\n')) {
                    final idx = line.indexOf(':');
                    if (idx <= 0) continue;
                    headers[line.substring(0, idx).trim()] =
                        line.substring(idx + 1).trim();
                  }
                  final cfg2 = WebhookTransportConfig(
                    url: _url.text.trim(),
                    headers: headers,
                    bodyTemplate: _body.text.trim().isEmpty ? null : _body.text,
                  );
                  await ref
                      .read(webhookTransportConfigProvider.notifier)
                      .save(cfg2);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Webhook config saved')),
                  );
                },
              ),
            ),
            const SettingRow(
              icon: LucideIcons.send,
              title: 'Test webhook',
              trailing: _TestSendButton(
                  kind: NotificationTransportKind.webhookGeneric),
              isLast: true,
            ),
          ],
        );
      },
    );
  }
}

// ---- Pushover (routing-aware) ------------------------------------------------
