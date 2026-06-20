import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'cutout_strip.dart';
import 'transient_submit_dialog.dart';

/// One difference-imaging transient candidate, the heart of the First Light
/// discovery surface.
///
/// Top to bottom: the verdict header (named known source vs. the headline
/// *possible unknown transient*), the side-by-side template / frame / residual
/// [CutoutStrip], a metrics row (SNR, Δmag, FWHM, confidence, shape class), and
/// the triage / submit actions. Triage routes through [FirstLightTriage] so it
/// works identically on desktop (local DB) and mobile (NetworkBackend → host).
class TransientCandidateCard extends ConsumerWidget {
  const TransientCandidateCard({super.key, required this.detection});

  final TransientDetectionRow detection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusLg,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(detection: detection, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceMd),
          CutoutStrip(detection: detection),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _MetricsRow(detection: detection, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _ActionsRow(detection: detection, ref: ref, colors: colors),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detection, required this.colors});

  final TransientDetectionRow detection;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final isUnknown = detection.catalogMatch == null;
    final kind = TransientKind.fromWire(detection.kind);
    final verdictColor = isUnknown ? colors.accent : colors.info;
    final title =
        isUnknown ? 'Possible unknown transient' : detection.catalogMatch!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
          decoration: NightshadeDecorations.tintedBadge(verdictColor),
          child: Icon(
            _kindIcon(kind),
            size: NightshadeTokens.iconMd,
            color: verdictColor,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: NightshadeTypography.h4.copyWith(
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Row(
                children: [
                  Icon(
                    NightshadeIcons.crosshair,
                    size: NightshadeTokens.iconXs,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Flexible(
                    child: Text(
                      '${CoordinateFormat.ra(detection.raDeg / 15.0)}  '
                      '${CoordinateFormat.dec(detection.decDeg)}',
                      style: NightshadeTypography.monoSm.copyWith(
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _VerdictBadge(detection: detection, colors: colors),
      ],
    );
  }

  IconData _kindIcon(TransientKind kind) {
    switch (kind) {
      case TransientKind.newSource:
        return NightshadeIcons.sparkle;
      case TransientKind.pointBrightening:
        return NightshadeIcons.sun;
      case TransientKind.movingStreak:
        return LucideIcons.orbit;
      case TransientKind.dipole:
        return LucideIcons.circleDot;
    }
  }
}

/// The triage-state / catalog-verdict badge.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.detection, required this.colors});

  final TransientDetectionRow detection;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _info();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: NightshadeTokens.borderRadiusFull,
      ),
      child: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(color: color),
      ),
    );
  }

  (String, Color) _info() {
    if (detection.dismissed) return ('Dismissed', colors.textMuted);
    if (detection.reviewed) return ('Confirmed', colors.success);
    if (detection.catalogMatch == null) return ('Unnamed', colors.accent);
    return ('Matched', colors.info);
  }
}

/// Compact metrics chips: SNR, Δmag, FWHM, confidence, and the shape class.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.detection, required this.colors});

  final TransientDetectionRow detection;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final dm = detection.deltaMag;
    final chips = <Widget>[
      _MetricChip(
        icon: NightshadeIcons.activity,
        label: 'SNR ${detection.snr.toStringAsFixed(1)}',
        color: colors.textSecondary,
        colors: colors,
      ),
      if (dm != null && dm.isFinite)
        _MetricChip(
          icon: dm <= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
          label: '${dm <= 0 ? '+' : '-'}${dm.abs().toStringAsFixed(2)} mag',
          color: dm <= 0 ? colors.accent : colors.info,
          colors: colors,
        ),
      _MetricChip(
        icon: NightshadeIcons.circle,
        label: 'FWHM ${detection.fwhm.toStringAsFixed(1)} px',
        color: colors.textSecondary,
        colors: colors,
      ),
      _MetricChip(
        icon: LucideIcons.gauge,
        label: 'Conf ${(detection.confidence * 100).round()}%',
        color: _confidenceColor(detection.confidence),
        colors: colors,
      ),
      _MetricChip(
        icon: LucideIcons.shapes,
        label: _kindLabel(TransientKind.fromWire(detection.kind)),
        color: colors.textSecondary,
        colors: colors,
      ),
    ];

    return Wrap(
      spacing: NightshadeTokens.spaceSm,
      runSpacing: NightshadeTokens.spaceSm,
      children: chips,
    );
  }

  Color _confidenceColor(double c) {
    if (c >= 0.7) return colors.success;
    if (c >= 0.45) return colors.warning;
    return colors.textMuted;
  }

  String _kindLabel(TransientKind kind) {
    switch (kind) {
      case TransientKind.newSource:
        return 'New source';
      case TransientKind.pointBrightening:
        return 'Brightening';
      case TransientKind.movingStreak:
        return 'Moving streak';
      case TransientKind.dipole:
        return 'Dipole';
    }
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final Color color;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: NightshadeTokens.iconXs, color: color),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            label,
            style: NightshadeTypography.labelSm.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.detection,
    required this.ref,
    required this.colors,
  });

  final TransientDetectionRow detection;
  final WidgetRef ref;
  final NightshadeColors colors;

  Future<void> _triage(BuildContext context, {required bool dismiss}) async {
    final triage = ref.read(firstLightTriageProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (dismiss) {
        await triage.dismiss(detection.id);
      } else {
        await triage.review(detection.id);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            dismiss
                ? 'Dismissed as an artefact — it will not resurface.'
                : 'Marked as confirmed.',
          ),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not update detection: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: 'Submit',
            icon: NightshadeIcons.upload,
            size: ButtonSize.small,
            variant: ButtonVariant.primary,
            onPressed: () => TransientSubmitDialog.show(context, detection),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: detection.reviewed
              ? _ConfirmedPill(colors: colors)
              : NightshadeButton(
                  label: 'Confirm',
                  icon: NightshadeIcons.check,
                  size: ButtonSize.small,
                  variant: ButtonVariant.outline,
                  onPressed: () => _triage(context, dismiss: false),
                ),
        ),
      ],
    );

    final dismissAction = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: NightshadeTokens.minTouchTarget,
        minHeight: NightshadeTokens.minTouchTarget,
      ),
      child: IconButton(
        icon: Icon(
          NightshadeIcons.close,
          size: NightshadeTokens.iconMd,
          color: detection.dismissed ? colors.textMuted : colors.textSecondary,
        ),
        tooltip: detection.dismissed ? 'Already dismissed' : 'Dismiss artefact',
        onPressed:
            detection.dismissed ? null : () => _triage(context, dismiss: true),
        style: IconButton.styleFrom(
          backgroundColor: colors.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: NightshadeTokens.borderRadiusSm,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < NightshadeTokens.breakpointMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: NightshadeTokens.spaceSm),
              Align(alignment: Alignment.centerRight, child: dismissAction),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: NightshadeTokens.spaceSm),
            dismissAction,
          ],
        );
      },
    );
  }
}

class _ConfirmedPill extends StatelessWidget {
  const _ConfirmedPill({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: NightshadeDecorations.tintedBadge(
        colors.success,
        borderRadius: NightshadeTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            NightshadeIcons.check,
            size: NightshadeTokens.iconSm,
            color: colors.success,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            'Confirmed',
            style: NightshadeTypography.labelSm.copyWith(color: colors.success),
          ),
        ],
      ),
    );
  }
}
