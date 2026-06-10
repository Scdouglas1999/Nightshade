import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

/// Bulk-cull callback signature: rejects accepted subs above [hfrThreshold] or
/// below [qualityThreshold].
typedef BulkCullCallback = void Function({
  double? hfrThreshold,
  double? qualityThreshold,
});

/// First-class sub gallery for the Session Review screen: a responsive grid of
/// the night's light subs with quality badges (grade / HFR / stars), per-sub
/// accept/reject culling, a "blink" mode that cycles subs to spot clouds /
/// satellites by eye, and a bulk "reject all below threshold" control.
///
/// Reuses the [FrameQualityAssessmentService] grade + [imagingBackendProvider]
/// thumbnail loading already used by the analytics thumbnail strip, promoted
/// from a horizontal rail into a full panel.
class SubGalleryPanel extends ConsumerStatefulWidget {
  final List<DbCapturedImage> subs;
  final void Function(DbCapturedImage) onTapSub;
  final void Function(int imageId, bool accepted) onSetAccepted;
  final BulkCullCallback onBulkCull;

  const SubGalleryPanel({
    super.key,
    required this.subs,
    required this.onTapSub,
    required this.onSetAccepted,
    required this.onBulkCull,
  });

  @override
  ConsumerState<SubGalleryPanel> createState() => _SubGalleryPanelState();
}

class _SubGalleryPanelState extends ConsumerState<SubGalleryPanel> {
  bool _blink = false;
  int _blinkIndex = 0;
  Timer? _blinkTimer;
  double _hfrCull = 3.5;

  @override
  void dispose() {
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
        if (!mounted) return;
        setState(() => _blinkIndex = (_blinkIndex + 1) % widget.subs.length);
      });
    }
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
          child: _Toolbar(
            blink: _blink,
            hfrThreshold: _hfrCull,
            onToggleBlink: _toggleBlink,
            onHfrChanged: (v) => setState(() => _hfrCull = v),
            onBulkCull: () => widget.onBulkCull(hfrThreshold: _hfrCull),
          ),
        ),
        if (_blink)
          Expanded(child: _BlinkView(sub: widget.subs[_blinkIndex]))
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: NightshadeTokens.spaceMd,
                crossAxisSpacing: NightshadeTokens.spaceMd,
                childAspectRatio: 0.82,
              ),
              itemCount: widget.subs.length,
              itemBuilder: (context, index) {
                final sub = widget.subs[index];
                return _SubTile(
                  sub: sub,
                  assessment: assessments[sub.id],
                  onTap: () => widget.onTapSub(sub),
                  onToggleAccept: () =>
                      widget.onSetAccepted(sub.id, !sub.isAccepted),
                  colors: colors,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool blink;
  final double hfrThreshold;
  final VoidCallback onToggleBlink;
  final ValueChanged<double> onHfrChanged;
  final VoidCallback onBulkCull;

  const _Toolbar({
    required this.blink,
    required this.hfrThreshold,
    required this.onToggleBlink,
    required this.onHfrChanged,
    required this.onBulkCull,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
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
        NightshadeButton(
          label: 'Reject below threshold',
          icon: NightshadeIcons.error,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: onBulkCull,
        ),
      ],
    );
  }
}

class _SubTile extends ConsumerWidget {
  final DbCapturedImage sub;
  final FrameQualityAssessment? assessment;
  final VoidCallback onTap;
  final VoidCallback onToggleAccept;
  final NightshadeColors colors;

  const _SubTile({
    required this.sub,
    required this.assessment,
    required this.onTap,
    required this.onToggleAccept,
    required this.colors,
  });

  Color _gradeColor() {
    if (!sub.isAccepted) return colors.error;
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
                    '${sub.filter ?? 'L'} · ${sub.exposureDuration.toInt()}s',
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
            color: const Color(0xFFFFFFFF),
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: NightshadeTypography.fontSize8,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

/// Full-bleed single-sub view used by blink mode.
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
                return _localPreview(colors);
              },
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            '${sub.fileName} · ${sub.filter ?? 'L'} · '
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

  Widget _localPreview(NightshadeColors colors) {
    try {
      final f = File(sub.filePath);
      if (f.existsSync() &&
          !sub.filePath.toLowerCase().endsWith('.fits') &&
          !sub.filePath.toLowerCase().endsWith('.fit')) {
        return Image.file(f, fit: BoxFit.contain);
      }
    } catch (_) {
      // fall through
    }
    return Center(
      child: Icon(NightshadeIcons.imageOff, size: 48, color: colors.textMuted),
    );
  }
}
