// Wave 5 Agent 5 — Notification routing settings panel.
//
// Lives alongside `notification_settings.dart` (the legacy push toggles)
// and is embedded inside that page. Exposes:
//   * Master "Routing enabled" switch
//   * One row per NotificationCategory showing the current transports +
//     an "Edit" pencil that opens the per-category editor dialog.
//   * Test-send buttons for every transport (email, webhook, Pushover,
//     Telegram, Discord, MQTT) with inline success / error display.
//   * Per-transport credential entry forms.
//
// Style mirrors the existing settings widgets (NightshadeColors,
// SettingsSection, SettingRow). We never write to a transport's secret
// fields without the user clicking Save so the obscure text field is a
// no-op for the unchanged case.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class NotificationRoutingSettings extends ConsumerWidget {
  final bool isMobile;

  const NotificationRoutingSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final matrixAsync = ref.watch(notificationRoutingMatrixProvider);

    return matrixAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load routing matrix: $e',
            style: TextStyle(color: colors.error)),
      ),
      data: (matrix) => _build(context, ref, matrix),
    );
  }

  Widget _build(
      BuildContext context, WidgetRef ref, NotificationRoutingMatrix matrix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Routing master switch',
          children: [
            SettingRow(
              icon: LucideIcons.share2,
              title: 'Notification routing enabled',
              subtitle:
                  'When off, no per-category routing fires (legacy push still works)',
              trailing: SettingsSwitch(
                value: matrix.enabled,
                onChanged: (v) {
                  ref
                      .read(notificationRoutingMatrixProvider.notifier)
                      .setEnabled(v);
                },
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Per-event routing',
          children: [
            for (var i = 0; i < NotificationCategory.values.length; i++)
              _categoryRow(
                context,
                ref,
                NotificationCategory.values[i],
                matrix,
                isLast: i == NotificationCategory.values.length - 1,
              ),
          ],
        ),
        _TransportsSection(isMobile: isMobile),
      ],
    );
  }

  Widget _categoryRow(
    BuildContext context,
    WidgetRef ref,
    NotificationCategory category,
    NotificationRoutingMatrix matrix, {
    required bool isLast,
  }) {
    final rule = matrix.ruleFor(category);
    final summary = rule.enabled && rule.transports.isNotEmpty
        ? rule.transports.map((t) => t.label).join(' + ')
        : '(disabled)';

    return SettingRow(
      icon: _iconFor(category),
      title: category.label,
      subtitle: '→ $summary',
      trailing: NightshadeButton(
        label: 'Edit',
        variant: ButtonVariant.outline,
        size: ButtonSize.small,
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (_) => _CategoryEditorDialog(
              category: category,
              rule: rule,
              onSave: (updated) async {
                await ref
                    .read(notificationRoutingMatrixProvider.notifier)
                    .setRule(category, updated);
              },
            ),
          );
        },
      ),
      isLast: isLast,
    );
  }

  IconData _iconFor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.sequenceStarted:
      case NotificationCategory.sequenceResumed:
        return LucideIcons.play;
      case NotificationCategory.sequenceCompleted:
        return LucideIcons.checkCircle;
      case NotificationCategory.sequenceFailed:
        return LucideIcons.alertOctagon;
      case NotificationCategory.sequencePaused:
        return LucideIcons.pause;
      case NotificationCategory.targetStarted:
      case NotificationCategory.targetCompleted:
        return LucideIcons.crosshair;
      case NotificationCategory.meridianFlipPerformed:
        return LucideIcons.rotateCw;
      case NotificationCategory.autofocusCompleted:
      case NotificationCategory.autofocusFailed:
        return LucideIcons.focus;
      case NotificationCategory.frameCaptured:
        return LucideIcons.camera;
      case NotificationCategory.frameRejected:
        return LucideIcons.cameraOff;
      case NotificationCategory.exposureFailed:
        return LucideIcons.alertTriangle;
      case NotificationCategory.recoveryStarted:
      case NotificationCategory.recoveryRecovered:
      case NotificationCategory.recoveryGaveUp:
        return LucideIcons.lifeBuoy;
      case NotificationCategory.guidingLost:
      case NotificationCategory.guidingRecovered:
        return LucideIcons.target;
      case NotificationCategory.weatherUnsafe:
      case NotificationCategory.weatherSafeAgain:
        return LucideIcons.cloudRain;
      case NotificationCategory.cloudArriving:
      case NotificationCategory.cloudOpening:
        return LucideIcons.cloud;
      case NotificationCategory.diskSpaceLow:
        return LucideIcons.hardDrive;
      case NotificationCategory.equipmentDisconnected:
        return LucideIcons.unplug;
      case NotificationCategory.triggerFired:
        return LucideIcons.zap;
      case NotificationCategory.custom:
        return LucideIcons.bell;
    }
  }
}

