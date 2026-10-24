import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css;

import 'css_spec.dart';
import 'style_sheet.dart';
import 'support_report.dart';

abstract final class WeftStyleSheetParser {
  static WeftParsedStyleSheet parse(String source) {
    if (source.trim().isEmpty) {
      return WeftParsedStyleSheet(
        sheet: const WeftStyleSheet.empty(),
        issues: const [],
      );
    }

    final issues = <SupportIssue>[];
    final rules = <WeftStyleRule>[];
    final messages = <css_parser.Message>[];
    late final css.StyleSheet parsed;

    try {
      parsed = css_parser.parse(
        source,
        errors: messages,
        options: const css_parser.PreprocessorOptions(
          useColors: false,
          inputFile: 'style',
        ),
      );
    } on Object catch (error) {
      issues.add(
        SupportIssue(
          code: 'css.parse.failed',
          message: 'The style sheet could not be parsed: $error',
        ),
      );
      return WeftParsedStyleSheet(
        sheet: const WeftStyleSheet.empty(),
        issues: issues,
      );
    }

    for (final message in messages.take(20)) {
      issues.add(
        SupportIssue(
          code: 'css.parse.warning',
          message: message.describe,
        ),
      );
    }

    var order = 0;
    final reportedSelectors = <String>{};
    final reportedProperties = <String>{};

    for (final node in parsed.topLevels) {
      if (node is css.Directive) {
        issues.add(
          const SupportIssue(
            code: 'css.directive.unsupported',
            message: 'CSS at-rules are outside the supported subset.',
          ),
        );
        continue;
      }
      if (node is! css.RuleSet) continue;
      if (rules.length >= 2000) {
        issues.add(
          const SupportIssue(
            code: 'css.rule.limit',
            message: 'Additional CSS rules were ignored at the rule limit.',
          ),
        );
        break;
      }

      final selectors = <WeftSelector>[];
      for (final selector
          in node.selectorGroup?.selectors ?? const <css.Selector>[]) {
        final converted = _convertSelector(selector);
        if (converted == null) {
          if (reportedSelectors.add(selector.toString())) {
            issues.add(
              SupportIssue(
                code: 'css.selector.unsupported',
                message: 'Unsupported CSS selector "$selector" was ignored.',
              ),
            );
          }
          continue;
        }
        selectors.add(converted);
      }
      if (selectors.isEmpty) continue;

      final declarations = <String, String>{};
      for (final declaration in node.declarationGroup.declarations) {
        if (declaration is! css.Declaration) continue;
        final property = declaration.property.toLowerCase();
        if (!WeftCssSpec.supportsProperty(property)) {
          if (reportedProperties.add(property)) {
            issues.add(
              SupportIssue(
                code: 'css.property.unsupported',
                message:
                    'CSS property "$property" is outside the supported subset.',
              ),
            );
          }
          continue;
        }
        if (declaration.important) {
          issues.add(
            SupportIssue(
              code: 'css.important.unsupported',
              message: '!important is not supported for "$property".',
            ),
          );
          continue;
        }

        final value = _declarationValue(declaration);
        if (value == null || value.isEmpty) continue;
        if (RegExp(r'(?:url|var|calc)\s*\(', caseSensitive: false)
            .hasMatch(value)) {
          issues.add(
            SupportIssue(
              code: 'css.value.unsupported',
              message: 'The value of "$property" uses an unsupported function.',
            ),
          );
          continue;
        }
        declarations[property] = value;
      }

      if (declarations.isEmpty) continue;
      rules.add(
        WeftStyleRule(
          selectors: selectors,
          declarations: declarations,
          order: order++,
        ),
      );
    }

    return WeftParsedStyleSheet(
      sheet: WeftStyleSheet(rules),
      issues: issues.take(100),
    );
  }

  static String? _declarationValue(css.Declaration declaration) {
    final raw = declaration.span.text.trim();
    final colon = raw.indexOf(':');
    if (colon < 0 || colon == raw.length - 1) return null;
    var value = raw.substring(colon + 1).trim();
    if (declaration.important) {
      value = value
          .replaceFirst(
            RegExp(r'!\s*important\s*$', caseSensitive: false),
            '',
          )
          .trim();
    }
    return value;
  }

  static WeftSelector? _convertSelector(css.Selector selector) {
    final parts = <WeftSelectorPart>[];
    final combinators = <WeftSelectorCombinator>[];
    var current = _PartBuilder();
    var hasPart = false;

    for (final sequence in selector.simpleSelectorSequences) {
      WeftSelectorCombinator? combinator;
      if (sequence.isCombinatorNone) {
        combinator = null;
      } else if (sequence.isCombinatorDescendant) {
        combinator = WeftSelectorCombinator.descendant;
      } else if (sequence.isCombinatorGreater) {
        combinator = WeftSelectorCombinator.child;
      } else {
        return null;
      }

      if (combinator != null) {
        if (!hasPart) return null;
        parts.add(current.build());
        combinators.add(combinator);
        current = _PartBuilder();
        hasPart = false;
      }

      if (!current.apply(sequence.simpleSelector)) return null;
      hasPart = true;
    }

    if (!hasPart) return null;
    parts.add(current.build());
    if (parts.isEmpty) return null;
    return WeftSelector(parts: parts, combinators: combinators);
  }
}

final class _PartBuilder {
  String? tag;
  String? id;
  final Set<String> classes = <String>{};

  bool apply(css.SimpleSelector selector) {
    if (selector.isWildcard) return true;
    if (selector is css.ElementSelector) {
      tag = selector.name.toLowerCase();
      return true;
    }
    if (selector is css.IdSelector) {
      id = selector.name;
      return true;
    }
    if (selector is css.ClassSelector) {
      classes.add(selector.name);
      return true;
    }
    return false;
  }

  WeftSelectorPart build() {
    return WeftSelectorPart(tag: tag, id: id, classes: classes);
  }
}
