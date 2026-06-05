import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../localization/nightshade_localizations.dart';
part 'diagnostics_screen/header_widgets.dart';
part 'diagnostics_screen/content_layout.dart';
part 'diagnostics_screen/health_summary_cards.dart';
part 'diagnostics_screen/optical_alignment_cards.dart';
part 'diagnostics_screen/psf_field_map.dart';
part 'diagnostics_screen/residual_vector.dart';
part 'diagnostics_screen/issues_and_skeleton.dart';

/// Thin shell that hosts [DiagnosticsTabContent].
///
/// Diagnostics merged into Analytics as a tab in §UX consolidation. The
/// `/diagnostics` route now redirects to `/analytics?tab=diagnostics`, so
/// this screen is unreachable through the router. It is kept so any direct
/// embedding (tests, debug entry points) keeps working until the redirect
/// is removed.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DiagnosticsTabContent();
  }
}

/// Optical-train diagnostics surface, embedded inside the Analytics screen.
class DiagnosticsTabContent extends ConsumerStatefulWidget {
  const DiagnosticsTabContent({super.key});

  @override
  ConsumerState<DiagnosticsTabContent> createState() =>
      _DiagnosticsTabContentState();
}

class _DiagnosticsTabContentState extends ConsumerState<DiagnosticsTabContent> {
  int? _selectedSessionId;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = Responsive.isMobile(context);
    final sessionsAsync = ref.watch(allSessionsProvider);
    final l10n = context.l10n;

    // Auto-select current session if none selected
    final sessionState = ref.watch(sessionStateProvider);
    if (_selectedSessionId == null && sessionState.dbSessionId != null) {
      _selectedSessionId = sessionState.dbSessionId;
    }

    // Phone tier reflows the header: the session selector drops to its own
    // line under the title so the wide dropdown can't push the title into a
    // RenderFlex overflow on a narrow phone.
    final isPhone = Responsive.isPhone(context);

    final titleRow = Row(
      children: [
        Icon(LucideIcons.microscope, size: 22, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.text('diagnosticsTitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isMobile ? NightshadeTypography.fontSize18 : NightshadeTypography.fontSize22,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );

    final sessionSelector = sessionsAsync.when(
      data: (sessions) => _SessionSelector(
        sessions: sessions,
        selectedSessionId: _selectedSessionId,
        onChanged: (id) => setState(() => _selectedSessionId = id),
        colors: colors,
      ),
      // Small skeleton chip rather than a spinner so the header doesn't
      // visibly jitter when sessions resolve.
      loading: () => const ShimmerLoading(
        child: SkeletonBox(width: 200, height: 28),
      ),
      error: (e, _) => Text(
        l10n.text('diagnosticsLoadSessionsFailed'),
        style: TextStyle(color: colors.error, fontSize: NightshadeTypography.fontSize12),
      ),
    );

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (isPhone) ...[
            titleRow,
            const SizedBox(height: 10),
            // Constrain so a long session name ellipsizes instead of forcing
            // the dropdown wider than the phone column.
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 24,
                ),
                child: sessionSelector,
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(child: titleRow),
                const SizedBox(width: 12),
                // Bounded width so the (isExpanded) dropdown has finite
                // constraints and ellipsizes a long session label.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: sessionSelector,
                ),
              ],
            ),
          const SizedBox(height: 8),
          // Users frequently confuse diagnostics with analytics; the audit
          // (§4.19) called out that the prior single-line intro didn't make
          // the scope obvious. Spell out the mechanical-health framing,
          // contrast it with analytics, and tell people when to come here.
          Text(
            'Optical-train mechanical health — collimation, tilt, sensor backfocus, and image-plane flatness — the hardware issues that show up as systematic PSF aberrations across the field. '
            'Analytics tracks per-frame image quality and photometry; diagnostics aggregates anomaly patterns across the whole session to point at the underlying hardware cause. '
            'Come here when imaging shows degraded HFR or eccentricity, or when analytics keeps flagging the same quality issue. Lower tilt and collimation scores are better.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          // No external docs site is wired up yet, so the chip uses a
          // `nightshade://docs/diagnostics` anchor as a stable target for a
          // future in-app docs viewer. Until that lands, the chip stays
          // informational — tapping is a no-op rather than a broken link.
          _DocsInfoChip(colors: colors),
          const SizedBox(height: 16),

          // Main content
          Expanded(
            child: _selectedSessionId == null
                // Scroll-wrap so the centered empty state never overflows when
                // a phone is short (landscape).
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: EmptyState(
                          icon: LucideIcons.star,
                          title: l10n.text('diagnosticsNoSessionTitle'),
                          body: l10n.text('diagnosticsNoSessionBody'),
                        ),
                      ),
                    ),
                  )
                : _DiagnosticsContent(
                    sessionId: _selectedSessionId!,
                    isMobile: isMobile,
                  ),
          ),
        ],
      ),
    );
  }
}

// Sits under the intro paragraph as a low-key affordance. Inline `InkWell`
// over a small icon + label keeps the chip visually quieter than
// `NightshadeButton.ghost`, which is sized for primary actions.
