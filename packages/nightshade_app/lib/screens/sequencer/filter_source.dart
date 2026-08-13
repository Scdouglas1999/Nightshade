import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Filter names the sequence builder should offer, and where they came from.
///
/// The builder used to read the equipment PROFILE and nothing else, so a rig
/// whose filters live on the connected wheel (the usual case for a wheel that
/// reports its own slot names) authored against "No filters in profile" and a
/// node header reading "Exposure: No Filter" — while the run captured, named
/// and reported every frame as filter "R". The authoring surface denied a
/// filter the data-writing path was using for filenames and statistics.
///
/// The profile stays authoritative when it has filters: it is the operator's
/// deliberate naming. The connected wheel is the fallback, not an override.
class BuilderFilterSource {
  const BuilderFilterSource({required this.names, required this.fromWheel});

  final List<String> names;

  /// True when [names] came from the connected wheel rather than the profile.
  final bool fromWheel;

  bool get isEmpty => names.isEmpty;

  /// What to tell the operator when there is nothing to choose from.
  static const String emptyHint =
      'No filters — connect a filter wheel or add them to the profile';
}

/// Resolve the filter names for the builder: the active profile's, else the
/// connected filter wheel's.
BuilderFilterSource builderFilterSource(WidgetRef ref) {
  final profileNames = ref.watch(activeEquipmentProfileProvider)?.filterNames;
  if (profileNames != null && profileNames.isNotEmpty) {
    return BuilderFilterSource(names: profileNames, fromWheel: false);
  }
  final wheel = ref.watch(filterWheelStateProvider);
  if (wheel.connectionState == DeviceConnectionState.connected &&
      wheel.filterNames.isNotEmpty) {
    return BuilderFilterSource(names: wheel.filterNames, fromWheel: true);
  }
  return const BuilderFilterSource(names: <String>[], fromWheel: false);
}
