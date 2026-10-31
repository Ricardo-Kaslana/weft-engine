import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'line_break_rules.dart';
import 'tag_renderer.dart';
import 'text_index.dart';

/// The bounding rectangle of one laid-out box, in document coordinates.
final class WeftLayoutBox {
  /// Creates a box for [nodeId] at [rect].
  const WeftLayoutBox({required this.nodeId, required this.rect});

  /// Id of the document node that produced this box.
  final int nodeId;

  /// The box's rectangle in document coordinates.
  final ui.Rect rect;
}

/// Hit region for one laid-out custom tag (ADR 0033).
final class WeftTagRegion {
  /// Creates a hit region for one custom tag.
  const WeftTagRegion({
    required this.nodeId,
    required this.tag,
    required this.rect,
    this.label,
  });

  /// Id of the custom tag element.
  final int nodeId;

  /// The custom element's tag name, e.g. `weft-badge`.
  final String tag;

  /// The tag's content-box rectangle in layout coordinates.
  final ui.Rect rect;

  /// Accessibility label supplied by the renderer, `aria-label`, or the tag.
  final String? label;

  /// Whether [position] falls inside this region's rectangle.
  bool contains(ui.Offset position) => rect.contains(position);
}

/// Hit region for one hyperlink: the target, painted text, and the
/// rectangles its runs cover.
final class WeftLinkRegion {
  /// Creates a link region covering [rects].
  WeftLinkRegion({
    required this.nodeId,
    required this.href,
    required this.text,
    required Iterable<ui.Rect> rects,
  }) : rects = List<ui.Rect>.unmodifiable(rects);

  /// Id of the anchor element.
  final int nodeId;

  /// The link target as written in the document.
  final String href;

  /// The anchor's painted text.
  final String text;

  /// Rectangles covered by the link's painted runs, in paint order.
  final List<ui.Rect> rects;

  /// Whether [position] falls inside any of this link's rectangles.
  bool contains(ui.Offset position) {
    return rects.any((rect) => rect.contains(position));
  }

  /// Returns a copy of this region translated by [offset].
  WeftLinkRegion shift(ui.Offset offset) {
    return WeftLinkRegion(
      nodeId: nodeId,
      href: href,
      text: text,
      rects: rects.map((rect) => rect.shift(offset)),
    );
  }
}

/// One primitive of the flat paint list the layout produces.
///
/// Commands are self-contained and attributable: each knows the node that
/// produced it, the rectangle it paints into, and how to paint, shift and
/// release itself. Paint order is list order (back to front).
sealed class WeftPaintCommand {
  /// Creates a command attributed to [nodeId].
  const WeftPaintCommand({required this.nodeId});

  /// Id of the document node that produced this command.
  final int nodeId;

  /// Paints this command at [origin] on [canvas].
  void paint(ui.Canvas canvas, ui.Offset origin);

  /// Releases native resources this command holds, if any. Safe to call
  /// more than once.
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

/// Paints one filled rectangle.
final class WeftRectPaintCommand extends WeftPaintCommand {
  /// Creates a command filling [rect] with [color].
  const WeftRectPaintCommand({
    required super.nodeId,
    required this.rect,
    required this.color,
  });

  /// Rectangle to fill, in document coordinates.
  final ui.Rect rect;

  /// Fill color applied to [rect].
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

/// Paints one shaped text run through a [TextPainter].
///
/// The command owns its painter: disposing the command disposes the painter,
/// so a command's painter must never be disposed separately.
final class WeftTextPaintCommand extends WeftPaintCommand {
  /// Creates a text command painting [painter] at [offset].
  const WeftTextPaintCommand({
    required super.nodeId,
    required this.painter,
    required this.offset,
    this.runs = const [],
  });

  /// The shaped text to paint; owned by this command.
  final TextPainter painter;

