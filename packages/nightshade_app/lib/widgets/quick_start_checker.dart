import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'quick_start_dialog.dart';
import 'session_recovery_dialog.dart';

/// Widget that checks for quick start opportunities on app startup.
///
/// This widget wraps the app and on first frame:
/// 1. First checks for crashed/interrupted sessions (recovery takes priority)
/// 2. Then checks for recent completed sessions (quick start opportunity)
///
/// Shows appropriate dialog based on what's found.
class QuickStartChecker extends ConsumerStatefulWidget {
  final Widget child;

  const QuickStartChecker({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<QuickStartChecker> createState() => _QuickStartCheckerState();
}

class _QuickStartCheckerState extends ConsumerState<QuickStartChecker> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    // Schedule check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForStartupOptions();
    });
  }

  Future<void> _checkForStartupOptions() async {
    if (_hasChecked || !mounted) return;

    _hasChecked = true;

    try {
      // First priority: Check for crashed/interrupted sessions
      final incompleteSessions =
          await ref.read(incompleteSessionsProvider.future);

      if (!mounted) return;

      if (incompleteSessions.isNotEmpty && mounted) {
        // Show recovery dialog for interrupted sessions (takes priority)
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => SessionRecoveryDialog(
              incompleteSessions: incompleteSessions,
            ),
          );
        }
        return;
      }

      // Second priority: Check for quick start opportunity
      final quickStartContext =
          await ref.read(quickStartContextProvider.future);

      if (!mounted) return;

      if (quickStartContext != null && quickStartContext.isRecent && mounted) {
        // Show quick start dialog
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          await QuickStartDialog.show(
            context,
            quickStartContext: quickStartContext,
            onStartFresh: () => _handleStartFresh(quickStartContext),
            onResumeProgress: () => _handleResumeProgress(quickStartContext),
            onSkip: () {
              // Just dismiss - user chose to skip
              debugPrint('[QuickStart] User skipped quick start');
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[QuickStart] Error checking startup options: $e');
      // Don't show error to user - this is a background check
    }
  }

  Future<void> _handleStartFresh(QuickStartContext context) async {
    debugPrint(
        '[QuickStart] Starting fresh with context: ${context.displayDescription}');

    try {
      // Load the equipment profile
      if (context.profileId != null) {
        final profilesNotifier = ref.read(equipmentProfilesProvider.notifier);
        await profilesNotifier.setActiveProfile(context.profileId!);
        debugPrint('[QuickStart] Activated profile ${context.profileId}');
      }

      // Load the sequence (reset to beginning)
      if (context.sequenceId != null) {
        final sequencesDao = ref.read(sequencesDaoProvider);
        final sequence =
            await sequencesDao.getSequenceById(context.sequenceId!);
        if (sequence != null) {
          // Reset sequence checkpoint to start from beginning
          final checkpointsDao = ref.read(sequenceCheckpointsDaoProvider);
          await checkpointsDao.deleteCheckpoint(context.sequenceId!);
          debugPrint(
              '[QuickStart] Loaded sequence ${context.sequenceId}, reset to frame 1');
        }
      }

      // Apply equipment settings from snapshot
      await _applyEquipmentSnapshot(context.equipmentSnapshot);

      if (mounted) {
        final colors = Theme.of(this.context).extension<NightshadeColors>()!;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text(
                'Starting fresh session for ${context.targetName ?? "previous target"}'),
            backgroundColor: colors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[QuickStart] Error starting fresh: $e');
      if (mounted) {
        final colors = Theme.of(this.context).extension<NightshadeColors>()!;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text('Failed to start fresh: $e'),
            backgroundColor: colors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleResumeProgress(QuickStartContext context) async {
    debugPrint(
        '[QuickStart] Resuming progress with context: ${context.displayDescription}');

    try {
      // Load the equipment profile
      if (context.profileId != null) {
        final profilesNotifier = ref.read(equipmentProfilesProvider.notifier);
        await profilesNotifier.setActiveProfile(context.profileId!);
        debugPrint('[QuickStart] Activated profile ${context.profileId}');
      }

      // Load the sequence (keep checkpoint for resumption)
      if (context.sequenceId != null) {
        final sequencesDao = ref.read(sequencesDaoProvider);
        final sequence =
            await sequencesDao.getSequenceById(context.sequenceId!);
        if (sequence != null) {
          debugPrint('[QuickStart] Loaded sequence ${context.sequenceId}, '
              'resuming from frame ${context.completedFrames}');
        }
      }

      // Apply equipment settings from snapshot
      await _applyEquipmentSnapshot(context.equipmentSnapshot);

      if (mounted) {
        final colors = Theme.of(this.context).extension<NightshadeColors>()!;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text(
                'Resuming session for ${context.targetName ?? "previous target"} '
                'from frame ${context.completedFrames}'),
            backgroundColor: colors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[QuickStart] Error resuming progress: $e');
      if (mounted) {
        final colors = Theme.of(this.context).extension<NightshadeColors>()!;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text('Failed to resume progress: $e'),
            backgroundColor: colors.error,
          ),
        );
      }
    }
  }

  Future<void> _applyEquipmentSnapshot(EquipmentSnapshot? snapshot) async {
    if (snapshot == null || !snapshot.hasEquipmentData) {
      debugPrint('[QuickStart] No equipment snapshot to apply');
      return;
    }

    debugPrint('[QuickStart] Applying equipment snapshot...');

    // Apply camera settings
    final cameraNotifier = ref.read(cameraStateProvider.notifier);
    if (snapshot.coolerTargetTemp != null) {
      cameraNotifier.setTargetTemp(snapshot.coolerTargetTemp!);
      debugPrint(
          '[QuickStart] Set cooler target temp to ${snapshot.coolerTargetTemp}');
    }

    // Note: gain/offset/binning are typically applied when starting an exposure,
    // not on camera state directly. The snapshot stores them for reference.

    // Apply filter position
    if (snapshot.filterPosition != null) {
      final filterWheelState = ref.read(filterWheelStateProvider);
      if (filterWheelState.connectionState == DeviceConnectionState.connected) {
        final deviceService = ref.read(deviceServiceProvider);
        try {
          await deviceService.setFilterWheelPosition(snapshot.filterPosition!);
          debugPrint(
              '[QuickStart] Moved filter wheel to position ${snapshot.filterPosition}');
        } catch (e) {
          debugPrint('[QuickStart] Failed to move filter wheel: $e');
        }
      }
    }

    // Apply focus position
    if (snapshot.focuserPosition != null) {
      final focuserState = ref.read(focuserStateProvider);
      if (focuserState.connectionState == DeviceConnectionState.connected) {
        final deviceService = ref.read(deviceServiceProvider);
        try {
          await deviceService.moveFocuserTo(snapshot.focuserPosition!);
          debugPrint(
              '[QuickStart] Moved focuser to position ${snapshot.focuserPosition}');
        } catch (e) {
          debugPrint('[QuickStart] Failed to move focuser: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
