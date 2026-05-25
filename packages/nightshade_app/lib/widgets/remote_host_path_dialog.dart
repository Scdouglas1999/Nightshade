import 'package:flutter/material.dart';

/// Prompt for a filesystem path on the connected imaging host.
///
/// Remote clients cannot use [file_selector] for host FITS/master frames;
/// this dialog collects a host path string instead.
class RemoteHostPathDialog {
  RemoteHostPathDialog._();

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? initialPath,
    String? hintText,
  }) async {
    final controller = TextEditingController(text: initialPath ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Path on imaging host',
            hintText: hintText ?? r'C:\Captures\master_flat.fits',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                Navigator.of(ctx).pop(path);
              }
            },
            child: const Text('Use path'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
