import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../session_review/widgets/master_overlay_view.dart';
import '../session_review/widgets/master_preview_view.dart';
import 'mosaic_contribute_sheet.dart';
import 'mosaic_project_controller.dart';
import 'widgets/mosaic_panel_grid.dart';

/// Present the WS4 consent sheet (license + anonymity opt-in) and, if the user
/// confirms, upload either one panel ([panelIndex] set) or every
/// integrated-but-unuploaded panel under the chosen license/attribution. A
/// cancelled sheet ships nothing — no panel master leaves the device without an
/// explicit per-upload opt-in.
Future<void> _uploadMosaicWithConsent(
  BuildContext context,
  MosaicProjectController controller, {
  int? panelIndex,
}) async {
  final choice = await showMosaicContributeSheet(context);
  if (choice == null) return;
  if (panelIndex == null) {
    await controller.uploadAllIntegrated(
      license: choice.license,
      attributionConsent: choice.attributionConsent,
    );
  } else {
    await controller.uploadPanelMaster(
      panelIndex,
      license: choice.license,
      attributionConsent: choice.attributionConsent,
    );
  }
}

/// Owner-only destructive recovery: confirm before force-releasing [panelIndex]
/// back to `pending` on the hub, since it drops the panel's current claim or
/// uploaded master and cannot be undone.
Future<void> _confirmForceRelease(
  BuildContext context,
  MosaicProjectController controller,
  int panelIndex,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Force release panel?'),
      content: Text(
        'Panel ${panelIndex + 1} will be released back to pending on the hub, '
        'dropping its current claim or uploaded master. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Force release'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.forceReleasePanel(panelIndex);
  }
}

/// Resolves the DURABLE per-app base directory for mosaic artifacts —
/// `<applicationSupport>/nightshade_mosaic`. Panel masters and the stitched
/// mosaic FITS/PNG land under a per-project subfolder of this so they SURVIVE
/// reboots and OS temp-dir sweeps (the old `Directory.systemTemp` default was a
/// data-loss footgun: panel masters and the stitched mosaic could vanish the
/// moment the OS cleaned temp).
final mosaicArtifactsBaseDirProvider = FutureProvider<String>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  return p.join(supportDir.path, 'nightshade_mosaic');
});

/// The mosaic project review screen at `/mosaic/:id`.
///
/// Shows a header (name, target region, NxM grid, status), the panel grid (each
/// panel's status + captured count + a master thumbnail once integrated), the
/// two durable actions (Integrate panels / Stitch mosaic) with busy/error
/// states, and — once the project is complete — the stitched master in the
/// reused [MasterOverlayView] / [MasterPreviewView].
///
/// Design-system pure: every colour, gap, and type style comes from
/// `nightshade_ui` tokens; the stitched-master hero is the morning-report widget
/// reused verbatim.
class MosaicProjectScreen extends ConsumerWidget {
  /// The `mosaic_projects.id` to review.
  final int projectId;

  /// Builds a panel's per-panel master FITS base path. When omitted the screen
  /// derives a DURABLE path under `<applicationSupport>/nightshade_mosaic`
  /// (resolved via [mosaicArtifactsBaseDirProvider]); the app/router can inject
  /// an explicit builder.
  final String Function(MosaicProjectPanel panel)? panelOutputPathBuilder;

  /// Builds the directory the stitched mosaic artifacts land in. When omitted
  /// the screen derives a DURABLE per-project subfolder under
  /// `<applicationSupport>/nightshade_mosaic`.
  final String Function(MosaicProject project)? stitchOutputDirectory;