  /// Top-left corner of the painted text, in document coordinates.
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
  /// Creates a run mapping painter offsets back to node offsets.
  const WeftTextPainterRun({
    required this.nodeId,
    required this.painterStart,
    required this.painterEnd,
    required this.nodeStart,
    required this.nodeEnd,
  });

  /// Id of the source text node.
  final NodeId nodeId;

  /// Start offset of the run in the painter's text.
  final int painterStart;

  /// End offset of the run in the painter's text.
  final int painterEnd;

  /// Start offset of the run's source range in the node's painted text.
  final int nodeStart;

  /// End offset of the run's source range in the node's painted text.
  final int nodeEnd;
}

/// Paints one resolved image into its destination rectangle.
final class WeftImagePaintCommand extends WeftPaintCommand {
  /// Creates a command painting [image] into [destination].
  const WeftImagePaintCommand({
    required super.nodeId,
    required this.image,
    required this.destination,
  });

  /// The decoded image supplied by the host's resolver.
  final ui.Image image;

  /// Rectangle the image is drawn into, in document coordinates.
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
  /// Builds a chunk from [commands]; [bounds] is computed as their union.
  WeftChunk({required this.key, required Iterable<WeftPaintCommand> commands})
      : commands = List<WeftPaintCommand>.unmodifiable(commands),

        /// Union of the chunk's command bounds, computed at construction.
        bounds = _unionBounds(commands);

  /// Key of the chrome chunk: body background/border commands and any command
  /// whose node does not map to a top-level body child. Chrome is always
  /// painted, so renderers must never cull it. Top-level body children use
  /// their zero-based ordinal as the key, which cannot collide with this.
  static const int chromeKey = -1;

  /// Either [chromeKey] or the zero-based ordinal of the top-level body
  /// child this chunk covers.
  final int key;

  /// Paints in document order, exactly as the flat command list would paint
  /// this group's slice.
  final List<WeftPaintCommand> commands;

  /// Union of the commands' [WeftPaintCommand.bounds]; fully contains every
  /// pixel the chunk can paint.
  final ui.Rect bounds;

  /// Whether this chunk is the body chrome chunk ([chromeKey]).
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
    final chrome = _ChunkAccumulator();
    final byOrdinal = <int, _ChunkAccumulator>{};
    final ordinalByNode = _topLevelOrdinalsByNode(document);
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

  /// The ordinal of the top-level body child owning [nodeId], or null when
  /// the node belongs to the chrome or the document has no body.
  static int? topLevelOrdinalForNode(
    WeftDocumentSnapshot document,
    NodeId nodeId,
  ) {
    return _topLevelOrdinalsByNode(document)[nodeId];
  }

  /// Maps every node id under a top-level body child to that child's
  /// zero-based ordinal. Body itself is absent — its own commands belong to
  /// the chrome chunk — and so is every node when the document has no body.
  static final _ordinalCache = Expando<Map<int, int>>();

  static Map<int, int> _topLevelOrdinalsByNode(WeftDocumentSnapshot document) {
    final cached = _ordinalCache[document];
    if (cached != null) return cached;
    final body = document.body;
    if (body == null) return const <int, int>{};
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
    _ordinalCache[document] = ordinalByNode;
    return ordinalByNode;
  }
}

/// Accumulates one chunk's commands plus their first and last index in the
/// flat command list for the contiguity assertion.
final class _ChunkAccumulator {
  final List<WeftPaintCommand> _commands = <WeftPaintCommand>[];
  int _firstIndex = -1;
  int _lastIndex = -1;

  /// Whether any command has been added.
  bool get isNotEmpty => _commands.isNotEmpty;

  /// Adds [command] and records its [index] in the flat command list.
  void add(WeftPaintCommand command, int index) {
    _commands.add(command);
    _firstIndex = _firstIndex < 0 ? index : _firstIndex;
    _lastIndex = index;
  }

