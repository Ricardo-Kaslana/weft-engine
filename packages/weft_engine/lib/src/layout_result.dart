import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'text_index.dart';

final class WeftLayoutBox {
  const WeftLayoutBox({required this.nodeId, required this.rect});

  final int nodeId;
  final ui.Rect rect;
}

final class WeftLinkRegion {
  WeftLinkRegion({
    required this.nodeId,
    required this.href,
    required this.text,
    required Iterable<ui.Rect> rects,
  }) : rects = List<ui.Rect>.unmodifiable(rects);

  final int nodeId;
  final String href;
  final String text;
  final List<ui.Rect> rects;

  bool contains(ui.Offset position) {
    return rects.any((rect) => rect.contains(position));
  }

  WeftLinkRegion shift(ui.Offset offset) {
    return WeftLinkRegion(
      nodeId: nodeId,
      href: href,
      text: text,
      rects: rects.map((rect) => rect.shift(offset)),
    );
  }
}

sealed class WeftPaintCommand {
  const WeftPaintCommand({required this.nodeId});

  final int nodeId;

  void paint(ui.Canvas canvas, ui.Offset origin);

  void dispose();

  /// Returns an equivalent command translated by [offset]. Used by table
  /// layout, which lays cells out at the origin before row heights are known
  /// and shifts them into place afterwards.
  WeftPaintCommand shift(ui.Offset offset);
}

final class WeftRectPaintCommand extends WeftPaintCommand {
  const WeftRectPaintCommand({
    required super.nodeId,
    required this.rect,
    required this.color,
  });

  final ui.Rect rect;
  final ui.Color color;

  @override
  void paint(ui.Canvas canvas, ui.Offset origin) {
    canvas.drawRect(rect.shift(origin), Paint()..color = color);
  }

  @override
  void dispose() {}

  @override
  WeftPaintCommand shift(ui.Offset offset) {
    return WeftRectPaintCommand(
      nodeId: nodeId,
      rect: rect.shift(offset),
      color: color,
    );
  }
}

final class WeftTextPaintCommand extends WeftPaintCommand {
  const WeftTextPaintCommand({
    required super.nodeId,
    required this.painter,
    required this.offset,
    this.runs = const [],
  });

  final TextPainter painter;
  final ui.Offset offset;

  /// Mapping from painter text ranges back to their source document text
  /// nodes. Selection geometry resolves node-anchored ranges through these.
  final List<WeftTextPainterRun> runs;

  @override
  void paint(ui.Canvas canvas, ui.Offset origin) {
    painter.paint(canvas, offset + origin);
  }

  @override
  void dispose() {
    painter.dispose();
  }

  @override
  WeftPaintCommand shift(ui.Offset shift) {
    return WeftTextPaintCommand(
      nodeId: nodeId,
      painter: painter,
      offset: offset + shift,
      runs: runs,
    );
  }
}

/// A contiguous text range inside one [WeftTextPaintCommand].
///
/// [painterStart]/[painterEnd] index the command's painter text;
/// [nodeStart]/[nodeEnd] index the source node's painted text (the node's
/// text after whitespace collapsing), so the same node keeps stable
/// coordinates across line-split painters.
final class WeftTextPainterRun {
  const WeftTextPainterRun({
    required this.nodeId,
    required this.painterStart,
    required this.painterEnd,
    required this.nodeStart,
    required this.nodeEnd,
  });

  final NodeId nodeId;
  final int painterStart;
  final int painterEnd;
  final int nodeStart;
  final int nodeEnd;
}

final class WeftImagePaintCommand extends WeftPaintCommand {
  const WeftImagePaintCommand({
    required super.nodeId,
    required this.image,
    required this.destination,
  });

  final ui.Image image;
  final ui.Rect destination;

