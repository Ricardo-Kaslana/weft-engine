import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const _badgeTag = 'weft-badge';

/// Example renderer: a rounded-free rectangular badge with centered text,
/// driven by attributes (`label`, `data-color`). This is the documented
/// custom-tag pattern: immutable element + width in, paint ops out.
final class _BadgeRenderer implements WeftTagRenderer {
  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final label = context.element.attribute('label') ?? 'Badge';
    final colorValue = context.element.attribute('data-color') ?? '#3355ff';
    final color = _parseHexColor(colorValue) ?? const Color(0xFF3355FF);
    const height = 24.0;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
      textScaler: context.textScaler,
    )..layout();
    final width = (painter.width + 16).clamp(24.0, context.contentWidth);
    return WeftTagLayout(
      height: height,
      semanticsLabel: 'Badge: $label',
      ops: [
        WeftTagRectOp(
          rect: Rect.fromLTWH(0, 0, width, height),
          color: color,
        ),
        WeftTagTextOp(
          offset: Offset(8, (height - painter.height) / 2),
          text: label,
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
          maxWidth: width - 16,
        ),
      ],
    );
  }
}

Color? _parseHexColor(String value) {
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

WeftDocumentSnapshot _badgeDocument({
  Set<String> customTags = const {_badgeTag},
  String html = '<p>Intro</p>'
      '<weft-badge label="New" data-color="#ff0055">ignored content</weft-badge>'
      '<p>Outro</p>',
}) {
  return WeftNormalizer(customTags: customTags)
      .normalize(html, id: 'badge-doc');
}

void main() {
  group('custom tags', () {
    test('the normalizer preserves allowlisted tags as attribute-driven leaves',
        () {
      final document = _badgeDocument();
      final body = document.body!;
      final badge = body.children.whereType<WeftElement>().firstWhere(
            (element) => element.tag == _badgeTag,
          );

      expect(badge.attribute('label'), 'New');
      expect(badge.attribute('data-color'), '#ff0055');
      expect(badge.children, isEmpty);
      expect(
        document.supportReport.issues
            .where((issue) => issue.code == 'html.tag.custom.contentIgnored'),
        hasLength(1),
      );
    });

    test('tags outside the allowlist keep the unknown-element behavior', () {
      final document = _badgeDocument(
          customTags: const <String>{},
          html: '<weft-badge label="New">ignored</weft-badge>');
      final body = document.body!;

      expect(body.children.whereType<WeftElement>(), isEmpty);
      expect(
        document.supportReport.issues
            .where((issue) => issue.code == 'html.tag.unknown'),
        hasLength(1),
      );
    });

    test('layout renders ops, a box and a hit region inside the content box',
        () {
      final document = _badgeDocument();
      final layout = WeftLayoutEngine(
        tagRenderers: {_badgeTag: _BadgeRenderer()},
      ).layout(document, width: 320);
      addTearDown(layout.dispose);

      expect(layout.tagRegions, hasLength(1));
      final region = layout.tagRegions.single;
      expect(region.tag, _badgeTag);
      expect(region.label, 'Badge: New');
      expect(region.rect.top, greaterThan(0));
      expect(region.rect.height, 24);

      final rects = layout.commands
          .whereType<WeftRectPaintCommand>()
          .where((command) => command.nodeId == region.nodeId)
          .toList();
      expect(rects, isNotEmpty);
      expect(rects.first.color, const Color(0xFFFF0055));
      expect(region.rect.contains(rects.first.rect.center), isTrue);

      final texts = layout.commands
          .whereType<WeftTextPaintCommand>()
          .where((command) => command.nodeId == region.nodeId)
          .toList();
      expect(texts, hasLength(1));
      expect(texts.single.painter.text!.toPlainText(), 'New');
      expect(region.rect.contains(texts.single.bounds.center), isTrue);

      expect(
        layout.commands
            .whereType<WeftRectPaintCommand>()
            .where((command) => command.nodeId == region.nodeId)
            .every((command) =>
                region.rect.intersect(command.rect) == command.rect),
        isTrue,
      );

      final middle = region.rect.center;
      expect(layout.tagAt(middle)?.nodeId, region.nodeId);
      expect(layout.tagAt(const Offset(2, 2)), isNull);
    });

    test('a missing renderer lays out an empty block without failing', () {
      final document = _badgeDocument();
      final layout = const WeftLayoutEngine().layout(document, width: 320);
      addTearDown(layout.dispose);

      expect(
        layout.tagRegions.where((region) => region.tag == _badgeTag),
        isEmpty,
      );
      expect(layout.commands.whereType<WeftTextPaintCommand>(), isNotEmpty);
    });

    test('a throwing renderer degrades to an empty box', () {
      final document = _badgeDocument();
      final layout = WeftLayoutEngine(
        tagRenderers: {_badgeTag: _ThrowingRenderer()},
      ).layout(document, width: 320);
      addTearDown(layout.dispose);

      expect(
        layout.commands.where((command) => command.bounds.isEmpty),
        isEmpty,
      );
      expect(layout.size.height, greaterThan(0));
    });

    test('renderer identity invalidates cached blocks on incremental layout',
        () {
      const engine = WeftLayoutEngine();
      final document = _badgeDocument();
      final withRenderer = WeftLayoutEngine(
        tagRenderers: {_badgeTag: _BadgeRenderer()},
      );
      final first = withRenderer.layout(document, width: 320);
      addTearDown(first.dispose);
      expect(first.tagRegions, hasLength(1));

      // A different engine without renderers must not reuse the cached block.
      final second = engine.layout(document, width: 320, previous: first);
      addTearDown(second.dispose);
      expect(second.tagRegions, isEmpty);

      // The same renderer map instance reuses the cached block and replays
      // the tag region.
      final renderers = {_badgeTag: _BadgeRenderer()};
      final third = WeftLayoutEngine(tagRenderers: renderers)
          .layout(document, width: 320);
      addTearDown(third.dispose);
      final fourth = WeftLayoutEngine(tagRenderers: renderers)
          .layout(document, width: 320, previous: third);
      addTearDown(fourth.dispose);
      expect(fourth.debugReusedBlockCount, greaterThan(0));
      expect(fourth.tagRegions, hasLength(1));
      expect(fourth.tagRegions.single.rect, third.tagRegions.single.rect);
    });

    testWidgets('surfaces report tag taps but not plain taps', (tester) async {
      final document = _badgeDocument();
      WeftTagRegion? tapped;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 320,
            child: WeftSurface(
              document: document,
              tagRenderers: {_badgeTag: _BadgeRenderer()},
              onTagTap: (region) => tapped = region,
            ),
          ),
        ),
      );

      final render =
          tester.allRenderObjects.whereType<RenderWeftSurface>().single;
      final region = render.debugLayout!.tagRegions.single;

      await tester.tapAt(region.rect.center);
      expect(tapped?.nodeId, region.nodeId);

      tapped = null;
      await tester.tapAt(const Offset(4, 4));
      expect(tapped, isNull);
    });

    testWidgets('custom tags expose their semantics label', (tester) async {
      final document = _badgeDocument();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 320,
            child: WeftSurface(
              document: document,
              tagRenderers: {_badgeTag: _BadgeRenderer()},
            ),
          ),
        ),
      );

      expect(find.semantics.byLabel('Badge: New'), findsOneWidget);
      semantics.dispose();
    });
  });
}

final class _ThrowingRenderer implements WeftTagRenderer {
  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    throw StateError('renderer exploded');
  }
}
