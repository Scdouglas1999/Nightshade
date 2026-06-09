import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The NxM panel grid: one tile per [MosaicProjectPanel], laid out row-major to
/// match the grid (`cols` wide), each showing the panel's status, captured
/// frame count, and — once integrated — a thumbnail of its per-panel master.
///
/// Pure presentation: it is handed the panels, the resolved per-panel masters
/// (keyed by `integrated_master_id`), and the grid dimensions; it never reads
/// the DB. Status colour + label come from the design system tokens only.
class MosaicPanelGrid extends StatelessWidget {
  /// Panels ordered by `panel_index` (row-major).
  final List<MosaicProjectPanel> panels;

  /// Per-panel masters keyed by `mosaic_panels.integrated_master_id`.
  final Map<int, IntegratedMaster> panelMasters;

  /// Grid columns (panels per row).
  final int cols;

  const MosaicPanelGrid({
    super.key,
    required this.panels,
    required this.panelMasters,
    required this.cols,
  });

  @override
  Widget build(BuildContext context) {
    if (panels.isEmpty) {
      return const EmptyState.compact(
        icon: NightshadeIcons.grid,
        title: 'No panels',
        body: 'This project has no panels laid out yet.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = NightshadeTokens.spaceSm;
        final columns = cols.clamp(1, panels.length);
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final panel in panels)
              SizedBox(
                width: tileWidth,
                child: _PanelTile(
                  panel: panel,
                  master: panel.integratedMasterId == null
                      ? null
                      : panelMasters[panel.integratedMasterId],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One panel tile — a [NightshadeCard] holding the panel number, its status
/// pill, a master thumbnail (when integrated) or a status-tinted placeholder,
/// and the captured-frame count.
class _PanelTile extends StatelessWidget {
  final MosaicProjectPanel panel;
  final IntegratedMaster? master;

  const _PanelTile({required this.panel, this.master});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final preview = master?.previewPngPath;
    final hasThumb = preview != null && _exists(preview);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Panel ${panel.panelIndex + 1}',
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              _PanelStatusDot(status: panel.status),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: NightshadeTokens.borderRadiusSm,
              child: hasThumb
                  ? Image.file(
                      File(preview),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _Placeholder(status: panel.status),
                    )
                  : _Placeholder(status: panel.status),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Row(
            children: [
              Text(
                mosaicPanelStatusLabel(panel.status),
                style: NightshadeTypography.captionSm.copyWith(
                  color: mosaicPanelStatusColor(panel.status, colors),
                ),
              ),
              const Spacer(),
              Text(
                '${panel.capturedCount} sub${panel.capturedCount == 1 ? '' : 's'}',
                style: NightshadeTypography.captionSm
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

/// The status-tinted placeholder shown when a panel has no master thumbnail
/// (pending / capturing / captured / failed): a status icon over a faint tint.
class _Placeholder extends StatelessWidget {
  final MosaicPanelStatus status;

  const _Placeholder({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final tint = mosaicPanelStatusColor(status, colors);
    return Container(
      color: tint.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(
        _statusIcon(status),
        size: NightshadeTokens.iconLg,
        color: tint.withValues(alpha: 0.7),
      ),
    );
  }

  IconData _statusIcon(MosaicPanelStatus status) {
    switch (status) {
      case MosaicPanelStatus.pending:
        return NightshadeIcons.clock;
      case MosaicPanelStatus.capturing:
        return NightshadeIcons.camera;
      case MosaicPanelStatus.captured:
        return NightshadeIcons.image;
      case MosaicPanelStatus.integrated:
        return NightshadeIcons.layers;
      case MosaicPanelStatus.failed:
        return NightshadeIcons.warning;
    }
  }
}

/// A small status dot for the panel tile header.
class _PanelStatusDot extends StatelessWidget {
  final MosaicPanelStatus status;

  const _PanelStatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return StatusDot(
      color: mosaicPanelStatusColor(status, colors),
      size: NightshadeTokens.spaceSm,
    );
  }
}

/// The display label for a [MosaicPanelStatus]. Shared with the header summary.
String mosaicPanelStatusLabel(MosaicPanelStatus status) {
  switch (status) {
    case MosaicPanelStatus.pending:
      return 'Pending';
    case MosaicPanelStatus.capturing:
      return 'Capturing';
    case MosaicPanelStatus.captured:
      return 'Captured';
    case MosaicPanelStatus.integrated:
      return 'Integrated';
    case MosaicPanelStatus.failed:
      return 'Failed';
  }
}

/// The design-system colour for a [MosaicPanelStatus]. Pulls only from the
/// passed [colors] (no raw hex): muted for pending, primary for in-flight /
/// captured, success for integrated, error for failed.
Color mosaicPanelStatusColor(
    MosaicPanelStatus status, NightshadeColors colors) {
  switch (status) {
    case MosaicPanelStatus.pending:
      return colors.textMuted;
    case MosaicPanelStatus.capturing:
      return colors.primary;
    case MosaicPanelStatus.captured:
      return colors.info;
    case MosaicPanelStatus.integrated:
      return colors.success;
    case MosaicPanelStatus.failed:
      return colors.error;
  }
}
