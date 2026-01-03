import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart'
    hide Phd2GuidingState, GuideErrorPoint;
import 'package:nightshade_ui/nightshade_ui.dart' as ui
    show Phd2GuidingState, GuideErrorPoint, GuideTargetDisplay, GuideControlsPanel;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show Phd2State;

/// Full PHD2 guiding interface screen
///
/// Provides comprehensive guiding control including:
/// - Star image view with crosshairs
/// - Target display (error history visualization)
/// - Advanced guiding graph with configurable scales
/// - PHD2 Brain settings panel
/// - Calibration controls
/// - Full guiding controls
class GuidingScreen extends ConsumerStatefulWidget {
  const GuidingScreen({super.key});

  @override
  ConsumerState<GuidingScreen> createState() => _GuidingScreenState();
}

class _GuidingScreenState extends ConsumerState<GuidingScreen> {
  GraphTimeScale _timeScale = GraphTimeScale.fiveMinutes;
  GraphYScale _yScale = GraphYScale.two;
  bool _showBrainPanel = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isConnected = ref.watch(phd2ConnectedProvider);
    final phd2State = ref.watch(phd2StateProvider);
    final guideStats = ref.watch(guideStatsProvider);

    // Initialize controller
    ref.watch(phd2ControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(colors, isConnected, phd2State, guideStats),
          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Left panel - Star view, Target display, Star stats
                  SizedBox(
                    width: 280,
                    child: _buildLeftPanel(colors, isConnected, guideStats),
                  ),
                  const SizedBox(width: 16),
                  // Center panel - Graph
                  Expanded(
                    child: _buildCenterPanel(colors, guideStats),
                  ),
                  const SizedBox(width: 16),
                  // Right panel - Controls
                  SizedBox(
                    width: 300,
                    child: _buildRightPanel(colors, isConnected, phd2State),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats guideStats,
  ) {
    final stateColor = _getStateColor(phd2State);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Connection status with glow effect
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? colors.success : colors.error,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? colors.success : colors.error).withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isConnected ? 'PHD2 Connected' : 'PHD2 Disconnected',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 20),
          // State indicator pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: stateColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stateColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStateLabel(phd2State),
                  style: TextStyle(
                    color: stateColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // RMS display
          if (phd2State == Phd2State.guiding) ...[
            _buildRmsChip('RA', guideStats.rmsRa, Colors.redAccent, colors),
            const SizedBox(width: 10),
            _buildRmsChip('Dec', guideStats.rmsDec, colors.info, colors),
            const SizedBox(width: 10),
            _buildRmsChip('Total', guideStats.rmsTotal, colors.primary, colors, bold: true),
            const SizedBox(width: 20),
          ],
          // Connect/Disconnect button
          if (!isConnected)
            NightshadeButton(
              label: 'Connect',
              icon: LucideIcons.plug,
              size: ButtonSize.small,
              onPressed: () => _connect(),
            )
          else
            NightshadeButton(
              label: 'Disconnect',
              icon: LucideIcons.plugZap,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => ref.read(phd2ControllerProvider).disconnect(),
            ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(LucideIcons.settings, color: colors.textSecondary, size: 18),
              onPressed: () => _showConnectionDialog(),
              tooltip: 'Connection Settings',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRmsChip(String label, double value, Color color, NightshadeColors colors, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          Text(
            '${value.toStringAsFixed(2)}"',
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(NightshadeColors colors, bool isConnected, Phd2GuideStats stats) {
    final starImage = ref.watch(starImageProvider);
    final errorHistory = ref.watch(targetDisplayHistoryProvider);
    final currentError = errorHistory.isNotEmpty ? errorHistory.last : null;

    return Column(
      children: [
        // Star view
        _buildGlassCard(
          colors,
          title: 'Guide Star',
          icon: LucideIcons.star,
          trailing: isConnected
              ? IconButton(
                  icon: Icon(LucideIcons.refreshCw, size: 14, color: colors.textSecondary),
                  onPressed: () => ref.read(starImageProvider.notifier).refresh(),
                  tooltip: 'Refresh',
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                )
              : null,
          child: AspectRatio(
            aspectRatio: 1,
            child: starImage.when(
              data: (image) => GuideStarView(
                pixels: image.pixels,
                width: image.width,
                height: image.height,
                starX: image.starX,
                starY: image.starY,
                snr: stats.snr,
                showCrosshairs: true,
                onStarSelected: isConnected ? (x, y) => _selectStar(x, y) : null,
                placeholderMessage: 'No star selected',
              ),
              loading: () => const GuideStarView(
                placeholderMessage: 'Waiting for image...',
              ),
              error: (_, __) => const GuideStarView(
                placeholderMessage: 'No star selected',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Target display
        _buildGlassCard(
          colors,
          title: 'Target Display',
          icon: LucideIcons.target,
          child: AspectRatio(
            aspectRatio: 1,
            child: ui.GuideTargetDisplay(
              errorHistory: errorHistory.map((e) => ui.GuideErrorPoint(
                raError: e.raError,
                decError: e.decError,
                timestamp: e.timestamp,
              )).toList(),
              currentRaError: currentError?.raError ?? 0,
              currentDecError: currentError?.decError ?? 0,
              scaleArcsec: _yScale.arcsec / 2,
              numRings: 3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Star stats - fixed height card instead of Expanded to prevent overflow
        _buildGlassCard(
          colors,
          title: 'Star Statistics',
          icon: LucideIcons.activity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow('SNR', stats.snr.toStringAsFixed(1), _getSnrColor(stats.snr, colors), colors),
              const SizedBox(height: 10),
              _buildStatRow('Star Mass', stats.starMass.toStringAsFixed(0), colors.textPrimary, colors),
              const SizedBox(height: 10),
              _buildStatRow('Frame Count', stats.frameCount.toString(), colors.textPrimary, colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard(
    NightshadeColors colors, {
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel(NightshadeColors colors, Phd2GuideStats stats) {
    final graphData = ref.watch(guideGraphProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(LucideIcons.lineChart, size: 14, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  'Guide Graph',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                // RMS display in header
                _buildCompactRms('RA', stats.rmsRa, Colors.redAccent, colors),
                const SizedBox(width: 12),
                _buildCompactRms('Dec', stats.rmsDec, colors.info, colors),
                const SizedBox(width: 12),
                _buildCompactRms('Total', stats.rmsTotal, colors.primary, colors, bold: true),
              ],
            ),
          ),
          // Graph content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GuideGraphAdvanced(
                data: graphData.map((p) => GuideDataPoint(
                  timestamp: p.time,
                  raError: p.ra,
                  decError: p.dec,
                )).toList(),
                timeScale: _timeScale,
                yScale: _yScale,
                rmsRa: stats.rmsRa,
                rmsDec: stats.rmsDec,
                rmsTotal: stats.rmsTotal,
                onTimeScaleChanged: (scale) => setState(() => _timeScale = scale),
                onYScaleChanged: (scale) => setState(() => _yScale = scale),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRms(String label, double value, Color color, NightshadeColors colors, {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        const SizedBox(width: 4),
        Text(
          '${value.toStringAsFixed(2)}"',
          style: TextStyle(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildRightPanel(NightshadeColors colors, bool isConnected, Phd2State phd2State) {
    final calibrationData = ref.watch(calibrationStateProvider);

    return Column(
      children: [
        // Controls panel
        Expanded(
          flex: 3,
          child: ui.GuideControlsPanel(
            state: _mapPhd2State(phd2State),
            isConnected: isConnected,
            onStartGuiding: () => ref.read(phd2ControllerProvider).startGuiding(),
            onStopGuiding: () => ref.read(phd2ControllerProvider).stopGuiding(),
            onLoop: () => ref.read(phd2ControllerProvider).loop(),
            onFindStar: () => ref.read(lockPositionProvider.notifier).findStar(),
            onDeselectStar: () => _deselectStar(),
            onDither: () => ref.read(phd2ControllerProvider).dither(),
          ),
        ),
        const SizedBox(height: 12),
        // Calibration panel
        Expanded(
          flex: 2,
          child: CalibrationPanel(
            state: calibrationData.isCalibrated
                ? CalibrationState.calibrated
                : CalibrationState.notCalibrated,
            data: CalibrationData(
              hasCalibration: calibrationData.isCalibrated,
              raAngle: calibrationData.rotationAngle,
              decAngle: null, // Not separately available
              raRate: calibrationData.raRate,
              decRate: calibrationData.decRate,
            ),
            isConnected: isConnected,
            onClearCalibration: () => _clearCalibration(),
            onFlipCalibration: () => _flipCalibration(),
          ),
        ),
        const SizedBox(height: 12),
        // Brain settings toggle
        NightshadeButton(
          label: _showBrainPanel ? 'Hide Brain Settings' : 'Brain Settings',
          icon: LucideIcons.brain,
          variant: ButtonVariant.outline,
          onPressed: () => setState(() => _showBrainPanel = !_showBrainPanel),
        ),
        if (_showBrainPanel) ...[
          const SizedBox(height: 12),
          Expanded(
            flex: 3,
            child: _buildBrainPanel(colors),
          ),
        ],
      ],
    );
  }

  Widget _buildBrainPanel(NightshadeColors colors) {
    final brainParams = ref.watch(brainParamsProvider);

    return brainParams.when(
      data: (params) => BrainSettingsPanel(
        raParams: params.raParams.entries.map((e) => BrainParam(name: e.key, value: e.value)).toList(),
        decParams: params.decParams.entries.map((e) => BrainParam(name: e.key, value: e.value)).toList(),
        onParamChanged: (axis, name, value) {
          ref.read(brainParamsProvider.notifier).setParam(axis, name, value);
        },
        // setParam() already sends to PHD2, these are for UI only
        onApply: () {}, // Already applied when param changes
        onReset: () => ref.read(brainParamsProvider.notifier).fetch(),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load brain params', style: TextStyle(color: colors.error)),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color valueColor, NightshadeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w500, fontSize: 12)),
      ],
    );
  }

  Color _getSnrColor(double snr, NightshadeColors colors) {
    if (snr >= 10) return colors.success;
    if (snr >= 5) return colors.warning;
    return colors.error;
  }

  Color _getStateColor(Phd2State state) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    switch (state) {
      case Phd2State.stopped:
        return colors.textMuted;
      case Phd2State.looping:
        return colors.warning;
      case Phd2State.calibrating:
        return colors.warning;
      case Phd2State.guiding:
        return colors.success;
      case Phd2State.paused:
        return colors.info;
      case Phd2State.settling:
        return colors.info;
      case Phd2State.lostLock:
        return colors.error;
      default:
        return colors.textMuted;
    }
  }

  String _getStateLabel(Phd2State state) {
    switch (state) {
      case Phd2State.stopped:
        return 'Stopped';
      case Phd2State.looping:
        return 'Looping';
      case Phd2State.calibrating:
        return 'Calibrating';
      case Phd2State.guiding:
        return 'Guiding';
      case Phd2State.paused:
        return 'Paused';
      case Phd2State.settling:
        return 'Settling';
      case Phd2State.lostLock:
        return 'Lost Lock';
      default:
        return 'Unknown';
    }
  }

  ui.Phd2GuidingState _mapPhd2State(Phd2State state) {
    switch (state) {
      case Phd2State.stopped:
        return ui.Phd2GuidingState.stopped;
      case Phd2State.looping:
        return ui.Phd2GuidingState.looping;
      case Phd2State.calibrating:
        return ui.Phd2GuidingState.calibrating;
      case Phd2State.guiding:
        return ui.Phd2GuidingState.guiding;
      case Phd2State.paused:
        return ui.Phd2GuidingState.paused;
      case Phd2State.settling:
        return ui.Phd2GuidingState.settling;
      case Phd2State.lostLock:
        return ui.Phd2GuidingState.lostLock;
      default:
        return ui.Phd2GuidingState.disconnected;
    }
  }

  Future<void> _connect() async {
    final settings = await ref.read(appSettingsProvider.future);
    ref.read(phd2ControllerProvider).connect(settings.phd2Host, settings.phd2Port);
  }

  void _showConnectionDialog() async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settings = await ref.read(appSettingsProvider.future);
    final hostController = TextEditingController(text: settings.phd2Host);
    final portController = TextEditingController(text: settings.phd2Port.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('PHD2 Connection', style: TextStyle(color: colors.textPrimary)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Host',
                  labelStyle: TextStyle(color: colors.textMuted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: portController,
                style: TextStyle(color: colors.textPrimary),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Port',
                  labelStyle: TextStyle(color: colors.textMuted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final host = hostController.text;
              final port = int.tryParse(portController.text) ?? 4400;
              await ref.read(appSettingsProvider.notifier).setPhd2Host(host);
              await ref.read(appSettingsProvider.notifier).setPhd2Port(port);
              ref.read(phd2ControllerProvider).connect(host, port);
            },
            style: FilledButton.styleFrom(backgroundColor: colors.primary),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _selectStar(double x, double y) {
    ref.read(lockPositionProvider.notifier).setLockPosition(x, y);
  }

  void _deselectStar() {
    ref.read(lockPositionProvider.notifier).deselectStar();
  }

  void _clearCalibration() {
    ref.read(calibrationStateProvider.notifier).clearCalibration();
  }

  void _flipCalibration() {
    ref.read(calibrationStateProvider.notifier).flipCalibration();
  }
}
