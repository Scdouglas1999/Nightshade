import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    show CatalogManager, CatalogSearchResult;
import 'package:nightshade_ui/nightshade_ui.dart';

/// Mount tab — phone-native mount control:
///   * Live RA/Dec/Alt/Az from `mountStateProvider`.
///   * Press-and-hold d-pad (port of the §2.7 web dashboard pattern).
///   * Park/unpark + tracking on/off.
///   * Slew-to-target by NGC/IC/Messier name or manual RA/Dec.
///
/// All hardware calls go through `DeviceService` — this widget is pure UI
/// with the d-pad lifecycle (pointer capture, axis stop on release) as the
/// only stateful piece.
class MountTab extends ConsumerStatefulWidget {
  const MountTab({super.key});

  @override
  ConsumerState<MountTab> createState() => _MountTabState();
}

class _MountTabState extends ConsumerState<MountTab> {
  /// Slew rate multiplier (deg/s) — mirrors the desktop dashboard's
  /// 0.5×/1×/2×/4×/8× preset menu.
  double _slewRate = 2.0;

  /// Track which axis is currently held down so we can issue the matching
  /// stop on pointer release, matching §2.7 ("release == stop, no implicit
  /// timeout"). Map of axis → direction.
  final Map<int, int> _activeAxes = {};

  /// Cached device id so the dispose hook can stop motion without
  /// re-reading the provider (provider may already be disposed).
  String? _lastDeviceId;

  Future<void> _startMove(int axis, int direction) async {
    final state = ref.read(mountStateProvider);
    if (state.connectionState != DeviceConnectionState.connected) {
      _showMessage('Mount not connected');
      return;
    }
    final id = state.deviceId;
    if (id == null) return;
    _lastDeviceId = id;
    _activeAxes[axis] = direction;
    final backend = ref.read(backendProvider);
    try {
      await backend.mountMoveAxis(id, axis, _slewRate * direction);
    } catch (e) {
      developer.log('mountMoveAxis failed: $e', name: 'MountTab', level: 1000);
      if (mounted) _showMessage('Slew failed: $e');
    }
  }

  Future<void> _stopMove(int axis) async {
    if (!_activeAxes.containsKey(axis)) return;
    _activeAxes.remove(axis);
    final id = _lastDeviceId;
    if (id == null) return;
    final backend = ref.read(backendProvider);
    try {
      await backend.mountMoveAxis(id, axis, 0.0);
    } catch (e) {
      developer.log('mountMoveAxis(0) failed: $e',
          name: 'MountTab', level: 1000);
    }
  }

