import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// Covers ADR 0053: CSS `font-family` list parsing and host-level fallback.
///
/// CJK text renders as tofu boxes when the resolved family is Latin-only and
/// no fallback is declared, so these invariants matter beyond cosmetics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextStyle _styleOf(
    WeftDocumentSnapshot document, {
    List<String>? fallback,
  }) {
    final layout = const WeftLayoutEngine()
        .layout(document, width: 320, fontFamilyFallback: fallback);
    addTearDown(layout.dispose);
    final command = layout.commands.whereType<WeftTextPaintCommand>().first;
    return _firstSpan(command).style!;
  }

  group('font-family list parsing', () {
    test('named families keep their order, generics do not become families',
        () {
      final document = const WeftNormalizer().normalize(
        '<style>p { font-family: "Noto Sans CJK SC", sans-serif; }</style>'
        '<p>中文 text</p>',
        id: 'named-list',
      );

      final style = _styleOf(document);
      expect(style.fontFamily, 'Noto Sans CJK SC');
      // `sans-serif` is a generic keyword, not a lookupable family.
      expect(style.fontFamilyFallback ?? const <String>[], isEmpty);
    });

    test('the first named family wins over a later one', () {
      final document = const WeftNormalizer().normalize(
        '<style>p { font-family: Georgia, "Times New Roman"; }</style>'
        '<p>text</p>',
        id: 'two-named',
      );

      final style = _styleOf(document);
      expect(style.fontFamily, 'Georgia');
      expect(style.fontFamilyFallback, ['Times New Roman']);
    });

    test('a leading generic name is dropped so the default family applies', () {
      final document = const WeftNormalizer().normalize(
        '<style>p { font-family: sans-serif; }</style><p>text</p>',
        id: 'generic-only',
      );

      final style = _styleOf(document);
      expect(style.fontFamily, isNull);
      expect(style.fontFamilyFallback ?? const <String>[], isEmpty);
    });

    test('monospace and serif keep their pre-existing mapping', () {
      final mono = _styleOf(
        const WeftNormalizer().normalize(
            '<style>p { font-family: monospace; }</style><p>x</p>',
            id: 'mono'),
      );
      expect(mono.fontFamily, 'monospace');

      final serif = _styleOf(
        const WeftNormalizer().normalize(
            '<style>p { font-family: serif; }</style><p>x</p>',
            id: 'serif'),
      );
      expect(serif.fontFamily, 'serif');
    });
  });

  group('host-level fallback', () {
    test('is applied when the author names no family', () {
      final document =
          const WeftNormalizer().normalize('<p>中文 text</p>', id: 'host-only');

      final style = _styleOf(document, fallback: const ['CJK Face']);
      expect(style.fontFamilyFallback, ['CJK Face']);
    });

    test('is appended after families the author did name', () {
      final document = const WeftNormalizer().normalize(
        '<style>p { font-family: Georgia, "Times New Roman"; }</style>'
        '<p>中文 text</p>',
        id: 'host-appended',
      );

      final style = _styleOf(document, fallback: const ['CJK Face']);
      expect(style.fontFamilyFallback, ['Times New Roman', 'CJK Face']);
    });

    test('does not duplicate a family the author already named', () {
      final document = const WeftNormalizer().normalize(
        '<style>p { font-family: "CJK Face"; }</style><p>中文 text</p>',
        id: 'host-dedupe',
      );

      final style = _styleOf(document, fallback: const ['CJK Face']);
      expect(style.fontFamily, 'CJK Face');
      expect(style.fontFamilyFallback ?? const <String>[], isEmpty);
    });

    test('is inherited by descendants', () {
      final document = const WeftNormalizer().normalize(
        '<div><p>中文 text</p></div>',
        id: 'host-inherited',
      );

      final style = _styleOf(document, fallback: const ['CJK Face']);
      expect(style.fontFamilyFallback, ['CJK Face']);
    });
  });

  group('style cache keyed on the fallback list', () {
    test('a changed fallback list invalidates the cached styles', () {
      final document =
          const WeftNormalizer().normalize('<p>中文 text</p>', id: 'cache-key');

      final first = const WeftLayoutEngine().layout(document,
          width: 320, fontFamilyFallback: const ['First Face']);
      addTearDown(first.dispose);
      expect(_spanStyleOf(first).fontFamilyFallback, ['First Face']);

      // Same snapshot instance: without the fallback in the cache key the
      // second layout would inherit the first pass's styles.
      final second = const WeftLayoutEngine().layout(
        document,
        width: 320,
        fontFamilyFallback: const ['Second Face'],
        previous: first,
      );
      addTearDown(second.dispose);
      expect(_spanStyleOf(second).fontFamilyFallback, ['Second Face']);
    });
  });
}

TextStyle _spanStyleOf(WeftLayoutResult layout) {
  final command = layout.commands.whereType<WeftTextPaintCommand>().first;
  return _firstSpan(command).style!;
}

TextSpan _firstSpan(WeftTextPaintCommand command) {
  final root = command.painter.text! as TextSpan;
  return root.children!.whereType<TextSpan>().first;
}
