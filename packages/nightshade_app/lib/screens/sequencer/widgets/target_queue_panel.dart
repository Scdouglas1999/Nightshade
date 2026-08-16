// Target Queue panel for the sequencer Builder.
//
// Bridges the planetarium's `target_queue_provider` (a user-curated
// wishlist of targets) into the sequencer authoring surface. Drag a
// queued target onto the sequence tree to insert a TargetHeaderNode
// with the target's RA/Dec pre-filled.
//
// The panel is purely a *view* on the planetarium's queue — it does
// not own its own state. Mutations to the queue (add / remove / mark
// active) flow through `targetQueueProvider`.
//
// Drag payload: a `TargetQueueDragPayload` (defined below) carrying the
// queued target plus a resolved coordinate. The sequence tree's
// existing `DragTarget<Object>` is widened in `sequence_tree.dart` to
// accept this payload and convert it into an `addNode` call.
//
// Drag-drop is disabled while the sequencer is running: the panel
// watches `canEditSequenceProvider` and wraps the Draggable subtree in
// an IgnorePointer when edits are locked.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/add_target_header_helper.dart';
import '../../accessible_dropdown.dart';
import 'target_header_card.dart';

/// Drag payload type carried by `Draggable<TargetQueueDragPayload>` from
/// the queue panel to the sequence tree. Carries the source queued
/// target so the tree can both build the node and (after a successful
/// drop) mark the queue entry as "in plan" for visual feedback.
/// Drag ghost width: design 320px, capped to ~92% of viewport so narrow
/// test surfaces and split-pane layouts never hit [clamp] min > max.
double _dragFeedbackWidth(BuildContext context) {
  final viewport = MediaQuery.sizeOf(context).width;
  final maxW = viewport * AdaptiveDialogConstraints.defaultWidthFraction;
  if (maxW <= 120) return maxW;
  return AdaptiveDialogConstraints.clampPanelWidth(
    context,
    designWidth: 320,
    minWidth: math.min(160, maxW),
    maxWidth: maxW,
  );
}

class TargetQueueDragPayload {
  final QueuedTarget queuedTarget;

  /// Pre-computed TargetHeaderNode template. Built in the panel so the
  /// drop site doesn't need access to the planetarium types — it just
  /// reads `node` and passes it to `currentSequenceProvider.addNode`.
  final TargetHeaderNode node;

  const TargetQueueDragPayload({
    required this.queuedTarget,
    required this.node,
  });
}

/// Matches an executor target to a queue label without confusing catalog IDs
/// such as M1 and M10. Qualified names (for example "M31 (Panel 1/9)") still
/// match their base target when the extra text begins at a word boundary.
bool targetQueueNamesMatch(String first, String second) {
  final a = first.trim().toLowerCase();
  final b = second.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  return _isQualifiedTargetName(a, b) || _isQualifiedTargetName(b, a);
}

bool _isQualifiedTargetName(String candidate, String base) {
  if (candidate == base) return true;
  if (!candidate.startsWith(base) || candidate.length == base.length) {
    return false;
  }
  return RegExp(r'[\s\(\[\{\-–—/:]').hasMatch(candidate[base.length]);
}

/// Sort modes for the target queue list.
enum _QueueSortMode {
  userOrder,
  score,
  altitude,
  name,
  ra,
}

extension _QueueSortModeLabel on _QueueSortMode {
  String get label {
    switch (this) {
      case _QueueSortMode.userOrder:
        return 'User order';
      case _QueueSortMode.score:
        return 'Visibility (altitude proxy)';
      case _QueueSortMode.altitude:
        return 'Current altitude';
      case _QueueSortMode.name:
        return 'Name';
      case _QueueSortMode.ra:
        return 'RA';
    }
  }
}

/// Filter modes.
enum _QueueFilterMode {
  all,
  aboveHorizon,
  pendingOnly,
}

extension _QueueFilterLabel on _QueueFilterMode {
  String get label {
    switch (this) {
      case _QueueFilterMode.all:
        return 'All targets';
      case _QueueFilterMode.aboveHorizon:
        return 'Above horizon';
      case _QueueFilterMode.pendingOnly:
        return 'Pending only';
    }
  }
}

