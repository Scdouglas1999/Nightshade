import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'snackbar_helper.dart';

/// Connects to PHD2 using saved settings.
///
/// This eliminates duplicate PHD2 connection code across screens.
/// All PHD2 connect buttons should use this helper instead of implementing
/// their own async settings lookup and connect logic.
///
/// [ref] - The WidgetRef for provider access
/// [context] - Optional BuildContext for error snackbars
Future<void> connectPhd2(WidgetRef ref, {BuildContext? context}) async {
  try {
    final settings = await ref.read(appSettingsProvider.future);
    await ref.read(phd2ControllerProvider).connect(
      settings.phd2Host,
      settings.phd2Port,
    );
  } catch (e) {
    if (context != null && context.mounted) {
      context.showErrorSnackBar('Failed to connect to PHD2: $e');
    }
  }
}

/// Disconnects from PHD2.
///
/// [ref] - The WidgetRef for provider access
void disconnectPhd2(WidgetRef ref) {
  ref.read(phd2ControllerProvider).disconnect();
}