  @override
  void paint(ui.Canvas canvas, ui.Offset origin) {
    final source = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // Browsers snap replaced content to device pixels before rasterizing.
    // A 1:1 blit at a fractional offset would instead resample every texel,
    // so snap the destination when the source maps without scaling.
    var target = destination.shift(origin);
    if (target.width == source.width && target.height == source.height) {
      target = ui.Rect.fromLTRB(
        target.left.roundToDouble(),
        target.top.roundToDouble(),
        target.right.roundToDouble(),
        target.bottom.roundToDouble(),
      );
    }
    canvas.drawImageRect(
      image,
      source,
      target,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  void dispose() {}

  @override
  WeftPaintCommand shift(ui.Offset offset) {
    return WeftImagePaintCommand(
      nodeId: nodeId,
      image: image,
      destination: destination.shift(offset),
    );
  }
}

final class WeftLayoutResult {
  WeftLayoutResult({
    required this.size,
    required Iterable<WeftLayoutBox> boxes,
    required Iterable<WeftPaintCommand> commands,
    required Iterable<WeftLinkRegion> links,
    this.textIndex,
  })  : boxes = List<WeftLayoutBox>.unmodifiable(boxes),
        commands = List<WeftPaintCommand>.unmodifiable(commands),
        links = List<WeftLinkRegion>.unmodifiable(links);

  final ui.Size size;
  final List<WeftLayoutBox> boxes;
  final List<WeftPaintCommand> commands;
  final List<WeftLinkRegion> links;

  /// The logical text model for this layout, used to resolve selection
  /// anchors across node boundaries.
  final WeftTextIndex? textIndex;

  WeftLinkRegion? linkAt(ui.Offset position) {
    for (final link in links.reversed) {
      if (link.contains(position)) return link;
    }
    return null;
  }

  /// Visual rectangles covering the painted text of [nodeId] between
  /// node-local [start] and [end] offsets.
  List<ui.Rect> textRectsForNode(NodeId nodeId, int start, int end) {
    if (end <= start) return const [];
    final rects = <ui.Rect>[];
    for (final command in commands) {
      if (command is! WeftTextPaintCommand) continue;
      for (final run in command.runs) {
        if (run.nodeId != nodeId) continue;
        final overlapStart = math.max(start, run.nodeStart);
        final overlapEnd = math.min(end, run.nodeEnd);
        if (overlapEnd <= overlapStart) continue;
        final painterStart = run.painterStart + overlapStart - run.nodeStart;
        final painterEnd = run.painterStart + overlapEnd - run.nodeStart;
        final boxes = command.painter.getBoxesForSelection(
          TextSelection(baseOffset: painterStart, extentOffset: painterEnd),
        );
        for (final box in boxes) {
          final rect = ui.Rect.fromLTRB(
            box.left + command.offset.dx,
            box.top + command.offset.dy,
            box.right + command.offset.dx,
            box.bottom + command.offset.dy,
          );
          if (rect.width > 0 && rect.height > 0) rects.add(rect);
        }
      }
    }
    return rects;
  }

  /// Visual rectangles for a selection between two anchors, resolved through
  /// the logical text index. Anchors may sit in different nodes.
  List<ui.Rect> selectionRects(TextSelectionRange selection) {
    final index = textIndex;
    if (index == null || selection.isCollapsed) return const [];
    final ordered = index.order(selection);
    if (ordered == null) return const [];
    final rects = <ui.Rect>[];
    for (final (entry, nodeStart, nodeEnd) in index.between(
      ordered.$1,
      ordered.$2,
    )) {
      rects.addAll(textRectsForNode(entry.nodeId, nodeStart, nodeEnd));
    }
    return rects;
  }

  /// The logical text between two anchors, with block boundaries rendered as
  /// newlines. Suitable for clipboard copy.
  String? selectionText(TextSelectionRange selection) {
    final index = textIndex;
    if (index == null || selection.isCollapsed) return null;
    final ordered = index.order(selection);
    if (ordered == null) return null;
    return index.textBetween(ordered.$1, ordered.$2);
  }

  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final command in commands) {
      command.dispose();
    }
  }
}