/// Single-target visibility snapshot computed from the shared ticker.
class _TargetVisibility {
  final double altitudeDeg;
  final double azimuthDeg;
  final double? transitAltitudeDeg;
  final DateTime? setTime;
  final bool aboveHorizon;
  final bool neverRises;
  final bool isCircumpolar;

  const _TargetVisibility({
    required this.altitudeDeg,
    required this.azimuthDeg,
    required this.transitAltitudeDeg,
    required this.setTime,
    required this.aboveHorizon,
    required this.neverRises,
    required this.isCircumpolar,
  });
}

_TargetVisibility _computeVisibility({
  required CelestialCoordinate coords,
  required double latitude,
  required double longitude,
  required DateTime now,
  required double effectiveHorizonDeg,
}) {
  final raDeg = coords.raDegrees;
  final decDeg = coords.dec;
  final (alt, az) = AstronomyCalculations.objectAltAz(
    raDeg: raDeg,
    decDeg: decDeg,
    dt: now,
    latitudeDeg: latitude,
    longitudeDeg: longitude,
  );
  final visibility = AstronomyCalculations.calculateObjectVisibility(
    raDeg: raDeg,
    decDeg: decDeg,
    // The NIGHT containing [now], not its calendar day: the scan runs local
    // noon to noon, so after midnight the raw instant selected the FOLLOWING
    // night and the "Sets" countdown below read ~25h for a target an hour from
    // the horizon.
    date: AstronomyCalculations.nightDateOf(now),
    latitudeDeg: latitude,
    longitudeDeg: longitude,
    minAltitude: effectiveHorizonDeg,
  );
  return _TargetVisibility(
    altitudeDeg: alt,
    azimuthDeg: az,
    transitAltitudeDeg: visibility.transitAltitude,
    setTime: visibility.setTime,
    aboveHorizon: alt > effectiveHorizonDeg,
    neverRises: visibility.neverRises,
    isCircumpolar: visibility.isCircumpolar,
  );
}

/// Public widget rendered in the sequencer Builder toolbox.
class TargetQueuePanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  /// Optional collapse handler — if provided, a collapse-icon is shown
  /// in the header that calls back to the parent toolbox.
  final VoidCallback? onCollapse;

  const TargetQueuePanel({
    super.key,
    required this.colors,
    this.onCollapse,
  });

  @override
  ConsumerState<TargetQueuePanel> createState() => _TargetQueuePanelState();
}

class _TargetQueuePanelState extends ConsumerState<TargetQueuePanel> {
  _QueueSortMode _sortMode = _QueueSortMode.userOrder;
  _QueueFilterMode _filterMode = _QueueFilterMode.all;

  /// Per-target visibility cache. Keyed by an invalidation signature built
  /// from the 30s tick bucket, observer location, and horizon so a sort/
  /// filter dropdown change (which triggers setState but doesn't change the
  /// sky) reuses the snapshots instead of recomputing real spherical trig for
  /// every queue entry. The cache is rebuilt only when the signature changes.
  final Map<String, _TargetVisibility> _visibilityCache = {};
  String? _visibilityCacheSignature;

