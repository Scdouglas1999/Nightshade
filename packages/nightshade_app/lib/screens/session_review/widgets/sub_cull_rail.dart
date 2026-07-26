import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../session_review_controller.dart';
import '../../../utils/filter_label.dart';

/// Workbench evolution of [SubGalleryPanel]: the same grade-badged sub grid with
/// **blink** + **bulk-reject below threshold**, plus two power-user culling
/// affordances the narrative gallery lacks:
///
///  * **Multi-select / lasso cull** — tap to toggle a selection, or drag a
///    rubber-band rectangle over the grid to select every sub it touches, then
///    reject the whole selection in one action.
///  * **"Drop to recommended keepN"** — wired to the improvement curve's
///    [SubsetRecommendation]: rejects every accepted sub the optimizer does not
///    recommend keeping (down to `keepN`), in one click, with the predicted
///    SNR gain surfaced on the action chip.
///
/// One controller, two renderings: the narrative screen uses [SubGalleryPanel];
/// the workbench uses this rail over the *same* `state.lights` + the same
/// accept/reject + bulk-cull controller actions.
class SubCullRail extends ConsumerStatefulWidget {
  /// The light subs to review (accepted + rejected), capture-time ascending.
  final List<DbCapturedImage> subs;

  /// The controller — read for the improvement curve and driven for the
  /// "drop to recommended" cull. Per-sub accept/reject and bulk-cull still flow
  /// through the explicit callbacks below so this rail composes with either
  /// scope without re-reading the provider family.
  final SessionReviewController controller;

  /// Open the per-sub detail dialog.
  final void Function(DbCapturedImage) onTapSub;

  /// Flip a single sub's accept flag.
  final void Function(int imageId, bool accepted) onSetAccepted;

  /// Reject every accepted sub above [hfrThreshold] (the threshold-bulk cull).
  final void Function({double? hfrThreshold, double? qualityThreshold})
      onBulkCull;

  const SubCullRail({
    super.key,
    required this.subs,
    required this.controller,
    required this.onTapSub,
    required this.onSetAccepted,
    required this.onBulkCull,
  });

  /// The grid's max cross-axis cell extent — mirrors the [SliverGridDelegate]
  /// `maxCrossAxisExtent` the grid lays out with. Exposed so the boundary-width
  /// regression test can build the same delegate.
  @visibleForTesting
  static const double lassoCellExtent = 200;

  /// The grid's cross-axis spacing — mirrors the delegate `crossAxisSpacing`.
  @visibleForTesting
  static const double lassoCellSpacing = NightshadeTokens.spaceMd;

  /// Column count the lasso hit-test uses for [innerWidth] (content width inside
  /// the grid padding). Matches Flutter's
  /// `SliverGridDelegateWithMaxCrossAxisExtent.getLayout` exactly:
  ///   `crossAxisCount = (crossAxisExtent / (maxCrossAxisExtent + spacing)).ceil()`
  /// with NO `+ spacing` added to the numerator. Adding it (the previous bug)
  /// yields one extra column at widths near a multiple of (maxExtent + spacing),
  /// which throws off every per-cell rect and mis-selects subs at the lasso
  /// boundary.
  static int lassoGridColumns(double innerWidth) {
    final cols = (innerWidth / (lassoCellExtent + lassoCellSpacing)).ceil();
    return cols < 1 ? 1 : cols;
  }

  @override
  ConsumerState<SubCullRail> createState() => _SubCullRailState();
}

class _SubCullRailState extends ConsumerState<SubCullRail> {
  // --- blink (kept from SubGalleryPanel) ---
  bool _blink = false;
  int _blinkIndex = 0;
  Timer? _blinkTimer;

  // --- threshold bulk-cull (kept from SubGalleryPanel) ---
  double _hfrCull = 3.5;

  // --- multi-select / lasso (new) ---
  bool _selectMode = false;
  final Set<int> _selected = <int>{};

  // Lasso drag state, in the grid's local coordinate space.
  Offset? _lassoStart;
  Offset? _lassoEnd;
  // Cell rects captured during layout so the lasso can hit-test them.
  final Map<int, Rect> _cellRects = <int, Rect>{};

