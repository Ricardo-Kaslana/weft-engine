import 'dart:convert';

import 'package:flutter/rendering.dart'
    show SemanticsFlag, SemanticsNode, SemanticsRole;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const _testPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGM0TjvDwMDAxAAG'
    'ABBNAWl85fWfAAAAAElFTkSuQmCC';

void main() {
  testWidgets('exposes reading-order text and activatable links',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p>Before <em>styled</em> '
      '<a href="https://example.com/target">target <strong>link</strong></a> after</p>'
      '<p>Second block</p>',
    );
    WeftLinkRegion? tapped;
    await tester.pumpWidget(
      _wrap(
        WeftSurface(
          document: document,
          onLinkTap: (region) => tapped = region,
        ),
      ),
    );

    expect(find.semantics.byLabel('Before styled '), findsOneWidget);
    expect(find.semantics.byLabel(' after'), findsOneWidget);
    expect(find.semantics.byLabel('Second block'), findsOneWidget);
    expect(find.semantics.byLabel('Before styled target link after'),
        findsNothing);
    final link = find.semantics.byLabel('target link');
    expect(link, findsOneWidget);
    expect(
      _node(link),
      containsSemantics(
        label: 'target link',
        isLink: true,
        hasTapAction: true,
        textDirection: TextDirection.ltr,
      ),
    );
    tester.semantics.tap(link);
    expect(tapped?.href, 'https://example.com/target');
    expect(tapped?.text, 'target link');
    semantics.dispose();
  });

  testWidgets('heading text and inline children expose header semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<h1>Main <a href="https://example.com">link</a></h1>'
      '<p>Body text</p><h3><em>Subheading</em></h3>'
      '<table><tr><th>Header cell</th><td>Data cell</td></tr></table>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(
      _node(find.semantics.byLabel('Main ')),
      containsSemantics(isHeader: true),
    );
    expect(
      _node(find.semantics.byLabel('link')),
      containsSemantics(isHeader: true, isLink: true),
    );
    expect(
      _node(find.semantics.byLabel('Subheading')),
      containsSemantics(isHeader: true),
    );
    expect(
      _node(find.semantics.byLabel('Body text')),
      containsSemantics(isHeader: false),
    );
    expect(
      _node(find.semantics.byLabel('Header cell')),
      containsSemantics(isHeader: true),
    );
    expect(
      _node(find.semantics.byLabel('Data cell')),
      containsSemantics(isHeader: false),
    );
    expect(
      _node(find.semantics.byLabel('Main ')).getSemanticsData().headingLevel,
      1,
    );
    expect(
      _node(find.semantics.byLabel('link')).getSemanticsData().headingLevel,
      1,
    );
    expect(
      _node(find.semantics.byLabel('Subheading'))
          .getSemanticsData()
          .headingLevel,
      3,
    );
    expect(
      _node(find.semantics.byLabel('Body text'))
          .getSemanticsData()
          .headingLevel,
      0,
    );
    expect(
      _node(find.semantics.byLabel('Header cell'))
          .getSemanticsData()
          .headingLevel,
      0,
    );
    final headerNode = _node(find.semantics.byLabel('Header cell'));
    expect(headerNode.parent?.role, SemanticsRole.columnHeader);
    expect(headerNode.parent?.indexInParent, 0);
    expect(headerNode.parent?.parent?.role, SemanticsRole.row);
    expect(headerNode.parent?.parent?.indexInParent, 0);
    expect(headerNode.parent?.parent?.parent?.role, SemanticsRole.table);
    semantics.dispose();
  });

  testWidgets('list items expose ordered and unordered markers once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<ol><li>First <em>item</em></li>'
      '<li><a href="https://example.com">Second item</a></li></ol>'
      '<ul><li>Bullet item</li></ul>'
      '<ol><li>Outer<ul><li>Nested</li></ul></li></ol>',
    );
    final probe = const WeftLayoutEngine().layout(document, width: 320);
    final entries = probe.textIndex!.entries;
    final selectionText = probe.selectionText(
      TextSelectionRange(
        anchor: TextAnchor(entries.first.nodeId, 0),
        extent: TextAnchor(entries.last.nodeId, 1),
      ),
    );
    probe.dispose();
    expect(selectionText, isNot(contains('1. ')));
    expect(selectionText, isNot(contains('• ')));

    await tester.pumpWidget(_wrap(WeftSurface(document: document)));
    expect(find.semantics.byLabel('1. First item'), findsOneWidget);
    expect(find.semantics.byLabel('2. Second item'), findsOneWidget);
    expect(find.semantics.byLabel('• Bullet item'), findsOneWidget);
    expect(find.semantics.byLabel('1. Outer'), findsOneWidget);
    expect(find.semantics.byLabel('• Nested'), findsOneWidget);
    final firstItem = _node(find.semantics.byLabel('1. First item'));
    expect(firstItem.parent?.role, SemanticsRole.listItem);
    expect(firstItem.parent?.indexInParent, 0);
    expect(firstItem.parent?.parent?.role, SemanticsRole.list);
    final secondItem = _node(find.semantics.byLabel('2. Second item'));
    expect(secondItem.parent?.indexInParent, 1);
    final nestedItem = _node(find.semantics.byLabel('• Nested'));
    expect(nestedItem.parent?.role, SemanticsRole.listItem);
    expect(nestedItem.parent?.parent?.role, SemanticsRole.list);
    semantics.dispose();
  });

  testWidgets('aria-live marks descendant text as live regions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p>Quiet</p>'
      '<div aria-live="polite"><p>Live <strong>update</strong></p>'
      '<p aria-live="off">Nested off</p></div>'
      '<p aria-live="off">Off</p>'
      '<p aria-live="assertive">Alert</p>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    bool live(String label) => _node(find.semantics.byLabel(label))
        .getSemanticsData()
        .flagsCollection
        .isLiveRegion;
    expect(live('Quiet'), isFalse);
    expect(live('Live update'), isTrue);
    expect(live('Nested off'), isFalse);
    expect(live('Off'), isFalse);
    expect(live('Alert'), isTrue);
    expect(find.semantics.byLabel('Live update'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('ordered list start and value reach semantic markers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<ol start="3"><li>Third</li><li value="7">Seventh</li>'
      '<li>Eighth</li></ol>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final third = _node(find.semantics.byLabel('3. Third'));
    final seventh = _node(find.semantics.byLabel('7. Seventh'));
    final eighth = _node(find.semantics.byLabel('8. Eighth'));
    expect(third.parent?.role, SemanticsRole.listItem);
    expect(third.parent?.indexInParent, 0);
    expect(seventh.parent?.indexInParent, 1);
    expect(eighth.parent?.indexInParent, 2);
    semantics.dispose();
  });

  testWidgets('table sections, caption and empty cells keep valid roles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<table><caption>Caption</caption>'
      '<thead><tr><th>Head</th></tr></thead>'
      '<tbody><tr><td></td><td>Body</td></tr></tbody></table>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final caption = _node(find.semantics.byLabel('Caption'));
    expect(caption.parent?.role, isNot(SemanticsRole.table));
    final head = _node(find.semantics.byLabel('Head'));
    expect(head.parent?.role, SemanticsRole.columnHeader);
    expect(head.parent?.parent?.role, SemanticsRole.row);
    expect(head.parent?.parent?.parent?.role, SemanticsRole.table);
    final body = _node(find.semantics.byLabel('Body'));
    expect(body.parent?.role, SemanticsRole.cell);
    expect(body.parent?.parent?.role, SemanticsRole.row);
    semantics.dispose();
  });

  testWidgets('selection copy action forwards the complete selected text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize('<p>Alpha block</p><p>Beta block</p>');
    final probe = const WeftLayoutEngine().layout(document, width: 280);
    final entries = probe.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries[0].nodeId, 2),
      extent: TextAnchor(entries[1].nodeId, 4),
    );
    final selectedText = probe.selectionText(selection)!;
    probe.dispose();
    String? copied;
    await tester.pumpWidget(
      _wrap(
        WeftSurface(
          document: document,
          selection: selection,
          onSemanticsCopy: (text) => copied = text,
        ),
      ),
    );

    final selected = find.semantics.byValue(selectedText);
    expect(selected, findsOneWidget);
    expect(
      _node(selected),
      containsSemantics(isSelected: true, hasCopyAction: true),
    );
    tester.semantics.copy(selected);
    expect(copied, selectedText);
    semantics.dispose();
  });

  testWidgets('link without a callback has no tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p><a href="https://example.com">Read only link</a></p>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(
      _node(find.semantics.byLabel('Read only link')),
      containsSemantics(isLink: true, hasTapAction: false),
    );
    semantics.dispose();
  });

  testWidgets('selection semantics follow updates without editable actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize('<p>Alpha block</p><p>Beta block</p>');
    final probe = const WeftLayoutEngine().layout(document, width: 280);
    final entries = probe.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries[0].nodeId, 2),
      extent: TextAnchor(entries[1].nodeId, 4),
    );
    final selectedText = probe.selectionText(selection);
    probe.dispose();
    expect(selectedText, isNotNull);

    await tester.pumpWidget(
      _wrap(WeftSurface(document: document, selection: selection)),
    );
    final selected = find.semantics.byValue(selectedText!);
    expect(selected, findsOneWidget);
    expect(
      _node(selected),
      containsSemantics(
        value: selectedText,
        isSelected: true,
        isTextField: false,
        hasCopyAction: false,
        hasSetSelectionAction: false,
      ),
    );

    await tester.pumpWidget(_wrap(WeftSurface(document: document)));
    expect(selected, findsNothing);
    semantics.dispose();
  });

  testWidgets(
      'resolved images expose alt once and decorative images are omitted', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<img src="memory://cover" alt="Cover image" width="40" height="20">'
      '<img src="memory://dot" alt="" width="10" height="10">',
    );
    final provider = MemoryImage(base64Decode(_testPngBase64));
    await tester.pumpWidget(
      _wrap(
        WeftSurface(
          document: document,
          imageResolver: (_) => provider,
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final image = find.semantics.byLabel('Cover image');
    expect(image, findsOneWidget);
    expect(_node(image), containsSemantics(isImage: true));
    expect(find.semantics.byFlag(SemanticsFlag.isImage), findsOneWidget);
    expect(find.semantics.byLabel('￼'), findsNothing);
    semantics.dispose();
  });

  testWidgets('unresolved image alt remains text without duplication', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p>Before <img src="memory://broken" alt="Fallback"> after</p>',
    );
    await tester.pumpWidget(
      _wrap(
        WeftSurface(
          document: document,
          imageResolver: (_) => null,
        ),
      ),
    );

    expect(find.semantics.byLabel('Fallback'), findsOneWidget);
    expect(
      _node(find.semantics.byLabel('Fallback')),
      containsSemantics(isImage: false),
    );
    expect(find.semantics.byLabel('Before '), findsOneWidget);
    expect(find.semantics.byLabel(' after'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('streaming revisions retain semantic node identities', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final first = _normalize('<p>Alpha</p>', id: 'stream', revision: 1);
    final appended = _normalize(
      '<p>Alpha</p><p>Beta</p>',
      id: 'stream',
      revision: 2,
    );
    final replacement = _normalize(
      '<p>Alpha</p><p>Beta</p>',
      id: 'other-document',
      revision: 3,
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: first)));
    final alpha = find.semantics.byLabel('Alpha');
    final originalId = _node(alpha).id;

    await tester.pumpWidget(_wrap(WeftSurface(document: appended)));
    expect(_node(alpha).id, originalId);
    expect(find.semantics.byLabel('Beta'), findsOneWidget);

    await tester.pumpWidget(_wrap(WeftSurface(document: replacement)));
    expect(_node(alpha).id, isNot(originalId));
    semantics.dispose();
  });

  testWidgets('preformatted newlines produce distinct semantic nodes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize('<pre>first line\nsecond line</pre>');
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(find.semantics.byLabel('first line'), findsOneWidget);
    expect(find.semantics.byLabel('second line'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('ExcludeSemantics hides and restores the whole surface', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize('<p>Semantic content</p>');
    Widget wrap(bool excluded) {
      return ExcludeSemantics(
        excluding: excluded,
        child: _wrap(WeftSurface(document: document)),
      );
    }

    await tester.pumpWidget(wrap(true));
    expect(find.semantics.byLabel('Semantic content'), findsNothing);
    await tester.pumpWidget(wrap(false));
    expect(find.semantics.byLabel('Semantic content'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('role button and link map to announcement flags', (tester) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<div role="button">Save draft</div>'
      '<p><span role="link">Read more</span></p>'
      '<p><a href="https://example.com" role="button">Anchored</a></p>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(
      _node(find.semantics.byLabel('Save draft')),
      containsSemantics(isButton: true, isLink: false, hasTapAction: false),
    );
    expect(
      _node(find.semantics.byLabel('Read more')),
      containsSemantics(isButton: false, isLink: true, hasTapAction: false),
    );
    // An explicit role overrides the anchor's implicit link semantics.
    expect(
      _node(find.semantics.byLabel('Anchored')),
      containsSemantics(isButton: true, isLink: false, hasTapAction: false),
    );
    semantics.dispose();
  });

  testWidgets('aria-hidden removes a subtree from semantics, not from copy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p>Visible intro</p>'
      '<div aria-hidden="true"><p>Hidden teaser</p></div>'
      '<p>Visible outro</p>',
    );
    final probe = const WeftLayoutEngine().layout(document, width: 280);
    final entries = probe.textIndex!.entries;
    final copyText = probe.selectionText(
      TextSelectionRange(
        anchor: TextAnchor(entries.first.nodeId, 0),
        extent: TextAnchor(entries.last.nodeId, 1),
      ),
    );
    probe.dispose();
    expect(copyText, contains('Hidden teaser'));

    await tester.pumpWidget(_wrap(WeftSurface(document: document)));
    expect(find.semantics.byLabel('Visible intro'), findsOneWidget);
    expect(find.semantics.byLabel('Hidden teaser'), findsNothing);
    expect(find.semantics.byLabel('Visible outro'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('presentation lists lose roles and markers but keep text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<ul role="presentation"><li>Plain one</li><li>Plain two</li></ul>'
      '<ul><li>Real bullet</li></ul>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(find.semantics.byLabel('• Plain one'), findsNothing);
    final plain = _node(find.semantics.byLabel('Plain one'));
    // Without the list containers the leaf hangs directly under the
    // surface root instead of a listItem role node.
    expect(plain.parent?.role, SemanticsRole.none);
    expect(find.semantics.byLabel('Plain two'), findsOneWidget);
    final real = _node(find.semantics.byLabel('• Real bullet'));
    expect(real.parent?.role, SemanticsRole.listItem);
    semantics.dispose();
  });

  testWidgets('presentation tables drop structural roles but keep cells', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<table role="presentation"><tr><th>Layout head</th>'
      '<td>Layout cell</td></tr></table>'
      '<table><tr><td>Real cell</td></tr></table>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final head = _node(find.semantics.byLabel('Layout head'));
    expect(head.parent?.role, SemanticsRole.none);
    expect(find.semantics.byLabel('Layout cell'), findsOneWidget);
    final real = _node(find.semantics.byLabel('Real cell'));
    expect(real.parent?.role, SemanticsRole.cell);
    semantics.dispose();
  });

  testWidgets('aria-atomic announces a live region as one group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<div aria-live="polite" aria-atomic="true"><p>Status one</p>'
      '<p>Status two</p></div>'
      '<div aria-live="polite"><p>Leaf one</p><p>Leaf two</p></div>'
      '<div aria-atomic="true"><p>Atomic outside live</p></div>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final group = find.semantics.byLabel('Status one Status two');
    expect(group, findsOneWidget);
    expect(
        _node(group).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(find.semantics.byLabel('Status one'), findsNothing);
    // Without atomic the leaves stay individual live regions.
    expect(find.semantics.byLabel('Leaf one'), findsOneWidget);
    expect(find.semantics.byLabel('Leaf two'), findsOneWidget);
    // Atomic outside a live region changes nothing.
    expect(find.semantics.byLabel('Atomic outside live'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('role alert and status imply grouped live announcements', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<div role="alert"><p>Connection lost</p><p>Retry soon</p></div>'
      '<div role="status"><p>Saved quietly</p></div>'
      '<div role="alert" aria-live="off"><p>Muted alert</p></div>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final alert = find.semantics.byLabel('Connection lost Retry soon');
    expect(alert, findsOneWidget);
    expect(
        _node(alert).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    // The framework forbids combining these roles with the liveRegion flag,
    // so the role itself is not mapped (ADR 0040).
    expect(_node(alert).getSemanticsData().role, SemanticsRole.none);
    final status = find.semantics.byLabel('Saved quietly');
    expect(status, findsOneWidget);
    expect(
      _node(status).getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    // An explicit aria-live="off" beats the implicit live role.
    expect(
      _node(find.semantics.byLabel('Muted alert'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('image aria-label wins over alt and presentation images drop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<img src="memory://cover" alt="Alt name" aria-label="Aria name" '
      'width="40" height="20">'
      '<img src="memory://decor" alt="Decoration" role="presentation" '
      'width="10" height="10">',
    );
    final provider = MemoryImage(base64Decode(_testPngBase64));
    await tester.pumpWidget(
      _wrap(
        WeftSurface(document: document, imageResolver: (_) => provider),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.semantics.byLabel('Aria name'), findsOneWidget);
    expect(find.semantics.byLabel('Alt name'), findsNothing);
    expect(find.semantics.byLabel('Decoration'), findsNothing);
    semantics.dispose();
  });

  testWidgets('aria-label collapses a subtree into one named leaf', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<div aria-label="Rating widget"><p>Five stars</p><p>Out of five</p></div>'
      '<p><a href="https://example.com/profile" aria-label="Open profile">'
      'Profile</a></p>',
    );
    WeftLinkRegion? tapped;
    await tester.pumpWidget(
      _wrap(
        WeftSurface(
          document: document,
          onLinkTap: (region) => tapped = region,
        ),
      ),
    );

    final named = find.semantics.byLabel('Rating widget');
    expect(named, findsOneWidget);
    expect(find.semantics.byLabel('Five stars'), findsNothing);
    expect(find.semantics.byLabel('Out of five'), findsNothing);
    final link = find.semantics.byLabel('Open profile');
    expect(link, findsOneWidget);
    expect(find.semantics.byLabel('Profile'), findsNothing);
    expect(_node(link), containsSemantics(isLink: true, hasTapAction: true));
    tester.semantics.tap(link);
    expect(tapped?.href, 'https://example.com/profile');
    semantics.dispose();
  });

  testWidgets('unsupported roles are dropped without breaking semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<p role="banner">Landmarked</p><p role="tooltip">Tipped</p>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    expect(find.semantics.byLabel('Landmarked'), findsOneWidget);
    expect(
      _node(find.semantics.byLabel('Landmarked')).getSemanticsData().role,
      SemanticsRole.none,
    );
    expect(find.semantics.byLabel('Tipped'), findsOneWidget);
    expect(
      document.supportReport.issues.map((issue) => issue.code),
      contains('aria.role.unsupported'),
    );
    semantics.dispose();
  });

  testWidgets('dialog roles become semantic containers with the name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _normalize(
      '<div role="dialog" aria-label="Confirm"><p>Confirm body</p></div>'
      '<div role="alertdialog"><p>Warning body</p></div>',
    );
    await tester.pumpWidget(_wrap(WeftSurface(document: document)));

    final named = _node(find.semantics.byLabel('Confirm'));
    expect(named.parent?.role, SemanticsRole.dialog);
    expect(find.semantics.byLabel('Confirm body'), findsNothing);
    final warning = _node(find.semantics.byLabel('Warning body'));
    expect(warning.parent?.role, SemanticsRole.alertDialog);
    semantics.dispose();
  });
}

SemanticsNode _node(SemanticsFinder finder) => finder.evaluate().single;

Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(width: 280, height: 300, child: child),
  );
}

WeftDocumentSnapshot _normalize(
  String html, {
  String id = 'semantics',
  int revision = 1,
}) {
  return const WeftNormalizer().normalize(html, id: id, revision: revision);
}
