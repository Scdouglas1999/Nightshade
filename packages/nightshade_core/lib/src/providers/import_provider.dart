import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/import/sequence_importer.dart';

/// Provides the singleton [SequenceImporter] used by the UI.
final sequenceImporterProvider = Provider<SequenceImporter>((ref) {
  return SequenceImporter();
});
