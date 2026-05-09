import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

final selectedAnnotationObjectProvider =
    StateProvider<CelestialObjectAnnotation?>((_) => null);

/// Provider for the annotation object that should be pulsed/highlighted.
/// Set when an object is selected from the sidebar list. The overlay reads this
/// to trigger a scale-up/down animation on the corresponding marker.
/// Value is the object ID, or null when no pulse is active.
final annotationPulseObjectProvider = StateProvider<String?>((ref) => null);
