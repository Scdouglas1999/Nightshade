import 'dart:convert';
import 'package:drift/drift.dart' hide Column; // For Value
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Provider for target search query
final targetSearchProvider = StateProvider<String>((ref) => '');

/// Provider for target type filter
final targetTypeFilterProvider = StateProvider<String?>((ref) => null);

/// Provider to watch all targets from database (using the database-generated Target type)
final targetsProvider = StreamProvider((ref) {
  return ref.watch(targetsDaoProvider).watchAllTargets();
});

class TargetsTab extends ConsumerWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final targetsAsync = ref.watch(targetsProvider);
    final searchQuery = ref.watch(targetSearchProvider);
    final typeFilter = ref.watch(targetTypeFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header with search and actions
          _TargetsHeader(colors: colors),

          const SizedBox(height: 20),

          // Target list
          Expanded(
            child: targetsAsync.when(
              data: (targets) {
                // Filter targets
                var filtered = targets;
                if (searchQuery.isNotEmpty) {
                  filtered = filtered.where((t) {
                    final nameMatch = t.name
                        .toLowerCase()
                        .contains(searchQuery.toLowerCase());
                    final catalogMatch = t.catalogId
                            ?.toLowerCase()
                            .contains(searchQuery.toLowerCase()) ??
                        false;
                    final constMatch = t.constellation
                            ?.toLowerCase()
                            .contains(searchQuery.toLowerCase()) ??
                        false;
                    return nameMatch || catalogMatch || constMatch;
                  }).toList();
                }
                if (typeFilter != null && typeFilter != 'All') {
                  filtered = filtered
                      .where((t) => t.objectType == typeFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return _EmptyState(colors: colors);
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _TargetCard(
                      colors: colors,
                      target: filtered[index],
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 48, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load targets',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    Text(
                      error.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                Icon(LucideIcons.search,
                    size: 16, color: widget.colors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      ref.read(targetSearchProvider.notifier).state = value;
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
                      ref.read(targetSearchProvider.notifier).state = '';
                    },
                    child: Icon(LucideIcons.x,
                        size: 16, color: widget.colors.textMuted),
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
                style:
                    TextStyle(fontSize: 13, color: widget.colors.textSecondary),
              ),
              icon: Icon(LucideIcons.chevronDown,
                  size: 16, color: widget.colors.textMuted),
              dropdownColor: widget.colors.surface,
              style: TextStyle(fontSize: 13, color: widget.colors.textPrimary),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('All Types'),
                ),
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
                  SnackBar(
                    content: Text('Imported $importedCount target(s)'),
                  ),
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
      builder: (context) => _AddTargetDialog(colors: widget.colors),
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
            catalogId:
                parts.length > 3 ? Value(parts[3]) : const Value.absent(),
            ra: ra,
            dec: dec,
            objectType:
                parts.length > 4 ? Value(parts[4]) : const Value.absent(),
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

class _ActionButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? _isHovered
                    ? widget.colors.primary.withValues(alpha: 0.9)
                    : widget.colors.primary
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(color: widget.colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isPrimary
                    ? primaryForeground
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.isPrimary
                      ? primaryForeground
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final dynamic
      target; // Using dynamic since Target is a database generated type

  const _TargetCard({required this.colors, required this.target});

  @override
  ConsumerState<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends ConsumerState<_TargetCard> {
  bool _isHovered = false;
  bool _isExpanded = false;

  IconData _getTypeIcon() {
    switch (widget.target.objectType) {
      case 'Galaxy':
        return LucideIcons.sparkles;
      case 'Nebula':
        return LucideIcons.cloud;
      case 'Cluster':
        return LucideIcons.sparkle;
      case 'Star':
        return LucideIcons.star;
      case 'Planet':
        return LucideIcons.globe;
      default:
        return LucideIcons.circle;
    }
  }

  Color _getTypeColor() {
    switch (widget.target.objectType) {
      case 'Galaxy':
        return widget.colors.accent;
      case 'Nebula':
        return widget.colors.info;
      case 'Cluster':
        return widget.colors.warning;
      case 'Star':
        return widget.colors.success;
      case 'Planet':
        return widget.colors.error;
      default:
        return widget.colors.textMuted;
    }
  }

  String _formatRa(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = (((raHours - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = (((absDec - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toString().padLeft(2, '0')}"';
  }

  String _formatIntegration(double secs) {
    final hours = (secs / 3600).floor();
    final minutes = ((secs % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _getTypeColor();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? typeColor.withValues(alpha: 0.5)
                : widget.colors.border,
            width: _isHovered ? 2 : 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: typeColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Main content
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getTypeIcon(),
                        size: 24,
                        color: typeColor,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.target.catalogId ?? widget.target.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: widget.colors.textPrimary,
                                ),
                              ),
                              if (widget.target.catalogId != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  widget.target.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: widget.colors.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.target.objectType ?? 'Object',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor,
                                  ),
                                ),
                              ),
                              if (widget.target.isFavorite) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  LucideIcons.heart,
                                  size: 14,
                                  color: widget.colors.error,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _InfoChip(
                                colors: widget.colors,
                                label: 'RA',
                                value: _formatRa(widget.target.ra),
                              ),
                              const SizedBox(width: 16),
                              _InfoChip(
                                colors: widget.colors,
                                label: 'Dec',
                                value: _formatDec(widget.target.dec),
                              ),
                              if (widget.target.magnitude != null) ...[
                                const SizedBox(width: 16),
                                _InfoChip(
                                  colors: widget.colors,
                                  label: 'Mag',
                                  value: widget.target.magnitude!
                                      .toStringAsFixed(1),
                                ),
                              ],
                              if (widget.target.constellation != null) ...[
                                const SizedBox(width: 16),
                                _InfoChip(
                                  colors: widget.colors,
                                  label: 'Con',
                                  value: widget.target.constellation!,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Stats
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.camera,
                                size: 12, color: widget.colors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.target.capturedSubs ?? 0} subs',
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(LucideIcons.timer,
                                size: 12, color: widget.colors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              _formatIntegration(
                                  widget.target.totalIntegrationSecs ?? 0),
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(width: 16),

                    // Actions
                    if (_isHovered) ...[
                      _IconButton(
                        colors: widget.colors,
                        icon: widget.target.isFavorite
                            ? LucideIcons.heart
                            : LucideIcons.heartHandshake,
                        tooltip: 'Toggle Favorite',
                        color: widget.colors.error,
                        onPressed: () {
                          ref
                              .read(targetsDaoProvider)
                              .toggleFavorite(widget.target.id);
                        },
                      ),
                      _IconButton(
                        colors: widget.colors,
                        icon: LucideIcons.crosshair,
                        tooltip: 'Add to Sequence',
                        onPressed: () {
                          // Add target to sequence
                          ref.read(currentSequenceProvider.notifier).addNode(
                                TargetGroupNode(
                                  targetName: widget.target.catalogId ??
                                      widget.target.name,
                                  raHours: widget.target.ra,
                                  decDegrees: widget.target.dec,
                                ),
                              );
                        },
                      ),
                      _IconButton(
                        colors: widget.colors,
                        icon: LucideIcons.pencil,
                        tooltip: 'Edit',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => EditTargetDialog(
                              colors: widget.colors,
                              target: widget.target,
                            ),
                          );
                        },
                      ),
                      _IconButton(
                        colors: widget.colors,
                        icon: LucideIcons.trash2,
                        tooltip: 'Delete',
                        color: widget.colors.error,
                        onPressed: () {
                          ref
                              .read(targetsDaoProvider)
                              .deleteTarget(widget.target.id);
                        },
                      ),
                    ],

                    Icon(
                      _isExpanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: widget.colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded content
            AnimatedCrossFade(
              firstChild: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: widget.colors.border),
                    const SizedBox(height: 12),
                    if (widget.target.notes != null &&
                        widget.target.notes!.isNotEmpty) ...[
                      Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.target.notes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: NightshadeButton(
                            label: 'Add to Sequence',
                            icon: LucideIcons.plus,
                            onPressed: () {
                              ref
                                  .read(currentSequenceProvider.notifier)
                                  .addNode(
                                    TargetGroupNode(
                                      targetName: widget.target.catalogId ??
                                          widget.target.name,
                                      raHours: widget.target.ra,
                                      decDegrees: widget.target.dec,
                                    ),
                                  );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NightshadeButton(
                            label: 'Slew to Target',
                            icon: LucideIcons.navigation,
                            variant: ButtonVariant.outline,
                            onPressed: () async {
                              try {
                                final deviceService =
                                    ref.read(deviceServiceProvider);
                                await deviceService.slewMountToCoordinates(
                                  widget.target.ra,
                                  widget.target.dec,
                                );

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Slewing to ${widget.target.name}'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Failed to slew: $e')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _InfoChip({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;

  const _IconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? color : widget.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              LucideIcons.target,
              size: 48,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No targets found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first target or import from a catalog',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTargetDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _AddTargetDialog({required this.colors});

  @override
  ConsumerState<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends ConsumerState<_AddTargetDialog> {
  final _nameController = TextEditingController();
  final _catalogIdController = TextEditingController();
  final _raController = TextEditingController();
  final _decController = TextEditingController();
  String _objectType = 'Nebula';

  @override
  void dispose() {
    _nameController.dispose();
    _catalogIdController.dispose();
    _raController.dispose();
    _decController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.plus, color: widget.colors.primary),
                const SizedBox(width: 12),
                Text(
                  'Add Target',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: widget.colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildField('Name', _nameController, 'e.g., Orion Nebula'),
            _buildField(
                'Catalog ID', _catalogIdController, 'e.g., M42, NGC 7000'),
            _buildField('RA (hours)', _raController, 'e.g., 5.588'),
            _buildField('Dec (degrees)', _decController, 'e.g., -5.391'),
            Text(
              'Object Type',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _objectType,
                  isExpanded: true,
                  dropdownColor: widget.colors.surface,
                  style:
                      TextStyle(fontSize: 13, color: widget.colors.textPrimary),
                  items: [
                    'Galaxy',
                    'Nebula',
                    'Cluster',
                    'Star',
                    'Planet',
                    'Other'
                  ]
                      .map((type) =>
                          DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _objectType = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: widget.colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: 'Add Target',
                  icon: LucideIcons.plus,
                  onPressed: () {
                    final ra = double.tryParse(_raController.text);
                    final dec = double.tryParse(_decController.text);

                    if (_nameController.text.isNotEmpty &&
                        ra != null &&
                        dec != null) {
                      ref.read(targetsDaoProvider).createTarget(
                            TargetsCompanion.insert(
                              name: _nameController.text,
                              catalogId: Value(_catalogIdController.text.isEmpty
                                  ? null
                                  : _catalogIdController.text),
                              ra: ra,
                              dec: dec,
                              objectType: Value(_objectType),
                            ),
                          );
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: TextField(
              controller: controller,
              style: TextStyle(fontSize: 13, color: widget.colors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(fontSize: 13, color: widget.colors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditTargetDialog extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final dynamic target;

  const EditTargetDialog(
      {super.key, required this.colors, required this.target});

  @override
  ConsumerState<EditTargetDialog> createState() => _EditTargetDialogState();
}

class _EditTargetDialogState extends ConsumerState<EditTargetDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _catalogIdController;
  late final TextEditingController _raController;
  late final TextEditingController _decController;
  late String _objectType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.target.name);
    _catalogIdController =
        TextEditingController(text: widget.target.catalogId ?? '');
    _raController = TextEditingController(text: widget.target.ra.toString());
    _decController = TextEditingController(text: widget.target.dec.toString());
    _objectType = widget.target.objectType ?? 'Nebula';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _catalogIdController.dispose();
    _raController.dispose();
    _decController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.pencil, color: widget.colors.primary),
                const SizedBox(width: 12),
                Text(
                  'Edit Target',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: widget.colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildField('Name', _nameController, 'e.g., Orion Nebula'),
            _buildField(
                'Catalog ID', _catalogIdController, 'e.g., M42, NGC 7000'),
            _buildField('RA (hours)', _raController, 'e.g., 5.588'),
            _buildField('Dec (degrees)', _decController, 'e.g., -5.391'),
            Text(
              'Object Type',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _objectType,
                  isExpanded: true,
                  dropdownColor: widget.colors.surface,
                  style:
                      TextStyle(fontSize: 13, color: widget.colors.textPrimary),
                  items: [
                    'Galaxy',
                    'Nebula',
                    'Cluster',
                    'Star',
                    'Planet',
                    'Other'
                  ]
                      .map((type) =>
                          DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _objectType = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: widget.colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                NightshadeButton(
                  label: 'Save Changes',
                  icon: LucideIcons.check,
                  onPressed: () {
                    final ra = double.tryParse(_raController.text);
                    final dec = double.tryParse(_decController.text);

                    if (_nameController.text.isNotEmpty &&
                        ra != null &&
                        dec != null) {
                      ref.read(targetsDaoProvider).updateTarget(
                            widget.target.copyWith(
                              name: _nameController.text,
                              catalogId: _catalogIdController.text.isEmpty
                                  ? null
                                  : _catalogIdController.text,
                              ra: ra,
                              dec: dec,
                              objectType: _objectType,
                            ),
                          );
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: TextField(
              controller: controller,
              style: TextStyle(fontSize: 13, color: widget.colors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(fontSize: 13, color: widget.colors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
