import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../session_review_controller.dart';
import 'master_preview_view.dart';

/// Side-by-side A/B comparison of two [IntegrationSettings] recipes over the
/// same accepted subs.
///
/// Each side runs `controller.reIntegratePreview(settings)` — a throwaway,
/// non-persisting integration — and renders the resulting master preview
/// (reusing [MasterPreviewView]) plus a compact stat block (frames integrated /
/// rejected, integration time, residual, dimensions). A diff strip under the
/// previews calls out which recipe won on each metric so the imager can pick a
/// finishing recipe by eye *and* by number.
///
/// The comparison is exploratory: it must not change the controller's working
/// settings, persist a master, or flip the shared hero/`lastOutcome`. The
/// preview path guarantees that — see [SessionReviewController.reIntegratePreview].
///
/// Recipe A defaults to the controller's current working settings; recipe B
/// seeds a sensible "tighter rejection" variant the user can edit via the
/// recipe chips. Per the CONTRACT this panel drives everything through the one
/// [SessionReviewController] — no separate provider read — but only via the
/// non-persisting preview path, so a comparison stays a comparison.
class AbComparePanel extends StatefulWidget {
  final SessionReviewController controller;

  const AbComparePanel({super.key, required this.controller});

  @override
  State<AbComparePanel> createState() => _AbComparePanelState();
}

class _AbComparePanelState extends State<AbComparePanel> {
  IntegrationSettings? _recipeA;
  IntegrationSettings? _recipeB;

  PostSessionIntegrationOutcome? _outcomeA;
  PostSessionIntegrationOutcome? _outcomeB;
  bool _runningA = false;
  bool _runningB = false;
  String? _error;
  RemoveListener? _removeListener;

