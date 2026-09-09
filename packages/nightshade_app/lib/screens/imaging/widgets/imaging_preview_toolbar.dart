import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/catalog_overlay_widget.dart'
    show CatalogOverlayPopover;
import '../../../widgets/tutorial_keys/imaging_keys.dart';
import 'annotation_panel.dart' show annotationPanelVisibleProvider;
import 'custom_annotation_drawing.dart'
    show customAnnotationDrawModeActiveProvider, toggleAnnotationDrawPalette;
import 'live_preview_area.dart' show previewReadoutsVisibleProvider;
import 'preview_display_scale.dart' show previewDisplayScaleProvider;

/// The 44 px viewer toolbar above the canvas (06 §Imaging).
///
/// Left: the frame's mono meta line — size, binning, zoom and sky brightness,
/// values loud and their labels quiet. Right: one [NightshadeToolbar] with the
/// named actions first (Overlays, Annotate) and the view glyphs after it.
///
/// Nothing here floats over the image. The canvas below runs edge to edge and
/// carries only glass.
class ImagingPreviewToolbar extends ConsumerStatefulWidget {
  const ImagingPreviewToolbar({
    super.key,
    required this.showCrosshair,
    required this.showStarOverlay,
    required this.isStoppingCapture,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToWindow,
    required this.onZoom1to1,
    required this.onAbortCapture,
    required this.onToggleCrosshair,
    required this.onToggleStarOverlay,
    this.onFullscreen,
  });

  final bool showCrosshair;
  final bool showStarOverlay;

  /// A manual capture abort is already in flight, so the abort control has
  /// nothing left to do — pressing it again would only re-issue a cancel for an
  /// exposure the app has already given up on.
  final bool isStoppingCapture;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToWindow;
  final VoidCallback onZoom1to1;
  final VoidCallback onAbortCapture;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleStarOverlay;

  /// Opens the frame in the fullscreen viewer. Null when there is no frame.
  final VoidCallback? onFullscreen;

  /// The bar's height (06 §Imaging: "A 44 px viewer toolbar on top").
  static const double height = 44;

  @override
  ConsumerState<ImagingPreviewToolbar> createState() =>
      _ImagingPreviewToolbarState();
}