  /// Builds the chunk, asserting non-chrome commands stayed contiguous in
  /// the flat command list.
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

/// A maximal run of the flat command list whose commands share one chunk.
///
/// Non-chrome chunks occupy one contiguous run each. The chrome chunk can be
/// split into several runs: the body's own loose text commands sit between
/// its children's command ranges in the flat list. Splitting keeps every
/// run's bounds tight and lets queries scan candidates in exact flat-list
/// order, so culled hit resolution sees commands in precisely the order the
/// full back-to-front scan would.
final class _HitSegment {
  const _HitSegment({
    required this.start,
    required this.end,
    required this.bounds,
  });

  /// Inclusive index of the first command of the run.
  final int start;

  /// Inclusive index of the last command of the run.
  final int end;

  /// Union of the run's command bounds. Every member command's bounds are
  /// fully contained here, so a point outside [bounds] cannot hit any
  /// command of the run.
  final ui.Rect bounds;
}

/// Spatial index for hit resolution over the chunked command list (ADR 0020).
///
/// Built once per layout from the attached document snapshot. Candidate
/// segments and chunks are located through fixed-height vertical bands, so a
/// query scans only the commands whose chunk can actually contain the point
/// instead of walking the whole list. Culling is exact, not approximate: a
/// command's bounds are contained in its segment's bounds and a link's rects
/// in its chunk's bounds, so a point outside every registered bound cannot
/// hit anything, and every candidate scan keeps the flat-list order the full
/// scan would use.
final class _HitIndex {
  _HitIndex._({
    required this.segments,
    required this.chunks,
    required this.segmentBands,
    required this.chunkBands,
    required this.linksByChunk,
    required this.unmappedLinks,
  });

  /// Height of one vertical band of the candidate grid. Bands only bound the
  /// search: candidates are still filtered by exact bounds afterwards, so
  /// the value trades memory for lookup width, never for correctness.
  static const double _bandExtent = 512;

  /// Command runs cut from the flat list, in flat-list order.
  final List<_HitSegment> segments;

  /// The document's chunks, in paint order (chrome first).
  final List<WeftChunk> chunks;

  /// Segment indices per band, ascending, so reversing a band visits
  /// candidates in flat-list reverse order.
  final List<List<int>> segmentBands;

  /// Chunk indices per band, ascending.
  final List<List<int>> chunkBands;

  /// Link indices bucketed by their chunk key, in link-list order.
  final Map<int, List<int>> linksByChunk;

  /// Indices of links whose node maps to no chunk. Structurally impossible
  /// while the snapshot has a body (every anchor sits inside a top-level
  /// child), so debug builds assert the list stays empty; release builds
  /// still resolve them against every query rather than dropping them.
  final List<int> unmappedLinks;

  /// Builds the index for one layout: partitions [commands] into chunks,
  /// cuts per-chunk segments, registers them in vertical bands and buckets
  /// [links] by their chunk.
  static _HitIndex build({
    required WeftDocumentSnapshot document,
    required List<WeftPaintCommand> commands,
    required List<WeftLinkRegion> links,
    required ui.Size size,
  }) {
    final ordinalByNode = WeftChunk._topLevelOrdinalsByNode(document);
    final chunks = WeftChunk.partition(
      document: document,
      commands: commands,
    );

    // Cut the flat command list into per-chunk runs. Chrome runs reappear
    // wherever the body's own loose text sits between its children.
    final segments = <_HitSegment>[];
    var start = 0;
    while (start < commands.length) {
      final key = ordinalByNode[commands[start].nodeId] ?? WeftChunk.chromeKey;
      var end = start;
      while (end + 1 < commands.length &&
          (ordinalByNode[commands[end + 1].nodeId] ?? WeftChunk.chromeKey) ==
              key) {
        end++;
      }
      var bounds = commands[start].bounds;
      for (var i = start + 1; i <= end; i++) {
        bounds = bounds.expandToInclude(commands[i].bounds);
      }
      segments.add(_HitSegment(start: start, end: end, bounds: bounds));
      start = end + 1;
    }

    final bandCount = math.max(1, (size.height / _bandExtent).ceil());
    final segmentBands = List<List<int>>.generate(bandCount, (_) => <int>[]);
    for (var i = 0; i < segments.length; i++) {
      _registerBounds(
        segmentBands,
        segments[i].bounds,
        i,
      );
    }
    final chunkBands = List<List<int>>.generate(bandCount, (_) => <int>[]);
    for (var i = 0; i < chunks.length; i++) {
      _registerBounds(chunkBands, chunks[i].bounds, i);
    }

    final linksByChunk = <int, List<int>>{};
    final unmappedLinks = <int>[];
    for (var i = 0; i < links.length; i++) {
      final ordinal = ordinalByNode[links[i].nodeId];
      if (ordinal == null) {
        unmappedLinks.add(i);
      } else {
        linksByChunk.putIfAbsent(ordinal, () => <int>[]).add(i);
      }
    }
    assert(
      unmappedLinks.isEmpty,
      'Links must resolve to a top-level body child: '
      '${unmappedLinks.length} did not.',
    );

    return _HitIndex._(
      segments: segments,
      chunks: chunks,
      segmentBands: segmentBands,
      chunkBands: chunkBands,
      linksByChunk: linksByChunk,
      unmappedLinks: unmappedLinks,
    );
  }

