import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import 'css_declaration_parser.dart';
import 'document_node.dart';
import 'document_snapshot.dart';
import 'html_spec.dart';
import 'style_sheet.dart';
import 'style_sheet_parser.dart';
import 'support_report.dart';

final class WeftNormalizationLimits {
  const WeftNormalizationLimits({
    this.maxInputLength = 2 * 1024 * 1024,
    this.maxStyleLength = 256 * 1024,
    this.maxInlineStyleLength = 10 * 1024,
    this.maxNodes = 100000,
    this.maxDepth = 128,
    this.maxIssues = 100,
  });

  final int maxInputLength;
  final int maxStyleLength;
  final int maxInlineStyleLength;
  final int maxNodes;
  final int maxDepth;
  final int maxIssues;
}

final class WeftNormalizer {
  const WeftNormalizer({this.limits = const WeftNormalizationLimits()});

  final WeftNormalizationLimits limits;

  WeftDocumentSnapshot normalize(
    String html, {
    required String id,
    int revision = 1,
  }) {
    final issues = <SupportIssue>[];

    if (html.length > limits.maxInputLength) {
      issues.add(
        const SupportIssue(
          code: 'html.input.tooLarge',
          message: 'The HTML input exceeds the configured size limit.',
          severity: SupportSeverity.error,
          requiresWebView: true,
        ),
      );
      return WeftDocumentSnapshot(
        id: id,
        revision: revision,
        normalizedHtml: '',
        supportReport: SupportReport(issues),
        body: null,
        styleSheet: const WeftStyleSheet.empty(),
      );
    }

    final parser = html_parser.HtmlParser(html);
    late final html_dom.Document document;
    try {
      document = parser.parse();
    } on Object catch (error) {
      issues.add(
        SupportIssue(
          code: 'html.parse.failed',
          message: 'The HTML input could not be parsed: $error',
          severity: SupportSeverity.error,
          requiresWebView: true,
        ),
      );
      return WeftDocumentSnapshot(
        id: id,
        revision: revision,
        normalizedHtml: '',
        supportReport: SupportReport(issues),
        body: null,
        styleSheet: const WeftStyleSheet.empty(),
      );
    }

    for (final error in parser.errors.take(20)) {
      issues.add(
        SupportIssue(
          code: 'html.parse.warning',
          message: error.toString(),
        ),
      );
    }

    if (document.querySelectorAll('script').isNotEmpty) {
      issues.add(
        const SupportIssue(
          code: 'html.script.unsupported',
          message:
              'Scripts require the runtime milestone and a WebView fallback.',
          requiresWebView: true,
        ),
      );
    }

    final styleBuffer = StringBuffer();
    var styleLength = 0;
    for (final element in document.querySelectorAll('style')) {
      final style = element.text;
      styleLength += style.length;
      if (styleLength > limits.maxStyleLength) break;
      styleBuffer
        ..writeln(style)
        ..writeln();
    }
    if (styleLength > limits.maxStyleLength) {
      issues.add(
        const SupportIssue(
          code: 'css.input.tooLarge',
          message: 'The style sheet exceeds the configured size limit.',
          severity: SupportSeverity.error,
          requiresWebView: true,
        ),
      );
    }

    final parsedStyle = WeftStyleSheetParser.parse(styleBuffer.toString());
    issues.addAll(parsedStyle.issues);

    final body = document.body;
    final builder = _TreeBuilder(issues: issues, limits: limits);
    final root = body == null ? null : builder.build(body);

    if (root == null) {
      issues.add(
        const SupportIssue(
          code: 'html.body.missing',
          message: 'No renderable document body was found.',
          severity: SupportSeverity.error,
          requiresWebView: true,
        ),
      );
    }

    return WeftDocumentSnapshot(
      id: id,
      revision: revision,
      normalizedHtml:
          root == null ? '' : root.children.map(_serializeNode).join(),
      supportReport: SupportReport(issues),
      body: root,
      styleSheet: parsedStyle.sheet,
    );
  }

  static String _serializeNode(WeftNode node) {
    if (node is WeftText) {
      return node.text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
    }
    if (node is! WeftElement) return '';
    final buffer = StringBuffer('<${node.tag}');
    final attributes = <String, String>{...node.attributes};
    if (node.inlineStyle.isNotEmpty) {
      attributes['style'] = node.inlineStyle.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('; ');
    }
    for (final entry in attributes.entries) {
      buffer.write(' ${entry.key}="${_escapeAttribute(entry.value)}"');
    }
    if (WeftHtmlSpec.voidTags.contains(node.tag)) {
      buffer.write('>');
      return buffer.toString();
    }
    buffer.write('>');
    for (final child in node.children) {
      buffer.write(_serializeNode(child));
    }
    buffer.write('</${node.tag}>');
    return buffer.toString();
  }

  static String _escapeAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

final class _TreeBuilder {
  _TreeBuilder({required this.issues, required this.limits});

  final List<SupportIssue> issues;
  final WeftNormalizationLimits limits;
  final Set<String> _reportedFallbackTags = <String>{};

  var _nextId = 0;
  var _nodeCount = 0;
  var _stopped = false;

  WeftElement? build(html_dom.Element body) {
    final rootId = _allocateNode(force: true);
    if (rootId == null) return null;
    final attributes = _sanitizeAttributes(body, 'body');
    final parsedStyle = _parseInlineStyle(body);
    final children = _visitNodes(body.nodes, depth: 1);
    return WeftElement(
      id: rootId,
      tag: 'body',
      attributes: attributes,
      inlineStyle: parsedStyle,
      children: children,
    );
  }

