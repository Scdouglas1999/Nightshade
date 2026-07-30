part of '../remote_access_settings.dart';

class _PairingCallout extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onPressed;

  const _PairingCallout({
    required this.title,
    required this.description,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: NightshadeTypography.labelStrong
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            label: context.l10n.text('remoteAccessManagePairing'),
            icon: LucideIcons.link,
            variant: ButtonVariant.primary,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// Turn a raw server startup failure into something an operator can act on.
///
/// The panel used to surface the bare `SocketException`, clipped after two
/// lines, which hid the one detail that matters (which port is taken). The raw
/// text is still available via the row's copy button — this only replaces what
/// is *displayed*.
@visibleForTesting
String explainRemoteAccessError(String rawError, int configuredPort) {
  final lower = rawError.toLowerCase();
  if (lower.contains('address already in use') ||
      lower.contains('errno = 98') ||
      lower.contains('errno = 10048')) {
    return 'Port $configuredPort is already in use by another program. '
        'Choose a different port, or stop the program holding it.';
  }
  if (lower.contains('permission denied') || lower.contains('errno = 13')) {
    return 'The system refused to open port $configuredPort. Ports below 1024 '
        'usually need elevated privileges — pick a higher port.';
  }
  if (lower.contains('cannot assign requested address') ||
      lower.contains('errno = 99')) {
    return 'The chosen network address is not available on this machine. '
        'Switch the access scope, or reconnect the network interface.';
  }
  return rawError;
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isLast;

  /// Raw text to put on the clipboard. When non-null a copy button is shown —
  /// used for diagnostics the operator needs to paste elsewhere.
  final String? copyValue;

  /// How many lines the value may occupy before it is ellipsised.
  final int valueMaxLines;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isLast = false,
    this.copyValue,
    this.valueMaxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final copyable = copyValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: SelectableText(
              value,
              maxLines: valueMaxLines,
              textAlign: TextAlign.right,
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          if (copyable != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 14),
              color: colors.textSecondary,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: 'Copy the full error',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: copyable));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