  const MosaicProjectScreen({
    super.key,
    required this.projectId,
    this.panelOutputPathBuilder,
    this.stitchOutputDirectory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    if (ref.watch(backendProvider) is NetworkBackend) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          child: EmptyState(
            icon: NightshadeIcons.device,
            title: 'Open this mosaic project on the imaging host',
            body: 'Mosaic project records, panel masters, and stitched '
                'artifacts live on the imaging computer. Remote project '
                'control is unavailable in this release.',
          ),
        ),
      );
    }

    // Resolve the DURABLE artifacts base before constructing the controller, so
    // panel/stitch FITS never land in (and get swept from) the system temp dir.
    // Explicit builders bypass the async resolution entirely.
    final hasExplicitBuilders =
        panelOutputPathBuilder != null && stitchOutputDirectory != null;
    if (hasExplicitBuilders) {
      return _scaffold(
        context,
        ref,
        colors,
        panelOutputPathBuilder!,
        stitchOutputDirectory!,
      );
    }

    final baseDir = ref.watch(mosaicArtifactsBaseDirProvider);
    return baseDir.when(
      loading: () => Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: EmptyState(
            icon: NightshadeIcons.warning,
            title: 'Mosaic storage unavailable',
            body: 'Could not resolve a durable artifacts directory: $e',
          ),
        ),
      ),
      data: (base) => _scaffold(
        context,
        ref,
        colors,
        panelOutputPathBuilder ?? _durablePanelOutputPathBuilder(base),
        stitchOutputDirectory ?? _durableStitchOutputDirectory(base),
      ),
    );
  }

  Widget _scaffold(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    String Function(MosaicProjectPanel panel) panelBuilder,
    String Function(MosaicProject project) stitchBuilder,
  ) {
    final args = MosaicProjectControllerArgs(
      projectId: projectId,
      panelOutputPathBuilder: panelBuilder,
      stitchOutputDirectory: stitchBuilder,
    );
    final state = ref.watch(mosaicProjectControllerProvider(args));
    final controller = ref.read(mosaicProjectControllerProvider(args).notifier);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: _body(context, state, controller),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    MosaicProjectState state,
    MosaicProjectController controller,
  ) {
    if (state.isLoading && state.project == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final project = state.project;
    if (project == null) {
      return EmptyState(
        icon: NightshadeIcons.grid,
        title: 'Mosaic project not found',
        body: state.error ?? 'No mosaic project with id $projectId.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MosaicProjectHeader(project: project, state: state),
        if (state.error != null)
          _ErrorBanner(message: state.error!, onDismiss: controller.clearError),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MosaicProjectActions(state: state, controller: controller),
                if (controller.canCollaborate) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  const SectionHeader(
                    title: 'Collaborative mosaic',
                    subtitle:
                        'Split the panels across your club and fuse centrally',
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  MosaicCollaborativeSection(
                    state: state,
                    controller: controller,
                  ),
                ],
                const SizedBox(height: NightshadeTokens.spaceLg),
                const SectionHeader(
                  title: 'Panels',
                  subtitle: 'Per-panel capture, integration, and master',
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                MosaicPanelGrid(
                  panels: state.panels,
                  panelMasters: state.panelMasters,
                  cols: project.cols,
                  // WS2 — surface per-panel claim/upload once the project is a
                  // published collaborative mosaic and a hub service is wired.
                  collaborative: controller.canCollaborate && state.isPublished,
                  collaborativeBusy: state.isBusy,
                  onClaimPanel: controller.claimPanel,
                  // WS2 owner/admin recovery: evict a squatting claim or a
                  // poisoned upload back to pending. Only the owner path gets the
                  // callback (the grid hides the button when it is null), so a
                  // non-owner never sees an always-failing destructive action; a
                  // confirm dialog guards the owner's irreversible release.
                  onForceReleasePanel: state.project?.collabRole == 'owner'
                      ? (idx) => _confirmForceRelease(context, controller, idx)
                      : null,
                  // WS4: route the per-panel upload through the consent sheet
                  // rather than calling the service with a silent default.
                  onUploadPanel: (idx) => _uploadMosaicWithConsent(
                    context,
                    controller,
                    panelIndex: idx,
                  ),
                ),
                if (state.isComplete) ...[
                  const SizedBox(height: NightshadeTokens.spaceXl),
                  const SectionHeader(
                    title: 'Stitched master',
                    subtitle: 'The composited mosaic across all panels',
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  MosaicStitchedMasterView(master: state.stitchedMaster!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Per-panel master FITS base path under the DURABLE [base] artifacts dir:
  /// `<base>/project_<id>/panel_<index>.fits`.
  static String Function(MosaicProjectPanel panel)
      _durablePanelOutputPathBuilder(
    String base,
  ) =>
          (panel) => p.join(
                base,
                'project_${panel.projectId}',
                'panel_${panel.panelIndex}.fits',
              );

  /// Per-project stitched-mosaic artifacts directory under the DURABLE [base]:
  /// `<base>/project_<id>`.
  static String Function(MosaicProject project) _durableStitchOutputDirectory(
    String base,
  ) =>
      (project) => p.join(base, 'project_${project.id}');
}

/// The project header: name, target region (RA/Dec), NxM grid, and lifecycle
/// status pill.
class MosaicProjectHeader extends StatelessWidget {
  final MosaicProject project;
  final MosaicProjectState state;

  const MosaicProjectHeader({
    super.key,
    required this.project,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final center = _centerLabel(state.panels);
    final integrated = state.countWithStatus(MosaicPanelStatus.integrated);
    return ScreenHeader(
      icon: NightshadeIcons.grid,
      title: project.name.isEmpty ? 'Mosaic project' : project.name,
      subtitle: [
        '${project.cols}x${project.rows} grid',
        '${project.totalPanels} panels',
        if (center != null) center,
        '$integrated integrated',
      ].join('  ·  '),
      trailing: StatusPill(
        icon: _statusIcon(project.status),
        label: 'Status',
        value: mosaicProjectStatusLabel(project.status),
        status: _pillStatus(project.status, colors),
      ),
    );
  }

  /// The mosaic's centre as a compact "RA · Dec" string, derived from the panel
  /// centres (mean), or null when there are no panels.
  static String? _centerLabel(List<MosaicProjectPanel> panels) {
    if (panels.isEmpty) return null;
    var ra = 0.0;
    var dec = 0.0;
    for (final panel in panels) {
      ra += panel.centerRa;
      dec += panel.centerDec;
    }
    ra /= panels.length;
    dec /= panels.length;
    return '${CoordinateParser.formatRaHms(ra)} '
        '${CoordinateParser.formatDecDms(dec)}';
  }

  static IconData _statusIcon(MosaicProjectStatus status) {
    switch (status) {
      case MosaicProjectStatus.planning:
        return NightshadeIcons.clock;
      case MosaicProjectStatus.capturing:
        return NightshadeIcons.camera;
      case MosaicProjectStatus.integrating:
        return NightshadeIcons.layers;
      case MosaicProjectStatus.stitching:
        return NightshadeIcons.grid;
      case MosaicProjectStatus.complete:
        return NightshadeIcons.success;
    }
  }

  static StatusPillStatus _pillStatus(
    MosaicProjectStatus status,
    NightshadeColors colors,
  ) {
    switch (status) {
      case MosaicProjectStatus.planning:
        return StatusPillStatus.inactive;
      case MosaicProjectStatus.capturing:
      case MosaicProjectStatus.integrating:
      case MosaicProjectStatus.stitching:
        return StatusPillStatus.active;
      case MosaicProjectStatus.complete:
        return StatusPillStatus.success;
    }
  }
}

/// The action row: 'Integrate panels' and 'Stitch mosaic', with busy/progress
/// and a stitch gate (<2 panels with masters disables stitch and explains why).
class MosaicProjectActions extends StatelessWidget {
  final MosaicProjectState state;
  final MosaicProjectController controller;

  const MosaicProjectActions({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final canStitch = state.canStitch;
    return NightshadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: NightshadeTokens.spaceMd,
            runSpacing: NightshadeTokens.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (controller.canStartCapture)
                NightshadeButton(
                  label: 'Start capture',
                  icon: NightshadeIcons.camera,
                  isLoading: state.isStartingCapture,
                  onPressed:
                      state.isBusy ? null : () => controller.startCapture(),
                ),
              NightshadeButton(
                label: 'Integrate panels',
                icon: NightshadeIcons.layers,
                isLoading: state.isIntegrating,
                onPressed:
                    state.isBusy ? null : () => controller.integratePanels(),
              ),
              NightshadeButton(
                label: 'Stitch mosaic',
                icon: NightshadeIcons.grid,
                variant: ButtonVariant.outline,
                isLoading: state.isStitching,
                onPressed: (!canStitch || state.isBusy)
                    ? null
                    : () => controller.stitchProject(),
              ),
              Text(
                canStitch
                    ? '${state.panelsWithMasters} of ${state.panels.length} '
                        'panels integrated'
                    : 'Stitch needs ≥ 2 integrated panels '
                        '(${state.panelsWithMasters} ready)',
                style: NightshadeTypography.bodySm.copyWith(
                  color: canStitch ? colors.textSecondary : colors.textMuted,
                ),
              ),
            ],
          ),
          if (state.isStartingCapture ||
              state.isIntegrating ||
              state.isStitching) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeProgressBar(
              value: 0,
              indeterminate: true,
              label: state.isStartingCapture
                  ? 'Launching capture…'
                  : state.isIntegrating
                      ? 'Integrating panels…'
                      : 'Stitching mosaic…',
            ),
          ],
        ],
      ),
    );
  }
}

/// Collaborative Sky WS2 — the distributed-mosaic lifecycle card on the owner /
/// participant project view. It surfaces the whole publish → claim → upload →
/// assemble → download loop by invoking the already-wired
/// [MosaicProjectController] collaborative actions; it owns no hub logic of its
/// own.
///
/// State machine rendered from the durable project + live `collab_status`:
///  * not yet published  → "Publish to hub" (becomes claimable work items);
///  * published          → hub id + role + status, claim-all / upload-all, and
///    a "Refresh status" poll control;
///  * owner + assembling  → "Assemble + publish" (pull every panel, stitch,
///    push the finished mosaic to the swarm);
///  * complete            → "Download finished mosaic".
///
/// Every button binds its enabled/spinner state to the controller's
/// isPublishing/isClaiming/isUploading/isAssembling/isRefreshing/isDownloading
/// busy flags; errors land on the screen-level banner via `state.error`.
class MosaicCollaborativeSection extends StatelessWidget {
  final MosaicProjectState state;
  final MosaicProjectController controller;

  const MosaicCollaborativeSection({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final published = state.isPublished;
    final role = state.project?.collabRole;
    final collabStatus = state.collabStatus;
    final isOwner = role == 'owner';

    return NightshadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!published) ...[
            Text(
              'This mosaic is local-only. Publish its panel grid to the hub so '
              'your club can claim and capture panels in parallel.',
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            Align(
              alignment: Alignment.centerLeft,
              child: NightshadeButton(
                label: 'Publish to hub',
                icon: NightshadeIcons.upload,
                isLoading: state.isPublishing,
                onPressed:
                    state.isBusy ? null : () => controller.publishToHub(),
              ),
            ),
          ] else ...[
            _CollabStatusLine(
              hubMosaicId: state.hubMosaicId ?? '',
              role: role,
              collabStatus: collabStatus,
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            Wrap(
              spacing: NightshadeTokens.spaceMd,
              runSpacing: NightshadeTokens.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NightshadeButton(
                  label: 'Claim all pending',
                  icon: NightshadeIcons.download,
                  variant: ButtonVariant.outline,
                  isLoading: state.isClaiming,
                  onPressed: (state.isBusy || state.unclaimedPanels.isEmpty)
                      ? null
                      : () => controller.claimAllPending(),
                ),
                NightshadeButton(
                  label: 'Upload all integrated',
                  icon: NightshadeIcons.upload,
                  variant: ButtonVariant.outline,
                  isLoading: state.isUploading,
                  onPressed:
                      (state.isBusy || state.integratedNotUploaded.isEmpty)
                          ? null
                          : () => _uploadMosaicWithConsent(context, controller),
                ),
                if (isOwner && collabStatus == 'assembling')
                  NightshadeButton(
                    label: 'Assemble + publish',
                    icon: NightshadeIcons.grid,
                    isLoading: state.isAssembling,
                    onPressed: state.isBusy
                        ? null
                        : () => controller.assembleFromHub(),
                  ),
                if (collabStatus == 'complete')
                  NightshadeButton(
                    label: 'Download finished mosaic',
                    icon: NightshadeIcons.download,
                    isLoading: state.isDownloading,
                    onPressed:
                        state.isBusy ? null : () => controller.downloadOutput(),
                  ),
                NightshadeButton(
                  label: 'Refresh status',
                  icon: NightshadeIcons.refresh,
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                  isLoading: state.isRefreshing,
                  onPressed:
                      state.isBusy ? null : () => controller.refreshStatus(),
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              '${state.panelsUploaded} of ${state.panels.length} panels '
              'uploaded to the hub'
              '${isOwner ? '' : ' · claim a panel below to contribute'}',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The published-mosaic summary line: hub id, this device's role, and the live
/// hub-side lifecycle pill.
class _CollabStatusLine extends StatelessWidget {
  final String hubMosaicId;
  final String? role;
  final String? collabStatus;

  const _CollabStatusLine({
    required this.hubMosaicId,
    required this.role,
    required this.collabStatus,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      children: [
        Icon(
          role == 'owner' ? NightshadeIcons.star : NightshadeIcons.user,
          size: NightshadeTokens.iconSm,
          color: colors.primary,
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            'Hub mosaic $hubMosaicId · '
            '${role == 'owner' ? 'Owner' : 'Participant'}',
            style:
                NightshadeTypography.bodySm.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        StatusPill(
          icon: _collabStatusIcon(collabStatus),
          label: 'Status',
          value: collabMosaicStatusLabel(collabStatus),
          status: _collabPillStatus(collabStatus),
        ),
      ],
    );
  }

  static IconData _collabStatusIcon(String? status) {
    switch (status) {
      case 'assembling':
        return NightshadeIcons.layers;
      case 'complete':
        return NightshadeIcons.success;
      case 'published':
      default:
        return NightshadeIcons.share;
    }
  }

  static StatusPillStatus _collabPillStatus(String? status) {
    switch (status) {
      case 'assembling':
        return StatusPillStatus.warning;
      case 'complete':
        return StatusPillStatus.success;
      case 'published':
      default:
        return StatusPillStatus.active;
    }
  }
}

/// The display label for a hub-side collaborative `collab_status`.
String collabMosaicStatusLabel(String? status) {
  switch (status) {
    case 'assembling':
      return 'Assembling';
    case 'complete':
      return 'Complete';
    case 'published':
      return 'Published';
    default:
      return status == null || status.isEmpty ? 'Published' : status;
  }
}

/// The stitched-master hero. Reuses the morning-report [MasterOverlayView] when
/// a preview PNG is on disk (so the operator gets zoom/pan + coverage/rejection
/// overlays), falling back to [MasterPreviewView] otherwise (which renders its
/// own honest empty state when even the preview is missing).
class MosaicStitchedMasterView extends StatelessWidget {
  final IntegratedMaster master;

  const MosaicStitchedMasterView({super.key, required this.master});

  @override
  Widget build(BuildContext context) {
    final preview = master.previewPngPath;
    return SizedBox(
      height: 520,
      child: NightshadeCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: NightshadeTokens.borderRadiusMd,
          child: preview != null
              ? MasterOverlayView(
                  previewPngPath: preview,
                  rejectionMapPngPath: master.rejectionMapPreviewPath,
                  coverageMapPngPath: master.coverageMapPreviewPath,
                )
              : MasterPreviewView.fromMaster(master),
        ),
      ),
    );
  }
}

/// A dismissible error banner shown under the header.
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceSm,
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.warning,
              size: NightshadeTokens.iconSm, color: colors.error),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              message,
              style: NightshadeTypography.bodySm.copyWith(color: colors.error),
            ),
          ),
          IconButton(
            icon: Icon(NightshadeIcons.close,
                size: NightshadeTokens.iconSm, color: colors.textSecondary),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// The display label for a [MosaicProjectStatus].
String mosaicProjectStatusLabel(MosaicProjectStatus status) {
  switch (status) {
    case MosaicProjectStatus.planning:
      return 'Planning';
    case MosaicProjectStatus.capturing:
      return 'Capturing';
    case MosaicProjectStatus.integrating:
      return 'Integrating';
    case MosaicProjectStatus.stitching:
      return 'Stitching';
    case MosaicProjectStatus.complete:
      return 'Complete';
  }
}
