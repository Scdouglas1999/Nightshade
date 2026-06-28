// Part of ../planner_screen.dart -- extracted for maintainability.
//
// "Discover" tab: a segmented Your Sky | Constellation toggle hosting the
// personal all-sky atlas and the community swarm view. These are the
// less-frequent discovery surfaces that used to hold their own rail slots; they
// now nest here, one tap inside Plan Tonight, leaving the rail for nightly tools.
part of '../planner_screen.dart';

/// Which view the "Discover" tab's inner segmented control shows.
enum DiscoverView { yourSky, constellation }

/// Maps a router `?view=` query value to a [DiscoverView]. Returns null for an
/// unrecognised value so the caller can fall back to [DiscoverView.yourSky].
/// Public so the `/your-sky` and `/constellation` redirects (and tests) share
/// the same mapping.
DiscoverView? plannerDiscoverViewFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'yoursky':
    case 'your-sky':
    case 'atlas':
      return DiscoverView.yourSky;
    case 'constellation':
    case 'swarm':
      return DiscoverView.constellation;
  }
  return null;
}

class _DiscoverTab extends ConsumerStatefulWidget {
  const _DiscoverTab();

  @override
  ConsumerState<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<_DiscoverTab> {
  late DiscoverView _view;
  String? _lastViewQuery;

  @override
  void initState() {
    super.initState();
    _lastViewQuery = _viewQuery();
    _view =
        plannerDiscoverViewFromQuery(_lastViewQuery) ?? DiscoverView.yourSky;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Discover tab lives in an always-built IndexedStack, so initState ran
    // once at first planner build. When a `/your-sky` or `/constellation`
    // deep-link re-enters the already-mounted planner with a new `?view=`,
    // re-apply it here (GoRouterState is an inherited dependency). Guarded on the
    // query changing so a user's manual segment toggle isn't snapped back.
    final viewQuery = _viewQuery();
    if (viewQuery != _lastViewQuery) {
      _lastViewQuery = viewQuery;
      final resolved = plannerDiscoverViewFromQuery(viewQuery);
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
            child: SegmentedButton<DiscoverView>(
              segments: const [
                ButtonSegment(
                  value: DiscoverView.yourSky,
                  label: Text('Your Sky'),
                  icon: Icon(LucideIcons.orbit),
                ),
                ButtonSegment(
                  value: DiscoverView.constellation,
                  label: Text('Constellation'),
                  icon: Icon(LucideIcons.users),
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
              YourSkyView(),
              ConstellationView(),
            ],
          ),
        ),
      ],
    );
  }
}
