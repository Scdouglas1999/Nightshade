// P0 regression — the DB sequence repository encoded five palette-reachable
// node types (OpenCover / CloseCover / CalibratorOn / CalibratorOff /
// SciencePhotometry) but had NO matching decoder case, so `_dbNodeToModel`
// returned null and `loadSequence` threw a StateError — losing the ENTIRE
// saved sequence. The cover/calibrator config was also dropped on encode.
// This drives a real in-memory database through saveSequence -> loadSequence
// and asserts every field round-trips.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late SequenceRepository repo;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    repo = SequenceRepository(db.sequencesDao);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'cover / calibrator / science-photometry nodes round-trip through the DB',
    () async {
      final root = InstructionSetNode(
        id: 'root',
        childIds: const [
          'open-cover',
          'calib-on',
          'science',
          'calib-off',
          'close-cover',
        ],
      );
      final sequence = Sequence.create(
        id: 'seq-db-cover-science',
        name: 'DB cover + science round trip',
        rootNodeId: 'root',
        nodes: {
          'root': root,
          'open-cover': OpenCoverNode(
            id: 'open-cover',
            parentId: 'root',
            timeoutSecs: 90,
          ),
          'calib-on': CalibratorOnNode(
            id: 'calib-on',
            parentId: 'root',
            brightness: 200,
            timeoutSecs: 45,
          ),
          'science': SciencePhotometryNode(
            id: 'science',
            parentId: 'root',
            targetDesignation: 'V0376 Per',
            referenceStars: const ['ref-a', 'ref-b'],
            maxCadenceGapSecs: 1.5,
            filter: 'V',
            exposureSecs: 30,
            count: 120,
            reduceLive: false,
            applyDifferential: false,
            quality: const PhotometryQualityGates(
              minSnr: 75,
              maxFwhmArcsec: 3.5,
              requireAllRefsVisible: false,
              maxAirmass: 2.0,
            ),
            gain: 100,
            offset: 20,
            binning: BinningMode.two,
          ),
          'calib-off': CalibratorOffNode(
            id: 'calib-off',
            parentId: 'root',
            timeoutSecs: 25,
          ),
          'close-cover': CloseCoverNode(
            id: 'close-cover',
            parentId: 'root',
            timeoutSecs: 75,
          ),
        },
      );

      final savedId = await repo.saveSequence(sequence);
      final loaded = await repo.loadSequence(savedId);

      expect(
        loaded,
        isNotNull,
        reason: 'loadSequence must not throw / drop the sequence',
      );
      expect(loaded!.nodes.length, 6);

      final reOpen = loaded.nodes['open-cover'];
      expect(reOpen, isA<OpenCoverNode>());
      expect((reOpen as OpenCoverNode).timeoutSecs, 90);

      final reCalibOn = loaded.nodes['calib-on'];
      expect(reCalibOn, isA<CalibratorOnNode>());
      expect((reCalibOn as CalibratorOnNode).brightness, 200);
      expect(reCalibOn.timeoutSecs, 45);

      final reCalibOff = loaded.nodes['calib-off'];
      expect(reCalibOff, isA<CalibratorOffNode>());
      expect((reCalibOff as CalibratorOffNode).timeoutSecs, 25);

      final reClose = loaded.nodes['close-cover'];
      expect(reClose, isA<CloseCoverNode>());
      expect((reClose as CloseCoverNode).timeoutSecs, 75);

      final reSci = loaded.nodes['science'];
      expect(reSci, isA<SciencePhotometryNode>());
      final sci = reSci as SciencePhotometryNode;
      expect(sci.targetDesignation, 'V0376 Per');
      expect(sci.referenceStars, ['ref-a', 'ref-b']);
      expect(sci.maxCadenceGapSecs, 1.5);
      expect(sci.filter, 'V');
      expect(sci.exposureSecs, 30);
      expect(sci.count, 120);
      expect(sci.reduceLive, isFalse);
      expect(sci.applyDifferential, isFalse);
      expect(sci.gain, 100);
      expect(sci.offset, 20);
      expect(sci.binning, BinningMode.two);
      expect(sci.quality.minSnr, 75);
      expect(sci.quality.maxFwhmArcsec, 3.5);
      expect(sci.quality.requireAllRefsVisible, isFalse);
      expect(sci.quality.maxAirmass, 2.0);
    },
  );
}