  /// Registers [index] in every band overlapped by [bounds]' vertical range.
  static void _registerBounds(
    List<List<int>> bands,
    ui.Rect bounds,
    int index,
  ) {
    if (bands.isEmpty) return;
    final first = _bandOf(bounds.top, bands.length);
    final last = _bandOf(bounds.bottom, bands.length);
    for (var band = first; band <= last; band++) {
      bands[band].add(index);
    }
  }

  static int _bandOf(double y, int bandCount) {
    return (y ~/ _bandExtent).clamp(0, bandCount - 1);
  }

  /// The candidate segments for [position] in flat-list reverse order: later
  /// content first, exactly as a full back-to-front command scan would visit
  /// them. Every segment whose bounds contain the point is yielded; segments
  /// outside the point's band cannot contain it and are never considered.
  Iterable<_HitSegment> textCandidates(ui.Offset position) sync* {
    if (segmentBands.isEmpty) return;
    final band = segmentBands[_bandOf(position.dy, segmentBands.length)];
    for (var i = band.length - 1; i >= 0; i--) {
      final segment = segments[band[i]];
      if (_containsPoint(segment.bounds, position)) yield segment;
    }
  }

  /// Every link that could contain [position], as (order, link) pairs where
  /// [order] is the link's index in the layout's link list. Candidates come
  /// from the chunks whose bounds contain the point plus the unmapped links;
  /// callers pick the greatest order among the links that actually contain
  /// the point, which is what the full back-to-front link scan returns.
  Iterable<(int, WeftLinkRegion)> linkCandidates(
    List<WeftLinkRegion> links,
    ui.Offset position,
  ) sync* {
    if (chunkBands.isEmpty) return;
    final band = chunkBands[_bandOf(position.dy, chunkBands.length)];
    for (var i = band.length - 1; i >= 0; i--) {
      final chunk = chunks[band[i]];
      if (!_containsPoint(chunk.bounds, position)) continue;
      for (final linkIndex in linksByChunk[chunk.key] ?? const <int>[]) {
        yield (linkIndex, links[linkIndex]);
      }
    }
    for (final linkIndex in unmappedLinks) {
      yield (linkIndex, links[linkIndex]);
    }
  }

