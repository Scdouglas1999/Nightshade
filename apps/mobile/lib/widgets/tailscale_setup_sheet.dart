// Mobile Companion — Internet Reachability via Tailscale (P3).
//
// Guided "connect over Tailscale" bottom sheet. This is the primary
// onboarding path for an off-site operator: the phone is NOT on the
// observatory LAN, so UDP broadcast and mDNS discovery find nothing
// (Tailscale has no broadcast domain). Instead the operator reaches the
// rig over the tailnet by its MagicDNS name (`my-rig.tailnet.ts.net`) or
// its `100.x.y.z` tailnet IP.
//
// What this sheet does:
//   1. Explains, in three short steps, how to bring the phone onto the
//      same tailnet (install Tailscale, sign in, read the rig's MagicDNS
//      name from the desktop's Remote Access settings).
//   2. Collects the tailnet host (MagicDNS name or 100.x address), port,
//      transport scheme (http/https), and an optional access token.
//   3. Validates the host fail-closed via [SavedServer.isTailscaleEndpoint]
//      so a public address can never be entered here, then returns a
//      [TailscaleSetupResult] for the caller to actually connect + persist.
//
// It deliberately does NOT perform the connect itself: main.dart owns the
// canonical `_connectToServer` path (fetchServerInfo → pairing →
// testServerConnection → BackendNotifier.connect → saveLastServer), and
// duplicating that here would fork the pairing/compatibility logic. The
// sheet is a focused data-collection step that hands a validated target
// back to that one path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/localization/nightshade_localizations.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../services/saved_servers_service.dart';

/// The validated target the operator entered in [TailscaleSetupSheet].
///
/// Immutable; the caller turns this into a `DiscoveredServer` and runs it
/// through the standard connect path.
@immutable
class TailscaleSetupResult {
  /// Tailnet host: a MagicDNS `*.ts.net` name or a `100.x.y.z` /
  /// `fd7a:115c::…` literal. Guaranteed to pass
  /// [SavedServer.isTailscaleEndpoint].
  final String host;

  /// Headless API port. Defaults to 8080 in the form.
  final int port;

  /// Transport scheme — `'http'` or `'https'`. A TLS-fronted tailnet host
  /// answers only on `https`.
  final String scheme;

  /// Optional bearer token pasted by the operator. `null`/empty means the
  /// caller should fall back to the interactive pairing-code flow.
  final String? authToken;

  const TailscaleSetupResult({
    required this.host,
    required this.port,
    required this.scheme,
    this.authToken,
  });
}

/// Bottom sheet that guides an off-site operator through a Tailscale
/// connect. Returns a [TailscaleSetupResult] when the operator taps
/// "Connect", or `null` when they dismiss it.
class TailscaleSetupSheet extends StatefulWidget {
  /// Pre-fills the host field — e.g. a saved rig's recorded tailnet host,
  /// or a host the caller already knows.
  final String? initialHost;

  /// Pre-fills the port field. Defaults to 8080 when null.
  final int? initialPort;

  /// Pre-selects the scheme toggle. Defaults to `'http'` when null.
  final String? initialScheme;

  const TailscaleSetupSheet({
    super.key,
    this.initialHost,
    this.initialPort,
    this.initialScheme,
  });

  /// Convenience launcher mirroring the rest of the mobile sheet helpers.
  /// Presents the sheet modally (scrollable, dim barrier) and resolves to
  /// the operator's [TailscaleSetupResult] or `null`.
  static Future<TailscaleSetupResult?> show(
    BuildContext context, {
    String? initialHost,
    int? initialPort,
    String? initialScheme,
  }) {
    final colors = NightshadeColors.of(context);
    return showModalBottomSheet<TailscaleSetupResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: colors.background.withValues(alpha: 0.72),
      builder: (sheetContext) => TailscaleSetupSheet(
        initialHost: initialHost,
        initialPort: initialPort,
        initialScheme: initialScheme,
      ),
    );
  }

  @override
  State<TailscaleSetupSheet> createState() => _TailscaleSetupSheetState();
}

