import 'dart:convert';

import 'document_node.dart';
import 'document_snapshot.dart';
import 'style_sheet.dart';
import 'support_report.dart';

/// Canonical JSON wire format for [WeftDocumentSnapshot] (ADR 0034).
///
/// The format is the server/client normalization contract: a trusted server
/// may run [WeftNormalizer] once and ship the encoded snapshot to clients,
/// which decode it instead of re-parsing HTML. Consistency is pinned by the
/// committed vectors under `conformance/normalization/` — a conforming
/// producer must emit exactly the recorded bytes for the recorded input.
///
/// Encoding is deterministic: maps preserve insertion order and selector
/// class sets are sorted, so equal snapshots encode to identical strings.
///
/// Compatibility policy: [version] gates the decoder. A snapshot written by
/// a newer format version is rejected with a [FormatException] naming the
/// version, so rolling a client back to an older release fails loudly
/// instead of misreading content (release runbook, docs/release-runbook.md).
final class WeftDocumentJson {
  WeftDocumentJson._();

  /// Format tag stored in every encoded snapshot.
  static const formatId = 'weft.document';

  /// Current wire format version. Bump when encoding changes, and update the
  /// compatibility table in docs/release-runbook.md in the same commit.
  static const version = 1;

  /// Encodes [snapshot] to canonical JSON text.
  static String encodeToString(WeftDocumentSnapshot snapshot) =>
      jsonEncode(encode(snapshot));

  /// Encodes [snapshot] to a JSON-encodable map.
  static Map<String, Object?> encode(WeftDocumentSnapshot snapshot) {
    return <String, Object?>{
      'format': formatId,
      'version': version,
      'id': snapshot.id,
      'revision': snapshot.revision,
      'normalizedHtml': snapshot.normalizedHtml,
      'supportReport': <String, Object?>{
        'issues': <Object?>[
          for (final issue in snapshot.supportReport.issues)
            _encodeIssue(issue),
        ],
      },
      if (snapshot.body != null) 'body': _encodeNode(snapshot.body!),
      'styleSheet': _encodeStyleSheet(snapshot.styleSheet),
    };
  }

  /// Decodes canonical JSON text produced by [encodeToString].
  static WeftDocumentSnapshot decodeFromString(String json) =>
      decode(_expectMap(jsonDecode(json), 'snapshot'));

  /// Decodes a snapshot from a JSON-decoded map.
  static WeftDocumentSnapshot decode(Map<String, Object?> json) {
    final format = json['format'];
    if (format != formatId) {
      throw FormatException(
        'Not a Weft document snapshot (format: ${format is String ? format : format.runtimeType}).',
      );
    }
    final decodedVersion = json['version'];
    if (decodedVersion is! int) {
      throw const FormatException('Snapshot version must be an integer.');
    }
    if (decodedVersion > version) {
      throw FormatException(
        'Snapshot format version $decodedVersion is newer than this '
        'engine supports (max $version). Upgrade weft_document or ship the '
        'document in a compatible format version.',
      );
    }
    if (decodedVersion != version) {
      throw FormatException(
        'Snapshot format version $decodedVersion is no longer readable '
        '(this engine reads version $version).',
      );
    }

    final report = _expectMap(json['supportReport'], 'supportReport');
    final issues = <SupportIssue>[
      for (final item in _expectList(report['issues'], 'supportReport.issues'))
        _decodeIssue(_expectMap(item, 'supportReport.issues[]')),
    ];

    final bodyValue = json['body'];
    final body = bodyValue == null
        ? null
        : _decodeBodyElement(_expectMap(bodyValue, 'body'));

    final styleSheet = _decodeStyleSheet(
      _expectMap(json['styleSheet'], 'styleSheet'),
    );

    return WeftDocumentSnapshot(
      id: _expectString(json['id'], 'id'),
      revision: _expectInt(json['revision'], 'revision'),
      normalizedHtml: _expectString(json['normalizedHtml'], 'normalizedHtml'),
      supportReport: SupportReport(issues),
      body: body,
      styleSheet: styleSheet,
    );
  }

  static WeftElement _decodeBodyElement(Map<String, Object?> json) {
    final node = _decodeNode(json);
    if (node is! WeftElement) {
      throw const FormatException('Snapshot body must be an element.');
    }
    return node;
  }

  static Map<String, Object?> _encodeIssue(SupportIssue issue) {
    return <String, Object?>{
      'code': issue.code,
      'message': issue.message,
      'severity': issue.severity.name,
      'requiresWebView': issue.requiresWebView,
    };
  }

  static SupportIssue _decodeIssue(Map<String, Object?> json) {
    final severityName = _expectString(json['severity'], 'severity');
    final severity = SupportSeverity.values
        .where((value) => value.name == severityName)
        .firstOrNull;
    if (severity == null) {
      throw FormatException('Unknown support severity "$severityName".');
    }
    return SupportIssue(
      code: _expectString(json['code'], 'code'),
      message: _expectString(json['message'], 'message'),
      severity: severity,
      requiresWebView: _expectBool(
        json['requiresWebView'],
        'requiresWebView',
      ),
    );
  }

  static Map<String, Object?> _encodeNode(WeftNode node) {
    if (node is WeftText) {
      return <String, Object?>{'id': node.id, 'text': node.text};
    }
    if (node is! WeftElement) {
      throw FormatException('Cannot encode node of type ${node.runtimeType}.');
    }
    return <String, Object?>{
      'id': node.id,
      'tag': node.tag,
      if (node.attributes.isNotEmpty)
        'attributes': <String, String>{
          for (final entry in node.attributes.entries) entry.key: entry.value,
        },
      if (node.inlineStyle.isNotEmpty)
        'style': <String, String>{
          for (final entry in node.inlineStyle.entries) entry.key: entry.value,
        },
      if (node.children.isNotEmpty)
        'children': <Object?>[
          for (final child in node.children) _encodeNode(child),
        ],
    };
  }

