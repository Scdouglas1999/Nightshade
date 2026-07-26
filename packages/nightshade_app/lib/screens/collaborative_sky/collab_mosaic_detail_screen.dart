import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../constellation/constellation_format.dart';
import '../mosaic/mosaic_project_screen.dart';
import '../your_sky/sky_atlas_format.dart';
import 'collaborative_sky_format.dart';
import 'collaborative_sky_providers.dart';

/// The per-panel detail for one collaborative mosaic (WS2): the claimable panel
/// grid, who has claimed/uploaded each panel (the attribution that credits every
/// contributor on the finished mosaic), and the live combined progress as panels
/// land. A participant can JOIN the mosaic here — linking it to a local project
/// — then claim + capture panels from that project's screen.
class CollabMosaicDetailScreen extends ConsumerWidget {
  final String mosaicId;
  final String mosaicName;

  const CollabMosaicDetailScreen({
    super.key,
    required this.mosaicId,
    required this.mosaicName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final detailAsync = ref.watch(collaborativeMosaicDetailProvider(mosaicId));

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: mosaicName.isEmpty ? 'Mosaic' : mosaicName,
              subtitle: 'Collaborative mosaic — panels split across the club',
              icon: LucideIcons.grid,
              trailing: IconButton(
                icon: const Icon(
                  NightshadeIcons.refresh,
                  size: NightshadeTokens.iconMd,
                ),
                tooltip: 'Refresh',
                color: colors.textSecondary,
                constraints: const BoxConstraints(
                  minWidth: NightshadeTokens.minTouchTarget,
                  minHeight: NightshadeTokens.minTouchTarget,
                ),
                onPressed: () =>
                    ref.invalidate(collaborativeMosaicDetailProvider(mosaicId)),
              ),
            ),
            Expanded(
              child: detailAsync.when(
                data: (mosaic) => _Body(mosaic: mosaic),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: LucideIcons.alertCircle,
                  title: 'Could not load the mosaic',
                  body: describeConstellationError(error),
                  action: NightshadeButton(
                    label: 'Retry',
                    icon: NightshadeIcons.refresh,
                    onPressed: () => ref.invalidate(
                      collaborativeMosaicDetailProvider(mosaicId),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final CollabMosaic mosaic;

  const _Body({required this.mosaic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final total = mosaic.panels.isNotEmpty
        ? mosaic.panels.length
        : mosaic.rows * mosaic.cols;
    final uploaded = mosaic.isComplete
        ? total
        : mosaic.panels.where((p) => p.uploaded).length;
    // Credit contributors from the hub's authoritative `/v1/attribution` list
    // (WS4 consent contract) rather than reconstructing them from the owner +
    // per-panel names; falls back to the embedded names until it resolves.
    final attribution = ref
        .watch(collaborativeMosaicAttributionProvider(mosaic.mosaicId))
        .valueOrNull;
    final credits = mosaicContributorCredits(mosaic, attribution: attribution);

    return ListView(
      padding: NightshadeTokens.screenPadding,
      children: [
        NightshadeCard(
          padding: NightshadeTokens.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Combined progress',
                style: NightshadeTypography.labelStrong.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              NightshadeProgressBar(
                value:
                    mosaicCompletionFraction(uploaded: uploaded, total: total),
                state: mosaic.isComplete
                    ? NightshadeProgressState.success
                    : NightshadeProgressState.normal,
                indeterminate: mosaic.isAssembling,
                showPercentage: true,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                mosaic.isAssembling
                    ? 'All panels in — the owner is stitching the mosaic'
                    : '${formatPanelProgress(uploaded: uploaded, total: total)} '
                        '· ${formatMosaicStatus(mosaic.status)}',
                style: NightshadeTypography.captionSm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Row(
                children: [
                  Icon(
                    LucideIcons.users,
                    size: NightshadeTokens.iconXs,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      'Contributors: $credits',
                      style: NightshadeTypography.captionSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!mosaic.isComplete) ...[
          const SizedBox(height: NightshadeTokens.spaceLg),
          _JoinMosaicButton(mosaic: mosaic),
        ],
        const SizedBox(height: NightshadeTokens.spaceLg),
        const SectionHeader(
          title: 'Panels',
          subtitle: 'Each panel is a claimable work item across the club',
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        if (mosaic.panels.isEmpty)
          NightshadeCard(
            variant: CardVariant.subtle,
            padding: NightshadeTokens.cardPadding,
            child: Text(
              'This mosaic has ${mosaic.rows * mosaic.cols} panels. Panel '
              'detail loads once the owner publishes the grid.',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          )
        else
          for (final panel in mosaic.panels)
            Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
              child: _PanelRow(panel: panel),
            ),
        const SizedBox(height: NightshadeTokens.spaceLg),
      ],
    );
  }
}

/// Wires the participant JOIN flow: link this hub mosaic to a (new or existing)
/// local [MosaicProject] via [CollaborativeMosaicService.joinMosaicAsParticipant]
/// — mirroring the hub grid into a durable project — then route to the mosaic
/// project screen so the rig can claim panels and capture. In-flight state
/// disables the button + shows a spinner, mirroring the WS3 `_JoinSessionButton`
/// pattern; failures surface a snackbar via [describeConstellationError].
class _JoinMosaicButton extends ConsumerStatefulWidget {
  final CollabMosaic mosaic;

  const _JoinMosaicButton({required this.mosaic});

  @override
  ConsumerState<_JoinMosaicButton> createState() => _JoinMosaicButtonState();
}

class _JoinMosaicButtonState extends ConsumerState<_JoinMosaicButton> {
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = ref.watch(backendProvider);
    final isRemote = backend is NetworkBackend;
    final canJoin =
        backend is! NetworkBackend && backend is! DisconnectedBackend;
    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Image with this club',
            style: NightshadeTypography.labelStrong.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            isRemote
                ? 'Join this mosaic on the imaging host, where its local '
                    'project, captured panels, and masters are stored.'
                : canJoin
                    ? 'Join this mosaic to mirror its panel grid into a local '
                        'project, then claim open panels and capture them on your '
                        'rig.'
                    : 'Connect to the imaging host that will own this mosaic '
                        'project before joining.',
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: isRemote
                  ? 'Join from imaging host'
                  : canJoin
                      ? 'Join mosaic'
                      : 'Connect to join',
              icon: LucideIcons.userPlus,
              isLoading: _joining,
              onPressed: _joining || !canJoin ? null : _join,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _join() async {
    final authority = ref.read(backendProvider);
    if (authority is NetworkBackend || authority is DisconnectedBackend) {
      return;
    }
    setState(() => _joining = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final projectId = await ref
          .read(collaborativeMosaicServiceProvider)
          .joinMosaicAsParticipant(widget.mosaic);
      if (!mounted || !identical(ref.read(backendProvider), authority)) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Joined ${widget.mosaic.name.isEmpty ? 'mosaic' : widget.mosaic.name}'
            ' — claim open panels to contribute.',
          ),
        ),
      );
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MosaicProjectScreen(projectId: projectId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeConstellationError(error))),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
}

class _PanelRow extends StatelessWidget {
  final CollabMosaicPanel panel;

  const _PanelRow({required this.panel});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final credit = (panel.assignedDisplayName ?? '').trim();

    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: NightshadeDecorations.tintedBadge(colors.primary),
            child: Text(
              '${panel.panelIndex + 1}',
              style: NightshadeTypography.labelStrongSm.copyWith(
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCenter(panel.centerRaDeg, panel.centerDecDeg),
                  style: NightshadeTypography.captionSm.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (credit.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    credit,
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          StatusPill(
            icon: _panelIcon(panel.status),
            label: '',
            value: _panelLabel(panel.status),
            status: _panelVariant(panel.status),
          ),
        ],
      ),
    );
  }

  IconData _panelIcon(String status) {
    switch (status) {
      case 'uploaded':
        return LucideIcons.checkCircle2;
      case 'claimed':
        return LucideIcons.user;
      default:
        return LucideIcons.circleDashed;
    }
  }

  String _panelLabel(String status) {
    switch (status) {
      case 'uploaded':
        return 'Uploaded';
      case 'claimed':
        return 'Claimed';
      default:
        return 'Open';
    }
  }

  StatusPillStatus _panelVariant(String status) {
    switch (status) {
      case 'uploaded':
        return StatusPillStatus.success;
      case 'claimed':
        return StatusPillStatus.active;
      default:
        return StatusPillStatus.inactive;
    }
  }
}
