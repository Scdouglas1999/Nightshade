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
  // WebDAV provider fields.
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // S3-compatible provider fields. The secret key controller is the only
  // one carrying a credential — its text is routed to the keyring via the
  // SyncService.saveConfig `password` param, never echoed into settings.
  final _s3EndpointController = TextEditingController();
  final _s3RegionController = TextEditingController();
  final _s3BucketController = TextEditingController();
  final _s3AccessKeyController = TextEditingController();
  final _s3SecretController = TextEditingController();

  // Shared.
  final _machineNameController = TextEditingController();

  SyncProvider _provider = SyncProvider.webdav;

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _pushing = false;
  bool _browsing = false;
  bool _autoPushEnabled = false;
  bool _s3PathStyle = false;
  // Tracked per provider so the "•••••••• (stored in OS keyring)" placeholder
  // is correct no matter which provider the dropdown shows.
  bool _hasStoredPassword = false;
  bool _hasStoredSecret = false;
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
    _s3EndpointController.dispose();
    _s3RegionController.dispose();
    _s3BucketController.dispose();
    _s3AccessKeyController.dispose();
    _s3SecretController.dispose();
    _machineNameController.dispose();
    super.dispose();
  }

  SyncService get _service => ref.read(syncServiceProvider);
  bool get _busy => _saving || _testing || _pushing || _browsing;

  Future<void> _load() async {
    try {
      final service = _service;
      final config = await service.loadConfig();
      // Read both providers' stored-secret flags so the keyring placeholder
      // renders correctly even after switching the dropdown.
      final hasPassword = await service.hasStoredSecret(SyncProvider.webdav);
      final hasSecret = await service.hasStoredSecret(SyncProvider.s3);
      final status = await service.status();
      if (!mounted) return;
      setState(() {
        _provider = config.provider;
        _serverUrlController.text = config.serverUrl;
        _usernameController.text = config.username;
        _s3EndpointController.text = config.s3Endpoint;
        _s3RegionController.text = config.s3Region;
        _s3BucketController.text = config.s3Bucket;
        _s3AccessKeyController.text = config.s3AccessKey;
        _s3PathStyle = config.s3PathStyle;
        _machineNameController.text = config.machineName;
        _autoPushEnabled = config.autoPushEnabled;
        _hasStoredPassword = hasPassword;
        _hasStoredSecret = hasSecret;
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

  /// Inline validation mirroring [SyncConfig.isConfigured] for the active
  /// provider, plus an http/https URL check. Returns the first problem as a
  /// user-facing message, or null when the active provider is well-formed.
  /// The S3 secret key is intentionally NOT required here — a blank secret
  /// means "keep the one already in the keyring".
  String? _validationError() {
    if (_machineNameController.text.trim().isEmpty) {
      return 'Machine name is required.';
    }
    switch (_provider) {
      case SyncProvider.webdav:
        final url = _serverUrlController.text.trim();
        if (url.isEmpty) return 'Server URL is required.';
        final uri = Uri.tryParse(url);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          return 'Server URL must start with http:// or https://.';
        }
      case SyncProvider.s3:
        final endpoint = _s3EndpointController.text.trim();
        if (endpoint.isEmpty) return 'S3 endpoint is required.';
        final uri = Uri.tryParse(endpoint);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          return 'S3 endpoint must be a valid http:// or https:// URL.';
        }
        if (_s3RegionController.text.trim().isEmpty) {
          return 'S3 region is required.';
        }
        if (_s3BucketController.text.trim().isEmpty) {
          return 'S3 bucket is required.';
        }
        if (_s3AccessKeyController.text.trim().isEmpty) {
          return 'S3 access key is required.';
        }
    }
    return null;
  }

  Future<bool> _save({
    bool manageBusy = true,
    bool showSuccess = true,
    SyncService? through,
  }) async {
    if (manageBusy && _busy) return false;
    final validationError = _validationError();
    if (validationError != null) {
      context.showErrorSnackBar(validationError);
      return false;
    }
    if (manageBusy) setState(() => _saving = true);
    final service = through ?? _service;
    try {
      // The active provider's secret controller is the only credential.
      // Leaving it blank keeps the stored secret (password: null); typing a
      // value routes it to the keyring via SyncService, never settings.
      final secret = _provider == SyncProvider.s3
          ? _s3SecretController.text
          : _passwordController.text;
      await service.saveConfig(
        SyncConfig(
          provider: _provider,
          serverUrl: _serverUrlController.text.trim(),
          username: _usernameController.text.trim(),
          s3Endpoint: _s3EndpointController.text.trim(),
          s3Region: _s3RegionController.text.trim(),
          s3Bucket: _s3BucketController.text.trim(),
          s3AccessKey: _s3AccessKeyController.text.trim(),
          s3PathStyle: _s3PathStyle,
          machineName: _machineNameController.text.trim(),
          autoPushEnabled: _autoPushEnabled,
        ),
        password: secret.isEmpty ? null : secret,
      );
      if (!mounted || !identical(service, _service)) return false;
      setState(() {
        if (secret.isNotEmpty) {
          if (_provider == SyncProvider.s3) {
            if (_s3SecretController.text == secret) {
              _s3SecretController.clear();
            }
            _hasStoredSecret = true;
          } else {
            if (_passwordController.text == secret) {
              _passwordController.clear();
            }
            _hasStoredPassword = true;
          }
        }
      });
      if (showSuccess) context.showSuccessSnackBar('Sync settings saved');
      return true;
    } catch (e) {
      if (!mounted || !identical(service, _service)) return false;
      context.showErrorSnackBar('Failed to save sync settings: $e');
      return false;
    } finally {
      if (manageBusy && mounted && identical(service, _service)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    final service = _service;
    setState(() => _testing = true);
    try {
      if (!await _save(
        manageBusy: false,
        showSuccess: false,
        through: service,
      )) {
        return;
      }
      await service.testConnection();
      if (!mounted || !identical(service, _service)) return;
      context.showSuccessSnackBar('Connection successful');
    } catch (e) {
      if (!mounted || !identical(service, _service)) return;
      context.showErrorSnackBar(
          'Connection failed: ${e is SyncTargetException ? e.message : e}');
    } finally {
      if (mounted && identical(service, _service)) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _pushNow() async {
    if (_busy) return;
    final service = _service;
    setState(() => _pushing = true);
    try {
      if (!await _save(
        manageBusy: false,
        showSuccess: false,
        through: service,
      )) {
        return;
      }
      final result = await service.pushNow();
      if (!mounted || !identical(service, _service)) return;
      if (result.success) {
        setState(() {
          _lastPushAt = result.timestamp;
          _lastError = null;
        });
        context.showSuccessSnackBar(
            'Pushed backup to ${result.remotePath ?? 'remote'}');
      } else {
        setState(() => _lastError = result.errorMessage);
        context.showErrorSnackBar('Push failed: ${result.errorMessage ?? '?'}');
      }
    } catch (e) {
      if (!mounted || !identical(service, _service)) return;
      setState(() => _lastError = '$e');
      context.showErrorSnackBar('Push failed: $e');
    } finally {
      if (mounted && identical(service, _service)) {
        setState(() => _pushing = false);
      }
    }
  }

  Future<void> _browseRemote() async {
    if (_busy) return;
    final service = _service;
    setState(() => _browsing = true);
    try {
      if (!await _save(
        manageBusy: false,
        showSuccess: false,
        through: service,
      )) {
        return;
      }
      if (!mounted || !identical(service, _service)) return;
      final selection = await showDialog<(String, SyncBundleInfo)>(
        context: context,
        builder: (_) => _RemoteBrowserDialog(service: service),
      );
      if (selection == null || !mounted || !identical(service, _service)) {
        return;
      }
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
      if (!confirmed || !mounted || !identical(service, _service)) return;

      final result = await service.pullAndRestore(
        machine: machine,
        bundleFile: bundle.file,
        replaceExisting: true,
      );
      if (!mounted || !identical(service, _service)) return;
      if (result.success) {
        context.showSuccessSnackBar(
            'Restored ${result.itemsRestored} items from $machine');
      } else {
        context.showErrorSnackBar(
            'Restore failed: ${result.errorMessage ?? 'unknown error'}');
      }
    } catch (e) {
      if (!mounted || !identical(service, _service)) return;
      context.showErrorSnackBar('Restore failed: $e');
    } finally {
      if (mounted && identical(service, _service)) {
        setState(() => _browsing = false);
      }
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
                    'ownCloud, generic WebDAV) or an S3-compatible object '
                    'store (AWS S3, MinIO, Backblaze B2) and restore them on '
                    'another machine. Sync is bundle-based: restoring replaces '
                    'local configuration — nothing is merged.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SyncProvider>(
                    initialValue: _provider,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: SyncProvider.webdav,
                        child: Text('WebDAV (Nextcloud, ownCloud)'),
                      ),
                      DropdownMenuItem(
                        value: SyncProvider.s3,
                        child: Text('S3-compatible (AWS, MinIO, Backblaze B2)'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _provider = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  if (_provider == SyncProvider.webdav)
                    ..._webdavFields()
                  else
                    ..._s3Fields(),
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
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _autoPushEnabled = v),
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
                        onPressed: _busy ? null : _save,
                      ),
                      NightshadeButton(
                        label: _testing ? 'Testing...' : 'Test Connection',
                        icon: LucideIcons.plugZap,
                        variant: ButtonVariant.outline,
                        isLoading: _testing,
                        onPressed: _busy ? null : _testConnection,
                      ),
                      NightshadeButton(
                        label: _pushing ? 'Working...' : 'Push Now',
                        icon: LucideIcons.uploadCloud,
                        variant: ButtonVariant.outline,
                        isLoading: _pushing,
                        onPressed: _busy ? null : _pushNow,
                      ),
                      NightshadeButton(
                        label:
                            _browsing ? 'Browsing...' : 'Browse Remote Backups',
                        icon: LucideIcons.folderSearch,
                        variant: ButtonVariant.outline,
                        isLoading: _browsing,
                        onPressed: _busy ? null : _browseRemote,
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

  /// WebDAV-specific fields: server URL + username/password. Machine name is
  /// rendered once by the shared block below the provider switch.
  List<Widget> _webdavFields() {
    return [
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
    ];
  }

  /// S3-compatible fields: endpoint, region + bucket, access key + secret
  /// key, and the path-style toggle MinIO requires. The secret key is
  /// obscured and only ever flows to the keyring via [_save].
  List<Widget> _s3Fields() {
    final colors = NightshadeColors.of(context);
    return [
      _field(
        controller: _s3EndpointController,
        label: 'Endpoint',
        hint: 'https://s3.us-east-1.amazonaws.com',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _field(
              controller: _s3RegionController,
              label: 'Region',
              hint: 'us-east-1',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              controller: _s3BucketController,
              label: 'Bucket',
              hint: 'my-nightshade-backups',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _field(
              controller: _s3AccessKeyController,
              label: 'Access key',
              hint: 'AKIA… / MinIO access key',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              controller: _s3SecretController,
              label: 'Secret key',
              hint: _hasStoredSecret
                  ? '•••••••• (stored in OS keyring)'
                  : 'S3 secret key',
              obscure: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          'Path-style addressing (required for MinIO)',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: NightshadeTypography.fontSize14,
          ),
        ),
        subtitle: Text(
          'Use <endpoint>/<bucket>/<key> instead of virtual-host style. '
          'Leave off for AWS S3; turn on for MinIO.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: NightshadeTypography.fontSize12,
          ),
        ),
        value: _s3PathStyle,
        onChanged: _busy ? null : (v) => setState(() => _s3PathStyle = v),
      ),
    ];
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
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// Read-only configuration summary plus Push Now for a remote controller.
///
/// Cloud credentials and restores stay on the imaging host. This card uses the
/// host's dedicated sync endpoints and never constructs a phone-local
/// [SyncService], which would otherwise report an empty database and upload the
/// wrong machine's configuration.
class RemoteCloudSyncCard extends ConsumerStatefulWidget {
  const RemoteCloudSyncCard({super.key});

  @override
  ConsumerState<RemoteCloudSyncCard> createState() =>
      _RemoteCloudSyncCardState();
}

class _RemoteCloudSyncCardState extends ConsumerState<RemoteCloudSyncCard> {
  SyncStatus? _status;
  bool _loading = true;
  bool _pushing = false;
  String? _error;
  int _loadGeneration = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous == null || identical(previous, next)) return;
        _load(authorityChanged: true);
      },
    );
    _load();
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  Future<void> _load({bool authorityChanged = false}) async {
    final generation = ++_loadGeneration;
    final backend = ref.read(backendProvider);
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        if (authorityChanged) {
          _status = null;
          _pushing = false;
        }
      });
    }
    try {
      if (backend is! NetworkBackend) {
        throw StateError('The imaging host is not connected.');
      }
      final status = await backend.getCloudSyncStatus();
      if (!mounted ||
          generation != _loadGeneration ||
          !identical(ref.read(backendProvider), backend)) {
        return;
      }
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != _loadGeneration ||
          !identical(ref.read(backendProvider), backend)) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load cloud sync status from the imaging host.';
      });
    }
  }

  Future<void> _pushNow() async {
    if (_pushing) return;
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      setState(() => _error = 'The imaging host is not connected.');
      return;
    }
    setState(() {
      _pushing = true;
      _error = null;
    });
    try {
      final result = await backend.pushCloudSyncNow();
      if (!mounted || !identical(ref.read(backendProvider), backend)) return;
      if (!result.success) {
        setState(() {
          _error = result.errorMessage ??
              'The imaging host reported that its cloud backup failed.';
        });
        return;
      }
      context.showSuccessSnackBar(
        'Host backup pushed to ${result.remotePath ?? 'cloud storage'}',
      );
      await _load();
    } catch (_) {
      if (!mounted || !identical(ref.read(backendProvider), backend)) return;
      setState(() {
        _error = 'The imaging host could not push its cloud backup. Check the '
            'host sync configuration and try again.';
      });
    } finally {
      if (mounted && identical(ref.read(backendProvider), backend)) {
        setState(() => _pushing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final status = _status;
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.cloud, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Backup & Sync (imaging host)',
                  style: NightshadeTypography.h4.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Pushes the imaging host’s configuration bundle. Provider and '
              'credentials are edited on the desktop host so secrets never '
              'cross to this controller.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && status == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!, style: TextStyle(color: colors.error)),
                  const SizedBox(height: 12),
                  NightshadeButton(
                    label: 'Retry',
                    icon: LucideIcons.refreshCw,
                    variant: ButtonVariant.outline,
                    onPressed: _load,
                  ),
                ],
              )
            else if (status != null) ...[
              _RemoteSyncStatusRow(
                label: 'Status',
                value: status.configured ? 'Configured' : 'Not configured',
                valueColor: status.configured ? colors.success : colors.warning,
              ),
              const SizedBox(height: 10),
              _RemoteSyncStatusRow(
                label: 'Machine',
                value: status.machineName.isEmpty ? '—' : status.machineName,
              ),
              if (status.serverUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                _RemoteSyncStatusRow(
                  label: 'Destination',
                  value: status.serverUrl,
                ),
              ],
              const SizedBox(height: 10),
              _RemoteSyncStatusRow(
                label: 'Automatic push',
                value: status.autoPushEnabled ? 'Enabled' : 'Disabled',
              ),
              const SizedBox(height: 10),
              _RemoteSyncStatusRow(
                label: 'Last push',
                value: status.lastPushAt == null
                    ? 'Never'
                    : DateFormat('MMM d, yyyy HH:mm')
                        .format(status.lastPushAt!.toLocal()),
              ),
              if (status.lastError != null || _error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Last host error: ${status.lastError}',
                  style: TextStyle(
                    color: colors.error,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
              ],
              if (!status.configured) ...[
                const SizedBox(height: 12),
                Text(
                  'Open Settings → Backup & Sync on the desktop imaging host '
                  'to choose a provider and enter its credentials.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  NightshadeButton(
                    label: _pushing || status.pushInProgress
                        ? 'Pushing…'
                        : 'Push Host Backup Now',
                    icon: LucideIcons.uploadCloud,
                    variant: ButtonVariant.primary,
                    isLoading: _pushing || status.pushInProgress,
                    onPressed:
                        !status.configured || status.pushInProgress || _pushing
                            ? null
                            : _pushNow,
                  ),
                  NightshadeButton(
                    label: 'Refresh',
                    icon: LucideIcons.refreshCw,
                    variant: ButtonVariant.outline,
                    onPressed: _pushing ? null : _load,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemoteSyncStatusRow extends StatelessWidget {
  const _RemoteSyncStatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? colors.textPrimary,
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
            title: Text(m.name, style: TextStyle(color: colors.textPrimary)),
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
            onPressed: () => Navigator.of(context).pop((machine, bundle)),
            child: const Text('Restore'),
          ),
        );
      },
    );
  }
}
