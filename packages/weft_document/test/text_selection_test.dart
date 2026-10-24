import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

void main() {
  test('collapsed selection preserves its stable anchor', () {
    const anchor = TextAnchor(7, 42);
    const selection = TextSelectionRange.collapsed(anchor);

    expect(selection.anchor, anchor);
    expect(selection.extent, anchor);
    expect(selection.isCollapsed, isTrue);
  });

  test('selection value equality includes both endpoints', () {
    const first = TextSelectionRange(
      anchor: TextAnchor(1, 0),
      extent: TextAnchor(4, 12),
    );
    const same = TextSelectionRange(
      anchor: TextAnchor(1, 0),
      extent: TextAnchor(4, 12),
    );
    const different = TextSelectionRange(
      anchor: TextAnchor(1, 0),
      extent: TextAnchor(4, 13),
    );

    expect(first, same);
    expect(first == different, isFalse);
  });
}
