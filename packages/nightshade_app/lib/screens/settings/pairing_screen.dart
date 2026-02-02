import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

import '../../utils/snackbar_helper.dart';

/// Provider for pairing state management
final pairingProvider = StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier();
});

/// Pairing state
class PairingState {
  final String? pairingCode;
  final DateTime? expiresAt;
  final List<PairedDevice> pairedDevices;
  final bool isLoading;
  final String? error;

  PairingState({
    this.pairingCode,
    this.expiresAt,
    this.pairedDevices = const [],
    this.isLoading = false,
    this.error,
  });

  PairingState copyWith({
    String? pairingCode,
    DateTime? expiresAt,
    List<PairedDevice>? pairedDevices,
    bool? isLoading,
    String? error,
  }) {
    return PairingState(
      pairingCode: pairingCode ?? this.pairingCode,
      expiresAt: expiresAt ?? this.expiresAt,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  Duration? get timeRemaining {
    if (expiresAt == null) return null;
    final remaining = expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Pairing state notifier
class PairingNotifier extends StateNotifier<PairingState> {
  Timer? _expirationTimer;
  Timer? _countdownTimer;
  late TokenManager _tokenManager;
  late PairingDatabase _database;

  PairingNotifier() : super(PairingState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    _database = PairingDatabase();
    _tokenManager = TokenManager(_database);
    await loadPairedDevices();
  }

  /// Start a new pairing session
  Future<void> startPairing() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final code = await _tokenManager.startPairing();
      final expiresAt = DateTime.now().add(const Duration(minutes: 5));

      state = state.copyWith(
        pairingCode: code,
        expiresAt: expiresAt,
        isLoading: false,
      );

      // Set expiration timer
      _expirationTimer?.cancel();
      _expirationTimer = Timer(const Duration(minutes: 5), () {
        state = state.copyWith(pairingCode: null, expiresAt: null);
      });

      // Start countdown timer for UI updates
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        state = state.copyWith(); // Trigger rebuild for countdown
        if (state.timeRemaining?.inSeconds == 0) {
          _countdownTimer?.cancel();
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to start pairing: $e',
      );
    }
  }

  /// Cancel the current pairing session
  void cancelPairing() {
    _expirationTimer?.cancel();
    _countdownTimer?.cancel();
    state = state.copyWith(pairingCode: null, expiresAt: null);
  }

  /// Load paired devices from database
  Future<void> loadPairedDevices() async {
    try {
      final devices = await _tokenManager.getActivePairedDevices();
      state = state.copyWith(pairedDevices: devices);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load devices: $e');
    }
  }

  /// Revoke a paired device
  Future<void> revokeDevice(String deviceId) async {
    state = state.copyWith(isLoading: true);

    try {
      await _tokenManager.revokeDevice(deviceId);
      await loadPairedDevices();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to revoke device: $e',
      );
    }
  }

  /// Delete a paired device
  Future<void> deleteDevice(String deviceId) async {
    state = state.copyWith(isLoading: true);

    try {
      await _tokenManager.deleteDevice(deviceId);
      await loadPairedDevices();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to delete device: $e',
      );
    }
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// Pairing screen for managing remote connections
class PairingScreen extends ConsumerWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pairingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Connection Pairing'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPairingSection(context, ref, state),
            const SizedBox(height: 32),
            _buildPairedDevicesSection(context, ref, state),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingSection(
      BuildContext context, WidgetRef ref, PairingState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pair New Device',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (state.pairingCode == null) ...[
              Text(
                'Start pairing mode to allow a new device to connect. '
                'The pairing code will be valid for 5 minutes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: state.isLoading
                    ? null
                    : () => ref.read(pairingProvider.notifier).startPairing(),
                icon: const Icon(Icons.link),
                label: const Text('Start Pairing Mode'),
              ),
            ] else ...[
              _buildPairingCodeDisplay(context, ref, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairingCodeDisplay(
      BuildContext context, WidgetRef ref, PairingState state) {
    final timeRemaining = state.timeRemaining;
    final minutes = timeRemaining?.inMinutes ?? 0;
    final seconds = (timeRemaining?.inSeconds ?? 0) % 60;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                'Enter this code on your device:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SelectableText(
                state.pairingCode!,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: state.pairingCode!));
                      context.showSuccessSnackBar(
                          'Pairing code copied to clipboard');
                    },
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy code',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => ref.read(pairingProvider.notifier).cancelPairing(),
          child: const Text('Cancel Pairing'),
        ),
      ],
    );
  }

  Widget _buildPairedDevicesSection(
      BuildContext context, WidgetRef ref, PairingState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paired Devices',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(pairingProvider.notifier).loadPairedDevices(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.pairedDevices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.devices_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No paired devices',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start pairing mode to connect a device',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.pairedDevices.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final device = state.pairedDevices[index];
                  return _buildDeviceListItem(context, ref, device);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListItem(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    return ListTile(
      leading: Icon(
        _getDeviceIcon(device.deviceType),
        size: 32,
      ),
      title: Text(device.deviceName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paired: ${_formatDate(device.pairedAt)}'),
          if (device.lastConnectedAt != null)
            Text('Last connected: ${_formatDate(device.lastConnectedAt!)}'),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'revoke') {
            _showRevokeDialog(context, ref, device);
          } else if (value == 'delete') {
            _showDeleteDialog(context, ref, device);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'revoke',
            child: Row(
              children: [
                Icon(Icons.block),
                SizedBox(width: 8),
                Text('Revoke Access'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete),
                SizedBox(width: 8),
                Text('Delete Device'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
        return Icons.smartphone;
      case 'tablet':
        return Icons.tablet;
      case 'desktop':
        return Icons.computer;
      default:
        return Icons.devices;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  void _showRevokeDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Device Access'),
        content: Text(
          'Are you sure you want to revoke access for "${device.deviceName}"? '
          'This device will no longer be able to connect until it is paired again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(pairingProvider.notifier).revokeDevice(device.deviceId);
              Navigator.of(context).pop();
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text(
          'Are you sure you want to permanently delete "${device.deviceName}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(pairingProvider.notifier).deleteDevice(device.deviceId);
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
