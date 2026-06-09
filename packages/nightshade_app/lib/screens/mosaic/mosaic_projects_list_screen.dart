import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'mosaic_project_controller.dart';
import 'mosaic_project_screen.dart';

/// A simple list of every durable mosaic project, reachable from nav / analytics.
///
/// Each row opens [MosaicProjectScreen] at `/mosaic/:id`. Design-system pure:
/// rows are [NightshadeCard]s with a status pill and the grid summary.
class MosaicProjectsListScreen extends ConsumerWidget {
  const MosaicProjectsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final projectsAsync = ref.watch(mosaicProjectsListProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              icon: NightshadeIcons.grid,
              title: 'Mosaic projects',
              subtitle: 'Multi-panel mosaics: capture, integrate, stitch',
            ),
            Expanded(
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => EmptyState(
                  icon: NightshadeIcons.warning,
                  title: 'Could not load mosaic projects',
                  body: '$e',
                ),
                data: (projects) => projects.isEmpty
                    ? const EmptyState(
                        icon: NightshadeIcons.grid,
                        title: 'No mosaic projects yet',
                        body: 'Design a mosaic in Framing or the Planetarium '
                            'and save it as a project to capture and stitch '
                            'it here.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                        itemCount: projects.length,
                        separatorBuilder: (_, __) => const SizedBox(
                          height: NightshadeTokens.spaceSm,
                        ),
                        itemBuilder: (context, index) => _ProjectRow(
                          project: projects[index],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final MosaicProject project;

  const _ProjectRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      enableHover: true,
      onTap: () => context.go('/mosaic/${project.id}'),
      child: Row(
        children: [
          Icon(NightshadeIcons.grid,
              size: NightshadeTokens.iconMd, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.name.isEmpty ? 'Mosaic project' : project.name,
                  style: NightshadeTypography.body
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  '${project.cols}x${project.rows} grid  ·  '
                  '${project.totalPanels} panels',
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          StatusPill(
            icon: project.isComplete
                ? NightshadeIcons.success
                : NightshadeIcons.clock,
            label: '',
            value: mosaicProjectStatusLabel(project.status),
            status: project.isComplete
                ? StatusPillStatus.success
                : StatusPillStatus.inactive,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Icon(NightshadeIcons.chevronRight,
              size: NightshadeTokens.iconSm, color: colors.textMuted),
        ],
      ),
    );
  }
}
