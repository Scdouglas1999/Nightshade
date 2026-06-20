import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'constellation_format.dart';
import 'constellation_sign_in_sheet.dart';
import 'constellation_ui_providers.dart';
import 'shared_target_detail_screen.dart';
import 'widgets/follow_the_night_card.dart';
import 'widgets/hub_status_card.dart';
import 'widgets/shared_target_card.dart';

/// Pillar C ("Constellation") — the community swarm surface.
///
/// A top-level shell destination where the observer signs in to a self-hosted
/// hub, browses the shared community targets the swarm is collecting (each with
/// its combined depth, contributor count, and your share), follows the night
/// ("M31 is dark for you now and the swarm needs more depth"), and opens a
/// target to contribute, pull the fused co-add, and blend it into Your Sky.
///
/// Reads exclusively through the core `constellationServiceProvider` family, so
/// it works unchanged on the desktop FFI backend and the mobile network backend.
class ConstellationScreen extends StatelessWidget {
  const ConstellationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: const SafeArea(bottom: false, child: ConstellationView()),
    );
  }
}

/// Scaffold-free body so the swarm view can also be embedded (e.g. a tab).
class ConstellationView extends ConsumerWidget {
  const ConstellationView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final configuredAsync = ref.watch(constellationConfiguredProvider);

    return Column(
      children: [
        ScreenHeader(
          title: 'Constellation',
          subtitle:
              'Join the swarm — pool your photons with other imagers into one '
              'deeper sky, and follow the night where it is darkest.',
          icon: LucideIcons.users,
          trailing: IconButton(
            icon: const Icon(
              NightshadeIcons.refresh,
              size: NightshadeTokens.iconMd,
            ),
            tooltip: 'Refresh swarm',
            color: colors.textSecondary,
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            onPressed: () => _refresh(ref),
          ),
        ),
        Expanded(
          child: configuredAsync.when(
            data: (configured) => configured
                ? _ConnectedBody(onRefresh: () => _refresh(ref))
                : _SignedOutBody(onSignedIn: () => _refresh(ref)),
            loading: () => _buildLoading(),
            error: (error, _) => _buildError(ref, error),
          ),
        ),
      ],
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(constellationConfiguredProvider);
    ref.invalidate(constellationHubInfoProvider);
    ref.invalidate(sharedTargetsProvider);
    ref.invalidate(followTheNightProvider(-1));
  }

  Widget _buildLoading() {
    return ShimmerLoading(
      child: ListView(
        padding: NightshadeTokens.screenPadding,
        children: const [
          SkeletonBox(
            width: double.infinity,
            height: 96,
            borderRadius: NightshadeTokens.radiusLg,
          ),
          SizedBox(height: NightshadeTokens.spaceLg),
          SkeletonBox(width: 160, height: 18),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonBox(
            width: double.infinity,
            height: 140,
            borderRadius: NightshadeTokens.radiusLg,
          ),
        ],
      ),
    );
  }

  Widget _buildError(WidgetRef ref, Object error) {
    return EmptyState(
      icon: LucideIcons.alertCircle,
      title: 'Could not reach the swarm',
      body: describeConstellationError(error),
      action: NightshadeButton(
        label: 'Retry',
        icon: NightshadeIcons.refresh,
        onPressed: () {
          ref.invalidate(constellationConfiguredProvider);
          ref.invalidate(constellationHubInfoProvider);
        },
      ),
    );
  }
}

/// Empty/signed-out state: explain the swarm, then a single sign-in CTA.
class _SignedOutBody extends ConsumerWidget {
  final VoidCallback onSignedIn;

