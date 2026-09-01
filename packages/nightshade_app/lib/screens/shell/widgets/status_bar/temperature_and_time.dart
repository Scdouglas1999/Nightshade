part of '../status_bar.dart';

/// Small indicator showing temp comp status next to focus pill.
/// Only visible when the focuser is connected and has temperature data.
class _TempCompIndicator extends ConsumerWidget {
  final NightshadeColors colors;
  final NightshadeLocalizations l10n;

  const _TempCompIndicator({required this.colors, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focuserState = ref.watch(focuserStateProvider);
    final focuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;

    // Only show when focuser is connected and reports temperature
    if (!focuserConnected || focuserState.temperature == null) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final tempCompEnabled = settings?.tempCompensation ?? false;

    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) return const SizedBox.shrink();

    final profileId = activeProfile.id.toString();
    final focusService = ref.watch(focusModelServiceProvider);
    final profileData = focusService.getProfileData(profileId);
    final model = profileData?.temperatureModel;
    final hasReliableModel = model != null && model.isReliable;

    // Determine state
    Color indicatorColor;
    String tooltip;

    if (!tempCompEnabled) {
      indicatorColor = colors.textMuted;
      tooltip = l10n.text('statusTempCompOff');
    } else if (!hasReliableModel) {
      indicatorColor = colors.warning;
      tooltip = model == null
          ? l10n.text('statusTempCompNoModel')
          : l10n.text(
              'statusTempCompUnreliable',
              params: {'r2': model.rSquared.toStringAsFixed(2)},
            );
    } else {
      final prediction = focusService.predictFocusPosition(
        profileId: profileId,
        currentTemperature: focuserState.temperature!,
      );
      indicatorColor = colors.success;
      final slope = model.slope.toStringAsFixed(1);
      tooltip = prediction != null
          ? l10n.text(
              'statusTempCompActive',
              params: {
                'slope': slope,
                'position': prediction.position.toString(),
              },
            )
          : l10n.text(
              'statusTempCompActiveNoPrediction',
              params: {'slope': slope},
            );
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: NightshadeDecorations.tintedBadge(
          indicatorColor,
          borderRadius: NightshadeTokens.borderRadiusInline4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.thermometerSun, size: 10, color: indicatorColor),
            const SizedBox(width: 3),
            Text(
              'TC',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize9,
                fontWeight: FontWeight.w600,
                color: indicatorColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the operator has actually given us an observing site.
///
/// 0/0 is the app's documented "not set" sentinel — see `locationSyncProvider`,
/// which deliberately refuses to guess a site. Every location-driven surface is
/// supposed to have an honest empty state for it.
@visibleForTesting
bool siteLocationIsSet(double latitude, double longitude) =>
    latitude != 0.0 || longitude != 0.0;

/// The LST chip's text.
///
/// `lstHours` is null when there is no site to compute it for.
///
/// A precise "LST 21:14" for a site the operator never gave is worse than no
/// LST: sidereal time is exactly what you read to decide what is transiting.
@visibleForTesting
String formatLstChip(double? lstHours) {
  if (lstHours == null) return 'LST --:--';
  // Normalized to [0, 24) upstream; fold defensively so a bad input can never
  // render as "-1:-30".
  var hours = lstHours % 24;
  if (hours < 0) hours += 24;
  final h = hours.floor();
  final m = ((hours - h) * 60).floor();
  return 'LST ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Wall-clock and LST chip that owns its per-second tick.
///
/// Owning the tick here scopes the per-second rebuild to this chip; on
/// `_StatusBarState` one `setState` a second rebuilds every device pill, both
/// action buttons and the enclosing `LayoutBuilder` to move one digit.
/// `status_bar_idle_repaint_test.dart` pins it via Flutter's rebuild tracer.
///
/// The [RepaintBoundary] below is insurance against this chip dirtying the bar,
/// NOT a measured saving: Flutter's Linux embedder submits a full-window frame
/// regardless of damage.
///
/// Ticking stops while the app is backgrounded.
class _TimeDisplay extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _TimeDisplay({required this.colors});

  @override
  ConsumerState<_TimeDisplay> createState() => _TimeDisplayState();
}

class _TimeDisplayState extends ConsumerState<_TimeDisplay>
    with WidgetsBindingObserver {
  AlignedTicker? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // Aligned to the wall-clock second so this tick shares its frame with the
    // planetarium's two 1 Hz clocks rather than costing a full-window frame of
    // its own. It also makes the displayed second change *on* the second.
    // See [AlignedTicker].
    _timer = AlignedTicker(const Duration(seconds: 1), () {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_timer == null || !_timer!.isActive) {
        // Resync immediately so the clock doesn't show a stale time.
        _now = DateTime.now();
        _startTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final now = _now;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final siteIsSet = settings != null &&
        siteLocationIsSet(settings.latitude, settings.longitude);
    // Only read the LST once we know whose LST it is.
    final lst = siteIsSet ? ref.watch(localSiderealTimeProvider) : null;
    final l10n = context.l10n;
    final lstTooltip = settings == null
        ? l10n.text('statusLstLoading')
        : siteIsSet
            ? l10n.text('statusLstTooltip')
            : l10n.text('statusLstNoSite');
    // Settings → Location → Timezone was inert on the one clock that is on
    // screen from every page: this chip formatted the host's `DateTime.now()`
    // straight through, so a remote-observatory operator who set the site
    // offset saw the setting persist, the row's subtitle update, and this
    // clock keep the laptop's time. `Clock.fromUtc` re-expresses the SAME
    // instant in the chosen zone — the caller's timer still decides when the
    // chip reticks — and [SystemClock] leaves host-local users untouched.
    final displayNow = ref.watch(clockProvider).fromUtc(now.toUtc());
    final timeStr =
        '${displayNow.hour.toString().padLeft(2, '0')}:${displayNow.minute.toString().padLeft(2, '0')}:${displayNow.second.toString().padLeft(2, '0')}';

    // The boundary is the point of the exercise: without it, repainting one
    // digit marks the parent layer dirty and the whole window re-rasterises
    // once a second.
    return RepaintBoundary(
      child: Row(
        children: [
          Icon(
            NightshadeIcons.clock,
            size: 12,
            color: colors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: lstTooltip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: NightshadeDecorations.statusChip(
                // An unknown LST must not wear the confident accent colour.
                lst == null ? colors.textMuted : colors.primary,
                borderRadius: NightshadeTokens.borderRadiusInline4,
                bordered: false,
              ),
              child: Text(
                formatLstChip(lst),
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w500,
                  color: lst == null ? colors.textMuted : colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
