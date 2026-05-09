import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class RemoteDirectoryPickerDialog extends ConsumerStatefulWidget {
  final String title;
  final String? initialPath;

  const RemoteDirectoryPickerDialog({
    super.key,
    required this.title,
    this.initialPath,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? initialPath,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => RemoteDirectoryPickerDialog(
        title: title,
        initialPath: initialPath,
      ),
    );
  }

  @override
  ConsumerState<RemoteDirectoryPickerDialog> createState() =>
      _RemoteDirectoryPickerDialogState();
}

class _RemoteDirectoryPickerDialogState
    extends ConsumerState<RemoteDirectoryPickerDialog> {
  RemoteDirectoryListing? _listing;
  String? _selectedPath;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  Future<void> _load(String? path) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      setState(() {
        _loading = false;
        _error = 'Remote directory browsing is only available while connected to a host.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final listing = await backend.browseRemoteDirectories(path: path);
      setState(() {
        _listing = listing;
        _selectedPath = listing.currentPath ?? path;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectCurrentDirectory() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend || _selectedPath == null) {
      return;
    }

    final validation = await backend.validateRemoteDirectory(
      _selectedPath!,
      mustExist: true,
      mustBeWritable: true,
    );

    if (!mounted) return;
    if (validation['valid'] == true) {
      Navigator.of(context).pop(
        validation['normalizedPath'] as String? ?? _selectedPath!,
      );
      return;
    }

    setState(() {
      _error = validation['error'] as String? ??
          'The selected host directory is not writable.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_listing != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors?.surfaceAlt ?? Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _listing?.currentPath ?? 'Host roots',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors?.error ?? Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    if (_listing?.parentPath != null)
                      ListTile(
                        leading: const Icon(LucideIcons.arrowUp),
                        title: const Text('Parent folder'),
                        onTap: () => _load(_listing?.parentPath),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _listing?.directories.length ?? 0,
                        itemBuilder: (context, index) {
                          final directory = _listing!.directories[index];
                          final isSelected = _selectedPath == directory.path;
                          return ListTile(
                            selected: isSelected,
                            leading: const Icon(LucideIcons.folder),
                            title: Text(directory.name),
                            subtitle: Text(
                              directory.path,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedPath = directory.path;
                              });
                            },
                            onLongPress: () => _load(directory.path),
                            trailing: IconButton(
                              icon: const Icon(LucideIcons.chevronRight),
                              onPressed: () => _load(directory.path),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _loading || _selectedPath == null ? null : _selectCurrentDirectory,
          child: const Text('Use this folder'),
        ),
      ],
    );
  }
}
