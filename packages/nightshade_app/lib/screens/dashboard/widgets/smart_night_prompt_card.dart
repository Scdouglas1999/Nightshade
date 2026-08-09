import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/shell/shell_chrome.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../sequencer/widgets/smart_night_dialog.dart';
import 'glass_card.dart';

const double _kDesktopPromptWidth = 480.0;
const double _kBottomInset = 16.0;
const double _kMobileHorizontalMargin = 16.0;
const Duration _kSlideInDuration = Duration(milliseconds: 240);

final smartNightPromptGraceProvider =
    Provider<Duration>((ref) => const Duration(seconds: 60));

/// Wall-clock source for the equipment-ready grace window, injectable so tests
/// can advance time without sleeping.
///
/// This MUST stay a *function*. It was a plain `Provider` of a `DateTime`
/// — a non-autoDispose provider, so the single `DateTime.now()`
/// captured on first read was cached for the life of the container. Every later
/// read returned that same instant, `now.difference(_equipmentReadySince)` was
/// permanently `Duration.zero`, the grace never elapsed, and the prompt was
/// invisible forever even with the setting on and every precondition met.
final smartNightPromptClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Whether the floating Smart Night auto-prompt is actually on screen right now.
/// [SmartNightPromptCard] publishes its real rendered visibility here (including
/// the equipment-ready grace and the pending-draft check) so other surfaces —
/// e.g. the cockpit standby header — can suppress a duplicate "Plan Tonight"
/// affordance while the prompt occupies the screen. Defaults to false.
final smartNightAutoPromptShowingProvider = StateProvider<bool>((ref) => false);

final smartNightEquipmentReadyProvider = Provider<bool>((ref) {
  final profile = ref.watch(activeEquipmentProfileProvider);
  if (profile == null) return false;
  final focalLength = profile.focalLength > 0
      ? profile.focalLength
      : (profile.telescopeFocalLength ?? 0);
  final aperture = profile.aperture > 0
      ? profile.aperture
      : (profile.telescopeAperture ?? 0);
  return focalLength > 0 && aperture > 0;
});

final _smartNightPromptDismissedDaysProvider =
    StateProvider<Set<String>>((ref) => <String>{});

class SmartNightPromptCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const SmartNightPromptCard({super.key, required this.colors});

  @override
  ConsumerState<SmartNightPromptCard> createState() =>
      _SmartNightPromptCardState();
}

