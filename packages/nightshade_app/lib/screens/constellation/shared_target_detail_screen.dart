import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
            const SizedBox(height: NightshadeTokens.spaceMd),
            _ContributeCard(
              enabled: _joined,
              yourSeconds: yourSeconds,
              onContribute: _contribute,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _BlendCard(
              enabled: _joined,
              pulling: _pulling,
              blended: _blended,
              onPull: _pullAndBlend,
            ),
            if (_blended.isNotEmpty) ...[
              const SizedBox(height: NightshadeTokens.spaceMd),
              const _RetractHintCard(),
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
    try {
      final tiles = await ref
          .read(constellationServiceProvider)
          .pullTarget(_target.targetId);
      if (!mounted) return;
      setState(() {
        _blended = tiles;
        _pulling = false;
      });
      // The pulled tiles now live under the atlas swarm/ cache; refresh the
      // atlas read surface so Your Sky can blend them in.
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
                    'for this field. Open Your Sky to scrub the combined depth.'
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

class _RetractHintCard extends StatelessWidget {
  const _RetractHintCard();

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
              'Changed your mind? A contribution can be retracted from the hub '
              'at any time — the swarm subtracts your sums exactly.',
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