  List<WeftNode> _visitNodes(
    List<html_dom.Node> nodes, {
    required int depth,
  }) {
    final result = <WeftNode>[];
    for (final node in nodes) {
      if (_stopped) break;
      if (node is html_dom.Text) {
        if (node.data.isEmpty) continue;
        final id = _allocateNode();
        if (id == null) break;
        result.add(WeftText(id: id, text: node.data));
        continue;
      }
      if (node is! html_dom.Element) continue;

      final tag = node.localName?.toLowerCase();
      if (tag == null) {
        result.addAll(_visitNodes(node.nodes, depth: depth + 1));
        continue;
      }
      if (tag == 'style' || tag == 'script') continue;
      if (WeftHtmlSpec.ignoredContainerTags.contains(tag)) continue;
      if (WeftHtmlSpec.transparentTags.contains(tag)) {
        result.addAll(_visitNodes(node.nodes, depth: depth + 1));
        continue;
      }

      if (WeftHtmlSpec.fallbackTags.contains(tag)) {
        _reportFallback(tag);
        continue;
      }
      if (!WeftHtmlSpec.allowedTags.contains(tag)) {
        _addIssue(
          SupportIssue(
            code: 'html.tag.unknown',
            message: 'Unknown element "$tag" was unwrapped.',
          ),
        );
        result.addAll(_visitNodes(node.nodes, depth: depth + 1));
        continue;
      }
      if (depth > limits.maxDepth) {
        _addIssue(
          const SupportIssue(
            code: 'html.depth.limit',
            message: 'Content exceeded the nesting depth limit.',
            severity: SupportSeverity.error,
            requiresWebView: true,
          ),
        );
        _stopped = true;
        break;
      }

      final id = _allocateNode();
      if (id == null) break;
      final attributes = _sanitizeAttributes(node, tag);
      final inlineStyle = _parseInlineStyle(node);
      final children = WeftHtmlSpec.voidTags.contains(tag)
          ? const <WeftNode>[]
          : _visitNodes(node.nodes, depth: depth + 1);
      result.add(
        WeftElement(
          id: id,
          tag: tag,
          attributes: attributes,
          inlineStyle: inlineStyle,
          children: children,
        ),
      );
    }
    return result;
  }

  Map<String, String> _sanitizeAttributes(
    html_dom.Element element,
    String tag,
  ) {
    final result = <String, String>{};
    final allowed = <String>{
      ...WeftHtmlSpec.globalAttributes,
      ...?WeftHtmlSpec.tagAttributes[tag],
    };

    for (final entry in element.attributes.entries) {
      final name = entry.key.toString().toLowerCase();
      if (name == 'style' || !allowed.contains(name)) continue;
      var value = entry.value.trim();
      if (name == 'class') {
        value = value.split(RegExp(r'\s+')).where((part) {
          return part.isNotEmpty;
        }).join(' ');
        if (value.length > 1024) value = value.substring(0, 1024);
      } else if (name == 'id' && value.length > 256) {
        value = value.substring(0, 256);
      } else if (name == 'href') {
        value = _sanitizeHref(value);
        if (value.isEmpty) continue;
      } else if (name == 'title' && value.length > 1024) {
        value = value.substring(0, 1024);
      }
      if (value.isNotEmpty) result[name] = value;
    }
    return result;
  }

  Map<String, String> _parseInlineStyle(html_dom.Element element) {
    final style = element.attributes['style'];
    if (style == null || style.trim().isEmpty) return const {};
    if (style.length > limits.maxInlineStyleLength) {
      _addIssue(
        const SupportIssue(
          code: 'css.inline.tooLarge',
          message: 'An inline style block was dropped because it is too large.',
        ),
      );
      return const {};
    }
    final parsed = WeftDeclarationParser.parse(style);
    for (final issue in parsed.issues) {
      _addIssue(issue);
    }
    return parsed.declarations;
  }

  String _sanitizeHref(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      _addIssue(
        const SupportIssue(
          code: 'href.invalid',
          message: 'An invalid link URL was removed.',
        ),
      );
      return '';
    }
    final scheme = uri.scheme.toLowerCase();
    const blockedSchemes = <String>{
      'data',
      'file',
      'javascript',
      'vbscript',
    };
    if (blockedSchemes.contains(scheme)) {
      _addIssue(
        SupportIssue(
          code: 'href.scheme.blocked',
          message: 'The link scheme "$scheme" was removed.',
        ),
      );
      return '';
    }
    return value;
  }

  int? _allocateNode({bool force = false}) {
    if (_stopped) return null;
    if (!force && _nodeCount >= limits.maxNodes) {
      _addIssue(
        const SupportIssue(
          code: 'html.node.limit',
          message: 'Content exceeded the node limit.',
          severity: SupportSeverity.error,
          requiresWebView: true,
        ),
      );
      _stopped = true;
      return null;
    }
    _nodeCount += 1;
    return _nextId++;
  }

  void _reportFallback(String tag) {
    if (!_reportedFallbackTags.add(tag)) return;
    _addIssue(
      SupportIssue(
        code: 'html.tag.requiresFallback',
        message: 'Element "$tag" requires a fallback renderer.',
        requiresWebView: true,
      ),
    );
  }

  void _addIssue(SupportIssue issue) {
    if (issues.length >= limits.maxIssues) return;
    issues.add(issue);
  }
}
