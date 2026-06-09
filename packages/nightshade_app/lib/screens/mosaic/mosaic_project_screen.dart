import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../session_review/widgets/master_overlay_view.dart';
import '../session_review/widgets/master_preview_view.dart';
import 'mosaic_project_controller.dart';
import 'widgets/mosaic_panel_grid.dart';

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

  /// Builds a panel's per-panel master FITS base path. Defaults to a temp-dir
  /// stem under the system temp; the app/router can inject a real artifacts dir.
  final String Function(MosaicProjectPanel panel)? panelOutputPathBuilder;

  /// Builds the directory the stitched mosaic artifacts land in. Defaults to a
  /// per-project temp dir.
  final String Function(MosaicProject project)? stitchOutputDirectory;

  const MosaicProjectScreen({
    super.key,
    required this.projectId,
    this.panelOutputPathBuilder,
    this.stitchOutputDirectory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = MosaicProjectControllerArgs(
      projectId: projectId,
      panelOutputPathBuilder:
          panelOutputPathBuilder ?? _defaultPanelOutputPathBuilder,
      stitchOutputDirectory:
          stitchOutputDirectory ?? _defaultStitchOutputDirectory,
    );
    final state = ref.watch(mosaicProjectControllerProvider(args));
    final controller = ref.read(mosaicProjectControllerProvider(args).notifier);
    final colors = NightshadeColors.of(context);

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

  static String _defaultPanelOutputPathBuilder(MosaicProjectPanel panel) =>
      p.join(
        Directory.systemTemp.path,
        'nightshade_mosaic',
        'project_${panel.projectId}',
        'panel_${panel.panelIndex}.fits',
      );

  static String _defaultStitchOutputDirectory(MosaicProject project) => p.join(
        Directory.systemTemp.path,
        'nightshade_mosaic',
        'project_${project.id}',
      );
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
          if (state.isBusy) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeProgressBar(
              value: 0,
              indeterminate: true,
              label: state.isIntegrating
                  ? 'Integrating panels…'
                  : 'Stitching mosaic…',
            ),
          ],
        ],
      ),
    );
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
                  rejectionMapPngPath: master.rejectionMapPath,
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
