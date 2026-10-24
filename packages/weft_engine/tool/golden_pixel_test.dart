import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  final root = _workspaceRoot();
  final manifest = jsonDecode(
    File('${root.path}/conformance/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (manifest['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((item) => item['pixel'] == true)
      .toList();
  final goldenDir = Directory(
    '${root.path}/conformance/goldens/flutter/images',
  );

  setUpAll(() async {
    expect(cases, isNotEmpty);
    goldenDir.createSync(recursive: true);
    await _loadFonts(root);
  });

  for (final item in cases) {
    final id = item['id'] as String;
    testWidgets('pixel golden $id', (tester) async {
      final width = (item['width'] as num).toDouble();
      final height = (item['height'] as num).toDouble();
      final source = File(
        '${root.path}/conformance/${item['file']}',
      ).readAsStringSync();
      final document = const WeftNormalizer().normalize(
        source,
        id: 'golden-$id',
      );
      expect(
        document.supportReport.canRender,
        isTrue,
        reason: 'Pixel case $id requested fallback.',
      );

      await tester.binding.setSurfaceSize(Size(width, height));
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.expand(
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: WeftSurface(
                  document: document,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byKey(boundaryKey),
        matchesGoldenFile(
          '../../../conformance/goldens/flutter/images/$id.png',
        ),
      );
      await tester.binding.setSurfaceSize(null);
    });
  }
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
    roboto.addFont(_fontData('$fontDir/$file'));
  }
  await roboto.load();

  final mono = FontLoader('WeftRobotoMono');
  for (final file in const [
    'RobotoMono-Regular.ttf',
    'RobotoMono-Bold.ttf',
  ]) {
    mono.addFont(_fontData('$fontDir/$file'));
  }
  await mono.load();
}

Future<ByteData> _fontData(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(bytes);
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