class _TailscaleSetupSheetState extends State<TailscaleSetupSheet> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  String _scheme = 'http';
  bool _tokenVisible = false;
  String? _hostError;
  String? _portError;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.initialHost ?? '');
    _portController =
        TextEditingController(text: (widget.initialPort ?? 8080).toString());
    _tokenController = TextEditingController();
    final initialScheme = widget.initialScheme?.toLowerCase();
    _scheme = initialScheme == 'https' ? 'https' : 'http';
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// Validate the form fail-closed and pop a [TailscaleSetupResult] on
  /// success. Errors are surfaced inline (host/port) rather than silently
  /// coerced.
  void _submit() {
    final l10n = context.l10n;
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    var hostError =
        host.isEmpty ? l10n.text('tailscaleHostEmptyError') : null;
    if (hostError == null && !SavedServer.isTailscaleEndpoint(host)) {
      hostError = l10n.text('tailscaleHostInvalidError');
    }
    int? port = int.tryParse(portText);
    final portError = (port == null || port <= 0 || port > 65535)
        ? l10n.text('tailscalePortRangeError')
        : null;
    if (hostError != null || portError != null) {
      setState(() {
        _hostError = hostError;
        _portError = portError;
      });
      return;
    }
    final token = _tokenController.text.trim();
    Navigator.of(context).pop(
      TailscaleSetupResult(
        host: host,
        port: port!,
        scheme: _scheme,
        authToken: token.isEmpty ? null : token,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      // Lift the sheet above the keyboard so the token field stays visible.
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NightshadeTokens.radiusLg),
          ),
          border: Border(top: BorderSide(color: colors.border)),
          boxShadow: NightshadeTokens.shadowLg,
        ),
        padding: NightshadeTokens.dialogPadding,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(colors),
              const SizedBox(height: NightshadeTokens.space2xl),
              _buildSteps(colors),
              const SizedBox(height: NightshadeTokens.space2xl),
              _buildForm(colors),
              const SizedBox(height: NightshadeTokens.space2xl),
              _buildActions(colors),
              const SizedBox(height: NightshadeTokens.spaceSm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    final l10n = context.l10n;
    return Row(
      children: [
        Container(
          padding: NightshadeTokens.paddingSm,
          decoration: NightshadeDecorations.iconChip(colors.accent),
          child: Icon(
            LucideIcons.radioTower,
            size: NightshadeTokens.iconMd,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.text('tailscaleConnect'),
                style: NightshadeTypography.h4
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.text('tailscaleConnectSubtitle'),
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(LucideIcons.x, size: NightshadeTokens.iconSm),
          color: colors.textSecondary,
          tooltip: l10n.text('tailscaleClose'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSteps(NightshadeColors colors) {
    final l10n = context.l10n;
    return SectionWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SetupStep(
            index: 1,
            icon: LucideIcons.smartphone,
            title: l10n.text('tailscaleStep1Title'),
            body: l10n.text('tailscaleStep1Body'),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _SetupStep(
            index: 2,
            icon: LucideIcons.monitorSmartphone,
            title: l10n.text('tailscaleStep2Title'),
            body: l10n.text('tailscaleStep2Body'),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _SetupStep(
            index: 3,
            icon: LucideIcons.link,
            title: l10n.text('tailscaleStep3Title'),
            body: l10n.text('tailscaleStep3Body'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(NightshadeColors colors) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.text('tailscaleAddressLabel'),
          style: NightshadeTypography.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        NightshadeTextField(
          controller: _hostController,
          hint: l10n.text('tailscaleAddressHint'),
          prefixIcon: LucideIcons.globe2,
          errorText: _hostError,
          keyboardType: TextInputType.url,
          onChanged: (_) {
            if (_hostError != null) setState(() => _hostError = null);
          },
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('tailscalePortLabel'),
                    style: NightshadeTypography.label
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  NightshadeTextField(
                    controller: _portController,
                    hint: '8080',
                    prefixIcon: LucideIcons.hash,
                    errorText: _portError,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) {
                      if (_portError != null) setState(() => _portError = null);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('tailscaleTransportLabel'),
                    style: NightshadeTypography.label
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  _SchemeToggle(
                    scheme: _scheme,
                    onChanged: (value) => setState(() => _scheme = value),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Text(
          l10n.text('tailscaleTokenLabel'),
          style: NightshadeTypography.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        NightshadeTextField(
          controller: _tokenController,
          hint: l10n.text('tailscaleTokenHint'),
          prefixIcon: LucideIcons.key,
          obscureText: !_tokenVisible,
          suffixWidget: IconButton(
            icon: Icon(
              _tokenVisible ? LucideIcons.eyeOff : LucideIcons.eye,
              size: NightshadeTokens.iconSm,
              color: colors.textSecondary,
            ),
            tooltip: _tokenVisible
                ? l10n.text('tailscaleHideToken')
                : l10n.text('tailscaleShowToken'),
            onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: l10n.text('savedServersCancel'),
            variant: ButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: NightshadeButton(
            label: l10n.text('tailscaleConnectAction'),
            icon: LucideIcons.radioTower,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}

/// A http/https segmented toggle styled to the design system.
class _SchemeToggle extends StatelessWidget {
  final String scheme;
  final ValueChanged<String> onChanged;

  const _SchemeToggle({required this.scheme, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      height: NightshadeTokens.inputHeight,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _segment(context, colors, 'http', 'HTTP'),
          _segment(context, colors, 'https', 'HTTPS'),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    NightshadeColors colors,
    String value,
    String label,
  ) {
    final selected = scheme == value;
    return Expanded(
      child: GestureDetector(
        onTap: selected ? null : () => onChanged(value),
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: NightshadeTokens.borderRadiusSm,
          ),
          child: Text(
            label,
            style: NightshadeTypography.labelSm.copyWith(
              color: selected ? colors.onPrimary : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// One numbered step in the "how to" block.
class _SetupStep extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String body;

  const _SetupStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: NightshadeDecorations.tintedBadge(colors.accent),
          child: Text(
            '$index',
            style: NightshadeTypography.labelSm.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: NightshadeTokens.iconSm, color: colors.textSecondary),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      title,
                      style: NightshadeTypography.bodyMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
