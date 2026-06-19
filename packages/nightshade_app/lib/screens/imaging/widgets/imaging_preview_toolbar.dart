import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/catalog_overlay_widget.dart'
    show CatalogOverlayPopover;
import '../../../widgets/tutorial_keys/imaging_keys.dart';
import 'annotation_widgets.dart' show annotationPanelVisibleProvider;
import 'custom_annotation_drawing.dart'
    show customAnnotationDrawModeActiveProvider, toggleAnnotationDrawPalette;
import 'overlay_widgets.dart';

/// Slim, off-canvas toolbar that sits *above* the live preview image rather
/// than floating over it. Hosts three groups, left-to-right:
///
///  1. A low-emphasis status readout cluster (resolution / binning / zoom% and
///     a Sky transparency readout). Reads as STATUS — no button chrome.
///  2. A single labelled **Overlays** popover that replaces the six former
///     loose overlay-toggle icons. Each menu row drives the exact same
///     provider/callback the old icon did.
///  3. A tight view-controls group (zoom in/out, 1:1, fit, abort capture).
///
/// The same widget renders for both the desktop and mobile imaging layouts.
/// On narrow widths the status cluster is allowed to scroll horizontally so it
/// never pushes the controls off-screen; the controls stay pinned trailing.
///
/// Every control here reuses the providers and callbacks that previously lived
/// in the on-image overlay bar — this is purely a relocation + regrouping, not
/// a behaviour change.
class ImagingPreviewToolbar extends ConsumerWidget {
  final NightshadeColors colors;
  final double zoomLevel;
  final bool showCrosshair;
  final bool showStarOverlay;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToWindow;
  final VoidCallback onZoom1to1;
  final VoidCallback onAbortCapture;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleStarOverlay;

