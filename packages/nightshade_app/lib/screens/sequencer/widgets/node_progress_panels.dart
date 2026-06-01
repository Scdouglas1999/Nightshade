import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

part 'node_progress_panels/cooling_progress_panel.dart';
part 'node_progress_panels/autofocus_progress_panel.dart';
part 'node_progress_panels/autofocus_visuals.dart';
part 'node_progress_panels/stat_box.dart';
part 'node_progress_panels/exposure_progress_panel.dart';
part 'node_progress_panels/other_progress_panels.dart';
part 'node_progress_panels/animated_progress_bar.dart';

/// Factory that returns the appropriate progress panel widget for a node type
Widget? getProgressPanelForNode({
  required SequenceNode node,
  required NightshadeColors colors,
  required double progressPercent,
  required String? progressDetail,
  InstructionProgressDetail? structuredProgressDetail,
}) {
  // Parse progress detail to extract relevant info
  final detail = progressDetail ?? '';

  if (node is CoolCameraNode || node is WarmCameraNode) {
    return _CoolingProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      isWarming: node is WarmCameraNode,
    );
  }

  if (node is AutofocusNode) {
    return _AutofocusProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
    );
  }

  if (node is ExposureNode) {
    return _ExposureProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      structuredDetail: structuredProgressDetail,
      node: node,
    );
  }

  if (node is SlewNode || node is CenterNode) {
    return _SlewProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
      isCentering: node is CenterNode,
    );
  }

  if (node is FilterChangeNode) {
    return _FilterProgressPanel(
      colors: colors,
      progressPercent: progressPercent,
      detail: detail,
    );
  }

  // Default panel for other node types
  return _DefaultProgressPanel(
    colors: colors,
    progressPercent: progressPercent,
    detail: detail,
  );
}
