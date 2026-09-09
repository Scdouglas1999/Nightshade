import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import 'command_entry.dart';
import 'command_sources.dart';

export 'command_entry.dart' show CommandEntry, CommandGroup;

/// Opens the command palette (04-shell §7).
///
/// `showGeneralDialog` with a top-aligned child rather than `NightshadeDialog`,
/// which forces a title row, a close button and centre alignment. A palette
/// has none of those: its title is the thing you type, its close is Esc, and
/// it belongs near the field that opened it, not in the middle of the window.
Future<void> showCommandPalette(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss the command palette',
    barrierColor: Colors.black.withValues(alpha: _scrimOpacity),
    transitionDuration: NightshadeTokens.durationFast,
    pageBuilder: (context, animation, secondaryAnimation) =>
        const _CommandPaletteRoute(),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: NightshadeTokens.curveStandard,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The dim behind a dialog or the palette.
const double _scrimOpacity = NightshadeTokens.opacityScrim;

class _CommandPaletteRoute extends StatelessWidget {
  const _CommandPaletteRoute();

  /// The palette sits below the top bar rather than in the middle of the
  /// window: it is the command field's own surface, and an operator who
  /// clicked the field looks where the field was.
  static const double _topInset = 96.0;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceLg,
        ).copyWith(top: _topInset),
        child: const CommandPalette(),
      ),
    );
  }
}

/// The palette itself. Public so a widget test can pump it without a router.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  static const double width = 560.0;
  static const double inputHeight = 40.0;

  /// How tall the results list is allowed to get before it scrolls.
  static const double maxResultsHeight = 420.0;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// The input owns the focus, and its node intercepts the navigation keys.
  ///
  /// `onKeyEvent` ON THE NODE runs BEFORE the editable consumes the event,
  /// which is the only place these bindings work: a single-line `TextField`
  /// handles Arrow Up / Down itself (they move the caret to the start and end
  /// of the line) and returns `handled`, so an ancestor `CallbackShortcuts`
  /// never sees them and the palette's selection could not be moved from the
  /// keyboard at all.
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKey);

  /// Index into the FLAT filtered list. The group eyebrows are not selectable,
  /// so selection is over entries, not over rendered rows.
  int _selected = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim().toLowerCase();
      if (next == _query) return;
      // Any change to the query invalidates the selection: keeping the index
      // would leave the highlight on whatever now happens to sit at that
      // position, and Enter would run something the operator never read.
      setState(() {
        _query = next;
        _selected = 0;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<CommandEntry> _entries() {
    final all = <CommandEntry>[
      ...buildScreenEntries(context),
      ...buildSettingEntries(context, _query),
      ...buildActionEntries(context, ref),
    ];
    final matched = all.where((e) => e.matches(_query)).toList();
    // Stable within a group: the sort key is (group, rank), and List.sort is
    // not stable, so the original position is the final tiebreak.
    final position = <String, int>{
      for (var i = 0; i < matched.length; i++) matched[i].id: i,
    };
    matched.sort((a, b) {
      final byGroup = a.group.index.compareTo(b.group.index);
      if (byGroup != 0) return byGroup;
      final byRank = a.rank(_query).compareTo(b.rank(_query));
      if (byRank != 0) return byRank;
      return position[a.id]!.compareTo(position[b.id]!);
    });
    return matched;
  }

  /// Arrow keys move the selection, Enter runs it, Esc closes the palette.
  ///
  /// Everything else is the operator typing, and belongs to the field.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final entries = _entries();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (entries.isEmpty) return KeyEventResult.handled;
        _invoke(entries[_selected.clamp(0, entries.length - 1)]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// Moves the selection, wrapping at both ends.
  ///
  /// Dart's `%` returns a non-negative result for a negative left operand, so
  /// Up from the first row lands on the last without a second branch.
  void _move(int delta, int length) {
    if (length == 0) return;
    setState(() => _selected = (_selected + delta) % length);
    _revealSelected();
  }

  /// Keeps the highlighted row inside the viewport when the arrows walk past
  /// its edge; without it the selection moves invisibly and Enter runs
  /// something off screen.
  void _revealSelected() {
    if (!_scrollController.hasClients) return;
    final target = (_selected * _CommandRow.height) -
        (CommandPalette.maxResultsHeight / 2) +
        _CommandRow.height;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: NightshadeTokens.durationFast,
      curve: NightshadeTokens.curveStandard,
    );
  }

  void _invoke(CommandEntry entry) {
    if (!entry.enabled) return;
    // Close first: a handler that pushes a route or opens a dialog must not
    // be doing it underneath a palette that is still dismissing.
    Navigator.of(context).pop();
    entry.invoke(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final entries = _entries();
    final selected =
        _selected.clamp(0, entries.isEmpty ? 0 : entries.length - 1);

    // No ancestor Focus: the input takes the focus and keeps it, and its node
    // owns the key bindings. An `autofocus` Focus around this took the focus
    // FROM the field, which left the palette open with a caret nowhere and
    // typing doing nothing at all.
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CommandPalette.width),
        child: Container(
          decoration: NightshadeDecorations.dialog(colors),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(colors),
              if (entries.isEmpty)
                _empty(colors)
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: CommandPalette.maxResultsHeight,
                    ),
                    child: _results(colors, entries, selected),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(NightshadeColors colors) {
    return Container(
      height: CommandPalette.inputHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: NightshadeTokens.iconSm,
            color: colors.textMuted,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: NightshadeTypography.input.copyWith(
                color: colors.textPrimary,
              ),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: context.l10n.text('commandPalettePlaceholder'),
                hintStyle: NightshadeTypography.input.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      child: Text(
        'Nothing matches "${_controller.text.trim()}".',
        style: NightshadeTypography.bodySm.copyWith(color: colors.textMuted),
      ),
    );
  }

  Widget _results(
    NightshadeColors colors,
    List<CommandEntry> entries,
    int selected,
  ) {
    // One flat list with an eyebrow rendered above the first entry of each
    // group: a nested list would make the arrow keys walk a tree, and the
    // arrow keys must walk exactly what the eye reads.
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceSm),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final startsGroup =
            index == 0 || entries[index - 1].group != entry.group;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (startsGroup)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  NightshadeTokens.spaceMd,
                  index == 0
                      ? NightshadeTokens.spaceSm
                      : NightshadeTokens.spaceMd,
                  NightshadeTokens.spaceMd,
                  NightshadeTokens.spaceXs,
                ),
                child: Text(
                  entry.group.label.toUpperCase(),
                  style: NightshadeTypography.eyebrow.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
            _CommandRow(
              entry: entry,
              isSelected: index == selected,
              colors: colors,
              onTap: () => _invoke(entry),
              onHover: () {
                if (_selected == index) return;
                setState(() => _selected = index);
              },
            ),
          ],
        );
      },
    );
  }
}

