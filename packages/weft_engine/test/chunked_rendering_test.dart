import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeftChunk.partition', () {
    test('groups each top-level child into one contiguous chunk', () {
      final document = _normalize(
        '<h1>Title</h1>'
            '<p>First paragraph with <em>emphasis</em> and a '
            '<a href="https://example.com/x">link</a> inside.</p>'
            '<ul><li>item one</li><li>item two</li></ul>'
            '<table><tr><td>cell a</td><td>cell b</td></tr>'
            '<tr><td colspan="2">wide cell</td></tr></table>'
            '<hr>'
            '<p>Last paragraph.</p>',
        'partition-contiguous',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 320);
      addTearDown(layout.dispose);
      final chunks = WeftChunk.partition(
        document: document,
        commands: layout.commands,
      );

      // Every command lands in exactly one chunk.
      final painted = <WeftPaintCommand>[];
      for (final chunk in chunks) {
        painted.addAll(chunk.commands);
      }
      expect(painted.length, layout.commands.length);

      // Recompute the owning top-level child independently of the
      // implementation to verify chunks cover contiguous command ranges in
      // ordinal order, which is the paint order the renderer relies on.
      final indexByCommand = <WeftPaintCommand, int>{
        for (var i = 0; i < layout.commands.length; i++) layout.commands[i]: i,
      };
      var previousLastIndex = -1;
      var previousKey = -2;
      for (final chunk in chunks) {
        final indices = chunk.commands
            .map((command) => indexByCommand[command]!)
            .toList()
          ..sort();
        if (!chunk.isChrome) {
          expect(chunk.key, greaterThan(previousKey));
          expect(indices.last - indices.first + 1, chunk.commands.length);
        }
        expect(indices.first, greaterThan(previousLastIndex));
        previousLastIndex = indices.last;
        previousKey = chunk.key;

        // The chunk bounds must fully contain every command it owns.
        for (final command in chunk.commands) {
          expect(
            _coversRect(chunk.bounds, command.bounds),
            isTrue,
            reason: 'chunk ${chunk.key} bounds ${chunk.bounds} must contain '
                'command bounds ${command.bounds}',
          );
        }
      }
      // Six children, all producing commands, in document order.
      expect(chunks.length, 6);
    });

    test('collects body chrome and loose body text into the chrome chunk', () {
      final document = _normalize(
        '<body style="background-color: #ffeecc">'
            '<p>One</p>loose text<p>Two</p>'
            '</body>',
        'partition-chrome',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 320);
      addTearDown(layout.dispose);
      final chunks = WeftChunk.partition(
        document: document,
        commands: layout.commands,
      );

      final chrome = chunks.firstWhere((chunk) => chunk.isChrome);
      final body = document.body!;
      // Body background plus the loose text node whose commands carry the
      // body node id; the two paragraphs stay in their own chunks.
      expect(chrome.commands.whereType<WeftRectPaintCommand>().length, 1);
      expect(chrome.commands.whereType<WeftTextPaintCommand>().length, 1);
      expect(
        chrome.commands.every((command) => command.nodeId == body.id),
        isTrue,
      );

      final paragraphs = chunks.where((chunk) => !chunk.isChrome).toList();
      expect(paragraphs.length, 2);
      for (final chunk in paragraphs) {
        expect(
          chunk.commands.every((command) => command.nodeId != body.id),
          isTrue,
        );
      }
    });

    test('skips children that produce no commands', () {
      final document = _normalize(
        '<p>Visible one</p>'
            '<div style="display: none"><p>Hidden</p></div>'
            '<div></div>'
            '<p>Visible two</p>',
        'partition-empty',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 320);
      addTearDown(layout.dispose);
      final chunks = WeftChunk.partition(
        document: document,
        commands: layout.commands,
      );

      final nonChrome = chunks.where((chunk) => !chunk.isChrome).toList();
      expect(nonChrome.length, 2);
      // Only the first and last children (ordinals 0 and 3) produce commands;
      // the hidden subtree and the empty div have none.
      expect(nonChrome.map((chunk) => chunk.key).toSet(), <int>{0, 3});

      final hidden = document.body!.children[1] as WeftElement;
      final hiddenIds = <int>{hidden.id};
      void visit(WeftNode node) {
        hiddenIds.add(node.id);
        if (node is WeftElement) {
          for (final child in node.children) {
            visit(child);
          }
        }
      }

      visit(hidden);
      for (final chunk in chunks) {
        expect(
          chunk.commands.any((command) => hiddenIds.contains(command.nodeId)),
          isFalse,
        );
      }
    });
  });

  test('chunked paint renders the same pixels as direct command paint',
      () async {
    final document = _normalize(
      '<h1>Paint equality</h1>'
          '<p style="background-color: #ccddff">A paragraph with a background, '
          '<em>emphasis</em> and a <a href="https://example.com/y">link</a>.</p>'
          '<div style="border: 2px solid #333344; padding: 4px">Bordered block</div>'
          '<ul><li>marker one</li><li>marker two</li></ul>'
          '<table><tr><th style="border: 1px solid #dddddd">H0</th>'
          '<th style="border: 1px solid #dddddd">H1</th></tr>'
          '<tr><td style="border: 1px solid #dddddd">a</td>'
          '<td style="border: 1px solid #dddddd">b</td></tr></table>'
          '<hr>',
      'paint-equality',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);
    final surface = RenderWeftSurface(
      document: document,
      textScaler: TextScaler.noScaling,
    );
    surface.layout(const BoxConstraints.tightFor(width: 320));
    addTearDown(surface.dispose);
    expect(layout.size.height, greaterThan(0));

    final direct = await _rasterize((canvas) {
      for (final command in layout.commands) {
        command.paint(canvas, Offset.zero);
      }
    }, layout.size);
    final chunked = await _rasterize((canvas) {
      surface.debugPaintChunks(canvas);
    }, layout.size);
    final directBytes = await direct.toByteData();
    final chunkedBytes = await chunked.toByteData();
    direct.dispose();
    chunked.dispose();
    expect(directBytes, isNotNull);
    expect(chunkedBytes, isNotNull);
    expect(
      chunkedBytes!.buffer.asUint8List(),
      directBytes!.buffer.asUint8List(),
    );
  });

  testWidgets('paints only chunks intersecting the scroll viewport', (
    tester,
  ) async {
    final buffer = StringBuffer();
    for (var i = 0; i < 40; i++) {
      buffer.write(
        '<p>Paragraph $i body text for the chunked surface scroll test.</p>',
      );
    }
    final document = _normalize(buffer.toString(), 'chunk-scroll');
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 600,
          child: SingleChildScrollView(
            controller: controller,
            child: WeftSurface(document: document),
          ),
        ),
      ),
    );

    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final totalChunks = render.debugChunks!.length;
    expect(totalChunks, 40);
    final rebuiltAfterFirstPaint = render.debugRebuiltChunkCount;
    final paintedAfterFirstPaint = render.debugPaintedChunkCount;
    // The 600px viewport shows only a fraction of the 40-paragraph document.
    expect(paintedAfterFirstPaint, greaterThan(0));
    expect(paintedAfterFirstPaint, lessThan(totalChunks));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    // Scrolling repaints a different window. Chunks entering the window are
    // built once on first sight; every chunk outside both windows is never
    // built or painted, and repeated paints never rebuild.
    final rebuiltDelta = render.debugRebuiltChunkCount - rebuiltAfterFirstPaint;
    final paintedDelta = render.debugPaintedChunkCount - paintedAfterFirstPaint;
    expect(paintedDelta, greaterThan(0));
    expect(paintedDelta, lessThan(totalChunks));
    expect(rebuiltDelta, lessThan(totalChunks));
    expect(rebuiltDelta, lessThanOrEqualTo(paintedDelta));
  });

  testWidgets('reuses cached pictures and selection rects across paints', (
    tester,
  ) async {
    final document = _normalize(
      '<p>Alpha block</p><p>Beta block</p><p>Gamma block</p>',
      'chunk-selection',
    );
    final probe = const WeftLayoutEngine().layout(document, width: 280);
    final index = probe.textIndex!;
    final selection = TextSelectionRange(
      anchor: TextAnchor(index.entries[0].nodeId, 2),
      extent: TextAnchor(index.entries[2].nodeId, 4),
    );
    probe.dispose();

    Widget wrap(TextSelectionRange? selection) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 120,
          child: WeftSurface(document: document, selection: selection),
        ),
      );
    }

    await tester.pumpWidget(wrap(selection));
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final rebuilt = render.debugRebuiltChunkCount;
    final painted = render.debugPaintedChunkCount;
    expect(render.debugSelectionRectBuildCount, 1);
    expect(
      render.debugCachedChunkPictureCount,
      render.debugChunks!.length,
    );

    // A forced repaint with unchanged inputs must hit both caches.
    render.markNeedsPaint();
    await tester.pump();
    expect(render.debugRebuiltChunkCount, rebuilt);
    expect(render.debugPaintedChunkCount, greaterThan(painted));
    expect(render.debugSelectionRectBuildCount, 1);

    // Changing the selection recomputes the rects but never the pictures.
    final changed = TextSelectionRange(
      anchor: TextAnchor(index.entries[0].nodeId, 1),
      extent: TextAnchor(index.entries[1].nodeId, 3),
    );
    await tester.pumpWidget(wrap(changed));
    expect(render.debugRebuiltChunkCount, rebuilt);
    expect(render.debugSelectionRectBuildCount, 2);
  });

  testWidgets('tail append reuses unchanged prefix pictures', (tester) async {
    final first = _normalize(
      '<p>Alpha</p><p>Beta</p><p>Gamma</p>',
      'chunk-append',
    );
    final appended = _normalize(
      '<p>Alpha</p><p>Beta</p><p>Gamma</p><p>Delta</p>',
      'chunk-append',
    );
    Widget wrap(WeftDocumentSnapshot document) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 200,
          child: WeftSurface(document: document),
        ),
      );
    }

    await tester.pumpWidget(wrap(first));
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final rebuiltForFirst = render.debugRebuiltChunkCount;
    expect(rebuiltForFirst, 3);

    await tester.pumpWidget(wrap(appended));
    expect(render.debugLayout!.debugReusedBlockCount, 3);
    expect(render.debugRebuiltChunkCount, rebuiltForFirst + 1);
    expect(render.debugCachedChunkPictureCount, 4);
  });

  testWidgets('rebuilds chunk pictures after the layout is invalidated', (
    tester,
  ) async {
    final first = _normalize('<p>First document</p>', 'chunk-rebuild-a');
    final second = _normalize(
      '<h1>Second document</h1><p>More content here.</p>',
      'chunk-rebuild-b',
    );
    Widget wrap(WeftDocumentSnapshot document) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 200,
          child: WeftSurface(document: document),
        ),
      );
    }

    await tester.pumpWidget(wrap(first));
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final rebuiltForFirst = render.debugRebuiltChunkCount;
    expect(rebuiltForFirst, greaterThan(0));

    await tester.pumpWidget(wrap(second));
    expect(render.debugRebuiltChunkCount, greaterThan(rebuiltForFirst));
    expect(
      render.debugCachedChunkPictureCount,
      render.debugChunks!.length,
    );
  });

  testWidgets('releases cached pictures on dispose without throwing', (
    tester,
  ) async {
    final document = _normalize('<p>Disposable content</p>', 'chunk-dispose');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 100,
          child: WeftSurface(document: document),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugCachedChunkPictureCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(render.debugCachedChunkPictureCount, 0);
    expect(tester.takeException(), isNull);
  });
}

/// Whether [outer] fully covers [inner]; [ui.Rect.contains] only accepts
/// points and excludes the right/bottom edges, so rect coverage needs the
/// four edge comparisons.
bool _coversRect(ui.Rect outer, ui.Rect inner) {
  return outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;
}

WeftDocumentSnapshot _normalize(String html, String id) {
  final document = const WeftNormalizer().normalize(html, id: id);
  if (!document.supportReport.canRender) {
    throw StateError(
      'Test document "$id" is not renderable: '
      '${document.supportReport.issues.map((issue) => issue.code).join(', ')}',
    );
  }
  return document;
}

Future<ui.Image> _rasterize(
  void Function(ui.Canvas canvas) paint,
  ui.Size size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  return image;
}
