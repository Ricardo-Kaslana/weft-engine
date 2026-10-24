import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

void main() {
  test('parses supported selectors and declarations into structured rules', () {
    const source = '''
      .article > p, h1#hero {
        color: #123456;
        font-size: 20px;
        position: absolute;
      }
      p .bad, a:hover {
        font-weight: 700;
      }
    ''';

    final parsed = WeftStyleSheetParser.parse(source);

    expect(parsed.sheet.rules, hasLength(2));
    final first = parsed.sheet.rules.first;
    expect(first.selectors, hasLength(2));
    expect(
      first.selectors.first.combinators,
      [WeftSelectorCombinator.child],
    );
    expect(first.selectors.first.parts.first.classes, {'article'});
    expect(first.selectors.first.parts.last.tag, 'p');
    expect(first.selectors.last.specificity.ids, 1);
    expect(first.declarations, {
      'color': '#123456',
      'font-size': '20px',
    });
    expect(
      parsed.issues.map((issue) => issue.code),
      containsAll(<String>[
        'css.property.unsupported',
        'css.selector.unsupported',
      ]),
    );
  });

  test('selector matching respects descendant and child relationships', () {
    final parsed = WeftStyleSheetParser.parse(
      '.article > p strong { color: red; }',
    );
    final selector = parsed.sheet.rules.single.selectors.single;

    final body = WeftElement(id: 0, tag: 'body');
    final article = WeftElement(
      id: 1,
      tag: 'div',
      attributes: const {'class': 'article'},
    );
    final paragraph = WeftElement(id: 2, tag: 'p');
    final strong = WeftElement(id: 3, tag: 'strong');

    expect(
      selector.matches(strong, [body, article, paragraph]),
      isTrue,
    );
    expect(
      selector.matches(strong, [body, paragraph, article]),
      isFalse,
    );
  });

  test('declaration parser drops unsupported and important declarations', () {
    final result = WeftDeclarationParser.parse(
      'color: red; margin: 4px 8px; position: fixed; '
      'background-color: rgb(1, 2, 3); font-size: 20px !important;',
    );

    expect(result.declarations, {
      'color': 'red',
      'margin': '4px 8px',
      'background-color': 'rgb(1, 2, 3)',
    });
    expect(
      result.issues.map((issue) => issue.code),
      containsAll(<String>[
        'css.property.unsupported',
        'css.important.unsupported',
      ]),
    );
  });
}
