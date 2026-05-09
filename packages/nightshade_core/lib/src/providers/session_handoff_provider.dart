import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_handoff_service.dart';

/// Service provider for SessionHandoffService.
final sessionHandoffServiceProvider =
    Provider<SessionHandoffService>((ref) {
  return const SessionHandoffService();
});
