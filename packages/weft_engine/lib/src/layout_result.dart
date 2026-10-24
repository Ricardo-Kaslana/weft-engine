import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

final class WeftLayoutBox {
  const WeftLayoutBox({required this.nodeId, required this.rect});

  final int nodeId;
  final ui.Rect rect;
}

sealed class WeftPaintCommand {
  const WeftPaintCommand({required this.nodeId});

  final int nodeId;

  void paint(ui.Canvas canvas, ui.Offset origin);

  void dispose();
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
}

final class WeftLayoutResult {
  WeftLayoutResult({
    required this.size,
    required Iterable<WeftLayoutBox> boxes,
    required Iterable<WeftPaintCommand> commands,
  })  : boxes = List<WeftLayoutBox>.unmodifiable(boxes),
        commands = List<WeftPaintCommand>.unmodifiable(commands);

  final ui.Size size;
  final List<WeftLayoutBox> boxes;
  final List<WeftPaintCommand> commands;

  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final command in commands) {
      command.dispose();
    }
  }
}