class _ImagingPreviewToolbarState extends ConsumerState<ImagingPreviewToolbar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final currentImage = ref.watch(currentImageProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final scienceSnapshot = ref.watch(currentScienceSnapshotProvider);
    final latestTransparency = scienceSnapshot.$2;
    final showAbort = !widget.isStoppingCapture &&
        exposureProgress.remaining > 0 &&
        !exposureProgress.isDownloading;

    final meta = _ViewerMeta(
      // Null renders "—", never "--- × ---" (02 rule 3).
      resolution: currentImage == null
          ? null
          : '${currentImage.width} × ${currentImage.height}',
      binning: exposureSettings.binning,
      // Screen px per image px, as measured by the preview itself. The viewer
      // state's zoom is a fit-relative multiplier, so printing it as a
      // percentage labelled a 4144 px frame letterboxed into ~990 px "100%".
      zoom: '${(ref.watch(previewDisplayScaleProvider) * 100).round()}%',
      sky: latestTransparency?.qualityBucket,
    );

    // No `overflow:` group. NightshadeToolbar's overflow fit lays out BOTH
    // candidate bars and paints one, so every labelled action appears twice in
    // the widget and semantics trees — two "Overlays" buttons to a screen
    // reader. This bar scrolls instead (below), which puts one node per
    // control on screen at every width.
    //
    // Deviation from `mockups/imaging.html`, recorded in notes.md: the mockup
    // draws five view glyphs; Nightshade also has 1:1 zoom and the catalog
    // overlay's magnitude settings, which exist today and have nowhere else to
    // live, so they ride in the same groups rather than being deleted.
    final toolbar = NightshadeToolbar(
      groups: <List<Widget>>[
        <Widget>[
          OverlaysMenuButton(
            showCrosshair: widget.showCrosshair,
            showStarOverlay: widget.showStarOverlay,
            onToggleCrosshair: widget.onToggleCrosshair,
            onToggleStarOverlay: widget.onToggleStarOverlay,
          ),
          _AnnotateButton(enabled: currentImage != null),
        ],
        <Widget>[
          NightshadeIconButton(
            icon: NightshadeIcons.crosshair,
            tooltip: 'Crosshair',
            size: IconButtonSize.sm,
            selected: widget.showCrosshair,
            onPressed: widget.onToggleCrosshair,
          ),
          NightshadeIconButton(
            icon: LucideIcons.zoomIn,
            tooltip: 'Zoom in',
            size: IconButtonSize.sm,
            onPressed: widget.onZoomIn,
          ),
          NightshadeIconButton(
            icon: LucideIcons.zoomOut,
            tooltip: 'Zoom out',
            size: IconButtonSize.sm,
            onPressed: widget.onZoomOut,
          ),
          NightshadeIconButton(
            icon: NightshadeIcons.collapse,
            tooltip: '1:1 zoom',
            size: IconButtonSize.sm,
            onPressed: widget.onZoom1to1,
          ),
          NightshadeIconButton(
            icon: LucideIcons.scan,
            tooltip: 'Fit to window',
            size: IconButtonSize.sm,
            onPressed: widget.onFitToWindow,
          ),
          NightshadeIconButton(
            icon: LucideIcons.maximize,
            tooltip: 'Fullscreen',
            size: IconButtonSize.sm,
            onPressed: widget.onFullscreen,
          ),
        ],
        <Widget>[
          const _CatalogOverlaySettingsButton(),
          if (showAbort)
            NightshadeIconButton(
              key: ImagingTutorialKeys.abortBtn,
              icon: NightshadeIcons.close,
              tooltip: 'Abort capture',
              size: IconButtonSize.sm,
              color: colors.error,
              onPressed: widget.onAbortCapture,
            ),
        ],
      ],
    );

    return Container(
      height: ImagingPreviewToolbar.height,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
      ),
      // ONE layout, and no width threshold — because no constant can be right
      // here. Every child except the meta line is intrinsically sized, so
      // whether they fit depends on runtime content: the frame's dimensions,
      // the sky reading, the locale, the user's text scale. IntrinsicWidth
      // asks the layout what it actually needs; ConstrainedBox(minWidth)
      // lets the bar fill the viewport when there IS slack so the actions stay
      // pinned trailing; and when the natural width exceeds the viewport it
      // scrolls. Nothing is ever clipped, at any width.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: IntrinsicWidth(
                child: Row(
                  key: ImagingTutorialKeys.zoomControls,
                  children: <Widget>[
                    meta,
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    const Spacer(),
                    toolbar,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `6248 × 4176 · Bin 1×1 · Zoom 55% · Sky 19.8 mag/″²` — mono 12, values in
/// `textPrimary`, their qualifiers in `textSecondary`, 14 px apart.
class _ViewerMeta extends StatelessWidget {
  const _ViewerMeta({
    required this.resolution,
    required this.binning,
    required this.zoom,
    required this.sky,
  });

  final String? resolution;
  final String binning;
  final String zoom;
  final String? sky;

  /// Gap between the segments (`observatory.css` `.vtool .meta`).
  static const double segmentGap = 14;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final label = NightshadeTypography.monoCaption.copyWith(
      color: colors.textSecondary,
    );
    final value = NightshadeTypography.monoCaption.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w500,
    );
    final muted = NightshadeTypography.monoCaption.copyWith(
      color: colors.textMuted,
    );

    // Plain `Text` per part rather than one `Text.rich`: a rich span carries no
    // `data`, so the zoom readout — the one thing on this bar a test and a
    // screen reader both go looking for by its value — became unfindable.
    Widget segment(String? prefix, String? text, [String? suffix]) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (prefix != null) ...<Widget>[
            Text(prefix, style: label, maxLines: 1, softWrap: false),
            const SizedBox(width: NightshadeTokens.spaceXs),
          ],
          Text(
            text ?? '\u2014',
            style: text == null ? muted : value,
            maxLines: 1,
            softWrap: false,
          ),
          if (suffix != null) ...<Widget>[
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(suffix, style: label, maxLines: 1, softWrap: false),
          ],
        ],
      );
    }

    // A segment whose value is unknown says "Sky —", never "Sky — mag/″²":
    // a unit on a value that does not exist describes nothing. The frame size
    // and the zoom drop out entirely with no frame on the canvas, because an
    // em dash is worth a slot only when the slot is permanent.
    final parts = <Widget>[
      if (resolution != null) segment(null, resolution),
      segment('Bin', binning),
      if (resolution != null) segment('Zoom', zoom),
      segment('Sky', sky, sky == null ? null : 'mag/″²'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < parts.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: segmentGap),
          parts[i],
        ],
      ],
    );
  }
}