  /// Whether [position] lies inside [bounds] or on its edges.
  ///
  /// [ui.Rect.contains] excludes the right and bottom edges, but the text
  /// hit check accepts a point exactly on a painter's right or bottom edge,
  /// so the candidate filter must admit those edges too and let the
  /// per-command check make the final call.
  static bool _containsPoint(ui.Rect bounds, ui.Offset position) {
    return position.dx >= bounds.left &&
        position.dx <= bounds.right &&
        position.dy >= bounds.top &&
        position.dy <= bounds.bottom;
  }
}

ui.Rect _paintBoundsFor(Iterable<WeftPaintCommand> commands) {
  var bounds = ui.Rect.zero;
  var first = true;
  for (final command in commands) {
    bounds = first ? command.bounds : bounds.expandToInclude(command.bounds);
    first = false;
  }
  return bounds;
}

/// Which edge of the content box a float reserves.
enum WeftFloatExclusionSide { left, right }

/// A rectangle block content must avoid, reserved by one float.
final class WeftFloatExclusion {
  /// Creates an exclusion on [side] covering [rect].
  const WeftFloatExclusion({required this.side, required this.rect});

  /// The float's side; text wraps on the opposite edge.
  final WeftFloatExclusionSide side;

  /// Rectangle the float occupies, in document coordinates.
  final ui.Rect rect;
}

/// The reusable layout output of one top-level body child, carried between
/// incremental layouts.
///
/// A block stores its position and extent plus the commands, boxes, hit
/// regions and float exclusions its subtree produced. Lazily laid-out passes
/// may store a block without its commands ([materialized] false); a later
/// pass materializes it when it scrolls into view.
final class WeftCachedLayoutBlock {
  /// Creates a cached block; [paintBounds] defaults to the union of
  /// [commands]' bounds.
  WeftCachedLayoutBlock({
    required this.element,
    required this.left,
    required this.top,
    required this.height,
    required this.materialized,
    ui.Rect? paintBounds,
    required Iterable<WeftLayoutBox> boxes,
    required Iterable<WeftPaintCommand> commands,
    required Iterable<WeftLinkRegion> links,
    Iterable<WeftTagRegion> tagRegions = const <WeftTagRegion>[],
    Iterable<WeftFloatExclusion> floatExclusions = const [],
  })  : boxes = List<WeftLayoutBox>.unmodifiable(boxes),

        /// Unmodifiable copy of the block's paint commands.
        commands = List<WeftPaintCommand>.unmodifiable(commands),

        /// Unmodifiable copy of the block's link regions.
        links = List<WeftLinkRegion>.unmodifiable(links),

        /// Unmodifiable copy of the block's custom tag regions.
        tagRegions = List<WeftTagRegion>.unmodifiable(tagRegions),

        /// Unmodifiable copy of the block's float exclusions.
        floatExclusions =
            List<WeftFloatExclusion>.unmodifiable(floatExclusions),

        /// Union of the block's command bounds, or the explicit
        /// [paintBounds].
        paintBounds = paintBounds ?? _paintBoundsFor(commands);

  /// The block's root element.
  final WeftElement element;

  /// Left edge of the block's margin box, in document coordinates.
  final double left;

  /// Top edge of the block's margin box, in document coordinates.
  final double top;

  /// Height the block contributed to the flow, including its margins.
  final double height;

  /// Whether commands/boxes/links are currently held for this block. A
  /// materialized block may legally have no paint commands.
  final bool materialized;

  /// Union of the block's command bounds; contains every pixel it paints.
  final ui.Rect paintBounds;

  /// Boxes the block produced, in paint order.
  final List<WeftLayoutBox> boxes;

  /// Commands the block produced, in paint order.
  final List<WeftPaintCommand> commands;

  /// Link hit regions the block produced.
  final List<WeftLinkRegion> links;

  /// Custom tag hit regions the block produced.
  final List<WeftTagRegion> tagRegions;

  /// Float exclusions the block's floats reserve for later content.
  final List<WeftFloatExclusion> floatExclusions;
}

/// Single-owner measured geometry and window lookup shared across lazy passes.
abstract class WeftViewportLayoutState {
  /// Read-only view of the measured prefix, in document order.
  List<WeftCachedLayoutBlock> get blocks;

  /// Number of eligible top-level elements, excluding formatting whitespace.
  int get childCount;

  /// Conservative start of unmeasured content, or infinity when fully measured.
  double get measuredEnd;

