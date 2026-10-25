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

  /// The layout-space rectangle this command paints into. Must fully contain
  /// every pixel the command can produce: chunked rendering culls chunks
  /// against the visible window through these bounds.
  ui.Rect get bounds;
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
  ui.Rect get bounds => rect;

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
  ui.Rect get bounds =>
      ui.Rect.fromLTWH(offset.dx, offset.dy, painter.width, painter.height);

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
  ui.Rect get bounds => destination;

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

/// A paint group covering one top-level body child, or the body chrome.
///
/// Chunking lives at the rendering layer: the layout engine keeps emitting one
/// flat command list, and [WeftChunk.partition] only reads the document tree to
/// map each command's node back to its top-level body child.
final class WeftChunk {
  WeftChunk({required this.key, required Iterable<WeftPaintCommand> commands})
      : commands = List<WeftPaintCommand>.unmodifiable(commands),
        bounds = _unionBounds(commands);

  /// Key of the chrome chunk: body background/border commands and any command
  /// whose node does not map to a top-level body child. Chrome is always
  /// painted, so renderers must never cull it. Top-level body children use
  /// their zero-based ordinal as the key, which cannot collide with this.
  static const int chromeKey = -1;

  final int key;

  /// Paints in document order, exactly as the flat command list would paint
  /// this group's slice.
  final List<WeftPaintCommand> commands;

  /// Union of the commands' [WeftPaintCommand.bounds]; fully contains every
  /// pixel the chunk can paint.
  final ui.Rect bounds;

  bool get isChrome => key == chromeKey;

  static ui.Rect _unionBounds(Iterable<WeftPaintCommand> commands) {
    var bounds = ui.Rect.zero;
    var first = true;
    for (final command in commands) {
      bounds = first ? command.bounds : bounds.expandToInclude(command.bounds);
      first = false;
    }
    return bounds;
  }

  /// Groups [commands] by the top-level body child that owns each command's
  /// node. Grouping never assumes the per-chunk commands are contiguous in
  /// [commands]; an assertion verifies they are, because the renderer paints
  /// chunks in ordinal order after the chrome chunk and relies on that order
  /// matching the flat list.
  static List<WeftChunk> partition({
    required WeftDocumentSnapshot document,
    required List<WeftPaintCommand> commands,
  }) {
    final body = document.body;
    final chrome = _ChunkAccumulator();
    final byOrdinal = <int, _ChunkAccumulator>{};
    if (body == null) {
      for (var i = 0; i < commands.length; i++) {
        chrome.add(commands[i], i);
      }
    } else {
      final ordinalByNode = <int, int>{};
      var ordinal = 0;
      for (final child in body.children) {
        void visit(WeftNode node) {
          ordinalByNode[node.id] = ordinal;
          if (node is WeftElement) {
            for (final grandchild in node.children) {
              visit(grandchild);
            }
          }
        }

        visit(child);
        ordinal++;
      }
      for (var i = 0; i < commands.length; i++) {
        final command = commands[i];
        final groupOrdinal = ordinalByNode[command.nodeId];
        if (groupOrdinal == null) {
          // Body chrome (nodeId == body.id) and unmapped commands always
          // paint, so they share the chrome chunk.
          chrome.add(command, i);
        } else {
          byOrdinal.putIfAbsent(groupOrdinal, _ChunkAccumulator.new).add(
                command,
                i,
              );
        }
      }
    }

    final chunks = <WeftChunk>[];
    if (chrome.isNotEmpty) {
      // Chrome paints first: it is a prefix of the command list in practice.
      chunks.add(chrome.build(chromeKey));
    }
    final ordinals = byOrdinal.keys.toList()..sort();
    for (final ordinal in ordinals) {
      chunks.add(byOrdinal[ordinal]!.build(ordinal));
    }
    return chunks;
  }
}

/// Accumulates one chunk's commands plus their first and last index in the
/// flat command list for the contiguity assertion.
final class _ChunkAccumulator {
  final List<WeftPaintCommand> _commands = <WeftPaintCommand>[];
  int _firstIndex = -1;
  int _lastIndex = -1;

  bool get isNotEmpty => _commands.isNotEmpty;

  void add(WeftPaintCommand command, int index) {
    _commands.add(command);
    _firstIndex = _firstIndex < 0 ? index : _firstIndex;
    _lastIndex = index;
  }

