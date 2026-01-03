import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sequence/sequence_models.dart';
import 'sequence_repository.dart';
import 'backup_service.dart';

/// Configuration for auto-save behavior
class AutoSaveConfig {
  final Duration sequenceInterval;
  final Duration backupInterval;
  final bool sequenceEnabled;
  final bool backupEnabled;
  final int maxBackups;

  const AutoSaveConfig({
    this.sequenceInterval = const Duration(minutes: 2),
    this.backupInterval = const Duration(hours: 24),
    this.sequenceEnabled = true,
    this.backupEnabled = true,
    this.maxBackups = 7, // Keep last 7 auto-backups
  });

  AutoSaveConfig copyWith({
    Duration? sequenceInterval,
    Duration? backupInterval,
    bool? sequenceEnabled,
    bool? backupEnabled,
    int? maxBackups,
  }) {
    return AutoSaveConfig(
      sequenceInterval: sequenceInterval ?? this.sequenceInterval,
      backupInterval: backupInterval ?? this.backupInterval,
      sequenceEnabled: sequenceEnabled ?? this.sequenceEnabled,
      backupEnabled: backupEnabled ?? this.backupEnabled,
      maxBackups: maxBackups ?? this.maxBackups,
    );
  }
}

/// Status of auto-save operations
class AutoSaveStatus {
  final DateTime? lastSequenceSave;
  final DateTime? lastBackup;
  final bool isSequenceSaving;
  final bool isBackingUp;
  final String? lastError;

  const AutoSaveStatus({
    this.lastSequenceSave,
    this.lastBackup,
    this.isSequenceSaving = false,
    this.isBackingUp = false,
    this.lastError,
  });

  AutoSaveStatus copyWith({
    DateTime? lastSequenceSave,
    DateTime? lastBackup,
    bool? isSequenceSaving,
    bool? isBackingUp,
    String? lastError,
  }) {
    return AutoSaveStatus(
      lastSequenceSave: lastSequenceSave ?? this.lastSequenceSave,
      lastBackup: lastBackup ?? this.lastBackup,
      isSequenceSaving: isSequenceSaving ?? this.isSequenceSaving,
      isBackingUp: isBackingUp ?? this.isBackingUp,
      lastError: lastError,
    );
  }
}

/// Service for automatic saving of sequences and backups
class AutoSaveService {
  final SequenceRepository sequenceRepository;
  final BackupService backupService;

  AutoSaveConfig _config = const AutoSaveConfig();
  Timer? _sequenceTimer;
  Timer? _backupTimer;

  // Track sequences that need saving
  final Map<String, Sequence> _pendingSequences = {};
  bool _hasUnsavedChanges = false;

  // Status tracking
  final _statusController = StreamController<AutoSaveStatus>.broadcast();
  AutoSaveStatus _status = const AutoSaveStatus();

  AutoSaveService({
    required this.sequenceRepository,
    required this.backupService,
  });

  /// Stream of auto-save status updates
  Stream<AutoSaveStatus> get statusStream => _statusController.stream;

  /// Current auto-save status
  AutoSaveStatus get status => _status;

  /// Current configuration
  AutoSaveConfig get config => _config;

  /// Whether there are unsaved changes
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  /// Start the auto-save service
  void start([AutoSaveConfig? config]) {
    if (config != null) {
      _config = config;
    }

    debugPrint('AutoSaveService: Starting with config:');
    debugPrint('  Sequence auto-save: ${_config.sequenceEnabled} (every ${_config.sequenceInterval.inMinutes} min)');
    debugPrint('  Backup auto-save: ${_config.backupEnabled} (every ${_config.backupInterval.inHours} hours)');
    debugPrint('  Max backups: ${_config.maxBackups}');

    // Start sequence auto-save timer
    if (_config.sequenceEnabled) {
      _sequenceTimer?.cancel();
      _sequenceTimer = Timer.periodic(_config.sequenceInterval, (_) {
        _autoSaveSequences();
      });
    }

    // Start backup timer
    if (_config.backupEnabled) {
      _backupTimer?.cancel();
      _backupTimer = Timer.periodic(_config.backupInterval, (_) {
        _autoBackup();
      });

      // Also run initial backup check (delayed to avoid startup overhead)
      Future.delayed(const Duration(minutes: 5), () {
        _checkAndPerformBackup();
      });
    }

    debugPrint('AutoSaveService: Started successfully');
  }

  /// Stop the auto-save service
  void stop() {
    debugPrint('AutoSaveService: Stopping...');

    _sequenceTimer?.cancel();
    _sequenceTimer = null;

    _backupTimer?.cancel();
    _backupTimer = null;

    // Save any pending changes before stopping
    if (_hasUnsavedChanges) {
      _autoSaveSequences();
    }

    debugPrint('AutoSaveService: Stopped');
  }

  /// Update configuration (restarts timers if needed)
  void updateConfig(AutoSaveConfig newConfig) {
    final needsRestart = _config.sequenceInterval != newConfig.sequenceInterval ||
                        _config.backupInterval != newConfig.backupInterval ||
                        _config.sequenceEnabled != newConfig.sequenceEnabled ||
                        _config.backupEnabled != newConfig.backupEnabled;

    _config = newConfig;

    if (needsRestart) {
      stop();
      start();
    }

    debugPrint('AutoSaveService: Configuration updated');
  }

