// Wave 5 Agent 2 — Sky-brightness adaptive exposure global defaults UI.
//
// Surfaces the master toggle, reference sky brightness, min/max clamp,
// and per-filter overrides for the global default config that the Rust
// executor's `RuntimeConfig.default_adaptive_exposure` reads at sequence
// start. Per-node `ExposureNode.adaptiveExposure` overrides still win at
// runtime; this page only tunes the *default* the executor uses when a
// node has no own block.
//
// The settings are persisted via `AppSettingsNotifier.setAdaptiveExposure*`
// and pushed to the executor via
// `backend.sequencerUpdateDefaultAdaptiveExposure` (or the clear
// equivalent when the master toggle is off).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class AdaptiveExposureSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const AdaptiveExposureSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<AdaptiveExposureSettings> createState() =>
      _AdaptiveExposureSettingsState();
}

class _AdaptiveExposureSettingsState
    extends ConsumerState<AdaptiveExposureSettings> {
  final _targetSnrController = TextEditingController();
  final _refMagController = TextEditingController();
  final _minSecsController = TextEditingController();
  final _maxSecsController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _targetSnrController.dispose();
    _refMagController.dispose();
    _minSecsController.dispose();
    _maxSecsController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (_initialized) return;
    _targetSnrController.text =
        settings.adaptiveExposureTargetSnr.toStringAsFixed(0);
    _refMagController.text =
        settings.adaptiveExposureReferenceMag.toStringAsFixed(2);
    _minSecsController.text =
        settings.adaptiveExposureMinSecs.toStringAsFixed(1);
    _maxSecsController.text =
        settings.adaptiveExposureMaxSecs.toStringAsFixed(1);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Text('Failed to load settings: $e',
            style: TextStyle(color: colors.error)),
      ),
      data: (settings) {
        _initControllers(settings);
        final notifier = ref.read(appSettingsProvider.notifier);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(LucideIcons.barChart3, size: 18, color: colors.primary),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  'Adaptive Exposure (Sky-Brightness)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              'Dynamically stretches per-frame exposure when the sky is brighter than '
                  'the reference, so SNR stays roughly constant across changing conditions. '
                  'Per-ExposureNode overrides always win at runtime; this page sets the '
                  'default applied to nodes without their own block.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),

            // Master toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enable global default',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SettingsSwitch(
                  value: settings.adaptiveExposureEnabled,
                  onChanged: (v) async {
                    await notifier.setAdaptiveExposureEnabled(v);
                  },
                ),
              ],
            ),

            // Conditional knobs
            if (settings.adaptiveExposureEnabled) ...[
              const SizedBox(height: NightshadeTokens.spaceLg),

              Row(
                children: [
                  Expanded(
                    child: _LabeledTextField(
                      label: 'Target SNR',
                      controller: _targetSnrController,
                      keyboardType: TextInputType.number,
                      onSubmitted: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          notifier.setAdaptiveExposureTargetSnr(parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: _LabeledTextField(
                      label: 'Reference (mag/arcsec²)',
                      controller: _refMagController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onSubmitted: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          notifier.setAdaptiveExposureReferenceMag(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: _LabeledTextField(
                      label: 'Global minimum exposure (s)',
                      controller: _minSecsController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onSubmitted: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          notifier.setAdaptiveExposureMinSecs(parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: _LabeledTextField(
                      label: 'Global maximum exposure (s)',
                      controller: _maxSecsController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onSubmitted: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          notifier.setAdaptiveExposureMaxSecs(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: NightshadeTokens.spaceLg),
              _PerFilterEditor(
                settings: settings,
                notifier: notifier,
              ),

              const SizedBox(height: NightshadeTokens.spaceLg),
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
                decoration: NightshadeDecorations.tintedBadge(
                  colors.info,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 14, color: colors.info),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Expanded(
                      child: Text(
                        'How it works: the Rust executor computes a flux ratio from the '
                            'reference vs. live sky brightness (Pogson formula) and stretches '
                            'or shrinks the configured exposure to keep the sky-noise-limited '
                            'SNR roughly constant. Per-filter overrides are respected; the '
                            'global min/max clamp prevents runaway exposures.',
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.keyboardType,
    required this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 13, color: colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}

class _PerFilterEditor extends ConsumerStatefulWidget {
  const _PerFilterEditor({
    required this.settings,
    required this.notifier,
  });
  final AppSettingsState settings;
  final AppSettingsNotifier notifier;

  @override
  ConsumerState<_PerFilterEditor> createState() => _PerFilterEditorState();
}

class _PerFilterEditorState extends ConsumerState<_PerFilterEditor> {
  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? const <String>[];
    if (filterNames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        decoration: NightshadeDecorations.tintedBadge(
          colors.warning,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle,
                size: 14, color: colors.warning),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                'No filter wheel on active profile — adaptive applies to every '
                    'capture (mono camera assumption).',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final enabledMap =
        Map<String, bool>.from(widget.settings.adaptiveExposurePerFilterEnabled);
    final minMap = Map<String, double>.from(
        widget.settings.adaptiveExposurePerFilterMinSecs);
    final maxMap = Map<String, double>.from(
        widget.settings.adaptiveExposurePerFilterMaxSecs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Per-filter overrides',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Empty rows inherit the global enable + clamp. Enable a filter to opt it '
              'into adaptive exposure; set min/max to override the global clamps.',
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        ...filterNames.map((filter) => _filterRow(filter, enabledMap, minMap, maxMap)),
      ],
    );
  }

  Widget _filterRow(
    String filter,
    Map<String, bool> enabledMap,
    Map<String, double> minMap,
    Map<String, double> maxMap,
  ) {
    final colors = NightshadeColors.of(context);
    final enabled = enabledMap[filter] ?? enabledMap.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              filter,
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          NightshadeCheckbox(
            value: enabled,
            onChanged: (v) {
              enabledMap[filter] = v ?? false;
              widget.notifier
                  .setAdaptiveExposurePerFilterEnabled(enabledMap);
              setState(() {});
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OverrideField(
              label: 'min s',
              initial: minMap[filter],
              onChanged: (v) {
                if (v == null) {
                  minMap.remove(filter);
                } else {
                  minMap[filter] = v;
                }
                widget.notifier
                    .setAdaptiveExposurePerFilterMinSecs(minMap);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OverrideField(
              label: 'max s',
              initial: maxMap[filter],
              onChanged: (v) {
                if (v == null) {
                  maxMap.remove(filter);
                } else {
                  maxMap[filter] = v;
                }
                widget.notifier
                    .setAdaptiveExposurePerFilterMaxSecs(maxMap);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OverrideField extends StatefulWidget {
  const _OverrideField({
    required this.label,
    required this.initial,
    required this.onChanged,
  });
  final String label;
  final double? initial;
  final ValueChanged<double?> onChanged;

  @override
  State<_OverrideField> createState() => _OverrideFieldState();
}

class _OverrideFieldState extends State<_OverrideField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null
          ? ''
          : widget.initial!.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_OverrideField old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) {
      _controller.text = widget.initial == null
          ? ''
          : widget.initial!.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: TextStyle(fontSize: 12, color: NightshadeColors.of(context).textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle:
            TextStyle(fontSize: 10, color: NightshadeColors.of(context).textMuted),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onSubmitted: (v) {
        if (v.trim().isEmpty) {
          widget.onChanged(null);
          return;
        }
        final parsed = double.tryParse(v);
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}
