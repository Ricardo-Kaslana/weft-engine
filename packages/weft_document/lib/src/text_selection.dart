/// Stable per-node identifier assigned by normalization; anchors survive
/// streaming updates through it.
typedef NodeId = int;

/// A position inside the logical text model: [offset] is a UTF-16 offset
/// within node [nodeId]'s text.
final class TextAnchor {
  /// Creates an anchor; offsets are non-negative UTF-16 positions.
  const TextAnchor(this.nodeId, this.offset)
      : assert(nodeId >= 0),
        assert(offset >= 0);

  /// The node containing this position.
  final NodeId nodeId;

  /// UTF-16 code-unit offset inside the node's text.
  final int offset;

  @override
  bool operator ==(Object other) {
    return other is TextAnchor &&
        other.nodeId == nodeId &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(nodeId, offset);
}

/// A logical selection between two anchors; order-independent for
/// rendering (the engine normalizes base/extent internally).
final class TextSelectionRange {
  /// Creates a range between two anchors.
  const TextSelectionRange({required this.anchor, required this.extent});

  /// A single-position selection (no visual highlight, caret only).
  const TextSelectionRange.collapsed(TextAnchor anchor)
      : this(anchor: anchor, extent: anchor);

  /// Selection start boundary.
  final TextAnchor anchor;

  /// Selection end boundary.
  final TextAnchor extent;

  /// Whether the range is a single position.
  bool get isCollapsed => anchor == extent;

  @override
  bool operator ==(Object other) {
    return other is TextSelectionRange &&
        other.anchor == anchor &&
        other.extent == extent;
  }

  @override
  int get hashCode => Object.hash(anchor, extent);
}