// ---------------------------------------------------------------------------
// Per-category editor dialog
// ---------------------------------------------------------------------------

class _CategoryEditorDialog extends StatefulWidget {
  final NotificationCategory category;
  final NotificationRoutingRule rule;
  final Future<void> Function(NotificationRoutingRule) onSave;

  const _CategoryEditorDialog({
    required this.category,
    required this.rule,
    required this.onSave,
  });

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late bool _enabled;
  late Set<NotificationTransportKind> _selectedTransports;
  late EventSeverity _minSeverity;
  late TextEditingController _maxPerHourController;
  late TextEditingController _debounceController;
  late TextEditingController _titleTemplateController;
  late TextEditingController _bodyTemplateController;

  @override
  void initState() {
    super.initState();
    _enabled = widget.rule.enabled;
    _selectedTransports = widget.rule.transports.toSet();
    _minSeverity = widget.rule.minSeverity;
    _maxPerHourController =
        TextEditingController(text: widget.rule.maxPerHour.toString());
    _debounceController =
        TextEditingController(text: widget.rule.debounceSeconds.toString());
    _titleTemplateController =
        TextEditingController(text: widget.rule.titleTemplate ?? '');
    _bodyTemplateController =
        TextEditingController(text: widget.rule.bodyTemplate ?? '');
  }

