import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

  /// The device that just consumed the outstanding pairing code, if any.
  ///
  /// This is the operator's only way to know that the phone in their hand is
  /// the thing that connected. Without it the desktop kept counting down a
  /// code the server had already destroyed, and the device list stayed a
  /// refresh behind.
  final PairedDevice? lastPairedDevice;

  PairingState({
    this.pairingCode,
    this.expiresAt,
    this.pairedDevices = const [],
    this.isLoading = false,
    this.error,
    this.lastPairedDevice,
  });

  PairingState copyWith({
    Object? pairingCode = _pairingUnset,
    Object? expiresAt = _pairingUnset,
    List<PairedDevice>? pairedDevices,
    bool? isLoading,
    Object? error = _pairingUnset,
    Object? lastPairedDevice = _pairingUnset,
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
      lastPairedDevice: identical(lastPairedDevice, _pairingUnset)
          ? this.lastPairedDevice
          : lastPairedDevice as PairedDevice?,
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
  final TokenManager _tokenManager;
  final PairingDatabase _database;
  final bool _ownsDatabase;
  late Future<void> _operationTail;
  int _queuedOperations = 0;

  /// deviceId -> pairedAt for every device known when the outstanding code was
  /// issued. A completed pairing is recognised by joining on deviceId (a
  /// re-pair deletes and re-adds the same id, so the timestamp is part of the
  /// identity) — never by comparing list lengths, which proves nothing about
  /// which row is new.
  Map<String, DateTime> _devicesWhenCodeIssued = const {};
  bool _completionCheckInFlight = false;

  PairingNotifier()
      : this._(
          PairingDatabase(),
          ownsDatabase: true,
        );

  /// Test/integration constructor for callers that already own a database.
  PairingNotifier.withDatabase(PairingDatabase database)
      : this._(database, ownsDatabase: false);

  PairingNotifier._(
    this._database, {
    required bool ownsDatabase,
  })  : _tokenManager = TokenManager(_database),
        _ownsDatabase = ownsDatabase,
        super(PairingState(isLoading: true)) {
    final initialization = _initialize();
    _operationTail = initialization.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
  }

  Future<void> _initialize() async {
    try {
      final devices = await _tokenManager.getActivePairedDevices();
      if (!mounted) return;
      state = state.copyWith(
        pairedDevices: devices,
        isLoading: _queuedOperations > 0,
        error: null,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: _queuedOperations > 0,
        error: 'pairingErrorLoad',
      );
    }
  }

  Future<bool> _enqueue(Future<bool> Function() operation) {
    if (_queuedOperations > 0) return Future<bool>.value(false);
    _queuedOperations += 1;
    if (mounted) state = state.copyWith(isLoading: true, error: null);
    final result = _operationTail.then((_) => operation());
    final tracked = result.whenComplete(() {
      _queuedOperations -= 1;
      if (mounted && _queuedOperations == 0) {
        state = state.copyWith(isLoading: false);
      }
    });
    _operationTail = tracked.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return tracked;
  }

  /// Start a new pairing session
  Future<bool> startPairing() {
    return _enqueue(() async {
      if (!mounted) return false;
      try {
        final code = await _tokenManager.startPairing();
        if (!mounted) return false;
        final expiresAt = DateTime.now().add(const Duration(minutes: 5));

        // Snapshot BEFORE the code can be used, so the device that consumes it
        // can be identified rather than guessed at.
        final known = await _tokenManager.getActivePairedDevices();
        if (!mounted) return false;
        _devicesWhenCodeIssued = {
          for (final device in known) device.deviceId: device.pairedAt,
        };

        state = state.copyWith(
          pairingCode: code,
          expiresAt: expiresAt,
          pairedDevices: known,
          lastPairedDevice: null,
          error: null,
        );

        _startCountdownTimers();
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorStart',
          );
        }
        return false;
      }
    });
  }

  void _startCountdownTimers() {
    // Set expiration timer
    _expirationTimer?.cancel();
    _expirationTimer = Timer(const Duration(minutes: 5), () {
      if (!mounted) return;
      state = state.copyWith(pairingCode: null, expiresAt: null);
    });

    // Start countdown timer for UI updates
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }
      state = state.copyWith(); // Trigger rebuild for countdown
      if (state.timeRemaining?.inSeconds == 0) {
        _countdownTimer?.cancel();
      }
      // The HTTP pairing endpoint runs against the same database file from a
      // separate PairingDatabase instance, so there is no Drift stream to
      // listen to and nothing pushes completion at this notifier. Ask, on the
      // same cadence the countdown already ticks at.
      unawaited(_checkPairingCompleted());
    });
  }

  /// Detect that the outstanding code has been consumed and say so.
  ///
  /// `completePairing` marks the session used and then deletes used sessions,
  /// so a missing (or used) row means the credential on screen is dead. Showing
  /// a live countdown for it is a false statement, and it invites the operator
  /// to read the dead code to a second device.
  Future<void> _checkPairingCompleted() async {
    if (!mounted || _completionCheckInFlight || _queuedOperations > 0) return;
    final code = state.pairingCode;
    if (code == null) return;
    _completionCheckInFlight = true;
    try {
      final session = await _database.getPairingSession(code);
      if (!mounted || state.pairingCode != code) return;
      if (session != null && !session.isUsed) return; // still outstanding

      final devices = await _tokenManager.getActivePairedDevices();
      if (!mounted || state.pairingCode != code) return;

      PairedDevice? paired;
      for (final device in devices) {
        final previous = _devicesWhenCodeIssued[device.deviceId];
        if (previous == null || previous != device.pairedAt) {
          paired = device;
          break;
        }
      }

      _expirationTimer?.cancel();
      _countdownTimer?.cancel();
      state = state.copyWith(
        pairingCode: null,
        expiresAt: null,
        pairedDevices: devices,
        lastPairedDevice: paired,
        error: null,
      );
    } catch (_) {
      // A transient read failure must never destroy a still-live code; the
      // next tick tries again.
    } finally {
      _completionCheckInFlight = false;
    }
  }

  /// Dismiss the "device paired" confirmation.
  void clearLastPairedDevice() {
    if (!mounted) return;
    state = state.copyWith(lastPairedDevice: null);
  }

  /// Cancel the current pairing session.
  ///
  /// The code remains visible if durable invalidation fails, so the operator
  /// is never told a still-live credential was cancelled.
  Future<bool> cancelPairing() {
    return _enqueue(() async {
      if (!mounted) return false;
      final code = state.pairingCode;
      if (code == null) {
        return true;
      }

      try {
        await _tokenManager.cancelPairing(code);
        if (!mounted) return false;
        _expirationTimer?.cancel();
        _countdownTimer?.cancel();
        state = state.copyWith(
          pairingCode: null,
          expiresAt: null,
          error: null,
        );
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorCancel',
          );
        }
        return false;
      }
    });
  }

  /// Load paired devices from database.
  Future<bool> loadPairedDevices() {
    return _enqueue(() async {
      if (!mounted) return false;
      try {
        final devices = await _tokenManager.getActivePairedDevices();
        if (!mounted) return false;
        state = state.copyWith(
          pairedDevices: devices,
          error: null,
        );
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorLoad',
          );
        }
        return false;
      }
    });
  }

  /// Revoke a paired device.
  Future<bool> revokeDevice(String deviceId) {
    return _enqueue(() async {
      if (!mounted) return false;
      try {
        await _tokenManager.revokeDevice(deviceId);
        final devices = await _tokenManager.getActivePairedDevices();
        if (!mounted) return false;
        state = state.copyWith(
          pairedDevices: devices,
          error: null,
        );
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorRevoke',
          );
        }
        return false;
      }
    });
  }

  /// Give a paired device a name the operator will recognise.
  ///
  /// Every phone pairs under a fixed per-platform name ("Android companion"),
  /// so the list is a stack of identical rows and revoking the handset you sold
  /// is guesswork. The name is the only field the host owns outright, so this
  /// is where that is settled; nothing about the device's token or grant
  /// changes.
  Future<bool> renameDevice(String deviceId, String deviceName) {
    final name = deviceName.trim();
    if (name.isEmpty) return Future<bool>.value(false);
    return _enqueue(() async {
      if (!mounted) return false;
      try {
        if (!await _tokenManager.renameDevice(deviceId, name)) {
          // The row is gone (deleted from another surface); say so rather than
          // reporting a rename that changed nothing.
          if (mounted) {
            final devices = await _tokenManager.getActivePairedDevices();
            if (mounted) state = state.copyWith(pairedDevices: devices);
          }
          return false;
        }
        final devices = await _tokenManager.getActivePairedDevices();
        if (!mounted) return false;
        state = state.copyWith(
          pairedDevices: devices,
          error: null,
        );
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorRename',
          );
        }
        return false;
      }
    });
  }

  /// Delete a paired device.
  Future<bool> deleteDevice(String deviceId) {
    return _enqueue(() async {
      if (!mounted) return false;
      try {
        await _tokenManager.deleteDevice(deviceId);
        final devices = await _tokenManager.getActivePairedDevices();
        if (!mounted) return false;
        state = state.copyWith(
          pairedDevices: devices,
          error: null,
        );
        return true;
      } catch (_) {
        if (mounted) {
          state = state.copyWith(
            error: 'pairingErrorDelete',
          );
        }
        return false;
      }
    });
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _countdownTimer?.cancel();
    if (_ownsDatabase) {
      final pending = _operationTail;
      unawaited(pending.whenComplete(_database.close));
    }
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
      body: SafeArea(
        child: SingleChildScrollView(
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
            if (state.lastPairedDevice != null) ...[
              _PairedConfirmation(
                device: state.lastPairedDevice!,
                onDismiss: () =>
                    ref.read(pairingProvider.notifier).clearLastPairedDevice(),
              ),
              const SizedBox(height: 16),
            ],
            if (state.pairingCode == null) ...[
              Text(
                l10n.text('pairingStartDesc'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              NightshadeButton(
                label: l10n.text('pairingStartButton'),
                icon: NightshadeIcons.link,
                variant: ButtonVariant.primary,
                isLoading: state.isLoading,
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                    icon: const Icon(NightshadeIcons.copy),
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
              NightshadeIcons.timer,
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
          isLoading: state.isLoading,
          onPressed: state.isLoading
              ? null
              : () => ref.read(pairingProvider.notifier).cancelPairing(),
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
                  onPressed: state.isLoading
                      ? null
                      : () => ref
                          .read(pairingProvider.notifier)
                          .loadPairedDevices(),
                  icon: const Icon(NightshadeIcons.refresh),
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
                        NightshadeIcons.device,
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
                  return _buildDeviceListItem(
                    context,
                    ref,
                    device,
                    enabled: !state.isLoading,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListItem(
    BuildContext context,
    WidgetRef ref,
    PairedDevice device, {
    required bool enabled,
  }) {
    final colors = NightshadeColors.of(context);
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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                        borderRadius:
                            BorderRadius.circular(NightshadeTokens.radiusFull),
                      ),
                      child: Text(
                        statusText,
                        style: NightshadeTypography.labelStrongSm
                            .copyWith(color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _deviceTypeLabel(device.deviceType),
                      style: NightshadeTypography.labelSm
                          .copyWith(color: colors.textMuted),
                    ),
                    // What this token is allowed to DO. The host has always
                    // stored it (paired_devices.auth_grant_spec) and the list
                    // never showed it, so a row holding 'admin' looked exactly
                    // like a view-only one — and revoking is the moment you
                    // most need to know which is which.
                    _AccessBadge(grantSpec: device.authGrantSpec),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.text(
                    'pairingPairedAt',
                    params: {'time': _formatDate(context, device.pairedAt)},
                  ),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
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
                      // Deliberately about the RECORD, not about the device:
                      // the host only stamps this on a fresh token
                      // verification, so a device that connects every night can
                      // legitimately have no entry here.
                      : 'No connection recorded yet',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: enabled,
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameDialog(context, ref, device);
              } else if (value == 'revoke') {
                _showRevokeDialog(context, ref, device);
              } else if (value == 'delete') {
                _showDeleteDialog(context, ref, device);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    const Icon(LucideIcons.pencil),
                    const SizedBox(width: 8),
                    Text(context.l10n.text('pairingRenameDevice')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'revoke',
                child: Row(
                  children: [
                    const Icon(LucideIcons.ban),
                    const SizedBox(width: 8),
                    Text(context.l10n.text('pairingRevokeAccess')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(NightshadeIcons.delete),
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

  // The primary pairing path (mobile_pairing_service.pairWithCode) sends
  // `defaultTargetPlatform.name`, so real rows carry 'android' / 'iOS' /
  // 'windows' / 'macOS' / 'linux' — none of which used to be handled. Every
  // Android phone therefore appeared as a desktop monitor labelled "Browser or
  // device". Only the lanClaim fallback sends 'mobile'.
  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
      case 'android':
      case 'ios':
        return NightshadeIcons.phone;
      case 'tablet':
        return LucideIcons.tablet;
      case 'desktop':
      case 'windows':
      case 'macos':
      case 'linux':
        return NightshadeIcons.device;
      case 'browser':
      case 'web':
        return LucideIcons.globe;
      default:
        return NightshadeIcons.device;
    }
  }

  String _deviceTypeLabel(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
        return 'Phone';
      case 'android':
        return 'Android phone or tablet';
      case 'ios':
        return 'iPhone or iPad';
      case 'tablet':
        return 'Tablet';
      case 'desktop':
        return 'Computer';
      case 'windows':
        return 'Windows computer';
      case 'macos':
        return 'Mac';
      case 'linux':
        return 'Linux computer';
      case 'browser':
      case 'web':
        return 'Browser';
      default:
        // Say we do not recognise it rather than asserting a category.
        return deviceType.trim().isEmpty
            ? 'Unknown device type'
            : 'Unrecognised device type ($deviceType)';
    }
  }

  String _deviceStatus(PairedDevice device) {
    if (!device.isActive) {
      return 'Revoked';
    }
    if (device.lastConnectedAt == null) {
      // A stale pairing row is not an invitation. "Ready to connect" was a
      // promise the app cannot make — it has never recorded this device
      // connecting, and it has no idea whether the device still exists.
      return 'Not seen yet';
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
      // Muted, not the accent colour: nothing about this row is a positive
      // signal, and a blue badge read as "this device is good to go".
      return colors.textMuted;
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

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _RenameDeviceDialog(
        device: device,
        onSubmit: (name) => ref
            .read(pairingProvider.notifier)
            .renameDevice(device.deviceId, name),
      ),
    );
  }

  void _showRevokeDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    _showDeviceActionDialog(
      context,
      titleKey: 'pairingRevokeTitle',
      bodyKey: 'pairingRevokeBody',
      confirmKey: 'pairingRevokeAccess',
      errorKey: 'pairingErrorRevoke',
      device: device,
      variant: ButtonVariant.primary,
      action: () =>
          ref.read(pairingProvider.notifier).revokeDevice(device.deviceId),
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, PairedDevice device) {
    _showDeviceActionDialog(
      context,
      titleKey: 'pairingDeleteTitle',
      bodyKey: 'pairingDeleteBody',
      confirmKey: 'pairingDeleteDevice',
      errorKey: 'pairingErrorDelete',
      device: device,
      variant: ButtonVariant.destructive,
      action: () =>
          ref.read(pairingProvider.notifier).deleteDevice(device.deviceId),
    );
  }

  void _showDeviceActionDialog(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required String confirmKey,
    required String errorKey,
    required PairedDevice device,
    required ButtonVariant variant,
    required Future<bool> Function() action,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var busy = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: Text(context.l10n.text(titleKey)),
              content: Text(
                context.l10n.text(
                  bodyKey,
                  params: {'name': device.deviceName},
                ),
              ),
              actions: [
                NightshadeButton(
                  label: context.l10n.text('cancel'),
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                ),
                NightshadeButton(
                  label: context.l10n.text(confirmKey),
                  variant: variant,
                  size: ButtonSize.small,
                  isLoading: busy,
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() => busy = true);
                          final succeeded = await action();
                          if (!dialogContext.mounted) return;
                          if (succeeded) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }
                          setDialogState(() => busy = false);
                          dialogContext.showErrorSnackBar(
                            dialogContext.l10n.text(errorKey),
                          );
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Renames one paired device.
///
/// Deliberately a plain one-field dialog: the field opens focused and holding
/// the current name, Return commits it, and an empty name is refused rather
/// than written (a blank row would be even less identifiable than the
/// duplicate it was meant to fix).
class _RenameDeviceDialog extends StatefulWidget {
  final PairedDevice device;
  final Future<bool> Function(String name) onSubmit;

  const _RenameDeviceDialog({required this.device, required this.onSubmit});

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.device.deviceName);
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final succeeded = await widget.onSubmit(name);
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
    context.showErrorSnackBar(context.l10n.text('pairingErrorRename'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l10n.text('pairingRenameTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.text('pairingRenameBody')),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              // Rebuild so Save disables the moment the field is emptied.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.text('pairingRenameLabel'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            label: l10n.text('cancel'),
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          NightshadeButton(
            label: l10n.text('save'),
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            isLoading: _busy,
            onPressed:
                _busy || _controller.text.trim().isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// What a paired device's token is allowed to do, as a badge.
///
/// `auth_grant_spec` is either one of the three coarse grants or the host
/// API's fine-grained `resource:level,...` form; the raw spec is always on the
/// tooltip so a custom grant is still inspectable.
class _AccessBadge extends StatelessWidget {
  final String grantSpec;

  const _AccessBadge({required this.grantSpec});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final spec = grantSpec.trim().toLowerCase();
    final (String label, Color color) = switch (spec) {
      // Admin can re-pair, revoke other devices and change server settings.
      // Coloured as a warning because it is the grant you look for when you
      // are deciding what to revoke.
      'admin' => ('Full access', colors.warning),
      'control' => ('Can control the rig', colors.info),
      'view' => ('View only', colors.textMuted),
      _ => ('Custom access', colors.textMuted),
    };

    return Tooltip(
      message: 'Granted access: $grantSpec',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: NightshadeTypography.labelQuiet.copyWith(color: color),
        ),
      ),
    );
  }
}

/// `<device> paired` confirmation shown the moment the outstanding code is
/// consumed. Names the device because that is what tells the operator the phone
/// in their hand — and not something else on the network — is what connected.
class _PairedConfirmation extends StatelessWidget {
  final PairedDevice device;
  final VoidCallback onDismiss;

  const _PairedConfirmation({
    required this.device,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.check, color: colors.success, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${device.deviceName} paired',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
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

class _PairingErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _PairingErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(NightshadeIcons.error, color: colors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.text(message),
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
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
