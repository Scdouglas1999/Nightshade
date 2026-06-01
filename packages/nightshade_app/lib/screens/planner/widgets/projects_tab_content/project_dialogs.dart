part of '../projects_tab_content.dart';

// =============================================================================
// Create / edit project dialog.
// =============================================================================

class _ProjectFormDialog extends StatefulWidget {
  final Project? existing;

  const _ProjectFormDialog({this.existing});

  @override
  State<_ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<_ProjectFormDialog> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _descCtl;
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtl = TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Project name is required');
      return;
    }
    final desc = _descCtl.text.trim();
    Navigator.of(context).pop(
      _ProjectFormResult(
        name: name,
        description: desc.isEmpty ? null : desc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeDialog(
      title: _isEdit ? 'Edit Project' : 'New Project',
      icon: _isEdit ? LucideIcons.pencil : LucideIcons.folderPlus,
      width: 480,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: _isEdit ? 'Save' : 'Create',
          icon: LucideIcons.check,
          size: ButtonSize.small,
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Group several targets into a multi-night campaign to track '
            'integration goals across clear nights.',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          NightshadeTextField(
            controller: _nameCtl,
            label: 'Name',
            hint: 'e.g. Winter Nebulae',
            prefixIcon: LucideIcons.folder,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeTextField(
            controller: _descCtl,
            label: 'Description (optional)',
            hint: 'Notes about this campaign',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Add-target dialog: searchable catalog picker.
// =============================================================================

class _AddTargetDialog extends ConsumerStatefulWidget {
  final Set<int> attachedTargetIds;

  const _AddTargetDialog({required this.attachedTargetIds});

  @override
  ConsumerState<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends ConsumerState<_AddTargetDialog> {
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final targetsAsync = ref.watch(allDbTargetsProvider);

    return NightshadeDialog(
      title: 'Add Target',
      icon: LucideIcons.plus,
      width: 560,
      height: 560,
      scrollableBody: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeTextField(
            controller: _searchCtl,
            hint: 'Search targets…',
            prefixIcon: LucideIcons.search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Expanded(
            child: targetsAsync.when(
              loading: () => Center(
                child: SizedBox(
                  width: NightshadeTokens.iconLg,
                  height: NightshadeTokens.iconLg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
              error: (err, _) => NightshadeAlert(
                severity: NightshadeAlertSeverity.error,
                title: 'Failed to load targets',
                message: err.toString(),
              ),
              data: (targets) {
                final available = targets
                    .where((t) => !widget.attachedTargetIds.contains(t.id))
                    .where((t) =>
                        _query.isEmpty || t.name.toLowerCase().contains(_query))
                    .toList()
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                if (targets.isEmpty) {
                  return const EmptyState.compact(
                    icon: LucideIcons.star,
                    title: 'No targets in the catalog',
                    body: 'Add targets to your library first, then attach '
                        'them to this campaign.',
                  );
                }
                if (available.isEmpty) {
                  return EmptyState.compact(
                    icon: LucideIcons.searchX,
                    title: 'No matching targets',
                    body: _query.isEmpty
                        ? 'Every catalog target is already in this campaign.'
                        : 'No catalog target matches "$_query".',
                  );
                }

                return ListView.separated(
                  itemCount: available.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: NightshadeTokens.spaceXs),
                  itemBuilder: (context, index) {
                    final t = available[index];
                    return _CatalogTargetTile(
                      colors: colors,
                      name: t.name,
                      onTap: () => Navigator.of(context).pop(t.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogTargetTile extends StatelessWidget {
  final NightshadeColors colors;
  final String name;
  final VoidCallback onTap;

  const _CatalogTargetTile({
    required this.colors,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: NightshadeTokens.borderRadiusSm,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceMd,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.target,
                size: NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  name,
                  style: NightshadeTypography.body.copyWith(
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                LucideIcons.plus,
                size: NightshadeTokens.iconSm,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
