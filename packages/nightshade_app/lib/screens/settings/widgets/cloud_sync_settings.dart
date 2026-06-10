// Cloud backup/sync — "Backup & Sync" settings card.
//
// UI surface for the bundle-based cloud sync in
// nightshade_core/src/services/sync/. Configures the WebDAV target
// (server URL + username in app settings, password in the OS keyring),
// the machine name, opt-in auto-push, and exposes manual actions:
// "Push now" and "Browse remote backups → restore".
//
// CONFLICT STANCE shown to the user: sync is bundle-based, no merging —
// restoring a remote bundle replaces local configuration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/confirm_dialog.dart';
import '../../../utils/snackbar_helper.dart';

class CloudSyncCard extends ConsumerStatefulWidget {
  const CloudSyncCard({super.key});

  @override
  ConsumerState<CloudSyncCard> createState() => _CloudSyncCardState();
}

class _CloudSyncCardState extends ConsumerState<CloudSyncCard> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _machineNameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _pushing = false;
  bool _autoPushEnabled = false;
  bool _hasStoredPassword = false;
  DateTime? _lastPushAt;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _machineNameController.dispose();
    super.dispose();
  }

  SyncService get _service => ref.read(syncServiceProvider);

  Future<void> _load() async {
    try {
      final service = _service;
      final config = await service.loadConfig();
      final hasPassword = await service.hasStoredPassword();
      final status = await service.status();
      if (!mounted) return;
      setState(() {
        _serverUrlController.text = config.serverUrl;
        _usernameController.text = config.username;
        _machineNameController.text = config.machineName;
        _autoPushEnabled = config.autoPushEnabled;
        _hasStoredPassword = hasPassword;
        _lastPushAt = status.lastPushAt;
        _lastError = status.lastError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showErrorSnackBar('Failed to load sync settings: $e');
    }
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      final password = _passwordController.text;
      await _service.saveConfig(
        SyncConfig(
          serverUrl: _serverUrlController.text.trim(),
          username: _usernameController.text.trim(),
          machineName: _machineNameController.text.trim(),
          autoPushEnabled: _autoPushEnabled,
        ),
        // Only touch the keyring when the user typed something; leaving
        // the field blank keeps the stored password.
        password: password.isEmpty ? null : password,
      );
      if (password.isNotEmpty) {
        _passwordController.clear();
        _hasStoredPassword = true;
      }
      if (!mounted) return false;
      setState(() => _saving = false);
      context.showSuccessSnackBar('Sync settings saved');
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      context.showErrorSnackBar('Failed to save sync settings: $e');
      return false;
    }
  }

  Future<void> _testConnection() async {
    if (!await _save()) return;
    setState(() => _testing = true);
    try {
      await _service.testConnection();
      if (!mounted) return;
      context.showSuccessSnackBar('Connection successful');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar(
          'Connection failed: ${e is SyncTargetException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _pushNow() async {
    if (!await _save()) return;
    setState(() => _pushing = true);
    try {
      final result = await _service.pushNow();
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _lastPushAt = result.timestamp;
          _lastError = null;
        });
        context.showSuccessSnackBar(
            'Pushed backup to ${result.remotePath ?? 'remote'}');
      } else {
        setState(() => _lastError = result.errorMessage);
        context
            .showErrorSnackBar('Push failed: ${result.errorMessage ?? '?'}');
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _browseRemote() async {
    if (!await _save()) return;
    if (!mounted) return;
    final selection = await showDialog<(String, SyncBundleInfo)>(
      context: context,
      builder: (_) => _RemoteBrowserDialog(service: _service),
    );
    if (selection == null || !mounted) return;
    final (machine, bundle) = selection;

    // Same confirmation flow a local backup restore uses; copy makes the
    // bundle-based (replace, never merge) semantics explicit.
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Restore Remote Backup?',
      message: 'This restores "${bundle.file}" from machine "$machine". '
          'Sync is bundle-based: restoring replaces local configuration '
          'with the contents of this backup — nothing is merged. '
          'This action cannot be undone.',
      confirmLabel: 'Restore',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result = await _service.pullAndRestore(
        machine: machine,
        bundleFile: bundle.file,
      );
      if (!mounted) return;
      if (result.success) {
        context.showSuccessSnackBar(
            'Restored ${result.itemsRestored} items from $machine');
      } else {
        context.showErrorSnackBar(
            'Restore failed: ${result.errorMessage ?? 'unknown error'}');
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.cloud, size: 20, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Backup & Sync',
                        style: NightshadeTypography.h4
                            .copyWith(color: colors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Push configuration backups to a WebDAV server (Nextcloud, '
                    'ownCloud, generic WebDAV) and restore them on another '
                    'machine. Sync is bundle-based: restoring replaces local '
                    'configuration — nothing is merged.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    controller: _serverUrlController,
                    label: 'Server URL',
                    hint: 'https://cloud.example.com/remote.php/dav/files/user/',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _usernameController,
                          label: 'Username',
                          hint: 'WebDAV username',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          controller: _passwordController,
                          label: 'Password',
                          hint: _hasStoredPassword
                              ? '•••••••• (stored in OS keyring)'
                              : 'WebDAV password / app token',
                          obscure: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _machineNameController,
                    label: 'Machine name',
                    hint: 'Identifies this machine on the server',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Auto-push after the daily backup',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: NightshadeTypography.fontSize14,
                      ),
                    ),
                    subtitle: Text(
                      'Uploads a fresh bundle whenever the scheduled '
                      'auto-backup completes. The newest '
                      '$kSyncDefaultRetainCount bundles are kept per machine.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize12,
                      ),
                    ),
                    value: _autoPushEnabled,
                    onChanged: (v) => setState(() => _autoPushEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NightshadeButton(
                        label: _saving ? 'Saving...' : 'Save',
                        icon: LucideIcons.save,
                        variant: ButtonVariant.primary,
                        isLoading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                      NightshadeButton(
                        label: _testing ? 'Testing...' : 'Test Connection',
                        icon: LucideIcons.plugZap,
                        variant: ButtonVariant.outline,
                        isLoading: _testing,
                        onPressed: _testing || _pushing ? null : _testConnection,
                      ),
                      NightshadeButton(
                        label: _pushing ? 'Working...' : 'Push Now',
                        icon: LucideIcons.uploadCloud,
                        variant: ButtonVariant.outline,
                        isLoading: _pushing,
                        onPressed: _pushing ? null : _pushNow,
                      ),
                      NightshadeButton(
                        label: 'Browse Remote Backups',
                        icon: LucideIcons.folderSearch,
                        variant: ButtonVariant.outline,
                        onPressed: _pushing ? null : _browseRemote,
                      ),
                    ],
                  ),
                  if (_lastPushAt != null || _lastError != null) ...[
                    const SizedBox(height: 12),
                    if (_lastPushAt != null)
                      Text(
                        'Last push: '
                        '${DateFormat('MMM d, yyyy HH:mm').format(_lastPushAt!.toLocal())}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: NightshadeTypography.fontSize12,
                        ),
                      ),
                    if (_lastError != null)
                      Text(
                        'Last sync error: $_lastError',
                        style: TextStyle(
                          color: colors.error,
                          fontSize: NightshadeTypography.fontSize12,
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// Two-level browser: machines under `nightshade-sync/`, then that
/// machine's bundles (from its manifest). Returns the selected
/// `(machine, bundle)` pair; the caller runs the restore confirmation.
class _RemoteBrowserDialog extends StatefulWidget {
  const _RemoteBrowserDialog({required this.service});

  final SyncService service;

  @override
  State<_RemoteBrowserDialog> createState() => _RemoteBrowserDialogState();
}

class _RemoteBrowserDialogState extends State<_RemoteBrowserDialog> {
  bool _loading = true;
  String? _error;
  List<SyncRemoteMachine> _machines = const [];
  String? _selectedMachine;
  List<SyncBundleInfo> _bundles = const [];

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final machines = await widget.service.listRemoteMachines();
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SyncTargetException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadBundles(String machine) async {
    setState(() {
      _selectedMachine = machine;
      _loading = true;
      _error = null;
    });
    try {
      final bundles = await widget.service.listRemoteBundles(machine);
      if (!mounted) return;
      setState(() {
        _bundles = bundles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SyncTargetException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final machine = _selectedMachine;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          if (machine != null)
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft, size: 18),
              tooltip: 'Back to machines',
              onPressed: () => setState(() {
                _selectedMachine = null;
                _bundles = const [];
              }),
            ),
          Expanded(
            child: Text(
              machine == null ? 'Remote Backups' : 'Backups from "$machine"',
              style:
                  NightshadeTypography.h4.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 320,
        child: _buildBody(colors),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildBody(NightshadeColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.cloudOff, size: 40, color: colors.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
    final machine = _selectedMachine;
    if (machine == null) {
      if (_machines.isEmpty) {
        return Center(
          child: Text(
            'No machines have pushed backups yet.',
            style: TextStyle(color: colors.textSecondary),
          ),
        );
      }
      return ListView.builder(
        itemCount: _machines.length,
        itemBuilder: (context, index) {
          final m = _machines[index];
          return ListTile(
            leading: Icon(LucideIcons.monitor, color: colors.primary),
            title: Text(m.name,
                style: TextStyle(color: colors.textPrimary)),
            trailing: const Icon(LucideIcons.chevronRight, size: 16),
            onTap: () => _loadBundles(m.name),
          );
        },
      );
    }
    if (_bundles.isEmpty) {
      return Center(
        child: Text(
          'No bundles found for "$machine".',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      itemCount: _bundles.length,
      itemBuilder: (context, index) {
        final bundle = _bundles[index];
        final sizeKb = (bundle.sizeBytes / 1024).toStringAsFixed(1);
        return ListTile(
          leading: Icon(LucideIcons.archive, color: colors.primary),
          title: Text(
            bundle.file,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize14,
            ),
          ),
          subtitle: Text(
            '$sizeKb KB | '
            '${DateFormat('MMM d, yyyy HH:mm').format(bundle.createdAt.toLocal())}'
            '${bundle.sha256.isEmpty ? ' | no integrity hash' : ''}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
          trailing: TextButton(
            onPressed: () =>
                Navigator.of(context).pop((machine, bundle)),
            child: const Text('Restore'),
          ),
        );
      },
    );
  }
}
