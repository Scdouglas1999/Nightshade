import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Hide the core wire enum of the same name; this screen uses the richer
// app-side `ConstellationPrivacy` from constellation_ui_providers.dart and maps
// to the core one via its `.wire` getter when calling the service.
import 'package:nightshade_core/nightshade_core.dart' hide ConstellationPrivacy;
import 'package:nightshade_ui/nightshade_ui.dart';

import 'constellation_format.dart';
import 'constellation_ui_providers.dart';

/// Open the contribute consent flow for [target]. Resolves the
/// [ContributionOutcome] once the push completes, or null if the user cancelled.
Future<ContributionOutcome?> showConstellationContributeSheet(
  BuildContext context, {
  required SharedTarget target,
}) {
  return showAdaptiveModal<ContributionOutcome>(
    context: context,
    designWidth: 560,
    phoneMode: PhoneModalMode.bottomSheet,
    builder: (_) => _ConstellationContributeSheet(target: target),
  );
}

/// Explicit consent + privacy choice before any pixels leave the device.
///
/// The default and recommended choice is SUMS — only the additive co-add stack
/// the master integration already keeps. SUBS (raw subframes) is the heavier,
/// more-revealing opt-in. The choice is persisted; the upload itself ships the
/// additive `.nst` sums through [ConstellationService.contributeTarget].
class _ConstellationContributeSheet extends ConsumerStatefulWidget {
  final SharedTarget target;

  const _ConstellationContributeSheet({required this.target});

  @override
  ConsumerState<_ConstellationContributeSheet> createState() =>
      _ConstellationContributeSheetState();
}

class _ConstellationContributeSheetState
    extends ConsumerState<_ConstellationContributeSheet> {
  ConstellationPrivacy _privacy = ConstellationPrivacy.sums;
  bool _consented = false;
  bool _busy = false;
  String? _error;
  bool _loadedChoice = false;

  /// Adopt the persisted privacy preference the first time it resolves, without
  /// clobbering a choice the user has already made in the sheet. Mutation is
  /// deferred to after the frame so it is never run during build.
  void _seedPrivacy(ConstellationPrivacy? stored) {
    if (_loadedChoice || stored == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_loadedChoice || !mounted) return;
      setState(() {
        _privacy = stored;
        _loadedChoice = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    // Seed the privacy toggle from the persisted preference once — the provider
    // is watched unconditionally and the mutation is deferred out of build.
    ref.listen<AsyncValue<ConstellationPrivacy>>(
      constellationPrivacyProvider,
      (_, next) => _seedPrivacy(next.valueOrNull),
    );
    _seedPrivacy(ref.watch(constellationPrivacyProvider).valueOrNull);

    return NightshadeDialog(
      title: 'Contribute to the swarm',
      icon: LucideIcons.upload,
      width: 560,
      showCloseButton: !_busy,
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        NightshadeButton(
          label: 'Contribute',
          icon: LucideIcons.upload,
          isLoading: _busy,
          onPressed: _consented && !_busy ? _contribute : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are about to add your imaging of '
            '"${widget.target.name.isEmpty ? 'target #${widget.target.targetId}' : widget.target.name}" '
            'to the shared co-add. Choose what leaves your device.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          for (final option in ConstellationPrivacy.values) ...[
            _PrivacyOption(
              option: option,
              selected: _privacy == option,
              onSelect: _busy ? null : () => setState(() => _privacy = option),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
          ],
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            severity: NightshadeAlertSeverity.info,
            compact: true,
            message: 'You only share additive co-add sums, so a contribution '
                'can be subtracted exactly hub-side — the shared depth returns '
                'to what it was before.',
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _ConsentRow(
            value: _consented,
            onChanged:
                _busy ? null : (v) => setState(() => _consented = v ?? false),
          ),
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

  Future<void> _contribute() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final settings = ref.read(settingsDaoProvider);
    try {
      await settings.setSetting(
        constellationPrivacySettingKey,
        _privacy.name,
      );
      final outcome = await ref
          .read(constellationServiceProvider)
          .contributeTarget(widget.target.targetId, privacy: _privacy.wire);
      if (!mounted) return;
      ref.invalidate(constellationPrivacyProvider);
      Navigator.of(context).pop(outcome);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeConstellationError(error);
      });
    }
  }
}

class _PrivacyOption extends StatelessWidget {
  final ConstellationPrivacy option;
  final bool selected;
  final VoidCallback? onSelect;

  const _PrivacyOption({
    required this.option,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final recommended = option == ConstellationPrivacy.sums;
    return NightshadeCard(
      variant: selected ? CardVariant.elevated : CardVariant.subtle,
      isSelected: selected,
      onTap: onSelect,
      padding: NightshadeTokens.cardPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        option.label,
                        style: NightshadeTypography.labelStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (recommended) ...[
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NightshadeTokens.spaceSm,
                          vertical: 2,
                        ),
                        decoration: NightshadeDecorations.tintedBadge(
                          colors.success,
                        ),
                        child: Text(
                          'DEFAULT',
                          style: NightshadeTypography.captionSm.copyWith(
                            color: colors.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  option.blurb,
                  style: NightshadeTypography.captionSm.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
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

class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _ConsentRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceXs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NightshadeCheckbox(value: value, onChanged: onChanged),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Text(
                'I understand what is being shared and consent to contributing '
                'it to this self-hosted hub.',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
