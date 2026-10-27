import 'document_node.dart';
import 'support_report.dart';

/// How a selector chain relates parts: descendant (whitespace in CSS) or
/// child (`>`).
enum WeftSelectorCombinator { descendant, child }

/// Specificity triple compared the CSS way (ids, then classes, then
/// element names); ties fall through to source order.
final class WeftSpecificity implements Comparable<WeftSpecificity> {
  /// Creates a specificity from its three CSS components.
  const WeftSpecificity({
    this.ids = 0,
    this.classes = 0,
    this.elements = 0,
  });

  /// Number of id selectors in the matched chain.
  final int ids;

  /// Number of class selectors in the matched chain.
  final int classes;

  /// Number of element/tag selectors in the matched chain.
  final int elements;

  /// Single scalar used for comparisons: ids carry the most weight.
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

/// One compound selector between combinators, e.g. `p.doc` is tag `p` +
/// class `doc`. Pseudo-classes and attribute selectors never reach here —
/// the stylesheet parser drops them with diagnostics.
final class WeftSelectorPart {
  /// Creates a compound part; [classes] is copied into a set.
  WeftSelectorPart({
    this.tag,
    this.id,
    Iterable<String> classes = const [],
  }) : classes = Set<String>.unmodifiable(classes);

  /// Required tag name, or null for a wildcard part.
  final String? tag;

  /// Required id, or null.
  final String? id;

  /// Required classes (all must match).
  final Set<String> classes;

  /// Whether this part matches [element] on its own (ancestors not
  /// considered here — see [WeftSelector.matches]).
  bool matches(WeftElement element) {
    if (tag != null && element.tag != tag) return false;
    if (id != null && element.idAttribute != id) return false;
    if (classes.isEmpty) return true;
    final elementClasses = element.classes;
    return classes.every(elementClasses.contains);
  }
}

/// A full selector chain: [parts] joined by [combinators] (one fewer
/// combinator than parts).
final class WeftSelector {
  /// Creates a selector; [combinators] must have exactly
  /// `parts.length - 1` entries.
  WeftSelector({
    required Iterable<WeftSelectorPart> parts,
    Iterable<WeftSelectorCombinator> combinators = const [],
  })  : assert(parts.length > 0),
        assert(combinators.length == parts.length - 1),
        parts = List<WeftSelectorPart>.unmodifiable(parts),
        combinators = List<WeftSelectorCombinator>.unmodifiable(combinators);

  /// Compound parts, left to right as written in CSS.
  final List<WeftSelectorPart> parts;

  /// Combinators between parts; entry `i` joins parts `i` and `i + 1`.
  final List<WeftSelectorCombinator> combinators;

  /// CSS specificity of the whole chain.
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

  /// Whether the chain matches [element] with [ancestors] as its ancestor
  /// chain (nearest first), honoring descendant and child combinators.
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

/// One rule: selectors share the [declarations], resolved in cascade order
/// via [order] (stylesheet source position).
final class WeftStyleRule {
  /// Creates a rule; selectors and declarations are copied into
  /// unmodifiable collections.
  WeftStyleRule({
    required Iterable<WeftSelector> selectors,
    required Map<String, String> declarations,
    required this.order,
  })  : selectors = List<WeftSelector>.unmodifiable(selectors),
        declarations = Map<String, String>.unmodifiable(declarations);

  /// Selectors this rule matches with; any match applies the declarations.
  final List<WeftSelector> selectors;

  /// Supported `property: value` declarations in source order.
  final Map<String, String> declarations;

  /// Source-order index used as the final cascade tiebreaker.
  final int order;
}

/// Immutable parsed stylesheet handed to the style resolver.
final class WeftStyleSheet {
  /// Collects [rules] into an immutable sheet.
  factory WeftStyleSheet(Iterable<WeftStyleRule> rules) {
    return WeftStyleSheet._(List<WeftStyleRule>.unmodifiable(rules));
  }

  const WeftStyleSheet._(this.rules);

  /// A sheet with no rules.
  const WeftStyleSheet.empty() : this._(const []);

  /// Rules in source order.
  final List<WeftStyleRule> rules;
}

/// Result of parsing one stylesheet: the rules plus any diagnostics the
/// parser produced for dropped selector constructs.
final class WeftParsedStyleSheet {
  /// Bundles the sheet and its issues.
  WeftParsedStyleSheet({
    required this.sheet,
    required Iterable<SupportIssue> issues,
  }) : issues = List<SupportIssue>.unmodifiable(issues);

  /// Parsed rules (possibly empty).
  final WeftStyleSheet sheet;

  /// Diagnostics for constructs outside the subset.
  final List<SupportIssue> issues;
}
