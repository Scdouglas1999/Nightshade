// Part of ../instruction_node_properties.dart -- extracted for maintainability.
//
// Notification + script properties: NotificationProperties with its transport multi-select and live preview, plus ScriptProperties.
part of '../instruction_node_properties.dart';

class NotificationProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final NotificationNode node;

  const NotificationProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wave 5 Agent 5 — pull live transport configs so we know which
    // transports are *enabled & configured*. Showing every transport in
    // the chip list would confuse the user with "Telegram" chips that
    // can never actually fire because no bot token was saved.
    final emailAsync = ref.watch(emailTransportConfigProvider);
    final pushoverAsync = ref.watch(pushoverTransportConfigProvider);
    final telegramAsync = ref.watch(telegramTransportConfigProvider);
    final discordAsync = ref.watch(discordTransportConfigProvider);
    final mqttAsync = ref.watch(mqttTransportConfigProvider);
    final webhookAsync = ref.watch(webhookTransportConfigProvider);

    bool isConfigured(NotificationTransportKind kind) {
      switch (kind) {
        case NotificationTransportKind.inApp:
        case NotificationTransportKind.systemPush:
          // Always available — no credentials required.
          return true;
        case NotificationTransportKind.email:
          return emailAsync.valueOrNull?.isConfigured ?? false;
        case NotificationTransportKind.webhookGeneric:
          return webhookAsync.valueOrNull?.isConfigured ?? false;
        case NotificationTransportKind.pushover:
          return pushoverAsync.valueOrNull?.isConfigured ?? false;
        case NotificationTransportKind.telegram:
          return telegramAsync.valueOrNull?.isConfigured ?? false;
        case NotificationTransportKind.discord:
          return discordAsync.valueOrNull?.isConfigured ?? false;
        case NotificationTransportKind.mqtt:
          return mqttAsync.valueOrNull?.isConfigured ?? false;
      }
    }

    final selected =
        node.explicitTransports?.toSet() ?? <NotificationTransportKind>{};
    final fontSize = Responsive.fontSize(context, 13);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Settings',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Title (template)',
          child: NodeTextInput(
            colors: colors,
            value: node.title,
            hint: r'e.g. Frame ${frame} of ${target.name} done',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(title: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Message (template, multi-line)',
          child: NodeTextInput(
            colors: colors,
            value: node.message,
            hint: r'e.g. Captured ${frame} frames at ${time.local}',
            maxLines: 4,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(message: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Level',
          child: NodeDropdown<NotificationLevel>(
            colors: colors,
            value: node.level,
            items: NotificationLevel.values,
            labelBuilder: (l) {
              switch (l) {
                case NotificationLevel.info:
                  return 'Info';
                case NotificationLevel.warning:
                  return 'Warning';
                case NotificationLevel.error:
                  return 'Error';
                case NotificationLevel.success:
                  return 'Success';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(level: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Send via',
          child: _TransportMultiSelect(
            colors: colors,
            selected: selected,
            isConfigured: isConfigured,
            onChanged: (next) {
              if (next.isEmpty) {
                // PHASE-5: NotificationNode.copyWith no longer has
                // `clearExplicitTransports`; clearing back to the
                // matrix default requires constructing a new node
                // without the `explicitTransports` argument.
                ref.read(currentSequenceProvider.notifier).updateNode(
                      NotificationNode(
                        id: node.id,
                        name: node.name,
                        isEnabled: node.isEnabled,
                        childIds: node.childIds,
                        parentId: node.parentId,
                        orderIndex: node.orderIndex,
                        comment: node.comment,
                        title: node.title,
                        message: node.message,
                        level: node.level,
                      ),
                    );
              } else {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(explicitTransports: next.toList()),
                    );
              }
            },
          ),
        ),
        _NotificationPreview(colors: colors, node: node),
      ],
    );
  }
}

/// Chip-based multi-select for NotificationTransportKind. Greyed-out
/// chips for unconfigured transports so the user knows why their pick
/// won't fire until they fill in the credentials. Selecting an
/// unconfigured transport is still allowed — it just won't send until
/// the user goes to Settings → Notifications and configures it.
class _TransportMultiSelect extends StatelessWidget {
  final NightshadeColors colors;
  final Set<NotificationTransportKind> selected;
  final bool Function(NotificationTransportKind) isConfigured;
  final ValueChanged<Set<NotificationTransportKind>> onChanged;

  const _TransportMultiSelect({
    required this.colors,
    required this.selected,
    required this.isConfigured,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const all = NotificationTransportKind.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Empty = use the matrix\'s default for "Custom" notifications. Tick one or more to override per-node.',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: all.map((kind) {
            final isSelected = selected.contains(kind);
            final configured = isConfigured(kind);
            return FilterChip(
              key: ValueKey('notif_transport_${kind.storageKey}'),
              label: Text(
                configured ? kind.label : '${kind.label} (not configured)',
                style: TextStyle(
                  fontSize: 12,
                  color: configured
                      ? (isSelected ? colors.background : colors.textPrimary)
                      : colors.textMuted,
                ),
              ),
              selected: isSelected,
              showCheckmark: false,
              selectedColor: colors.primary,
              backgroundColor: colors.surfaceAlt,
              side: BorderSide(
                color: configured
                    ? colors.border
                    : colors.warning.withValues(alpha: 0.6),
              ),
              onSelected: (sel) {
                final next = Set<NotificationTransportKind>.of(selected);
                if (sel) {
                  next.add(kind);
                } else {
                  next.remove(kind);
                }
                onChanged(next);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  final NightshadeColors colors;
  final NotificationNode node;

  const _NotificationPreview({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final title = previewInterpolation(node.title);
    final body = previewInterpolation(node.message);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title.isEmpty ? '(no title)' : title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: title.isEmpty ? colors.textMuted : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body.isEmpty ? '(no body)' : body,
            style: TextStyle(
              fontSize: 12,
              color: body.isEmpty ? colors.textMuted : colors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class ScriptProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ScriptNode node;

  const ScriptProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Script Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Script Path',
          child: NodeTextInput(
            colors: colors,
            value: node.scriptPath,
            hint: 'Path to script file',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(scriptPath: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Arguments',
          child: NodeTextInput(
            colors: colors,
            value: node.arguments.join(' '),
            hint: 'Space-separated arguments',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(
                        arguments: value
                            .split(' ')
                            .where((s) => s.isNotEmpty)
                            .toList()),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Timeout',
          child: NodeNumberInput(
            colors: colors,
            value: (node.timeoutSecs ?? 300).toDouble(),
            suffix: 's',
            min: 1,
            max: 3600,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.toInt()),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.tintedBadge(
            colors.warning,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scripts run with sequence context variables available as environment variables',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
