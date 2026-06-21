// Part of ../planner_screen.dart -- extracted for maintainability.
//
// "Projects" tab: the multi-night campaign workspace. The former "Projects" and
// "Progress" tabs are unified here behind one clearly-labelled scope switch —
// the active campaign's goal tracking vs. the global all-targets roll-up — so a
// user reaches both from a single tab instead of two siblings that read the
// same captured-frames / integration-goal data at different scopes.
part of '../planner_screen.dart';

/// Which progress scope the consolidated "Projects" tab shows.
enum _ProjectsScope { campaign, allTargets }

class _ProjectsTab extends StatefulWidget {
  const _ProjectsTab();

  @override
  State<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<_ProjectsTab> {
  _ProjectsScope _scope = _ProjectsScope.campaign;

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
            child: SegmentedButton<_ProjectsScope>(
              segments: const [
                ButtonSegment(
                  value: _ProjectsScope.campaign,
                  label: Text('This Campaign'),
                  icon: Icon(LucideIcons.folderKanban),
                ),
                ButtonSegment(
                  value: _ProjectsScope.allTargets,
                  label: Text('All Targets'),
                  icon: Icon(LucideIcons.trendingUp),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (selection) =>
                  setState(() => _scope = selection.first),
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
          child: _scope == _ProjectsScope.campaign
              ? const ProjectsTabContent()
              : const ProgressTabContent(),
        ),
      ],
    );
  }
}
