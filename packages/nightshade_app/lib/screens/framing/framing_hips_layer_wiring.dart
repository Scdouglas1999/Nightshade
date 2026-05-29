// Component C8b — framing-screen wiring for the Flutter-side GPU HiPS tile layer.
//
// This is the single, self-contained widget the framing screen composes into its
// `Expanded > Stack` (next to `FramingCanvas`) so the C8 [HipsTileLayer] and its
// [HipsAttributionBadge] appear at the right z-order, gated by the C7
// [hipsFramingActiveProvider] (the user toggle [hipsFramingEnabledProvider]
// combined with the survey's HiPS capability gate). It owns no rendering, no
// fetching and no geometry of its own: it is pure composition, layering the
// already-built C8 widgets and the survey-attribution credit over the framing
// imagery band.
//
// ## Where it sits in the framing render path (z-order)
//
// The framing imagery is composited by the framing render path's own widgets —
// the opaque [FramingCanvas] (survey-snapshot painter / starfield fallback *and*
// the grid / FOV / mosaic overlays, all in one internal `Stack`). The HiPS tile
// layer is a Flutter-side, GPU-composited imagery layer that streams a deep,
// zoomable tile mosaic registered to the SAME [FramingPlateScale] the canvas and
// its overlays use, so it co-registers to the pixel at every zoom.
//
// This wiring stacks the HiPS tile layer directly OVER the framing canvas: the
// canvas is the outermost never-blank fallback (its single survey snapshot or
// starfield shows through wherever the tile mosaic has no imagery yet — the C8
// painter draws nothing outside the resident tile footprint and stays
// transparent until imagery is resident), and the streamed HiPS mosaic is the
// sharp imagery on top. The tile layer is wrapped in [IgnorePointer] inside C8,
// so pan / rotate gestures fall straight through to the canvas beneath; this
// wiring adds its own [IgnorePointer] guarantee around the imagery + badge so the
// composed group never intercepts a gesture meant for the canvas.
//
// ## Platform independence (hard requirement)
//
// Nothing here reads the planetarium `RenderingPlatform` or touches the
// planetarium renderer (v1 CustomPainter or experimental v2 wgpu). The framing
// background is its own Flutter render path; the HiPS tiles are a Flutter-side
// GPU layer inside it, so HiPS framing works for every user regardless of the
// rendering-platform setting.
//
// ## Attribution (a licence requirement, not chrome)
//
// CDS and the survey publishers require the survey's `obs_copyright` credit to be
// displayed whenever its imagery is shown. This wiring resolves the survey's HiPS
// `properties` once per survey (via [framingHipsPropertiesProvider], built on the
// shared C5 fetcher so no extra network client is created) and renders the C8
// [HipsAttributionBadge] only while the HiPS layer is active AND actually showing
// imagery. A properties-fetch failure is surfaced (logged + the future carries
// the error) and the badge simply renders nothing — the imagery already falls
// back to the canvas snapshot, so there is never a silent blank.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'widgets/hips_attribution_badge.dart';
import 'widgets/hips_tile_layer.dart';

// The survey `properties` document is resolved by the single shared
// [framingHipsPropertiesProvider] in nightshade_core (the C7 provider surface,
// exported via the barrel above), so the tile layer/loader and this attribution
// badge consume ONE fetch / one cache / one error surface per survey rather than
// fetching the identical immutable document twice over divergent code paths.

/// Composes the C8 HiPS tile layer + attribution badge over the framing imagery
/// band, gated by the C7 active-for-survey decision.
///
/// Drop this into the framing screen's `Expanded > Stack` as a [Positioned.fill]
/// directly above the [FramingCanvas]: the canvas is the never-blank fallback
/// underneath, and this layer streams the sharp HiPS mosaic on top, with the
/// survey attribution credit in the canvas's quiet bottom-left chrome band.
///
/// When the layer is inactive for the current survey (feature off, or the survey
/// has no verified HiPS pyramid) this renders a zero-cost transparent box, so the
/// framing canvas's existing single survey snapshot / starfield is the only
/// background — exactly the pre-HiPS behaviour, untouched.
class FramingHipsLayerWiring extends ConsumerWidget {
  const FramingHipsLayerWiring({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surveySource =
        ref.watch(framingProvider.select((s) => s.surveySource));
    final active = ref.watch(hipsFramingActiveProvider(surveySource));

    // Inactive for this survey: contribute nothing. The framing canvas's single
    // survey snapshot / starfield remains the visible background unchanged.
    if (!active) {
      return const SizedBox.shrink();
    }

    // Active: the HiPS layer streams imagery once it is resident. The badge is
    // shown only while imagery is actually on screen (the licence requirement),
    // so it reads the resident snapshot's `hasAnyImagery`.
    final hasImagery = ref.watch(
      hipsResidentTilesProvider.select((snapshot) => snapshot.hasAnyImagery),
    );
    final propertiesAsync =
        ref.watch(framingHipsPropertiesProvider(surveySource));

    // The group is NOT wrapped in a blanket IgnorePointer: the C8 tile layer
    // ignores pointers itself (pan / rotate fall through to the framing canvas
    // beneath), while the attribution badge must stay tappable to open the
    // survey's copyright page. Wrapping the whole group would swallow that tap.
    return Stack(
      children: [
        // The streamed HiPS tile mosaic, registered to the shared
        // FramingPlateScale so it co-registers with the canvas overlays. C8
        // measures its own canvas, resolves the shared plate scale, drives the
        // loader and paints the resident snapshot; it stays transparent until
        // imagery is resident, so the canvas snapshot shows through underneath.
        const Positioned.fill(child: HipsTileLayer()),

        // Survey attribution credit, in the framing canvas's quiet bottom chrome
        // band, centred so it never collides with the canvas's bottom-left scale
        // indicator or bottom-right zoom controls. Shown only while HiPS imagery
        // is actually visible and the survey published a credit; otherwise the
        // badge renders nothing.
        Positioned(
          left: 0,
          right: 0,
          bottom: NightshadeTokens.spaceMd,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: HipsAttributionBadge(
              properties: propertiesAsync.valueOrNull,
              visible: hasImagery,
            ),
          ),
        ),
      ],
    );
  }
}
