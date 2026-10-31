import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = _workspaceRoot();
  final referencePath =
      '${root.path}/conformance/reference/rtl_paragraph.geometry.json';
  final reference = jsonDecode(File(referencePath).readAsStringSync())
      as Map<String, dynamic>;

  setUpAll(() async {
    await _loadFonts(root);
  });

  // The `data-geo` attributes are Chrome-side anchors; the normalized
  // snapshot drops them, so elements are located by a stable text prefix.
  WeftElement elementFor(WeftDocumentSnapshot document, String prefix) {
    WeftElement? found;
    void visit(WeftNode node) {
      if (found != null) return;
      if (node is WeftElement) {
        final buffer = StringBuffer();
        for (final child in node.children) {
          if (child is WeftText) buffer.write(child.text);
        }
        if (buffer.toString().trim().startsWith(prefix)) {
          found = node;
          return;
        }
        for (final child in node.children) {
          visit(child);
        }
      }
    }

    visit(document.body!);
    expect(found, isNotNull, reason: 'missing element "$prefix"');
    return found!;
  }

  ui.Rect textUnion(WeftLayoutResult result, WeftElement element) {
    ui.Rect? union;
    void visit(WeftNode node) {
      if (node is WeftText) {
        for (final rect
            in result.textRectsForNode(node.id, 0, node.text.length)) {
          union = union == null ? rect : union!.expandToInclude(rect);
        }
        return;
      }
      if (node is! WeftElement || node.tag == 'img') return;
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(element);
    expect(union, isNotNull, reason: 'no painted text found');
    return union!;
  }

  test('RTL paragraph geometry matches the Chrome reference edges', () {
    final source = File(
      '${root.path}/conformance/cases/rtl_paragraph.html',
    ).readAsStringSync();
    final document = const WeftNormalizer().normalize(
      source,
      id: 'rtl-paragraph-geometry',
    );
    expect(document.supportReport.canRender, isTrue);
    final result = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(result.dispose);

    final chrome = reference['words'] as Map<String, dynamic>;

    double chromeEdge(String key, {required bool right}) {
      double edge = right ? double.negativeInfinity : double.infinity;
      for (final word in chrome[key]! as List<dynamic>) {
        for (final rect
            in (word as Map<String, dynamic>)['rects'] as List<dynamic>) {
          final value =
              ((rect as Map<String, dynamic>)[right ? 'right' : 'left'] as num)
                  .toDouble();
          edge = right
              ? (value > edge ? value : edge)
              : (value < edge ? value : edge);
        }
      }
      return edge;
    }

    final keysByPrefix = <String, bool>{
      'Latin control paragraph': false,
      'مرحبا بالعالم من محرك ويفت': true,
      'نص عربي مع mixed': true,
      'Latin paragraph inside': false,
      'فقرة ترث الاتجاه': true,
      'فقرات تعتمد على اتجاه': true,
      'مرحبا auto detection': true,
      'auto detection with Latin': false,
      'عنصر قائمة باتجاه': true,
      'second item': true,
    };

    for (final entry in keysByPrefix.entries) {
      final element = elementFor(document, entry.key);
      final union = textUnion(result, element);
      final expected = chromeEdge(
        _chromeKeyFor(entry.key),
        right: entry.value,
      );
      final actual = entry.value ? union.right : union.left;
      expect(
        actual,
        moreOrLessEquals(expected, epsilon: 2),
        reason: '${entry.key} ${entry.value ? 'right' : 'left'} edge vs Chrome',
      );
    }
  });
}

String _chromeKeyFor(String prefix) {
  const map = <String, String>{
    'Latin control paragraph': 'ltr-control',
    'مرحبا بالعالم من محرك ويفت': 'rtl-plain',
    'نص عربي مع mixed': 'rtl-mixed',
    'Latin paragraph inside': 'nested-ltr',
    'فقرة ترث الاتجاه': 'nested-inherit',
    'فقرات تعتمد على اتجاه': 'css-rtl',
    'مرحبا auto detection': 'auto-rtl',
    'auto detection with Latin': 'auto-ltr',
    'عنصر قائمة باتجاه': 'rtl-li',
    'second item': 'rtl-li2',
  };
  return map[prefix]!;
}

Future<void> _loadFonts(Directory root) async {
  final fontDir = '${root.path}/conformance/fonts';
  final roboto = FontLoader('WeftRoboto');
  for (final file in const [
    'Roboto-Regular.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'Roboto-BoldItalic.ttf',
  ]) {
    final bytes = await File('$fontDir/$file').readAsBytes();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await roboto.load();
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
              RegExp(r'^workspace:', multiLine: true),
            )) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find the Weft workspace root.');
    }
    current = parent;
  }
}