  /// Whether the window needs new measurements or different materialization.
  bool needsLayout(double start, double end);
}

/// Everything a relayout needs to reuse the previous pass's work: the inputs
/// that produced it and the per-block results.
///
/// The engine validates the inputs (snapshot instance, width, text scaling,
/// images, line-break rules, renderer set) before reusing [blocks]; any
/// mismatch discards the cache instead of reusing stale output.
final class WeftIncrementalLayoutCache {
  /// Creates a cache, borrowing the single-owner lazy state's read-only blocks.
  WeftIncrementalLayoutCache({
    required this.document,
    required this.width,
    required this.textScaler,
    required Map<int, ui.Image> images,
    required WeftLineBreakRules lineBreakRules,
    required Iterable<WeftCachedLayoutBlock> blocks,
    required this.measuredPrefixLength,
    required this.isLazy,
    required this.estimatedExtent,
    this.tagRenderers = const <String, WeftTagRenderer>{},
    Map<WeftElement, WeftComputedStyle>? styleCache,
    this.viewportState,
  })  : images = Map<int, ui.Image>.unmodifiable(images),

        /// Unmodifiable copy of the line-break rules the layout used.
        lineBreakRules = WeftLineBreakRules(
          lineStartProhibited: Set<int>.unmodifiable(
            lineBreakRules.lineStartProhibited,
          ),
          lineEndProhibited: Set<int>.unmodifiable(
            lineBreakRules.lineEndProhibited,
          ),
        ),

        /// Unmodifiable copy of the cached blocks, in document order.
        blocks = viewportState?.blocks ??
            List<WeftCachedLayoutBlock>.unmodifiable(blocks),

        /// Style cache to keep across relayouts; created fresh when omitted.
        styleCache = styleCache ?? <WeftElement, WeftComputedStyle>{};

  /// The snapshot the cached layout was built from; reuse requires the same
  /// instance.
  final WeftDocumentSnapshot document;

  /// Viewport width the cached layout was produced at.
  final double width;

  /// Text scaling the cached layout was produced with.
  final TextScaler textScaler;

  /// Decoded images available to the cached layout.
  final Map<int, ui.Image> images;

  /// Kinsoku tables the cached layout was produced with.
  final WeftLineBreakRules lineBreakRules;

  /// Per-block results, one per laid-out top-level body child, in document
  /// order.
  final List<WeftCachedLayoutBlock> blocks;

  /// How many of the document's leading top-level children the cached blocks
  /// cover; a full pass lays out all of them, a lazy pass only a prefix.
  final int measuredPrefixLength;

  /// Whether the cached layout was produced by a lazy viewport pass.
  final bool isLazy;

  /// Total document height the pass reported, including estimated blocks.
  final double estimatedExtent;

  /// Renderer set that produced cached custom tag blocks. Block reuse is
  /// disabled when the map identity changes.
  final Map<String, WeftTagRenderer> tagRenderers;

  /// Computed styles keyed by element identity, filled by layout passes and
  /// reused while [document] stays the same instance. Valid because computed
  /// styles derive only from the snapshot; width, text scaling and images do
  /// not participate. The layout engine mutates the map while relayouting
  /// this snapshot and reads previous entries for unchanged elements.
  final Map<WeftElement, WeftComputedStyle> styleCache;

  /// Window geometry transferred with this cache, never shared by live owners.
  final WeftViewportLayoutState? viewportState;

