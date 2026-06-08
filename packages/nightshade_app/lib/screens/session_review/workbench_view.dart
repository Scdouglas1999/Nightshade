import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_screen/psf_field_map_view.dart';
import '../sequencer/widgets/run_dashboard/frame_detail_dialog.dart';
import 'session_review_controller.dart';
import 'widgets/ab_compare_panel.dart';
import 'widgets/integration_settings_panel.dart';
import 'widgets/master_overlay_view.dart';
import 'widgets/narrowband_mixer_panel.dart' as nb;
import 'widgets/sub_cull_rail.dart';

/// The *workbench* rendering of the one [SessionReviewController] state: a
/// dense, control-heavy console for the operator who wants to drive every knob.
///
/// Layout (design §1, §2.6): the cull rail (sub table + blink + lasso) on the
/// left; the master with every overlay toggle, the per-sub field-quality maps,
/// the narrowband mixer, an A/B re-integrate compare, and the full
/// integration-settings form on the right.
///
/// Same provider as `NarrativeView` — two renderings of one model. Every panel
/// is composed by its contract constructor signature and is design-system pure.
class WorkbenchView extends ConsumerWidget {
  final SessionReviewScope scope;

  const WorkbenchView({super.key, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionReviewControllerProvider(scope));
    final controller =
        ref.read(sessionReviewControllerProvider(scope).notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= NightshadeTokens.breakpointDesktop;
        final left = _LeftColumn(
          state: state,
          controller: controller,
          onTapSub: (image) => FrameDetailDialog.showForFrame(
            context,
            imageId: image.id,
          ),
          onSetAccepted: controller.setAccepted,
          onBulkCull: ({hfrThreshold, qualityThreshold}) =>
              controller.bulkReject(
            hfrThreshold: hfrThreshold,
            qualityThreshold: qualityThreshold,
          ),
        );
        final right = _RightColumn(
          state: state,
          controller: controller,
        );

        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: NightshadeTokens.spaceLg),
                right,
              ],
            ),
          );
        }

        // Two dense columns side by side on desktop widths.
        return Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(child: left),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(child: right),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Left column: the sub-culling rail (full sub grid + blink + lasso + a
/// "drop to recommended keepN" action wired to the improvement curve).
class _LeftColumn extends StatelessWidget {
  final SessionReviewState state;
  final SessionReviewController controller;
  final void Function(DbCapturedImage) onTapSub;
  final void Function(int imageId, bool accepted) onSetAccepted;
  final void Function({double? hfrThreshold, double? qualityThreshold})
      onBulkCull;

  const _LeftColumn({
    required this.state,
    required this.controller,
    required this.onTapSub,
    required this.onSetAccepted,
    required this.onBulkCull,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionHeader(title: 'Subs & culling'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        // SubCullRail extends the existing sub gallery: blink + bulk-reject
        // plus multi-select / lasso cull and a curve-linked "drop to keepN".
        SizedBox(
          height: 520,
          child: SubCullRail(
            subs: state.lights,
            controller: controller,
            onTapSub: onTapSub,
            onSetAccepted: onSetAccepted,
            onBulkCull: onBulkCull,
          ),
        ),
      ],
    );
  }
}

/// Right column: the master + overlays, the per-sub field-quality maps, the
/// narrowband mixer, the A/B compare, and the integration-settings form.
class _RightColumn extends StatelessWidget {
  final SessionReviewState state;
  final SessionReviewController controller;

  const _RightColumn({
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final outcome = state.lastOutcome;
    final master = state.reviewedMaster;
    // Prefer the freshest run's preview; otherwise the persisted master's.
    final previewPath = outcome?.result.previewPath ?? master?.previewPngPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Master with every overlay toggle. ────────────────────────────
        const SectionHeader(title: 'Master & overlays'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        if (previewPath != null)
          NightshadeCard(
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 480,
              child: MasterOverlayView(
                previewPngPath: previewPath,
                annotations: state.annotationLayer,
                rejectionMapPngPath: outcome?.result.rejectionMapPath,
                showAnnotations: true,
                showRejection: false,
                showCoverage: false,
                finishingLayers: _finishingLayers(master),
              ),
            ),
          )
        else
          NightshadeCard(
            variant: CardVariant.subtle,
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: Row(
              children: [
                Icon(NightshadeIcons.info,
                    size: NightshadeTokens.iconSm, color: colors.info),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    'Integrate to produce a master, then toggle the rejection, '
                    'coverage and annotation overlays here.',
                    style: NightshadeTypography.bodySm
                        .copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NightshadeTokens.spaceMd),

        // ── Finishing actions (non-destructive post-steps on the master). ─
        _FinishingActions(state: state, controller: controller),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // ── Per-sub field quality (PSF map). ─────────────────────────────
        // Reuses the shared PsfFieldMapView painter (extracted from the
        // diagnostics surface) at per-sub granularity, per the design's
        // "Reused: psf_field_map.dart".
        const SectionHeader(title: 'Optical field quality'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        _FieldQualityCard(subs: state.acceptedLights),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // ── Narrowband channel mixer. ────────────────────────────────────
        const SectionHeader(title: 'Narrowband mixer'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        nb.NarrowbandMixerPanel(
          // Bridge the controller's canonical channel refs (which carry the
          // on-disk FITS path the combine consumes) to the mixer's display
          // refs. The combine re-resolves the FITS internally, so onApply only
          // needs to hand back the palette + weight matrix.
          channels: [
            for (final c in controller.narrowbandChannels())
              nb.NarrowbandChannelRef(
                masterId: c.masterId,
                filter: c.label,
                label: c.label,
              ),
          ],
          // Await the combine and surface the persisted composite path rather
          // than discarding it: a failed combine sets `state.error`, a successful
          // one pushes the `narrowband_composites` row onto state, which the
          // `_NarrowbandCompositeCard` below renders.
          onApply: (palette, weights) async {
            await controller.runNarrowband(palette, weights);
          },
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        _NarrowbandCompositeCard(composite: state.narrowbandComposite),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // ── A/B compare two integration recipes. ─────────────────────────
        const SectionHeader(title: 'A / B compare'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        AbComparePanel(controller: controller),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // ── Integration settings + actions. ──────────────────────────────
        const SectionHeader(title: 'Integration settings'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeCard(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: IntegrationSettingsPanel(
            settings: state.settings,
            subCount: state.acceptedCount,
            onChanged: controller.updateSettings,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        NightshadeButton(
          label: state.lastOutcome == null ? 'Integrate now' : 'Re-integrate',
          icon: NightshadeIcons.play,
          isLoading: state.integrating,
          onPressed: (state.integrating || state.acceptedCount == 0)
              ? null
              : () => controller.reIntegrate(state.settings),
        ),
      ],
    );
  }
}

/// The conventional sibling preview PNG for a finishing-artifact FITS at
/// [fitsPath]: the same path with a `.png` extension — what the controller's
/// finishing actions render beside each `_bgx`/`_decon`/`_starred` FITS.
String _siblingPng(String fitsPath) {
  final dir = p.dirname(fitsPath);
  final stem = p.basenameWithoutExtension(fitsPath);
  return p.join(dir, '$stem.png');
}

/// The finishing-result "after" layers for [master] that exist on disk — one
/// per persisted finishing FITS path (background extraction / deconvolution /
/// star reduction), pointing at its sibling preview PNG so [MasterOverlayView]
/// can A/B each pass against the raw master. Empty when no master / no
/// finishing artifacts have been produced.
List<FinishingResultLayer> _finishingLayers(IntegratedMaster? master) {
  if (master == null) return const [];
  bool exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  final out = <FinishingResultLayer>[];
  void add(String? fits, String label, IconData icon) {
    if (fits == null || fits.trim().isEmpty) return;
    final png = _siblingPng(fits);
    if (!exists(png)) return;
    out.add(FinishingResultLayer(label: label, pngPath: png, icon: icon));
  }

  add(master.backgroundExtractedPath, 'Background extract', NightshadeIcons.grid);
  add(master.deconvolvedPath, 'Deconvolve', NightshadeIcons.sparkle);
  add(master.starReducedPath, 'Reduce stars', NightshadeIcons.star);
  add(master.colorCalibratedPath, 'Color calibrate', NightshadeIcons.star);
  return out;
}

/// The non-destructive finishing-action row: "Background extract", "Deconvolve",
/// and "Reduce stars" buttons that run the matching post-step on the current
/// reviewed master's finished FITS (never re-integrating). Each writes its
/// `_bgx`/`_decon`/`_starred` FITS + a sibling preview PNG, persists the path,
/// and the result then surfaces as a toggleable "after" layer in the
/// `MasterOverlayView` hero above. Disabled (with a calm hint) until a finished
/// master exists or while any finishing pass is in flight.
class _FinishingActions extends StatelessWidget {
  final SessionReviewState state;
  final SessionReviewController controller;

  const _FinishingActions({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final master = state.reviewedMaster;
    final hasMaster = master?.masterFitsPath != null &&
        master!.masterFitsPath!.trim().isNotEmpty;
    final busy = state.busy;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.sparkle,
                  size: NightshadeTokens.iconSm, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  'Finishing (non-destructive previews)',
                  style:
                      NightshadeTypography.h5.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          if (!hasMaster)
            Text(
              'Integrate a master first — finishing runs on the finished FITS.',
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            )
          else
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: NightshadeTokens.spaceSm,
              children: [
                NightshadeButton(
                  label: 'Background extract',
                  icon: NightshadeIcons.grid,
                  variant: ButtonVariant.outline,
                  isLoading: state.extractingBackground,
                  onPressed: busy ? null : controller.runBackgroundExtraction,
                ),
                NightshadeButton(
                  label: 'Deconvolve',
                  icon: NightshadeIcons.sparkle,
                  variant: ButtonVariant.outline,
                  isLoading: state.deconvolving,
                  onPressed: busy ? null : controller.runDeconvolve,
                ),
                NightshadeButton(
                  label: 'Reduce stars',
                  icon: NightshadeIcons.star,
                  variant: ButtonVariant.outline,
                  isLoading: state.reducingStars,
                  onPressed: busy ? null : controller.runStarReduction,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The per-sub optical field quality card: a HFR field-map heat-grid for the
/// selected sub, rendered through the shared [PsfFieldMapView] painter (the same
/// painter the Diagnostics surface uses — the design's reuse of
/// `psf_field_map.dart` at per-sub granularity).
///
/// It defaults to the best accepted sub, lets the operator step through subs,
/// and loads each sub's `psf_field_tiles` rows on demand. When a sub has no
/// per-sub tiles yet (not all rigs/pipelines populate them), it shows a calm
/// empty state rather than fabricating a map.
class _FieldQualityCard extends ConsumerStatefulWidget {
  final List<DbCapturedImage> subs;

  const _FieldQualityCard({required this.subs});

  @override
  ConsumerState<_FieldQualityCard> createState() => _FieldQualityCardState();
}

class _FieldQualityCardState extends ConsumerState<_FieldQualityCard> {
  int _index = 0;
  Future<List<PsfFieldTileRow>>? _tilesFuture;

  @override
  void initState() {
    super.initState();
    _index = _initialIndex();
    _loadTiles();
  }

  @override
  void didUpdateWidget(covariant _FieldQualityCard old) {
    super.didUpdateWidget(old);
    if (widget.subs.length != old.subs.length) {
      _index = _index.clamp(0, _maxIndex);
      _loadTiles();
    }
  }

  int get _maxIndex => widget.subs.isEmpty ? 0 : widget.subs.length - 1;

  /// Start on the sharpest accepted sub (lowest HFR) — the field map is most
  /// informative on a good frame.
  int _initialIndex() {
    if (widget.subs.isEmpty) return 0;
    var best = 0;
    var bestHfr = double.infinity;
    for (var i = 0; i < widget.subs.length; i++) {
      final hfr = widget.subs[i].hfr ?? double.infinity;
      if (hfr < bestHfr) {
        bestHfr = hfr;
        best = i;
      }
    }
    return best;
  }

  void _loadTiles() {
    if (widget.subs.isEmpty) {
      _tilesFuture = Future.value(const <PsfFieldTileRow>[]);
      return;
    }
    final id = widget.subs[_index].id;
    _tilesFuture = ref.read(scienceDaoProvider).getPsfTilesForImage(id);
  }

  void _step(int delta) {
    if (widget.subs.isEmpty) return;
    setState(() {
      _index = (_index + delta).clamp(0, _maxIndex);
      _loadTiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final subs = widget.subs;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.grid,
                  size: NightshadeTokens.iconSm, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  'PSF field map',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              if (subs.isNotEmpty) ...[
                IconButton(
                  iconSize: NightshadeTokens.iconSm,
                  visualDensity: VisualDensity.compact,
                  onPressed: _index > 0 ? () => _step(-1) : null,
                  icon: const Icon(NightshadeIcons.chevronLeft),
                  tooltip: 'Previous sub',
                ),
                Text(
                  'sub ${_index + 1} / ${subs.length}',
                  style: NightshadeTypography.labelSm
                      .copyWith(color: colors.textSecondary),
                ),
                IconButton(
                  iconSize: NightshadeTokens.iconSm,
                  visualDensity: VisualDensity.compact,
                  onPressed: _index < _maxIndex ? () => _step(1) : null,
                  icon: const Icon(NightshadeIcons.chevronRight),
                  tooltip: 'Next sub',
                ),
              ],
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          if (subs.isEmpty)
            Text(
              'No accepted subs to map.',
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            )
          else
            FutureBuilder<List<PsfFieldTileRow>>(
              future: _tilesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 180,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final tiles = snapshot.data ?? const <PsfFieldTileRow>[];
                if (tiles.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceMd),
                    child: Text(
                      'No PSF field tiles for this sub yet — capture '
                      'plate-solved frames to populate the per-sub map.',
                      style: NightshadeTypography.bodySm
                          .copyWith(color: colors.textSecondary),
                    ),
                  );
                }
                return AspectRatio(
                  aspectRatio: 1.5,
                  child: PsfFieldMapView(tiles: tiles),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The applied narrowband composite result card.
///
/// Surfaces the persisted `narrowband_composites` row after a palette is applied
/// — the SHO/HOO output is no longer an orphan FITS on disk. It shows the
/// palette, the component master ids the composite was combined from, the output
/// dimensions, and the on-disk path. When a stretched preview PNG sits alongside
/// the composite FITS (same path, `.png` extension) it is rendered through the
/// shared [MasterOverlayView] hero exactly like an integrated master; otherwise a
/// calm "composite written" panel reports the artifact. Renders nothing until a
/// composite exists.
class _NarrowbandCompositeCard extends StatelessWidget {
  final NarrowbandComposite? composite;

  const _NarrowbandCompositeCard({required this.composite});

  /// The conventional sibling preview PNG for a composite FITS at [fitsPath]:
  /// the same path with a `.png` extension. The native combine writes only the
  /// composite FITS today, so this is usually absent — but when a preview is
  /// produced alongside it the hero lights up for free.
  String _siblingPreviewPath(String fitsPath) {
    final dir = p.dirname(fitsPath);
    final stem = p.basenameWithoutExtension(fitsPath);
    return p.join(dir, '$stem.png');
  }

  bool _exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = composite;
    if (c == null) return const SizedBox.shrink();
    final colors = NightshadeColors.of(context);
    final previewPath = _siblingPreviewPath(c.outputPath);
    final hasPreview = _exists(previewPath);

    final components = c.componentMasterIds.isEmpty
        ? '—'
        : c.componentMasterIds.map((id) => '#$id').join(' · ');
    final dims = (c.width > 0 && c.height > 0) ? '${c.width}×${c.height}' : null;

    return NightshadeCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: Row(
              children: [
                Icon(NightshadeIcons.palette,
                    size: NightshadeTokens.iconSm, color: colors.primary),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.palette.toUpperCase()} composite',
                        style: NightshadeTypography.h5
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: NightshadeTokens.spaceXs),
                      Text(
                        'Channels $components'
                        '${dims != null ? '  ·  $dims' : ''}',
                        style: NightshadeTypography.bodySm
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasPreview)
            SizedBox(
              height: 360,
              child: MasterOverlayView(
                previewPngPath: previewPath,
                showAnnotations: false,
                showRejection: false,
                showCoverage: false,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NightshadeTokens.spaceMd,
                0,
                NightshadeTokens.spaceMd,
                NightshadeTokens.spaceMd,
              ),
              child: Row(
                children: [
                  Icon(NightshadeIcons.check,
                      size: NightshadeTokens.iconSm, color: colors.success),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      'Composite written to\n${c.outputPath}',
                      style: NightshadeTypography.bodySm
                          .copyWith(color: colors.textSecondary),
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
