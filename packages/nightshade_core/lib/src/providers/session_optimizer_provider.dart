import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_optimizer_service.dart';
import 'target_suggestion_provider.dart';

/// Service provider for SessionOptimizerService.
///
/// Depends on [targetSuggestionServiceProvider] which is injected via the
/// service constructor.
final sessionOptimizerServiceProvider =
    Provider<SessionOptimizerService>((ref) {
  final suggestionService = ref.watch(targetSuggestionServiceProvider);
  return SessionOptimizerService(suggestionService: suggestionService);
});
