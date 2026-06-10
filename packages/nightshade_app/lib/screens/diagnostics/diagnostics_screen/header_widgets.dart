part of '../diagnostics_screen.dart';

class _DocsInfoChip extends StatelessWidget {
  final NightshadeColors colors;

  const _DocsInfoChip({required this.colors});

  // Routed to the in-app docs viewer once it's available; see §4.19 note.
  static const String _docsAnchor = 'nightshade://docs/diagnostics';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      // Until the docs viewer ships, surface the anchor in a tooltip so
      // power users can see where the link will go without it appearing
      // broken on tap.
      onTap: null,
      child: Tooltip(
        message: _docsAnchor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Learn more about optical diagnostics',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.labelSm
                      .copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSelector extends StatelessWidget {
  final List<ImagingSession> sessions;
  final int? selectedSessionId;
  final ValueChanged<int?> onChanged;
  final NightshadeColors colors;

  const _SessionSelector({
    required this.sessions,
    required this.selectedSessionId,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Text(
        context.l10n.text('diagnosticsNoSessions'),
        style: TextStyle(
            color: colors.textMuted, fontSize: NightshadeTypography.fontSize12),
      );
    }

    final dateFormat = DateFormat('MMM d, HH:mm');
    final sessionsByRecency = sessions.reversed.toList();
    final recentSessions = sessionsByRecency.take(50).toList();
    final selectedSession = selectedSessionId == null
        ? null
        : sessions.cast<ImagingSession?>().firstWhere(
              (session) => session?.id == selectedSessionId,
              orElse: () => null,
            );
    final visibleSessions = [...recentSessions];

    if (selectedSession != null &&
        !visibleSessions.any((session) => session.id == selectedSession.id)) {
      visibleSessions.insert(0, selectedSession);
    }

    final dropdownValue = selectedSessionId != null &&
            visibleSessions.any((session) => session.id == selectedSessionId)
        ? selectedSessionId
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: dropdownValue,
          // isExpanded lets the button shrink to its bounded parent and
          // ellipsize the selected label instead of sizing to the widest
          // item (which overflows a narrow phone header).
          isExpanded: true,
          hint: Text(
            context.l10n.text('diagnosticsSelectSession'),
            style: TextStyle(
                color: colors.textMuted,
                fontSize: NightshadeTypography.fontSize13),
          ),
          dropdownColor: colors.surfaceElevated,
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize13),
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          items: visibleSessions.map((session) {
            final label = session.name != null && session.name!.isNotEmpty
                ? '${session.name} (${dateFormat.format(session.startTime)})'
                : dateFormat.format(session.startTime);
            return DropdownMenuItem(
              value: session.id,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
