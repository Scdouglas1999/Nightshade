part of '../projects_tab_content.dart';

/// Result returned by [_ProjectFormDialog] on save.
class _ProjectFormResult {
  final String name;
  final String? description;
  const _ProjectFormResult({required this.name, this.description});
}

// =============================================================================
// Header bar: project selector + create / edit / delete.
// =============================================================================

class _ProjectHeaderBar extends StatelessWidget {
  final NightshadeColors colors;
  final List<Project> projects;
  final Project active;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onCreate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPlanInSmartNight;

  const _ProjectHeaderBar({
    required this.colors,
    required this.projects,
    required this.active,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onPlanInSmartNight,
  });

  @override
  Widget build(BuildContext context) {
    // Project names are not guaranteed unique, so the dropdown value space is
    // the set of decimal ids (stable, unique), with names supplied as labels.
    final ids = projects
        .map((p) => p.id)
        .whereType<int>()
        .map((id) => id.toString())
        .toList();
    final labels = projects.map((p) => p.name).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: NightshadeDropdown(
                value: active.id?.toString(),
                items: ids,
                itemLabels: labels,
                isExpanded: true,
                onChanged: (raw) {
                  if (raw == null) return;
                  final id = int.tryParse(raw);
                  if (id != null) onSelect(id);
                },
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          AccessibleIconButton(
            icon: LucideIcons.pencil,
            label: 'Edit project',
            tooltip: 'Edit project',
            size: NightshadeTokens.iconMd,
            onPressed: onEdit,
          ),
          AccessibleIconButton(
            icon: LucideIcons.trash2,
            label: 'Delete project',
            tooltip: 'Delete project',
            color: colors.error,
            size: NightshadeTokens.iconMd,
            onPressed: onDelete,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'Plan in Smart Night',
            icon: LucideIcons.sparkles,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onPlanInSmartNight,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'New Project',
            icon: LucideIcons.folderPlus,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => onCreate(),
          ),
        ],
      ),
    );
  }
}