/// The "Annotate" toggle. Flips [customAnnotationDrawModeActiveProvider] via
/// [toggleAnnotationDrawPalette] so the docked drawing palette appears at the
/// bottom of the canvas only while drawing is active.
class _AnnotateButton extends ConsumerWidget {
  const _AnnotateButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(customAnnotationDrawModeActiveProvider);
    // A ghost button has no on-state in the sheet, so the toggle publishes it
    // as semantics; on screen the docked drawing palette IS the on-state.
    return Semantics(
      toggled: active,
      child: NightshadeButton(
        label: 'Annotate',
        icon: NightshadeIcons.tag,
        size: ButtonSize.small,
        variant: ButtonVariant.ghost,
        semanticsHint: enabled ? null : 'Available once a frame is on screen',
        onPressed: enabled ? () => toggleAnnotationDrawPalette(ref) : null,
      ),
    );
  }
}

/// The single labelled "Overlays" entry point. Tapping opens a compact popover
/// of labelled checkbox rows, one per overlay.
class OverlaysMenuButton extends ConsumerWidget {
  const OverlaysMenuButton({
    super.key,
    required this.showCrosshair,
    required this.showStarOverlay,
    required this.onToggleCrosshair,
    required this.onToggleStarOverlay,
  });

  final bool showCrosshair;
  final bool showStarOverlay;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleStarOverlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull;
    final gridType = annotationSettings?.gridType ?? GridType.none;
    final annotationPanelVisible = ref.watch(annotationPanelVisibleProvider);
    final catalogEnabled = ref.watch(catalogOverlayEnabledProvider);
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceHudVisible = scienceMode.scienceHudVisible;
    final readoutsVisible = ref.watch(previewReadoutsVisibleProvider);

