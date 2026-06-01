part of '../snippet_palette.dart';

extension _SnippetPaletteActions on _SnippetPaletteState {
void _showCreateSnippetDialog() {
    final selectedNodeId = ref.read(selectedNodeIdProvider);
    final sequence = ref.read(currentSequenceProvider);

    if (selectedNodeId == null || sequence == null) return;

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    SnippetCategory selectedCategory = SnippetCategory.custom;
    String selectedIconName = 'puzzle';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.colors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          title: Row(
            children: [
              Icon(
                LucideIcons.bookmark,
                size: 20,
                color: widget.colors.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Create Template',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              context,
              designMaxWidth: 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                _buildDialogLabel('Name'),
                const SizedBox(height: 8),
                _buildDialogTextField(
                  controller: nameController,
                  hintText: 'Enter template name',
                ),
                const SizedBox(height: 16),

                // Description field
                _buildDialogLabel('Description'),
                const SizedBox(height: 8),
                _buildDialogTextField(
                  controller: descriptionController,
                  hintText: 'Describe what this template does',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Category dropdown
                _buildDialogLabel('Category'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SnippetCategory>(
                      value: selectedCategory,
                      isExpanded: true,
                      dropdownColor: widget.colors.surfaceOverlay,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.colors.textPrimary,
                      ),
                      items: SnippetCategory.values.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Row(
                            children: [
                              Icon(
                                _getCategoryIcon(category),
                                size: 16,
                                color: _getCategoryColor(category),
                              ),
                              const SizedBox(width: 8),
                              Text(_getCategoryDisplayName(category)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedCategory = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Icon selection
                _buildDialogLabel('Icon'),
                const SizedBox(height: 8),
                _buildIconSelector(
                  selectedIconName: selectedIconName,
                  onIconSelected: (iconName) {
                    setDialogState(() => selectedIconName = iconName);
                  },
                ),
              ],
            ),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () {
                final name = nameController.text.trim();
                final description = descriptionController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a template name'),
                      backgroundColor: widget.colors.error,
                    ),
                  );
                  return;
                }

                _createSnippetFromSelection(
                  name: name,
                  description:
                      description.isEmpty ? 'Custom template' : description,
                  category: selectedCategory,
                  iconName: selectedIconName,
                  nodeIds: [selectedNodeId],
                  sequence: sequence,
                );

                Navigator.of(context).pop();
              },
              label: 'Create',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: widget.colors.textSecondary,
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 14,
        color: widget.colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 14,
          color: widget.colors.textMuted,
        ),
        filled: true,
        fillColor: widget.colors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.colors.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildIconSelector({
    required String selectedIconName,
    required Function(String) onIconSelected,
  }) {
    final iconOptions = [
      ('focus', LucideIcons.focus),
      ('palette', LucideIcons.palette),
      ('move', LucideIcons.move),
      ('shield', LucideIcons.shield),
      ('rotate-cw', LucideIcons.rotateCw),
      ('filter', LucideIcons.filter),
      ('camera', LucideIcons.camera),
      ('target', LucideIcons.target),
      ('clock', LucideIcons.clock),
      ('star', LucideIcons.star),
      ('zap', LucideIcons.zap),
      ('layers', LucideIcons.layers),
      ('repeat', LucideIcons.repeat),
      ('grid', LucideIcons.grid),
      ('puzzle', LucideIcons.puzzle),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: iconOptions.map((option) {
        final (name, icon) = option;
        final isSelected = name == selectedIconName;
        return InkWell(
          onTap: () => onIconSelected(name),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: isSelected
                ? NightshadeDecorations.selectedSurface(
                    widget.colors.primary,
                    borderRadius: BorderRadius.circular(8),
                    fillAlpha: 0.2,
                  )
                : BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? widget.colors.primary
                  : widget.colors.textSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _createSnippetFromSelection({
    required String name,
    required String description,
    required SnippetCategory category,
    required String iconName,
    required List<String> nodeIds,
    required Sequence sequence,
  }) {
    try {
      final snippet = createSnippetFromSelection(
        name: name,
        description: description,
        category: category,
        iconName: iconName,
        nodeIds: nodeIds,
        sequence: sequence,
      );

      ref.read(customSnippetsProvider.notifier).addSnippet(snippet);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "$name" created successfully'),
            backgroundColor: widget.colors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create template: $e'),
            backgroundColor: widget.colors.error,
          ),
        );
      }
    }
  }

  void _handleDeleteSnippet(TemplateSnippet snippet) {
    if (snippet.isBuiltIn) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.colors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: Row(
          children: [
            Icon(
              LucideIcons.trash2,
              size: 20,
              color: widget.colors.error,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Template',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: widget.colors.textPrimary,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            context,
            designMaxWidth: 400,
          ),
          child: Text(
            'Are you sure you want to delete "${snippet.name}"? This action cannot be undone.',
            style: TextStyle(
              fontSize: 14,
              color: widget.colors.textSecondary,
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              ref
                  .read(customSnippetsProvider.notifier)
                  .removeSnippet(snippet.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Template "${snippet.name}" deleted'),
                  backgroundColor: widget.colors.info,
                ),
              );
            },
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  /// Returns true if the running platform has a native share sheet
  /// `share_plus` can reach. Desktop platforms (Windows / Linux) have no
  /// system share sheet — those flow through `_handleExportSnippet`
  /// instead so the user manually moves the resulting file. macOS does
  /// have a share sheet, so it's allowed alongside iOS/Android.
  bool get _platformHasShareSheet {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _handleImportSnippet() async {
    try {
      final service = ref.read(snippetFileServiceProvider);
      final imported = await service.importSnippet();
      if (imported == null) return; // user cancelled

      await ref.read(customSnippetsProvider.notifier).addSnippet(imported);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported snippet "${imported.name}"'),
          backgroundColor: widget.colors.success,
        ),
      );
    } on SnippetVersionMismatchException catch (e) {
      // Loud, distinct path so the user understands an upgrade — not a
      // file fix — is required. Different copy from the schema-issue
      // branch below.
      if (!mounted) return;
      _showImportErrorDialog(
        title: 'Snippet from a newer Nightshade',
        body:
            'The selected snippet was authored with schema version ${e.fileVersion}, '
            'but this build of Nightshade only supports up to version '
            '${e.supportedVersion}. Update Nightshade and try again.',
      );
    } on SnippetImportException catch (e) {
      if (!mounted) return;
      _showImportErrorDialog(
        title: 'Snippet file is invalid',
        body:
            'The snippet file could not be imported. Fix the following issue'
            '${e.issues.length == 1 ? '' : 's'} and try again:',
        issues: e.issues,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import snippet: $e'),
          backgroundColor: widget.colors.error,
        ),
      );
    }
  }

  Future<void> _handleExportSnippet(TemplateSnippet snippet) async {
    try {
      final service = ref.read(snippetFileServiceProvider);
      final savedPath = await service.exportSnippet(snippet);
      if (savedPath == null) return; // user cancelled

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported "${snippet.name}" to ${p.basename(savedPath)}',
          ),
          backgroundColor: widget.colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export snippet: $e'),
          backgroundColor: widget.colors.error,
        ),
      );
    }
  }

  /// Share via the platform share sheet (iOS / Android / macOS). On
  /// platforms without a share sheet this falls back to
  /// [_handleExportSnippet] — the user gets a save dialog instead and
  /// can attach the resulting file to whatever they like.
  Future<void> _handleShareSnippet(TemplateSnippet snippet) async {
    if (!_platformHasShareSheet) {
      // Desktop fallback: open the export dialog. Same user-visible
      // result (a file they can attach to anything) without pretending
      // we can drive a system share UI that doesn't exist.
      await _handleExportSnippet(snippet);
      return;
    }

    try {
      final service = ref.read(snippetFileServiceProvider);

      // Stage the bundle in the OS temp directory under a filename the
      // share sheet preview can show. Cleanup of temp dirs is handled
      // by the OS — share_plus copies the file before returning, so a
      // later sweep won't break the share itself.
      final tmpDir = await getTemporaryDirectory();
      final filename = service.suggestedFilename(snippet);
      final tmpPath = p.join(tmpDir.path, filename);
      await service.exportSnippetToPath(snippet, tmpPath);

      await Share.shareXFiles(
        [XFile(tmpPath, mimeType: 'application/json')],
        subject: snippet.name,
        text:
            'Nightshade snippet: ${snippet.name}\n\n${snippet.description}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share snippet: $e'),
          backgroundColor: widget.colors.error,
        ),
      );
    }
  }

  void _showImportErrorDialog({
    required String title,
    required String body,
    List<SnippetImportIssue> issues = const [],
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.colors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: Row(
          children: [
            Icon(
              LucideIcons.alertTriangle,
              size: 20,
              color: widget.colors.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            ctx,
            designMaxWidth: 480,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.colors.textSecondary,
                ),
              ),
              if (issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    border: Border.all(color: widget.colors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: issues
                          .map(
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                i.field.isEmpty
                                    ? '• ${i.message}'
                                    : '• ${i.field}: ${i.message}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.colors.textPrimary,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Close',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}