  @override
  void initState() {
    super.initState();
    // Seed recipe A from the controller's current working settings (and B from
    // a tighter-rejection variant) the first time the controller publishes its
    // state. Listening avoids the deprecated `debugState` getter and keeps A in
    // sync if the user edits settings elsewhere before running a comparison.
    _removeListener = widget.controller.addListener((state) {
      if (_recipeA != null) return; // seed once; edits below own the recipes
      setState(() {
        _recipeA = state.settings;
        _recipeB = _tighterRejection(state.settings);
      });
    });
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  /// A defensible "B" seed: the same recipe with tighter sigma rejection — the
  /// most common A/B question ("did clipping harder help or hurt?").
  static IntegrationSettings _tighterRejection(IntegrationSettings base) {
    return base.copyWith(
      reject: RejectAlgorithm.sigmaClip,
      rejectLow: (base.rejectLow - 0.5).clamp(1.0, 6.0),
      rejectHigh: (base.rejectHigh - 0.5).clamp(1.0, 6.0),
    );
  }

  Future<void> _run({required bool isA}) async {
    final recipe = isA ? _recipeA : _recipeB;
    if (recipe == null) return;
    setState(() {
      if (isA) {
        _runningA = true;
      } else {
        _runningB = true;
      }
      _error = null;
    });
    final outcome = await widget.controller.reIntegratePreview(recipe);
    if (!mounted) return;
    setState(() {
      if (isA) {
        _runningA = false;
        _outcomeA = outcome;
      } else {
        _runningB = false;
        _outcomeB = outcome;
      }
      if (outcome == null) {
        _error = 'Re-integration failed for recipe ${isA ? 'A' : 'B'}.';
      }
    });
  }

  Future<void> _runBoth() async {
    await _run(isA: true);
    if (!mounted) return;
    await _run(isA: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final recipeA = _recipeA;
    final recipeB = _recipeB;
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(NightshadeIcons.layers,
                    size: NightshadeTokens.iconSm, color: colors.accent),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  'A / B recipe compare',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
                const Spacer(),
                NightshadeButton(
                  label: 'Run both',
                  icon: NightshadeIcons.play,
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                  isLoading: _runningA || _runningB,
                  onPressed:
                      (recipeA == null || _runningA || _runningB) ? null : _runBoth,
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            if (_error != null) ...[
              NightshadeAlert(
                severity: NightshadeAlertSeverity.error,
                message: _error!,
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
            ],
            if (recipeA == null || recipeB == null)
              const Padding(
                padding: EdgeInsets.symmetric(
                    vertical: NightshadeTokens.space4xl),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RecipeColumn(
                        label: 'A',
                        accent: colors.info,
                        settings: recipeA,
                        outcome: _outcomeA,
                        running: _runningA,
                        onEdit: (s) => setState(() => _recipeA = s),
                        onRun: () => _run(isA: true),
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceMd),
                    Expanded(
                      child: _RecipeColumn(
                        label: 'B',
                        accent: colors.accent,
                        settings: recipeB,
                        outcome: _outcomeB,
                        running: _runningB,
                        onEdit: (s) => setState(() => _recipeB = s),
                        onRun: () => _run(isA: false),
                      ),
                    ),
                  ],
                ),
              ),
              if (_outcomeA != null && _outcomeB != null) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                _DiffStrip(a: _outcomeA!.result, b: _outcomeB!.result),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeColumn extends StatelessWidget {
  final String label;
  final Color accent;
  final IntegrationSettings settings;
  final PostSessionIntegrationOutcome? outcome;
  final bool running;
  final ValueChanged<IntegrationSettings> onEdit;
  final VoidCallback onRun;

  const _RecipeColumn({
    required this.label,
    required this.accent,
    required this.settings,
    required this.outcome,
    required this.running,
    required this.onEdit,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.subtle,
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: NightshadeTokens.spaceLg,
                  height: NightshadeTokens.spaceLg,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                        alpha: NightshadeTokens.opacityStatusFill),
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusSm),
                    border: Border.all(color: accent),
                  ),
                  child: Text(
                    label,
                    style: NightshadeTypography.labelStrongSm
                        .copyWith(color: accent),
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    _recipeSummary(settings),
                    style: NightshadeTypography.bodySm
                        .copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                NightshadeButton(
                  label: 'Run',
                  icon: NightshadeIcons.refresh,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  isLoading: running,
                  onPressed: running ? null : onRun,
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            _RecipeChips(settings: settings, onEdit: onEdit),
            const SizedBox(height: NightshadeTokens.spaceMd),
            SizedBox(
              height: 280,
              child: outcome != null
                  ? MasterPreviewView.fromOutcome(outcome!)
                  : _PreviewPlaceholder(running: running),
            ),
            if (outcome != null) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              _StatBlock(result: outcome!.result),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact editable knobs for the most A/B-relevant settings (rejection +
/// combine). Heavier editing lives in the full integration settings panel; here
/// we expose just enough to make a meaningful comparison without leaving.
class _RecipeChips extends StatelessWidget {
  final IntegrationSettings settings;
  final ValueChanged<IntegrationSettings> onEdit;

  const _RecipeChips({required this.settings, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Wrap(
      spacing: NightshadeTokens.spaceSm,
      runSpacing: NightshadeTokens.spaceXs,
      children: [
        _Chip(
          icon: NightshadeIcons.filter,
          label: 'Reject: ${_rejectLabel(settings.reject)}',
          colors: colors,
        ),
        _Chip(
          icon: NightshadeIcons.sliders,
          label:
              'clip ${settings.rejectLow.toStringAsFixed(1)}/${settings.rejectHigh.toStringAsFixed(1)}',
          colors: colors,
        ),
        _Chip(
          icon: NightshadeIcons.layers,
          label: 'Combine: ${_combineLabel(settings.combine)}',
          colors: colors,
        ),
        if (settings.weightingEnabled)
          _Chip(
            icon: NightshadeIcons.gauge,
            label: 'Weighted',
            colors: colors,
          ),
        if (settings.drizzle)
          _Chip(
            icon: NightshadeIcons.grid,
            label: 'Drizzle ${settings.drizzleScale.toStringAsFixed(1)}×',
            colors: colors,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _Chip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: NightshadeTokens.iconXs, color: colors.textMuted),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            label,
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final bool running;
  const _PreviewPlaceholder({required this.running});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border),
      ),
      alignment: Alignment.center,
      child: running
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  'Integrating…',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(NightshadeIcons.image,
                    size: NightshadeTokens.iconXl, color: colors.textMuted),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  'Run this recipe to preview',
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final IntegrateSessionResult result;
  const _StatBlock({required this.result});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Wrap(
      spacing: NightshadeTokens.spaceLg,
      runSpacing: NightshadeTokens.spaceXs,
      children: [
        _Stat(
          label: 'Integrated',
          value: '${result.framesIntegrated}',
          colors: colors,
        ),
        _Stat(
          label: 'Rejected',
          value: '${result.framesRejected}',
          colors: colors,
        ),
        _Stat(
          label: 'Time',
          value: formatHms(result.totalIntegrationSec),
          colors: colors,
        ),
        _Stat(
          label: 'Residual',
          value: '${result.rmsResidual.toStringAsFixed(2)} px',
          colors: colors,
        ),
        _Stat(
          label: 'Size',
          value: '${result.width}×${result.height}',
          colors: colors,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _Stat({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: NightshadeTypography.statValue.copyWith(color: colors.textPrimary),
        ),
        Text(
          label.toUpperCase(),
          style: NightshadeTypography.statLabel.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// Per-metric winner callout under the two previews.
class _DiffStrip extends StatelessWidget {
  final IntegrateSessionResult a;
  final IntegrateSessionResult b;

  const _DiffStrip({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.subtle,
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Winner by metric',
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Wrap(
              spacing: NightshadeTokens.spaceMd,
              runSpacing: NightshadeTokens.spaceXs,
              children: [
                _DiffPill(
                  metric: 'Frames kept',
                  winner: _cmp(a.framesIntegrated, b.framesIntegrated,
                      higherIsBetter: true),
                  detail: '${a.framesIntegrated} vs ${b.framesIntegrated}',
                  colors: colors,
                ),
                _DiffPill(
                  metric: 'Residual',
                  winner: _cmp(a.rmsResidual, b.rmsResidual,
                      higherIsBetter: false),
                  detail:
                      '${a.rmsResidual.toStringAsFixed(2)} vs ${b.rmsResidual.toStringAsFixed(2)} px',
                  colors: colors,
                ),
                _DiffPill(
                  metric: 'Integration time',
                  winner: _cmp(a.totalIntegrationSec, b.totalIntegrationSec,
                      higherIsBetter: true),
                  detail:
                      '${formatHms(a.totalIntegrationSec)} vs ${formatHms(b.totalIntegrationSec)}',
                  colors: colors,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Returns 'A', 'B', or '=' for the winning recipe on a metric.
  static String _cmp(num x, num y, {required bool higherIsBetter}) {
    if (x == y) return '=';
    final aWins = higherIsBetter ? x > y : x < y;
    return aWins ? 'A' : 'B';
  }
}

class _DiffPill extends StatelessWidget {
  final String metric;
  final String winner;
  final String detail;
  final NightshadeColors colors;

  const _DiffPill({
    required this.metric,
    required this.winner,
    required this.detail,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final tint = winner == 'A'
        ? colors.info
        : winner == 'B'
            ? colors.accent
            : colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: NightshadeTokens.opacityStatusFill),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: tint),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metric,
                style: NightshadeTypography.labelSm
                    .copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                winner == '=' ? 'tie' : 'wins: $winner',
                style: NightshadeTypography.labelStrongSm.copyWith(color: tint),
              ),
            ],
          ),
          Text(
            detail,
            style: NightshadeTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

String _recipeSummary(IntegrationSettings s) {
  final parts = <String>[
    _combineLabel(s.combine),
    _rejectLabel(s.reject),
    'clip ${s.rejectLow.toStringAsFixed(1)}/${s.rejectHigh.toStringAsFixed(1)}',
    if (s.weightingEnabled) 'weighted',
    if (s.drizzle) 'drizzle',
  ];
  return parts.join(' · ');
}

String _rejectLabel(RejectAlgorithm r) {
  switch (r) {
    case RejectAlgorithm.auto:
      return 'auto';
    case RejectAlgorithm.none:
      return 'none';
    case RejectAlgorithm.sigmaClip:
      return 'sigma';
    case RejectAlgorithm.winsorizedSigma:
      return 'winsorized';
    case RejectAlgorithm.linearFit:
      return 'linear-fit';
    case RejectAlgorithm.percentile:
      return 'percentile';
    case RejectAlgorithm.minMax:
      return 'min/max';
  }
}

String _combineLabel(CombineMode c) {
  switch (c) {
    case CombineMode.mean:
      return 'mean';
    case CombineMode.median:
      return 'median';
  }
}
