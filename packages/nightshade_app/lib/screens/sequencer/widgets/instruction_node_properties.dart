import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';
import 'meridian_flip_edit_helper.dart';
import 'node_property_widgets.dart';

// ---------------------------------------------------------------------------
// File split: every public widget that this library exports now lives in a
// instruction_node_properties_parts/ part file. Importers continue to use
// the same `instruction_node_properties.dart` path; the `part`
// mechanism keeps all public symbols in this library's scope.
//
// Cohesion buckets:
//   * _exposure.dart            - ExposureProperties (the largest widget) +
//                                 its sky-brightness adaptive sub-section
//   * _capture_properties.dart  - cool/warm camera, filter change, dither,
//                                 start-guiding
//   * _motion_properties.dart   - center, autofocus, rotator, slew,
//                                 meridian flip, polar alignment
//   * _notification_and_script.dart - notifications (transport multi-select
//                                 + preview) and script
//   * _misc_properties.dart     - delay, simple-instruction info, dome,
//                                 instruction-set info, cover/calibrator
//                                 quartet
// ---------------------------------------------------------------------------

part 'instruction_node_properties_parts/_exposure.dart';
part 'instruction_node_properties_parts/_capture_properties.dart';
part 'instruction_node_properties_parts/_motion_properties.dart';
part 'instruction_node_properties_parts/_notification_and_script.dart';
part 'instruction_node_properties_parts/_misc_properties.dart';
