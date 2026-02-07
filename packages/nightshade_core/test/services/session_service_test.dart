import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  late NightshadeDatabase database;
  late SessionsDao sessionsDao;
  late SequenceCheckpointsDao checkpointsDao;
  late TargetsDao targetsDao;
  late EquipmentProfilesDao profilesDao;
  late SessionService sessionService;
  late LoggingService logger;

  setUp(() async {
    // Create in-memory database for testing
    database = NightshadeDatabase.forTesting(NativeDatabase.memory());
    sessionsDao = SessionsDao(database);
    checkpointsDao = SequenceCheckpointsDao(database);
    targetsDao = TargetsDao(database);
    profilesDao = EquipmentProfilesDao(database);

    // Seed FK dependencies used by session tests
    await targetsDao.createTarget(
      TargetsCompanion.insert(
        name: 'Target 1',
        ra: 5.0,
        dec: 25.0,
      ),
    );
    await targetsDao.createTarget(
      TargetsCompanion.insert(
        name: 'Target 2',
        ra: 10.0,
        dec: -15.0,
      ),
    );
    await targetsDao.createTarget(
      TargetsCompanion.insert(
        name: 'Target 3',
        ra: 15.0,
        dec: 35.0,
      ),
    );

    await profilesDao.createProfile(
      EquipmentProfilesCompanion.insert(name: 'Profile 1'),
    );
    await profilesDao.createProfile(
      EquipmentProfilesCompanion.insert(name: 'Profile 2'),
    );

    logger = LoggingService();
    sessionService = SessionService(
      sessionsDao: sessionsDao,
      checkpointsDao: checkpointsDao,
      logger: logger,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('SessionService - Lifecycle Management', () {
    test('startSession creates a new session with active status', () async {
      final sessionId = await sessionService.startSession(
        name: 'Test Session',
        targetId: 1,
        profileId: 2,
      );

      expect(sessionId, isPositive);
      expect(sessionService.hasActiveSession, isTrue);
      expect(sessionService.currentSessionId, equals(sessionId));

      // Verify session in database
      final session = await sessionsDao.getSessionById(sessionId);
      expect(session, isNotNull);
      expect(session!.name, equals('Test Session'));
      expect(session.targetId, equals(1));
      expect(session.profileId, equals(2));
      expect(session.status, equals('active'));
      expect(session.endTime, isNull);
    });

    test('startSession throws when session already active', () async {
      await sessionService.startSession(name: 'First Session');

      expect(
        () => sessionService.startSession(name: 'Second Session'),
        throwsException,
      );
    });

    test('endSession finalizes session with completed status', () async {
      final sessionId = await sessionService.startSession(name: 'Test Session');

      // Update some stats
      final stats = SessionStats(
        completedExposures: 10,
        failedExposures: 2,
        totalIntegrationSecs: 300.0,
        avgHfr: 2.5,
        avgGuidingRms: 0.8,
        autofocusCount: 3,
        lastUpdated: DateTime.now(),
      );
      await sessionService.updateSessionProgress(stats);

      await sessionService.endSession(status: 'completed');

      expect(sessionService.hasActiveSession, isFalse);
      expect(sessionService.currentSessionId, isNull);

      // Verify session in database
      final session = await sessionsDao.getSessionById(sessionId);
      expect(session, isNotNull);
      expect(session!.status, equals('completed'));
      expect(session.endTime, isNotNull);
      expect(session.successfulExposures, equals(10));
      expect(session.failedExposures, equals(2));
      expect(session.totalIntegrationSecs, equals(300.0));
      expect(session.avgHfr, equals(2.5));
      expect(session.avgGuidingRms, equals(0.8));
      expect(session.autofocusCount, equals(3));
    });

    test('abortSession marks session as aborted', () async {
      final sessionId = await sessionService.startSession(name: 'Test Session');
      await sessionService.abortSession();

      final session = await sessionsDao.getSessionById(sessionId);
      expect(session!.status, equals('aborted'));
    });

    test('errorSession marks session as error with message', () async {
      final sessionId = await sessionService.startSession(name: 'Test Session');
      await sessionService.errorSession('Camera disconnected');

      final session = await sessionsDao.getSessionById(sessionId);
      expect(session!.status, equals('error'));
      expect(session.notes, contains('Camera disconnected'));
    });
  });

  group('SessionService - Checkpointing', () {
    test('checkpoint saves current statistics', () async {
      final sessionId = await sessionService.startSession(name: 'Test Session');

      final stats = SessionStats(
        completedExposures: 5,
        failedExposures: 1,
        totalIntegrationSecs: 150.0,
        avgHfr: 2.3,
        lastUpdated: DateTime.now(),
      );
      await sessionService.updateSessionProgress(stats);

      // Manually trigger checkpoint
      await sessionService.checkpoint();

      // Verify stats are saved
      final session = await sessionsDao.getSessionById(sessionId);
      expect(session!.successfulExposures, equals(5));
      expect(session.failedExposures, equals(1));
      expect(session.totalIntegrationSecs, equals(150.0));
      expect(session.avgHfr, equals(2.3));
    });

    test('updateSessionProgress triggers checkpoint after image threshold',
        () async {
      final config = SessionCheckpointConfig(
        checkpointImageInterval: 3,
        checkpointTimeInterval:
            Duration(hours: 1), // Long time to avoid time-based trigger
        enabled: true,
      );
      sessionService.updateConfig(config);

      final sessionId = await sessionService.startSession(name: 'Test Session');

      // First update - no checkpoint
      await sessionService.updateSessionProgress(SessionStats(
        completedExposures: 1,
        failedExposures: 0,
        totalIntegrationSecs: 30.0,
        lastUpdated: DateTime.now(),
      ));

      var session = await sessionsDao.getSessionById(sessionId);
      expect(session!.successfulExposures, equals(0)); // Not checkpointed yet

      // Second update - no checkpoint
      await sessionService.updateSessionProgress(SessionStats(
        completedExposures: 2,
        failedExposures: 0,
        totalIntegrationSecs: 60.0,
        lastUpdated: DateTime.now(),
      ));

      session = await sessionsDao.getSessionById(sessionId);
      expect(session!.successfulExposures, equals(0)); // Still not checkpointed

      // Third update - should trigger checkpoint
      await sessionService.updateSessionProgress(SessionStats(
        completedExposures: 3,
        failedExposures: 0,
        totalIntegrationSecs: 90.0,
        lastUpdated: DateTime.now(),
      ));

      session = await sessionsDao.getSessionById(sessionId);
      expect(session!.successfulExposures, equals(3)); // Now checkpointed
      expect(session.totalIntegrationSecs, equals(90.0));
    });

    test('checkpoint configuration can be updated', () async {
      expect(sessionService.config.checkpointImageInterval, equals(5));
      expect(sessionService.config.checkpointTimeInterval,
          equals(Duration(minutes: 5)));

      final newConfig = SessionCheckpointConfig(
        checkpointImageInterval: 10,
        checkpointTimeInterval: Duration(minutes: 10),
        enabled: true,
      );
      sessionService.updateConfig(newConfig);

      expect(sessionService.config.checkpointImageInterval, equals(10));
      expect(sessionService.config.checkpointTimeInterval,
          equals(Duration(minutes: 10)));
    });
  });

  group('SessionService - Recovery', () {
    test('findIncompleteSessionsForRecovery finds active sessions', () async {
      // Create active session
      final activeId = await sessionsDao.startSession(
        name: 'Active Session',
        targetId: 1,
      );

      // Create completed session
      final completedId = await sessionsDao.startSession(
        name: 'Completed Session',
        targetId: 2,
      );
      await sessionsDao.updateSessionStats(completedId,
          successfulExposures: 10);
      await sessionsDao.endSession(completedId, status: 'completed');

      // Find incomplete sessions
      final incompleteSessions =
          await sessionService.findIncompleteSessionsForRecovery();

      expect(incompleteSessions.length, equals(1));
      expect(incompleteSessions[0].sessionId, equals(activeId));
      expect(incompleteSessions[0].sessionName, equals('Active Session'));
    });

    test('recoverSession restores session state', () async {
      // Create a session with stats
      final sessionId =
          await sessionsDao.startSession(name: 'Recoverable Session');
      await sessionsDao.updateSessionStats(
        sessionId,
        successfulExposures: 15,
        failedExposures: 3,
        totalIntegrationSecs: 450.0,
        avgHfr: 2.8,
        avgGuidingRms: 0.9,
        autofocusCount: 2,
      );

      // Simulate crash/restart - create new service instance
      final newService = SessionService(
        sessionsDao: sessionsDao,
        checkpointsDao: checkpointsDao,
        logger: logger,
      );

      expect(newService.hasActiveSession, isFalse);

      // Recover the session
      await newService.recoverSession(sessionId);

      expect(newService.hasActiveSession, isTrue);
      expect(newService.currentSessionId, equals(sessionId));

      final stats = newService.currentStats;
      expect(stats, isNotNull);
      expect(stats!.completedExposures, equals(15));
      expect(stats.failedExposures, equals(3));
      expect(stats.totalIntegrationSecs, equals(450.0));
      expect(stats.avgHfr, equals(2.8));
      expect(stats.avgGuidingRms, equals(0.9));
      expect(stats.autofocusCount, equals(2));
    });

    test('recoverSession throws when session not found', () async {
      expect(
        () => sessionService.recoverSession(999),
        throwsException,
      );
    });

    test('recoverSession throws when session is not active', () async {
      final sessionId = await sessionsDao.startSession(name: 'Test');
      await sessionsDao.endSession(sessionId, status: 'completed');

      expect(
        () => sessionService.recoverSession(sessionId),
        throwsException,
      );
    });

    test('recoverSession throws when another session is active', () async {
      await sessionService.startSession(name: 'Active Session');

      final oldSessionId = await sessionsDao.startSession(name: 'Old Session');

      expect(
        () => sessionService.recoverSession(oldSessionId),
        throwsException,
      );
    });

    test('markSessionAborted marks session as aborted without active session',
        () async {
      final sessionId = await sessionsDao.startSession(name: 'Test Session');

      // Mark as aborted without making it active
      await sessionService.markSessionAborted(sessionId);

      final session = await sessionsDao.getSessionById(sessionId);
      expect(session!.status, equals('aborted'));
      expect(session.endTime, isNotNull);
    });
  });

  group('SessionService - Statistics Tracking', () {
    test('updateSessionProgress updates current stats', () async {
      await sessionService.startSession(name: 'Test Session');

      final stats = SessionStats(
        completedExposures: 20,
        failedExposures: 4,
        totalIntegrationSecs: 600.0,
        avgHfr: 3.1,
        avgGuidingRms: 1.2,
        autofocusCount: 5,
        lastImageId: 42,
        lastUpdated: DateTime.now(),
      );

      await sessionService.updateSessionProgress(stats);

      final currentStats = sessionService.currentStats;
      expect(currentStats, isNotNull);
      expect(currentStats!.completedExposures, equals(20));
      expect(currentStats.failedExposures, equals(4));
      expect(currentStats.totalIntegrationSecs, equals(600.0));
      expect(currentStats.avgHfr, equals(3.1));
      expect(currentStats.avgGuidingRms, equals(1.2));
      expect(currentStats.autofocusCount, equals(5));
      expect(currentStats.lastImageId, equals(42));
    });

    test('SessionStats calculates success rate correctly', () {
      final stats = SessionStats(
        completedExposures: 18,
        failedExposures: 2,
        totalIntegrationSecs: 0,
        lastUpdated: DateTime.now(),
      );

      expect(stats.successRate, equals(0.9)); // 18/20 = 0.9
    });

    test('SessionStats success rate handles zero exposures', () {
      final stats = SessionStats(
        completedExposures: 0,
        failedExposures: 0,
        totalIntegrationSecs: 0,
        lastUpdated: DateTime.now(),
      );

      expect(
          stats.successRate, equals(1.0)); // Default to 1.0 when no exposures
    });
  });

  group('SessionService - Status Stream', () {
    test('status stream emits events', () async {
      final statusEvents = <String>[];
      final subscription = sessionService.statusStream.listen((status) {
        statusEvents.add(status);
      });

      await sessionService.startSession(name: 'Test Session');
      await sessionService.endSession();

      await Future.delayed(Duration(milliseconds: 100));

      expect(statusEvents.length, greaterThanOrEqualTo(2));
      expect(statusEvents.any((s) => s.contains('started')), isTrue);
      expect(statusEvents.any((s) => s.contains('ended')), isTrue);

      await subscription.cancel();
    });
  });

  group('SessionService - Edge Cases', () {
    test('endSession with no active session does nothing', () async {
      expect(sessionService.hasActiveSession, isFalse);

      await sessionService.endSession();

      expect(sessionService.hasActiveSession, isFalse);
    });

    test('checkpoint with no active session does nothing', () async {
      expect(sessionService.hasActiveSession, isFalse);

      await sessionService.checkpoint();

      expect(sessionService.hasActiveSession, isFalse);
    });

    test('updateSessionProgress with no active session does nothing', () async {
      expect(sessionService.hasActiveSession, isFalse);

      final stats = SessionStats(
        completedExposures: 5,
        failedExposures: 0,
        totalIntegrationSecs: 150.0,
        lastUpdated: DateTime.now(),
      );
      await sessionService.updateSessionProgress(stats);

      expect(sessionService.currentStats, isNull);
    });

    test('service can be disposed safely', () {
      expect(() => sessionService.dispose(), returnsNormally);
    });

    test('service can be disposed with active session', () async {
      await sessionService.startSession(name: 'Test Session');
      expect(sessionService.hasActiveSession, isTrue);

      expect(() => sessionService.dispose(), returnsNormally);
    });
  });

  group('SessionService - Multiple Sessions', () {
    test('can start new session after ending previous one', () async {
      final sessionId1 = await sessionService.startSession(name: 'Session 1');
      await sessionService.endSession();

      final sessionId2 = await sessionService.startSession(name: 'Session 2');
      expect(sessionId2, isNot(equals(sessionId1)));
      expect(sessionService.currentSessionId, equals(sessionId2));
    });

    test('multiple incomplete sessions can be recovered', () async {
      // Create multiple active sessions (simulating different app instances)
      await sessionsDao.startSession(name: 'Session 1', targetId: 1);
      await sessionsDao.startSession(name: 'Session 2', targetId: 2);
      await sessionsDao.startSession(name: 'Session 3', targetId: 3);

      final incompleteSessions =
          await sessionService.findIncompleteSessionsForRecovery();

      expect(incompleteSessions.length, equals(3));
      final names = incompleteSessions
          .map((session) => session.sessionName)
          .whereType<String>()
          .toSet();
      expect(
        names,
        containsAll(<String>['Session 1', 'Session 2', 'Session 3']),
      );
    });
  });

  group('SessionRecoveryInfo', () {
    test('calculates duration correctly', () {
      final startTime =
          DateTime.now().subtract(Duration(hours: 2, minutes: 30));
      final recoveryInfo = SessionRecoveryInfo(
        sessionId: 1,
        startTime: startTime,
        stats: SessionStats(
          completedExposures: 10,
          failedExposures: 0,
          totalIntegrationSecs: 300.0,
          lastUpdated: DateTime.now(),
        ),
      );

      expect(recoveryInfo.duration.inHours, equals(2));
      expect(recoveryInfo.duration.inMinutes, greaterThanOrEqualTo(150));
    });
  });
}