  @override
  void dispose() {
    _maxPerHourController.dispose();
    _debounceController.dispose();
    _titleTemplateController.dispose();
    _bodyTemplateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NightshadeColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        widget.category.label,
        style: TextStyle(color: c.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: dialogMaxWidth(context, 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NightshadeSwitch(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  const SizedBox(width: 8),
                  Text('Rule enabled', style: TextStyle(color: c.textPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              Text('Transports', style: TextStyle(color: c.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: NotificationTransportKind.values.map((t) {
                  final selected = _selectedTransports.contains(t);
                  return FilterChip(
                    label: Text(t.label),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedTransports.add(t);
                      } else {
                        _selectedTransports.remove(t);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text('Minimum severity',
                  style: TextStyle(color: c.textSecondary)),
              const SizedBox(height: 6),
              DropdownButton<EventSeverity>(
                value: _minSeverity,
                isDense: true,
                items: EventSeverity.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.name),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _minSeverity = v);
                },
              ),
              const SizedBox(height: 12),
              _numericField(
                label: 'Max per hour (0 = unlimited)',
                controller: _maxPerHourController,
              ),
              const SizedBox(height: 12),
              _numericField(
                label: 'Debounce seconds (0 = none)',
                controller: _debounceController,
              ),
              const SizedBox(height: 12),
              Text('Title template (empty = default)',
                  style: TextStyle(color: c.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleTemplateController,
                style: TextStyle(color: c.textPrimary),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: r'e.g. ${target.name} done',
                ),
              ),
              const SizedBox(height: 12),
              Text('Body template (empty = default)',
                  style: TextStyle(color: c.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyTemplateController,
                maxLines: 3,
                style: TextStyle(color: c.textPrimary),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: r'e.g. Finished ${target.name} at ${time.local}',
                ),
              ),
              const SizedBox(height: 6),
              Text('Live preview:',
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                _previewBody(),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final maxPerHour = int.tryParse(_maxPerHourController.text) ?? 0;
            final debounce = int.tryParse(_debounceController.text) ?? 0;
            final updated = NotificationRoutingRule(
              transports: _selectedTransports.isEmpty
                  ? const [NotificationTransportKind.inApp]
                  : _selectedTransports.toList(),
              minSeverity: _minSeverity,
              maxPerHour: maxPerHour,
              debounceSeconds: debounce,
              titleTemplate: _titleTemplateController.text.trim().isEmpty
                  ? null
                  : _titleTemplateController.text,
              bodyTemplate: _bodyTemplateController.text.trim().isEmpty
                  ? null
                  : _bodyTemplateController.text,
              enabled: _enabled,
            );
            await widget.onSave(updated);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _numericField(
      {required String label, required TextEditingController controller}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style:
                  TextStyle(color: NightshadeColors.of(context).textSecondary)),
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: TextStyle(color: NightshadeColors.of(context).textPrimary),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ],
    );
  }

  String _previewBody() {
    final tpl = _bodyTemplateController.text.trim();
    if (tpl.isEmpty) return '(default template)';
    return previewInterpolation(tpl);
  }
}

// ---------------------------------------------------------------------------
// Per-transport configuration + test send sections
// ---------------------------------------------------------------------------

class _TransportsSection extends ConsumerWidget {
  final bool isMobile;

  const _TransportsSection({required this.isMobile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _EmailTransportSection(isMobile: isMobile),
        _WebhookTransportSection(isMobile: isMobile),
        _PushoverRoutingSection(isMobile: isMobile),
        _TelegramTransportSection(isMobile: isMobile),
        _DiscordRoutingSection(isMobile: isMobile),
        _MqttTransportSection(isMobile: isMobile),
      ],
    );
  }
}

// ---- Common helper: secure-field row ----------------------------------------

/// Wave 5 Agent 5 — masked input for secrets stored in flutter_secure_storage.
///
/// When a secret value is already in the store (controller has non-empty
/// text), the row renders a masked placeholder ("•••••••• (stored
/// securely)") and a "Replace" button. Tapping Replace switches the row
/// into edit mode with an empty text field; the user types a new value
/// and the next Save click writes it through the typed config's `save`
/// notifier, which in turn writes the secret via [SecretsStore].
class _SecretFieldRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final TextEditingController controller;

  /// `true` when the underlying store already has a non-empty value for
  /// this secret. Controls the masked-vs-edit initial state.
  final bool hasStoredValue;

  /// Optional hint shown while editing (e.g. "your bot token").
  final String? hint;

  final bool isMobile;

  const _SecretFieldRow({
    required this.icon,
    required this.title,
    required this.controller,
    required this.hasStoredValue,
    required this.isMobile,
    this.subtitle,
    this.hint,
  });

  @override
  State<_SecretFieldRow> createState() => _SecretFieldRowState();
}

class _SecretFieldRowState extends State<_SecretFieldRow> {
  /// `true` once the user clicks Replace OR if no value was stored yet
  /// (in which case there's nothing to mask).
  late bool _editing;

  @override
  void initState() {
    super.initState();
    _editing = !widget.hasStoredValue;
  }

  @override
  void didUpdateWidget(covariant _SecretFieldRow old) {
    super.didUpdateWidget(old);
    // If the store gains a value (e.g. after Save), drop back to masked
    // mode so the new value isn't shown.
    if (!old.hasStoredValue && widget.hasStoredValue) {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    if (_editing) {
      return SettingRow(
        icon: widget.icon,
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: settingsTrailingTextInput(
          context: context,
          controller: widget.controller,
          hint: widget.hint ?? '',
          isMobile: widget.isMobile,
          obscure: true,
        ),
      );
    }

    // Masked + Replace
    return SettingRow(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle ?? 'Stored securely in the OS keyring.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              '•••••••• (stored securely)',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            label: 'Replace',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () {
              widget.controller.text = '';
              setState(() => _editing = true);
            },
          ),
        ],
      ),
    );
  }
}

// ---- Common helper: test-send button with inline result ---------------------

class _TestSendButton extends ConsumerStatefulWidget {
  final NotificationTransportKind kind;
  const _TestSendButton({required this.kind});

  @override
  ConsumerState<_TestSendButton> createState() => _TestSendButtonState();
}

class _TestSendButtonState extends ConsumerState<_TestSendButton> {
  bool _busy = false;
  NotificationResult? _result;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _result!.success ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: _result!.success
                  ? NightshadeColors.of(context).success
                  : NightshadeColors.of(context).error,
            ),
          ),
        NightshadeButton(
          label: 'Send test',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          isLoading: _busy,
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final router = ref.read(notificationRouterProvider);
                  final res = await router.sendTest(widget.kind);
                  if (!context.mounted) return;
                  setState(() {
                    _result = res;
                    _busy = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      res.success
                          ? 'Test sent via ${widget.kind.label}'
                          : 'Failed: ${res.error}',
                    ),
                  ));
                },
        ),
      ],
    );
  }
}

// ---- Email ------------------------------------------------------------------

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
      error: (e, _) => Text('Email config error: $e'),
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
      error: (e, _) => Text('Discord error: $e'),
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
      error: (e, _) => Text('MQTT error: $e'),
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
