import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SavePathDialog extends ConsumerStatefulWidget {
  final String? currentPath;
  final bool createDateSubfolder;
  final bool createFilterSubfolders;

  const SavePathDialog({
    super.key,
    this.currentPath,
    this.createDateSubfolder = true,
    this.createFilterSubfolders = true,
  });

  static Future<SavePathResult?> show(
    BuildContext context, {
    String? currentPath,
    bool createDateSubfolder = true,
    bool createFilterSubfolders = true,
  }) {
    return showDialog<SavePathResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SavePathDialog(
        currentPath: currentPath,
        createDateSubfolder: createDateSubfolder,
        createFilterSubfolders: createFilterSubfolders,
      ),
    );
  }

  @override
  ConsumerState<SavePathDialog> createState() => _SavePathDialogState();
}

class _SavePathDialogState extends ConsumerState<SavePathDialog> {
  late TextEditingController _pathController;
  late bool _createDateSubfolder;
  late bool _createFilterSubfolders;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.currentPath ?? '');
    _createDateSubfolder = widget.createDateSubfolder;
    _createFilterSubfolders = widget.createFilterSubfolders;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browsePath() async {
    final result = await getDirectoryPath(
      confirmButtonText: 'Select',
      initialDirectory:
          _pathController.text.isNotEmpty ? _pathController.text : null,
    );

    if (result != null) {
      setState(() {
        _pathController.text = result;
      });
    }
  }

  void _confirm() {
    if (_pathController.text.isEmpty) return;

    Navigator.of(context).pop(SavePathResult(
      path: _pathController.text,
      createDateSubfolder: _createDateSubfolder,
      createFilterSubfolders: _createFilterSubfolders,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.folderOpen,
                    color: colors.warning,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save Location Required',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose where to save your flat frames',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Path input
            Row(
              children: [
                Expanded(
                  child: NightshadeTextField(
                    controller: _pathController,
                    hint: 'Select a folder...',
                    prefixIcon: LucideIcons.folder,
                  ),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: 'Browse...',
                  onPressed: _browsePath,
                  variant: ButtonVariant.outline,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Options
            _OptionCheckbox(
              value: _createDateSubfolder,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _createDateSubfolder = v);
                }
              },
              label: 'Create date subfolder automatically',
              description: 'e.g., /2026-01-07/',
              colors: colors,
            ),
            const SizedBox(height: 12),
            _OptionCheckbox(
              value: _createFilterSubfolders,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _createFilterSubfolders = v);
                }
              },
              label: 'Create filter subfolders',
              description: 'e.g., /L/, /R/, /G/, /B/',
              colors: colors,
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NightshadeButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  variant: ButtonVariant.ghost,
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: 'Continue',
                  onPressed: _pathController.text.isNotEmpty ? _confirm : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String description;
  final NightshadeColors colors;

  const _OptionCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.description,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavePathResult {
  final String path;
  final bool createDateSubfolder;
  final bool createFilterSubfolders;

  SavePathResult({
    required this.path,
    required this.createDateSubfolder,
    required this.createFilterSubfolders,
  });
}
