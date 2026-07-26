import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../constellation_format.dart';
import '../constellation_ui_providers.dart';

/// Shared sign-out action for every hub surface. It serializes taps, exposes
/// progress, and keeps the connected UI intact when credential storage fails.
class ConstellationSignOutButton extends ConsumerStatefulWidget {
  final VoidCallback onSignedOut;
  final ButtonVariant variant;
  final ButtonSize size;

  const ConstellationSignOutButton({
    super.key,
    required this.onSignedOut,
    this.variant = ButtonVariant.ghost,
    this.size = ButtonSize.small,
  });

  @override
  ConsumerState<ConstellationSignOutButton> createState() =>
      _ConstellationSignOutButtonState();
}

class _ConstellationSignOutButtonState
    extends ConsumerState<ConstellationSignOutButton> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await clearConstellationCredentials(ref.read(settingsDaoProvider));
      if (!mounted) return;
      widget.onSignedOut();
    } catch (error) {
      if (!mounted) return;
      context.showErrorSnackBar('Could not sign out: $error');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NightshadeButton(
      label: 'Sign out',
      variant: widget.variant,
      size: widget.size,
      icon: LucideIcons.logOut,
      isLoading: _signingOut,
      onPressed: _signOut,
    );
  }
}

/// The connected-hub banner: the verified hub identity (name + short
/// fingerprint), its tiling parameters, the signed-in display name, and a
/// sign-out affordance. Self-hosted, LAN-only — no cloud account, made explicit.
class HubStatusCard extends StatelessWidget {
  final HubInfo info;
  final String displayName;
  final VoidCallback onSignOut;

  const HubStatusCard({
    super.key,
    required this.info,
    required this.displayName,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(colors.success),
                child: Icon(
                  LucideIcons.radioTower,
                  size: NightshadeTokens.iconSm,
                  color: colors.success,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected',
                      style: NightshadeTypography.labelSm.copyWith(
                        color: colors.success,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHubLabel(info.name, info.fingerprint),
                      style: NightshadeTypography.labelStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ConstellationSignOutButton(
                onSignedOut: onSignOut,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              if (displayName.isNotEmpty)
                _MetaChip(
                  icon: LucideIcons.userCircle2,
                  label: displayName,
                  colors: colors,
                ),
              _MetaChip(
                icon: LucideIcons.layoutGrid,
                label: 'order ${info.healpixOrder} · ${info.tilePixels}px',
                colors: colors,
              ),
              _MetaChip(
                icon: info.selfHosted ? LucideIcons.home : LucideIcons.cloud,
                label: info.selfHosted ? 'Self-hosted' : 'Shared hub',
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: NightshadeTokens.iconXs, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            label,
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
