// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// The 'no node selected' placeholder and the central _NodeEditor dispatcher widget that picks the right per-node properties widget based on the selected node's runtime type.
part of '../node_properties_panel.dart';

class _EmptySelection extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const _EmptySelection({required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mousePointer,
            size: isMobile ? 40 : 32,
            color: colors.textMuted,
          ),
          SizedBox(height: isMobile ? 16 : 12),
          Text(
            'Select a node',
            style: TextStyle(
              fontSize: isMobile ? 16 : 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'to view its properties',
            style: TextStyle(
              fontSize: isMobile ? 14 : 11,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeEditor extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final ScrollController? scrollController;
  final bool isMobile;

  const _NodeEditor({
    required this.colors,
    required this.node,
    this.scrollController,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.all(isMobile ? 20 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node type badge
          _NodeTypeBadge(colors: colors, node: node),
          const SizedBox(height: 16),

          // Name field
          _PropertyField(
            colors: colors,
            label: 'Name',
            child: _TextInput(
              colors: colors,
              value: node.name,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(name: value),
                    );
              },
            ),
          ),

          // Enabled toggle
          _PropertyField(
            colors: colors,
            label: 'Enabled',
            child: _ToggleSwitch(
              colors: colors,
              value: node.isEnabled,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(isEnabled: value),
                    );
              },
            ),
          ),

          const Divider(height: 32),

          // Type-specific properties
          _buildTypeSpecificProperties(ref),

          const SizedBox(height: 24),

          // Delete button — routes through the canonical confirmation
          // helper so a stray click on the Properties-panel button can't
          // silently nuke a container holding many descendants. The
          // helper handles both the prompt and the selection cleanup.
          SizedBox(
            width: double.infinity,
            child: _DangerButton(
              colors: colors,
              label: 'Delete Node',
              icon: LucideIcons.trash2,
              onPressed: () async {
                await confirmAndDeleteSequenceNode(
                  context: context,
                  ref: ref,
                  nodeId: node.id,
                  colors: colors,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSpecificProperties(WidgetRef ref) {
    // P3-8: dispatch is a Dart-3 switch expression. The old 30-arm if/else
    // chain was both hard to read and easy to break — adding a node type
    // meant remembering to update an inert `else if` slot. The switch keeps
    // every branch in one visual scan and binds the typed node directly
    // (no more `as ExposureNode` casts in each arm).
    final Widget propertiesWidget = switch (node) {
      ExposureNode n => _ExposureProperties(colors: colors, node: n),
      TargetHeaderNode n => _TargetGroupProperties(colors: colors, node: n),
      LoopNode n => _LoopProperties(colors: colors, node: n),
      TargetSchedulerNode n =>
        TargetSchedulerProperties(colors: colors, node: n),
      SmartExposureNode n => SmartExposureProperties(colors: colors, node: n),
      CenterNode n => _CenterProperties(colors: colors, node: n),
      AutofocusNode n => _AutofocusProperties(colors: colors, node: n),
      CoolCameraNode n => _CoolCameraProperties(colors: colors, node: n),
      FilterChangeNode n => _FilterChangeProperties(colors: colors, node: n),
      DelayNode n => _DelayProperties(colors: colors, node: n),
      DitherNode n => _DitherProperties(colors: colors, node: n),
      WarmCameraNode n => _WarmCameraProperties(colors: colors, node: n),
      RotatorNode n => _RotatorProperties(colors: colors, node: n),
      SlewNode n => _SlewProperties(colors: colors, node: n),
      WaitTimeNode n => _WaitTimeProperties(colors: colors, node: n),
      ConditionalNode n => _ConditionalProperties(colors: colors, node: n),
      ParallelNode n => _ParallelProperties(colors: colors, node: n),
      RecoveryNode n => _RecoveryProperties(colors: colors, node: n),
      NotificationNode n => _NotificationProperties(colors: colors, node: n),
      ScriptNode n => _ScriptProperties(colors: colors, node: n),
      ParkNode() ||
      UnparkNode() =>
        _SimpleInstructionInfo(colors: colors, node: node),
      MeridianFlipNode n => _MeridianFlipProperties(colors: colors, node: n),
      OpenDomeNode() ||
      CloseDomeNode() ||
      ParkDomeNode() =>
        _DomeProperties(colors: colors, node: node),
      OpenCoverNode n => _OpenCoverProperties(colors: colors, node: n),
      CloseCoverNode n => _CloseCoverProperties(colors: colors, node: n),
      CalibratorOnNode n => _CalibratorOnProperties(colors: colors, node: n),
      CalibratorOffNode n => _CalibratorOffProperties(colors: colors, node: n),
      PolarAlignmentNode n =>
        _PolarAlignmentProperties(colors: colors, node: n),
      InstructionSetNode n => _InstructionSetInfo(colors: colors, node: n),
      _ => _UnknownNodeProperties(colors: colors, node: node),
    };

    // Add timing section for nodes with meaningful duration
    if (_hasMeaningfulDuration(node)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          propertiesWidget,
          const SizedBox(height: 16),
          _TimingSection(colors: colors, node: node),
        ],
      );
    }

    return propertiesWidget;
  }
}
