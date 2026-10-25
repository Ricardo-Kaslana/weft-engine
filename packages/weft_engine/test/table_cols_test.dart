import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeftDocumentSnapshot normalize(String html) {
    final document = const WeftNormalizer().normalize(html, id: 'table-cols');
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

  Rect tableBox(WeftLayoutResult layout, WeftDocumentSnapshot document) {
    final table = document.body!.children
        .whereType<WeftElement>()
        .firstWhere((element) => element.tag == 'table');
    return layout.boxes.singleWhere((box) => box.nodeId == table.id).rect;
  }

  group('column track normalization', () {
    test('keeps colgroup and col with sanitized span and width', () {
      final snapshot = normalize(
        '<table><colgroup span="2"><col width="80"><col width="25%" span="3">'
        '</colgroup><tr><td>A</td><td>B</td><td>C</td></tr></table>',
      );

      final table = snapshot.body!.children.whereType<WeftElement>().single;
      final groups = table.children
          .whereType<WeftElement>()
          .where((element) => element.tag == 'colgroup')
          .toList();
      expect(groups, hasLength(1));
      expect(groups.single.attribute('span'), '2');
      final cols = groups.single.children.whereType<WeftElement>().toList();
      expect(cols.map((col) => col.tag), ['col', 'col']);
      expect(cols[0].attribute('width'), '80');
      expect(cols[1].attribute('width'), '25%');
      expect(cols[1].attribute('span'), '3');
    });

    test('keeps a colgroup declared after the rows', () {
      final snapshot = normalize(
        '<table><tr><td>A</td></tr><colgroup><col width="40"></colgroup></table>',
      );

      final table = snapshot.body!.children.whereType<WeftElement>().single;
      expect(
        table.children.whereType<WeftElement>().map((element) => element.tag),
        containsAllInOrder(<String>['tbody', 'colgroup']),
      );
    });

    test('drops column declarations outside tables', () {
      // The HTML5 parser ignores colgroup/col outside table context, so the
      // normalized tree keeps none of them; the normalizer's own guard only
      // covers tree sources that bypass the parser.
      final snapshot = normalize(
        '<p>a</p><colgroup><col></colgroup><div><col width="80"></div>',
      );

      final tags = <String>[];
      void visit(WeftNode node) {
        if (node is WeftElement) {
          tags.add(node.tag);
          for (final child in node.children) {
            visit(child);
          }
        }
      }

      visit(snapshot.body!);
      expect(tags, isNot(anyElement(anyOf('colgroup', 'col'))));
    });

    test('sanitizes column spans and widths', () {
      final snapshot = const WeftNormalizer().normalize(
        '<table><col span="0" width="abc"><col span="9999" width="-4">'
        '<col width="40px"><tr><td>A</td></tr></table>',
        id: 'col-sanitize',
      );

      expect(snapshot.supportReport.canRender, isTrue);
      expect(
        snapshot.supportReport.issues.map((issue) => issue.code),
        containsAll(<String>[
          'table.span.invalid',
          'table.span.clamped',
          'table.col.width.invalid',
        ]),
      );

      final table = snapshot.body!.children.whereType<WeftElement>().single;
      final cols = table.children
          .whereType<WeftElement>()
          .where((element) => element.tag == 'colgroup')
          .expand((group) => group.children.whereType<WeftElement>())
          .toList();
      expect(cols, hasLength(3));
      expect(cols[0].attributes.keys, isNot(anyOf('span', 'width')));
      expect(cols[1].attribute('span'), '1000');
      expect(cols[1].attributes.keys, isNot(contains('width')));
      expect(cols[2].attributes.keys, isNot(contains('width')));
    });
  });

  group('column track layout', () {
    test('pins columns to the col px width from CSS and the attribute', () {
      const html = '<table style="border-spacing: 0"><colgroup>'
          '<col style="width: 100px"><col width="50"></colgroup>'
          '<tr><td id="a">A</td><td id="b">B</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      expect(boxOf(result, document, 'a'), const Rect.fromLTWH(0, 0, 100, 24));
      expect(boxOf(result, document, 'b'), const Rect.fromLTWH(100, 0, 50, 24));
      expect(tableBox(result, document).width,
          moreOrLessEquals(150, epsilon: 0.5));
    });

    test('col span pins every column it covers', () {
      const html = '<table style="border-spacing: 0"><colgroup>'
          '<col style="width: 40px" span="2"><col></colgroup>'
          '<tr><td id="a">A</td><td id="b">B</td><td id="c">C</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(40, epsilon: 0.5));
      expect(boxOf(result, document, 'b').width,
          moreOrLessEquals(40, epsilon: 0.5));
      expect(boxOf(result, document, 'b').left,
          moreOrLessEquals(40, epsilon: 0.5));
      expect(boxOf(result, document, 'c').left,
          moreOrLessEquals(80, epsilon: 0.5));
    });

    test('colgroup span declares placeholder tracks for empty columns', () {
      const html = '<table style="border-spacing: 0; width: 100px"><colgroup>'
          '<col style="width: 40px"></colgroup><colgroup span="1"></colgroup>'
          '<tr><td id="a">A</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      // The placeholder track exists and absorbs the surplus: without it the
      // table would shrink to the 40px pinned column.
      expect(tableBox(result, document).width,
          moreOrLessEquals(100, epsilon: 0.5));
      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(40, epsilon: 0.5));
    });

    test('colgroup span is ignored once col children exist', () {
      const html = '<table style="border-spacing: 0; width: 100px">'
          '<colgroup span="3"><col style="width: 40px"></colgroup>'
          '<tr><td id="a">A</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      // One col child means one track, so the table shrinks to it.
      expect(
          tableBox(result, document).width, moreOrLessEquals(40, epsilon: 0.5));
    });

    test('auto columns consume the budget left by pinned tracks', () {
      const html = '<table style="border-spacing: 0; width: 300px"><colgroup>'
          '<col style="width: 80px"><col style="width: 120px"></colgroup>'
          '<tr><td id="a">A</td><td id="b">B</td>'
          '<td id="c" style="width: 100px">C</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(80, epsilon: 0.5));
      expect(boxOf(result, document, 'b').width,
          moreOrLessEquals(120, epsilon: 0.5));
      expect(boxOf(result, document, 'c').width,
          moreOrLessEquals(100, epsilon: 0.5));
      expect(boxOf(result, document, 'c').left,
          moreOrLessEquals(200, epsilon: 0.5));
      expect(tableBox(result, document).width,
          moreOrLessEquals(300, epsilon: 0.5));
    });

    test('percentage columns resolve against the table width', () {
      const html = '<table style="border-spacing: 0; width: 400px"><colgroup>'
          '<col style="width: 25%"><col></colgroup>'
          '<tr><td id="a">A</td><td id="b" style="width: 100px">B</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(100, epsilon: 0.5));
      expect(boxOf(result, document, 'b').width,
          moreOrLessEquals(300, epsilon: 0.5));
      expect(boxOf(result, document, 'b').left,
          moreOrLessEquals(100, epsilon: 0.5));
    });

    test('colspan need bypasses pinned columns and flows into auto columns',
        () {
      const html = '<table style="border-spacing: 0; width: 220px"><colgroup>'
          '<col style="width: 60px"><col></colgroup>'
          '<tr><td id="wide" colspan="2">alpha bravo</td></tr>'
          '<tr><td id="a">A</td><td id="b">B</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      // The spanning cell needs far more than 60px, but the pinned column
      // keeps its declared width and the auto column absorbs the rest.
      final wide = boxOf(result, document, 'wide');
      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(60, epsilon: 0.5));
      expect(boxOf(result, document, 'b').width,
          moreOrLessEquals(160, epsilon: 0.5));
      expect(wide.width, moreOrLessEquals(220, epsilon: 0.5));
      expect(wide.height, moreOrLessEquals(24, epsilon: 0.5));
    });

    test('rows with more cells than tracks create implicit auto columns', () {
      const html = '<table style="border-spacing: 0; width: 200px"><colgroup>'
          '<col style="width: 50px"><col style="width: 50px"></colgroup>'
          '<tr><td id="a">A</td><td id="b">B</td><td id="c">C</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      expect(boxOf(result, document, 'a').width,
          moreOrLessEquals(50, epsilon: 0.5));
      expect(boxOf(result, document, 'b').width,
          moreOrLessEquals(50, epsilon: 0.5));
      expect(boxOf(result, document, 'c').left,
          moreOrLessEquals(100, epsilon: 0.5));
      expect(boxOf(result, document, 'c').width,
          moreOrLessEquals(100, epsilon: 0.5));
    });

    test('tracks coexist with collapsed and separated borders', () {
      const html = '<table style="border-collapse: collapse; width: 240px">'
          '<colgroup><col style="width: 80px"><col style="width: 50%"></colgroup>'
          '<colgroup span="1"></colgroup>'
          '<tr><td id="a" style="border: 2px solid #000">A</td>'
          '<td id="b" style="border: 2px solid #000">B</td>'
          '<td id="c" style="border: 2px solid #000">C</td></tr></table>'
          '<table style="border-spacing: 4px; width: 240px"><colgroup>'
          '<col style="width: 80px"><col width="25%"></colgroup>'
          '<colgroup span="1"></colgroup>'
          '<tr><td id="d">D</td><td id="e">E</td><td id="f">F</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      // Collapsed: cells span edge centre lines, so a pinned 80px col keeps
      // the 80px centre-line distance while the shared borders become
      // synthetic padding.
      final a = boxOf(result, document, 'a');
      final b = boxOf(result, document, 'b');
      final c = boxOf(result, document, 'c');
      expect(a.width, moreOrLessEquals(80, epsilon: 0.5));
      expect(b.width, moreOrLessEquals(120, epsilon: 0.5));
      expect(c.width, moreOrLessEquals(40, epsilon: 0.5));
      expect(a.right, moreOrLessEquals(b.left, epsilon: 0.5));
      expect(b.right, moreOrLessEquals(c.left, epsilon: 0.5));

      // Separated: cells keep their own borders inside the declared widths
      // and the spacing sits between and around them.
      final d = boxOf(result, document, 'd');
      final e = boxOf(result, document, 'e');
      final f = boxOf(result, document, 'f');
      expect(d.width, moreOrLessEquals(80, epsilon: 0.5));
      expect(e.width, moreOrLessEquals(60, epsilon: 0.5));
      expect(f.width, moreOrLessEquals(84, epsilon: 0.5));
      expect(f.right, moreOrLessEquals(236, epsilon: 0.5));
      // Like Chrome, the collapsed box carries the outer half edges beyond
      // the specified width (240 + 2).
      final tables = document.body!.children
          .whereType<WeftElement>()
          .where((element) => element.tag == 'table')
          .toList();
      final boxes = tables
          .map(
            (table) => result.boxes
                .singleWhere((box) => box.nodeId == table.id)
                .rect
                .width,
          )
          .toList();
      expect(boxes[0], moreOrLessEquals(242, epsilon: 0.5));
      expect(boxes[1], moreOrLessEquals(240, epsilon: 0.5));
    });

    test('caption layout is unaffected by column tracks', () {
      const html = '<table style="border-spacing: 0">'
          '<caption id="cap">Caption</caption>'
          '<colgroup><col style="width: 100px"></colgroup>'
          '<tr><td id="a">A</td></tr></table>';
      final document = normalize(html);
      final result = layout(html);

      final caption = boxOf(result, document, 'cap');
      final a = boxOf(result, document, 'a');
      expect(caption.width, moreOrLessEquals(100, epsilon: 0.5));
      expect(a.width, moreOrLessEquals(100, epsilon: 0.5));
      expect(a.top, moreOrLessEquals(caption.bottom, epsilon: 0.5));
    });

    test('declarations outside the table or colgroup are ignored', () {
      // Hand-built snapshot: the HTML5 parser would relocate these, but other
      // tree sources might not, so the engine only reads direct col/colgroup
      // children and only col children of a colgroup.
      final document = WeftDocumentSnapshot(
        id: 'handmade',
        revision: 1,
        normalizedHtml: '',
        body: WeftElement(
          id: 0,
          tag: 'body',
          children: [
            WeftElement(
              id: 1,
              tag: 'table',
              children: [
                WeftElement(id: 2, tag: 'colgroup', children: [
                  WeftElement(id: 3, tag: 'col', attributes: {'width': '60'}),
                  WeftElement(id: 4, tag: 'span', children: [
                    const WeftText(id: 5, text: 'stray'),
                  ]),
                ]),
                WeftElement(id: 6, tag: 'tbody', children: [
                  WeftElement(id: 7, tag: 'col', attributes: {'width': '500'}),
                  WeftElement(id: 8, tag: 'tr', children: [
                    WeftElement(id: 9, tag: 'td', children: [
                      const WeftText(id: 10, text: 'A'),
                    ]),
                  ]),
                ]),
              ],
            ),
          ],
        ),
      );
      final result = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(result.dispose);

      // The 60px col applies; the stray span and the 500px col inside tbody
      // change nothing.
      final table = result.boxes.singleWhere((box) => box.nodeId == 1);
      expect(table.rect.width, moreOrLessEquals(64, epsilon: 0.5));
    });
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
