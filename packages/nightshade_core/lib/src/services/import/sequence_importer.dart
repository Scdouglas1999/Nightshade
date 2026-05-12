import 'dart:io';

import '../../models/import/canonical_sequence_node.dart';
import '../../models/import/import_result.dart';
import 'canonical_node_mapper.dart';
import 'nina_sequence_parser.dart';
import 'sgp_sequence_parser.dart';

/// Top-level entry point for importing a sequence file. Detects the format
/// (NINA / SGP), parses to a canonical tree, and maps to a Nightshade
/// [Sequence].
///
/// Errors propagate. Specifically:
///   * [UnknownFormatError] - couldn't sniff NINA or SGP.
///   * [MalformedSourceError] - file looked like NINA/SGP but JSON was bad.
///   * [UnsupportedNodeError] - in strict mode, at least one node had no
///     Nightshade equivalent. Caller can retry with `forceUnsupported: true`.
class SequenceImporter {
  final NinaSequenceParser _nina;
  final SgpSequenceParser _sgp;
  final CanonicalNodeMapper _mapper;

  SequenceImporter({
    NinaSequenceParser? nina,
    SgpSequenceParser? sgp,
    CanonicalNodeMapper? mapper,
  })  : _nina = nina ?? NinaSequenceParser(),
        _sgp = sgp ?? SgpSequenceParser(),
        _mapper = mapper ?? CanonicalNodeMapper();

  /// Detect the format from [content]. Inspects only the first ~16 KB.
  SourceFormat detectFormat(String content) {
    final snippet =
        content.length > 16 * 1024 ? content.substring(0, 16 * 1024) : content;
    if (NinaSequenceParser.sniff(snippet)) return SourceFormat.nina;
    if (SgpSequenceParser.sniff(snippet)) return SourceFormat.sgp;
    throw UnknownFormatError(
      'Could not identify file as NINA (.json) or SGP (.sgf). '
      r'Expected a NINA $type discriminator or an SGP TargetSet.',
      sniffedSnippet: snippet.length > 200 ? snippet.substring(0, 200) : snippet,
    );
  }

  /// Import a file directly from disk.
  Future<ImportResult> importFromPath(String filePath,
      {required bool forceUnsupported, String? sequenceName}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MalformedSourceError('File does not exist: $filePath');
    }
    final content = await file.readAsString();
    final defaultName = sequenceName ?? _deriveSequenceName(filePath);
    return importFromString(content,
        forceUnsupported: forceUnsupported, sequenceName: defaultName);
  }

  /// Import from raw string content. [sequenceName] becomes the name on the
  /// resulting Nightshade sequence.
  ImportResult importFromString(String content,
      {required bool forceUnsupported, required String sequenceName}) {
    final format = detectFormat(content);
    final CanonicalSequenceNode root;
    switch (format) {
      case SourceFormat.nina:
        root = _nina.parse(content);
        break;
      case SourceFormat.sgp:
        root = _sgp.parse(content);
        break;
    }
    return _mapAndAssemble(root, format, sequenceName, forceUnsupported);
  }

  ImportResult _mapAndAssemble(
    CanonicalSequenceNode root,
    SourceFormat format,
    String sequenceName,
    bool forceUnsupported,
  ) {
    final mapped = _mapper.map(
      root,
      sequenceName: sequenceName,
      forceUnsupported: forceUnsupported,
    );

    // In strict mode, unsupported nodes are a hard stop. The caller gets the
    // full list (not just the first) so they can show it in a dialog.
    if (!forceUnsupported && mapped.unsupported.isNotEmpty) {
      throw UnsupportedNodeError(mapped.unsupported);
    }

    return ImportResult(
      sourceFormat: format,
      totalNodes: mapped.totalNodes,
      mappingTable: mapped.mappingTable,
      droppedNodes: mapped.dropped,
      unsupportedNodes: mapped.unsupported,
      sequence: mapped.sequence,
      forcedImport: forceUnsupported && mapped.unsupported.isNotEmpty,
    );
  }

  String _deriveSequenceName(String filePath) {
    final lastSep = filePath.lastIndexOf(RegExp(r'[\\/]'));
    final base = lastSep >= 0 ? filePath.substring(lastSep + 1) : filePath;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
