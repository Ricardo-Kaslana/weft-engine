// Layout dump driver. `dart run` cannot execute Flutter packages directly,
// so this runs through the test harness:
//
//   cd packages/weft_engine
//   flutter test tool/dump_layout_test.dart --no-pub  # uses WEFT_DUMP env vars
//
// Environment:
//   WEFT_DUMP_FILE   path to an HTML file (usually a conformance case)
//   WEFT_DUMP_WIDTH  viewport width, default 360
//   WEFT_DUMP_DIFF   1 = print a per-element diff vs the Chrome reference
//   WEFT_DUMP_RUNS   1 = include painter->node run mappings
//   WEFT_DUMP_OUT    output file, defaults to build/dump_layout.txt
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

Future<void> main() async {
  final root = _workspaceRoot();
  final htmlPath = Platform.environment['WEFT_DUMP_FILE'];
  if (htmlPath == null) {
    fail('Set WEFT_DUMP_FILE to the HTML file to dump.');
  }
  final width =
      double.tryParse(Platform.environment['WEFT_DUMP_WIDTH'] ?? '') ?? 360;
  final diff = Platform.environment['WEFT_DUMP_DIFF'] == '1';
  final showRuns = Platform.environment['WEFT_DUMP_RUNS'] == '1';
  final outPath = Platform.environment['WEFT_DUMP_OUT'] ??
      '${root.path}/build/dump_layout.txt';

  test('dump layout', () async {
    await _loadFonts(root);
    final source = File(htmlPath).readAsStringSync();
    final document = const WeftNormalizer().normalize(source, id: 'dump');
    final images = await _resolveImages(root, document);
    final layout = const WeftLayoutEngine().layout(
      document,
      width: width,
      images: images,
    );
    addTearDown(layout.dispose);

    final buffer = StringBuffer()
      ..writeln('size: ${layout.size}')
      ..writeln(
        'issues: ${document.supportReport.issues.map((issue) => issue.code).join(', ')}',
      );

    final tagById = _tagsById(document);
    for (final box in layout.boxes) {
      buffer.writeln('box ${tagById[box.nodeId] ?? '?'} ${box.rect}');
    }
    for (final command in layout.commands) {
      if (command is! WeftTextPaintCommand) continue;
      final text = command.painter.text?.toPlainText() ?? '';
      if (text.isEmpty) continue;
      buffer.writeln(
        'line ${tagById[command.nodeId] ?? '?'} '
        'dx=${command.offset.dx.toStringAsFixed(2)} '
        'dy=${command.offset.dy.toStringAsFixed(2)} '
        'w=${command.painter.width.toStringAsFixed(1)} '
        '${text.length > 48 ? text.substring(0, 48) : text}',
      );
      if (showRuns) {
        for (final run in command.runs) {
          buffer.writeln(
            '  run node=${run.nodeId} '
            'painter=[${run.painterStart},${run.painterEnd}) '
            'node=[${run.nodeStart},${run.nodeEnd})',
          );
        }
      }
    }
    final index = layout.textIndex;
    if (index != null) {
      buffer.writeln('logical text: ${index.text}');
    }

    if (diff) {
      final caseId = _caseIdFromPath(htmlPath);
      final referenceFile = File(
        '${root.path}/conformance/reference/$caseId.geometry.json',
      );
      if (!referenceFile.existsSync()) {
        fail(
          'No reference at ${referenceFile.path}. Generate with '
          'node tool/browser_references.mjs --case $caseId --emit-reference',
        );
      }
      final reference =
          jsonDecode(referenceFile.readAsStringSync()) as Map<String, dynamic>;
      final elements = reference['elements'] as Map<String, dynamic>;
      final boxesByNode = <int, Rect>{
        for (final box in layout.boxes) box.nodeId: box.rect,
      };
      final order = _documentOrderIds(document, elements);
      buffer
        ..writeln()
        ..writeln('--- diff vs Chrome ($caseId) ---');
      var position = 0;
      for (final entry in elements.entries) {
        final value = entry.value as Map<String, dynamic>;
        final expected = Rect.fromLTWH(
          (value['left'] as num).toDouble(),
          (value['top'] as num).toDouble(),
          (value['width'] as num).toDouble(),
          (value['height'] as num).toDouble(),
        );
        final actual =
            position < order.length ? boxesByNode[order[position]] : null;
        position += 1;
        if (actual == null) {
          buffer.writeln('${entry.key.padRight(14)} NO WEFT BOX');
          continue;
        }
        final deltas = [
          actual.left - expected.left,
          actual.top - expected.top,
          actual.width - expected.width,
          actual.height - expected.height,
        ];
        final worst =
            deltas.map((value) => value.abs()).reduce((a, b) => a > b ? a : b);
        final flag = worst <= 0.5 ? 'ok' : (worst <= 1.5 ? '~' : '!!');
        buffer.writeln(
          '${entry.key.padRight(14)} $flag '
          'dL=${deltas[0].toStringAsFixed(2)} '
          'dT=${deltas[1].toStringAsFixed(2)} '
          'dW=${deltas[2].toStringAsFixed(2)} '
          'dH=${deltas[3].toStringAsFixed(2)}',
        );
      }
    }

    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(buffer.toString());
    // ignore: avoid_print
    print('dumped to $outPath');
  });
}

String _caseIdFromPath(String htmlPath) {
  final file = htmlPath.replaceAll('\\', '/').split('/').last;
  return file.endsWith('.html') ? file.substring(0, file.length - 5) : file;
}

Future<Map<int, ui.Image>> _resolveImages(
  Directory root,
  WeftDocumentSnapshot document,
) async {
  final images = <int, ui.Image>{};
  final body = document.body;
  if (body == null) return images;
  Future<void> visit(WeftNode node) async {
    if (node is WeftElement) {
      final src = node.tag == 'img' ? node.attribute('src') : null;
      if (src != null && src.startsWith('assets/')) {
        final bytes = await File('${root.path}/conformance/$src').readAsBytes();
        final completer = Completer<ui.Image>();
        ui.decodeImageFromList(bytes, completer.complete);
        images[node.id] = await completer.future;
      }
      for (final child in node.children) {
        await visit(child);
      }
    }
  }

  await visit(body);
  return images;
}

Map<int, String> _tagsById(WeftDocumentSnapshot document) {
  final result = <int, String>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      result[node.id] = node.tag;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  final body = document.body;
  if (body != null) visit(body);
  return result;
}

/// Elements with layout boxes in document order, restricted to the tags the
/// reference marks, so the sequences stay 1:1 with the extraction script.
List<int> _documentOrderIds(
  WeftDocumentSnapshot document,
  Map<String, dynamic> elements,
) {
  final markedTags = elements.values
      .map((value) => (value as Map<String, dynamic>)['tag'] as String)
      .toSet();
  final order = <int>[];
  void visit(WeftNode node) {
    if (node is WeftElement) {
      if (markedTags.contains(node.tag)) {
        order.add(node.id);
      }
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  final body = document.body;
  if (body != null) visit(body);
  return order;
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
  final mono = FontLoader('WeftRobotoMono');
  for (final file in const [
    'RobotoMono-Regular.ttf',
    'RobotoMono-Bold.ttf',
  ]) {
    final bytes = await File('$fontDir/$file').readAsBytes();
    mono.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await mono.load();
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
