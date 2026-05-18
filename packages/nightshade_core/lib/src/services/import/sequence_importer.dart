import 'dart:io';

import '../../models/import/canonical_sequence_node.dart';
import '../../models/import/import_result.dart';
import '../../models/sequence/sequence_models.dart';
import '../../providers/sequence/sequence_validation.dart';
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
///   * [SequenceImportValidationFailedException] - after a successful
///     parse + map, running the unified validator surfaced ERROR-severity
///     issues. Caller can retry with `forceImport: true` to import the
///     sequence regardless (the issue list is still attached for display).
class SequenceImporter {
  final NinaSequenceParser _nina;
  final SgpSequenceParser _sgp;
  final CanonicalNodeMapper _mapper;

  /// Strategy used by [_runValidation]. Defaults to the pure top-level
  /// [validateSequence] (structural rules only — no Ref required since
  /// the importer runs in a non-Riverpod context). Tests can inject a
  /// fake to assert error paths without depending on the full rule
  /// registry.
  final List<ValidationIssue> Function(Sequence) _validate;

  SequenceImporter({
    NinaSequenceParser? nina,
    SgpSequenceParser? sgp,
    CanonicalNodeMapper? mapper,
    List<ValidationIssue> Function(Sequence)? validateSequenceFn,
  })  : _nina = nina ?? NinaSequenceParser(),
        _sgp = sgp ?? SgpSequenceParser(),
        _mapper = mapper ?? CanonicalNodeMapper(),
        _validate = validateSequenceFn ?? validateSequence;

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
      {required bool forceUnsupported,
      bool forceImport = false,
      String? sequenceName}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MalformedSourceError('File does not exist: $filePath');
    }
    final content = await file.readAsString();
    final defaultName = sequenceName ?? _deriveSequenceName(filePath);
    return importFromString(
      content,
      forceUnsupported: forceUnsupported,
      forceImport: forceImport,
      sequenceName: defaultName,
    );
  }

  /// Import from raw string content. [sequenceName] becomes the name on the
  /// resulting Nightshade sequence.
  ///
  /// After parse + map, the resulting [Sequence] is run through the
  /// unified validator (`validateSequence` — structural rules). If the
  /// result has ERROR-severity issues and [forceImport] is `false`, a
  /// [SequenceImportValidationFailedException] is thrown carrying both
  /// the issue list and the assembled (but unvalidated) result. The UI
  /// can show the issues and re-invoke with `forceImport: true` if the
  /// user opts to import anyway.
  ///
  /// Warnings and info-level issues never block import — they're
  /// returned via [ImportResult.validationIssues] for display in the
  /// summary dialog.
  ImportResult importFromString(
    String content, {
    required bool forceUnsupported,
    bool forceImport = false,
    required String sequenceName,
  }) {
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
    return _mapAndAssemble(
      root,
      format,
      sequenceName,
      forceUnsupported,
      forceImport,
    );
  }

  ImportResult _mapAndAssemble(
    CanonicalSequenceNode root,
    SourceFormat format,
    String sequenceName,
    bool forceUnsupported,
    bool forceImport,
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

    // Run the unified validator over the assembled sequence. We do this
    // *after* the unsupported-node check so the user sees only one error
    // class at a time (force-import-unsupported, then validation). If
    // forceImport is set, we still run validation so the issues can be
    // surfaced in the summary dialog — just don't throw.
    final issues = _validate(mapped.sequence);
    final hasErrors =
        issues.any((i) => i.severity == ValidationSeverity.error);

    final result = ImportResult(
      sourceFormat: format,
      totalNodes: mapped.totalNodes,
      mappingTable: mapped.mappingTable,
      droppedNodes: mapped.dropped,
      unsupportedNodes: mapped.unsupported,
      sequence: mapped.sequence,
      forcedImport: forceUnsupported && mapped.unsupported.isNotEmpty,
      validationIssues: issues,
    );

    if (hasErrors && !forceImport) {
      throw SequenceImportValidationFailedException(
        issues: issues,
        parsed: result,
      );
    }

    return result;
  }

  String _deriveSequenceName(String filePath) {
    final lastSep = filePath.lastIndexOf(RegExp(r'[\\/]'));
    final base = lastSep >= 0 ? filePath.substring(lastSep + 1) : filePath;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