  // The latest improvement curve, kept in sync by listening to the controller
  // directly so the rail tracks the live state without re-deriving the provider
  // scope (the workbench passes the controller, not the scope).
  IntegrationCurve? _curve;
  RemoveListener? _removeControllerListener;
  void _onControllerChanged(SessionReviewState s) {
    if (!mounted) return;
    final next = s.improvementCurve;
    if (next != _curve) setState(() => _curve = next);
  }

  @override
  void initState() {
    super.initState();
    _removeControllerListener =
        widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SubCullRail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller)) {
      _removeControllerListener?.call();
      _removeControllerListener =
          widget.controller.addListener(_onControllerChanged);
    }

    final currentIds = widget.subs.map((sub) => sub.id).toSet();
    _selected.removeWhere((id) => !currentIds.contains(id));
    _cellRects.removeWhere((id, _) => !currentIds.contains(id));

    if (widget.subs.isEmpty) {
      _blinkTimer?.cancel();
      _blinkTimer = null;
      _blink = false;
      _blinkIndex = 0;
      _lassoStart = null;
      _lassoEnd = null;
    } else if (_blinkIndex >= widget.subs.length) {
      _blinkIndex = 0;
    }
  }

  @override
  void dispose() {
    _removeControllerListener?.call();
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _toggleBlink() {
    setState(() {
      _blink = !_blink;
      _blinkIndex = 0;
    });
    _blinkTimer?.cancel();
    if (_blink && widget.subs.isNotEmpty) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (!mounted || widget.subs.isEmpty) {
          _blinkTimer?.cancel();
          _blinkTimer = null;
          if (mounted) {
            setState(() {
              _blink = false;
              _blinkIndex = 0;
            });
          }
          return;
        }
        setState(() => _blinkIndex = (_blinkIndex + 1) % widget.subs.length);
      });
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) {
        _selected.clear();
        _lassoStart = null;
        _lassoEnd = null;
      }
    });
  }

  void _toggleSelected(int imageId) {
    setState(() {
      if (!_selected.add(imageId)) _selected.remove(imageId);
    });
  }

  Future<void> _rejectSelected() async {
    final ids = _selected.toList();
    final currentSubs = {for (final sub in widget.subs) sub.id: sub};
    for (final id in ids) {
      final sub = currentSubs[id];
      if (sub == null) continue;
      if (sub.isAccepted) widget.onSetAccepted(id, false);
    }
    setState(() {
      _selected.clear();
      _lassoStart = null;
      _lassoEnd = null;
    });
  }

  Future<void> _cullToRecommended(IntegrationCurve curve) async {
    final result = await widget.controller.cullToRecommended();
    if (!mounted) return;
    final keepN = curve.recommendation.keepN;
    final String message;
    switch (result.outcome) {
      case CullOutcome.culled:
        message = 'Culled to best $keepN subs (${result.rejected} rejected, '
            '+${curve.recommendation.predictedSnrGainPct.toStringAsFixed(0)}% SNR)';
        break;
      case CullOutcome.alreadyOptimal:
        message = 'Already at the recommended $keepN subs';
        break;
      case CullOutcome.staleCurve:
        message =
            'Curve is out of date — re-integrate to refresh before culling';
        break;
    }
    NightshadeToastHelper.show(
      context: context,
      message: message,
      severity: NightshadeAlertSeverity.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    if (widget.subs.isEmpty) {
      return const EmptyState(
        icon: NightshadeIcons.imageOff,
        title: 'No light subs',
        body: 'This session captured no light frames to review.',
      );
    }

    final curve = _curve;

    const assessor = FrameQualityAssessmentService();
    final assessments = assessor.assessBatch(widget.subs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NightshadeTokens.spaceLg,
            NightshadeTokens.spaceMd,
            NightshadeTokens.spaceLg,
            NightshadeTokens.spaceSm,
          ),
          child: _CullToolbar(
            blink: _blink,
            selectMode: _selectMode,
            selectedCount: _selected.length,
            hfrThreshold: _hfrCull,
            curve: curve,
            onToggleBlink: _toggleBlink,
            onToggleSelect: _toggleSelectMode,
            onHfrChanged: (v) => setState(() => _hfrCull = v),
            onBulkCull: () => widget.onBulkCull(hfrThreshold: _hfrCull),
            onRejectSelected: _selected.isEmpty ? null : _rejectSelected,
            onClearSelection: _selected.isEmpty
                ? null
                : () => setState(() => _selected.clear()),
            onCullToRecommended: curve != null && curve.recommendation.keepN > 0
                ? () => _cullToRecommended(curve)
                : null,
          ),
        ),
        if (_blink)
          Expanded(child: _BlinkView(sub: widget.subs[_blinkIndex]))
        else
          Expanded(child: _buildGrid(assessments, colors)),
      ],
    );
  }

  // Fixed grid geometry — kept in lock-step with the SliverGridDelegate below
  // so the lasso can hit-test cell rects analytically (a GridView gives no
  // per-cell rect, and reporting them from render objects is brittle under
  // scrolling). Padding + spacing + aspect ratio fully determine the layout.
  static const double _gridPad = NightshadeTokens.spaceLg;
  static const double _maxCellExtent = SubCullRail.lassoCellExtent;
  static const double _cellSpacing = SubCullRail.lassoCellSpacing;
  static const double _cellAspect = 0.82; // width / height

  /// Resolve column count, cell width and cell height for [innerWidth] (the
  /// content width inside the grid padding), matching Flutter's
  /// max-cross-axis-extent packing.
  ({int cols, double cellW, double cellH}) _gridMetrics(double innerWidth) {
    final cols = SubCullRail.lassoGridColumns(innerWidth);
    final cellW = (innerWidth - (cols - 1) * _cellSpacing) / cols;
    final cellH = cellW / _cellAspect;
    return (cols: cols, cellW: cellW, cellH: cellH);
  }

  /// Recompute every cell's rect (relative to the gesture surface origin) and
  /// select those the [marquee] overlaps.
  void _applyLasso(Rect marquee, double innerWidth) {
    final m = _gridMetrics(innerWidth);
    _cellRects.clear();
    for (var i = 0; i < widget.subs.length; i++) {
      final col = i % m.cols;
      final row = i ~/ m.cols;
      final left = _gridPad + col * (m.cellW + _cellSpacing);
      final top = _gridPad + row * (m.cellH + _cellSpacing);
      final rect = Rect.fromLTWH(left, top, m.cellW, m.cellH);
      _cellRects[widget.subs[i].id] = rect;
      if (rect.overlaps(marquee)) _selected.add(widget.subs[i].id);
    }
  }

  Widget _buildGrid(
    Map<int, FrameQualityAssessment> assessments,
    NightshadeColors colors,
  ) {
    final grid = GridView.builder(
      padding: const EdgeInsets.all(_gridPad),
      physics: _selectMode
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _maxCellExtent,
        mainAxisSpacing: _cellSpacing,
        crossAxisSpacing: _cellSpacing,
        childAspectRatio: _cellAspect,
      ),
      itemCount: widget.subs.length,
      itemBuilder: (context, index) {
        final sub = widget.subs[index];
        return _SubTile(
          sub: sub,
          assessment: assessments[sub.id],
          selectMode: _selectMode,
          selected: _selected.contains(sub.id),
          onTap: _selectMode
              ? () => _toggleSelected(sub.id)
              : () => widget.onTapSub(sub),
          onToggleAccept: () => widget.onSetAccepted(sub.id, !sub.isAccepted),
          colors: colors,
        );
      },
    );

    if (!_selectMode) return grid;

    // In select mode the grid stops scrolling; a GestureDetector captures the
    // rubber-band lasso and a CustomPaint draws the marquee. Cell hit-testing
    // is analytic against the grid geometry resolved from this width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final innerWidth = constraints.maxWidth - 2 * _gridPad;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (d) =>
              setState(() => _lassoStart = _lassoEnd = d.localPosition),
          onPanUpdate: (d) {
            if (_lassoStart == null) return;
            setState(() => _lassoEnd = d.localPosition);
          },
          onPanEnd: (_) {
            final s = _lassoStart, e = _lassoEnd;
            if (s != null && e != null) {
              setState(() => _applyLasso(Rect.fromPoints(s, e), innerWidth));
            }
            setState(() => _lassoStart = _lassoEnd = null);
          },
          child: Stack(
            children: [
              grid,
              if (_lassoStart != null && _lassoEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _LassoPainter(
                        rect: Rect.fromPoints(_lassoStart!, _lassoEnd!),
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CullToolbar extends StatelessWidget {
  final bool blink;
  final bool selectMode;
  final int selectedCount;
  final double hfrThreshold;
  final IntegrationCurve? curve;
  final VoidCallback onToggleBlink;
  final VoidCallback onToggleSelect;
  final ValueChanged<double> onHfrChanged;
  final VoidCallback onBulkCull;
  final VoidCallback? onRejectSelected;
  final VoidCallback? onClearSelection;
  final VoidCallback? onCullToRecommended;

  const _CullToolbar({
    required this.blink,
    required this.selectMode,
    required this.selectedCount,
    required this.hfrThreshold,
    required this.curve,
    required this.onToggleBlink,
    required this.onToggleSelect,
    required this.onHfrChanged,
    required this.onBulkCull,
    required this.onRejectSelected,
    required this.onClearSelection,
    required this.onCullToRecommended,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final keepN = curve?.recommendation.keepN ?? 0;
    final gainPct = curve?.recommendation.predictedSnrGainPct ?? 0;

    return Wrap(
      spacing: NightshadeTokens.spaceMd,
      runSpacing: NightshadeTokens.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NightshadeButton(
          label: blink ? 'Stop blink' : 'Blink mode',
          icon: NightshadeIcons.play,
          variant: blink ? ButtonVariant.primary : ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onToggleBlink,
        ),
        NightshadeButton(
          label: selectMode ? 'Done selecting' : 'Select / lasso',
          icon: NightshadeIcons.crosshair,
          variant: selectMode ? ButtonVariant.primary : ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onToggleSelect,
        ),
        if (selectMode) ...[
          _SelectionPill(count: selectedCount, colors: colors),
          NightshadeButton(
            label: 'Reject selected',
            icon: NightshadeIcons.error,
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: onRejectSelected,
          ),
          NightshadeButton(
            label: 'Clear',
            icon: NightshadeIcons.close,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: onClearSelection,
          ),
        ],
        if (onCullToRecommended != null)
          Tooltip(
            message:
                'Drop to the optimizer-recommended best $keepN subs (+${gainPct.toStringAsFixed(0)}% SNR)',
            child: NightshadeButton(
              label: 'Keep best $keepN (+${gainPct.toStringAsFixed(0)}%)',
              icon: NightshadeIcons.success,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onCullToRecommended,
            ),
          ),
        if (!selectMode)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cull HFR >',
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textSecondary),
              ),
              SizedBox(
                width: 160,
                child: Slider(
                  value: hfrThreshold.clamp(1.0, 8.0),
                  min: 1.0,
                  max: 8.0,
                  divisions: 28,
                  activeColor: colors.primary,
                  label: hfrThreshold.toStringAsFixed(1),
                  onChanged: onHfrChanged,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  hfrThreshold.toStringAsFixed(1),
                  style: NightshadeTypography.mono
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        if (!selectMode)
          NightshadeButton(
            label: 'Reject HFR above',
            icon: NightshadeIcons.error,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onBulkCull,
          ),
      ],
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final int count;
  final NightshadeColors colors;
  const _SelectionPill({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.primary
            .withValues(alpha: NightshadeTokens.opacityStatusFill),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
        border: Border.all(color: colors.primary),
      ),
      child: Text(
        '$count selected',
        style: NightshadeTypography.labelSm.copyWith(color: colors.primary),
      ),
    );
  }
}

class _LassoPainter extends CustomPainter {
  final Rect rect;
  final Color color;

  _LassoPainter({required this.rect, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color.withValues(alpha: NightshadeTokens.opacityStatusFill)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(_LassoPainter old) =>
      old.rect != rect || old.color != color;
}

class _SubTile extends ConsumerWidget {
  final DbCapturedImage sub;
  final FrameQualityAssessment? assessment;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleAccept;
  final NightshadeColors colors;

  const _SubTile({
    required this.sub,
    required this.assessment,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onToggleAccept,
    required this.colors,
  });

  /// Colour of the top-left grade badge — driven purely by the QUALITY GRADE,
  /// not by accept/reject state. A GOOD sub shows a green GOOD badge whether it
  /// was kept or culled; the reject state is conveyed separately by the
  /// "REJECTED" chip + amber ✕ + card dimming, so the grade must not be
  /// recoloured red just because the sub was rejected.
  Color _gradeColor() {
    switch (assessment?.level) {
      case FrameQualityLevel.good:
        return colors.success;
      case FrameQualityLevel.needsReview:
        return colors.warning;
      case FrameQualityLevel.poor:
        return colors.error;
      case null:
        return colors.border;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grade = _gradeColor();
    return NightshadeCard(
      onTap: onTap,
      enableHover: true,
      isSelected: selected,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NightshadeTokens.radiusMd),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SubThumbnail(imageId: sub.id, colors: colors),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _Badge(
                      text: (assessment?.label ?? 'N/A').toUpperCase(),
                      color: grade,
                    ),
                  ),
                  if (sub.hfr != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _Badge(
                        text: 'HFR ${sub.hfr!.toStringAsFixed(1)}',
                        color: colors.info,
                      ),
                    ),
                  if (selectMode)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _SelectMarker(selected: selected, colors: colors),
                    )
                  else
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _AcceptToggle(
                        accepted: sub.isAccepted,
                        onTap: onToggleAccept,
                        colors: colors,
                      ),
                    ),
                  if (!sub.isAccepted)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: _Badge(text: 'REJECTED', color: colors.error),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${filterLabel(sub.filter)} · ${sub.exposureDuration.toInt()}s',
                    style: NightshadeTypography.labelSm
                        .copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sub.starCount != null)
                  Text(
                    '${sub.starCount}★',
                    style: NightshadeTypography.caption
                        .copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectMarker extends StatelessWidget {
  final bool selected;
  final NightshadeColors colors;
  const _SelectMarker({required this.selected, required this.colors});

  @override
  Widget build(BuildContext context) {
    final color = selected ? colors.primary : colors.surfaceOverlay;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: Icon(
        selected ? NightshadeIcons.check : NightshadeIcons.crosshair,
        size: 14,
        color: selected ? colors.onPrimary : colors.textSecondary,
      ),
    );
  }
}

class _SubThumbnail extends ConsumerStatefulWidget {
  final int imageId;
  final NightshadeColors colors;

  const _SubThumbnail({required this.imageId, required this.colors});

  @override
  ConsumerState<_SubThumbnail> createState() => _SubThumbnailState();
}

class _SubThumbnailState extends ConsumerState<_SubThumbnail> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(imagingBackendProvider).getImageThumbnail(widget.imageId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.colors.surface,
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
          }
          return _placeholder();
        },
      ),
    );
  }

  Widget _placeholder() => Center(
        child: Icon(
          NightshadeIcons.image,
          size: 28,
          color: widget.colors.textMuted,
        ),
      );
}

class _AcceptToggle extends StatelessWidget {
  final bool accepted;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _AcceptToggle({
    required this.accepted,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final color = accepted ? colors.success : colors.warning;
    return Tooltip(
      message: accepted ? 'Reject this sub' : 'Accept this sub',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: Icon(
            accepted ? NightshadeIcons.check : NightshadeIcons.error,
            size: 14,
            color: colors.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
      ),
      child: Text(
        text,
        style: NightshadeTypography.captionSm.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Full-bleed single-sub view used by blink mode (kept from [SubGalleryPanel]).
class _BlinkView extends ConsumerWidget {
  final DbCapturedImage sub;
  const _BlinkView({required this.sub});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return Container(
      color: colors.background,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<Uint8List>(
              future:
                  ref.read(imagingBackendProvider).getImageThumbnail(sub.id),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null && bytes.isNotEmpty) {
                  return Image.memory(bytes, fit: BoxFit.contain);
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                return Center(
                  child: Icon(NightshadeIcons.imageOff,
                      size: 48, color: colors.textMuted),
                );
              },
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            '${sub.fileName} · ${filterLabel(sub.filter)} · '
            '${sub.exposureDuration.toInt()}s'
            '${sub.hfr != null ? ' · HFR ${sub.hfr!.toStringAsFixed(2)}' : ''}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NightshadeTypography.bodySm
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
