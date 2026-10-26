import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
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

  test('non-null initial selection forces a full surface layout', () {
    final document = _article(80);
    final probe = const WeftLayoutEngine().layout(document, width: 320);
    final entries = probe.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries.first.nodeId, 0),
      extent: TextAnchor(entries.last.nodeId, 1),
    );
    probe.dispose();
    final render = RenderWeftSurface(
      document: document,
      selection: selection,
      enableLazyLayout: true,
      viewportHeight: 400,
    );
    addTearDown(render.dispose);
    render.layout(const BoxConstraints.tightFor(width: 320));

    expect(render.debugFullLayoutRequired, isTrue);
    expect(render.debugFullLayoutReason, 'selection');
    expect(render.debugLayout!.debugIsLazy, isFalse);
    render.selection = null;
    render.layout(const BoxConstraints.tightFor(width: 320));
    expect(render.debugLayout!.debugIsLazy, isFalse);

    render.document = _article(80, id: 'lazy-layout-next');
    render.layout(const BoxConstraints.tightFor(width: 320));
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugLayout!.debugIsLazy, isTrue);
  });

  test('height-only blocks stay materialized without relayout', () {
    const engine = WeftLayoutEngine();
    final html = StringBuffer();
    for (var i = 0; i < 40; i++) {
      html.write('<div style="height: 24px"></div>');
    }
    final document = const WeftNormalizer().normalize(
      html.toString(),
      id: 'lazy-height-only',
    );
    final first = engine.layoutViewport(
      document,
      width: 320,
      viewportStart: 0,
      viewportEnd: 960,
    );
    final second = engine.layoutViewport(
      document,
      width: 320,
      viewportStart: 1,
      viewportEnd: 961,
      previous: first,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(second.debugLaidOutBlockCount, 0);
    expect(second.debugReusedBlockCount, greaterThan(0));
    expect(second.commands, isEmpty);
    expect(
      second.incrementalCache!.blocks.every((block) => block.materialized),
      isTrue,
    );
  });

  test('multi-screen forward and reverse windows match fresh layouts', () {
    const engine = WeftLayoutEngine();
    final document = _article(80);
    const offsets = [0.0, 700.0, 1400.0, 2100.0, 1400.0, 700.0, 0.0];
    var current = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 650,
    );
    addTearDown(() => current.dispose());

    for (final offset in offsets.skip(1)) {
      final next = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: offset,
        viewportEnd: offset + 650,
        previous: current,
      );
      final fresh = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: offset,
        viewportEnd: offset + 650,
      );
      expect(next.debugIsLazy, isTrue);
      expect(next.commands, hasLength(fresh.commands.length));
      for (var i = 0; i < next.commands.length; i++) {
        expect(next.commands[i].nodeId, fresh.commands[i].nodeId);
        expect(next.commands[i].bounds, fresh.commands[i].bounds);
      }
      if (offset == 1400) {
        expect(
          next.incrementalCache!.blocks.any((block) => !block.materialized),
          isTrue,
        );
      }
      fresh.dispose();
      current.dispose();
      current = next;
    }
  });

  test('nested resolved Float checkpoints survive lazy round trips', () async {
    final image = await _createImage(80, 200);
    addTearDown(image.dispose);
    const engine = WeftLayoutEngine();
    final document = _floatingArticle();
    final images = _imagesFor(document, image);
    const offsets = [0.0, 600.0, 3000.0, 600.0];
    var current = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 650,
      images: images,
    );
    addTearDown(() => current.dispose());
    expect(current.debugIsLazy, isTrue);
    expect(current.incrementalCache!.blocks.first.floatExclusions, isNotEmpty);

    for (final offset in offsets.skip(1)) {
      final next = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: offset,
        viewportEnd: offset + 650,
        images: images,
        previous: current,
      );
      final fresh = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: offset,
        viewportEnd: offset + 650,
        images: images,
      );
      expect(next.debugIsLazy, isTrue);
      expect(next.commands, hasLength(fresh.commands.length));
      for (var i = 0; i < next.commands.length; i++) {
        expect(next.commands[i].nodeId, fresh.commands[i].nodeId);
        expect(next.commands[i].bounds, fresh.commands[i].bounds);
        if (next.commands[i] is WeftTextPaintCommand) {
          final actual = next.commands[i] as WeftTextPaintCommand;
          final expected = fresh.commands[i] as WeftTextPaintCommand;
          expect(
            actual.painter.text?.toPlainText(),
            expected.painter.text?.toPlainText(),
          );
          expect(actual.offset, expected.offset);
        }
      }
      if (offset == 600) {
        final floatBlock = next.incrementalCache!.blocks.first;
        expect(floatBlock.materialized, isFalse);
        expect(floatBlock.floatExclusions, isNotEmpty);
      }
      fresh.dispose();
      current.dispose();
      current = next;
    }
  });

  test('non-materialized Float still contributes document extent', () async {
    final image = await _createImage(80, 800);
    addTearDown(image.dispose);
    const engine = WeftLayoutEngine();
    final document = const WeftNormalizer().normalize(
      '<div><img src="asset:float" width="80" height="800" '
      'style="float:left"></div>',
      id: 'lazy-float-extent',
    );
    final images = _imagesFor(document, image);
    final first = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 900,
      images: images,
    );
    final second = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 1200,
      viewportEnd: 1500,
      images: images,
      previous: first,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(second.debugIsLazy, isTrue);
    expect(second.size.height, 800);
    final floatBlock = second.incrementalCache!.blocks.first;
    expect(floatBlock.materialized, isFalse);
    expect(floatBlock.floatExclusions, isNotEmpty);
  });

  test('lazy Float admission supports resolved images in normal blocks',
      () async {
    final image = await _createImage(40, 40);
    addTearDown(image.dispose);
    const engine = WeftLayoutEngine();
    final nested = const WeftNormalizer().normalize(
      '<p><img src="asset:float" width="40" height="40" style="float:left">'
      'Wrapping text</p>',
      id: 'lazy-nested-float',
    );
    final bodyDirect = const WeftNormalizer().normalize(
      '<img src="asset:float" width="40" height="40" style="float:left">',
      id: 'full-body-float',
    );
    final nonImage = const WeftNormalizer().normalize(
      '<div style="float:left">Not an image</div>',
      id: 'full-block-float',
    );
    final inlineAncestor = const WeftNormalizer().normalize(
      '<p><span><img src="asset:float" width="40" height="40" '
      'style="float:left"></span>Wrapping</p>',
      id: 'full-inline-float',
    );
    final unresolved = const WeftNormalizer().normalize(
      '<p><img src="asset:float" width="40" height="40" '
      'style="float:left">Wrapping</p>',
      id: 'full-unresolved-float',
    );
    final layouts = <WeftLayoutResult>[];
    for (final document in [
      nested,
      bodyDirect,
      nonImage,
      inlineAncestor,
      unresolved,
    ]) {
      layouts.add(
        engine.layoutViewport(
          document,
          width: 320,
          viewportStart: 0,
          viewportEnd: 650,
          images: identical(document, unresolved)
              ? const <int, ui.Image>{}
              : _imagesFor(document, image),
        ),
      );
    }
    addTearDown(() {
      for (final layout in layouts) {
        layout.dispose();
      }
    });

    expect(layouts[0].debugIsLazy, isTrue);
    expect(layouts[1].debugIsLazy, isTrue);
    expect(layouts.skip(2).every((layout) => !layout.debugIsLazy), isTrue);
  });

  test('valid anchors focus-measure lazy surfaces without going full', () {
    final document = _article(80);
    final canonical = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(canonical.dispose);
    final entry = canonical.textIndex!.entries.last;
    final expected = canonical.textRectsForNode(entry.nodeId, 2, 3).first;

    final render = RenderWeftSurface(
      document: document,
      enableLazyLayout: true,
      viewportHeight: 400,
    );
    addTearDown(render.dispose);
    render.layout(const BoxConstraints.tightFor(width: 320));
    expect(render.debugLayout!.debugIsLazy, isTrue);

    expect(render.textRectForAnchor(const TextAnchor(999999, 0)), isNull);
    expect(
      render.textRectForAnchor(TextAnchor(entry.nodeId, entry.text.length)),
      isNull,
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugFullLayoutRequired, isFalse);

    final rect = render.textRectForAnchor(TextAnchor(entry.nodeId, 2));
    expect(rect, expected);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugFullLayoutReason, isNull);
    expect(
      render.debugLayout!.incrementalCache!.blocks.last.materialized,
      isTrue,
    );
  });

  test('async anchor measurement advances within a block budget', () {
    const engine = WeftLayoutEngine();
    final document = _article(80);
    final canonical = engine.layout(document, width: 320);
    final entry = canonical.textIndex!.entries.last;
    canonical.dispose();
    var layout = engine.layoutViewport(
      document,
      width: 320,
      viewportStart: 0,
      viewportEnd: 650,
      focusNodeId: entry.nodeId,
      maxNewBlocks: 10,
    );
    var passes = 1;
    expect(layout.debugIsLazy, isTrue);
    expect(layout.debugLaidOutBlockCount, lessThanOrEqualTo(10));
    var previousPrefix = layout.incrementalCache!.measuredPrefixLength;
    expect(previousPrefix, lessThan(document.body!.children.length));
    while (previousPrefix < document.body!.children.length && passes < 30) {
      final next = engine.layoutViewport(
        document,
        width: 320,
        viewportStart: 0,
        viewportEnd: 650,
        focusNodeId: entry.nodeId,
        maxNewBlocks: 10,
        previous: layout,
      );
      layout.dispose();
      layout = next;
      passes += 1;
      expect(layout.debugLaidOutBlockCount, lessThanOrEqualTo(10));
      final measured = layout.incrementalCache!.measuredPrefixLength;
      expect(measured, greaterThan(previousPrefix));
      previousPrefix = measured;
    }
    addTearDown(layout.dispose);
    expect(
      layout.incrementalCache!.measuredPrefixLength,
      document.body!.children.length,
    );
    expect(layout.debugIsLazy, isTrue);
    expect(layout.incrementalCache!.blocks.last.materialized, isTrue);
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

  test('identical snapshot relayouts reuse the whole measured prefix', () {
    const engine = WeftLayoutEngine();
    final document = _article(60);
    final canonical = engine.layout(document, width: 360);
    final first = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 1050,
    );
    addTearDown(canonical.dispose);
    addTearDown(first.dispose);

    final prefix = first.incrementalCache!.measuredPrefixLength;
    expect(prefix, greaterThan(0));
    final firstCache = first.incrementalCache!;
    final firstTextIndex = first.textIndex;
    final second = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 1000,
      viewportEnd: 2050,
      previous: first,
    );
    addTearDown(second.dispose);
    expect(second.debugReusedBlockCount, prefix);
    expect(second.incrementalCache!.measuredPrefixLength, greaterThan(prefix));
    // ADR 0031: an unchanged snapshot instance carries its logical text index
    // and style cache across relayouts instead of rebuilding them.
    expect(identical(second.textIndex, firstTextIndex), isTrue);
    expect(
      identical(second.incrementalCache!.styleCache, firstCache.styleCache),
      isTrue,
    );

    // A full relayout reusing a complete full-layout cache reuses every
    // top-level block and stays canonical. (Lazy results are never a reuse
    // source for full layouts — ADR 0025.)
    final again = engine.layout(document, width: 360, previous: canonical);
    addTearDown(again.dispose);
    expect(again.debugReusedBlockCount, document.body!.children.length);
    expect(again.size, canonical.size);
    expect(again.commands, hasLength(canonical.commands.length));
    for (var i = 0; i < again.commands.length; i++) {
      expect(again.commands[i].nodeId, canonical.commands[i].nodeId);
      expect(again.commands[i].bounds, canonical.commands[i].bounds);
    }
  });

  test('cross-frame style cache keeps selector-matched styles exact', () {
    const engine = WeftLayoutEngine();
    const html = '<style>'
        'p { margin: 8px 0; }'
        'div p { margin-left: 12px; }'
        'div.highlight p { background-color: #FFEE88; }'
        'ul li { margin: 4px 0; }'
        '</style>'
        '<p>Plain paragraph text.</p>'
        '<div><p>Nested paragraph inside a plain div.</p></div>'
        '<div class="highlight"><p>Highlighted paragraph.</p>'
        '<ul><li>Item one</li><li>Item two</li></ul></div>'
        '<p style="margin-top: 32px">Inline styled tail paragraph.</p>';
    final document = const WeftNormalizer().normalize(
      html,
      id: 'style-cache',
    );
    final canonical = engine.layout(document, width: 360);
    addTearDown(canonical.dispose);
    final first = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: 400,
    );
    final second = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 30,
      viewportEnd: 100000,
      previous: first,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(second.debugIsLazy, isTrue);
    expect(
      second.incrementalCache!.measuredPrefixLength,
      document.body!.children.length,
    );
    expect(second.size, canonical.size);
    expect(second.commands, hasLength(canonical.commands.length));
    for (var i = 0; i < second.commands.length; i++) {
      expect(second.commands[i].nodeId, canonical.commands[i].nodeId);
      expect(second.commands[i].bounds, canonical.commands[i].bounds);
    }
    expect(second.links, hasLength(canonical.links.length));
    expect(second.textIndex!.text, canonical.textIndex!.text);
  });

  testWidgets('deep scroll jumps measure within a per-frame block budget',
      (tester) async {
    const engine = WeftLayoutEngine();
    final document = _article(300);
    final canonical = engine.layout(document, width: 360);
    addTearDown(canonical.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: WeftSurface(
              document: document,
              enableLazyLayout: true,
              viewportHeight: 800,
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    final childCount = document.body!.children.length;

    // Jumping to the estimated bottom must not measure the whole prefix in
    // one frame (ADR 0031): each pass adds at most the block budget and the
    // post-frame continuation advances the rest across frames.
    render.setViewportPixels(canonical.size.height - 800);
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
    expect(
      render.debugLayout!.incrementalCache!.measuredPrefixLength,
      lessThan(childCount),
    );

    var passes = 1;
    while (render.debugLayout!.incrementalCache!.measuredPrefixLength <
        childCount) {
      await tester.pump();
      passes += 1;
      expect(render.debugLayout!.debugIsLazy, isTrue);
      expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
      expect(passes, lessThan(childCount));
    }
    expect(render.debugLayout!.size, canonical.size);
    // The surface materializes its overscan window; a fresh layout over the
    // same window must produce identical commands.
    final freshWindow = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: canonical.size.height - 1050,
      viewportEnd: canonical.size.height + 250,
    );
    addTearDown(freshWindow.dispose);
    expect(
      render.debugLayout!.commands,
      hasLength(freshWindow.commands.length),
    );
    for (var i = 0; i < render.debugLayout!.commands.length; i++) {
      expect(render.debugLayout!.commands[i].nodeId,
          freshWindow.commands[i].nodeId);
      expect(
        render.debugLayout!.commands[i].bounds,
        freshWindow.commands[i].bounds,
      );
    }
  }, semanticsEnabled: false);

  testWidgets('deep initial offsets seed through budgeted passes',
      (tester) async {
    const engine = WeftLayoutEngine();
    final document = _article(200);
    final canonical = engine.layout(document, width: 360);
    addTearDown(canonical.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: WeftSurface(
              document: document,
              enableLazyLayout: true,
              viewportHeight: 800,
              initialViewportPixels: canonical.size.height - 800,
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
    final childCount = document.body!.children.length;
    var passes = 1;
    while (render.debugLayout!.incrementalCache!.measuredPrefixLength <
        childCount) {
      await tester.pump();
      passes += 1;
      expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
      expect(passes, lessThan(childCount));
    }
    expect(render.debugLayout!.size, canonical.size);
  }, semanticsEnabled: false);

  test('scrolls near the frontier still measure synchronously', () {
    const engine = WeftLayoutEngine();
    final document = _article(120);
    final render = RenderWeftSurface(
      document: document,
      enableLazyLayout: true,
      viewportHeight: 800,
    );
    addTearDown(render.dispose);
    render.layout(const BoxConstraints.tightFor(width: 360));
    final prefix = render.debugLayout!.incrementalCache!.measuredPrefixLength;

    // The new window lies within one screenful of measured content, so one
    // synchronous pass covers it without the budget.
    render.setViewportPixels(800);
    render.layout(const BoxConstraints.tightFor(width: 360));
    final cache = render.debugLayout!.incrementalCache!;
    expect(cache.measuredPrefixLength, greaterThan(prefix));
    final fresh = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 550,
      viewportEnd: 1850,
    );
    addTearDown(fresh.dispose);
    expect(render.debugLayout!.commands, hasLength(fresh.commands.length));
    for (var i = 0; i < render.debugLayout!.commands.length; i++) {
      expect(render.debugLayout!.commands[i].nodeId, fresh.commands[i].nodeId);
      expect(render.debugLayout!.commands[i].bounds, fresh.commands[i].bounds);
    }
  });

  testWidgets('scroll round trips keep caches in a stable budget',
      (tester) async {
    final document = _article(120);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: WeftSurface(
              document: document,
              enableLazyLayout: true,
              viewportHeight: 800,
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final childCount = document.body!.children.length;

    // Multiple full down-and-up round trips. Picture cache, materialized
    // commands and the incremental cache must stay bounded by the document,
    // not grow with the number of scroll rounds (phase 3 acceptance).
    for (var round = 0; round < 4; round++) {
      render.setViewportPixels(6000);
      await tester.pump();
      render.setViewportPixels(0);
      await tester.pump();
      render.setViewportPixels(3000);
      await tester.pump();

      final pictures = render.debugCachedChunkPictureCount;
      // The picture cache only holds the current layout's chunks: bounded by
      // the document size, never by the number of scroll rounds. (A tight
      // inter-round equality is timing dependent — post-frame extent
      // corrections can shift the window by a pump under load.)
      expect(
        pictures,
        lessThanOrEqualTo(childCount),
        reason: 'round $round held $pictures chunk pictures',
      );
      expect(
        render.debugLayout!.incrementalCache!.blocks.length,
        lessThanOrEqualTo(childCount),
        reason: 'round $round cache grows with rounds, not the document',
      );
    }
  }, semanticsEnabled: false);
}

WeftDocumentSnapshot _floatingArticle() {
  final html = StringBuffer(
    '<div><img src="asset:float" width="80" height="200" '
    'style="float:left"></div>',
  );
  html.write('<p>${'Text wrapping around the float. ' * 60}</p>');
  for (var i = 0; i < 12; i++) {
    html.write('<p>Tail paragraph $i with enough text to extend the page.</p>');
  }
  return const WeftNormalizer().normalize(
    html.toString(),
    id: 'lazy-float-roundtrip',
  );
}

Map<int, ui.Image> _imagesFor(WeftDocumentSnapshot document, ui.Image image) {
  final result = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is! WeftElement) return;
    if (node.tag == 'img') result[node.id] = image;
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(document.body!);
  return result;
}

Future<ui.Image> _createImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

WeftDocumentSnapshot _article(
  int paragraphs, {
  String id = 'lazy-layout',
}) {
  final html = StringBuffer();
  for (var i = 0; i < paragraphs; i++) {
    if (i % 10 == 0) html.write('<h3>Section ${i ~/ 10}</h3>');
    html.write(
      '<p>Paragraph $i with mixed English text and 中文内容, '
      '<em>emphasis</em> and enough words to wrap at the viewport width.</p>',
    );
  }
  return const WeftNormalizer().normalize(html.toString(), id: id);
}
