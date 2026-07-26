// Sky-brightness adaptive exposure global defaults UI.
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

import 'dart:async';

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
  final _refMagController = TextEditingController();
  final _minSecsController = TextEditingController();
  final _maxSecsController = TextEditingController();
  String? _globalBoundsError;
  int _globalBoundsSaveGeneration = 0;

  @override
  void dispose() {
    _refMagController.dispose();
    _minSecsController.dispose();
    _maxSecsController.dispose();
    super.dispose();
  }

  Future<void> _commitGlobalBounds(AppSettingsNotifier notifier) async {
    final minSecs = double.tryParse(_minSecsController.text.trim());
    final maxSecs = double.tryParse(_maxSecsController.text.trim());
    String? validationError;
    if (minSecs == null || !minSecs.isFinite || minSecs <= 0) {
      validationError = 'Minimum exposure must be a positive number.';
    } else if (maxSecs == null || !maxSecs.isFinite || maxSecs <= 0) {
      validationError = 'Maximum exposure must be a positive number.';
    } else if (minSecs > maxSecs) {
      validationError = 'Minimum exposure cannot exceed maximum exposure.';
    }
    if (validationError != null) {
      if (mounted) setState(() => _globalBoundsError = validationError);
      throw StateError(validationError);
    }

    final generation = ++_globalBoundsSaveGeneration;
    if (mounted) setState(() => _globalBoundsError = null);
    try {
      await notifier.setAdaptiveExposureBounds(
        minSecs: minSecs!,
        maxSecs: maxSecs!,
      );
    } catch (error) {
      if (mounted && generation == _globalBoundsSaveGeneration) {
        setState(() {
          _globalBoundsError = 'Could not save exposure bounds: $error';
        });
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Text('Could not load adaptive exposure settings.',
            style: TextStyle(color: colors.error)),
      ),
      data: (settings) {
        final authority = ref.watch(backendProvider);
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
                    fontSize: NightshadeTypography.fontSize16,
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
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),

            // Master toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enable global default',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
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
              // Target SNR control hidden until the native executor honors
              // target_snr; compute_adaptive_exposure ignores it today.
              _LabeledNumberField(
                fieldKey: const ValueKey('adaptive-reference-mag'),
                label: 'Reference (mag/arcsec²)',
                controller: _refMagController,
                authoritativeValue: settings.adaptiveExposureReferenceMag,
                authorityKey: authority,
                min: 14,
                max: 24,
                decimals: 2,
                onChanged: notifier.setAdaptiveExposureReferenceMag,
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: _LabeledNumberField(
                      fieldKey: const ValueKey('adaptive-global-min-secs'),
                      label: 'Global minimum exposure (s)',
                      controller: _minSecsController,
                      authoritativeValue: settings.adaptiveExposureMinSecs,
                      authorityKey: authority,
                      min: 0.1,
                      max: 86400,
                      decimals: 1,
                      onChanged: (_) => _commitGlobalBounds(notifier),
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: _LabeledNumberField(
                      fieldKey: const ValueKey('adaptive-global-max-secs'),
                      label: 'Global maximum exposure (s)',
                      controller: _maxSecsController,
                      authoritativeValue: settings.adaptiveExposureMaxSecs,
                      authorityKey: authority,
                      min: 0.1,
                      max: 86400,
                      decimals: 1,
                      onChanged: (_) => _commitGlobalBounds(notifier),
                    ),
                  ),
                ],
              ),
              if (_globalBoundsError != null) ...[
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  _globalBoundsError!,
                  style: TextStyle(
                    color: colors.error,
                    fontSize: NightshadeTypography.fontSize11,
                  ),
                ),
              ],
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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
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
                            fontSize: NightshadeTypography.fontSize12,
                            color: colors.textSecondary),
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

