import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

void main() {
  group('WeftDocumentJson round trip', () {
    test('empty snapshot encodes and decodes', () {
      const snapshot = WeftDocumentSnapshot.empty;
      final encoded = WeftDocumentJson.encodeToString(snapshot);
      final decoded = WeftDocumentJson.decodeFromString(encoded);

      expect(WeftDocumentJson.encodeToString(decoded), encoded);
      expect(decoded.id, 'empty');
      expect(decoded.revision, 0);
      expect(decoded.body, isNull);
      expect(decoded.supportReport.issues, isEmpty);
      expect(decoded.styleSheet.rules, isEmpty);
    });

    test('full snapshot round trips content exactly', () {
      final snapshot = const WeftNormalizer().normalize('''
<!doctype html>
<html>
<head><style>
  p.doc { color: red; margin: 4px 8px; }
  #lead, .note span { font-weight: bold; }
</style></head>
<body>
  <p class="doc" style="color: blue">Hello <strong>weft</strong>!你好</p>
  <img src="https://example.com/a.png" alt="a" width="32">
  <!-- comment -->
  <weft-badge data-label="New"></weft-badge>
</body>
</html>
''', id: 'round-trip', revision: 7);

      final encoded = WeftDocumentJson.encodeToString(snapshot);
      final decoded = WeftDocumentJson.decodeFromString(encoded);

      expect(WeftDocumentJson.encodeToString(decoded), encoded);
      expect(decoded.id, 'round-trip');
      expect(decoded.revision, 7);
      expect(decoded.normalizedHtml, snapshot.normalizedHtml);

      final body = decoded.body!;
      expect(body.tag, 'body');
      final paragraphs = body.children.whereType<WeftElement>().toList();
      expect(paragraphs.first.tag, 'p');
      expect(paragraphs.first.inlineStyle, isNotEmpty);
      // Unknown tags are unwrapped; their text survives normalization.
      expect(paragraphs.any((node) => node.tag == 'strong'), isFalse);

      final rules = decoded.styleSheet.rules;
      expect(rules, isNotEmpty);
      final firstRule = rules.first;
      expect(firstRule.selectors.first.parts.first.classes, {'doc'});
      expect(firstRule.declarations['color'], 'red');
      expect(firstRule.order, 0);

      // A descendant selector decodes back into parts + combinators.
      final descendant = rules
          .expand((rule) => rule.selectors)
          .firstWhere((selector) => selector.combinators.isNotEmpty);
      expect(descendant.combinators, [WeftSelectorCombinator.descendant]);
      expect(descendant.parts, hasLength(2));
    });

    test('diagnostics round trip with severity and webview flag', () {
      final snapshot = const WeftNormalizer().normalize(
        '<body><table><tr><td><table><tr><td>x</td></tr></table></td></tr></table></body>',
        id: 'nested',
      );
      expect(snapshot.supportReport.requiresWebView, isTrue);

      final decoded = WeftDocumentJson.decodeFromString(
        WeftDocumentJson.encodeToString(snapshot),
      );
      expect(decoded.supportReport.requiresWebView, isTrue);
      expect(
        decoded.supportReport.issues
            .where((issue) => issue.code == 'html.table.nested'),
        isNotEmpty,
      );
      final flagged = decoded.supportReport.issues
          .firstWhere((issue) => issue.code == 'html.table.nested');
      expect(flagged.severity, SupportSeverity.warning);
      expect(flagged.requiresWebView, isTrue);
    });

    test('encoding is deterministic for identical snapshots', () {
      const html = '<body><h1>Tit</h1><p>Text 中文</p></body>';
      final a = WeftDocumentJson.encodeToString(
        const WeftNormalizer().normalize(html, id: 'd', revision: 3),
      );
      final b = WeftDocumentJson.encodeToString(
        const WeftNormalizer().normalize(html, id: 'd', revision: 3),
      );
      expect(a, b);
    });

    test('selector class sets encode sorted for stability', () {
      final snapshot = const WeftNormalizer().normalize(
        '<head><style>.mu.alpha.zeta { color: red; }</style></head>'
        '<body><p class="zeta alpha mu">x</p></body>',
        id: 'sorted',
      );
      final encoded = WeftDocumentJson.encodeToString(snapshot);
      final decoded = WeftDocumentJson.decodeFromString(encoded);
      final secondEncode = WeftDocumentJson.encodeToString(decoded);
      expect(secondEncode, encoded);
      final rule = decoded.styleSheet.rules.single;
      expect(
          rule.selectors.single.parts.single.classes, {'alpha', 'mu', 'zeta'});
    });
  });

  group('WeftDocumentJson version gate', () {
    Map<String, Object?> reversion(
      WeftDocumentSnapshot snapshot,
      int version,
    ) {
      final json = WeftDocumentJson.encode(snapshot);
      json['version'] = version;
      return json;
    }

    test('newer version is rejected with a forward-compat error', () {
      final json = reversion(WeftDocumentSnapshot.empty, 2);
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('newer than this engine supports'),
          ),
        ),
      );
    });

    test('older version is rejected instead of misread', () {
      final json = reversion(WeftDocumentSnapshot.empty, 0);
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-weft format is rejected', () {
      expect(
        () => WeftDocumentJson.decode(<String, Object?>{
          'format': 'other.document',
          'version': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing version is rejected', () {
      final json = WeftDocumentJson.encode(WeftDocumentSnapshot.empty)
        ..remove('version');
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('WeftDocumentJson malformed input', () {
    test('wrong field types throw with the field name', () {
      final json = WeftDocumentJson.encode(WeftDocumentSnapshot.empty)
        ..['revision'] = 'one';
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(
          isA<FormatException>().having(
              (error) => error.message, 'message', contains('revision')),
        ),
      );
    });

    test('unknown severity throws', () {
      final json = WeftDocumentJson.encode(WeftDocumentSnapshot.empty)
        ..['supportReport'] = <String, Object?>{
          'issues': <Object?>[
            <String, Object?>{
              'code': 'x',
              'message': 'y',
              'severity': 'fatal',
              'requiresWebView': false,
            },
          ],
        };
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('attribute values must be strings', () {
      final json = WeftDocumentJson.encode(WeftDocumentSnapshot.empty)
        ..['body'] = <String, Object?>{
          'id': 0,
          'tag': 'body',
          'attributes': <String, Object?>{'class': 3},
        };
      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