  const ImagingPreviewToolbar({
    super.key,
    required this.colors,
    required this.zoomLevel,
    required this.showCrosshair,
    required this.showStarOverlay,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToWindow,
    required this.onZoom1to1,
    required this.onAbortCapture,
    required this.onToggleCrosshair,
    required this.onToggleStarOverlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentImage = ref.watch(currentImageProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final scienceSnapshot = ref.watch(currentScienceSnapshotProvider);
    final latestTransparency = scienceSnapshot.$2;

    final status = _StatusReadoutCluster(
      colors: colors,
      resolutionLabel: currentImage != null
          ? '${currentImage.width} × ${currentImage.height}'
          : '--- × ---',
      binningLabel: 'Bin ${exposureSettings.binning}',
      zoomLabel: '${(zoomLevel * 100).round()}%',
      showCalibration: true,
      skyLabel: latestTransparency == null
          ? 'Sky --'
          : 'Sky ${latestTransparency.qualityBucket}',
    );

    final overlays = OverlaysMenuButton(
      colors: colors,
      showCrosshair: showCrosshair,
      showStarOverlay: showStarOverlay,
      onToggleCrosshair: onToggleCrosshair,
      onToggleStarOverlay: onToggleStarOverlay,
    );

    final viewControls = _ViewControlsGroup(
      colors: colors,
      onZoomIn: onZoomIn,
      onZoomOut: onZoomOut,
      onZoom1to1: onZoom1to1,
      onFitToWindow: onFitToWindow,
      onAbortCapture: onAbortCapture,
      showAbort: exposureProgress.percent > 0 && exposureProgress.percent < 1.0,
    );

    final trailing = <Widget>[
      overlays,
      const SizedBox(width: NightshadeTokens.spaceXs),
      // Annotate toggle: opens/closes the docked drawing palette. Only
      // meaningful with a frame on the canvas to draw over.
      if (currentImage != null) ...[
        _DrawModeButton(colors: colors),
        const SizedBox(width: NightshadeTokens.spaceXs),
      ],
      viewControls,
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The status readouts + Overlays menu + view controls do not all fit
          // on a narrow bar. Rather than clip, the whole bar becomes one
          // horizontally-scrolling row so every control stays reachable. Only
          // on a genuinely wide bar does the status cluster take the slack
          // (Expanded) with controls pinned right. The threshold is set above
          // the widest phone-landscape image pane (~544px on a Z Fold cover
          // split) so that pane scrolls instead of overflowing the trailing
          // controls by a few px; desktop full-width toolbars still expand.
          const wideEnough = 680.0;
          if (constraints.maxWidth >= wideEnough) {
            return Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: status,
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
                ...trailing,
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                status,
                const SizedBox(width: NightshadeTokens.spaceSm),
                ...trailing,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Labelled "Annotate" toggle. Flips [annotationDrawPaletteOpenProvider] via
/// [toggleAnnotationDrawPalette] so the docked drawing palette appears at the
/// bottom of the canvas only while drawing is active. Shows the active accent
/// while the palette / a tool is engaged.
class _DrawModeButton extends ConsumerWidget {
  final NightshadeColors colors;

  const _DrawModeButton({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(customAnnotationDrawModeActiveProvider);
    return _LabeledToolbarToggle(
      colors: colors,
      icon: NightshadeIcons.edit,
      label: 'Annotate',
      tooltip: active ? 'Close drawing tools' : 'Draw on the image',
      active: active,
      onTap: () => toggleAnnotationDrawPalette(ref),
    );
  }
}

/// Low-emphasis, non-interactive status readout. Renders as a row of muted
/// text segments separated by thin dividers — deliberately *not* chips with
/// button chrome, so it never reads as tappable. The Sky/transparency readout
/// sits behind a leading gauge icon; zero-point now lives only in the richer
/// tappable [FrameScienceChip] on the canvas.
class _StatusReadoutCluster extends StatelessWidget {
  final NightshadeColors colors;
  final String resolutionLabel;
  final String binningLabel;
  final String zoomLabel;
  final bool showCalibration;
  final String skyLabel;

  const _StatusReadoutCluster({
    required this.colors,
    required this.resolutionLabel,
    required this.binningLabel,
    required this.zoomLabel,
    required this.showCalibration,
    required this.skyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _segment(NightshadeIcons.expand, resolutionLabel),
      _divider(),
      _segment(NightshadeIcons.grid, binningLabel),
      _divider(),
      _segment(NightshadeIcons.search, zoomLabel),
    ];

    if (showCalibration) {
      children
        ..add(_divider())
        ..add(_segment(NightshadeIcons.gauge, skyLabel));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _segment(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceSm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
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

  Widget _divider() {
    return Container(
      width: 1,
      height: 14,
      color: colors.border,
    );
  }
}

/// The single labelled "Overlays" entry point that replaces the six former
/// loose overlay-toggle icons. Tapping opens a compact popover of labelled
/// checkbox rows; each row drives the same provider/callback the old icon did.
///
/// The button shows the active accent whenever *any* overlay is enabled, so the
/// operator still gets at-a-glance "something is drawn on the frame" feedback
/// without six competing glyphs.
class OverlaysMenuButton extends ConsumerWidget {
  final NightshadeColors colors;
  final bool showCrosshair;
  final bool showStarOverlay;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleStarOverlay;

  const OverlaysMenuButton({
    super.key,
    required this.colors,
    required this.showCrosshair,
    required this.showStarOverlay,
    required this.onToggleCrosshair,
    required this.onToggleStarOverlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull ??
            const AnnotationSettings();
    final gridType = annotationSettings.gridType;
    final annotationPanelVisible = ref.watch(annotationPanelVisibleProvider);
    final catalogEnabled = ref.watch(catalogOverlayEnabledProvider);
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceHudVisible = scienceMode.scienceHudVisible;

    final anyOverlayActive = showCrosshair ||
        gridType != GridType.none ||
        showStarOverlay ||
        annotationPanelVisible ||
        catalogEnabled ||
        scienceHudVisible;

    return PopupMenuButton<int>(
      tooltip: 'Overlays',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 248, maxWidth: 296),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      // Each item handles its own onTap so the menu stays open is NOT desired —
      // PopupMenu closes after a tap, which matches a quick "flip one overlay"
      // interaction. Re-opening to flip a second overlay is one click.
      itemBuilder: (context) {
        return <PopupMenuEntry<int>>[
          _overlayItem(
            value: 0,
            icon: NightshadeIcons.crosshair,
            label: 'Crosshair',
            active: showCrosshair,
            onTap: onToggleCrosshair,
          ),
          _overlayItem(
            value: 1,
            icon: gridType == GridType.celestial
                ? NightshadeIcons.globe
                : NightshadeIcons.grid,
            label: 'Grid',
            subtitle: switch (gridType) {
              GridType.none => 'Off',
              GridType.pixel => 'Pixel',
              GridType.celestial => 'RA / Dec',
            },
            active: gridType != GridType.none,
            onTap: () =>
                ref.read(annotationSettingsProvider.notifier).cycleGridType(),
          ),
          _overlayItem(
            value: 2,
            icon: NightshadeIcons.sparkle,
            label: 'Star detection',
            active: showStarOverlay,
            onTap: onToggleStarOverlay,
          ),
          _overlayItem(
            value: 3,
            icon: NightshadeIcons.list,
            label: 'Object annotations',
            active: annotationPanelVisible,
            onTap: () => ref
                .read(annotationPanelVisibleProvider.notifier)
                .state = !annotationPanelVisible,
          ),
          _overlayItem(
            value: 4,
            icon: NightshadeIcons.target,
            label: 'Catalog overlay',
            active: catalogEnabled,
            onTap: () => ref
                .read(catalogOverlayEnabledProvider.notifier)
                .state = !catalogEnabled,
          ),
          _overlayItem(
            value: 5,
            icon: NightshadeIcons.science,
            label: 'Science HUD',
            active: scienceHudVisible,
            onTap: () => ref.read(scienceModeStateProvider.notifier).state =
                scienceMode.copyWith(
              scienceHudVisible: !scienceHudVisible,
            ),
          ),
        ];
      },
      child: _LabeledToolbarToggle(
        colors: colors,
        icon: NightshadeIcons.layers,
        label: 'Overlays',
        // Tooltip is provided by PopupMenuButton itself; the pill is purely
        // visual here so the popup owns the tap.
        tooltip: null,
        active: anyOverlayActive,
        showChevron: true,
        onTap: null,
      ),
    );
  }

  PopupMenuItem<int> _overlayItem({
    required int value,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return PopupMenuItem<int>(
      value: value,
      // The list/catalog/grid rows also have their own deeper config elsewhere;
      // here a tap simply flips/cycles the same provider the old icon did.
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: 2,
      ),
      child: _OverlayMenuRow(
        colors: colors,
        icon: icon,
        label: label,
        subtitle: subtitle,
        active: active,
      ),
    );
  }
}

/// A labelled pill toggle used for the toolbar's named controls (Overlays,
/// Annotate). Mirrors the [OverlayIconButton] active/hover treatment so it sits
/// visually with the view controls, but carries a text label so the control's
/// purpose is legible at a glance instead of a cryptic glyph.
///
/// When [onTap] is null the pill is purely presentational (e.g. the trigger
/// child of a [PopupMenuButton], which owns the gesture); otherwise it behaves
/// as a tappable button. [showChevron] adds a trailing caret for popovers.
class _LabeledToolbarToggle extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool active;
  final bool showChevron;
  final VoidCallback? onTap;

  const _LabeledToolbarToggle({
    required this.colors,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.active,
    this.showChevron = false,
    this.onTap,
  });

  @override
  State<_LabeledToolbarToggle> createState() => _LabeledToolbarToggleState();
}

class _LabeledToolbarToggleState extends State<_LabeledToolbarToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final accent = widget.active ? colors.primary : colors.textSecondary;

    final pill = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: NightshadeTokens.durationQuick,
        height: 32,
        padding:
            const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceSm),
        decoration: BoxDecoration(
          color: widget.active
              ? colors.primary.withValues(alpha: 0.16)
              : _hovered
                  ? colors.surfaceHover
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(
            color: widget.active
                ? colors.primary.withValues(alpha: 0.45)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 15, color: accent),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              widget.label,
              style: NightshadeTypography.labelSm.copyWith(color: accent),
            ),
            if (widget.showChevron) ...[
              const SizedBox(width: 2),
              Icon(NightshadeIcons.chevronDown,
                  size: 13, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );

    final tappable = widget.onTap == null
        ? pill
        : GestureDetector(onTap: widget.onTap, child: pill);

    final tooltip = widget.tooltip;
    if (tooltip == null) return tappable;
    return NightshadeTooltip(
      message: tooltip,
      position: NightshadeTooltipPosition.bottom,
      child: tappable,
    );
  }
}

/// A single labelled checkbox row inside the Overlays popover.
class _OverlayMenuRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool active;

  const _OverlayMenuRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // Check box — communicates on/off without button chrome.
          Icon(
            active ? LucideIcons.checkSquare : LucideIcons.square,
            size: 16,
            color: active ? colors.primary : colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Icon(
            icon,
            size: 15,
            color: active ? colors.primary : colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              label,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              subtitle!,
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The trailing view-controls group: zoom in/out, 1:1, fit-to-window, and
/// (only while a capture is mid-flight) an abort button. Kept as one tight,
/// visually distinct cluster on the bar's trailing edge. The catalog-overlay
/// settings popover button rides along here too, since its dropdown still
/// configures the catalog overlay toggled from the Overlays menu.
class _ViewControlsGroup extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoom1to1;
  final VoidCallback onFitToWindow;
  final VoidCallback onAbortCapture;
  final bool showAbort;

  const _ViewControlsGroup({
    required this.colors,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoom1to1,
    required this.onFitToWindow,
    required this.onAbortCapture,
    required this.showAbort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ImagingTutorialKeys.zoomControls,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Catalog overlay magnitude/kind settings popover. The overlay's
        // on/off lives in the Overlays menu; this caret keeps its deeper
        // configuration (magnitude limit, object kinds) reachable next to the
        // view controls without re-introducing a second on/off toggle.
        _CatalogOverlaySettingsButton(colors: colors),
        OverlayIconButton(
          icon: LucideIcons.zoomIn,
          tooltip: 'Zoom in',
          colors: colors,
          onTap: onZoomIn,
        ),
        OverlayIconButton(
          icon: LucideIcons.zoomOut,
          tooltip: 'Zoom out',
          colors: colors,
          onTap: onZoomOut,
        ),
        OverlayIconButton(
          icon: NightshadeIcons.collapse,
          tooltip: '1:1 zoom',
          colors: colors,
          onTap: onZoom1to1,
        ),
        OverlayIconButton(
          icon: LucideIcons.maximize,
          tooltip: 'Fit to window',
          colors: colors,
          onTap: onFitToWindow,
        ),
        if (showAbort)
          OverlayIconButton(
            key: ImagingTutorialKeys.abortBtn,
            icon: NightshadeIcons.close,
            tooltip: 'Abort capture',
            colors: colors,
            onTap: onAbortCapture,
          ),
      ],
    );
  }
}

/// Settings-only catalog-overlay control: a caret that opens the catalog
/// magnitude/kind popover. The overlay's on/off now lives in the Overlays
/// menu, so unlike the old combined toggle+caret button this exposes *only*
/// the deeper configuration and never duplicates the enable toggle.
class _CatalogOverlaySettingsButton extends ConsumerWidget {
  final NightshadeColors colors;

  const _CatalogOverlaySettingsButton({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final magnitudeLimit = ref.watch(catalogOverlayMagnitudeLimitProvider);
    return PopupMenuButton<String>(
      tooltip: 'Catalog overlay settings [Mag ≤ '
          '${magnitudeLimit.toStringAsFixed(0)}]',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      onSelected: (_) {},
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 0,
          child: CatalogOverlayPopover(colors: colors),
        ),
      ],
      icon: Icon(NightshadeIcons.target, color: colors.textMuted, size: 16),
      splashRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceXs),
    );
  }
}
