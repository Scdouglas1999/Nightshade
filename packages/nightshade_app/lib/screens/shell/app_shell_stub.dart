// Stub implementation for platforms without window_manager
import 'package:flutter/material.dart';

/// Callback type for when window close is requested (stub)
typedef OnCloseRequested = Future<bool> Function();

// Stub functions for mobile/web
void initWindowManager(State state, {OnCloseRequested? onCloseRequested}) {
  // No-op on mobile/web
}

void disposeWindowManager(State state) {
  // No-op on mobile/web
}

// Stub mixin for compatibility (not actually used)
mixin WindowListenerMixin {
  // Empty - not needed
}

