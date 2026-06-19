// Part of ../planner_screen.dart -- extracted for maintainability.
//
// "Sky" tab: a segmented Framing|Planetarium toggle hosting the framing and planetarium views absorbed from the standalone /framing and /planetarium screens.
part of '../planner_screen.dart';

/// Which view the "Sky" tab's inner segmented control shows.
enum SkyView { framing, planetarium }

/// Maps a router `?view=` query value to a [SkyView]. Returns null for an
/// unrecognised value so the caller can fall back to [SkyView.framing]. Public
/// so the `/framing` and `/planetarium` redirects (and tests) share the same
/// mapping.
SkyView? plannerSkyViewFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'framing':
      return SkyView.framing;
    case 'planetarium':
      return SkyView.planetarium;
  }
  return null;
}

class _SkyTab extends ConsumerStatefulWidget {
  const _SkyTab();

  @override
  ConsumerState<_SkyTab> createState() => _SkyTabState();
}

class _SkyTabState extends ConsumerState<_SkyTab> {
  late SkyView _view;
  String? _lastViewQuery;

  @override
  void initState() {
    super.initState();
    _lastViewQuery = _viewQuery();
    _view = plannerSkyViewFromQuery(_lastViewQuery) ?? SkyView.framing;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Sky tab lives in an always-built IndexedStack, so initState ran once
    // at first planner build. When a `/framing` or `/planetarium` deep-link
    // re-enters the already-mounted planner with a new `?view=`, re-apply it
    // here (GoRouterState is an inherited dependency). Guarded on the query
    // changing so a user's manual segment toggle isn't snapped back on rebuild.
    final viewQuery = _viewQuery();
    if (viewQuery != _lastViewQuery) {
      _lastViewQuery = viewQuery;
      final resolved = plannerSkyViewFromQuery(viewQuery);
      if (resolved != null && resolved != _view) {
        setState(() => _view = resolved);
      }
    }
  }

  /// Reads the `?view=` query from the current GoRouter location. Returns null
  /// outside the GoRouter tree (tests mount the screen standalone).
  String? _viewQuery() {
    try {
      return GoRouterState.of(context).uri.queryParameters['view'];
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceLg,
            vertical: NightshadeTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<SkyView>(
              segments: const [
                ButtonSegment(
                  value: SkyView.framing,
                  label: Text('Framing'),
                  icon: Icon(LucideIcons.crop),
                ),
                ButtonSegment(
                  value: SkyView.planetarium,
                  label: Text('Planetarium'),
                  icon: Icon(LucideIcons.globe),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: colors.primary.withValues(alpha: 0.18),
                selectedForegroundColor: colors.primary,
                foregroundColor: colors.textSecondary,
                backgroundColor: colors.surfaceAlt,
                side: BorderSide(color: colors.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
                textStyle:
                    const TextStyle(fontSize: NightshadeTypography.fontSize12),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            children: const [
              FramingView(),
              PlanetariumView(),
            ],
          ),
        ),
      ],
    );
  }
}
