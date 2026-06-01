// Part of ../targets_tab.dart -- extracted for maintainability.
//
// Add-target and optimize-order dialogs.
part of '../targets_tab.dart';

class _AddTargetDialog extends ConsumerStatefulWidget {
  const _AddTargetDialog();

  @override
  ConsumerState<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends ConsumerState<_AddTargetDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final searchState = ref.watch(objectSearchProvider);

    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 500,
      designHeight: 600,
    );
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Target to Session',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Search Bar
              TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search object (e.g. M42, NGC 7000)...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  prefixIcon: Icon(LucideIcons.search, color: colors.textMuted),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  ref.read(objectSearchProvider.notifier).search(value);
                },
              ),

              const SizedBox(height: 16),

              // Results
              Expanded(
                child: searchState.isSearching
                    ? Center(
                        child: CircularProgressIndicator(color: colors.primary))
                    : searchState.results.isEmpty
                        ? Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'Type to search...'
                                  : 'No results found',
                              style: TextStyle(color: colors.textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: searchState.results.length,
                            separatorBuilder: (_, __) =>
                                Divider(color: colors.border, height: 1),
                            itemBuilder: (context, index) {
                              final obj = searchState.results[index];
                              return ListTile(
                                title: Text(
                                  obj.name,
                                  style: TextStyle(color: colors.textPrimary),
                                ),
                                subtitle: Text(
                                  obj.id != obj.name ? obj.id : '',
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                                trailing: NightshadeButton(
                                  label: 'Add',
                                  icon: LucideIcons.plus,
                                  variant: ButtonVariant.ghost,
                                  size: ButtonSize.small,
                                  onPressed: () {
                                    ref
                                        .read(currentSequenceProvider.notifier)
                                        .addNode(
                                          TargetHeaderNode(
                                            targetName: obj.name,
                                            raHours: obj.coordinates.ra,
                                            decDegrees: obj.coordinates.dec,
                                          ),
                                        );
                                    Navigator.pop(context);
                                    if (context.mounted) {
                                      context.showSuccessSnackBar(
                                          'Added ${obj.name} to sequence');
                                    }
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptimizeOrderDialog extends ConsumerStatefulWidget {
  final List<TargetHeaderNode> targets;

  const _OptimizeOrderDialog({required this.targets});

  @override
  ConsumerState<_OptimizeOrderDialog> createState() =>
      _OptimizeOrderDialogState();
}

class _OptimizeOrderDialogState extends ConsumerState<_OptimizeOrderDialog> {
  OptimizationStrategy _strategy = OptimizationStrategy.settingFirst;
  double _minAltitude = 30.0;
  List<AltitudeData>? _previewData;
  List<TargetHeaderNode>? _optimizedOrder;

  @override
  void initState() {
    super.initState();
    _calculatePreview();
  }

  void _calculatePreview() {
    final scheduler = ref.read(schedulerServiceProvider);
    final location = ref.read(observerLocationProvider);
    final now = DateTime.now();

    _previewData = scheduler.calculateTargetAltitudes(
      targets: widget.targets,
      observationTime: now,
      latitudeDegrees: location.latitude,
      longitudeDegrees: location.longitude,
      minAltitude: _minAltitude,
    );

    _optimizedOrder = scheduler.optimizeTargetOrder(
      targets: widget.targets,
      strategy: _strategy,
      observationTime: now,
      latitudeDegrees: location.latitude,
      longitudeDegrees: location.longitude,
      minAltitude: _minAltitude,
    );

    setState(() {});
  }

  void _applyOptimization() {
    if (_optimizedOrder == null) return;

    final notifier = ref.read(currentSequenceProvider.notifier);

    // Reorder targets to match optimized order. If any cross-parent
    // reorder is requested by the optimizer (shouldn't happen — the
    // optimizer operates on flat sibling lists) we surface it instead
    // of half-applying the plan.
    try {
      for (int i = 0; i < _optimizedOrder!.length; i++) {
        final target = _optimizedOrder![i];
        final currentIndex =
            widget.targets.indexWhere((t) => t.id == target.id);
        if (currentIndex != i && currentIndex != -1) {
          notifier.reorderTargets(currentIndex, i);
        }
      }
    } on CrossParentReorderException catch (e) {
      Navigator.of(context).pop();
      if (context.mounted) {
        context.showErrorSnackBar(
          'Optimizer plan crosses target parents: ${e.message}',
        );
      }
      return;
    } on SequenceLockedException catch (e) {
      Navigator.of(context).pop();
      if (context.mounted) {
        context.showErrorSnackBar(e.message);
      }
      return;
    }

    Navigator.of(context).pop();
    if (context.mounted) {
      context.showSuccessSnackBar('Target order optimized');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 700,
      designHeight: 600,
    );
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles, color: colors.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Optimize Target Order',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Strategy Selection
              Text('Optimization Strategy', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OptimizationStrategy.values.map((strategy) {
                  final isSelected = _strategy == strategy;
                  return ChoiceChip(
                    label: Text(_strategyLabel(strategy)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _strategy = strategy);
                      _calculatePreview();
                    },
                    selectedColor: colors.primary.withValues(alpha: 0.3),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Min Altitude Slider
              Row(
                children: [
                  Text('Minimum Altitude: ${_minAltitude.toStringAsFixed(0)}°'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: _minAltitude,
                      min: 0,
                      max: 60,
                      divisions: 12,
                      onChanged: (v) {
                        setState(() => _minAltitude = v);
                        _calculatePreview();
                      },
                      activeColor: colors.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Preview
              Text('Preview Order', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: _optimizedOrder == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _optimizedOrder!.length,
                          itemBuilder: (context, index) {
                            final target = _optimizedOrder![index];
                            final data = _previewData?.firstWhere(
                              (d) => d.targetId == target.id,
                            );
                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: NightshadeDecorations.kpiBadge(
                                  colors.primary,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(target.targetName),
                              subtitle: data != null
                                  ? Text(
                                      'Alt: ${data.currentAltitude.toStringAsFixed(1)}° '
                                      '(${data.isRising ? "Rising" : "Setting"}) '
                                      '• Transit: ${DateFormat('HH:mm').format(data.transitTime)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    )
                                  : null,
                              trailing: Icon(
                                data?.isRising == true
                                    ? LucideIcons.trendingUp
                                    : LucideIcons.trendingDown,
                                color: data?.isRising == true
                                    ? colors.success
                                    : colors.warning,
                                size: 18,
                              ),
                            );
                          },
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  NightshadeButton(
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                  const SizedBox(width: 12),
                  NightshadeButton(
                    onPressed: _applyOptimization,
                    icon: LucideIcons.check,
                    label: 'Apply Order',
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _strategyLabel(OptimizationStrategy strategy) {
    switch (strategy) {
      case OptimizationStrategy.transitTime:
        return 'By Transit Time';
      case OptimizationStrategy.currentAltitude:
        return 'By Current Altitude';
      case OptimizationStrategy.risingFirst:
        return 'Rising First';
      case OptimizationStrategy.settingFirst:
        return 'Setting First (Recommended)';
      case OptimizationStrategy.priority:
        return 'By Priority';
    }
  }
}
