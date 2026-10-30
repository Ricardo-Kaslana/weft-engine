import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

void main() {
  test('normalizes tags, attributes, inline declarations, and links', () {
    const html = '''
      <style>
        .lead { color: #224466; }
        .article p > strong { font-weight: 700; }
      </style>
      <h1 id="hero" class="lead" onclick="bad()">Title</h1>
      <p style="color: red; position: fixed; margin: 4px 8px">
        Hello <strong>world</strong><br>
        <a href="javascript:alert(1)">bad</a>
        <a href="https://example.com/docs">good</a>
      </p>
      <unknown><span>unwrapped</span></unknown>
    ''';

    final snapshot = const WeftNormalizer().normalize(html, id: 'article');

    expect(snapshot.id, 'article');
    expect(snapshot.supportReport.canRender, isTrue);
    final body = snapshot.body;
    expect(body, isNotNull);
    expect(body?.id, 0);
    expect(
      body?.children.whereType<WeftElement>().map((node) => node.tag),
      ['h1', 'p', 'span'],
    );
    expect(snapshot.styleSheet.rules, hasLength(2));

    final elements = body!.children.whereType<WeftElement>().toList();
    final heading = elements.first;
    expect(heading.attributes.containsKey('onclick'), isFalse);
    expect(heading.attributes['class'], 'lead');

    final paragraph = elements[1];
    expect(paragraph.inlineStyle, {
      'color': 'red',
      'margin': '4px 8px',
    });
    expect(paragraph.inlineStyle.containsKey('position'), isFalse);

    final links = paragraph.children.whereType<WeftElement>().where((node) {
      return node.tag == 'a';
    }).toList();
    expect(links.first.attributes.containsKey('href'), isFalse);
    expect(links.last.attributes['href'], 'https://example.com/docs');

    expect(snapshot.normalizedHtml, isNot(contains('onclick')));
    expect(snapshot.normalizedHtml, isNot(contains('javascript:')));
    expect(snapshot.normalizedHtml, isNot(contains('position')));
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      containsAll(<String>[
        'html.tag.unknown',
        'css.property.unsupported',
        'href.scheme.blocked',
      ]),
    );
  });

  test('tail append preserves node ids throughout the unchanged prefix', () {
    final first = const WeftNormalizer().normalize(
      '<p>Hello <em>world</em></p><div>Nested <strong>text</strong></div>',
      id: 'append-ids',
    );
    final appended = const WeftNormalizer().normalize(
      '<p>Hello <em>world</em></p><div>Nested <strong>text</strong></div>'
      '<p>New tail</p>',
      id: 'append-ids',
      revision: 2,
    );

    void expectSameIds(WeftNode before, WeftNode after) {
      expect(after.id, before.id);
      if (before is! WeftElement) return;
      final afterChildren = (after as WeftElement).children;
      expect(afterChildren, hasLength(before.children.length));
      for (var i = 0; i < before.children.length; i++) {
        expectSameIds(before.children[i], afterChildren[i]);
      }
    }

    final prefix = first.body!.children;
    final next = appended.body!.children;
    expect(next, hasLength(prefix.length + 1));
    for (var i = 0; i < prefix.length; i++) {
      expectSameIds(prefix[i], next[i]);
    }
  });

  test('complex content requests an explicit fallback', () {
    const html = '''
      <p>Before</p>
      <canvas></canvas>
      <table><tr><td>Unsupported table</td></tr></table>
      <script>alert(1)</script>
    ''';

    final snapshot = const WeftNormalizer().normalize(html, id: 'fallback');

    expect(snapshot.supportReport.canRender, isFalse);
    expect(snapshot.supportReport.requiresWebView, isTrue);
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      containsAll(<String>[
        'html.tag.requiresFallback',
        'html.script.unsupported',
      ]),
    );
  });

  test('normalizes image sources and dimensions', () {
    const html = '''
      <img src="asset:assets/cover.png" alt="Cover" width="240" height="160"
           onerror="bad()">
      <img src="javascript:alert(1)" alt="Unsafe">
      <img src="cover.png" width="-4" height="12.5">
    ''';

    final snapshot = const WeftNormalizer().normalize(html, id: 'images');
    final images = snapshot.body!.children.whereType<WeftElement>().toList();

    expect(snapshot.supportReport.canRender, isTrue);
    expect(images.map((element) => element.tag), ['img', 'img', 'img']);
    expect(images.first.attributes, {
      'src': 'asset:assets/cover.png',
      'alt': 'Cover',
      'width': '240',
      'height': '160',
    });
    expect(images[1].attributes.containsKey('src'), isFalse);
    expect(images[1].attributes['alt'], 'Unsafe');
    expect(images[2].attributes['src'], 'cover.png');
    expect(images[2].attributes.containsKey('width'), isFalse);
    expect(images[2].attributes.containsKey('height'), isFalse);
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      containsAll(<String>['img.src.blocked', 'img.dimension.invalid']),
    );
  });

  test('keeps live-region and ordered-list numbering attributes', () {
    final snapshot = const WeftNormalizer().normalize(
      '<div aria-live=" POLITE "><p>Status</p></div>'
      '<ol start="5"><li>Fifth</li><li value="9">Ninth</li><li>Tenth</li></ol>'
      '<p aria-live="loud">Bad live</p>'
      '<ol start="x"><li value="y">Bad numbering</li></ol>',
      id: 'aria-and-lists',
    );

    expect(snapshot.supportReport.canRender, isTrue);
    final elements = snapshot.body!.children.whereType<WeftElement>().toList();
    final live = elements[0];
    expect(live.attributes['aria-live'], 'polite');
    final ordered = elements[1];
    expect(ordered.attribute('start'), '5');
    final items = ordered.children.whereType<WeftElement>().toList();
    expect(items.map((item) => item.attribute('value')), [null, '9', null]);
    final invalidLive = elements[2];
    expect(invalidLive.attributes.containsKey('aria-live'), isFalse);
    final invalidOrdered = elements[3];
    expect(invalidOrdered.attributes.containsKey('start'), isFalse);
    final invalidItem = invalidOrdered.children.whereType<WeftElement>().single;
    expect(invalidItem.attributes.containsKey('value'), isFalse);
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      containsAll(<String>[
        'aria.live.invalid',
        'list.start.invalid',
        'list.value.invalid',
      ]),
    );
  });

  test('node limit fails safely instead of returning partial content', () {
    const normalizer = WeftNormalizer(
      limits: WeftNormalizationLimits(maxNodes: 4),
    );

    final snapshot = normalizer.normalize(
      '<p>a</p><p>b</p><p>c</p><p>d</p>',
      id: 'limited',
    );

    expect(snapshot.supportReport.canRender, isFalse);
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      contains('html.node.limit'),
    );
  });

  test('table family is accepted with sanitized spans', () {
    final snapshot = const WeftNormalizer().normalize(
      '<table><thead><tr><th colspan="2">Head</th></tr></thead>'
      '<tbody><tr><td rowspan="0">A</td><td colspan="abc">B</td></tr>'
      '<tr><td colspan="9999">C</td></tr></tbody></table>',
      id: 'tables',
    );

    expect(snapshot.supportReport.canRender, isTrue);
    final table = snapshot.body!.children.whereType<WeftElement>().single;
    expect(table.tag, 'table');
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      containsAll(<String>['table.span.invalid', 'table.span.clamped']),
    );

    final cells = <WeftElement>[];
    void visit(WeftNode node) {
      if (node is WeftElement) {
        if (node.tag == 'td' || node.tag == 'th') cells.add(node);
        for (final child in node.children) {
          visit(child);
        }
      }
    }

    visit(table);
    expect(cells.map((cell) => cell.tag), ['th', 'td', 'td', 'td']);
    expect(cells[0].attribute('colspan'), '2');
    // rowspan="0" is not a positive span; the attribute is removed with a
    // report and the engine treats a missing span as 1.
    expect(cells[1].attribute('rowspan'), isNull);
    expect(cells[2].attribute('colspan'), isNull);
    expect(cells[3].attribute('colspan'), '1000');
  });

  test('nested tables request an explicit fallback', () {
    final snapshot = const WeftNormalizer().normalize(
      '<table><tr><td>outer'
      '<table><tr><td>inner</td></tr></table>'
      '</td></tr></table>',
      id: 'nested-table',
    );

    expect(snapshot.supportReport.canRender, isFalse);
    expect(
      snapshot.supportReport.issues.map((issue) => issue.code),
      contains('html.table.nested'),
    );
    // The inner table subtree is dropped, the outer table survives.
    final table = snapshot.body!.children.whereType<WeftElement>().single;
    expect(table.tag, 'table');
    final text = StringBuffer();
    void collectText(WeftNode node) {
      if (node is WeftText) text.write(node.text);
      if (node is WeftElement) {
        for (final child in node.children) {
          collectText(child);
        }
      }
    }

    collectText(table);
    expect(text.toString(), contains('outer'));
    expect(text.toString(), isNot(contains('inner')));
  });

  test('stray table content is foster-parented like a browser', () {
    // The HTML5 parser relocates misplaced table content before the table,
    // matching browser tree construction, so nothing is silently dropped.
    final snapshot = const WeftNormalizer().normalize(
      '<div><table><tr><td>cell</td></tr>stray text</table></div>',
      id: 'stray-table',
    );

    expect(snapshot.supportReport.canRender, isTrue);
    final children = snapshot.body!.children.whereType<WeftElement>().single;
    // The stray text is a sibling of the table, ahead of it.
    expect(children.children.first, isA<WeftText>());
    expect(
      (children.children.first as WeftText).text,
      contains('stray text'),
    );
    expect(
      children.children.whereType<WeftElement>().map((e) => e.tag),
      contains('table'),
    );
  });
}
