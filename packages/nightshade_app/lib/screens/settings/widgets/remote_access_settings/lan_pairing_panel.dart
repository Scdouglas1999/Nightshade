part of '../remote_access_settings.dart';

class _RemotePairingQrPanel extends StatelessWidget {
  final WebServerState webState;
  final String? pairingCode;
  final String appVersion;
  final VoidCallback? onStartPairing;

  const _RemotePairingQrPanel({
    required this.webState,
    required this.pairingCode,
    required this.appVersion,
    this.onStartPairing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    // Never embed localhost in QR — tablets cannot reach the PC loopback.
    final host = webState.localIp.isNotEmpty &&
            webState.localIp != 'localhost' &&
            webState.localIp != '127.0.0.1'
        ? webState.localIp
        : '';
    final qrPayload = host.isEmpty
        ? null
        : EnhancedNightshadeDiscovery.generateQrData(
            host: host,
            webPort: webState.actualPort,
            version: appVersion,
            fingerprint: webState.serverFingerprint,
            serverName: 'Nightshade',
            mode: 'desktop',
            authRequired: webState.requiresAuthentication,
            authenticationMode:
                webState.requiresAuthentication ? 'token' : 'none',
            pairingSupported: true,
            pairingCode: pairingCode,
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.text('remoteAccessQrTitle'),
            style: NightshadeTypography.labelStrong.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.text('remoteAccessQrBody'),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            '${l10n.text('remoteAccessFingerprint')}: '
            '${shortServerFingerprint(webState.serverFingerprint)}',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontFamily: 'monospace',
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (pairingCode == null && onStartPairing != null) ...[
            NightshadeButton(
              label: l10n.text('pairingStartButton'),
              icon: LucideIcons.link,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onStartPairing,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.text('remoteAccessQrStartHint'),
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
            ),
          ] else if (pairingCode != null && qrPayload != null) ...[
            Center(
              child: QrImageView(
                data: qrPayload,
                size: 200,
                backgroundColor: const Color(0xFFFFFFFF),
                semanticsLabel:
                    'Nightshade pairing QR for $host:${webState.actualPort}',
              ),
            ),
          ] else if (pairingCode != null && qrPayload == null) ...[
            Text(
              l10n.text('remoteAccessQrNoLanIp'),
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.warning),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                pairingCode!,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Look up a localization [key], falling back to [fallback] when the key is
/// not present in the active locale's table.
///
/// [NightshadeLocalizations.text] returns the *key itself* for an unknown key
/// (see its `?? key` tail). The Tailscale strings introduced here are new and
/// may not yet exist in every `nightshade_localizations.dart` table; routing
/// them through this helper keeps the i18n contract live — a translator who
/// adds the key later wins automatically — while guaranteeing we never render a
/// raw `remoteAccessTailscale…` identifier to the operator. [params] tokens are
/// substituted into whichever string is used.
String _l10nOr(
  NightshadeLocalizations l10n,
  String key,
  String fallback, {
  Map<String, String> params = const {},
}) {
  final resolved = l10n.text(key, params: params);
  if (resolved != key) {
    return resolved;
  }
  var value = fallback;
  params.forEach((paramKey, paramValue) {
    value = value.replaceAll('{$paramKey}', paramValue);
  });
  return value;
}