  Future<void> _stopAll() async {
    // Always stop both axes regardless of which one we think we started;
    // the pointer-leave handler can drop in mid-call and we don't want a
    // runaway slew sitting on the hardware.
    await _stopMove(0);
    await _stopMove(1);
    try {
      await ref.read(deviceServiceProvider).abortMountSlew();
    } catch (e) {
      if (mounted) _showMessage('Stop failed: $e');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    // Safety: if the tab is disposed mid-slew, kill both axes. Without
    // this the user can navigate away with the mount still moving. We
    // capture the device id and backend reference at start time because
    // reading providers in dispose isn't always safe.
    final id = _lastDeviceId;
    if (id != null && _activeAxes.isNotEmpty) {
      try {
        final backend = ref.read(backendProvider);
        backend.mountMoveAxis(id, 0, 0.0).ignore();
        backend.mountMoveAxis(id, 1, 0.0).ignore();
      } catch (e) {
        developer.log('Mount stop on dispose failed: $e',
            name: 'MountTab', level: 1000);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mountStateProvider);
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    if (state.connectionState != DeviceConnectionState.connected) {
      return const EmptyState(
        icon: LucideIcons.move,
        title: 'Mount not connected',
        body: 'Connect the mount from the Devices tab to enable slew '
            'controls and tracking.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PositionCard(state: state, colors: colors),
        const SizedBox(height: 16),
        _SlewRateSelector(
          value: _slewRate,
          onChanged: (v) => setState(() => _slewRate = v),
        ),
        const SizedBox(height: 16),
        _Dpad(
          enabled: !state.isParked,
          onStart: _startMove,
          onStop: _stopMove,
          onStopAll: _stopAll,
        ),
        const SizedBox(height: 16),
        _ControlsRow(state: state),
        const SizedBox(height: 16),
        const _SlewToTarget(),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  final MountState state;
  final NightshadeColors colors;
  const _PositionCard({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final ra = state.ra;
    final dec = state.dec;
    final alt = state.altitude;
    final az = state.azimuth;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: 'RA',
                  value: ra != null ? _formatRa(ra) : '—',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  label: 'Dec',
                  value: dec != null ? _formatDec(dec) : '—',
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: 'Alt',
                  value: alt != null ? '${alt.toStringAsFixed(1)}°' : '—',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  label: 'Az',
                  value: az != null ? '${az.toStringAsFixed(1)}°' : '—',
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(
                label: state.isParked ? 'Parked' : 'Unparked',
                color: state.isParked ? colors.warning : colors.success,
              ),
              _StatusBadge(
                label: state.isTracking ? 'Tracking' : 'Idle',
                color: state.isTracking ? colors.success : colors.textMuted,
              ),
              if (state.isSlewing)
                _StatusBadge(label: 'Slewing', color: colors.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  const _MetricCell({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: colors.textMuted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontFamily: 'monospace',
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SlewRateSelector extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _SlewRateSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    const options = <(double, String)>[
      (0.5, '0.5×'),
      (1.0, '1×'),
      (2.0, '2×'),
      (4.0, '4×'),
      (8.0, '8×'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slew rate',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final opt in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _RateChip(
                      label: opt.$2,
                      selected: value == opt.$1,
                      onTap: () => onChanged(opt.$1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        // 44 pt tap height.
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceAlt,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.background : colors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Press-and-hold d-pad. Each direction starts a slew on pointer down and
/// stops it on pointer up / leave / cancel. Mirrors §2.7 of the web
/// dashboard so the runaway-slew failure mode (start without matching
/// stop) cannot occur on a phone either.
class _Dpad extends StatelessWidget {
  final bool enabled;
  final Future<void> Function(int axis, int direction) onStart;
  final Future<void> Function(int axis) onStop;
  final Future<void> Function() onStopAll;

  const _Dpad({
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onStopAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Press and hold to slew',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(child: SizedBox.shrink()),
              Expanded(
                child: _DpadButton(
                  icon: LucideIcons.arrowUp,
                  label: 'North',
                  enabled: enabled,
                  axis: 1,
                  direction: 1,
                  onStart: onStart,
                  onStop: onStop,
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _DpadButton(
                  icon: LucideIcons.arrowLeft,
                  label: 'West',
                  enabled: enabled,
                  axis: 0,
                  direction: -1,
                  onStart: onStart,
                  onStop: onStop,
                ),
              ),
              Expanded(
                child: _StopButton(onPressed: onStopAll),
              ),
              Expanded(
                child: _DpadButton(
                  icon: LucideIcons.arrowRight,
                  label: 'East',
                  enabled: enabled,
                  axis: 0,
                  direction: 1,
                  onStart: onStart,
                  onStop: onStop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(child: SizedBox.shrink()),
              Expanded(
                child: _DpadButton(
                  icon: LucideIcons.arrowDown,
                  label: 'South',
                  enabled: enabled,
                  axis: 1,
                  direction: -1,
                  onStart: onStart,
                  onStop: onStop,
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }
}

class _DpadButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final int axis;
  final int direction;
  final Future<void> Function(int axis, int direction) onStart;
  final Future<void> Function(int axis) onStop;

  const _DpadButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.axis,
    required this.direction,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<_DpadButton> createState() => _DpadButtonState();
}

class _DpadButtonState extends State<_DpadButton> {
  bool _pressed = false;

  void _start() {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    widget.onStart(widget.axis, widget.direction);
  }

  void _stop() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onStop(widget.axis);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final bg = !widget.enabled
        ? colors.surfaceAlt
        : (_pressed ? colors.primary : colors.surfaceElevated);
    final fg = !widget.enabled
        ? colors.textMuted
        : (_pressed ? colors.background : colors.textPrimary);
    return Semantics(
      label: 'Slew ${widget.label}, hold to move',
      button: true,
      enabled: widget.enabled,
      child: Listener(
        // Listener (vs GestureDetector) is what guarantees we get a
        // pointer-up event even when the finger drifts to a sibling — the
        // hit-target is the pointer's initial widget. We additionally
        // listen for pointer-cancel to recover from system pre-empts
        // (notification shade pulled down, etc.).
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: Container(
          height: 72,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 28, color: fg),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  final Future<void> Function() onPressed;
  const _StopButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => onPressed(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: colors.error,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'STOP',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlsRow extends ConsumerWidget {
  final MountState state;
  const _ControlsRow({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(deviceServiceProvider);

    Future<void> guard(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: state.isParked ? 'Unpark' : 'Park',
            icon: state.isParked ? LucideIcons.unlock : LucideIcons.lock,
            size: ButtonSize.large,
            variant: ButtonVariant.outline,
            onPressed: () => guard(() async {
              if (state.isParked) {
                await service.unparkMount();
              } else {
                await service.parkMount();
              }
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NightshadeButton(
            label: state.isTracking ? 'Tracking on' : 'Tracking off',
            icon: state.isTracking ? LucideIcons.zap : LucideIcons.zapOff,
            size: ButtonSize.large,
            variant: state.isTracking
                ? ButtonVariant.primary
                : ButtonVariant.outline,
            onPressed: () =>
                guard(() => service.setMountTracking(!state.isTracking)),
          ),
        ),
      ],
    );
  }
}

class _SlewToTarget extends ConsumerStatefulWidget {
  const _SlewToTarget();

  @override
  ConsumerState<_SlewToTarget> createState() => _SlewToTargetState();
}

class _SlewToTargetState extends ConsumerState<_SlewToTarget> {
  final _nameCtrl = TextEditingController();
  final _raCtrl = TextEditingController();
  final _decCtrl = TextEditingController();
  List<CatalogSearchResult> _hits = [];
  bool _searching = false;
  bool _slewing = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _raCtrl.dispose();
    _decCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _nameCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final hits = await CatalogManager.instance.search(q);
      if (!mounted) return;
      setState(() => _hits = hits.take(8).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _slewToHit(CatalogSearchResult hit) async {
    // Catalog gives degrees; mountSlewToCoordinates expects RA hours.
    final raHours = hit.ra / 15.0;
    await _slewRaDec(raHours, hit.dec, label: hit.name);
  }

  Future<void> _slewManual() async {
    final ra = CoordinateParser.parseRa(_raCtrl.text);
    final dec = CoordinateParser.parseDec(_decCtrl.text);
    if (ra == null || dec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid RA or Dec')),
      );
      return;
    }
    await _slewRaDec(ra, dec, label: 'RA $ra / Dec $dec');
  }

  Future<void> _slewRaDec(double raHours, double decDeg,
      {required String label}) async {
    setState(() => _slewing = true);
    try {
      await ref
          .read(deviceServiceProvider)
          .slewMountToCoordinates(raHours, decDeg);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Slewing to $label')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Slew failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _slewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slew to target',
            style: TextStyle(
              fontSize: 14,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // Name lookup
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Target name (e.g. M31, NGC 7000)',
              prefixIcon: const Icon(LucideIcons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: colors.surfaceAlt,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: _searching ? 'Searching…' : 'Look up',
              icon: LucideIcons.search,
              size: ButtonSize.large,
              variant: ButtonVariant.outline,
              isLoading: _searching,
              onPressed: _searching ? null : _search,
            ),
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._hits.map((h) => _HitTile(
                  hit: h,
                  busy: _slewing,
                  onSlew: () => _slewToHit(h),
                )),
          ],
          const SizedBox(height: 16),
          Divider(color: colors.border),
          const SizedBox(height: 8),
          Text('Or enter coordinates manually',
              style: TextStyle(fontSize: 12, color: colors.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _raCtrl,
                  decoration: InputDecoration(
                    labelText: 'RA',
                    hintText: '00h42m44s',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceAlt,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _decCtrl,
                  decoration: InputDecoration(
                    labelText: 'Dec',
                    hintText: '+41°16\'',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceAlt,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: 'Slew to coordinates',
              icon: LucideIcons.target,
              size: ButtonSize.large,
              isLoading: _slewing,
              onPressed: _slewing ? null : _slewManual,
            ),
          ),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  final CatalogSearchResult hit;
  final bool busy;
  final VoidCallback onSlew;
  const _HitTile({
    required this.hit,
    required this.busy,
    required this.onSlew,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${hit.type}  ${_formatRa(hit.ra / 15.0)}  ${_formatDec(hit.dec)}',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          NightshadeButton(
            label: 'Slew',
            size: ButtonSize.small,
            onPressed: busy ? null : onSlew,
          ),
        ],
      ),
    );
  }
}

String _formatRa(double raHours) {
  final h = raHours.floor();
  final m = ((raHours - h) * 60).floor();
  final s = (((raHours - h) * 60 - m) * 60).round();
  return '${h.toString().padLeft(2, '0')}h'
      '${m.toString().padLeft(2, '0')}m'
      '${s.toString().padLeft(2, '0')}s';
}

String _formatDec(double decDeg) {
  final sign = decDeg >= 0 ? '+' : '-';
  final a = decDeg.abs();
  final d = a.floor();
  final m = ((a - d) * 60).round();
  return '$sign${d.toString().padLeft(2, '0')}°${m.toString().padLeft(2, '0')}\'';
}
