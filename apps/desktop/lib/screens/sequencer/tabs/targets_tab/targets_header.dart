part of '../targets_tab.dart';

class _TargetsHeader extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _TargetsHeader({required this.colors});

  @override
  ConsumerState<_TargetsHeader> createState() => _TargetsHeaderState();
}

class _TargetsHeaderState extends ConsumerState<_TargetsHeader> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typeFilter = ref.watch(targetTypeFilterProvider);

    return Row(
      children: [
        // Search
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 16,
                  color: widget.colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      ref.read(sequenceTargetSearchProvider.notifier).state =
                          value;
                    },
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search targets...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      ref.read(sequenceTargetSearchProvider.notifier).state =
                          '';
                    },
                    child: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Type filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.colors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: typeFilter,
              hint: Text(
                'All Types',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.colors.textSecondary,
                ),
              ),
              icon: Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: widget.colors.textMuted,
              ),
              dropdownColor: widget.colors.surface,
              style: TextStyle(fontSize: 13, color: widget.colors.textPrimary),
              items: const [
                DropdownMenuItem(value: null, child: Text('All Types')),
                DropdownMenuItem(value: 'Galaxy', child: Text('Galaxies')),
                DropdownMenuItem(value: 'Nebula', child: Text('Nebulae')),
                DropdownMenuItem(value: 'Cluster', child: Text('Clusters')),
                DropdownMenuItem(value: 'Star', child: Text('Stars')),
                DropdownMenuItem(value: 'Planet', child: Text('Planets')),
              ],
              onChanged: (value) {
                ref.read(targetTypeFilterProvider.notifier).state = value;
              },
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Add button
        _ActionButton(
          colors: widget.colors,
          icon: LucideIcons.plus,
          label: 'Add Target',
          isPrimary: true,
          onPressed: () => _showAddTargetDialog(context),
        ),

        const SizedBox(width: 8),

        // Import button
        _ActionButton(
          colors: widget.colors,
          icon: LucideIcons.download,
          label: 'Import',
          onPressed: () async {
            try {
              final file = await file_selector.openFile(
                acceptedTypeGroups: [
                  const file_selector.XTypeGroup(
                    label: 'CSV or JSON',
                    extensions: ['csv', 'json'],
                  ),
                ],
              );

              if (file == null) return;

              final content = await file.readAsString();
              final extension = file.name.split('.').last.toLowerCase();

              int importedCount = 0;
              if (extension == 'csv') {
                importedCount = await _importTargetsFromCsv(content);
              } else if (extension == 'json') {
                importedCount = await _importTargetsFromJson(content);
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Imported $importedCount target(s)')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to import targets: $e')),
                );
              }
            }
          },
        ),
      ],
    );
  }

  void _showAddTargetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _AddTargetDialog(),
    );
  }

  Future<int> _importTargetsFromCsv(String content) async {
    final lines = content.split('\n');
    if (lines.isEmpty) return 0;

    // Skip header if present
    int startIndex = 0;
    if (lines[0].toLowerCase().contains('name') ||
        lines[0].toLowerCase().contains('ra') ||
        lines[0].toLowerCase().contains('dec')) {
      startIndex = 1;
    }

    int imported = 0;
    final targetsDao = ref.read(targetsDaoProvider);

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) continue; // Need at least name, RA, Dec

      try {
        final name = parts[0];
        final ra = double.tryParse(parts[1]);
        final dec = double.tryParse(parts[2]);

        if (ra == null || dec == null) continue;

        await targetsDao.createTarget(
          TargetsCompanion.insert(
            name: name,
            catalogId: parts.length > 3
                ? Value(parts[3])
                : const Value.absent(),
            ra: ra,
            dec: dec,
            objectType: parts.length > 4
                ? Value(parts[4])
                : const Value.absent(),
          ),
        );
        imported++;
      } catch (e) {
        // Skip invalid rows
        continue;
      }
    }

    return imported;
  }

  Future<int> _importTargetsFromJson(String content) async {
    try {
      final json = jsonDecode(content) as dynamic;
      final List<dynamic> targetsList;

      if (json is List) {
        targetsList = json;
      } else if (json is Map && json['targets'] != null) {
        targetsList = json['targets'] as List<dynamic>;
      } else {
        return 0;
      }

      int imported = 0;
      final targetsDao = ref.read(targetsDaoProvider);

      for (final targetJson in targetsList) {
        if (targetJson is! Map<String, dynamic>) continue;

        try {
          final name = targetJson['name'] as String?;
          final ra = (targetJson['ra'] as num?)?.toDouble();
          final dec = (targetJson['dec'] as num?)?.toDouble();

          if (name == null || ra == null || dec == null) continue;

          await targetsDao.createTarget(
            TargetsCompanion.insert(
              name: name,
              catalogId: Value(targetJson['catalogId'] as String?),
              ra: ra,
              dec: dec,
              objectType: Value(targetJson['objectType'] as String?),
              magnitude: targetJson['magnitude'] != null
                  ? Value((targetJson['magnitude'] as num).toDouble())
                  : const Value.absent(),
              constellation: Value(targetJson['constellation'] as String?),
              notes: Value(targetJson['notes'] as String?),
            ),
          );
          imported++;
        } catch (e) {
          // Skip invalid entries
          continue;
        }
      }

      return imported;
    } catch (e) {
      return 0;
    }
  }
}