  WeftChunk build(int key) {
    assert(
      key == WeftChunk.chromeKey ||
          _lastIndex - _firstIndex + 1 == _commands.length,
      'Commands of chunk $key are not contiguous in the command list: '
      'indices $_firstIndex..$_lastIndex hold ${_commands.length} commands.',
    );
    return WeftChunk(key: key, commands: _commands);
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

  /// Width of the caret bar produced by [caretRectForAnchor].
  static const double caretWidth = 2;

  /// The caret rectangle for a collapsed-selection [anchor] in document
  /// coordinates: a [caretWidth]-wide bar at the left edge of the anchor
  /// position's glyph box, spanning the box's full height.
  ///
  /// Returns null when the anchor maps to no painted text — an unknown node
  /// or an offset at the very end of a node's text — mirroring the safe-drop
  /// semantics of the selection model (ADR 0013) instead of clamping.
  ui.Rect? caretRectForAnchor(TextAnchor anchor) {
    final rects =
        textRectsForNode(anchor.nodeId, anchor.offset, anchor.offset + 1);
    if (rects.isEmpty) return null;
    final first = rects.first;
    return ui.Rect.fromLTRB(
      first.left,
      first.top,
      first.left + caretWidth,
      first.bottom,
    );
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

  /// Resolves the selection anchor under [position] in document coordinates,
  /// or null when the point hits no painted text.
  ///
  /// Text commands are scanned back-to-front so later content (float-wrapped
  /// lines, later table cells) wins. A point only anchors when it falls
  /// inside a command's painted bounds and maps into a run whose node still
  /// resolves in the logical text index; points in the gaps between blocks
  /// hit nothing.
  TextAnchor? anchorAt(ui.Offset position) {
    final hit = _textHitAt(position);
    if (hit == null) return null;
    return _anchorForPainterOffset(hit.$1, hit.$2);
  }

  /// Resolves the whole-word selection under [position] in document
  /// coordinates — anchor at the word start, extent at the word end — or
  /// null when the point hits no painted text.
  TextSelectionRange? wordSelectionAt(ui.Offset position) {
    final hit = _textHitAt(position);
    if (hit == null) return null;
    final command = hit.$1;
    final boundary = command.painter.getWordBoundary(
      TextPosition(offset: hit.$2),
    );
    if (boundary.end <= boundary.start) return null;
    final start = _anchorForPainterOffset(command, boundary.start);
    final end = _anchorForPainterOffset(command, boundary.end);
    if (start == null || end == null) return null;
    return TextSelectionRange(anchor: start, extent: end);
  }

  /// Locates the text command and painter offset under [position], or null.
  (WeftTextPaintCommand, int)? _textHitAt(ui.Offset position) {
    if (textIndex == null) return null;
    for (final command in commands.reversed) {
      if (command is! WeftTextPaintCommand) continue;
      final local = position - command.offset;
      // getPositionForOffset clamps distant points onto the text, so only
      // points inside the painter's laid-out bounds count as hits.
      if (local.dx < 0 ||
          local.dy < 0 ||
          local.dx > command.painter.width ||
          local.dy > command.painter.height) {
        continue;
      }
      final painterOffset = command.painter.getPositionForOffset(local).offset;
      if (_runForPainterOffset(command, painterOffset) == null) continue;
      return (command, painterOffset);
    }
    return null;
  }

  /// The run that owns [painterOffset], preferring runs whose node still
  /// resolves in the logical text index.
  ///
  /// Runs tile the command's painter text contiguously, so an offset on a
  /// run seam belongs to two runs. Hard-break runs own no logical text
  /// entry, so their seams fall back to the neighboring text run instead of
  /// producing an anchor the index cannot resolve.
  WeftTextPainterRun? _runForPainterOffset(
    WeftTextPaintCommand command,
    int painterOffset,
  ) {
    final index = textIndex;
    if (index == null) return null;
    WeftTextPainterRun? seamFallback;
    for (final run in command.runs) {
      if (painterOffset < run.painterStart || painterOffset > run.painterEnd) {
        continue;
      }
      if (!index.entryByNode.containsKey(run.nodeId)) continue;
      if (painterOffset < run.painterEnd) return run;
      seamFallback ??= run;
    }
    return seamFallback;
  }

  TextAnchor? _anchorForPainterOffset(
    WeftTextPaintCommand command,
    int painterOffset,
  ) {
    final run = _runForPainterOffset(command, painterOffset);
    if (run == null) return null;
    return TextAnchor(
      run.nodeId,
      run.nodeStart + painterOffset - run.painterStart,
    );
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
