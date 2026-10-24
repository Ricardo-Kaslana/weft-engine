import 'document_node.dart';
import 'support_report.dart';

enum WeftSelectorCombinator { descendant, child }

final class WeftSpecificity implements Comparable<WeftSpecificity> {
  const WeftSpecificity({
    this.ids = 0,
    this.classes = 0,
    this.elements = 0,
  });

  final int ids;
  final int classes;
  final int elements;

  int get packed => (ids << 20) | (classes << 10) | elements;

  @override
  int compareTo(WeftSpecificity other) => packed.compareTo(other.packed);

  @override
  bool operator ==(Object other) {
    return other is WeftSpecificity &&
        other.ids == ids &&
        other.classes == classes &&
        other.elements == elements;
  }

  @override
  int get hashCode => Object.hash(ids, classes, elements);
}

final class WeftSelectorPart {
  WeftSelectorPart({
    this.tag,
    this.id,
    Iterable<String> classes = const [],
  }) : classes = Set<String>.unmodifiable(classes);

  final String? tag;
  final String? id;
  final Set<String> classes;

  bool matches(WeftElement element) {
    if (tag != null && element.tag != tag) return false;
    if (id != null && element.idAttribute != id) return false;
    if (classes.isEmpty) return true;
    final elementClasses = element.classes;
    return classes.every(elementClasses.contains);
  }
}

final class WeftSelector {
  WeftSelector({
    required Iterable<WeftSelectorPart> parts,
    Iterable<WeftSelectorCombinator> combinators = const [],
  })  : assert(parts.length > 0),
        assert(combinators.length == parts.length - 1),
        parts = List<WeftSelectorPart>.unmodifiable(parts),
        combinators = List<WeftSelectorCombinator>.unmodifiable(combinators);

  final List<WeftSelectorPart> parts;
  final List<WeftSelectorCombinator> combinators;

  WeftSpecificity get specificity {
    var ids = 0;
    var classes = 0;
    var elements = 0;
    for (final part in parts) {
      if (part.id != null) ids += 1;
      classes += part.classes.length;
      if (part.tag != null) elements += 1;
    }
    return WeftSpecificity(ids: ids, classes: classes, elements: elements);
  }

  bool matches(WeftElement element, List<WeftElement> ancestors) {
    return _matchesAt(parts.length - 1, element, ancestors);
  }

  bool _matchesAt(
    int index,
    WeftElement element,
    List<WeftElement> ancestors,
  ) {
    if (!parts[index].matches(element)) return false;
    if (index == 0) return true;

    switch (combinators[index - 1]) {
      case WeftSelectorCombinator.child:
        if (ancestors.isEmpty) return false;
        return _matchesAt(
          index - 1,
          ancestors.last,
          ancestors.sublist(0, ancestors.length - 1),
        );
      case WeftSelectorCombinator.descendant:
        for (var cursor = ancestors.length - 1; cursor >= 0; cursor -= 1) {
          if (_matchesAt(
            index - 1,
            ancestors[cursor],
            ancestors.sublist(0, cursor),
          )) {
            return true;
          }
        }
        return false;
    }
  }
}

final class WeftStyleRule {
  WeftStyleRule({
    required Iterable<WeftSelector> selectors,
    required Map<String, String> declarations,
    required this.order,
  })  : selectors = List<WeftSelector>.unmodifiable(selectors),
        declarations = Map<String, String>.unmodifiable(declarations);

  final List<WeftSelector> selectors;
  final Map<String, String> declarations;
  final int order;
}

final class WeftStyleSheet {
  factory WeftStyleSheet(Iterable<WeftStyleRule> rules) {
    return WeftStyleSheet._(List<WeftStyleRule>.unmodifiable(rules));
  }

  const WeftStyleSheet._(this.rules);

  const WeftStyleSheet.empty() : this._(const []);

  final List<WeftStyleRule> rules;
}

final class WeftParsedStyleSheet {
  WeftParsedStyleSheet({
    required this.sheet,
    required Iterable<SupportIssue> issues,
  }) : issues = List<SupportIssue>.unmodifiable(issues);

  final WeftStyleSheet sheet;
  final List<SupportIssue> issues;
}
