import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../your_sky/region_detail_screen.dart';
import '../your_sky/sky_atlas_format.dart';
import 'constellation_contribute_sheet.dart';
import 'constellation_format.dart';
import 'constellation_ui_providers.dart';
import 'widgets/contribution_bar.dart';

/// Detail for one shared community target: the fused swarm co-add summary, your
/// contribution, and the three swarm actions — JOIN (record the hub target),
/// CONTRIBUTE (push your additive sums after an explicit consent step), and PULL
/// the fused co-add to blend into Your Sky.
class SharedTargetDetailScreen extends ConsumerStatefulWidget {
  final SharedTarget target;

  const SharedTargetDetailScreen({super.key, required this.target});

  @override
  ConsumerState<SharedTargetDetailScreen> createState() =>
      _SharedTargetDetailScreenState();
}

class _SharedTargetDetailScreenState
    extends ConsumerState<SharedTargetDetailScreen> {
  bool _joined = false;
  bool _pulling = false;
  List<SwarmTile> _blended = const [];

  /// Own integration (seconds) at the moment of the last successful pull — the
  /// "before" half of the Pull & Blend payoff card.
  double _ownSecondsBeforeBlend = 0.0;

  SharedTarget get _target => widget.target;

  @override
  void initState() {
    super.initState();
    _joined = ref
        .read(constellationServiceProvider)
        .joinedTargets
        .any((t) => t.targetId == _target.targetId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final yourSeconds =
        ref.watch(yourContributionSecondsProvider(_target)).valueOrNull ?? 0.0;
    // Contribute / Pull / Retract all read the LOCAL atlas + LOCAL contribution
    // receipts and write the hub — empty on a slave, so they are host-only.
    // Browse/Join stay enabled everywhere.
    final hostActionsEnabled =
        ref.watch(isConstellationHostActionEnabledProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text(
          _target.name.isEmpty ? 'Target #${_target.targetId}' : _target.name,
          style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: NightshadeTokens.screenPadding,
          children: [
            _SwarmSummaryCard(target: _target, yourSeconds: yourSeconds),
            const SizedBox(height: NightshadeTokens.spaceLg),
            _JoinCard(
              joined: _joined,
              onToggle: _toggleJoin,
              targetName: _target.name,
            ),
            if (!hostActionsEnabled) ...[
              const SizedBox(height: NightshadeTokens.spaceMd),
              const _HostOnlyNotice(),
            ],
            const SizedBox(height: NightshadeTokens.spaceMd),
            _ContributeCard(
              enabled: _joined && hostActionsEnabled,
              yourSeconds: yourSeconds,
              onContribute: _contribute,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _BlendCard(
              enabled: _joined && hostActionsEnabled,
              pulling: _pulling,
              blended: _blended,
              onPull: _pullAndBlend,
            ),
            if (_blended.isNotEmpty) ...[
              const SizedBox(height: NightshadeTokens.spaceMd),
              _BlendPayoffCard(
                ownSecondsBefore: _ownSecondsBeforeBlend,
                swarmSeconds: _target.integrationSeconds,
                onOpenInYourSky: _openBlendedRegion,
              ),
            ],
            if (hostActionsEnabled) ...[
              const SizedBox(height: NightshadeTokens.spaceMd),
              _ContributionsCard(target: _target, onRetract: _retract),
            ],
            if (_blended.isNotEmpty) ...[
              const SizedBox(height: NightshadeTokens.spaceMd),
              const _SwarmTrustCard(),
            ],
            const SizedBox(height: NightshadeTokens.spaceLg),
          ],
        ),
      ),
    );
  }

  void _toggleJoin() {
    final service = ref.read(constellationServiceProvider);
    setState(() {
      if (_joined) {
        service.leaveSharedTarget(_target.targetId);
        _joined = false;
      } else {
        service.joinSharedTarget(_target);
        _joined = true;
      }
    });
  }

  Future<void> _contribute() async {
    final outcome = await showConstellationContributeSheet(
      context,
      target: _target,
    );
    if (outcome == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    ref.invalidate(sharedTargetsProvider);
    ref.invalidate(yourContributionSecondsProvider(_target));
    final msg = outcome.acceptedCount == 0
        ? 'No locally-imaged tiles overlap this target yet.'
        : 'Contributed ${outcome.acceptedCount} tile'
            '${outcome.acceptedCount == 1 ? '' : 's'} to the swarm'
            '${outcome.rejectedCount > 0 ? ' (${outcome.rejectedCount} rejected)' : ''}.';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pullAndBlend() async {
    setState(() => _pulling = true);
    final messenger = ScaffoldMessenger.of(context);
    // Snapshot the user's own depth on this field BEFORE the blend so the payoff
    // card can honestly show "yours -> yours + swarm".
    final ownBefore =
        ref.read(yourContributionSecondsProvider(_target)).valueOrNull ?? 0.0;
    try {
      // Pull the additive `.nst` accumulator (finalized: false) so the service
      // actually folds it into the local atlas — that merge is what makes the
      // swarm's depth show up in Your Sky. A finalized FITS pull is a
      // display-only blob the app never blends, which would make the "blended
      // into Your Sky" copy below false.
      final tiles = await ref
          .read(constellationServiceProvider)
          .pullTarget(_target.targetId, finalized: false);
      if (!mounted) return;
      setState(() {
        _blended = tiles;
        _ownSecondsBeforeBlend = ownBefore;
        _pulling = false;
      });
      // The pull already merged each delta into the local atlas tiles; refresh
      // the atlas read surface so Your Sky reflects the deeper blended stack.
      ref.invalidate(skyAtlasCoverageProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tiles.isEmpty
                ? 'Nothing to pull for this target yet.'
                : 'Pulled ${tiles.length} community tile'
                    '${tiles.length == 1 ? '' : 's'} — ready to blend into '
                    'Your Sky.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _pulling = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeConstellationError(error))),
      );
    }
  }

  /// Deep-link into the Your Sky region the blend deepened, so the payoff lands
  /// on-screen instead of telling the user to "go look elsewhere". Resolves the
  /// tightest region covering the target centre (the pull blended its tiles into
  /// the same atlas region) and pushes RegionDetail. Falls back to a snackbar
  /// when no region covers the field yet.
  Future<void> _openBlendedRegion() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final region = await ref
        .read(skyAtlasServiceProvider)
        .getRegionForPoint(_target.raDeg, _target.decDeg);
    if (!mounted) return;
    if (region == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Open Your Sky to scrub the blended depth — name this field as a '
            'region to track it night over night.',
          ),
        ),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => RegionDetailScreen(regionId: region.id),
      ),
    );
  }

  Future<void> _retract(ContributionRecord record) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final receipt = await ref
          .read(constellationServiceProvider)
          .retractTile(record.tileId);
      if (!mounted) return;
      // The high-water reset means the contribution bar + swarm depth shift; the
      // contributions list drops this tile.
      ref.invalidate(myContributionsProvider);
      ref.invalidate(sharedTargetsProvider);
      ref.invalidate(yourContributionSecondsProvider(_target));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Retracted your contribution to tile ${record.tileId}. The fused '
            'depth is now ${receipt.totalFramesAfter} frame'
            '${receipt.totalFramesAfter == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeConstellationError(error))),
      );
    }
  }
}

