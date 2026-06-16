import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// View the connected appliance's temperature-compensation focus model.
///
/// The model is built on the rig (where autofocus runs); the orphaned local
/// FocusModelPanel computes from local state and would be empty over the
/// network. This pulls the rig's model (slope/R²/reliability) over REST so a
/// remote operator can confirm temp-comp is healthy. Remote-only.
class FocusModelSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const FocusModelSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<FocusModelSettings> createState() => _FocusModelSettingsState();
}

class _FocusModelSettingsState extends ConsumerState<FocusModelSettings> {
  Map<String, dynamic>? _model;
  bool _loading = false;
  String? _error;

  NetworkBackend? get _backend {
    final b = ref.read(backendProvider);
    return b is NetworkBackend ? b : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final backend = _backend;
    if (backend == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = await backend.getFocusModel();
      if (!mounted) return;
      setState(() {
        _model = model;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _clear() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      await backend.clearFocusModelData();
      if (mounted) context.showSuccessSnackBar('Focus model data cleared');
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Clear failed: $e');
    } finally {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = _backend;
    final model = _model;
    final hasModel = model?['hasModel'] == true;
    final m = model?['model'] as Map<String, dynamic>?;

    return SettingsPage(
      title: 'Focus Model',
      description: 'Temperature-compensation focus model on the connected rig',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        if (backend == null)
          _info(colors, LucideIcons.info,
              'Connect to a remote appliance to view its focus model.')
        else ...[
          Row(
            children: [
              Text('Active equipment profile',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize13)),
              const Spacer(),
              NightshadeButton(
                onPressed: _loading ? null : _refresh,
                label: 'Refresh',
                icon: LucideIcons.rotateCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading && model == null)
            _info(colors, LucideIcons.loader, 'Loading…')
          else if (hasModel && m != null)
            NightshadeCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          m['isReliable'] == true
                              ? LucideIcons.checkCircle
                              : LucideIcons.alertTriangle,
                          size: 16,
                          color: m['isReliable'] == true
                              ? colors.success
                              : colors.warning),
                      const SizedBox(width: 8),
                      Text(
                          m['isReliable'] == true
                              ? 'Model healthy'
                              : 'Model low-confidence',
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: NightshadeTypography.fontSize15,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _row(colors, 'Slope',
                      '${_num(m['slope'])} steps/°C'),
                  _row(colors, 'R²', _num(m['rSquared'])),
                  _row(colors, 'Data points', '${m['dataPointCount'] ?? '—'}'),
                  if (model?['description'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${model!['description']}',
                          style: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize12)),
                    ),
                ],
              ),
            )
          else
            _info(
                colors,
                LucideIcons.thermometer,
                model?['message']?.toString() ??
                    'No focus model yet (autofocus runs across temperatures '
                        'build it automatically). '
                        'Data points: ${model?['dataPointCount'] ?? 0}.'),
          const SizedBox(height: 12),
          NightshadeButton(
            onPressed: _loading ? null : _clear,
            label: 'Clear Model Data',
            icon: LucideIcons.trash2,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _info(colors, LucideIcons.alertTriangle, 'Error: $_error'),
          ],
        ],
      ],
    );
  }

  static String _num(dynamic v) {
    if (v is num) return v.toStringAsFixed(3);
    return '$v';
  }

  Widget _row(NightshadeColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _info(NightshadeColors colors, IconData icon, String text) {
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13)),
          ),
        ],
      ),
    );
  }
}
