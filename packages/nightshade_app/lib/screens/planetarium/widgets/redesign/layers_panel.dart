import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Unified layers panel — the single source of truth for sky visibility.
///
/// Replaces the scattered toggles that used to live in the left rail,
/// FilterSidebar, top-overlay cluster and mobile filter sheet. Every row uses
/// one consistent switch idiom ([_LayerSwitch]) and writes through
/// [skyRenderConfigProvider] / the relevant [StateProvider]. Current values are
/// read from [effectiveSkyRenderConfigProvider] and the HUD providers.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({super.key, this.onClose, this.showFov, this.onToggleFov});

  /// Optional close affordance (shown as a header X on phone bottom sheets).
  final VoidCallback? onClose;

  /// FOV-indicator state + toggle (lives in screen state, not render config).
  final bool? showFov;
  final VoidCallback? onToggleFov;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final config = ref.watch(effectiveSkyRenderConfigProvider);
    final notifier = ref.read(skyRenderConfigProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(colors: colors, onClose: onClose),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _Group(
                title: 'Stars & Deep Sky',
                colors: colors,
                children: [
                  _LayerSwitch(
                    label: 'Stars',
                    value: config.showStars,
                    onChanged: (_) => notifier.toggleStars(),
                  ),
                  _LayerSwitch(
                    label: 'Deep stars (Tycho-2 / Gaia tier)',
                    value: ref.watch(showDeepStarsProvider),
                    onChanged: (v) =>
                        ref.read(showDeepStarsProvider.notifier).state = v,
                  ),
                  _LayerSwitch(
                    label: 'Deep-sky objects',
                    value: config.showDSOs,
                    onChanged: (_) => notifier.toggleDSOs(),
                  ),
                  _LayerSwitch(
                    label: 'DSO labels',
                    value: config.showDSOLabels,
                    onChanged: (_) => notifier.toggleDsoLabels(),
                  ),
                  _LayerSwitch(
                    label: 'Constellation lines',
                    value: config.showConstellationLines,
                    onChanged: (_) => notifier.toggleConstellationLines(),
                  ),
                  _LayerSwitch(
                    label: 'Constellation labels',
                    value: config.showConstellationLabels,
                    onChanged: (_) => notifier.toggleConstellationLabels(),
                  ),
                  _LayerSwitch(
                    label: 'Constellation boundaries',
                    value: config.showConstellationBoundaries,
                    onChanged: (_) => notifier.toggleConstellationBoundaries(),
                  ),
                  _LayerSwitch(
                    label: 'Constellation art',
                    value: config.showConstellationArt,
                    onChanged: (_) => notifier.toggleConstellationArt(),
                  ),
                  _LayerSwitch(
                    label: 'Milky Way',
                    value: config.showMilkyWay,
                    onChanged: (_) => notifier.toggleMilkyWay(),
                  ),
                  _LayerSwitch(
                    label: 'Variable stars',
                    value: ref.watch(showVariableStarsProvider),
                    onChanged: (v) {
                      ref.read(showVariableStarsProvider.notifier).state = v;
                      notifier.toggleVariableStars();
                    },
                  ),
                ],
              ),
              _Group(
                title: 'Grids & Lines',
                colors: colors,
                children: [
                  _LayerSwitch(
                    label: 'Equatorial grid',
                    value: config.showEquatorialGrid,
                    onChanged: (_) => notifier.toggleEquatorialGrid(),
                  ),
                  _LayerSwitch(
                    label: 'Alt/Az grid',
                    value: config.showAltAzGrid,
                    onChanged: (_) => notifier.toggleAltAzGrid(),
                  ),
                  _LayerSwitch(
                    label: 'Coordinate grid',
                    value: config.showCoordinateGrid,
                    onChanged: (_) => notifier.toggleGrid(),
                  ),
                  _LayerSwitch(
                    label: 'Ecliptic',
                    value: config.showEcliptic,
                    onChanged: (_) => notifier.toggleEcliptic(),
                  ),
                  _LayerSwitch(
                    label: 'Galactic plane',
                    value: config.showGalacticPlane,
                    onChanged: (_) => notifier.toggleGalacticPlane(),
                  ),
                  _LayerSwitch(
                    label: 'Meridian',
                    value: config.showMeridian,
                    onChanged: (_) => notifier.toggleMeridian(),
                  ),
                  _LayerSwitch(
                    label: 'Cardinal directions',
                    value: config.showCardinalDirections,
                    onChanged: (_) => notifier.toggleCardinalDirections(),
                  ),
                ],
              ),
              _Group(
                title: 'Solar System',
                colors: colors,
                children: [
                  _LayerSwitch(
                    label: 'Sun',
                    value: config.showSun,
                    onChanged: (_) => notifier.toggleSun(),
                  ),
                  _LayerSwitch(
                    label: 'Moon',
                    value: config.showMoon,
                    onChanged: (_) => notifier.toggleMoon(),
                  ),
                  _LayerSwitch(
                    label: 'Planets',
                    value: config.showPlanets,
                    onChanged: (_) => notifier.togglePlanets(),
                  ),
                  _LayerSwitch(
                    label: 'Satellites',
                    value: ref.watch(showSatellitesProvider),
                    onChanged: (v) {
                      ref.read(showSatellitesProvider.notifier).state = v;
                      notifier.toggleSatellites();
                    },
                  ),
                  _LayerSwitch(
                    label: 'Minor planets / comets',
                    value: ref.watch(showMinorPlanetsProvider),
                    onChanged: (v) {
                      ref.read(showMinorPlanetsProvider.notifier).state = v;
                      notifier.toggleMinorPlanets();
                    },
                  ),
                ],
              ),
              _Group(
                title: 'Ground & Site',
                colors: colors,
                children: [
                  _LayerSwitch(
                    label: 'Horizon',
                    value: config.showHorizon,
                    onChanged: (_) => notifier.toggleHorizon(),
                  ),
                  _LayerSwitch(
                    label: 'Ground plane',
                    value: ref.watch(showGroundPlaneProvider),
                    onChanged: (v) =>
                        ref.read(showGroundPlaneProvider.notifier).state = v,
                  ),
                ],
              ),
              _Group(
                title: 'Planning',
                colors: colors,
                children: [
                  _LayerSwitch(
                    label: 'Planning overlays',
                    value: config.showPlanningOverlays,
                    onChanged: (_) => notifier.togglePlanningOverlays(),
                  ),
                  if (showFov != null && onToggleFov != null)
                    _LayerSwitch(
                      label: 'FOV indicator',
                      value: showFov!,
                      onChanged: (_) => onToggleFov!(),
                    ),
                  _LayerSwitch(
                    label: 'FOV rings (Telrad / finder)',
                    value: ref.watch(showFovRingsProvider),
                    onChanged: (v) =>
                        ref.read(showFovRingsProvider.notifier).state = v,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.colors, this.onClose});

  final NightshadeColors colors;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.list, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Layers',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: Icon(NightshadeIcons.close,
                  size: 18, color: colors.textSecondary),
              onPressed: onClose,
              tooltip: 'Close',
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    required this.colors,
  });

  final String title;
  final List<Widget> children;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// One consistent switch row idiom for every layer toggle.
class _LayerSwitch extends StatelessWidget {
  const _LayerSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: value ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}
