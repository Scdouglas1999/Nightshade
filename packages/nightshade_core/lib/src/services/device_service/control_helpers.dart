part of '../device_service.dart';

extension _DeviceServiceControlHelpers on DeviceService {
  /// connect and apply them to the active equipment profile ONLY when the
  /// profile has no explicit value set.
  ///
  /// Contract:
  /// - Query the camera SDK via [NightshadeBackend.cameraGetRecommendedSettings].
  /// - If unityGain is non-null AND the profile's defaultGain is null, write
  ///   the recommendation through and log it.
  /// - Same for defaultOffset.
  /// - Existing user-set values are never overwritten.
  /// - Any failure (query failed, no active profile, no profile id) is logged
  ///   and swallowed — the camera is already connected; auto-detect is a
  ///   convenience, not a precondition.
  Future<void> _autoApplyRecommendedCameraSettings(
      String deviceId, String deviceName) async {
    try {
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile == null || activeProfile.id == null) {
        // No profile to update. Honest no-op.
        return;
      }

      // If the profile already has BOTH values set, skip the SDK query
      // entirely — there's nothing we'd want to write anyway.
      if (activeProfile.defaultGain != null &&
          activeProfile.defaultOffset != null) {
        return;
      }

      final CameraRecommendedSettings rec;
      try {
        rec = await _backend.cameraGetRecommendedSettings(deviceId);
      } catch (e) {
        _safeLog(
          (l) => l.warning(
              'Auto-detect recommended camera settings failed for $deviceName ($deviceId): $e',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // No recommendation available (typical for ASCOM/Alpaca/INDI and
      // Touptek/Player One/Atik/FLI/Moravian). Honest no-op.
      if (rec.unityGain == null && rec.defaultOffset == null) {
        if (rec.notes.isNotEmpty) {
          _safeLog(
            (l) => l.info(
                'Camera $deviceName reported no SDK recommendation: ${rec.notes}',
                source: 'DeviceService'),
            'auto-detect-recommended-settings',
          );
        }
        return;
      }

      // Decide what to apply. Never overwrite user values.
      final int? newGain =
          (activeProfile.defaultGain == null) ? rec.unityGain : null;
      final int? newOffset =
          (activeProfile.defaultOffset == null) ? rec.defaultOffset : null;

      if (newGain == null && newOffset == null) {
        // Both already set by the user; surface the recommendation in logs
        // so they can compare manually if interested.
        _safeLog(
          (l) => l.info(
              'Camera $deviceName advertised recommendation but profile already populated. '
              'SDK reported: unity_gain=${rec.unityGain}, default_offset=${rec.defaultOffset}. '
              'Notes: ${rec.notes}',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // Persist the new values.
      final notifier = _ref.read(equipmentProfilesProvider.notifier);
      final updated = activeProfile.copyWith(
        defaultGain: newGain ?? activeProfile.defaultGain,
        defaultOffset: newOffset ?? activeProfile.defaultOffset,
      );
      try {
        await notifier.updateProfile(updated);
      } catch (e) {
        _safeLog(
          (l) => l.warning(
              'Failed to persist auto-detected camera settings to profile ${activeProfile.id}: $e',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // Log clearly per task spec: "Auto-applied recommended gain from
      // camera (X): unity gain at G=Y".
      final logged = <String>[];
      if (newGain != null) {
        logged.add('unity gain G=$newGain');
      }
      if (newOffset != null) {
        logged.add('offset O=$newOffset');
      }
      _safeLog(
        (l) => l.info(
            'Auto-applied recommended camera settings from $deviceName: '
            '${logged.join(", ")} (notes: ${rec.notes})',
            source: 'DeviceService'),
        'auto-detect-recommended-settings',
      );
    } catch (e) {
      // Belt-and-braces: any unexpected error here must not break the
      // connect flow.
      _safeLog(
        (l) => l.warning(
            'Unexpected error in auto-detect recommended settings for $deviceId: $e',
            source: 'DeviceService'),
        'auto-detect-recommended-settings',
      );
    }
  }

  /// Sync filter names from the active equipment profile or session to the
  /// native driver after a filter wheel connects.
  ///
  /// Filter names are resolved in this priority order:
  /// 1. Active profile filter names (if profile exists and has filter names)
  /// 2. Session filter names (if set via sessionFilterNamesProvider)
  /// 3. Driver-reported names (no sync needed, already set)
  Future<void> _syncFilterNamesToDriver(
      String deviceId, List<String> driverNames) async {
    final notifier = _ref.read(filterWheelStateProvider.notifier);
    final logger = _ref.read(loggingServiceProvider);

    try {
      // Priority 1: Check active profile filter names
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile != null && activeProfile.filterNames.isNotEmpty) {
        final profileFilterNames = activeProfile.filterNames;
        logger.debug(
          'Profile has ${profileFilterNames.length} filter names; '
          'driver has ${driverNames.length} slots',
          source: 'DeviceService',
        );

        // Pad or trim profile names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (profileFilterNames.length < driverNames.length) {
          syncedNames = [
            ...profileFilterNames,
            ...driverNames.sublist(profileFilterNames.length),
          ];
          logger.debug(
            'Padded profile filter names to ${syncedNames.length}: '
            '$syncedNames',
            source: 'DeviceService',
          );
        } else if (profileFilterNames.length > driverNames.length &&
            driverNames.isNotEmpty) {
          syncedNames = profileFilterNames.sublist(0, driverNames.length);
        } else {
          syncedNames = profileFilterNames;
        }

        await _applyFilterNamesToNotifier(
          notifier: notifier,
          deviceId: deviceId,
          syncedNames: syncedNames,
        );
        logger.debug(
          'Profile filter names synced: $syncedNames',
          source: 'DeviceService',
        );
        return;
      }

      // Priority 2: Check session filter names
      final sessionFilterNames = _ref.read(sessionFilterNamesProvider);
      if (sessionFilterNames != null && sessionFilterNames.isNotEmpty) {
        logger.debug(
          'Session has ${sessionFilterNames.length} filter names; '
          'driver has ${driverNames.length} slots',
          source: 'DeviceService',
        );

        // Pad or trim session names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (sessionFilterNames.length < driverNames.length) {
          syncedNames = [
            ...sessionFilterNames,
            ...driverNames.sublist(sessionFilterNames.length),
          ];
        } else if (sessionFilterNames.length > driverNames.length &&
            driverNames.isNotEmpty) {
          syncedNames = sessionFilterNames.sublist(0, driverNames.length);
        } else {
          syncedNames = sessionFilterNames;
        }

        await _applyFilterNamesToNotifier(
          notifier: notifier,
          deviceId: deviceId,
          syncedNames: syncedNames,
        );
        logger.debug(
          'Session filter names synced: $syncedNames',
          source: 'DeviceService',
        );
        return;
      }

      // Priority 3: Use driver-reported names (already set, no sync needed)
      logger.debug(
        'No profile or session filter names; using driver-reported names',
        source: 'DeviceService',
      );
    } catch (e) {
      // Don't fail connection if filter name sync fails - log the error
      logger.warning(
        'Failed to sync filter names: $e',
        source: 'DeviceService',
      );
    }
  }

  /// Derive a human-readable name from a device ID without running discovery.
  /// e.g. "native:zwo_efw:0" → "ZWO EFW 0"
  ///      "ascom:ASCOM.EFWmini.FilterWheel" → "EFWmini FilterWheel"
  ///
  /// Delegates to the single source of truth in `utils/device_id.dart` so the
  /// id-pattern fallback lives in exactly one place.
  String _friendlyNameFromId(String deviceId) =>
      friendlyNameFromDeviceId(deviceId);

  /// Verify focuser reached target position with polling and timeout.
  ///
  /// Polls the focuser position every 500ms until it reaches the target
  /// (within 1 step tolerance). Times out after 300 seconds.
  Future<void> _verifyFocuserPosition({
    required String deviceId,
    required int targetPosition,
    required int generation,
  }) async {
    final deadline = DateTime.now().add(DeviceService._focuserMoveTimeout);
    final focuserNotifier = _ref.read(focuserStateProvider.notifier);

    while (true) {
      if (_disposed || generation != _focuserVerifyGeneration) {
        throw StateError('Focuser verification was cancelled.');
      }

      final status = await _backend.getFocuserStatus(deviceId);
      if (_disposed || generation != _focuserVerifyGeneration) {
        throw StateError('Focuser verification was cancelled.');
      }
      focuserNotifier.updatePosition(status.position);
      focuserNotifier.setMoving(status.moving);
      if (status.temperature != null) {
        focuserNotifier.updateTemperature(status.temperature!);
      }

      // Check if we've reached the target (within 1 step tolerance)
      if ((status.position - targetPosition).abs() <= 1) {
        focuserNotifier.setMoving(false);
        return;
      }

      // Check if focuser stopped moving but hasn't reached target (stall)
      if (!status.moving && (status.position - targetPosition).abs() > 1) {
        throw Exception(
          'Focuser stalled at position ${status.position}, '
          'target was $targetPosition.',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Focuser did not reach position $targetPosition within '
          '${DeviceService._focuserMoveTimeout.inSeconds}s '
          '(last reported position: ${status.position}).',
        );
      }

      await Future.delayed(DeviceService._focuserMovePollInterval);
    }
  }

  /// After a failed verify, sync position/moving from hardware instead of
  /// blindly clearing moving state while the wheel is still rotating.
  Future<bool> _recoverFilterWheelMovingState(
    String deviceId,
    FilterWheelStateNotifier filterWheelNotifier,
  ) async {
    try {
      final status = await _backend.getFilterWheelStatus(deviceId);
      filterWheelNotifier.updatePosition(status.position);
      final stillMoving = status.moving || status.position < 0;
      filterWheelNotifier.setMoving(stillMoving);
      return stillMoving;
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'Filter wheel moving-state recovery failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'filter-wheel-recover-moving',
      );
      return false;
    }
  }

  Future<void> _verifyFilterWheelPosition({
    required String deviceId,
    required int expectedPosition,
    required List<String> filterNames,
    required int generation,
  }) async {
    final deadline =
        DateTime.now().add(DeviceService._filterWheelVerifyTimeout);
    final filterWheelNotifier = _ref.read(filterWheelStateProvider.notifier);

    while (true) {
      if (_disposed || generation != _filterWheelVerifyGeneration) {
        throw StateError('Filter wheel verification was cancelled.');
      }

      final status = await _backend.getFilterWheelStatus(deviceId);
      if (_disposed || generation != _filterWheelVerifyGeneration) {
        throw StateError('Filter wheel verification was cancelled.');
      }
      final isMoving = status.moving || status.position < 0;

      filterWheelNotifier.updatePosition(status.position);
      filterWheelNotifier.setMoving(isMoving);

      if (!isMoving && status.position == expectedPosition) {
        return;
      }

      if (!isMoving && status.position != expectedPosition) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final actualName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel reported "$actualName" after change, expected "$expectedName".',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final lastName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel did not reach "$expectedName" within ${DeviceService._filterWheelVerifyTimeout.inSeconds}s '
          '(last reported "$lastName").',
        );
      }

      await Future.delayed(DeviceService._filterWheelVerifyPollInterval);
    }
  }

  String _formatFilterName(List<String> filterNames, int position) {
    if (position >= 0 && position < filterNames.length) {
      return filterNames[position];
    }
    return 'Position $position';
  }

  /// Apply focus offset for a given filter
  ///
  /// Checks if there's a configured offset for this filter and moves
  /// the focuser accordingly. This is called automatically by setFilterWheelPosition.
  /// Respects the `useFilterFocusOffsets` toggle from AppSettings.
  ///
  /// Uses delta-based offset application: when switching from filter A to
  /// filter B, the focuser is moved by (B_offset - A_offset) rather than
  /// cumulative addition, preventing drift over multiple filter changes.
  ///
  /// Per-filter autofocus config `focusOffset` values from AppSettings take
  /// precedence over the general filter offset provider values.
  Future<void> _applyFilterFocusOffset(String filterName) async {
    try {
      // Check if filter focus offsets are enabled in settings.
      // If settings haven't loaded yet, skip offsets (fail closed) rather than
      // applying offsets the user may have disabled.
      final appSettings = _ref.read(appSettingsProvider).valueOrNull;
      if (appSettings == null || !appSettings.useFilterFocusOffsets) {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.debug(
          appSettings == null
              ? 'Filter focus offsets skipped: settings not yet loaded for "$filterName"'
              : 'Filter focus offsets disabled in settings, skipping offset for "$filterName"',
          source: 'DeviceService',
        );
        return;
      }

      // Check if focuser is connected
      final focuserDeviceId = await _getFocuserDeviceId();
      if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
        return;
      }

      // Check if focuser is ready
      final focuserState = _ref.read(focuserStateProvider);
      if (focuserState.connectionState != DeviceConnectionState.connected) {
        return;
      }

      // Resolve the effective offset for this filter.
      // Per-filter AF config focusOffset takes precedence if set.
      int newOffset = 0;

      final afFilterSettings = AutofocusSettings.parseFilterSettingsJson(
          appSettings.afFilterSettingsJson);
      final perFilterConfig = afFilterSettings[filterName];
      if (perFilterConfig != null && perFilterConfig.focusOffset != 0) {
        newOffset = perFilterConfig.focusOffset;
      } else {
        final filterOffsetState = _ref.read(filterOffsetProvider);
        newOffset = filterOffsetState.offsets[filterName] ?? 0;
      }

      final filterWheelDeviceId = _ref.read(filterWheelStateProvider).deviceId;
      final offsetKey = filterWheelDeviceId?.isNotEmpty == true
          ? filterWheelDeviceId!
          : '__default_filter_wheel__';
      final lastAppliedOffset = _lastAppliedFilterOffsetByWheel[offsetKey] ?? 0;

      // Calculate delta from last applied offset for this wheel.
      final delta = newOffset - lastAppliedOffset;

      if (delta == 0) {
        // No movement needed
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.debug(
          'Filter "$filterName" offset ($newOffset) same as previous, no focuser move needed',
          source: 'DeviceService',
        );
        return;
      }

      // Move focuser by the delta amount
      final currentPosition = focuserState.position ?? 0;
      final targetPosition = currentPosition + delta;

      final focuserNotifier = _ref.read(focuserStateProvider.notifier);
      focuserNotifier.setMoving(true);

      try {
        await _backend.focuserMoveTo(focuserDeviceId, targetPosition);
        focuserNotifier.updatePosition(targetPosition);
        _lastAppliedFilterOffsetByWheel[offsetKey] = newOffset;

        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.info(
          'Applied focus offset for filter "$filterName": delta=$delta steps '
          '(offset=$newOffset, moved to position $targetPosition)',
          source: 'DeviceService',
        );
      } finally {
        focuserNotifier.setMoving(false);
      }
    } catch (e) {
      // Don't fail filter change if focus offset fails
      final loggingService = _ref.read(loggingServiceProvider);
      loggingService.error(
        'Failed to apply focus offset for filter "$filterName": $e',
        source: 'DeviceService',
      );
    }
  }
}
