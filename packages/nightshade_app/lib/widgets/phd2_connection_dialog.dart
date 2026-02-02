import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Reusable PHD2 connection configuration dialog.
///
/// Allows users to enter PHD2 host and port, saves settings,
/// and initiates connection.
class Phd2ConnectionDialog extends ConsumerStatefulWidget {
  final String initialHost;
  final int initialPort;

  const Phd2ConnectionDialog({
    super.key,
    required this.initialHost,
    required this.initialPort,
  });

  /// Shows the PHD2 connection dialog.
  ///
  /// Reads current settings from [appSettingsProvider] and displays
  /// a dialog for the user to configure and connect.
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final settings = await ref.read(appSettingsProvider.future);
    if (!context.mounted) return;
    return showDialog(
      context: context,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: Phd2ConnectionDialog(
          initialHost: settings.phd2Host,
          initialPort: settings.phd2Port,
        ),
      ),
    );
  }

  @override
  ConsumerState<Phd2ConnectionDialog> createState() => _Phd2ConnectionDialogState();
}

class _Phd2ConnectionDialogState extends ConsumerState<Phd2ConnectionDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.initialHost);
    _portController = TextEditingController(text: widget.initialPort.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'PHD2 Connection',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 360,
          minWidth: 280,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _hostController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Host',
                labelStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              style: TextStyle(color: colors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          onPressed: _connect,
          style: FilledButton.styleFrom(backgroundColor: colors.primary),
          child: const Text('Connect'),
        ),
      ],
    );
  }

  Future<void> _connect() async {
    Navigator.pop(context);
    final host = _hostController.text;
    final port = int.tryParse(_portController.text) ?? 4400;

    // Save settings
    await ref.read(appSettingsProvider.notifier).setPhd2Host(host);
    await ref.read(appSettingsProvider.notifier).setPhd2Port(port);

    // Connect
    ref.read(phd2ControllerProvider).connect(host, port);
  }
}
