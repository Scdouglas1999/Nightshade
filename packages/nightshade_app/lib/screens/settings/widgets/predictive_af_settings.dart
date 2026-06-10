// Wave 8 — Predictive autofocus settings + per-camera/filter model viewer.
//
// Lives next to the legacy `autofocus_settings.dart` so a user clicking the
// "Autofocus" entry in the side bar sees the new "Predictive" subsection
// underneath the existing AF tuning. The page consumes
// [PredictiveAfService] for the model data and listens to its
// [PredictiveAfService.driftEvents] stream so it can render an inline "Your
// Ha filter focus model has drifted by 1200 steps over the last 5 runs.
// Consider re-training" banner.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Hide nightshade_core's ConnectionState — Flutter's async.ConnectionState
// is what FutureBuilder needs in this file, and the two collide via the
// barrel. (See nightshade_core.dart re: device_types.dart.)
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

/// Settings page: "Autofocus → Predictive". Surfaces the auto-learn toggle,
/// the confidence thresholds, the drift-detection knobs, and a viewer that
/// lists every persisted per-filter model with re-train / export actions.
class PredictiveAfSettingsPage extends ConsumerStatefulWidget {
  final bool isMobile;

  const PredictiveAfSettingsPage({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<PredictiveAfSettingsPage> createState() =>
      _PredictiveAfSettingsPageState();
}

class _PredictiveAfSettingsPageState
    extends ConsumerState<PredictiveAfSettingsPage> {
  StreamSubscription<DriftStatus>? _driftSub;
  String? _latestDriftWarning;

  @override
  void initState() {
    super.initState();
    // We attach in the next frame because the service provider isn't
    // available until after `build()` runs once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachDriftListener());
  }

  void _attachDriftListener() {
    final service = ref.read(predictiveAfServiceProvider);
    _driftSub?.cancel();
    _driftSub = service.driftEvents.listen((status) {
      if (!mounted) return;
      if (status is ShouldWarn) {
        setState(() => _latestDriftWarning = status.message);
      }
    });
  }

  @override
  void dispose() {
    _driftSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(predictiveAfServiceProvider);
    final config = service.config;
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    return SettingsPage(
      title: 'Predictive Autofocus',
      description:
          'Learn per-filter focus/temperature slope across sessions and skip '
          'manual autofocus when the model is confident.',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        if (_latestDriftWarning != null)
          _DriftWarningBanner(
            message: _latestDriftWarning!,
            onDismiss: () => setState(() => _latestDriftWarning = null),
          ),
        SettingsSection(
          title: 'Gates',
          isMobile: widget.isMobile,
          children: [
            _settingRow(
              icon: LucideIcons.brainCircuit,
              title: 'Auto-learn focus models',
              subtitle: 'When enabled, each successful AF run appends a sample '
                  'to the matching (camera, filter) model and re-fits the '
                  'regression on every insert.',
              trailing: SettingsSwitch(
                value: config.enabled,
                onChanged: (value) => setState(() {
                  service.config = config.copyWith(enabled: value);
                }),
              ),
            ),
            _settingRow(
              icon: LucideIcons.barChart3,
              title: 'Minimum samples for trust',
              subtitle: 'Below this count, even a high-R² model still forces a '
                  'real AF sweep so the predictor cannot lock onto a tiny '
                  'sample window by coincidence.',
              trailing: _NumberField(
                initialValue: config.minSamplesForTrust.toDouble(),
                min: 3,
                max: 50,
                decimals: 0,
                onChanged: (v) => setState(() {
                  service.config = config.copyWith(
                    minSamplesForTrust: v.toInt(),
                  );
                }),
              ),
            ),
            _settingRow(
              icon: LucideIcons.checkCircle,
              title: 'High-confidence threshold (R²)',
              subtitle: 'R² ≥ this → apply prediction directly.',
              trailing: _NumberField(
                initialValue: config.highConfidenceThreshold,
                min: 0.5,
                max: 1.0,
                decimals: 2,
                onChanged: (v) => setState(() {
                  service.config = config.copyWith(
                    highConfidenceThreshold: v,
                  );
                }),
              ),
            ),
            _settingRow(
              icon: LucideIcons.alertCircle,
              title: 'Low-confidence threshold (R²)',
              subtitle: 'R² < this → force a real AF sweep.',
              trailing: _NumberField(
                initialValue: config.lowConfidenceThreshold,
                min: 0.0,
                max: 0.9,
                decimals: 2,
                onChanged: (v) => setState(() {
                  service.config = config.copyWith(
                    lowConfidenceThreshold: v,
                  );
                }),
              ),
            ),
            _settingRow(
              icon: LucideIcons.activity,
              title: 'Drift threshold (steps)',
              subtitle: 'How many focuser steps a prediction can be off before '
                  'counting as a "bad" run for drift tracking.',
              trailing: _NumberField(
                initialValue: config.driftThresholdSteps.toDouble(),
                min: 20,
                max: 2000,
                decimals: 0,
                onChanged: (v) => setState(() {
                  service.config = config.copyWith(
                    driftThresholdSteps: v.toInt(),
                  );
                }),
              ),
            ),
            _settingRow(
              icon: LucideIcons.alertTriangle,
              title: 'Bad runs before warning',
              subtitle: 'Consecutive bad predictions required before the app '
                  'surfaces a re-train notification.',
              trailing: _NumberField(
                initialValue: config.driftRunsBeforeWarn.toDouble(),
                min: 1,
                max: 20,
                decimals: 0,
                onChanged: (v) => setState(() {
                  service.config = config.copyWith(
                    driftRunsBeforeWarn: v.toInt(),
                  );
                }),
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Learned models',
          isMobile: widget.isMobile,
          children: [
            _ModelViewer(
              service: service,
              equipmentProfileId: activeProfile?.id,
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    bool isLast = false,
  }) {
    if (widget.isMobile) {
      return SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        isMobile: true,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }
}

class _DriftWarningBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _DriftWarningBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.warning,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, color: colors.warning, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            iconSize: 14,
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(LucideIcons.x, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Table-of-models viewer. Re-fetches from the DB on every build (driven by
/// `_refreshTrigger`) so post-action state always reflects what was just
/// written.
class _ModelViewer extends StatefulWidget {
  final PredictiveAfService service;
  final int? equipmentProfileId;

  const _ModelViewer({
    required this.service,
    required this.equipmentProfileId,
  });

  @override
  State<_ModelViewer> createState() => _ModelViewerState();
}

class _ModelViewerState extends State<_ModelViewer> {
  Future<List<FilterFocusModel>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(_ModelViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.equipmentProfileId != widget.equipmentProfileId) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = widget.service.listModels(
        equipmentProfileId: widget.equipmentProfileId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilterFocusModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final models = snapshot.data ?? const <FilterFocusModel>[];
        if (models.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(LucideIcons.info,
                    color: NightshadeColors.of(context).textMuted, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.equipmentProfileId == null
                        ? 'Activate an equipment profile to see its learned focus models.'
                        : 'No focus models have been learned for this profile yet. '
                            'Run autofocus across a few temperatures and they will '
                            'appear here.',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: NightshadeColors.of(context).textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: models
                .map((m) => _ModelRow(
                      model: m,
                      onClear: () async {
                        await widget.service.clearSamples(
                          equipmentProfileId: m.equipmentProfileId,
                          filterName: m.filterName,
                        );
                        _reload();
                      },
                      onExport: () async {
                        final json = await widget.service.exportModel(
                          equipmentProfileId: m.equipmentProfileId,
                          filterName: m.filterName,
                        );
                        if (!context.mounted || json == null) return;
                        await Clipboard.setData(
                          ClipboardData(text: json),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied ${m.filterName} model JSON to clipboard',
                            ),
                          ),
                        );
                      },
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

class _ModelRow extends StatefulWidget {
  final FilterFocusModel model;
  final VoidCallback onClear;
  final VoidCallback onExport;

  const _ModelRow({
    required this.model,
    required this.onClear,
    required this.onExport,
  });

  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final c = NightshadeColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _confidenceDot(m.confidenceScore, c),
              const SizedBox(width: 8),
              Text(
                m.filterName,
                style: NightshadeTypography.labelStrong
                    .copyWith(color: c.textPrimary),
              ),
              const SizedBox(width: 12),
              _stat('Slope', '${m.slopeStepsPerC.toStringAsFixed(1)} steps/°C',
                  c),
              const SizedBox(width: 12),
              _stat('Samples', '${m.samples.length}', c),
              const SizedBox(width: 12),
              _stat('Runs', '${m.trainingRunCount}', c),
              const SizedBox(width: 12),
              _stat('R²', m.confidenceScore.toStringAsFixed(3), c),
              const Spacer(),
              IconButton(
                tooltip: _expanded ? 'Hide samples' : 'View samples',
                iconSize: 14,
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  color: c.textMuted,
                ),
              ),
              IconButton(
                tooltip: 'Export JSON',
                iconSize: 14,
                onPressed: widget.onExport,
                icon: Icon(LucideIcons.download, color: c.textMuted),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Re-train ${m.filterName} focus model?'),
                      content: Text(
                        'This clears all ${m.samples.length} learned samples '
                        'for ${m.filterName}. The next autofocus run will '
                        'start a fresh regression window.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Re-train'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) widget.onClear();
                },
                icon: Icon(LucideIcons.refreshCw, size: 13, color: c.warning),
                label: Text(
                  'Re-train',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: c.warning),
                ),
              ),
            ],
          ),
          if (m.consecutiveBadPredictions > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.alertTriangle, size: 12, color: c.warning),
                const SizedBox(width: 6),
                Text(
                  'Drift: ${m.consecutiveBadPredictions} consecutive bad '
                  'predictions; ${m.accumulatedDriftSteps} accumulated steps',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: c.warning),
                ),
              ],
            ),
          ],
          if (m.lastUsedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last used: ${_formatTimeAgo(m.lastUsedAt!)} · '
              'Last trained: ${_formatTimeAgo(m.lastTrainedAt)}',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: c.textMuted),
            ),
          ],
          if (_expanded) ...[
            const SizedBox(height: 10),
            _SampleScatter(samples: m.samples, model: m),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, NightshadeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize9, color: c.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _confidenceDot(double confidence, NightshadeColors c) {
    final Color color;
    if (confidence >= 0.8) {
      color = c.success;
    } else if (confidence >= 0.5) {
      color = c.warning;
    } else {
      color = c.error;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _formatTimeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Inline scatter plot for the per-filter sample window. Light-weight
/// custom painter — no chart library dependency.
class _SampleScatter extends StatelessWidget {
  final List<FocusTrainingSample> samples;
  final FilterFocusModel model;

  const _SampleScatter({
    required this.samples,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return SizedBox(
      height: 140,
      child: NightshadeCard(
        variant: CardVariant.subtle,
        borderRadius: NightshadeTokens.radiusInline4,
        padding: const EdgeInsets.all(8),
        child: samples.isEmpty
            ? Center(
                child: Text(
                  'No samples',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
              )
            : CustomPaint(
                size: Size.infinite,
                painter: _ScatterPainter(
                  samples: samples,
                  model: model,
                  pointColor: colors.accent,
                  lineColor: colors.primary,
                  gridColor: colors.border,
                ),
              ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  final List<FocusTrainingSample> samples;
  final FilterFocusModel model;
  final Color pointColor;
  final Color lineColor;
  final Color gridColor;

  _ScatterPainter({
    required this.samples,
    required this.model,
    required this.pointColor,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    double minTemp = samples.first.temperatureCelsius;
    double maxTemp = samples.first.temperatureCelsius;
    double minPos = samples.first.focusPosition.toDouble();
    double maxPos = samples.first.focusPosition.toDouble();
    for (final s in samples) {
      if (s.temperatureCelsius < minTemp) minTemp = s.temperatureCelsius;
      if (s.temperatureCelsius > maxTemp) maxTemp = s.temperatureCelsius;
      if (s.focusPosition < minPos) minPos = s.focusPosition.toDouble();
      if (s.focusPosition > maxPos) maxPos = s.focusPosition.toDouble();
    }
    final tempRange = (maxTemp - minTemp).abs();
    if (tempRange < 1) {
      minTemp -= 1;
      maxTemp += 1;
    }
    final posRange = (maxPos - minPos).abs();
    if (posRange < 50) {
      minPos -= 50;
      maxPos += 50;
    }

    double mapX(double t) => (t - minTemp) / (maxTemp - minTemp) * size.width;
    double mapY(double p) =>
        size.height - (p - minPos) / (maxPos - minPos) * size.height;

    // Border / grid
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, gridPaint);

    // Regression line
    if (model.slopeStepsPerC.abs() > 1e-6) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final y1 = model.predictPosition(minTemp);
      final y2 = model.predictPosition(maxTemp);
      canvas.drawLine(
        Offset(mapX(minTemp), mapY(y1.toDouble())),
        Offset(mapX(maxTemp), mapY(y2.toDouble())),
        linePaint,
      );
    }

    // Points
    final pointPaint = Paint()..color = pointColor;
    for (final s in samples) {
      canvas.drawCircle(
        Offset(mapX(s.temperatureCelsius), mapY(s.focusPosition.toDouble())),
        2.5,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter old) =>
      old.samples != samples || old.model.uuid != model.uuid;
}

/// Single number field used by the settings page. Avoids requiring callers
/// to manage a TextEditingController for each row.
class _NumberField extends StatefulWidget {
  final double initialValue;
  final double min;
  final double max;
  final int decimals;
  final void Function(double) onChanged;

  const _NumberField({
    required this.initialValue,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(widget.decimals),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsNumberInput(
      controller: _controller,
      suffix: '',
      min: widget.min,
      max: widget.max,
      decimals: widget.decimals,
      onChanged: widget.onChanged,
    );
  }
}