class _CommandRow extends StatelessWidget {
  final CommandEntry entry;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _CommandRow({
    required this.entry,
    required this.isSelected,
    required this.colors,
    required this.onTap,
    required this.onHover,
  });

  /// Fixed so the arrow keys can compute where the selection is without
  /// measuring every row.
  static const double height = 36.0;

  @override
  Widget build(BuildContext context) {
    final foreground = entry.enabled
        ? (isSelected ? colors.textPrimary : colors.textSecondary)
        : colors.textMuted.withValues(
            alpha: NightshadeTokens.opacityDisabled,
          );
    final hint = entry.enabled ? entry.hint : entry.disabledReason;

    return Semantics(
      button: true,
      enabled: entry.enabled,
      selected: isSelected,
      label: hint == null ? entry.label : '${entry.label}, $hint',
      child: MouseRegion(
        cursor:
            entry.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          onTap: entry.enabled ? onTap : null,
          child: Container(
            height: height,
            margin: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: isSelected ? colors.surfaceHover : Colors.transparent,
              borderRadius: NightshadeTokens.borderRadiusSm,
            ),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: NightshadeTokens.iconSm,
                  color: entry.enabled ? colors.textMuted : foreground,
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Expanded(
                  child: Text(
                    entry.label,
                    style: NightshadeTypography.bodySm.copyWith(
                      color: foreground,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(width: NightshadeTokens.spaceMd),
                  Text(
                    hint,
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