  /// Number of top-level flow entries in this cache's document.
  int get childCount =>
      viewportState?.childCount ?? document.body!.children.length;
}

/// The output of one layout pass: document size, boxes, the flat paint
/// command list, hit regions, and the text model selection resolves through.
///
/// The result owns its paint commands. Call [dispose] when done; pass
/// commands to another result first with [transferCommands] if that result
/// reuses them.
final class WeftLayoutResult {
  /// Creates a layout result; collections are copied into unmodifiable
  /// lists.
  WeftLayoutResult({
    required this.size,
    required Iterable<WeftLayoutBox> boxes,
    required Iterable<WeftPaintCommand> commands,
    required Iterable<WeftLinkRegion> links,
    Iterable<WeftTagRegion> tagRegions = const <WeftTagRegion>[],
    this.textIndex,
    this.debugReusedBlockCount = 0,
    this.debugLaidOutBlockCount = 0,
    this.debugMaterializedBlockCount = 0,
    this.debugVisitedBlockCount = 0,
    this.debugEstimatedBlockCount = 0,
    this.debugEligibilityVisitCount = 0,
    this.debugIsLazy = false,
  })  : boxes = List<WeftLayoutBox>.unmodifiable(boxes),

        /// Unmodifiable copy of the flat paint command list.
        commands = List<WeftPaintCommand>.unmodifiable(commands),

        /// Unmodifiable copy of the link hit regions.
        links = List<WeftLinkRegion>.unmodifiable(links),

        /// Unmodifiable copy of the custom tag hit regions.
        tagRegions = List<WeftTagRegion>.unmodifiable(tagRegions);

  /// Total document size: [ui.Size.width] is the layout width, the height
  /// the measured (or estimated) extent.
  final ui.Size size;

  /// Laid-out boxes in paint order.
  final List<WeftLayoutBox> boxes;

  /// The flat paint list, in back-to-front paint order.
  final List<WeftPaintCommand> commands;

  /// Link hit regions in paint order (later regions paint on top).
  final List<WeftLinkRegion> links;

  /// Custom tag hit regions in paint order (later regions paint on top).
  final List<WeftTagRegion> tagRegions;

  /// Debug counter: top-level blocks copied from the previous result.
  final int debugReusedBlockCount;

  /// Debug counter: top-level blocks laid out fresh in this pass.
  final int debugLaidOutBlockCount;

  /// Debug counter: reused blocks materialized into paint commands.
  final int debugMaterializedBlockCount;

  /// Top-level entries visited while preparing or updating this lazy pass.
  final int debugVisitedBlockCount;

  /// Entries incorporated into or removed from the cached suffix estimate.
  final int debugEstimatedBlockCount;

  /// Elements inspected by this pass's lazy admission walk.
  final int debugEligibilityVisitCount;

  /// Debug flag: whether this pass was a lazy viewport pass.
  final bool debugIsLazy;

  /// Cache this pass seeded for the next incremental layout. Null when the
  /// pass cannot seed reuse, e.g. after [transferCommands].
  WeftIncrementalLayoutCache? incrementalCache;

  /// The logical text model for this layout, used to resolve selection
  /// anchors across node boundaries.
  final WeftTextIndex? textIndex;

  /// The snapshot this layout was built from, attached by whoever laid it
  /// out, and the hit index built lazily from it on first use (ADR 0020).
  ///
  /// The snapshot is only needed to map command and link nodes back to their
  /// top-level body child; without it the hit queries fall back to full
  /// scans that resolve the same results.
  WeftDocumentSnapshot? _hitDocument;
  _HitIndex? _hitIndex;

  /// Enables chunk-culled hit resolution against [document], the snapshot
  /// this layout was built from. Production surfaces call this right after
  /// laying out. Attaching a different snapshot drops the cached index; the
  /// next query rebuilds it.
  void attachDocument(WeftDocumentSnapshot document) {
    if (identical(_hitDocument, document)) return;
    _hitDocument = document;
    _hitIndex = null;
  }

  /// The hit index for point queries, built on first use from the attached
  /// document, or null while no document is attached.
  _HitIndex? get _hits {
    final document = _hitDocument;
    if (document == null) return null;
    return _hitIndex ??= _HitIndex.build(
      document: document,
      commands: commands,
      links: links,
      size: size,
    );
  }

