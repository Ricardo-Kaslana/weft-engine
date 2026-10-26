import 'dart:convert';

import 'package:flutter/rendering.dart' show SemanticsFlag, SemanticsNode;
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
