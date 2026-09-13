// The Notes inspector tab (spec §8).
//
// Two note surfaces live here because they answer different questions:
//   * [TargetNotesSection] — the database-backed journal entries attached to
//     the TARGET ("M31 collected 40 frames over three nights"), shown only
//     for [TargetHeaderNode].
//   * the node comment editor — the free-text [SequenceNode.comment] the
//     tree already renders as a muted italic line under the row. Nothing in
//     the app edited it before this tab.
//
// The comment commits on focus loss or Enter through the canonical
// `currentSequenceProvider.notifier.updateNode` path, guarded by
// `canEditSequenceProvider` and wrapped in `withSequenceMutation` like every
// other inspector edit. "No comment" is stored as `''` — every node's
// `copyWith(comment:)` is keep-or-replace so null cannot clear it, and both
// the tree's italic line and the tab's dot check `isNotEmpty`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/sequence_mutator_helper.dart';
import 'node_property_widgets.dart';
import 'notes_panel.dart';

class NodeNotesTab extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final ScrollController? scrollController;
  final bool isMobile;

  const NodeNotesTab({
    super.key,
    required this.colors,
    required this.node,
    this.scrollController,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canEditSequenceProvider);
    final node = this.node;

    // The edit lock mirrors `_NodeEditor`: dim outside the scroll view,
    // pointer-blocking inside it, so a locked (running) sequence still lets
    // the operator READ their notes — and the sheet keeps scrolling on
    // mobile.
    return Material(
      type: MaterialType.transparency,
      child: Opacity(
        opacity: canEdit ? 1.0 : NightshadeTokens.opacityDisabled,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(
            isMobile ? NightshadeTokens.spaceXl : NightshadeTokens.spaceLg,
          ),
          child: IgnorePointer(
            ignoring: !canEdit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (node is TargetHeaderNode) ...[
                  TargetNotesSection(
                    targetId: node.targetName,
                    colors: colors,
                  ),
                  const SizedBox(height: NightshadeTokens.space2xl),
                ],
                NodePropertyField(
                  colors: colors,
                  label: 'Comment',
                  helpText:
                      'Shown as an italic line under this node in the tree.',
                  child: _NodeCommentEditor(node: node, colors: colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-line editor for [SequenceNode.comment], committing on focus loss or
/// submit. The node's own `updateNode` call carries undo/redo, autosave and
/// `modifiedAt` bookkeeping, so no notes-specific write path is needed.
class _NodeCommentEditor extends ConsumerStatefulWidget {
  final SequenceNode node;
  final NightshadeColors colors;

  const _NodeCommentEditor({required this.node, required this.colors});

  @override
  ConsumerState<_NodeCommentEditor> createState() => _NodeCommentEditorState();
}

class _NodeCommentEditorState extends ConsumerState<_NodeCommentEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.node.comment ?? '');
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NodeCommentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      // Selection moved while the field may hold uncommitted text: commit it
      // against the node it was typed on — carrying it onto the new node's
      // comment would silently misattribute the note.
      _commitAgainst(oldWidget.node);
      _controller.text = widget.node.comment ?? '';
    } else if (!_focusNode.hasFocus &&
        widget.node.comment != oldWidget.node.comment) {
      // The comment changed under us (undo/redo): adopt the new text unless
      // the user is mid-edit — typing must not lose its place because the
      // model re-emitted the same node.
      _controller.text = widget.node.comment ?? '';
    }
  }

  void _handleFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() => _commitAgainst(widget.node);

  void _commitAgainst(SequenceNode node) {
    final text = _controller.text.trim();
    if (text == (node.comment ?? '')) return;
    if (!ref.read(canEditSequenceProvider)) return;
    withSequenceMutation(
      context,
      ref,
      operationName: 'update note',
      action: () async {
        ref.read(currentSequenceProvider.notifier).updateNode(
              node.copyWith(comment: text),
            );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Node comment',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        decoration:
            NightshadeDecorations.field(widget.colors, focused: _focused),
        child: TextField(
          key: const ValueKey('node-comment-field'),
          controller: _controller,
          focusNode: _focusNode,
          minLines: 4,
          maxLines: 10,
          // A tap anywhere else — another tab, another row — is the
          // focus-loss commit; without this the field would keep focus until
          // it unmounted and the half-typed note would silently vanish.
          onTapOutside: (_) => _focusNode.unfocus(),
          onSubmitted: (_) => _commit(),
          style: NightshadeTypography.bodySm.copyWith(
            color: widget.colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Add a note for this node…',
            hintStyle: NightshadeTypography.bodySm.copyWith(
              color: widget.colors.textMuted,
            ),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }
}
