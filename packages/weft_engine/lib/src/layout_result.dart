import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

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
  });

  final TextPainter painter;
  final ui.Offset offset;

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
    );
  }
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
  })  : boxes = List<WeftLayoutBox>.unmodifiable(boxes),
        commands = List<WeftPaintCommand>.unmodifiable(commands),
        links = List<WeftLinkRegion>.unmodifiable(links);

  final ui.Size size;
  final List<WeftLayoutBox> boxes;
  final List<WeftPaintCommand> commands;
  final List<WeftLinkRegion> links;

  WeftLinkRegion? linkAt(ui.Offset position) {
    for (final link in links.reversed) {
      if (link.contains(position)) return link;
    }
    return null;
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
