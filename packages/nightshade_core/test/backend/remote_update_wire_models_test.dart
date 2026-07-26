import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('remote update wire models', () {
    test('queued admission uses status and the caller operation', () {
      final job = RemoteJob.fromJson({
        'jobId': 'job-1',
        'status': 'queued',
      }, fallbackOperation: 'system.update.check');

      expect(job.jobId, 'job-1');
      expect(job.operation, 'system.update.check');
      expect(job.state, 'queued');
    });

    test('job admissions fail loudly when identity is missing', () {
      expect(
        () => RemoteJob.fromJson({
          'status': 'queued',
        }, fallbackOperation: 'system.update.check'),
        throwsFormatException,
      );
      expect(
        () => RemoteJob.fromJson({'jobId': 'job-1', 'status': 'queued'}),
        throwsFormatException,
      );
    });

    test('legacy status without signing capability fails closed', () {
      final status = RemoteUpdateStatus.fromJson({
        'state': 'available',
        'availableVersion': '6.1.0',
      });

      expect(status.hasAvailableUpdate, isTrue);
      expect(status.canAuthenticateUpdates, isFalse);
      expect(status.rollbackAvailable, isFalse);
    });

    test('invalid progress is not rendered as a plausible status', () {
      expect(
        () => RemoteUpdateStatus.fromJson({
          'state': 'downloading',
          'progressPct': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => RemoteUpdateStatus.fromJson({
          'state': 'downloading',
          'progressPct': 101,
        }),
        throwsFormatException,
      );
    });

    test(
      'version identity is required instead of defaulting to build zero',
      () {
        expect(
          () => RemoteVersionInfo.fromJson({
            'currentVersion': '6.0.0',
            'channel': 'stable',
            'platform': 'linux',
          }),
          throwsFormatException,
        );
        expect(
          () => RemoteVersionInfo.fromJson({
            'currentVersion': '',
            'buildNumber': 60,
            'channel': 'stable',
            'platform': 'linux',
          }),
          throwsFormatException,
        );
      },
    );
  });
}
