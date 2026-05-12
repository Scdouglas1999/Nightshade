import 'package:equatable/equatable.dart';

/// Source format the canonical node was parsed from.
enum SourceFormat { nina, sgp }

extension SourceFormatExtension on SourceFormat {
  String get displayName {
    switch (this) {
      case SourceFormat.nina:
        return 'NINA';
      case SourceFormat.sgp:
        return 'Sequence Generator Pro';
    }
  }
}

/// Canonical instruction kinds we know how to map to Nightshade.
///
/// Sources are normalized into this enum so the mapper does not need to know
/// about NINA vs SGP specifics. If a source node cannot be normalized it is
/// returned as [CanonicalKind.unsupported] with the original type name in
/// [CanonicalSequenceNode.sourceType].
enum CanonicalKind {
  // Containers / logic
  sequential,
  parallel,
  loop,
  targetHeader,

  // Instructions
  exposure,
  slew,
  center,
  autofocus,
  filterChange,
  waitForTime,
  delay,
  dither,
  startGuiding,
  stopGuiding,
  meridianFlip,
  park,
  unpark,
  coolCamera,
  warmCamera,
  rotator,

  /// Decorative-only annotation/comment. Always dropped on mapping.
  annotation,

  /// Node we recognized as belonging to the source format but for which there
  /// is no Nightshade equivalent. The mapper will surface this in
  /// `unsupportedNodes`.
  unsupported,
}

/// A format-neutral representation of one node in an imported sequence.
///
/// Parsers produce a tree of these; the mapper consumes them and emits the
/// concrete `SequenceNode` subclasses Nightshade uses.
class CanonicalSequenceNode extends Equatable {
  final CanonicalKind kind;

  /// Human-readable name as provided by the source file (or a sensible default
  /// for instruction kinds).
  final String name;

  /// Original source-format type discriminator, e.g.
  /// `NINA.Sequencer.SequenceItem.Imaging.TakeExposure`. Always populated so
  /// the import summary can show "TakeExposure -> ExposureNode".
  final String sourceType;

  /// Bag of attributes copied straight off the source node. Mapper consults
  /// this for instruction-specific parameters (exposure time, RA/Dec, filter
  /// name, etc.). Unknown keys are silently ignored.
  final Map<String, Object?> attributes;

  /// Direct children, in execution order.
  final List<CanonicalSequenceNode> children;

  const CanonicalSequenceNode({
    required this.kind,
    required this.name,
    required this.sourceType,
    this.attributes = const {},
    this.children = const [],
  });

  /// Convenience: walk the tree (pre-order, includes self).
  Iterable<CanonicalSequenceNode> walk() sync* {
    yield this;
    for (final child in children) {
      yield* child.walk();
    }
  }

  CanonicalSequenceNode copyWith({
    CanonicalKind? kind,
    String? name,
    String? sourceType,
    Map<String, Object?>? attributes,
    List<CanonicalSequenceNode>? children,
  }) {
    return CanonicalSequenceNode(
      kind: kind ?? this.kind,
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      attributes: attributes ?? this.attributes,
      children: children ?? this.children,
    );
  }

  @override
  List<Object?> get props => [kind, name, sourceType, attributes, children];
}
