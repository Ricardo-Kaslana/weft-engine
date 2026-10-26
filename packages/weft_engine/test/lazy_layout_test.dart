import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first viewport measures only a continuous prefix', () {
    const engine = WeftLayoutEngine();
    final document = _article(300);
    final canonical = engine.layout(document, width: 360);
    final lazy = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 1050,
    );
    addTearDown(canonical.dispose);
    addTearDown(lazy.dispose);

    expect(lazy.debugIsLazy, isTrue);
    expect(lazy.debugLaidOutBlockCount, lessThan(300));
    expect(lazy.debugMaterializedBlockCount, lessThan(300));
    expect(lazy.incrementalCache!.measuredPrefixLength, lessThan(300));
    expect(lazy.commands.length, lessThan(canonical.commands.length));
    expect(lazy.incrementalCache!.estimatedExtent, lazy.size.height);
    for (var i = 0; i < lazy.commands.length; i++) {
      expect(lazy.commands[i].nodeId, canonical.commands[i].nodeId);
      expect(lazy.commands[i].bounds, canonical.commands[i].bounds);
    }
  });

  test('cold jump measures intermediate blocks and converges to full height',
      () {
    const engine = WeftLayoutEngine();
    final document = _article(80);
    final canonical = engine.layout(document, width: 360);
    final first = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 1050,
    );
    final bottom = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: canonical.size.height - 800,
      viewportEnd: canonical.size.height,
      previous: first,
    );
    addTearDown(canonical.dispose);
    addTearDown(first.dispose);
    addTearDown(bottom.dispose);

    expect(bottom.size, canonical.size);
    expect(bottom.incrementalCache!.measuredPrefixLength, 88);
    expect(bottom.debugMaterializedBlockCount, lessThan(88));
    expect(bottom.commands, isNotEmpty);
    final canonicalBottomCommands = canonical.commands.where((command) {
      return command.bounds.bottom >= canonical.size.height - 800;
    }).toList();
    expect(bottom.commands.length, canonicalBottomCommands.length);
    for (var i = 0; i < bottom.commands.length; i++) {
      expect(bottom.commands[i].nodeId, canonicalBottomCommands[i].nodeId);
      expect(bottom.commands[i].bounds, canonicalBottomCommands[i].bounds);
    }
  });
  test('fully measured lazy layout matches canonical margins lists and tables',
      () {
    const engine = WeftLayoutEngine();
    final html = StringBuffer();
    for (var i = 0; i < 8; i++) {
      html.write(
        '<h3>Section $i</h3>'
        '<ul><li>First item $i</li><li>Second item $i</li></ul>'
        '<table><tr><td style="border:1px solid #333">Cell $i</td>'
        '<td style="border:1px solid #333">Value $i</td></tr></table>'
        '<p style="margin: 12px 0">Body $i</p>',
      );
    }
    final document = const WeftNormalizer().normalize(
      html.toString(),
      id: 'lazy-structured',
    );
    final canonical = engine.layout(document, width: 360);
    final lazy = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 100000,
    );
    addTearDown(canonical.dispose);
    addTearDown(lazy.dispose);

    expect(lazy.debugIsLazy, isTrue);
    expect(lazy.size, canonical.size);
    expect(lazy.commands, hasLength(canonical.commands.length));
    for (var i = 0; i < lazy.commands.length; i++) {
      expect(lazy.commands[i].nodeId, canonical.commands[i].nodeId);
      expect(lazy.commands[i].bounds, canonical.commands[i].bounds);
    }
    expect(
      lazy.incrementalCache!.measuredPrefixLength,
      document.body!.children.length,
    );
  });

  test('surface enables lazy layout when a viewport is supplied', () {
    final render = RenderWeftSurface(
      document: _article(120),
      enableLazyLayout: true,
      viewportHeight: 400,
    );
    addTearDown(render.dispose);
    render.layout(const BoxConstraints.tightFor(width: 320));
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThan(120));
  });
}

WeftDocumentSnapshot _article(int paragraphs) {
  final html = StringBuffer();
  for (var i = 0; i < paragraphs; i++) {
    if (i % 10 == 0) html.write('<h3>Section ${i ~/ 10}</h3>');
    html.write(
      '<p>Paragraph $i with mixed English text and 中文内容, '
      '<em>emphasis</em> and enough words to wrap at the viewport width.</p>',
    );
  }
  return const WeftNormalizer().normalize(html.toString(), id: 'lazy-layout');
}
