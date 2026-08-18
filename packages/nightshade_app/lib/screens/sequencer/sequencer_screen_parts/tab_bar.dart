part of '../sequencer_screen.dart';

/// Sequencer tab strip.
///
/// Uses [AdaptiveTabBar] so the four tabs (Builder / Templates / Sequences /
/// History) scroll horizontally instead of overflowing on a 360 px phone —
/// and collapse their labels to icon-only on a compact phone (`< 480`). The
/// strip drives the screen's [TabController] so the existing keyboard
/// shortcuts, provider sync and tutorial flow keep working.
class _SequencerTabBar extends StatelessWidget {
  final NightshadeColors colors;
  final TabController controller;

  /// The run's live STATE, not a boolean. An `isRunning` flag is true for both
  /// running and paused, so a paused run would show a green "Sequence Running"
  /// chip a row above the toolbar's amber "Paused" — the app's most prominent
  /// run indicator contradicting the one beside it about whether the rig is
  /// exposing.
  final SequenceExecutionState executionState;

  /// Form-factor decision computed once at the screen level so the
  /// strip and the builder body agree on phone-vs-desktop.
  final bool isPhone;

  const _SequencerTabBar({
    required this.colors,
    required this.controller,
    this.executionState = SequenceExecutionState.idle,
    required this.isPhone,
  });

  /// Tutorial keys keyed by tab so the strip stays in sync with the
  /// [SequencerTab] enum that drives the controller.
  static Key? _buttonKeyFor(SequencerTab tab) {
    switch (tab) {
      case SequencerTab.builder:
        return SequencerTutorialKeys.tabBuilder;
      case SequencerTab.templates:
        return SequencerTutorialKeys.tabTemplates;
      case SequencerTab.sequences:
      case SequencerTab.history:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Derive the strip from the single SequencerTab enum so adding a tab
    // there updates the controller length and this strip in one edit. On
    // desktop the keyboard accelerators (Alt+1..4) are surfaced in the tab's
    // tooltip/semantics so they are discoverable; phones have no keyboard so
    // the hint is omitted.
    final tabs = <AdaptiveTab>[
      for (final tab in SequencerTab.values)
        AdaptiveTab(
          label: tab.label,
          icon: tab.icon,
          buttonKey: _buttonKeyFor(tab),
          semanticLabel:
              isPhone ? tab.label : '${tab.label} (Alt+${tab.index + 1})',
        ),
    ];

    // The chip states the run's state verbatim; `null` draws no chip at all.
    // Paused deliberately gets its own amber label rather than reusing the
    // running one, because a paused rig is not exposing.
    final String? chipLabel = switch (executionState) {
      SequenceExecutionState.running => 'Sequence Running',
      SequenceExecutionState.paused => 'Sequence Paused',
      _ => null,
    };
    final chipColor = executionState == SequenceExecutionState.paused
        ? colors.warning
        : colors.success;

    // On phone the running state is surfaced by the playback bar, so the
    // trailing run chip is desktop/tablet only.
    final trailing = <Widget>[
      // A discoverable entry point to the full keyboard-shortcut
      // cheat-sheet. Keyboard-only, so desktop/tablet just like the
      // accelerator hints above.
      if (!isPhone)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: 'Keyboard shortcuts',
            child: IconButton(
              icon: Icon(
                LucideIcons.keyboard,
                size: 18,
                color: colors.textSecondary,
              ),
              onPressed: () => _SequencerShortcutsSheet.show(context, colors),
            ),
          ),
        ),
      if (chipLabel != null && !isPhone)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: NightshadeDecorations.statusChip(
              chipColor,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: chipColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: chipColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  chipLabel,
                  style: NightshadeTypography.h6.copyWith(color: chipColor),
                ),
              ],
            ),
          ),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          // Title + sub-tabs share ONE row (the screen had no title row of its
          // own above the tabs — the outer nav named it). Fold the title inline
          // to the left of the tab strip — icon-only on a phone — while the
          // existing keyboard/running chips keep riding at the right end via
          // the AdaptiveTabBar trailing slot.
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: NightshadeTokens.spaceLg,
                  right: isPhone
                      ? NightshadeTokens.spaceSm
                      : NightshadeTokens.spaceMd,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      NightshadeIcons.listOrdered,
                      size: 18,
                      color: colors.primary,
                    ),
                    if (!isPhone) ...[
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Text(
                        context.l10n.text('navSequencer'),
                        style: NightshadeTypography.h5.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  // Rebuild the strip when the controller's selection changes so
                  // the highlighted tab + auto-scroll-into-view follow the
                  // active index regardless of whether the change came from a
                  // tap, a keyboard shortcut, or the provider→controller sync in
                  // initState.
                  animation: controller.animation ?? controller,
                  builder: (context, _) {
                    return AdaptiveTabBar(
                      tabs: tabs,
                      selectedIndex: controller.index,
                      horizontalPadding: isPhone ? 8 : 20,
                      onSelected: (i) => controller.animateTo(i),
                      trailing: trailing,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A read-only cheat-sheet listing every sequencer keyboard binding, opened
/// from the strip's keyboard icon. Mirrors the [CallbackShortcuts]
/// bindings declared in `sequencer_screen.dart` and the toolbox Ctrl+T toggle
/// — keep this list in sync when adding a shortcut.
class _SequencerShortcutsSheet {
  const _SequencerShortcutsSheet._();

  static const List<({String keys, String action})> _shortcuts = [
    (keys: 'Alt+1', action: 'Builder tab'),
    (keys: 'Alt+2', action: 'Templates tab'),
    (keys: 'Alt+3', action: 'Sequences tab'),
    (keys: 'Alt+4', action: 'History tab'),
    (keys: 'Ctrl+T', action: 'Toggle Nodes / Snippets'),
    (keys: 'Ctrl+Z', action: 'Undo'),
    (keys: 'Ctrl+Y', action: 'Redo'),
    (keys: 'Ctrl+D', action: 'Duplicate node'),
    (keys: 'Ctrl+C', action: 'Copy selected nodes'),
    (keys: 'Ctrl+V', action: 'Paste nodes'),
    (keys: 'Delete', action: 'Delete selected nodes'),
    (keys: 'Esc', action: 'Clear multi-selection'),
  ];

  static Future<void> show(BuildContext context, NightshadeColors colors) {
    return showAdaptiveModal<void>(
      context: context,
      designWidth: 420,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.keyboard, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Keyboard Shortcuts',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final s in _shortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: NightshadeDecorations.tintedBadge(
                        colors.primary,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline4),
                      ),
                      child: Text(
                        s.keys,
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.action,
                        style: NightshadeTypography.bodySm
                            .copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: NightshadeButton(
                label: 'Close',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
