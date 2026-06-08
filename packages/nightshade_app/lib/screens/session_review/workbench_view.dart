import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

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
    final previewPath = outcome?.result.previewPath;

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
          onApply: (palette, weights) =>
              controller.runNarrowband(palette, weights),
        ),
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
