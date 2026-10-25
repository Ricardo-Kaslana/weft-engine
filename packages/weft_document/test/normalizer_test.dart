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
}
