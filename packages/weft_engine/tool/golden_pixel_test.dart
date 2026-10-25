import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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

      final imageSources = _assetImageSources(document);
      if (imageSources.isNotEmpty) {
        // File decoding runs on real timers that the fake-async clock never
        // fires. Decode the fixtures up front and hand the surface providers
        // that complete synchronously.
        await tester.runAsync(() => _decodeAssetImages(imageSources));
      }
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
                  imageResolver: imageSources.isEmpty
                      ? null
                      : (request) {
                          final image = _decodedImages[request.src];
                          return image == null ? null : _PrecodedImage(image);
                        },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (imageSources.isNotEmpty) {
        // Precoded providers complete on microtasks; keep pumping until the
        // surface has re-laid out with the resolved images.
        await tester.pumpAndSettle(const Duration(milliseconds: 10));
      }

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

/// Collects the `assets/<name>` image sources referenced by a pixel case.
Set<String> _assetImageSources(WeftDocumentSnapshot document) {
  final result = <String>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      final src = node.tag == 'img' ? node.attribute('src') : null;
      if (src != null && src.startsWith('assets/')) {
        result.add(src);
      }
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  final body = document.body;
  if (body != null) visit(body);
  return result;
}

final _decodedImages = <String, ui.Image>{};

Future<void> _decodeAssetImages(Set<String> sources) async {
  final root = _workspaceRoot();
  for (final src in sources) {
    if (_decodedImages.containsKey(src)) continue;
    final bytes = await File('${root.path}/conformance/$src').readAsBytes();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    _decodedImages[src] = await completer.future;
  }
}

/// An [ImageProvider] that hands out an already decoded image, so the surface
/// never needs real async decoding inside the fake clock.
final class _PrecodedImage extends ImageProvider<_PrecodedImage> {
  const _PrecodedImage(this.image);

  final ui.Image image;

  @override
  Future<_PrecodedImage> obtainKey(ImageConfiguration configuration) async {
    return this;
  }

  @override
  ImageStreamCompleter loadImage(
    _PrecodedImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: key.image)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _PrecodedImage && other.image == image;

  @override
  int get hashCode => identityHashCode(image);
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