  static WeftNode _decodeNode(Map<String, Object?> json) {
    final id = _expectInt(json['id'], 'node id');
    final text = json['text'];
    if (text != null) {
      return WeftText(id: id, text: _expectString(text, 'node text'));
    }
    final children = <WeftNode>[
      if (json['children'] != null)
        for (final item in _expectList(json['children'], 'node children'))
          _decodeNode(_expectMap(item, 'node children[]')),
    ];
    final attributes = <String, String>{
      if (json['attributes'] != null)
        for (final entry
            in _expectMap(json['attributes'], 'node attributes').entries)
          entry.key: _expectString(entry.value, 'attribute value'),
    };
    final inlineStyle = <String, String>{
      if (json['style'] != null)
        for (final entry
            in _expectMap(json['style'], 'node inline style').entries)
          entry.key: _expectString(entry.value, 'inline style value'),
    };
    return WeftElement(
      id: id,
      tag: _expectString(json['tag'], 'node tag'),
      attributes: attributes,
      inlineStyle: inlineStyle,
      children: children,
    );
  }

  static Map<String, Object?> _encodeStyleSheet(WeftStyleSheet sheet) {
    return <String, Object?>{
      'rules': <Object?>[
        for (final rule in sheet.rules) _encodeRule(rule),
      ],
    };
  }

  static Map<String, Object?> _encodeRule(WeftStyleRule rule) {
    return <String, Object?>{
      'selectors': <Object?>[
        for (final selector in rule.selectors) _encodeSelector(selector),
      ],
      'declarations': <String, String>{
        for (final entry in rule.declarations.entries) entry.key: entry.value,
      },
      'order': rule.order,
    };
  }

  static Map<String, Object?> _encodeSelector(WeftSelector selector) {
    return <String, Object?>{
      'parts': <Object?>[
        for (final part in selector.parts) _encodeSelectorPart(part),
      ],
      if (selector.combinators.isNotEmpty)
        'combinators': <String>[
          for (final combinator in selector.combinators) combinator.name,
        ],
    };
  }

  static Map<String, Object?> _encodeSelectorPart(WeftSelectorPart part) {
    final classes = part.classes.toList()..sort();
    return <String, Object?>{
      if (part.tag != null) 'tag': part.tag!,
      if (part.id != null) 'id': part.id!,
      if (classes.isNotEmpty) 'classes': classes,
    };
  }

  static WeftStyleSheet _decodeStyleSheet(Map<String, Object?> json) {
    final rules = <WeftStyleRule>[
      for (final item in _expectList(json['rules'], 'styleSheet.rules'))
        _decodeRule(_expectMap(item, 'styleSheet.rules[]')),
    ];
    return WeftStyleSheet(rules);
  }

  static WeftStyleRule _decodeRule(Map<String, Object?> json) {
    final selectors = <WeftSelector>[
      for (final item in _expectList(json['selectors'], 'selectors'))
        _decodeSelector(_expectMap(item, 'selectors[]')),
    ];
    final declarations = <String, String>{
      for (final entry
          in _expectMap(json['declarations'], 'declarations').entries)
        entry.key: _expectString(entry.value, 'declaration value'),
    };
    return WeftStyleRule(
      selectors: selectors,
      declarations: declarations,
      order: _expectInt(json['order'], 'rule order'),
    );
  }

  static WeftSelector _decodeSelector(Map<String, Object?> json) {
    final parts = <WeftSelectorPart>[
      for (final item in _expectList(json['parts'], 'selector parts'))
        _decodeSelectorPart(_expectMap(item, 'selector parts[]')),
    ];
    final combinators = <WeftSelectorCombinator>[
      if (json['combinators'] != null)
        for (final item
            in _expectList(json['combinators'], 'selector combinators'))
          _decodeCombinator(item),
    ];
    return WeftSelector(parts: parts, combinators: combinators);
  }

  static WeftSelectorPart _decodeSelectorPart(Map<String, Object?> json) {
    return WeftSelectorPart(
      tag: json['tag'] == null ? null : _expectString(json['tag'], 'tag'),
      id: json['id'] == null ? null : _expectString(json['id'], 'selector id'),
      classes: json['classes'] == null
          ? const <String>[]
          : <String>[
              for (final item in _expectList(json['classes'], 'classes'))
                _expectString(item, 'class name'),
            ],
    );
  }

  static WeftSelectorCombinator _decodeCombinator(Object? value) {
    final name = _expectString(value, 'combinator');
    final combinator = WeftSelectorCombinator.values
        .where((item) => item.name == name)
        .firstOrNull;
    if (combinator == null) {
      throw FormatException('Unknown selector combinator "$name".');
    }
    return combinator;
  }

  static Map<String, Object?> _expectMap(Object? value, String where) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    throw FormatException('$where must be an object.');
  }

  static List<Object?> _expectList(Object? value, String where) {
    if (value is List<Object?>) return value;
    if (value is List) return List<Object?>.from(value);
    throw FormatException('$where must be an array.');
  }

  static String _expectString(Object? value, String where) {
    if (value is String) return value;
    throw FormatException('$where must be a string.');
  }

  static int _expectInt(Object? value, String where) {
    if (value is int) return value;
    throw FormatException('$where must be an integer.');
  }

  static bool _expectBool(Object? value, String where) {
    if (value is bool) return value;
    throw FormatException('$where must be a boolean.');
  }
}
