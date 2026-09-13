// The two category->tint mappings must stay identical: `nodeCategoryTint`
// (the ledger row's glyph) was extracted from `NodeSummaryLine`'s private
// `_categoryColor`, and any drift would paint one node's two surfaces in
// different hues.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/node_summary_line.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  test('nodeCategoryTint and NodeSummaryLine agree for every NodeCategory', () {
    final colors = NightshadeTheme.dark.extension<NightshadeColors>()!;
    for (final category in NodeCategory.values) {
      expect(
        nodeCategoryTint(category, colors),
        NodeSummaryLine.categoryColorForTesting(colors, category),
        reason: 'category ${category.name}',
      );
    }
  });
}
