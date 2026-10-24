typedef NodeId = int;

final class TextAnchor {
  const TextAnchor(this.nodeId, this.offset)
      : assert(nodeId >= 0),
        assert(offset >= 0);

  final NodeId nodeId;
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

final class TextSelectionRange {
  const TextSelectionRange({required this.anchor, required this.extent});

  const TextSelectionRange.collapsed(TextAnchor anchor)
      : this(anchor: anchor, extent: anchor);

  final TextAnchor anchor;
  final TextAnchor extent;

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
