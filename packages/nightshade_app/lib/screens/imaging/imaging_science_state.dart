import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

final selectedAnnotationObjectProvider =
    StateProvider<CelestialObjectAnnotation?>((_) => null);
