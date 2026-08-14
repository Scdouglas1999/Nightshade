import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

import '../../localization/nightshade_localizations.dart';
import '../../utils/snackbar_helper.dart';

part 'pairing_screen_parts/_notifier.dart';
part 'pairing_screen_parts/_dialogs_and_banners.dart';

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
        // The framework's back arrow carries a tooltip and no accessible NAME
        // — read off the live tree, the only way off this page was an unnamed
        // button. AccessibleIconButton publishes one node that says what it is
        // and how to press it.
        leading: Navigator.of(context).canPop()
            ? AccessibleIconButton(
                icon: NightshadeIcons.arrowLeft,
                label: 'Back to Remote Access',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
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
              // Its own node. Bare Texts open no semantics boundary, so
              // Flutter merged this line, the expiry line and the Cancel
              // button's label into ONE node carrying the card's role: the
              // live tree read `button: Pair New Device / Enter this code on
              // your device: / Expires in 04:53 / Cancel Pairing` — a single
              // "button" whose name was four unrelated sentences.
              Semantics(
                container: true,
                child: Text(
                  l10n.text('pairingEnterCode'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              // Named for assistive tech, not just drawn. A [SelectableText]
              // publishes its text as a semantic value; the live tree exposed
              // "Enter this code on your device:" and "Expires in 04:55" with
              // the code itself missing between them, so the only credential
              // that has to be read aloud was the only thing that could not be.
              Semantics(
                container: true,
                excludeSemantics: true,
                label: 'Pairing code: ${state.pairingCode}',
                child: SelectableText(
                  state.pairingCode!,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        fontFamily: 'monospace',
                      ),
                ),
              ),
              const SizedBox(height: 8),
              // The copy control published NO accessible node at all — a bare
              // IconButton's tooltip is not a name — and pressing it changed
              // nothing the operator could see: two screenshots taken 3 s
              // apart across the click were identical. It is now a named
              // button that confirms in place.
              _CopyCodeButton(code: state.pairingCode!),
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
            Semantics(
              container: true,
              child: Text(
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
              children: [
                Expanded(
                  child: Text(
                    l10n.text('pairingDevicesTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                // Only offered when there is something to revoke: an
                // always-present "Revoke All" on an empty list is a control
                // that cannot do anything.
                if (state.pairedDevices.isNotEmpty) ...[
                  NightshadeButton(
                    label: l10n.text('pairingRevokeAllButton'),
                    icon: NightshadeIcons.shieldOff,
                    variant: ButtonVariant.destructive,
                    size: ButtonSize.small,
                    onPressed: state.isLoading
                        ? null
                        : () => _showRevokeAllDialog(
                              context,
                              ref,
                              state.pairedDevices,
                            ),
                  ),
                  const SizedBox(width: 8),
                ],
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
                      // `colorScheme.outline` is a BORDER colour. Used as
                      // body text on this empty state it measured 1.31:1
                      // against the card — rgb(43,49,59) on rgb(24,28,34) —
                      // so the one sentence telling a new user how to pair a
                      // device was effectively invisible. textSecondary is the
                      // design system's body-secondary token and clears AA.
                      Text(
                        l10n.text('pairingNoDevicesDesc'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: NightshadeColors.of(context).textSecondary,
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

  /// Revoke every paired device, after saying how many that is.
  ///
  /// The count is the whole point of the confirmation: the list is scrollable
  /// and inherited stores run to a dozen rows, so "revoke all" without a
  /// number is asking the operator to agree to something they cannot see.
  ///
  /// With exactly one device there is no "all" and no plural — the page said
  /// "Revoke access for all 1 paired devices?" — so the single-device wording
  /// is used, naming the device instead of counting it.
  void _showRevokeAllDialog(
    BuildContext context,
    WidgetRef ref,
    List<PairedDevice> devices,
  ) {
    final single = devices.length == 1 ? devices.single : null;
    _showConfirmDialog(
      context,
      titleKey: single != null ? 'pairingRevokeTitle' : 'pairingRevokeAllTitle',
      body: single != null
          ? context.l10n
              .text('pairingRevokeBody', params: {'name': single.deviceName})
          : context.l10n.text(
              'pairingRevokeAllBody',
              params: {'count': devices.length.toString()},
            ),
      confirmKey:
          single != null ? 'pairingRevokeAccess' : 'pairingRevokeAllConfirm',
      errorKey: 'pairingErrorRevokeAll',
      variant: ButtonVariant.destructive,
      action: () => ref.read(pairingProvider.notifier).revokeAll(),
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
    _showConfirmDialog(
      context,
      titleKey: titleKey,
      body: context.l10n.text(bodyKey, params: {'name': device.deviceName}),
      confirmKey: confirmKey,
      errorKey: errorKey,
      variant: variant,
      action: action,
    );
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String titleKey,
    required String body,
    required String confirmKey,
    required String errorKey,
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
              content: Text(body),
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

/// Copy-the-pairing-code control.
///
/// A named button (so assistive tech can find and press it) that acknowledges
/// itself where the operator is looking. The snack bar stays for the screen
/// reader announcement, but it is no longer the only feedback: the label swaps
/// to "Copied" for a few seconds, which is what a silent click needed.
class _CopyCodeButton extends StatefulWidget {
  const _CopyCodeButton({required this.code});

  final String code;

  @override
  State<_CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<_CopyCodeButton> {
  static const Duration _confirmFor = Duration(seconds: 3);
  Timer? _resetTimer;
  bool _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    // The confirmation is NOT gated on the platform round-trip. Awaiting
    // `Clipboard.setData` before touching the UI is why the click looked dead:
    // where the channel does not answer, the label never changed and no snack
    // bar was ever posted. Acknowledge the press, then correct the record if
    // the write actually fails.
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_confirmFor, () {
      if (mounted) setState(() => _copied = false);
    });
    context.showSuccessSnackBar(context.l10n.text('pairingCodeCopied'));

    unawaited(
      Clipboard.setData(ClipboardData(text: widget.code)).catchError((_) {
        if (!mounted) return;
        setState(() => _copied = false);
        context.showErrorSnackBar(
          'Could not copy the code — read it off the screen instead.',
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label =
        _copied ? l10n.text('pairingCodeCopied') : l10n.text('pairingCopyCode');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Filled, not ghost. A ghost button paints no fill until hover, so its
        // `textSecondary` label sat straight on the card's `primaryContainer`
        // and measured 1.15:1 — the one affordance for the credential read as
        // a disabled ghost (WF-SS-N1). A filled variant carries its own
        // background, so the label's contrast no longer depends on whatever
        // card it is dropped onto.
        NightshadeButton(
          label: label,
          icon: _copied ? NightshadeIcons.success : NightshadeIcons.copy,
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: _copy,
        ),
      ],
    );
  }
}
