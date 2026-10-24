import 'text_selection.dart';

sealed class WeftNode {
  const WeftNode(this.id);

  final NodeId id;
}

final class WeftElement extends WeftNode {
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

  final String tag;
  final Map<String, String> attributes;
  final Map<String, String> inlineStyle;
  final List<WeftNode> children;

  String? attribute(String name) => attributes[name];

  String? get idAttribute => attributes['id'];

  Set<String> get classes {
    final value = attributes['class'];
    if (value == null || value.isEmpty) return const {};
    return value.split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toSet();
  }
}

final class WeftText extends WeftNode {
  const WeftText({required int id, required this.text}) : super(id);

  final String text;
}
