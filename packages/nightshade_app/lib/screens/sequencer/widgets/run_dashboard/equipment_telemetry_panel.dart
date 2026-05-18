import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../equipment_telemetry_strip.dart';

/// Run-dashboard equipment telemetry card.
///
/// Thin wrapper around [EquipmentTelemetryStrip] in its vertical layout
/// (`direction: Axis.vertical`). The strip is the single source of truth
/// for which device fields render — both the toolbar (horizontal) and
/// this dashboard panel (vertical) read the same providers and produce
/// matching telemetry.
///
/// History: this file used to hand-format a parallel set of device rows.
/// That duplicate was deleted when the strip learned to render vertically
/// — see `equipment_telemetry_strip.dart`'s `_VerticalLayout`.
class RunDashboardEquipmentPanel extends ConsumerWidget {
  const RunDashboardEquipmentPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return EquipmentTelemetryStrip(
      colors: colors,
      direction: Axis.vertical,
    );
  }
}
