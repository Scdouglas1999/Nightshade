part of '../notification_routing_settings.dart';

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
        _HomeAssistantSection(isMobile: isMobile),
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
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              '•••••••• (stored securely)',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
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
              _result!.success ? NightshadeIcons.success : NightshadeIcons.error,
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
