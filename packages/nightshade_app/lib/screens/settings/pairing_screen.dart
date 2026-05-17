import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

import '../../localization/nightshade_localizations.dart';
import '../../utils/snackbar_helper.dart';

/// Provider for pairing state management
final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
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
    Object? pairingCode = _pairingUnset,
    Object? expiresAt = _pairingUnset,
    List<PairedDevice>? pairedDevices,
    bool? isLoading,
    Object? error = _pairingUnset,
  }) {
    return PairingState(
      pairingCode: identical(pairingCode, _pairingUnset)
          ? this.pairingCode
          : pairingCode as String?,
      expiresAt: identical(expiresAt, _pairingUnset)
          ? this.expiresAt
          : expiresAt as DateTime?,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _pairingUnset) ? this.error : error as String?,
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
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'pairingErrorStart',
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
      state = state.copyWith(pairedDevices: devices, error: null);
    } catch (_) {
      state = state.copyWith(error: 'pairingErrorLoad');
    }
  }

  /// Revoke a paired device
  Future<void> revokeDevice(String deviceId) async {
    state = state.copyWith(isLoading: true);

    try {
      await _tokenManager.revokeDevice(deviceId);
      await loadPairedDevices();
      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'pairingErrorRevoke',
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
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'pairingErrorDelete',
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('pairingTitle')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.error != null) ...[
              _PairingErrorBanner(
                message: state.error!,
                onDismiss: () =>
                    ref.read(pairingProvider.notifier).clearError(),
              ),
              const SizedBox(height: 16),
            ],
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
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.text('pairingNewDeviceTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (state.pairingCode == null) ...[
              Text(
                l10n.text('pairingStartDesc'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              NightshadeButton(
                label: l10n.text('pairingStartButton'),
                icon: Icons.link,
                variant: ButtonVariant.primary,
                onPressed: state.isLoading
                    ? null
                    : () => ref.read(pairingProvider.notifier).startPairing(),
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
    final l10n = context.l10n;
    final timeRemaining = state.timeRemaining;
    final minutes = timeRemaining?.inMinutes ?? 0;
    final seconds = (timeRemaining?.inSeconds ?? 0) % 60;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                l10n.text('pairingEnterCode'),
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
                        l10n.text('pairingCodeCopied'),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    tooltip: l10n.text('pairingCopyCode'),
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
              l10n.text(
                'pairingExpiresIn',
                params: {
                  'minutes': minutes.toString().padLeft(2, '0'),
                  'seconds': seconds.toString().padLeft(2, '0'),
                },
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        NightshadeButton(
          label: l10n.text('pairingCancel'),
          variant: ButtonVariant.outline,
          onPressed: () => ref.read(pairingProvider.notifier).cancelPairing(),
        ),
      ],
    );
  }

  Widget _buildPairedDevicesSection(
      BuildContext context, WidgetRef ref, PairingState state) {
    final l10n = context.l10n;
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
                  l10n.text('pairingDevicesTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(pairingProvider.notifier).loadPairedDevices(),
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.text('pairingRefresh'),
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
                        l10n.text('pairingNoDevices'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.text('pairingNoDevicesDesc'),
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final statusText = _deviceStatus(device);
    final statusColor = _deviceStatusColor(colors, device);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getDeviceIcon(device.deviceType),
              size: 22,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.deviceName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _deviceTypeLabel(device.deviceType),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.text(
                    'pairingPairedAt',
                    params: {'time': _formatDate(context, device.pairedAt)},
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                Text(
                  device.lastConnectedAt != null
                      ? context.l10n.text(
                          'pairingLastConnected',
                          params: {
                            'time':
                                _formatDate(context, device.lastConnectedAt!),
                          },
                        )
                      : 'Has not connected yet',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'revoke') {
                _showRevokeDialog(context, ref, device);
              } else if (value == 'delete') {
                _showDeleteDialog(context, ref, device);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'revoke',
                child: Row(
                  children: [
                    const Icon(Icons.block),
                    const SizedBox(width: 8),
                    Text(context.l10n.text('pairingRevokeAccess')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete),
                    const SizedBox(width: 8),
                    Text(context.l10n.text('pairingDeleteDevice')),
                  ],
                ),
              ),
            ],
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

  String _deviceTypeLabel(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
        return 'Phone';
      case 'tablet':
        return 'Tablet';
      case 'desktop':
        return 'Computer';
      default:
        return 'Browser or device';
    }
  }

  String _deviceStatus(PairedDevice device) {
    if (!device.isActive) {
      return 'Revoked';
    }
    if (device.lastConnectedAt == null) {
      return 'Ready to connect';
    }
    final difference = DateTime.now().difference(device.lastConnectedAt!);
    if (difference.inHours < 24) {
      return 'Seen recently';
    }
    return 'Trusted';
  }

  Color _deviceStatusColor(NightshadeColors colors, PairedDevice device) {
    if (!device.isActive) {
      return colors.error;
    }
    if (device.lastConnectedAt == null) {
      return colors.primary;
    }
    final difference = DateTime.now().difference(device.lastConnectedAt!);
    if (difference.inHours < 24) {
      return colors.success;
    }
    return colors.textSecondary;
  }

  String _formatDate(BuildContext context, DateTime date) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return l10n.text('pairingJustNow');
        }
        return l10n.text(
          'pairingMinutesAgo',
          params: {'count': difference.inMinutes.toString()},
        );
      }
      return l10n.text(
        'pairingHoursAgo',
        params: {'count': difference.inHours.toString()},
      );
    } else if (difference.inDays < 7) {
      return l10n.text(
        'pairingDaysAgo',
        params: {'count': difference.inDays.toString()},
      );
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  void _showRevokeDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('pairingRevokeTitle')),
        content: Text(
          context.l10n.text(
            'pairingRevokeBody',
            params: {'name': device.deviceName},
          ),
        ),
        actions: [
          NightshadeButton(
            label: context.l10n.text('cancel'),
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(context).pop(),
          ),
          NightshadeButton(
            label: context.l10n.text('pairingRevokeAccess'),
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () {
              ref.read(pairingProvider.notifier).revokeDevice(device.deviceId);
              Navigator.of(context).pop();
            },
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
        title: Text(context.l10n.text('pairingDeleteTitle')),
        content: Text(
          context.l10n.text(
            'pairingDeleteBody',
            params: {'name': device.deviceName},
          ),
        ),
        actions: [
          NightshadeButton(
            label: context.l10n.text('cancel'),
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(context).pop(),
          ),
          NightshadeButton(
            label: context.l10n.text('pairingDeleteDevice'),
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () {
              ref.read(pairingProvider.notifier).deleteDevice(device.deviceId);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _PairingErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _PairingErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.text(message),
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onDismiss,
            child: Text(context.l10n.text('pairingDismissError')),
          ),
        ],
      ),
    );
  }
}

const Object _pairingUnset = Object();
