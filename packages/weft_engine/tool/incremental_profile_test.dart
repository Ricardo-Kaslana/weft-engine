// Incremental layout profiling driver. It decomposes the remaining
// O(block count) streaming-update costs (ADR 0023's leftover list: snapshot
// diff, style resolution, list merging, text index rebuild), measures the
// streaming update shapes hosts actually emit, and prices the Float /
// mid-edit capability gaps, so the next optimization direction is chosen on
// data (docs/adr/0043).
//
//   cd packages/weft_engine
//   flutter test tool/incremental_profile_test.dart --no-pub
//
// Host Stopwatch timings include harness costs, not device FrameTiming
// budgets: use them for relative comparison between components and shapes
// only. Device budgets need the profile-build FrameTiming flow from
// docs/device-matrix.md.
//
// The style resolver imports reach into `src/` on purpose: this is a
// same-package tool measuring the engine's real selector-matching path,
// which the public exports do not expose.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';
import 'package:weft_engine/src/computed_style.dart';
import 'package:weft_engine/src/style_resolver.dart';

const double _viewportWidth = 360;
const double _viewportHeight = 800;
const int _sampleCount = 5;
const int _streamWarmupRounds = 3;
const int _streamRounds = 6;
const int _streamAppendPerRound = 10;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  test(
    'incremental profile: streaming cost decomposition (E0)',
    () {
      _profileDecomposition(engine);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'incremental profile: streaming update shapes (E1)',
    () {
      _profileStreamingShapes(engine);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'incremental profile: float path costs (E3)',
    () async {
      await _profileFloatCosts(engine);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// E0: decompose one plain-host streaming round into text index, style
/// resolution, snapshot diff and reuse-walk shares at three scales.
///
/// The decomposition is differential: a new-snapshot relayout of unchanged
/// content pays diff + text index + style resolution + reuse walk, the
/// same-snapshot floor pays only the walk, and text index / style / diff are
/// each measured directly through public (or same-package) entry points. The
/// residual — the part of the round not covered by the four components — is
/// printed so the identity can be checked instead of assumed.
///
/// Since ADR 0044 the new-snapshot round itself reuses the text index
/// prefix, so `newSnapshotMs` no longer contains the full-build
/// `textIndexMs`; the round should instead be close to floorMs +
/// styleResolveMs (the walk's own resolve-all) + a suffix-only index build.
/// The identity reading applies to fallback rounds only.
void _profileDecomposition(WeftLayoutEngine engine) {
  for (final n in const [300, 1000, 2000]) {
    final html = _articleHtml(n);
    final docA = _normalize(html, 'profile-decomp-$n');
    final docB = _normalize(html, 'profile-decomp-$n');
    final children = docA.body!.children.length;
    expect(docB.body!.children.length, children);

    final coldMs = _medianMs(
      () => engine.layout(docA, width: _viewportWidth).dispose(),
    );
    // Same-snapshot relayout: the diff, style cache and text index are all
    // skipped, leaving the reuse walk and bookkeeping.
    final floorMs = _relayoutMs(engine, docA, docA, children);
    // New snapshot with byte-identical content: full diff + style + index.
    final newSnapshotMs = _relayoutMs(engine, docA, docB, children);

    final resolver = WeftStyleResolver(docA.styleSheet);
    final textIndexMs = _medianMs(
      () => WeftTextIndex.build(document: docA, styleResolver: resolver),
    );
    final styleMs = _medianMs(() => _styleResolveAll(docA, resolver));
    final diffProxyMs = _medianMs(() => _sameNodeProxy(docA.body!, docB.body!));

    final residualMs = newSnapshotMs - textIndexMs - styleMs - floorMs;
    final coveredMs = textIndexMs + styleMs + diffProxyMs + floorMs;
    _profileLine(
      'e0 n=$n children=$children coldMs=${_f(coldMs)} '
      'floorMs=${_f(floorMs)} newSnapshotMs=${_f(newSnapshotMs)} '
      'textIndexMs=${_f(textIndexMs)} styleResolveMs=${_f(styleMs)} '
      'diffProxyMs=${_f(diffProxyMs)} residualMs=${_f(residualMs)} '
      'perBlockUs=${_f(newSnapshotMs * 1000 / children)} '
      'identityCoverage=${_f(100 * coveredMs / newSnapshotMs)}%',
    );
  }
}

/// E1: per-round cost of the streaming shapes hosts emit, on plain and lazy
/// surfaces, against a cold relayout of the same final document.
void _profileStreamingShapes(WeftLayoutEngine engine) {
  for (final base in const [300, 1000]) {
    _runStreamingShape(
      engine: engine,
      shape: 'tail-append',
      host: 'plain',
      base: base,
      htmlFor: (round) =>
          _plainArticleHtml(base + round * _streamAppendPerRound),
      expectedReused: (_, previousChildren) => previousChildren,
    );
    _runStreamingShape(
      engine: engine,
      shape: 'tail-growth',
      host: 'plain',
      base: base,
      htmlFor: (round) => _plainArticleHtml(
        base,
        paragraphFor: (i) => i == base - 1 ? _growingTail(i, round) : null,
      ),
      expectedReused: (_, previousChildren) => previousChildren - 1,
    );
    _runStreamingShape(
      engine: engine,
      shape: 'mid-edit',
      host: 'plain',
      base: base,
      htmlFor: (round) => _plainArticleHtml(
        base,
        paragraphFor: (i) => i == base ~/ 2 ? _editedParagraph(i, round) : null,
      ),
      // ADR 0046: everything but the edited block comes back — prefix up
      // to the edit, shifted suffix after it.
      expectedReused: (_, previousChildren) => previousChildren - 1,
    );
    if (base == 300) {
      _runStreamingShape(
        engine: engine,
        shape: 'head-insert',
        host: 'plain',
        base: base,
        htmlFor: (round) =>
            '<p>置顶快讯第 $round 轮。Weft streaming prepends a fresh block '
            'above unchanged content, so the first top-level block already '
            'differs.</p>${_plainArticleHtml(base)}',
        // ADR 0046: every previous block returns as the shifted suffix
        // except the per-round top paragraph, whose text differs each round.
        expectedReused: (_, previousChildren) => previousChildren - 1,
      );
    }
    _runStreamingShape(
      engine: engine,
      shape: 'tail-append',
      host: 'lazy',
      base: base,
      htmlFor: (round) =>
          _plainArticleHtml(base + round * _streamAppendPerRound),
      expectedReused: null,
      expectLazy: true,
    );
  }
}

/// E3: what Float costs today — the plain host cannot even seed an
/// incremental cache for a float document, the lazy host streams through
/// re-admission every round, and the per-line wrapping path shapes the
/// remaining text once per line.
Future<void> _profileFloatCosts(WeftLayoutEngine engine) async {
  final floatImage = await _createImage(48, 48, const Color(0xFF3366CC));
  addTearDown(floatImage.dispose);
  const lead = _floatLeadParagraph;

  // Plain host: the float document never seeds an incremental cache, so
  // every streaming round is a cold relayout of the whole document.
  final plainHtml = '${lead()}${_articleHtml(300)}';
  final plainDoc = _normalize(plainHtml, 'profile-float-plain');
  final plainImages = _imagesFor(plainDoc, floatImage);
  final plainInitial = engine.layout(
    plainDoc,
    width: _viewportWidth,
    images: plainImages,
  );
  _profileLine(
    'e3 float-plain initial isLazy=${plainInitial.debugIsLazy} '
    'cacheSeeded=${plainInitial.incrementalCache != null} '
    'children=${plainDoc.body!.children.length} '
    'commands=${plainInitial.commands.length}',
  );
  expect(plainInitial.debugIsLazy, isFalse);
  expect(plainInitial.incrementalCache, isNull);
  var current = plainInitial;
  final plainRoundMs = <double>[];
  for (var round = 1; round <= _streamWarmupRounds + _streamRounds; round++) {
    final document = _normalize(
      '${lead()}${_articleHtml(300 + round * _streamAppendPerRound)}',
      'profile-float-plain',
    );
    final watch = Stopwatch()..start();
    final next = engine.layout(
      document,
      width: _viewportWidth,
      images: plainImages,
    );
    watch.stop();
    current.dispose();
    current = next;
    if (round > _streamWarmupRounds) {
      expect(next.incrementalCache, isNull);
      expect(next.debugReusedBlockCount, 0);
      plainRoundMs.add(watch.elapsedMicroseconds / 1000.0);
      _profileLine(
        'e3 float-plain round=$round ms=${_f(watch.elapsedMicroseconds / 1000.0)} '
        'children=${document.body!.children.length} '
        'reused=${next.debugReusedBlockCount} cacheSeeded=false',
      );
    }
  }
  current.dispose();
  _profileLine(
    'e3 float-plain summary rounds=${plainRoundMs.length} '
    'median=${_f(_medianOf(plainRoundMs))}ms',
  );

  // Lazy host: image floats stay lazy-eligible, but every round pays the
  // full-tree admission walk again because the snapshot instance changed.
  WeftLayoutResult? lazyCurrent;
  final lazyRoundMs = <double>[];
  final lazyReused = <int>[];
  final lazyEstimated = <int>[];
  final lazyEligibility = <int>[];
  for (var round = 0; round <= _streamWarmupRounds + _streamRounds; round++) {
    final document = _normalize(
      '${lead()}${_articleHtml(300 + round * _streamAppendPerRound)}',
      'profile-float-lazy',
    );
    final watch = Stopwatch()..start();
    final next = engine.layoutViewport(
      document,
      width: _viewportWidth,
      viewportStart: 0,
      viewportEnd: _viewportHeight,
      images: _imagesFor(document, floatImage),
      previous: lazyCurrent,
    );
    watch.stop();
    lazyCurrent?.dispose();
    lazyCurrent = next;
    expect(next.debugIsLazy, isTrue);
    if (round > _streamWarmupRounds) {
      lazyRoundMs.add(watch.elapsedMicroseconds / 1000.0);
      lazyReused.add(next.debugReusedBlockCount);
      lazyEstimated.add(next.debugEstimatedBlockCount);
      lazyEligibility.add(next.debugEligibilityVisitCount);
      _profileLine(
        'e3 float-lazy round=$round ms=${_f(watch.elapsedMicroseconds / 1000.0)} '
        'children=${document.body!.children.length} '
        'reused=${next.debugReusedBlockCount} '
        'estimated=${next.debugEstimatedBlockCount} '
        'eligibility=${next.debugEligibilityVisitCount} '
        'cacheSeeded=${next.incrementalCache != null}',
      );
    }
  }
  lazyCurrent?.dispose();
  _profileLine(
    'e3 float-lazy summary rounds=${lazyRoundMs.length} '
    'median=${_f(_medianOf(lazyRoundMs))}ms '
    'reusedRange=${lazyReused.first}..${lazyReused.last} '
    'estimatedRange=${lazyEstimated.first}..${lazyEstimated.last} '
    'eligibilityRange=${lazyEligibility.first}..${lazyEligibility.last}',
  );

  // Per-line wrapping scale: one float + one long CJK paragraph. The probe
  // painter re-shapes all remaining text once per line, so cost should grow
  // superlinearly with paragraph length; the control paragraph takes the
  // whole-paragraph path.
  for (final chars in const [1000, 2000, 4000, 8000]) {
    final filler = _cjkFiller(chars);
    final floatDoc = _normalize(
      '${lead()}<p>$filler</p>',
      'profile-linewrap-float-$chars',
    );
    final plainDoc =
        _normalize('<p>$filler</p>', 'profile-linewrap-plain-$chars');
    final floatImages = _imagesFor(floatDoc, floatImage);
    final floatMs = _medianMs(
      () => engine
          .layout(floatDoc, width: _viewportWidth, images: floatImages)
          .dispose(),
      samples: 3,
    );
    final plainMs = _medianMs(
      () => engine.layout(plainDoc, width: _viewportWidth).dispose(),
      samples: 3,
    );
    final probe =
        engine.layout(floatDoc, width: _viewportWidth, images: floatImages);
    final commands = probe.commands.length;
    probe.dispose();
    _profileLine(
      'e3 linewrap chars=$chars floatMs=${_f(floatMs)} '
      'plainMs=${_f(plainMs)} ratio=${_f(floatMs / plainMs)} '
      'commands=$commands',
    );
  }
}

String _floatLeadParagraph() {
  return '<p><img src="asset:profile-float.png" style="float:left" '
      'width="48" height="48">首段浮图锚定。Weft floats the image so every '
      'following paragraph takes the per-line wrapping path.</p>';
}

String _growingTail(int index, int round) {
  return '<p>第 $index 段。Weft engine lays out mixed English and 中文内容 '
      'at a fixed 360px viewport, exercising line breaking '
      'deterministically.${_cjkFiller(120 + 120 * round)}'
      '流式正文在第 $round 轮增长。</p>';
}

String _editedParagraph(int index, int round) {
  return '<p>第 $index 段（第 $round 轮被编辑）。Weft engine relayouts from '
      'the first changed block through the end of the document, so an edit '
      'in the middle pays for the whole suffix.</p>';
}

/// CJK filler of an exact UTF-16 length: long enough to wrap across many
/// lines at 360px, with punctuation that exercises the line-break rules.
String _cjkFiller(int chars) {
  const unit = 'Weft 引擎在浮动图片旁边逐行缩短行盒，中文文本连续排布时按字符'
      '断行，标点不落在行首。';
  final buffer = StringBuffer();
  while (buffer.length < chars) {
    buffer.write(unit);
  }
  return buffer.toString().substring(0, chars);
}

/// Streams one update shape over a document chain: every round normalizes a
/// new snapshot under the same document id (the engine's reuse key), lays it
/// out against the previous result, and records the round cost plus the
/// structural counters that say which path actually ran.
void _runStreamingShape({
  required WeftLayoutEngine engine,
  required String shape,
  required String host,
  required int base,
  required String Function(int round) htmlFor,
  int Function(int round, int previousChildren)? expectedReused,
  bool expectLazy = false,
}) {
  final id = 'profile-stream-$shape-$host-$base';
  WeftLayoutResult? current;
  var previousChildren = 0;
  final roundMs = <double>[];
  final reusedSeen = <int>[];
  for (var round = 1; round <= _streamWarmupRounds + _streamRounds; round++) {
    final document = _normalize(htmlFor(round), id);
    final children = document.body!.children.length;
    final watch = Stopwatch()..start();
    final WeftLayoutResult next;
    if (host == 'lazy') {
      next = engine.layoutViewport(
        document,
        width: _viewportWidth,
        viewportStart: 0,
        viewportEnd: _viewportHeight,
        images: const <int, ui.Image>{},
        previous: current,
      );
    } else {
      next = engine.layout(
        document,
        width: _viewportWidth,
        images: const <int, ui.Image>{},
        previous: current,
      );
    }
    watch.stop();
    current?.dispose();
    current = next;
    if (round > _streamWarmupRounds) {
      if (expectLazy) {
        expect(next.debugIsLazy, isTrue, reason: 'shape=$shape round=$round');
      } else {
        expect(
          next.debugReusedBlockCount,
          expectedReused!(round, previousChildren),
          reason: 'shape=$shape round=$round: reuse must follow the shape '
              'contract for the cost reading to mean anything',
        );
      }
      roundMs.add(watch.elapsedMicroseconds / 1000.0);
      reusedSeen.add(next.debugReusedBlockCount);
      _profileLine(
        'e1 shape=$shape host=$host base=$base round=$round '
        'ms=${_f(watch.elapsedMicroseconds / 1000.0)} children=$children '
        'reused=${next.debugReusedBlockCount} '
        'laidOut=${next.debugLaidOutBlockCount} '
        'estimated=${next.debugEstimatedBlockCount} '
        'eligibility=${next.debugEligibilityVisitCount} '
        'lazy=${next.debugIsLazy} '
        'cacheSeeded=${next.incrementalCache != null}',
      );
    }
    previousChildren = children;
  }
  current?.dispose();

  final finalDoc = _normalize(
    htmlFor(_streamWarmupRounds + _streamRounds),
    '$id-coldref',
  );
  final coldRefMs = _medianMs(
    () => engine.layout(finalDoc, width: _viewportWidth).dispose(),
  );
  final median = _medianOf(roundMs);
  _profileLine(
    'e1 shape=$shape host=$host base=$base summary rounds=${roundMs.length} '
    'medianMs=${_f(median)} reusedRange=${reusedSeen.first}..${reusedSeen.last} '
    'coldRefMs=${_f(coldRefMs)} saving=${_f(100 * (1 - median / coldRefMs))}%',
  );
}

/// Lays [targetDoc] out against freshly seeded previous results of
/// [seedDoc]. Each previous is consumed exactly once because reused commands
/// transfer out of it; the first pass is the warm-up.
double _relayoutMs(
  WeftLayoutEngine engine,
  WeftDocumentSnapshot seedDoc,
  WeftDocumentSnapshot targetDoc,
  int expectedReused,
) {
  final previouses = List<WeftLayoutResult>.generate(
    _sampleCount + 1,
    (_) => engine.layout(seedDoc, width: _viewportWidth),
  );
  final samples = <double>[];
  for (var i = 0; i < previouses.length; i++) {
    final previous = previouses[i];
    final watch = Stopwatch()..start();
    final next = engine.layout(
      targetDoc,
      width: _viewportWidth,
      previous: previous,
    );
    watch.stop();
    if (i > 0) {
      expect(
        next.debugReusedBlockCount,
        expectedReused,
        reason: 'reuse must fully engage for the decomposition to hold',
      );
      samples.add(watch.elapsedMicroseconds / 1000.0);
    }
    previous.dispose();
    next.dispose();
  }
  return _medianOf(samples);
}

/// Resolves every element in the document exactly the way the text index
/// build and the layout walk do, so its cost prices one full style pass.
int _styleResolveAll(
  WeftDocumentSnapshot document,
  WeftStyleResolver resolver,
) {
  var count = 0;
  void visit(
      WeftNode node, WeftComputedStyle style, List<WeftElement> ancestors) {
    if (node is! WeftElement) return;
    final childAncestors = <WeftElement>[...ancestors, node];
    final childStyle = resolver.resolve(
      node,
      parent: style,
      ancestors: ancestors,
    );
    count++;
    for (final child in node.children) {
      visit(child, childStyle, childAncestors);
    }
  }

  final body = document.body;
  if (body != null) {
    visit(
      body,
      resolver.resolve(body,
          parent: WeftComputedStyle.initial, ancestors: const []),
      const [],
    );
  }
  return count;
}

/// Tool-side mirror of the engine's recursive snapshot diff
/// (layout_engine.dart `_sameNode`): ids, tags, attributes, inline styles
/// and text, recursing through children. The engine diffs block by block
/// until the first mismatch; over unchanged content it visits the same tree.
bool _sameNodeProxy(WeftNode first, WeftNode second) {
  if (first.id != second.id) return false;
  if (first is WeftText && second is WeftText) {
    return first.text == second.text;
  }
  if (first is! WeftElement || second is! WeftElement) return false;
  if (first.tag != second.tag ||
      !_sameStringsProxy(first.attributes, second.attributes) ||
      !_sameStringsProxy(first.inlineStyle, second.inlineStyle) ||
      first.children.length != second.children.length) {
    return false;
  }
  for (var i = 0; i < first.children.length; i++) {
    if (!_sameNodeProxy(first.children[i], second.children[i])) {
      return false;
    }
  }
  return true;
}

bool _sameStringsProxy(Map<String, String> first, Map<String, String> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}

WeftDocumentSnapshot _normalize(String html, String id) {
  final document = const WeftNormalizer().normalize(html, id: id);
  if (!document.supportReport.canRender) {
    throw StateError(
      'Profile document "$id" is not renderable: '
      '${document.supportReport.issues.map((issue) => issue.code).join(', ')}',
    );
  }
  return document;
}

/// Rich article body: a heading every ten paragraphs, inline emphasis and
/// links inside the paragraphs (same paragraph template as
/// tool/layout_benchmark_test.dart).
String _articleHtml(int count) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    if (i % 10 == 0) {
      buffer.write('<h3>章节 ${i ~/ 10}:中英混排与布局性能基准</h3>');
    }
    buffer.write(_articleParagraphHtml(i));
  }
  return buffer.toString();
}

String _articleParagraphHtml(int i) {
  return '<p>第 $i 段。Weft engine lays out mixed English and 中文内容 at a '
      'fixed 360px viewport, exercising line breaking, <em>强调文本 $i</em> '
      'and <a href="https://example.com/a$i">inline links 第 $i 段</a> so the '
      'paragraph wraps onto several lines deterministically.</p>';
}

/// Plain article body without headings: one block per paragraph so the
/// streaming shapes can splice and replace blocks by index.
String _plainArticleHtml(int count,
    {String? Function(int index)? paragraphFor}) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    buffer.write(paragraphFor?.call(i) ?? _articleParagraphHtml(i));
  }
  return buffer.toString();
}

Map<int, ui.Image> _imagesFor(WeftDocumentSnapshot document, ui.Image image) {
  final images = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      if (node.tag == 'img') images[node.id] = image;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  final body = document.body;
  if (body != null) visit(body);
  return images;
}

Future<ui.Image> _createImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

double _medianMs(
  void Function() body, {
  int warmups = 1,
  int samples = _sampleCount,
}) {
  for (var i = 0; i < warmups; i++) {
    body();
  }
  final values = <double>[];
  for (var i = 0; i < samples; i++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    values.add(watch.elapsedMicroseconds / 1000.0);
  }
  return _medianOf(values);
}

double _medianOf(List<double> samples) {
  final sorted = samples.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

String _f(double value) => value.toStringAsFixed(3);

void _profileLine(String message) {
  // ignore: avoid_print
  print('profile $message');
}