  /// The topmost link whose rectangles contain [position], or null.
  ///
  /// With a document attached the query runs against the chunk-culled index
  /// and returns exactly what the full back-to-front scan would.
  WeftLinkRegion? linkAt(ui.Offset position) {
    final index = _hits;
    if (index == null) {
      for (final link in links.reversed) {
        if (link.contains(position)) return link;
      }
      return null;
    }
    // Links are compared by their order in [links] so the culled scan
    // returns exactly what the full back-to-front scan would: the last link
    // in list order whose rects contain the point.
    WeftLinkRegion? best;
    var bestOrder = -1;
    for (final (order, link) in index.linkCandidates(links, position)) {
      if (order > bestOrder && link.contains(position)) {
        best = link;
        bestOrder = order;
      }
    }
    return best;
  }

  /// The topmost custom tag region containing [position], or null.
  WeftTagRegion? tagAt(ui.Offset position) {
    for (final region in tagRegions.reversed) {
      if (region.contains(position)) return region;
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
  /// coordinates: a [caretWidth]-wide bar at the leading edge of the anchor
  /// position's glyph box — the left edge for LTR runs, the right edge for
  /// RTL ones (ADR 0042) — spanning the box's full height.
  ///
  /// Returns null when the anchor maps to no painted text — an unknown node
  /// or an offset at the very end of a node's text — mirroring the safe-drop
  /// semantics of the selection model (ADR 0013) instead of clamping.
  ui.Rect? caretRectForAnchor(TextAnchor anchor) {
    final rects =
        textRectsForNode(anchor.nodeId, anchor.offset, anchor.offset + 1);
    if (rects.isEmpty) return null;
    final first = rects.first;
    if (_anchorIsRtl(anchor)) {
      return ui.Rect.fromLTRB(
        first.right - caretWidth,
        first.top,
        first.right,
        first.bottom,
      );
    }
    return ui.Rect.fromLTRB(
      first.left,
      first.top,
      first.left + caretWidth,
      first.bottom,
    );
  }

  bool _anchorIsRtl(TextAnchor anchor) {
    for (final command in commands) {
      if (command is! WeftTextPaintCommand) continue;
      for (final run in command.runs) {
        if (run.nodeId == anchor.nodeId) {
          return command.painter.textDirection == ui.TextDirection.rtl;
        }
      }
    }
    return false;
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
  /// lines, later table cells) wins; chunk culling only narrows which
  /// commands are visited, never the order. A point only anchors when it
  /// falls inside a command's painted bounds and maps into a run whose node
  /// still resolves in the logical text index; points in the gaps between
  /// blocks hit nothing.
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
  ///
  /// With a document attached, candidate segments are located through the
  /// chunk index first and only their commands are scanned; the scan order
  /// stays the flat-list reverse order, so the result is exactly what a full
  /// scan produces. Without one, every command is scanned back-to-front.
  (WeftTextPaintCommand, int)? _textHitAt(ui.Offset position) {
    if (textIndex == null) return null;
    final index = _hits;
    if (index == null) {
      return _textHitInRange(commands.length - 1, 0, position);
    }
    for (final segment in index.textCandidates(position)) {
      final hit = _textHitInRange(segment.end, segment.start, position);
      if (hit != null) return hit;
    }
    return null;
  }

  /// The back-to-front text hit across commands[from]..commands[to] walking
  /// [from] down to [to], or null.
  (WeftTextPaintCommand, int)? _textHitInRange(
    int from,
    int to,
    ui.Offset position,
  ) {
    for (var i = from; i >= to; i--) {
      final command = commands[i];
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
  final Set<WeftPaintCommand> _transferredCommands = <WeftPaintCommand>{};

  /// Hands ownership of [commands] to another result so [dispose] skips
  /// them. A result that transferred commands cannot seed another
  /// incremental layout.
  void transferCommands(Iterable<WeftPaintCommand> commands) {
    assert(!_disposed);
    _transferredCommands.addAll(commands);
    incrementalCache = null;
  }

  /// Disposes every paint command still owned by this result. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    incrementalCache = null;
    for (final command in commands) {
      if (!_transferredCommands.contains(command)) command.dispose();
    }
  }
}
