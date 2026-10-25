import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeftDocumentSnapshot normalize(String html) {
    final document = const WeftNormalizer().normalize(html, id: 'tables');
    expect(document.supportReport.canRender, isTrue);
    expect(document.body, isNotNull);
    return document;
  }

  WeftLayoutResult layout(String html, {double width = 400}) {
    final result = const WeftLayoutEngine().layout(
      normalize(html),
      width: width,
    );
    addTearDown(result.dispose);
    return result;
  }

  Rect boxOf(
      WeftLayoutResult layout, WeftDocumentSnapshot document, String id) {
    final element = findById(document.body!, id);
    return layout.boxes.singleWhere((box) => box.nodeId == element.id).rect;
  }

  test('separate model sizes columns to pinned cell widths', () {
    const html = '<table><tr>'
        '<td id="a" style="width: 100px">A</td>'
        '<td id="b" style="width: 120px">B</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    // Default UA spacing of 2px pads the table edges and separates cells.
    expect(boxOf(result, document, 'a'), const Rect.fromLTWH(2, 2, 100, 24));
    expect(boxOf(result, document, 'b'), const Rect.fromLTWH(104, 2, 120, 24));

    final tableBox = result.boxes.firstWhere(
      (box) =>
          box.nodeId ==
          document.body!.children.whereType<WeftElement>().first.id,
    );
    // Shrink-to-fit: 2 + 100 + 2 + 120 + 2 = 226, well below 400 available.
    expect(tableBox.rect.width, moreOrLessEquals(226, epsilon: 0.5));
    expect(tableBox.rect.height, moreOrLessEquals(28, epsilon: 0.5));
  });

  test('multi-row grids stack rows with spacing', () {
    const html = '<table><tr>'
        '<td id="a" style="width: 100px">A</td>'
        '</tr><tr>'
        '<td id="c" style="width: 100px">C</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    expect(boxOf(result, document, 'a'), const Rect.fromLTWH(2, 2, 100, 24));
    expect(boxOf(result, document, 'c'), const Rect.fromLTWH(2, 28, 100, 24));
  });

  test('colspan spans columns and fills available span width', () {
    const html = '<table><tr>'
        '<td id="wide" colspan="2" style="width: 200px">Wide</td>'
        '</tr><tr>'
        '<td id="a" style="width: 80px">A</td>'
        '<td id="b" style="width: 120px">B</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final wide = boxOf(result, document, 'wide');
    expect(wide.top, 2);
    expect(wide.left, 2);
    // The spanning cell covers both columns plus the interior gutter.
    expect(wide.width, moreOrLessEquals(202, epsilon: 0.5));
    expect(wide.height, moreOrLessEquals(24, epsilon: 0.5));

    expect(
        boxOf(result, document, 'a').top, moreOrLessEquals(28, epsilon: 0.5));
    expect(
        boxOf(result, document, 'b').left, moreOrLessEquals(84, epsilon: 0.5));
  });

  test('rowspan grows the final spanned row when content is taller', () {
    const html = '<table><tr>'
        '<td id="tall" rowspan="2" style="width: 80px">1<br>2<br>3</td>'
        '<td id="b" style="width: 80px">B</td>'
        '</tr><tr>'
        '<td id="c" style="width: 80px">C</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final tall = boxOf(result, document, 'tall');
    final b = boxOf(result, document, 'b');
    final c = boxOf(result, document, 'c');
    // The spanning cell is 3 lines (72px); rows 24+24+2 = 50 cannot fit it,
    // so the last row absorbs the deficit and grows to 46. Like a browser,
    // c's cell box stretches to the full row slot; its content centers.
    expect(tall.height, moreOrLessEquals(72, epsilon: 0.5));
    expect(b.height, moreOrLessEquals(24, epsilon: 0.5));
    expect(c.height, moreOrLessEquals(46, epsilon: 0.5));
    expect(c.top, moreOrLessEquals(28, epsilon: 0.5));
    expect(c.bottom, moreOrLessEquals(74, epsilon: 0.5));
  });

  test('overhanging rowspan creates implicit rows', () {
    const html = '<table><tr>'
        '<td id="hang" rowspan="3" style="width: 60px">H</td>'
        '<td id="x" style="width: 60px">X</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final hang = boxOf(result, document, 'hang');
    final x = boxOf(result, document, 'x');
    // The hanging span covers 24px plus 2x2 spacing of slack across the two
    // empty implicit rows; its box stretches to that 28px slot.
    expect(hang.top, 2);
    expect(hang.height, moreOrLessEquals(28, epsilon: 0.5));
    expect(x.top, 2);
    expect(hang.bottom, moreOrLessEquals(30, epsilon: 0.5));
    // Two inter-row gutters keep the implicit rows alive.
    expect(result.size.height, moreOrLessEquals(32, epsilon: 0.5));
  });

  test('border-spacing zero removes the gutters', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="a" style="width: 100px">A</td>'
        '<td id="b" style="width: 100px">B</td>'
        '</tr><tr>'
        '<td id="c" style="width: 100px">C</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    expect(
        boxOf(result, document, 'b').left, moreOrLessEquals(100, epsilon: 0.5));
    expect(
        boxOf(result, document, 'c').top, moreOrLessEquals(24, epsilon: 0.5));
  });

  test('table width distributes extra space across columns', () {
    const html = '<table style="width: 300px"><tr>'
        '<td id="a" style="width: 100px">A</td>'
        '<td id="b" style="width: 120px">B</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final a = boxOf(result, document, 'a');
    final b = boxOf(result, document, 'b');
    // 294px of column budget above the three gutters: extra 74 split
    // 100:120.
    expect(a.width, moreOrLessEquals(133.64, epsilon: 1));
    expect(b.width, moreOrLessEquals(161.36, epsilon: 1));
    expect(a.width + b.width, moreOrLessEquals(294, epsilon: 0.5));
    expect(b.left - a.right, moreOrLessEquals(2, epsilon: 0.5));
  });

  test('cells vertically center by default and honor explicit alignment', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="tall" style="width: 60px">1<br>2<br>3</td>'
        '<td id="mid" style="width: 60px">m</td>'
        '<td id="top" style="width: 60px; vertical-align: top">t</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final tall = boxOf(result, document, 'tall');
    final mid = boxOf(result, document, 'mid');
    final top = boxOf(result, document, 'top');
    // All cell boxes stretch to the 72px row; vertical alignment moves the
    // CONTENT, so the middle cell's text starts (72 - 24) / 2 = 24px lower.
    expect(tall.top, 0);
    expect(mid.top, 0);
    expect(top.top, 0);
    expect(tall.height, 72);
    expect(mid.height, 72);
    final textTops = <int, double>{};
    for (final command in result.commands.whereType<WeftTextPaintCommand>()) {
      textTops[command.nodeId] = command.offset.dy;
    }
    final midElement = findById(document.body!, 'mid');
    final topElement = findById(document.body!, 'top');
    expect(
      textTops[midElement.id]! - textTops[topElement.id]!,
      moreOrLessEquals(24, epsilon: 0.5),
    );
  });

  test('caption renders above the grid', () {
    const html = '<table>'
        '<caption id="cap">Caption</caption>'
        '<tr><td id="a" style="width: 100px">A</td></tr>'
        '</table>';
    final document = normalize(html);
    final result = layout(html);

    final caption = boxOf(result, document, 'cap');
    final cell = boxOf(result, document, 'a');
    expect(caption.top, 0);
    // The caption spans the table box: 100 + leading and trailing gutters.
    expect(caption.width, moreOrLessEquals(104, epsilon: 0.5));
    // The grid starts below the caption plus the leading gutter.
    expect(cell.top, moreOrLessEquals(caption.bottom + 2, epsilon: 0.5));
    expect(cell.left, 2);
  });

  test('collapsed borders resolve to the widest shared edge', () {
    const html = '<table style="border-collapse: collapse; width: 200px"><tr>'
        '<td id="a" style="border: 2px solid #ff0000">A</td>'
        '<td id="b" style="border: 4px solid #00ff00">B</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    // No per-cell border commands in the collapsed model; only grid edges:
    // three vertical plus two horizontal.
    final rects = result.commands.whereType<WeftRectPaintCommand>().toList();
    expect(rects, hasLength(5));

    final middle = rects.firstWhere((command) {
      final rect = command.rect;
      return rect.left > 10 && rect.left < 190 && rect.width == 4;
    });
    expect(middle.color, const Color(0xFF00FF00));
    // Cell boxes meet at the middle edge centerline and together fill the
    // column budget (200 minus the outer half edges).
    final a = boxOf(result, document, 'a');
    final b = boxOf(result, document, 'b');
    expect(a.right, moreOrLessEquals(b.left, epsilon: 0.5));
    expect(a.width + b.width, moreOrLessEquals(197, epsilon: 1));
    expect(b.right, lessThanOrEqualTo(200.5));
  });

  test('separate borders keep per-cell borders inside cell boxes', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="a" style="border: 2px solid #000000; width: 100px">A</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final a = boxOf(result, document, 'a');
    // Default box-sizing is content-box: 100px of content plus 2px borders
    // on both sides.
    expect(a, const Rect.fromLTWH(0, 0, 104, 28));
    final rects = result.commands.whereType<WeftRectPaintCommand>().toList();
    // The cell paints its four solid border sides as rects around the box.
    expect(rects.length, greaterThanOrEqualTo(4));
  });

  test('cell padding offsets content and grows the cell box', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="a" style="padding: 8px 12px; width: 100px; '
        'box-sizing: border-box">A</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final a = boxOf(result, document, 'a');
    expect(a, const Rect.fromLTWH(0, 0, 100, 40));

    final text = result.commands.whereType<WeftTextPaintCommand>().single;
    expect(text.offset.dx, moreOrLessEquals(12, epsilon: 0.5));
    expect(text.offset.dy, moreOrLessEquals(8, epsilon: 0.5));
  });

  test('thead/tbody rows render in document order', () {
    const html = '<table style="border-spacing: 0">'
        '<thead><tr><td id="h" style="width: 60px">H</td></tr></thead>'
        '<tbody><tr><td id="b" style="width: 60px">B</td></tr></tbody>'
        '</table>';
    final document = normalize(html);
    final result = layout(html);

    expect(boxOf(result, document, 'h').top, 0);
    expect(
        boxOf(result, document, 'b').top, moreOrLessEquals(24, epsilon: 0.5));
  });

  test('links inside cells produce clickable regions in cell bounds', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="a" style="width: 200px">'
        '<a id="link" href="https://example.com/cell">Cell link</a></td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final link = result.links.single;
    expect(link.href, 'https://example.com/cell');
    expect(link.rects, isNotEmpty);
    final cell = boxOf(result, document, 'a');
    for (final rect in link.rects) {
      expect(rect.left, greaterThanOrEqualTo(cell.left - 0.5));
      expect(rect.right, lessThanOrEqualTo(cell.right + 0.5));
      expect(rect.top, greaterThanOrEqualTo(cell.top - 0.5));
      expect(rect.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
      expect(result.linkAt(rect.center)?.href, link.href);
    }
  });

  test('block paragraphs inside cells stack vertically', () {
    const html = '<table style="border-spacing: 0"><tr>'
        '<td id="a" style="width: 200px"><p>One</p><p>Two</p></td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final a = boxOf(result, document, 'a');
    // Two paragraphs of one line each with collapsed 16px margins: 24 + 16 +
    // 24 = 64 tall.
    expect(a.height, moreOrLessEquals(64, epsilon: 0.5));
  });

  test('tables respect surrounding block margins without collapsing through',
      () {
    const html = '<p style="margin: 0">Before</p>'
        '<table style="margin: 10px 0; border-spacing: 0"><tr>'
        '<td style="width: 50px">A</td></tr></table>'
        '<p style="margin: 0">After</p>';
    final document = normalize(html);
    final result = layout(html);

    final tableBox = result.boxes.firstWhere(
      (box) =>
          box.nodeId ==
          document.body!.children
              .whereType<WeftElement>()
              .firstWhere((element) => element.tag == 'table')
              .id,
    );
    // 24 (paragraph) + 10 (margin) = 34; no collapse-through with cells.
    expect(tableBox.rect.top, moreOrLessEquals(34, epsilon: 0.5));
    expect(tableBox.rect.bottom, moreOrLessEquals(58, epsilon: 0.5));
    final after = result.commands.whereType<WeftTextPaintCommand>().singleWhere(
          (command) =>
              command.painter.text?.toPlainText().contains('After') ?? false,
        );
    expect(after.offset.dy, moreOrLessEquals(68, epsilon: 0.5));
  });

  test('long cell content wraps within the resolved column width', () {
    const html = '<table style="width: 200px"><tr>'
        '<td id="a">alpha bravo charlie delta echo foxtrot golf</td>'
        '<td id="b" style="width: 40px">B</td>'
        '</tr></table>';
    final document = normalize(html);
    final result = layout(html);

    final a = boxOf(result, document, 'a');
    final b = boxOf(result, document, 'b');
    expect(a.width, lessThanOrEqualTo(160));
    expect(a.width, greaterThan(40));
    expect(b.left, greaterThan(a.right));
    expect(a.height, greaterThan(24));
  });
}

WeftElement findById(WeftNode node, String id) {
  final found = findByIdOrNull(node, id);
  if (found == null) {
    throw StateError('Element with id "$id" was not found.');
  }
  return found;
}

WeftElement? findByIdOrNull(WeftNode node, String id) {
  if (node is! WeftElement) return null;
  if (node.idAttribute == id) return node;
  for (final child in node.children) {
    final match = findByIdOrNull(child, id);
    if (match != null) return match;
  }
  return null;
}