    // Undeclared, this publishes as `panel: Overlays [DISABLED]` — a live popup
    // trigger announced as an inert panel — because PopupMenuButton's InkWell
    // contributes a tap action but no button role or enabled state, and the
    // label inside contributes a second, separate named node. One control, one
    // node, with the role and the state it actually has.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: true,
        label: 'Overlays',
        child: PopupMenuButton<int>(
          tooltip: 'Overlays',
          position: PopupMenuPosition.under,
          offset: const Offset(0, NightshadeTokens.spaceXs),
          color: colors.surfaceElevated,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          constraints: const BoxConstraints(minWidth: 248, maxWidth: 296),
          shape: RoundedRectangleBorder(
            borderRadius: NightshadeTokens.borderRadiusXl,
            side: BorderSide(color: colors.border),
          ),
          itemBuilder: (BuildContext context) {
            return <PopupMenuEntry<int>>[
              _overlayItem(
                colors: colors,
                value: 0,
                icon: NightshadeIcons.crosshair,
                label: 'Crosshair',
                active: showCrosshair,
                onTap: onToggleCrosshair,
              ),
              _overlayItem(
                colors: colors,
                value: 1,
                icon: gridType == GridType.celestial
                    ? NightshadeIcons.globe
                    : NightshadeIcons.grid,
                label: 'Grid',
                subtitle: switch (gridType) {
                  GridType.none =>
                    annotationSettings == null ? 'Settings unavailable' : 'Off',
                  GridType.pixel => 'Pixel',
                  GridType.celestial => 'RA / Dec',
                },
                active: gridType != GridType.none,
                onTap: annotationSettings == null
                    ? null
                    : () => ref
                        .read(annotationSettingsProvider.notifier)
                        .cycleGridType(),
              ),
              _overlayItem(
                colors: colors,
                value: 2,
                icon: NightshadeIcons.sparkle,
                label: 'Star detection',
                active: showStarOverlay,
                onTap: onToggleStarOverlay,
              ),
              _overlayItem(
                colors: colors,
                value: 3,
                icon: NightshadeIcons.list,
                label: 'Object annotations',
                active: annotationPanelVisible,
                onTap: () => ref
                    .read(annotationPanelVisibleProvider.notifier)
                    .state = !annotationPanelVisible,
              ),
              _overlayItem(
                colors: colors,
                value: 4,
                icon: NightshadeIcons.target,
                label: 'Catalog overlay',
                active: catalogEnabled,
                onTap: () => ref
                    .read(catalogOverlayEnabledProvider.notifier)
                    .state = !catalogEnabled,
              ),
              _overlayItem(
                colors: colors,
                value: 5,
                icon: NightshadeIcons.science,
                label: 'Science HUD',
                active: scienceHudVisible,
                onTap: () => ref.read(scienceModeStateProvider.notifier).state =
                    scienceMode.copyWith(
                  scienceHudVisible: !scienceHudVisible,
                ),
              ),
              // The measurement readouts are explicit and default ON — nothing
              // on the canvas hides itself on a timer. This row is how the
              // clean-frame view is asked for.
              _overlayItem(
                colors: colors,
                value: 6,
                icon: NightshadeIcons.activity,
                label: 'Readouts',
                subtitle: 'Histogram, HFR / stars, image stats',
                active: readoutsVisible,
                onTap: () => ref
                    .read(previewReadoutsVisibleProvider.notifier)
                    .state = !readoutsVisible,
              ),
            ];
          },
          // Excluded so the label does not publish a SECOND "Overlays" node
          // beside the one the wrapper above owns; PopupMenuButton's tap sits
          // above this, so the action is unaffected.
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: NightshadeButton(
                label: 'Overlays',
                icon: NightshadeIcons.layers,
                size: ButtonSize.small,
                variant: ButtonVariant.ghost,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<int> _overlayItem({
    required NightshadeColors colors,
    required int value,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    return PopupMenuItem<int>(
      value: value,
      enabled: onTap != null,
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

/// A single labelled checkbox row inside the Overlays popover.
class _OverlayMenuRow extends StatelessWidget {
  const _OverlayMenuRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.active,
  });

  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // The description stacks UNDER the label rather than sitting beside it.
    // Side by side, the description took its full intrinsic width first and
    // left the label a sliver, so "Readouts" rendered as "Rea" / "dou" broken
    // across two lines.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: <Widget>[
          // Check box — communicates on/off without button chrome.
          Icon(
            active ? LucideIcons.checkSquare : LucideIcons.square,
            size: NightshadeTokens.iconSm,
            color: active ? colors.primary : colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Icon(
            icon,
            size: SectionTitle.iconSize,
            color: active ? colors.primary : colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings-only catalog-overlay control: a glyph that opens the catalog
/// magnitude / kind popover. The overlay's on/off lives in the Overlays menu,
/// so this exposes *only* the deeper configuration.
class _CatalogOverlaySettingsButton extends ConsumerWidget {
  const _CatalogOverlaySettingsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final magnitudeLimit = ref.watch(catalogOverlayMagnitudeLimitProvider);
    return PopupMenuButton<String>(
      tooltip: 'Catalog overlay settings, magnitude '
          '${magnitudeLimit.toStringAsFixed(0)} and brighter',
      position: PopupMenuPosition.under,
      offset: const Offset(0, NightshadeTokens.spaceXs),
      color: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: NightshadeTokens.borderRadiusXl,
        side: BorderSide(color: colors.border),
      ),
      onSelected: (_) {},
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 0,
          child: CatalogOverlayPopover(colors: colors),
        ),
      ],
      icon: Icon(
        NightshadeIcons.target,
        color: colors.textMuted,
        size: NightshadeTokens.iconSm,
      ),
      splashRadius: NightshadeTokens.iconSm,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: NightshadeTokens.iconButtonSizeSm,
        height: NightshadeTokens.iconButtonSizeSm,
      ),
    );
  }
}
