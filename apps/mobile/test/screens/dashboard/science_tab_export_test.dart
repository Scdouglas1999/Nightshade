import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/science_tab.dart';

void main() {
  test(
    'remote science export stages the host PDF instead of local DAO data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nightshade-science-export-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var localExporterCalled = false;

      final staged = await stageScienceReportForShare(
        backend: _ReportBackend(Uint8List.fromList([37, 80, 68, 70])),
        sessionId: 42,
        exportLocalMarkdown: () async {
          localExporterCalled = true;
          throw StateError('local exporter must not run in companion mode');
        },
        temporaryDirectory: () async => directory,
      );

      expect(localExporterCalled, isFalse);
      expect(staged.mimeType, 'application/pdf');
      expect(staged.file.path, endsWith('nightshade-science-session-42.pdf'));
      expect(await staged.file.readAsBytes(), [37, 80, 68, 70]);
    },
  );
}

class _ReportBackend extends NetworkBackend {
  final Uint8List report;

  _ReportBackend(this.report)
    : super(serverHost: '127.0.0.1', autoConnectWebSocket: false);

  @override
  Future<Uint8List> generateObservationReport(int sessionId) async => report;
}