class _SmartNightPromptCardState extends ConsumerState<SmartNightPromptCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  bool _busy = false;
  DateTime? _equipmentReadySince;
  Timer? _graceTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _kSlideInDuration,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  /// Publish the prompt's real rendered visibility after the frame settles, so
  /// reading widgets (the standby header) rebuild without mutating provider
  /// state mid-build.
  void _publishShowing(bool showing) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(smartNightAutoPromptShowingProvider.notifier);
      if (notifier.state != showing) notifier.state = showing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(activeEquipmentProfileProvider);
    final location = ref.watch(appObserverLocationProvider);
    final autoPromptEnabled = ref
            .watch(appSettingsProvider)
            .valueOrNull
            ?.smartNightAutoPromptEnabled ??
        false;
    final sequenceActive =
        _sequenceIsActive(ref.watch(sequenceExecutionStateProvider));
    final equipmentReady = ref.watch(smartNightEquipmentReadyProvider);
    final readyGraceElapsed = _equipmentReadyGraceElapsed(equipmentReady);
    final dayKey = _astronomicalDayKey(DateTime.now());
    final dismissedDays = ref.watch(_smartNightPromptDismissedDaysProvider);
    final persistedDismissedKey = ref
            .watch(appSettingsProvider)
            .valueOrNull
            ?.smartNightPromptDismissedDayKey ??
        '';

    final canPlan = equipmentReady &&
        readyGraceElapsed &&
        profile != null &&
        location != null &&
        !(location.latitude == 0.0 && location.longitude == 0.0);
    final baseShouldShow = canPlan &&
        autoPromptEnabled &&
        !sequenceActive &&
        !dismissedDays.contains(dayKey) &&
        persistedDismissedKey != dayKey;

    if (!baseShouldShow) {
      _animController.value = 0.0;
      _publishShowing(false);
      return const SizedBox.shrink();
    }

    final lookup = SmartNightDraftLookup(
      profileId: profile.id?.toString() ?? profile.name,
      astronomicalDay: _astronomicalDay(DateTime.now()),
    );
    final draftAsync = ref.watch(pendingSmartNightDraftProvider(lookup));
    if (draftAsync.isLoading || draftAsync.valueOrNull != null) {
      _animController.value = 0.0;
      _publishShowing(false);
      return const SizedBox.shrink();
    }

    _publishShowing(true);
    if (!_animController.isAnimating && _animController.value < 1.0) {
      _animController.forward();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < BreakpointTokens.breakpointPhone;
        final cardWidth = isMobile
            ? constraints.maxWidth - (_kMobileHorizontalMargin * 2)
            : _kDesktopPromptWidth;
        final useBottomNav =
            ShellChrome.useBottomNavigation(constraints.maxWidth);

        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: ShellChromeMetrics.floatingOverlayBottomInset(
                context,
                useBottomNav: useBottomNav,
                margin: _kBottomInset,
              ),
              left: _kMobileHorizontalMargin,
              right: _kMobileHorizontalMargin,
            ),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: SizedBox(
                  width: cardWidth,
                  child: _buildCard(context, lookup),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    SmartNightDraftLookup lookup,
  ) {
    final colors = widget.colors;
    return DashboardGlassCard(
      colors: colors,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hardware ready - build tonight\'s plan?',
                  style: NightshadeTypography.h5.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _OverflowMenuButton(colors: colors, onSelected: _onMenuSelected),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              'Smart Night will choose targets, exposures, and filters '
              'from your gear and the sky tonight.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11_5,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              NightshadeButton(
                label: 'Not now',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: _busy ? null : _dismissToday,
              ),
              const SizedBox(width: 8),
              NightshadeButton(
                label: 'Plan Tonight',
                icon: LucideIcons.sparkles,
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                isLoading: _busy,
                onPressed: _busy ? null : () => _openPlanner(lookup),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPlanner(SmartNightDraftLookup lookup) async {
    setState(() => _busy = true);
    try {
      await showSmartNightDialog(context);
      ref.invalidate(pendingSmartNightDraftProvider(lookup));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onMenuSelected(_PromptMenuAction action) {
    switch (action) {
      case _PromptMenuAction.dismissToday:
        _dismissToday();
      case _PromptMenuAction.disableOnConnect:
        ref
            .read(appSettingsProvider.notifier)
            .setSmartNightAutoPromptEnabled(false);
    }
  }

  void _dismissToday() {
    final dayKey = _astronomicalDayKey(DateTime.now());
    ref.read(_smartNightPromptDismissedDaysProvider.notifier).update(
          (days) => {...days, dayKey},
        );
    ref
        .read(appSettingsProvider.notifier)
        .setSmartNightPromptDismissedDayKey(dayKey);
  }

  bool _equipmentReadyGraceElapsed(bool equipmentReady) {
    if (!equipmentReady) {
      _equipmentReadySince = null;
      _graceTimer?.cancel();
      _graceTimer = null;
      return false;
    }

    final now = ref.watch(smartNightPromptClockProvider)();
    final grace = ref.watch(smartNightPromptGraceProvider);
    _equipmentReadySince ??= now;
    if (grace <= Duration.zero) {
      _graceTimer?.cancel();
      _graceTimer = null;
      return true;
    }

    final elapsed = now.difference(_equipmentReadySince!);
    if (elapsed >= grace) {
      _graceTimer?.cancel();
      _graceTimer = null;
      return true;
    }

    final remaining = grace - elapsed;
    // Clearing the handle from inside the callback is what lets the wake-up
    // RE-ARM. A fired Timer stays non-null, so the `??=` below would never
    // schedule another one and a rebuild that still fell short of the grace
    // would leave the card with nothing left to wake it.
    _graceTimer ??= Timer(remaining, () {
      _graceTimer = null;
      if (mounted) setState(() {});
    });
    return false;
  }
}

enum _PromptMenuAction { dismissToday, disableOnConnect }

class _OverflowMenuButton extends StatelessWidget {
  final NightshadeColors colors;
  final ValueChanged<_PromptMenuAction> onSelected;

  const _OverflowMenuButton({
    required this.colors,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PromptMenuAction>(
      tooltip: 'Prompt options',
      icon: Icon(LucideIcons.moreVertical, size: 16, color: colors.textMuted),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _PromptMenuAction.dismissToday,
          child: Text('Hide for tonight'),
        ),
        PopupMenuItem(
          value: _PromptMenuAction.disableOnConnect,
          child: Text("Don't ask again on connect"),
        ),
      ],
    );
  }
}

DateTime _astronomicalDay(DateTime now) {
  final local = now.toLocal();
  final day = local.hour < 12 ? local.subtract(const Duration(days: 1)) : local;
  return DateTime.utc(day.year, day.month, day.day);
}

bool _sequenceIsActive(SequenceExecutionState state) {
  switch (state) {
    case SequenceExecutionState.idle:
    case SequenceExecutionState.completed:
    case SequenceExecutionState.failed:
      return false;
    case SequenceExecutionState.running:
    case SequenceExecutionState.paused:
    case SequenceExecutionState.stopping:
    case SequenceExecutionState.recovering:
    // A failed stop (hardware possibly still imaging), a pending cleanup, or an
    // in-flight finalization are all "active" — Smart Night must not prompt to
    // launch over a run that has not settled.
    case SequenceExecutionState.stopFailed:
    case SequenceExecutionState.cleanupFailed:
    case SequenceExecutionState.finalizing:
      return true;
  }
}

String _astronomicalDayKey(DateTime now) {
  final day = _astronomicalDay(now);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}
