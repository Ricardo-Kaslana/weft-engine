import 'css_spec.dart';
import 'support_report.dart';

/// Result of parsing a declaration list: supported declarations plus
/// diagnostics for everything dropped.
final class WeftDeclarationParseResult {
  /// Creates a parse result.
  WeftDeclarationParseResult({
    required Map<String, String> declarations,
    required Iterable<SupportIssue> issues,
  })  : declarations = Map<String, String>.unmodifiable(declarations),
        issues = List<SupportIssue>.unmodifiable(issues);

  /// Supported declarations in source order; unsupported ones are absent.
  final Map<String, String> declarations;

  /// One diagnostic per dropped or degraded declaration (deduped per
  /// property name).
  final List<SupportIssue> issues;
}

/// Splits an inline `style` value (or declaration list) into supported
/// `property: value` declarations, dropping everything outside the subset
/// with an explicit diagnostic (comments removed, `!important` stripped
/// and reported, url()/var()/calc() values rejected).
abstract final class WeftDeclarationParser {
  static const _commentPattern = r'/\*[\s\S]*?\*/';
  static const _importantPattern = r'!\s*important\s*$';
  static const _unsupportedValuePattern = r'(?:url|var|calc)\s*\(';

  static WeftDeclarationParseResult parse(String source) {
    final declarations = <String, String>{};
    final issues = <SupportIssue>[];
    final reportedProperties = <String>{};
    final cleaned = source.replaceAll(RegExp(_commentPattern), '');

    for (final part in _splitDeclarations(cleaned)) {
      final colon = part.indexOf(':');
      if (colon <= 0) {
        _addIssue(
          issues,
          'css.declaration.invalid',
          'A CSS declaration without a valid name was dropped.',
        );
        continue;
      }

      final property = part.substring(0, colon).trim().toLowerCase();
      var value = part.substring(colon + 1).trim();
      if (value.isEmpty) continue;

      if (!WeftCssSpec.supportsProperty(property)) {
        if (reportedProperties.add(property)) {
          _addIssue(
            issues,
            'css.property.unsupported',
            'CSS property "$property" is outside the supported subset.',
          );
        }
        continue;
      }

      if (RegExp(_importantPattern, caseSensitive: false).hasMatch(value)) {
        value = value
            .replaceFirst(RegExp(_importantPattern, caseSensitive: false), '')
            .trim();
        _addIssue(
          issues,
          'css.important.unsupported',
          '!important is not supported and was ignored for "$property".',
        );
        continue;
      }

      if (RegExp(_unsupportedValuePattern, caseSensitive: false)
          .hasMatch(value)) {
        _addIssue(
          issues,
          'css.value.unsupported',
          'The value of "$property" uses an unsupported function.',
        );
        continue;
      }

      declarations[property] = value;
    }

    return WeftDeclarationParseResult(
      declarations: declarations,
      issues: issues,
    );
  }

  static Iterable<String> _splitDeclarations(String source) {
    final parts = <String>[];
    final current = StringBuffer();
    var quote = '';
    var escaped = false;
    var parentheses = 0;

    for (final codeUnit in source.codeUnits) {
      final character = String.fromCharCode(codeUnit);
      if (escaped) {
        current.write(character);
        escaped = false;
        continue;
      }
      if (character == r'\') {
        current.write(character);
        escaped = true;
        continue;
      }
      if (quote.isNotEmpty) {
        current.write(character);
        if (character == quote) quote = '';
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        current.write(character);
        continue;
      }
      if (character == '(') {
        parentheses += 1;
        current.write(character);
        continue;
      }
      if (character == ')') {
        if (parentheses > 0) parentheses -= 1;
        current.write(character);
        continue;
      }
      if (character == ';' && parentheses == 0) {
        final declaration = current.toString().trim();
        if (declaration.isNotEmpty) parts.add(declaration);
        current.clear();
        continue;
      }
      current.write(character);
    }

    final tail = current.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static void _addIssue(
    List<SupportIssue> issues,
    String code,
    String message,
  ) {
    if (issues.length >= 50) return;
    issues.add(SupportIssue(code: code, message: message));
  }
}
