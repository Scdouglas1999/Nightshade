import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When true, [sceneSnapshotProvider] stops per-frame polling (app backgrounded).
final planetariumQuiescedProvider = StateProvider<bool>((ref) => false);
