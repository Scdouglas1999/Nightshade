import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Which sky source seeds the region's centre + name.
enum _RegionSource { target, custom }

/// "Name a region" sheet — the explicit control that makes the entire Your Sky
/// region UX reachable by hand (alongside the automatic on-fold attach).
///
/// Pick a source — one of the user's targets (active target / library) or a
/// custom RA-Dec + radius (covers a mosaic, polar field, or any patch of sky) —
/// give it a name, and create the region through the authority-aware
/// [skyAtlasRegionWriterProvider]. On a companion the metadata write runs on
/// the imaging host; atlas pixels and fold history never move to the client.
class NameRegionSheet extends ConsumerStatefulWidget {
  const NameRegionSheet({super.key});

  /// Show the sheet; returns true when a region was created.
  static Future<bool?> show(BuildContext context) {
    return showAdaptiveModal<bool>(
      context: context,
      builder: (_) => const NameRegionSheet(),
    );
  }

  @override
  ConsumerState<NameRegionSheet> createState() => _NameRegionSheetState();
}

class _NameRegionSheetState extends ConsumerState<NameRegionSheet> {
  _RegionSource _source = _RegionSource.target;
  DbTarget? _selectedTarget;
  final _nameController = TextEditingController();
  final _raController = TextEditingController();
  final _decController = TextEditingController();
  final _radiusController = TextEditingController(text: '0.5');
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A validation message must not outlive the state that produced it. The
    // sheet used to keep showing "Pick a target first." after the user did
    // exactly what its own copy told them to do — switch to Custom RA/Dec,
    // a mode with no target to pick — right through to a successful create.
    for (final c in [
      _nameController,
      _raController,
      _decController,
      _radiusController,
    ]) {
      c.addListener(_clearError);
    }
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  /// Whether [_create] could possibly succeed as the form now stands. Only the
  /// unsatisfiable case is blocked: the range errors on the custom fields still
  /// have to be reachable, because they say what a valid entry looks like.
  bool get _canSubmit =>
      _source != _RegionSource.target || _selectedTarget != null;

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _raController,
      _decController,
      _radiusController,
    ]) {
      c.removeListener(_clearError);
    }
    _nameController.dispose();
    _raController.dispose();
    _decController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final targetsAsync = ref.watch(allDbTargetsProvider);

    final sheet = SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: NightshadeTokens.spaceLg,
          right: NightshadeTokens.spaceLg,
          top: NightshadeTokens.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom +
              NightshadeTokens.spaceLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.plus,
                      size: NightshadeTokens.iconMd, color: colors.primary),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    'Name a region',
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Text(
                'Group the sky you have imaged into a named region to track its '
                'depth and scrub it through time. Future folds at this position '
                'deepen it automatically.',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              _SourceToggle(
                source: _source,
                onChanged: (s) => setState(() {
                  _source = s;
                  _error = null;
                }),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              if (_source == _RegionSource.target)
                _buildTargetPicker(colors, targetsAsync)
              else
                _buildCustomFields(colors),
              const SizedBox(height: NightshadeTokens.spaceMd),
              NightshadeTextField(
                controller: _nameController,
                label: 'Region name',
                hint: _source == _RegionSource.target
                    ? 'Defaults to the target name'
                    : 'e.g. Cygnus Wall mosaic',
              ),
              if (_error != null) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                Text(
                  _error!,
                  style: NightshadeTypography.caption
                      .copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: NightshadeTokens.spaceLg),
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: 'Cancel',
                      variant: ButtonVariant.outline,
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).maybePop(false),
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Create region',
                      icon: LucideIcons.check,
                      isLoading: _saving,
                      onPressed: _saving || !_canSubmit ? null : _create,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope(canPop: !_saving, child: sheet);
  }

  Widget _buildTargetPicker(
    NightshadeColors colors,
    AsyncValue<List<DbTarget>> targetsAsync,
  ) {
    return targetsAsync.when(
      data: (targets) {
        if (targets.isEmpty) {
          return NightshadeCard(
            variant: CardVariant.subtle,
            padding: NightshadeTokens.cardPadding,
            child: Text(
              'No targets in your library yet — switch to Custom to enter a '
              'sky position by hand.',
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textMuted),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            NightshadeDropdown(
              value: _selectedTarget == null ? null : '${_selectedTarget!.id}',
              hint: 'Choose a target',
              isExpanded: true,
              items: [for (final t in targets) '${t.id}'],
              itemLabels: [for (final t in targets) t.name],
              onChanged: (idStr) => setState(() {
                final id = int.tryParse(idStr ?? '');
                DbTarget? t;
                for (final x in targets) {
                  if (x.id == id) {
                    t = x;
                    break;
                  }
                }
                _selectedTarget = t;
                _error = null;
                if (t != null && _nameController.text.trim().isEmpty) {
                  _nameController.text = t.name;
                }
              }),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: NightshadeCircularProgress(
          value: 0,
          indeterminate: true,
          size: NightshadeTokens.iconLg,
        ),
      ),
      error: (_, __) => Text(
        'Could not load targets.',
        style: NightshadeTypography.caption.copyWith(color: colors.error),
      ),
    );
  }

  Widget _buildCustomFields(NightshadeColors colors) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NightshadeTextField(
                controller: _raController,
                label: 'RA (degrees)',
                hint: '0–360',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: NightshadeTextField(
                controller: _decController,
                label: 'Dec (degrees)',
                hint: '-90–90',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        NightshadeTextField(
          controller: _radiusController,
          label: 'Radius (degrees)',
          hint: 'cone radius, e.g. 0.5',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    double raDeg;
    double decDeg;
    double radiusDeg;
    String kind;
    final name = _nameController.text.trim();

    if (_source == _RegionSource.target) {
      final target = _selectedTarget;
      if (target == null) {
        setState(() {
          _saving = false;
          _error = 'Pick a target first.';
        });
        return;
      }
      raDeg = target.ra * 15.0; // RA hours -> degrees.
      decDeg = target.dec;
      radiusDeg = 0.5;
      kind = 'target';
    } else {
      final ra = double.tryParse(_raController.text.trim());
      final dec = double.tryParse(_decController.text.trim());
      final radius = double.tryParse(_radiusController.text.trim());
      if (ra == null ||
          !ra.isFinite ||
          ra < 0 ||
          ra > 360 ||
          dec == null ||
          !dec.isFinite ||
          dec < -90 ||
          dec > 90 ||
          radius == null ||
          !radius.isFinite ||
          radius <= 0 ||
          radius > 180) {
        setState(() {
          _saving = false;
          _error = 'Enter RA from 0–360°, Dec from -90–90°, and a radius '
              'greater than 0° and no more than 180°.';
        });
        return;
      }
      raDeg = ra;
      decDeg = dec;
      radiusDeg = radius;
      kind = 'custom';
    }

    final effectiveName =
        name.isNotEmpty ? name : (_selectedTarget?.name ?? 'Custom region');

    final authority = ref.read(backendProvider);
    try {
      await ref.read(skyAtlasRegionWriterProvider).ensureRegion(
            name: effectiveName,
            centerRaDeg: raDeg,
            centerDecDeg: decDeg,
            radiusDeg: radiusDeg,
            kind: kind,
            targetId:
                _source == _RegionSource.target ? _selectedTarget?.id : null,
          );
      if (!mounted) return;
      if (!identical(ref.read(backendProvider), authority)) {
        setState(() {
          _saving = false;
          _error = 'The imaging host changed while the region was being '
              'created. Check the active host before trying again.';
        });
        return;
      }
      ref.invalidate(skyAtlasRegionsProvider);
      unawaited(Navigator.of(context).maybePop(true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create region: $e';
      });
    }
  }
}

class _SourceToggle extends StatelessWidget {
  final _RegionSource source;
  final ValueChanged<_RegionSource> onChanged;

  const _SourceToggle({required this.source, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: NightshadeChip(
            label: 'From a target',
            selected: source == _RegionSource.target,
            onTap: () => onChanged(_RegionSource.target),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: NightshadeChip(
            label: 'Custom RA/Dec',
            selected: source == _RegionSource.custom,
            onTap: () => onChanged(_RegionSource.custom),
          ),
        ),
      ],
    );
  }
}
