part of '../annotation_panel.dart';

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NightshadeDialog(
      title: 'Save Preset',
      icon: LucideIcons.save,
      width: 420,
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          label: 'Save',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
      child: NightshadeTextField(
        label: 'Preset name',
        hint: 'e.g. Deep sky defaults',
        controller: _controller,
      ),
    );
  }
}
