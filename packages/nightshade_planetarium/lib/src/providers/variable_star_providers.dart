import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../catalogs/variable_star_catalog.dart';

// ============================================================================
// Variable Star Toggle Provider
// ============================================================================

/// Whether variable star overlay is enabled
final showVariableStarsProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// Variable Star Data Provider
// ============================================================================

/// Provides the full list of variable stars from the embedded catalog.
/// Only returns data when the toggle is enabled.
final variableStarDataProvider = Provider<List<VariableStarData>>((ref) {
  final show = ref.watch(showVariableStarsProvider);
  if (!show) return [];
  return VariableStarCatalog.stars;
});

/// Provides only bright variable stars (mag max <= 8.0) for rendering.
final brightVariableStarsProvider = Provider<List<VariableStarData>>((ref) {
  final show = ref.watch(showVariableStarsProvider);
  if (!show) return [];
  return VariableStarCatalog.getBrighterThan(8.0);
});