  @override
  void initState() {
    super.initState();
    // Cross-screen reactivity: when the sequencer reaches a
    // TargetHeader whose display name matches a queue entry, mark
    // that entry as active. This drives the "live" pulsing card on
    // the planetarium too (both screens read from the same
    // targetQueueProvider).
    //
    // The reverse — removing a TargetHeader from the sequence
    // affecting the queue — is deliberately *not* wired here: the
    // queue is a wishlist and the user expects it to persist when
    // they delete nodes from the sequence tree. The brief is
    // explicit about this asymmetry.
    ref.listenManual<String?>(
      sequenceProgressProvider.select((p) => p.currentTarget),
      (prev, next) {
        if (!mounted) return;
        final queue = ref.read(targetQueueProvider);
        if (next == null || next.isEmpty) {
          // Sequencer is between targets — clear "active" flag.
          if (queue.activeTargetId != null) {
            ref.read(targetQueueProvider.notifier).setActiveTarget(null);
          }
          return;
        }
        // Find queue entry whose displayName matches the executor's
        // current target. Case-insensitive prefix match keeps "M31"
        // and "M31 (Panel 1/9)" together so mosaics light up the
        // parent queue card.
        final match = queue.targets.cast<QueuedTarget?>().firstWhere(
              (t) => t != null && targetQueueNamesMatch(t.displayName, next),
              orElse: () => null,
            );
        if (match != null && match.id != queue.activeTargetId) {
          ref.read(targetQueueProvider.notifier).setActiveTarget(match.id);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final queue = ref.watch(targetQueueProvider);
    final observer = ref.watch(observerLocationProvider);
    final horizonDeg = ref.watch(planetariumEffectiveHorizonDegProvider);
    // Live 30s tick — altitude / time-to-set need to refresh as the
    // sky moves. Cadence intentionally matches the dashboard's altitude
    // card (see clock_provider.dart).
    final tickAsync = ref.watch(tickerProvider(TickerCadence.thirtySeconds));
    final now = tickAsync.valueOrNull ?? DateTime.now();
    final canEdit = ref.watch(canEditSequenceProvider);

    // Compute visibility for every queue entry, memoised on the tick bucket /
    // location / horizon so sort+filter dropdown changes don't recompute the
    // trig. The snapshots stay in lock-step with the 30s ticker; a separate
    // provider would add cache-coordination work for no real benefit at this
    // list size (<= 50 targets typically).
    //
    // Altitude and rise/set are readings against a horizon, so with no site on
    // record there is nothing to compute: the cache is emptied and the rows
    // render without visibility rather than against a default observer.
    final site = observer.site;
    final tickBucket = now.millisecondsSinceEpoch ~/ 30000;
    final signature = site == null
        ? 'no-site'
        : '$tickBucket|${site.latitude}|${site.longitude}|$horizonDeg';
    if (site == null) {
      _visibilityCache.clear();
      _visibilityCacheSignature = signature;
    } else if (_visibilityCacheSignature != signature) {
      _visibilityCache
        ..clear()
        ..addEntries(queue.targets.map((t) => MapEntry(
              t.id,
              _computeVisibility(
                coords: t.coordinates,
                latitude: site.latitude,
                longitude: site.longitude,
                now: now,
                effectiveHorizonDeg: horizonDeg,
              ),
            )));
      _visibilityCacheSignature = signature;
    } else {
      // Same tick/location, but the queue set may have changed (add/remove);
      // backfill any newly-present targets without touching the rest.
      for (final t in queue.targets) {
        _visibilityCache.putIfAbsent(
          t.id,
          () => _computeVisibility(
            coords: t.coordinates,
            latitude: site.latitude,
            longitude: site.longitude,
            now: now,
            effectiveHorizonDeg: horizonDeg,
          ),
        );
      }
    }
    final visibilityByTarget = _visibilityCache;

    final filtered = _applyFilter(queue.targets, visibilityByTarget);
    _applySort(filtered, visibilityByTarget);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            colors: colors,
            queueLength: queue.targets.length,
            onCollapse: widget.onCollapse,
          ),
          _SortFilterBar(
            colors: colors,
            sortMode: _sortMode,
            filterMode: _filterMode,
            onSortChanged: (m) => setState(() => _sortMode = m),
            onFilterChanged: (m) => setState(() => _filterMode = m),
          ),
          if (queue.targets.isEmpty)
            _EmptyState(colors: colors)
          else if (filtered.isEmpty)
            _NoMatchesState(colors: colors)
          else
            Expanded(
              child: ListView.separated(
                key: const ValueKey('target_queue_list'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final target = filtered[index];
                  final visibility = visibilityByTarget[target.id];
                  return _QueueRow(
                    colors: colors,
                    target: target,
                    visibility: visibility,
                    canEdit: canEdit,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<QueuedTarget> _applyFilter(
    List<QueuedTarget> input,
    Map<String, _TargetVisibility> visibility,
  ) {
    switch (_filterMode) {
      case _QueueFilterMode.all:
        return List.of(input);
      case _QueueFilterMode.aboveHorizon:
        return input
            .where((t) => visibility[t.id]?.aboveHorizon ?? false)
            .toList();
      case _QueueFilterMode.pendingOnly:
        return input.where((t) => t.isPending).toList();
    }
  }

  void _applySort(
    List<QueuedTarget> list,
    Map<String, _TargetVisibility> visibility,
  ) {
    switch (_sortMode) {
      case _QueueSortMode.userOrder:
        list.sort((a, b) => a.priority.compareTo(b.priority));
        return;
      case _QueueSortMode.score:
        // Score = clamped altitude (0..90) — a real night-window
        // scoring would require the scoring service, which itself
        // depends on moon/twilight providers and would over-rebuild
        // this list on every minute tick. Altitude is the dominant
        // term in the published score function (target_scoring.dart),
        // so it's a good practical proxy for the list view.
        list.sort((a, b) {
          final av = visibility[a.id]?.altitudeDeg ?? -90;
          final bv = visibility[b.id]?.altitudeDeg ?? -90;
          return bv.compareTo(av); // descending
        });
        return;
      case _QueueSortMode.altitude:
        list.sort((a, b) {
          final av = visibility[a.id]?.altitudeDeg ?? -90;
          final bv = visibility[b.id]?.altitudeDeg ?? -90;
          return bv.compareTo(av);
        });
        return;
      case _QueueSortMode.name:
        list.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        return;
      case _QueueSortMode.ra:
        list.sort((a, b) => a.coordinates.ra.compareTo(b.coordinates.ra));
        return;
    }
  }
}

// Header / sort & filter bar

class _Header extends StatelessWidget {
  final NightshadeColors colors;
  final int queueLength;
  final VoidCallback? onCollapse;

  const _Header({
    required this.colors,
    required this.queueLength,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.listChecks, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Target Queue',
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              '$queueLength',
              style: NightshadeTypography.labelStrongSm
                  .copyWith(color: colors.textSecondary),
            ),
          ),
          if (onCollapse != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Collapse panel',
              child: InkWell(
                onTap: onCollapse,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.panelLeftClose,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortFilterBar extends StatelessWidget {
  final NightshadeColors colors;
  final _QueueSortMode sortMode;
  final _QueueFilterMode filterMode;
  final ValueChanged<_QueueSortMode> onSortChanged;
  final ValueChanged<_QueueFilterMode> onFilterChanged;

  const _SortFilterBar({
    required this.colors,
    required this.sortMode,
    required this.filterMode,
    required this.onSortChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: _Dropdown<_QueueSortMode>(
              colors: colors,
              icon: LucideIcons.arrowDownUp,
              tooltip: 'Sort',
              value: sortMode,
              entries: _QueueSortMode.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSortChanged(v);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _Dropdown<_QueueFilterMode>(
              colors: colors,
              icon: LucideIcons.filter,
              tooltip: 'Filter',
              value: filterMode,
              entries: _QueueFilterMode.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onFilterChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String tooltip;
  final T value;
  final List<DropdownMenuItem<T>> entries;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: AccessibleDropdown<T>(
                  value: value,
                  isDense: true,
                  isExpanded: true,
                  iconSize: 14,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textPrimary,
                  ),
                  dropdownColor: colors.surface,
                  items: entries,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Empty / no-match states

class _EmptyState extends ConsumerWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.list,
                size: 32, color: colors.textMuted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              'Your target queue is empty.',
              textAlign: TextAlign.center,
              style:
                  NightshadeTypography.h6.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              'Add targets from Plan Tonight \u2192 Planetarium, then drag '
              'them into the sequence tree to start a plan. This queue is the '
              'builder\'s own \u2014 the autopilot runs the separate '
              'scheduler queue in Plan Tonight \u2192 Schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchesState extends StatelessWidget {
  final NightshadeColors colors;
  const _NoMatchesState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No targets match the current filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// Single queue row + draggable

class _QueueRow extends ConsumerWidget {
  final NightshadeColors colors;
  final QueuedTarget target;
  final _TargetVisibility? visibility;
  final bool canEdit;

  const _QueueRow({
    required this.colors,
    required this.target,
    required this.visibility,
    required this.canEdit,
  });

  TargetHeaderNode _buildNode() {
    return TargetHeaderNode(
      name: target.displayName,
      targetName: target.displayName,
      raHours: target.coordinates.ra,
      decDegrees: target.coordinates.dec,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = TargetQueueDragPayload(
      queuedTarget: target,
      node: _buildNode(),
    );

    final card = _RowCard(
      colors: colors,
      target: target,
      visibility: visibility,
      onAddPressed: canEdit ? () => _addToSequence(context, ref) : null,
      onRemovePressed: () =>
          ref.read(targetQueueProvider.notifier).removeTarget(target.id),
    );

    if (!canEdit) {
      // While the sequencer is running we still let the user see the
      // queue but block the drag handle. The remove button stays live
      // because the queue is independent of the sequence (per the
      // brief — the queue is a wishlist).
      return Opacity(opacity: 0.75, child: card);
    }

    return LongPressDraggable<TargetQueueDragPayload>(
      data: payload,
      delay: const Duration(milliseconds: 150),
      hapticFeedbackOnStart: true,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: _dragFeedbackWidth(context),
          child: TargetHeaderCard(
            node: payload.node,
            colors: colors,
            isSelected: false,
            nodeStatus: null,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }

  Future<void> _addToSequence(BuildContext context, WidgetRef ref) async {
    final node = _buildNode();
    final added = await addTargetHeaderWithPrompt(
      context: context,
      ref: ref,
      targetNode: node,
    );
    if (added && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${target.displayName} to sequence')),
      );
    }
  }
}

/// The visual card for a queue row — extracted so the same widget can
/// render both the actual list item and the drag-feedback ghost.
class _RowCard extends StatelessWidget {
  final NightshadeColors colors;
  final QueuedTarget target;
  final _TargetVisibility? visibility;
  final VoidCallback? onAddPressed;
  final VoidCallback? onRemovePressed;

  const _RowCard({
    required this.colors,
    required this.target,
    required this.visibility,
    required this.onAddPressed,
    required this.onRemovePressed,
  });

  @override
  Widget build(BuildContext context) {
    final v = visibility;
    final altText = v == null
        ? '—'
        : v.neverRises
            ? 'never rises'
            : '${v.altitudeDeg.toStringAsFixed(0)}°';
    final transitText = v?.transitAltitudeDeg == null
        ? '—'
        : '${v!.transitAltitudeDeg!.toStringAsFixed(0)}°';
    final setText = v?.setTime == null
        ? (v?.isCircumpolar == true ? 'never sets' : '—')
        : _formatTimeRemaining(v!.setTime!);

    final coordsText =
        'RA ${_formatHours(target.coordinates.ra)}  Dec ${_formatDegrees(target.coordinates.dec)}';

    final accent = target.isActive ? colors.primary : colors.border;
    return Container(
      decoration: BoxDecoration(
        color: target.isActive
            ? colors.primary.withValues(alpha: 0.06)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: accent),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 12, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  target.displayName,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onAddPressed != null)
                Tooltip(
                  message: 'Add to sequence',
                  child: InkWell(
                    onTap: onAddPressed,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(LucideIcons.plus,
                          size: 13, color: colors.primary),
                    ),
                  ),
                ),
              if (onRemovePressed != null)
                Tooltip(
                  message: 'Remove from queue',
                  child: InkWell(
                    onTap: onRemovePressed,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(LucideIcons.x,
                          size: 13, color: colors.textMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            coordsText,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              color: colors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Stat(
                colors: colors,
                label: 'Alt',
                value: altText,
                highlight: v?.aboveHorizon ?? false,
              ),
              const SizedBox(width: 8),
              _Stat(
                colors: colors,
                label: 'Max',
                value: transitText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  colors: colors,
                  label: 'Sets',
                  value: setText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatHours(double ra) {
    final h = ra.floor();
    final m = ((ra - h) * 60).floor();
    return '${h.toString().padLeft(2, '0')}h${m.toString().padLeft(2, '0')}m';
  }

  static String _formatDegrees(double dec) {
    final sign = dec >= 0 ? '+' : '-';
    final absDec = dec.abs();
    final d = absDec.floor();
    final m = ((absDec - d) * 60).floor();
    return '$sign${d.toString().padLeft(2, '0')}°${m.toString().padLeft(2, '0')}\'';
  }

  static String _formatTimeRemaining(DateTime when) {
    final now = DateTime.now();
    final diff = when.difference(now);
    if (diff.isNegative) return 'set';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}

class _Stat extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final bool highlight;

  const _Stat({
    required this.colors,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize8,
            color: colors.textMuted,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: NightshadeTypography.labelStrongSm
              .copyWith(color: highlight ? colors.primary : colors.textPrimary),
        ),
      ],
    );
  }
}