  const _SignedOutBody({required this.onSignedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: NightshadeTokens.screenPadding,
      children: [
        const SizedBox(height: NightshadeTokens.spaceLg),
        EmptyState(
          icon: LucideIcons.users,
          title: 'Image together, go deeper',
          body: 'Connect to a self-hosted Constellation hub to pool your '
              'integration with other imagers. You always choose what leaves '
              'your device — by default, only the additive co-add sums your '
              'atlas already keeps, never your raw subframes.',
          action: NightshadeButton(
            label: 'Connect to a hub',
            icon: LucideIcons.radioTower,
            onPressed: () => _openSignIn(context, ref),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        NightshadeCard(
          variant: CardVariant.subtle,
          padding: NightshadeTokens.cardPadding,
          child: Row(
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: NightshadeTokens.iconMd,
                color: colors.info,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'LAN-only and self-hosted: there is no Nightshade cloud and '
                  'no central account. You federate directly with a hub you '
                  'or your group runs.',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openSignIn(BuildContext context, WidgetRef ref) async {
    final signedIn = await showConstellationSignInSheet(context);
    if (signedIn == true) onSignedIn();
  }
}

/// Connected state: hub banner, follow-the-night, shared-target browse list.
class _ConnectedBody extends ConsumerWidget {
  final VoidCallback onRefresh;

  const _ConnectedBody({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hubAsync = ref.watch(constellationHubInfoProvider);
    final displayName =
        ref.watch(constellationDisplayNameProvider).valueOrNull ?? '';
    final suggestionsAsync = ref.watch(followTheNightProvider(-1));
    final targetsAsync = ref.watch(sharedTargetsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        onRefresh();
        await ref.read(sharedTargetsProvider.future);
      },
      child: ListView(
        padding: NightshadeTokens.screenPadding,
        children: [
          hubAsync.when(
            data: (info) => info == null
                ? const SizedBox.shrink()
                : HubStatusCard(
                    info: info,
                    displayName: displayName,
                    onSignOut: () => _signOut(context, ref),
                  ),
            loading: () => const SkeletonBox(
              width: double.infinity,
              height: 96,
              borderRadius: NightshadeTokens.radiusLg,
            ),
            error: (error, _) => NightshadeAlert(
              severity: NightshadeAlertSeverity.warning,
              title: 'Hub unavailable',
              message: describeConstellationError(error),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _FollowTheNightSection(suggestionsAsync: suggestionsAsync),
          const SizedBox(height: NightshadeTokens.spaceLg),
          const SectionHeader(
            title: 'Shared targets',
            subtitle: 'Community fields the swarm is deepening together',
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _SharedTargetsSection(targetsAsync: targetsAsync),
          const SizedBox(height: NightshadeTokens.spaceLg),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsDaoProvider);
    await settings.setSetting(constellationHubUrlSettingKey, '');
    await settings.setSetting(constellationHubTokenSettingKey, '');
    ref.invalidate(constellationConfiguredProvider);
    ref.invalidate(constellationHubInfoProvider);
  }
}

class _FollowTheNightSection extends StatelessWidget {
  final AsyncValue<List<FollowTheNightSuggestion>> suggestionsAsync;

  const _FollowTheNightSection({required this.suggestionsAsync});

  @override
  Widget build(BuildContext context) {
    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Follow the night',
              subtitle: 'Where it is darkest for you and the swarm needs depth',
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: NightshadeTokens.spaceMd,
                ),
                child: _FollowTheNightCardWired(suggestion: s),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Wires a follow-the-night card's Claim button to the service, with local
/// in-flight state so the button shows a spinner and disables while claiming.
class _FollowTheNightCardWired extends ConsumerStatefulWidget {
  final FollowTheNightSuggestion suggestion;

  const _FollowTheNightCardWired({required this.suggestion});

  @override
  ConsumerState<_FollowTheNightCardWired> createState() =>
      _FollowTheNightCardWiredState();
}

class _FollowTheNightCardWiredState
    extends ConsumerState<_FollowTheNightCardWired> {
  bool _claiming = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    return FollowTheNightCard(
      suggestion: s,
      claiming: _claiming,
      onClaim: s.isReadyNow ? _claim : null,
    );
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final claim = await ref
          .read(constellationServiceProvider)
          .claimHandoff(widget.suggestion.targetId);
      if (!mounted) return;
      ref.invalidate(followTheNightProvider(-1));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            claim?.claimToken != null
                ? 'You hold the baton for ${widget.suggestion.targetName}. '
                    'Image it tonight.'
                : 'Claim requested for ${widget.suggestion.targetName}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeConstellationError(error))),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }
}

class _SharedTargetsSection extends StatelessWidget {
  final AsyncValue<List<SharedTarget>> targetsAsync;

  const _SharedTargetsSection({required this.targetsAsync});

  @override
  Widget build(BuildContext context) {
    return targetsAsync.when(
      data: (targets) {
        if (targets.isEmpty) {
          return const NightshadeCard(
            variant: CardVariant.subtle,
            padding: NightshadeTokens.cardPadding,
            child: _EmptySwarmHint(),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= NightshadeTokens.breakpointTablet
                    ? 2
                    : 1;
            return _SharedTargetGrid(targets: targets, columns: columns);
          },
        );
      },
      loading: () => const ShimmerLoading(
        child: Column(
          children: [
            SkeletonBox(
              width: double.infinity,
              height: 160,
              borderRadius: NightshadeTokens.radiusLg,
            ),
            SizedBox(height: NightshadeTokens.spaceMd),
            SkeletonBox(
              width: double.infinity,
              height: 160,
              borderRadius: NightshadeTokens.radiusLg,
            ),
          ],
        ),
      ),
      error: (error, _) => NightshadeAlert(
        severity: NightshadeAlertSeverity.warning,
        title: 'Could not list shared targets',
        message: describeConstellationError(error),
      ),
    );
  }
}

class _EmptySwarmHint extends StatelessWidget {
  const _EmptySwarmHint();

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      children: [
        Icon(LucideIcons.globe2,
            size: NightshadeTokens.iconMd, color: colors.info),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Text(
            'No shared targets on this hub yet. When you contribute one of your '
            'imaged targets, it becomes a field the whole swarm can deepen.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Responsive grid mirroring the Your Sky region grid: intrinsic-height cards in
/// 1/2/3 columns so the contribution bars never clip.
class _SharedTargetGrid extends StatelessWidget {
  final List<SharedTarget> targets;
  final int columns;

  const _SharedTargetGrid({required this.targets, required this.columns});

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        children: [
          for (final t in targets)
            Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
              child: SharedTargetCard(
                target: t,
                onTap: () => _open(context, t),
              ),
            ),
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < targets.length; i += columns) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final index = i + c;
        if (c > 0) {
          rowChildren.add(const SizedBox(width: NightshadeTokens.spaceMd));
        }
        rowChildren.add(
          Expanded(
            child: index < targets.length
                ? SharedTargetCard(
                    target: targets[index],
                    onTap: () => _open(context, targets[index]),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowChildren,
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  void _open(BuildContext context, SharedTarget target) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharedTargetDetailScreen(target: target),
      ),
    );
  }
}
