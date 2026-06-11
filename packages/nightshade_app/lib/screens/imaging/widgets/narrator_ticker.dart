import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/narrator/narrator_card.dart';
import '../../../widgets/narrator/narrator_feed.dart';

/// One-line Night Narrator strip for the imaging screen, sitting near the
/// Science HUD.
///
/// Surface #2 of the Night Narrator (see `docs/night_narrator_design.md`). It
/// is the eyepiece-level glance at "the story of your night": the most recent
/// event headline with its category icon and severity accent, auto-advancing
/// through any events from the last ~10 minutes so a glance keeps up with what
/// just happened. Tapping opens a bottom sheet with the full [NarratorFeed].
///
/// Visibility mirrors the other imaging HUD chrome:
///   * Session id comes from [sessionStateProvider] (the same source
///     `SubQualityBadge` / the Science HUD use); when there is no DB session
///     the strip is hidden — captures on the imaging screen always run inside a
///     session, so a sessionless fallback would only ever be empty here.
///   * Like [SubQualityBadge] it renders [SizedBox.shrink] when there is
///     nothing honest to show — here, when the feed is empty — so the canvas
///     gains no idle clutter before the first insight fires.
///
/// Cost: the widget watches only the feed provider. A single [Timer] drives the
/// rotation (cancelled on dispose); relative-time labels refresh on the same
/// rotation cadence rather than a second timer.
class NarratorTicker extends ConsumerWidget {
  const NarratorTicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    // No session → nothing to narrate on the imaging canvas. (Captures here
    // always belong to a session, so the sessionless feed would be empty.)
    if (sessionId == null) return const SizedBox.shrink();

    final events = ref.watch(narratorFeedProvider(sessionId)).valueOrNull ??
        const <NarratorEvent>[];
    if (events.isEmpty) return const SizedBox.shrink();

    return _NarratorTickerView(sessionId: sessionId, events: events);
  }
}

/// The animated strip itself, separated from the provider watch so the rotation
/// [Timer] lives in a [State] without forcing the consumer to be stateful.
class _NarratorTickerView extends StatefulWidget {
  final int sessionId;
  final List<NarratorEvent> events;

  const _NarratorTickerView({required this.sessionId, required this.events});

  @override
  State<_NarratorTickerView> createState() => _NarratorTickerViewState();
}

class _NarratorTickerViewState extends State<_NarratorTickerView> {
  /// Events younger than this auto-advance in the rotation; older ones are
  /// pinned in only as the single resting headline once the recent ones drain.
  static const Duration _recentWindow = Duration(minutes: 10);

  /// How long each event holds the strip before advancing to the next.
  static const Duration _advanceInterval = Duration(seconds: 6);

  Timer? _timer;

  /// Index into [_rotation] of the event currently on screen.
  int _index = 0;

  /// The events eligible for auto-advance (recent, capped), newest/pinned
  /// first. Always at least one entry while the strip is visible.
  late List<NarratorEvent> _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = _buildRotation(widget.events);
    _restartTimer();
  }

  @override
  void didUpdateWidget(_NarratorTickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.events, widget.events)) {
      final next = _buildRotation(widget.events);
      // Keep the strip pinned to the newest event when fresh insight arrives so
      // the user sees the latest happening, rather than mid-rotation drift.
      final newestId = next.isEmpty ? null : next.first.id;
      final hadNewest = _rotation.isNotEmpty && _rotation.first.id == newestId;
      _rotation = next;
      if (!hadNewest) {
        _index = 0;
        _restartTimer();
      } else if (_index >= _rotation.length) {
        _index = 0;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The events that participate in the auto-advance rotation: those within
  /// [_recentWindow] of now, newest/pinned-first (the provider already orders
  /// the feed that way, so we keep its order). Capped so a long burst of events
  /// doesn't make the rotation crawl. Falls back to just the single newest
  /// event when nothing is recent, so the strip always rests on the latest.
  List<NarratorEvent> _buildRotation(List<NarratorEvent> events) {
    final now = DateTime.now();
    final recent = events
        .where((e) => now.difference(e.timestamp).abs() <= _recentWindow)
        .take(6)
        .toList(growable: false);
    if (recent.isNotEmpty) return recent;
    return events.isEmpty ? const <NarratorEvent>[] : [events.first];
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_rotation.length < 2) return;
    _timer = Timer.periodic(_advanceInterval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _rotation.length);
    });
  }

  Future<void> _openFeed() {
    final colors = NightshadeColors.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NightshadeTokens.radiusLg),
        ),
      ),
      builder: (sheetContext) =>
          _NarratorFeedSheet(sessionId: widget.sessionId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    if (_rotation.isEmpty) return const SizedBox.shrink();

    final index = _index.clamp(0, _rotation.length - 1);
    final event = _rotation[index];
    final accent = NarratorVisuals.accentFor(event.severity, colors);
    final icon = NarratorVisuals.iconFor(event.category);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: NightshadeTokens.opacityStrong),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _openFeed,
          borderRadius: NightshadeTokens.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thin severity dot leading the strip — the "subtle accent"
                // idiom, never a filled alarm box.
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: NightshadeTokens.durationNormal,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.25),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _TickerLine(
                      // Key by event id so the switcher animates only on a real
                      // advance, not on an unrelated rebuild.
                      key: ValueKey<int>(event.id),
                      event: event,
                      colors: colors,
                    ),
                  ),
                ),
                if (_rotation.length > 1) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  _CountChip(count: _rotation.length, colors: colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The headline + relative-time pair shown for the current event. Kept as its
/// own widget so the [AnimatedSwitcher] has a clean keyed child to transition.
class _TickerLine extends StatelessWidget {
  final NarratorEvent event;
  final NightshadeColors colors;

  const _TickerLine({super.key, required this.event, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            event.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          formatNarratorRelativeTime(event.timestamp),
          style: NightshadeTypography.withTabular(
            NightshadeTypography.labelQuiet.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Small "N" counter chip shown when more than one event is in rotation, so the
/// glance knows the strip is cycling through several recent happenings.
class _CountChip extends StatelessWidget {
  final int count;
  final NightshadeColors colors;

  const _CountChip({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$count',
        style: NightshadeTypography.withTabular(
          NightshadeTypography.labelQuiet.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// Bottom sheet host for the full session feed. Reuses the shared [NarratorFeed]
/// so the cards open their own detail sheets on tap. Capped height so the sheet
/// never swallows the whole screen on a tall feed.
class _NarratorFeedSheet extends ConsumerWidget {
  final int sessionId;

  const _NarratorFeedSheet({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final events = ref.watch(narratorFeedProvider(sessionId)).valueOrNull ??
        const <NarratorEvent>[];
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NightshadeTokens.spaceLg,
                NightshadeTokens.spaceMd,
                NightshadeTokens.spaceLg,
                NightshadeTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Icon(
                    NarratorVisuals.iconFor(NarratorCategory.discovery),
                    size: 16,
                    color: colors.accent,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Text(
                    'Night Narrator',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
            Flexible(
              child: NarratorFeed(
                events: events,
                padding: const EdgeInsets.fromLTRB(
                  NightshadeTokens.spaceLg,
                  0,
                  NightshadeTokens.spaceLg,
                  NightshadeTokens.spaceLg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
