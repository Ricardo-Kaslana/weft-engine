import 'text_selection.dart';

/// A node of the normalized, immutable document tree. Ids are assigned
/// sequentially by the normalizer and are stable within a snapshot; views
/// key semantics and hit regions on them.
sealed class WeftNode {
  /// Node id from [NodeId] allocation order.
  const WeftNode(this.id);

  /// Normalization-assigned stable identifier.
  final NodeId id;
}

/// An element node with sanitized attributes, parsed inline style and
/// immutable children. Unknown/unsupported tags never appear here: the
/// normalizer either unwrapped, dropped, or reported them.
final class WeftElement extends WeftNode {
  /// Creates an element; the maps/lists are copied into unmodifiable
  /// collections.
  WeftElement({
    required int id,
    required this.tag,
    Map<String, String> attributes = const {},
    Map<String, String> inlineStyle = const {},
    Iterable<WeftNode> children = const [],
  })  : attributes = Map<String, String>.unmodifiable(attributes),
        inlineStyle = Map<String, String>.unmodifiable(inlineStyle),
        children = List<WeftNode>.unmodifiable(children),
        super(id);

  /// Lowercased tag name (always a whitelisted or custom tag).
  final String tag;

  /// Sanitized attributes (whitelisted names, truncated values).
  final Map<String, String> attributes;

  /// Inline `style` declarations after the declaration parser filtered
  /// them; insertion order matches the source.
  final Map<String, String> inlineStyle;

  /// Child nodes in document order.
  final List<WeftNode> children;

  /// Attribute value for [name], or null.
  String? attribute(String name) => attributes[name];

  /// The `id` attribute, or null.
  String? get idAttribute => attributes['id'];

  /// The `class` attribute split on whitespace; empty when absent.
  Set<String> get classes {
    final value = attributes['class'];
    if (value == null || value.isEmpty) return const {};
    return value.split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toSet();
  }
}

/// A text node. Whitespace is preserved exactly as normalization produced
/// it (the layout engine owns folding); text is UTF-16.
final class WeftText extends WeftNode {
  /// Creates a text node.
  const WeftText({required int id, required this.text}) : super(id);

  /// The node's text content.
  final String text;
}
