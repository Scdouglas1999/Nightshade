import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Split view layout for flat wizard with controls on left, preview on right
class FlatWizardSplitView extends StatelessWidget {
  final Widget controlsPanel;
  final Widget previewPanel;
  final double controlsWidth;

  const FlatWizardSplitView({
    super.key,
    required this.controlsPanel,
    required this.previewPanel,
    this.controlsWidth = 0.4, // 40% for controls
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final controlsPixelWidth = constraints.maxWidth * controlsWidth;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls panel (left)
            SizedBox(
              width: controlsPixelWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    right: BorderSide(color: colors.border),
                  ),
                ),
                child: controlsPanel,
              ),
            ),

            // Preview panel (right)
            Expanded(
              child: Container(
                color: colors.background,
                child: previewPanel,
              ),
            ),
          ],
        );
      },
    );
  }
}
