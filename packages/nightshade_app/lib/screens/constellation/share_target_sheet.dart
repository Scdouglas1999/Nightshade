import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../your_sky/sky_atlas_format.dart';
import 'constellation_format.dart';

/// Open the "Share one of my targets" flow: pick a local imageable field,
/// confirm the swarm radius, and seed it as a shared target on the hub.
///
/// Resolves the newly-created [SharedTarget] once the hub accepts it (so the
/// caller can route into its detail screen), or null if the user cancelled.
Future<SharedTarget?> showShareTargetSheet(BuildContext context) {
  return showAdaptiveModal<SharedTarget>(
    context: context,
    designWidth: 560,
    phoneMode: PhoneModalMode.bottomSheet,
    builder: (_) => const _ShareTargetSheet(),
  );
}

class _ShareTargetSheet extends ConsumerStatefulWidget {
  const _ShareTargetSheet();

  @override
  ConsumerState<_ShareTargetSheet> createState() => _ShareTargetSheetState();
}

class _ShareTargetSheetState extends ConsumerState<_ShareTargetSheet> {
  ShareableLocalTarget? _selected;
  double _radiusDeg = 1.5;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final targetsAsync = ref.watch(shareableLocalTargetsProvider);

    // Surface, not NightshadeDialog: showAdaptiveModal already supplies the
    // frame (a Dialog on desktop, a bottom sheet on a phone). Nesting a second
    // dialog stretched that frame into a full-height slab.
    return NightshadeDialogSurface(
      title: 'Share one of my targets',
      icon: LucideIcons.globe2,
      showCloseButton: !_busy,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: 'Share to swarm',
          icon: LucideIcons.globe2,
          isLoading: _busy,
          onPressed: _selected != null && !_busy ? _submit : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seed a community field from one of your own targets. Other imagers '
            'can then join and deepen it with you. Sharing the field publishes '
            'only its name and sky position — no imaging leaves your device '
            'until you contribute.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          targetsAsync.when(
            data: (targets) => targets.isEmpty
                ? _EmptyTargets(colors: colors)
                : _TargetPicker(
                    targets: targets,
                    selected: _selected,
                    onSelect:
                        _busy ? null : (t) => setState(() => _selected = t),
                  ),
            loading: () => const ShimmerLoading(
              child: SkeletonBox(
                width: double.infinity,
                height: 72,
                borderRadius: NightshadeTokens.radiusLg,
              ),
            ),
            error: (error, _) => NightshadeAlert(
              severity: NightshadeAlertSeverity.warning,
              title: 'Could not load your targets',
              message: '$error',
            ),
          ),
          if (_selected != null) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            _RadiusRow(
              radiusDeg: _radiusDeg,
              onChanged: _busy ? null : (v) => setState(() => _radiusDeg = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.error,
              message: _error!,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = await ref.read(constellationServiceProvider).proposeTarget(
            name: selected.name,
            raDeg: selected.raDeg,
            decDeg: selected.decDeg,
            radiusDeg: _radiusDeg,
          );
      if (!mounted) return;
      Navigator.of(context).pop(target);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeConstellationError(error);
      });
    }
  }
}

class _TargetPicker extends StatelessWidget {
  final List<ShareableLocalTarget> targets;
  final ShareableLocalTarget? selected;
  final ValueChanged<ShareableLocalTarget>? onSelect;

  const _TargetPicker({
    required this.targets,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PICK A FIELD',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final t in targets) ...[
                  _TargetOption(
                    target: t,
                    selected: selected?.targetId == t.targetId,
                    onTap: onSelect == null ? null : () => onSelect!(t),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetOption extends StatelessWidget {
  final ShareableLocalTarget target;
  final bool selected;
  final VoidCallback? onTap;

  const _TargetOption({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: selected ? CardVariant.elevated : CardVariant.subtle,
      isSelected: selected,
      onTap: onTap,
      padding: NightshadeTokens.cardPadding,
      child: Row(
        children: [
          Icon(
            selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
            size: NightshadeTokens.iconMd,
            color: selected ? colors.accent : colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name.isEmpty
                      ? 'Target #${target.targetId}'
                      : target.name,
                  style: NightshadeTypography.labelStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCenter(target.raDeg, target.decDeg),
                  style: NightshadeTypography.captionSm.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadiusRow extends StatelessWidget {
  final double radiusDeg;
  final ValueChanged<double>? onChanged;

  const _RadiusRow({required this.radiusDeg, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SWARM RADIUS',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Text(
              '${radiusDeg.toStringAsFixed(1)}°',
              style: NightshadeTypography.labelStrong.copyWith(
                color: colors.accent,
              ),
            ),
          ],
        ),
        NightshadeSlider(
          value: radiusDeg,
          min: 0.5,
          max: 5.0,
          divisions: 9,
          onChanged: onChanged,
        ),
        Text(
          'How wide a cone the swarm deepens around this field. Matches the area '
          'your contributions and pulls cover.',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _EmptyTargets extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyTargets({required this.colors});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Row(
        children: [
          Icon(
            LucideIcons.star,
            size: NightshadeTokens.iconMd,
            color: colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              'You have no targets in your catalog yet. Add a target you image, '
              'then share it with the swarm.',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