class _LabeledNumberField extends StatelessWidget {
  const _LabeledNumberField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.authoritativeValue,
    required this.authorityKey,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
  });
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final double authoritativeValue;
  final Object authorityKey;
  final double min;
  final double max;
  final int decimals;
  final FutureOr<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NightshadeTypography.labelStrongSm
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        SettingsNumberInput(
          key: fieldKey,
          controller: controller,
          authoritativeValue: authoritativeValue,
          authorityKey: authorityKey,
          suffix: '',
          min: min,
          max: max,
          decimals: decimals,
          onChanged: onChanged,
          flexible: true,
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
  String? _boundsError;
  int _saveGeneration = 0;

  void _showBoundsError(String message) {
    if (mounted) setState(() => _boundsError = message);
  }

  Future<void> _commitBounds(
    Map<String, double> minMap,
    Map<String, double> maxMap,
  ) async {
    final generation = ++_saveGeneration;
    if (mounted) setState(() => _boundsError = null);
    try {
      await widget.notifier.setAdaptiveExposurePerFilterBounds(
        minSecs: minMap,
        maxSecs: maxMap,
      );
    } catch (error) {
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _boundsError = error is ArgumentError
              ? error.message.toString()
              : 'Could not save per-filter exposure bounds: $error';
        });
      }
    }
  }

  Future<void> _commitEnabled(Map<String, bool> enabledMap) async {
    try {
      await widget.notifier.setAdaptiveExposurePerFilterEnabled(enabledMap);
    } catch (error) {
      _showBoundsError('Could not save per-filter enablement: $error');
    }
  }

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
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                'No filter wheel on active profile — adaptive applies to every '
                'capture (mono camera assumption).',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final enabledMap = Map<String, bool>.from(
        widget.settings.adaptiveExposurePerFilterEnabled);
    final minMap = Map<String, double>.from(
        widget.settings.adaptiveExposurePerFilterMinSecs);
    final maxMap = Map<String, double>.from(
        widget.settings.adaptiveExposurePerFilterMaxSecs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Per-filter overrides',
          style: NightshadeTypography.h6.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Empty rows inherit the global enable + clamp. Enable a filter to opt it '
          'into adaptive exposure; set min/max to override the global clamps.',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        ...filterNames
            .map((filter) => _filterRow(filter, enabledMap, minMap, maxMap)),
        if (_boundsError != null) ...[
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            _boundsError!,
            style: TextStyle(
              color: colors.error,
              fontSize: NightshadeTypography.fontSize11,
            ),
          ),
        ],
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
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          NightshadeCheckbox(
            value: enabled,
            onChanged: (v) {
              // An empty map means "all filters enabled". Materialize that
              // implicit state before changing one checkbox; otherwise the
              // first unchecked filter makes every absent filter disabled.
              if (enabledMap.isEmpty) {
                for (final profileFilter
                    in ref.read(activeEquipmentProfileProvider)?.filterNames ??
                        const <String>[]) {
                  enabledMap[profileFilter] = true;
                }
              }
              enabledMap[filter] = v ?? false;
              unawaited(_commitEnabled(enabledMap));
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OverrideField(
              key: ValueKey('adaptiveExposure.$filter.min'),
              label: 'min s',
              initial: minMap[filter],
              onChanged: (v) {
                if (v == null) {
                  minMap.remove(filter);
                } else {
                  minMap[filter] = v;
                }
                unawaited(_commitBounds(minMap, maxMap));
              },
              onInvalid: _showBoundsError,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OverrideField(
              key: ValueKey('adaptiveExposure.$filter.max'),
              label: 'max s',
              initial: maxMap[filter],
              onChanged: (v) {
                if (v == null) {
                  maxMap.remove(filter);
                } else {
                  maxMap[filter] = v;
                }
                unawaited(_commitBounds(minMap, maxMap));
              },
              onInvalid: _showBoundsError,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverrideField extends StatefulWidget {
  const _OverrideField({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    required this.onInvalid,
  });
  final String label;
  final double? initial;
  final ValueChanged<double?> onChanged;
  final ValueChanged<String> onInvalid;

  @override
  State<_OverrideField> createState() => _OverrideFieldState();
}

class _OverrideFieldState extends State<_OverrideField> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();
  late String _lastSubmitted;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null ? '' : widget.initial!.toStringAsFixed(1),
    );
    _lastSubmitted = _controller.text;
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // Persist on blur, not only on Enter, so an override edit survives leaving
    // the field without submitting.
    if (!_focusNode.hasFocus) {
      _submit(_controller.text);
    }
  }

  void _submit(String v) {
    final text = v.trim();
    if (text == _lastSubmitted) return;
    _lastSubmitted = text;
    if (text.isEmpty) {
      widget.onChanged(null);
      return;
    }
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      widget.onInvalid('${widget.label} must be a positive number.');
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  void didUpdateWidget(_OverrideField old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) {
      _controller.text =
          widget.initial == null ? '' : widget.initial!.toStringAsFixed(1);
      _lastSubmitted = _controller.text;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: NightshadeColors.of(context).textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            color: NightshadeColors.of(context).textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onSubmitted: _submit,
    );
  }
}