class _SwarmSummaryCard extends StatelessWidget {
  final SharedTarget target;
  final double yourSeconds;

  const _SwarmSummaryCard({required this.target, required this.yourSeconds});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatCenter(target.raDeg, target.decDeg),
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          ResponsiveStatStrip(
            stats: [
              ResponsiveStat(
                label: 'FUSED DEPTH',
                value: formatIntegration(target.integrationSeconds),
                icon: LucideIcons.layers,
                valueColor: colors.accent,
              ),
              ResponsiveStat(
                label: 'CONTRIBUTORS',
                value: '${target.contributors}',
                icon: LucideIcons.users,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          ContributionBar(
            yourSeconds: yourSeconds,
            swarmSeconds: target.integrationSeconds,
          ),
        ],
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  final bool joined;
  final VoidCallback onToggle;
  final String targetName;

  const _JoinCard({
    required this.joined,
    required this.onToggle,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      padding: NightshadeTokens.cardPadding,
      child: Row(
        children: [
          Icon(
            joined ? LucideIcons.checkCircle2 : LucideIcons.userPlus,
            size: NightshadeTokens.iconMd,
            color: joined ? colors.success : colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  joined ? 'Joined' : 'Join this target',
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  joined
                      ? 'Contribute and pull are unlocked.'
                      : 'Track this field so you can contribute and pull.',
                  style: NightshadeTypography.captionSm.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          NightshadeButton(
            label: joined ? 'Leave' : 'Join',
            variant: joined ? ButtonVariant.outline : ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

class _ContributeCard extends StatelessWidget {
  final bool enabled;
  final double yourSeconds;
  final VoidCallback onContribute;

  const _ContributeCard({
    required this.enabled,
    required this.yourSeconds,
    required this.onContribute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final hasLocal = yourSeconds > 0;
    return NightshadeCard(
      variant: enabled ? CardVariant.standard : CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.upload,
                size: NightshadeTokens.iconMd,
                color: enabled ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Contribute your light',
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: enabled ? colors.textPrimary : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            hasLocal
                ? 'Add your ${formatIntegration(yourSeconds)} of imaging on this '
                    'field to the swarm. You will confirm exactly what leaves '
                    'your device first.'
                : 'You have not imaged this field yet. Image and fold it into '
                    'Your Sky, then contribute.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerRight,
            child: NightshadeButton(
              label: 'Contribute',
              icon: LucideIcons.upload,
              size: ButtonSize.small,
              onPressed: enabled && hasLocal ? onContribute : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlendCard extends StatelessWidget {
  final bool enabled;
  final bool pulling;
  final List<SwarmTile> blended;
  final VoidCallback onPull;

  const _BlendCard({
    required this.enabled,
    required this.pulling,
    required this.blended,
    required this.onPull,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final blendedCount = blended.length;
    return NightshadeCard(
      variant: enabled ? CardVariant.standard : CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.download,
                size: NightshadeTokens.iconMd,
                color: enabled ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Pull the fused image',
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: enabled ? colors.textPrimary : colors.textMuted,
                  ),
                ),
              ),
              if (blendedCount > 0)
                StatusPill(
                  icon: LucideIcons.combine,
                  label: 'BLENDED',
                  value: '$blendedCount',
                  status: StatusPillStatus.success,
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            blendedCount > 0
                ? 'The swarm co-add is cached locally and blended into Your Sky '
                    'for this field — see the depth gained below.'
                : 'Download the swarm\'s combined co-add for this field and blend '
                    'it into Your Sky alongside your own integration.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerRight,
            child: NightshadeButton(
              label: blendedCount > 0 ? 'Refresh blend' : 'Pull & blend',
              icon: LucideIcons.combine,
              size: ButtonSize.small,
              isLoading: pulling,
              onPressed: enabled && !pulling ? onPull : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pull & Blend payoff: the before/after depth the swarm's photons added to this
/// field, plus a deep link into the Your Sky region so the deeper sky lands
/// on-screen instead of a dead-end "go look elsewhere". "Before" is the user's
/// own integration at pull time; "after" adds the fused community depth the
/// blend folded into the local atlas.
class _BlendPayoffCard extends StatelessWidget {
  final double ownSecondsBefore;
  final double swarmSeconds;
  final VoidCallback onOpenInYourSky;

  const _BlendPayoffCard({
    required this.ownSecondsBefore,
    required this.swarmSeconds,
    required this.onOpenInYourSky,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final after = ownSecondsBefore + swarmSeconds;
    return NightshadeCard(
      variant: CardVariant.standard,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.trendingUp,
                size: NightshadeTokens.iconMd,
                color: colors.success,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Depth gained',
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              Text(
                formatIntegration(ownSecondsBefore),
                style: NightshadeTypography.h5.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Icon(
                LucideIcons.arrowRight,
                size: NightshadeTokens.iconSm,
                color: colors.textMuted,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                formatIntegration(after),
                style: NightshadeTypography.h5.copyWith(
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'fused',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            'The swarm added ${formatIntegration(swarmSeconds)} of community '
            'integration to your ${formatIntegration(ownSecondsBefore)} on this '
            'field.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerRight,
            child: NightshadeButton(
              label: 'Open in Your Sky',
              icon: LucideIcons.sparkles,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onOpenInYourSky,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slave notice: the host-owned actions read the host's atlas + receipts, so we
/// disable them here and say where they run rather than no-op silently.
class _HostOnlyNotice extends StatelessWidget {
  const _HostOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return const NightshadeAlert(
      severity: NightshadeAlertSeverity.info,
      compact: true,
      message: 'Contributing, pulling, and retracting run on your imaging '
          'host. Browse and join from here; open Constellation on the host to '
          'share your light.',
    );
  }
}

/// "Your contributions" — the persisted retractable receipts for this hub.
///
/// Lists every tile this device has contributed (the Wave-0 receipts carrying a
/// remote contributionId) with a per-row Retract that subtracts it back off the
/// hub exactly. This is what makes the twice-printed "subtract your contribution
/// exactly" promise true. Receipts are per-tile and hub-wide (a target's cone
/// spans several tiles), so the list is scoped to the hub, not one target.
class _ContributionsCard extends ConsumerWidget {
  final SharedTarget target;
  final ValueChanged<ContributionRecord> onRetract;

  const _ContributionsCard({required this.target, required this.onRetract});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final contributionsAsync = ref.watch(myContributionsProvider);
    return contributionsAsync.when(
      data: (records) {
        if (records.isEmpty) return const SizedBox.shrink();
        return NightshadeCard(
          padding: NightshadeTokens.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    size: NightshadeTokens.iconMd,
                    color: colors.accent,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: Text(
                      'Your contributions',
                      style: NightshadeTypography.labelStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'You only shared additive co-add sums, so retracting a tile '
                'subtracts your contribution exactly — the shared depth returns '
                'to what it was before.',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              for (final r in records)
                _ContributionRow(record: r, onRetract: () => onRetract(r)),
            ],
          ),
        );
      },
      loading: () => const SkeletonBox(
        width: double.infinity,
        height: 96,
        borderRadius: NightshadeTokens.radiusLg,
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ContributionRow extends StatelessWidget {
  final ContributionRecord record;
  final VoidCallback onRetract;

  const _ContributionRow({required this.record, required this.onRetract});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tile ${record.tileId}',
                  style: NightshadeTypography.label.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.contributedFrames} frame'
                  '${record.contributedFrames == 1 ? '' : 's'} · '
                  '${formatIntegration(record.contributedIntegrationSeconds)}',
                  style: NightshadeTypography.captionSm.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          NightshadeButton(
            label: 'Retract',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onRetract,
          ),
        ],
      ),
    );
  }
}

class _SwarmTrustCard extends StatelessWidget {
  const _SwarmTrustCard();

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Row(
        children: [
          Icon(
            LucideIcons.shieldCheck,
            size: NightshadeTokens.iconSm,
            color: colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              'You only ever shared additive co-add sums, so the hub can subtract '
              'your contribution exactly to restore the prior depth.',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