  /// Mark a sequence as having unsaved changes
  void markSequenceChanged(Sequence sequence) {
    _pendingSequences[sequence.id] = sequence;
    _hasUnsavedChanges = true;
  }

  /// Clear unsaved changes marker for a sequence
  void markSequenceSaved(String sequenceId) {
    _pendingSequences.remove(sequenceId);
    if (_pendingSequences.isEmpty) {
      _hasUnsavedChanges = false;
    }
  }

  /// Manually trigger sequence save
  Future<void> saveNow() async {
    await _autoSaveSequences();
  }

  /// Manually trigger backup
  Future<BackupResult> backupNow() async {
    return await _autoBackup();
  }

  /// Auto-save sequences that have pending changes
  Future<void> _autoSaveSequences() async {
    if (_pendingSequences.isEmpty) {
      return;
    }

    debugPrint('AutoSaveService: Auto-saving ${_pendingSequences.length} sequence(s)...');

    _updateStatus(_status.copyWith(isSequenceSaving: true));

    try {
      final sequences = _pendingSequences.values.toList();
      for (final sequence in sequences) {
        await sequenceRepository.saveSequence(sequence);
        _pendingSequences.remove(sequence.id);
      }

      _hasUnsavedChanges = _pendingSequences.isNotEmpty;

      _updateStatus(_status.copyWith(
        isSequenceSaving: false,
        lastSequenceSave: DateTime.now(),
        lastError: null,
      ));

      debugPrint('AutoSaveService: Successfully saved ${sequences.length} sequence(s)');
    } catch (e) {
      debugPrint('AutoSaveService: Error saving sequences: $e');
      _updateStatus(_status.copyWith(
        isSequenceSaving: false,
        lastError: 'Failed to auto-save sequences: $e',
      ));
    }
  }

  /// Check if backup is needed and perform it
  Future<void> _checkAndPerformBackup() async {
    // Check if enough time has passed since last backup
    if (_status.lastBackup != null) {
      final timeSinceLastBackup = DateTime.now().difference(_status.lastBackup!);
      if (timeSinceLastBackup < _config.backupInterval) {
        debugPrint('AutoSaveService: Skipping backup, last backup was ${timeSinceLastBackup.inHours} hours ago');
        return;
      }
    }

    await _autoBackup();
  }

  /// Perform automatic backup
  Future<BackupResult> _autoBackup() async {
    debugPrint('AutoSaveService: Starting automatic backup...');

    _updateStatus(_status.copyWith(isBackingUp: true));

    try {
      final result = await backupService.autoSaveBackup();

      if (result.success) {
        debugPrint('AutoSaveService: Backup completed successfully: ${result.filePath}');

        _updateStatus(_status.copyWith(
          isBackingUp: false,
          lastBackup: DateTime.now(),
          lastError: null,
        ));

        // Clean up old backups
        await _cleanupOldBackups();
      } else {
        debugPrint('AutoSaveService: Backup failed: ${result.errorMessage}');

        _updateStatus(_status.copyWith(
          isBackingUp: false,
          lastError: 'Backup failed: ${result.errorMessage}',
        ));
      }

      return result;
    } catch (e) {
      debugPrint('AutoSaveService: Error during backup: $e');

      _updateStatus(_status.copyWith(
        isBackingUp: false,
        lastError: 'Backup error: $e',
      ));

      return BackupResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// Remove old auto-save backups, keeping only the most recent ones
  Future<void> _cleanupOldBackups() async {
    try {
      final backups = await backupService.listBackups();

      // Filter to only auto-save backups
      final autoSaveBackups = backups
          .where((file) => file.path.contains('autosave'))
          .toList();

      // Keep only the most recent N backups
      if (autoSaveBackups.length > _config.maxBackups) {
        final toDelete = autoSaveBackups.sublist(_config.maxBackups);

        debugPrint('AutoSaveService: Cleaning up ${toDelete.length} old backup(s)');

        for (final file in toDelete) {
          try {
            await file.delete();
            debugPrint('AutoSaveService: Deleted old backup: ${file.path}');
          } catch (e) {
            debugPrint('AutoSaveService: Failed to delete backup ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('AutoSaveService: Error cleaning up backups: $e');
    }
  }

  void _updateStatus(AutoSaveStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  /// Dispose of resources
  void dispose() {
    stop();
    _statusController.close();
    debugPrint('AutoSaveService: Disposed');
  }
}

/// Provider for AutoSaveService
final autoSaveServiceProvider = Provider<AutoSaveService>((ref) {
  final sequenceRepo = ref.watch(sequenceRepositoryProvider);
  final backupService = ref.watch(backupServiceProvider);

  final service = AutoSaveService(
    sequenceRepository: sequenceRepo,
    backupService: backupService,
  );

  ref.onDispose(() => service.dispose());

  return service;
});

/// Provider for auto-save status stream
final autoSaveStatusProvider = StreamProvider<AutoSaveStatus>((ref) {
  final service = ref.watch(autoSaveServiceProvider);
  return service.statusStream;
});

/// Provider for checking if there are unsaved changes
final hasUnsavedChangesProvider = Provider<bool>((ref) {
  final service = ref.watch(autoSaveServiceProvider);
  return service.hasUnsavedChanges;
});
