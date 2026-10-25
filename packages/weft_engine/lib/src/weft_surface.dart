import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';

import 'image_resources.dart';
import 'layout_engine.dart';
import 'layout_result.dart';

/// Accent color of the caret painted by [RenderWeftSurface] and of the
/// selection handle overlays built by the weft view layer. Kept const so the
/// selection chrome carries no theme dependency.
const Color kWeftSelectionColor = Color(0xFF1A73E8);

/// Edge length of a drag handle's square touch target, following the
/// customary 44px minimum for touch targets.
const double kWeftSelectionHandleTouchExtent = 44;

/// Suggested size of the selection copy button. The engine places
/// [WeftSelectionControlsGeometry.copyButton] with this size and the weft
/// overlay draws itself inside that rect.
const Size kWeftCopyButtonSize = Size(72, 32);

/// Vertical gap between the selection bounds and the copy button.
const double kWeftCopyButtonVerticalGap = 8;

/// Geometry for the selection chrome overlays, in surface-local coordinates.
///
/// Handle anchors sit at the classic selection ends: the bottom-left of the
/// first logical-order selection rectangle and the bottom-right of the last
/// one. The touch rects around them and the copy button placement are only
/// suggestions for the view layer — [RenderWeftSurface] never paints these
/// widgets itself.
final class WeftSelectionControlsGeometry {
  const WeftSelectionControlsGeometry({
    required this.startAnchor,
    required this.endAnchor,
    required this.startHandle,
    required this.endHandle,
    required this.copyButton,
  });

  /// Bottom-left corner of the first selection rectangle.
  final ui.Offset startAnchor;

  /// Bottom-right corner of the last selection rectangle.
  final ui.Offset endAnchor;

  /// Touch target around [startAnchor], or null when handles are disabled.
  final ui.Rect? startHandle;

  /// Touch target around [endAnchor], or null when handles are disabled.
  final ui.Rect? endHandle;

  /// Suggested copy button placement above the selection (below it when the
  /// space above would leave the surface), or null when disabled.
  final ui.Rect? copyButton;
}

/// A single render-object surface that lays out and paints a normalized
/// document.
///
/// Used standalone — without [WeftView] — the surface paints the selection
/// highlight and, for collapsed selections, a caret bar gated by [showCaret].
/// Selection drag handles and the copy button never appear on a standalone
/// surface: they are chrome overlay widgets owned by WeftView, positioned
/// through [RenderWeftSurface.selectionControlsGeometry]. The show* flags
/// here gate that query so the view layer can turn chrome off.
class WeftSurface extends StatefulWidget {
  const WeftSurface({
    super.key,
    required this.document,
    this.selection,
    this.textScaler = TextScaler.noScaling,
    this.imageResolver,
    this.onLinkTap,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
    this.copyButtonLabel = '复制',
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
  final WeftImageResolver? imageResolver;
  final ValueChanged<WeftLinkRegion>? onLinkTap;

  /// Whether [RenderWeftSurface.selectionControlsGeometry] exposes drag
  /// handle touch targets. Handles are overlay widgets owned by WeftView and
  /// never paint here; standalone surfaces only surface the query.
  final bool showSelectionHandles;

  /// Whether a collapsed selection paints a caret bar on the canvas.
  final bool showCaret;

  /// Whether [RenderWeftSurface.selectionControlsGeometry] suggests a copy
  /// button placement. Like the handles, the button is a WeftView overlay.
  final bool showCopyButton;

  /// Label for the copy button overlay built by WeftView, which forwards its
  /// own parameter here so hosts share one source of defaults. A standalone
  /// [WeftSurface] never shows a copy button.
  final String copyButtonLabel;

  @override
  State<WeftSurface> createState() => _WeftSurfaceState();
}

class _WeftSurfaceState extends State<WeftSurface> {
  final _surfaceKey = GlobalKey();

  void _handleTapUp(TapUpDetails details) {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderWeftSurface) return;
    final link = renderObject.linkAt(details.localPosition);
    if (link != null) widget.onLinkTap?.call(link);
  }

  @override
  Widget build(BuildContext context) {
    final surface = _RawWeftSurface(
      key: _surfaceKey,
      document: widget.document,
      selection: widget.selection,
      textScaler: widget.textScaler,
      imageResolver: widget.imageResolver,
      showSelectionHandles: widget.showSelectionHandles,
      showCaret: widget.showCaret,
      showCopyButton: widget.showCopyButton,
    );
    if (widget.onLinkTap == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      excludeFromSemantics: true,
      onTapUp: _handleTapUp,
      child: surface,
    );
  }
}

class _RawWeftSurface extends LeafRenderObjectWidget {
  const _RawWeftSurface({
    super.key,
    required this.document,
    this.selection,
    this.textScaler = TextScaler.noScaling,
    this.imageResolver,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
  final WeftImageResolver? imageResolver;
  final bool showSelectionHandles;
  final bool showCaret;
  final bool showCopyButton;

  @override
  RenderWeftSurface createRenderObject(BuildContext context) {
    return RenderWeftSurface(
      document: document,
      selection: selection,
      textScaler: textScaler,
      imageResolver: imageResolver,
      imageConfiguration: createLocalImageConfiguration(context),
      showSelectionHandles: showSelectionHandles,
      showCaret: showCaret,
      showCopyButton: showCopyButton,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWeftSurface renderObject,
  ) {
    renderObject
      ..document = document
      ..selection = selection
      ..textScaler = textScaler
      ..imageConfiguration = createLocalImageConfiguration(context)
      ..imageResolver = imageResolver
      ..showSelectionHandles = showSelectionHandles
      ..showCaret = showCaret
      ..showCopyButton = showCopyButton;
  }
}

class RenderWeftSurface extends RenderBox {
  RenderWeftSurface({
    required WeftDocumentSnapshot document,
    TextSelectionRange? selection,
    TextScaler textScaler = TextScaler.noScaling,
    WeftImageResolver? imageResolver,
    ImageConfiguration imageConfiguration = ImageConfiguration.empty,
    bool showSelectionHandles = true,
    bool showCaret = true,
    bool showCopyButton = true,
  })  : _document = document,
        _selection = selection,
        _textScaler = textScaler,
        _imageResolver = imageResolver,
        _imageConfiguration = imageConfiguration,
        _showSelectionHandles = showSelectionHandles,
        _showCaret = showCaret,
        _showCopyButton = showCopyButton;

  static const _layoutEngine = WeftLayoutEngine();

  WeftDocumentSnapshot _document;
  TextSelectionRange? _selection;
  TextScaler _textScaler;
  WeftImageResolver? _imageResolver;
  ImageConfiguration _imageConfiguration;
  bool _showSelectionHandles;
  bool _showCaret;
  bool _showCopyButton;
  WeftLayoutResult? _layout;
  final Map<int, _ResolvedImage> _images = <int, _ResolvedImage>{};

  /// Chunks of [_layout] and their recorded pictures, built lazily on paint.
  ///
  /// [WeftChunk.chromeKey] and the top-level child ordinals key the map.
  /// Pictures never depend on the selection, so selection changes must not
  /// drop them; anything that replaces the layout does.
  List<WeftChunk>? _chunks;
  WeftLayoutResult? _chunksLayout;
  final Map<int, ui.Picture> _chunkPictures = <int, ui.Picture>{};

  /// Memo for [WeftLayoutResult.selectionRects], keyed by the layout instance
  /// and the selection value; either changing recomputes it once.
  WeftLayoutResult? _selectionRectsLayout;
  TextSelectionRange? _selectionRectsKey;
  List<ui.Rect> _selectionRects = const <ui.Rect>[];

  /// Memo for [WeftLayoutResult.caretRectForAnchor], keyed like the selection
  /// rects. Only a collapsed selection paints a caret.
  WeftLayoutResult? _caretRectLayout;
  TextSelectionRange? _caretRectKey;
  ui.Rect? _caretRect;

  int _debugRebuiltChunkCount = 0;
  int _debugPaintedChunkCount = 0;
  int _debugSelectionRectBuildCount = 0;

  WeftDocumentSnapshot get document => _document;

  set document(WeftDocumentSnapshot value) {
    if (identical(_document, value)) return;
    _document = value;
    _invalidateLayout();
    _clearImages();
  }

  TextSelectionRange? get selection => _selection;

  set selection(TextSelectionRange? value) {
    if (_selection == value) return;
    _selection = value;
    markNeedsPaint();
  }

  TextScaler get textScaler => _textScaler;

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _invalidateLayout();
  }

  WeftImageResolver? get imageResolver => _imageResolver;

  set imageResolver(WeftImageResolver? value) {
    if (identical(_imageResolver, value)) return;
    _imageResolver = value;
    _invalidateLayout();
    _clearImages();
  }

  ImageConfiguration get imageConfiguration => _imageConfiguration;

  set imageConfiguration(ImageConfiguration value) {
    if (_imageConfiguration == value) return;
    _imageConfiguration = value;
    _invalidateLayout();
    _clearImages();
  }

  /// Whether [selectionControlsGeometry] exposes drag handle touch targets.
  /// Handles are overlay widgets owned by the view layer and never paint
  /// here; the flag only gates the geometry query.
  bool get showSelectionHandles => _showSelectionHandles;

  set showSelectionHandles(bool value) {
    if (_showSelectionHandles == value) return;
    _showSelectionHandles = value;
    markNeedsPaint();
  }

  /// Whether a collapsed selection paints a caret bar on the canvas.
  bool get showCaret => _showCaret;

  set showCaret(bool value) {
    if (_showCaret == value) return;
    _showCaret = value;
    markNeedsPaint();
  }

  /// Whether [selectionControlsGeometry] suggests a copy button placement.
  bool get showCopyButton => _showCopyButton;

  set showCopyButton(bool value) {
    if (_showCopyButton == value) return;
    _showCopyButton = value;
    markNeedsPaint();
  }

  @visibleForTesting
  WeftLayoutResult? get debugLayout => _layout;

  @visibleForTesting
  int get debugResolvedImageCount {
    return _images.values.where((entry) => entry.info != null).length;
  }

  /// Total number of chunk pictures recorded since construction. A stable
  /// value across paints proves cached pictures were reused, not rebuilt.
  @visibleForTesting
  int get debugRebuiltChunkCount => _debugRebuiltChunkCount;

  /// Total number of chunk pictures drawn since construction, including
  /// repeat draws of the same picture on later paints.
  @visibleForTesting
  int get debugPaintedChunkCount => _debugPaintedChunkCount;

  /// Total number of times selection rectangles were recomputed.
  @visibleForTesting
  int get debugSelectionRectBuildCount => _debugSelectionRectBuildCount;

  /// Number of chunk pictures currently held in the cache.
  @visibleForTesting
  int get debugCachedChunkPictureCount => _chunkPictures.length;

  @visibleForTesting
  List<WeftChunk>? get debugChunks => _chunks;

  void _invalidateLayout() {
    _discardPaintCache();
    _layout?.dispose();
    _layout = null;
    markNeedsLayout();
  }

  void _discardPaintCache() {
    _chunks = null;
    _chunksLayout = null;
    for (final picture in _chunkPictures.values) {
      picture.dispose();
    }
    _chunkPictures.clear();
    _selectionRectsLayout = null;
    _selectionRectsKey = null;
    _selectionRects = const <ui.Rect>[];
    _caretRectLayout = null;
    _caretRectKey = null;
    _caretRect = null;
  }

  @override
  void performLayout() {
    if (!constraints.hasBoundedWidth) {
      throw FlutterError(
        'WeftSurface requires a bounded width. '
        'Place it in a vertically scrollable or width-constrained parent.',
      );
    }

    _syncImages();
    final width = constraints.maxWidth;
    final previous = _layout;
    final current = _layoutEngine.layout(
      _document,
      width: width,
      textScaler: _textScaler,
      images: _resolvedImages,
    );
    _layout = current;
    previous?.dispose();
    size = constraints.constrain(Size(width, current.size.height));
  }

  void _syncImages() {
    final requests = <int, WeftImageRequest>{};
    final body = _document.body;
    if (body != null) {
      void visit(WeftNode node) {
        if (node is! WeftElement) return;
        if (node.tag == 'img') {
          final src = node.attribute('src');
          if (src != null && src.isNotEmpty) {
            requests[node.id] = WeftImageRequest(
              documentId: _document.id,
              nodeId: node.id,
              src: src,
              alt: node.attribute('alt') ?? '',
            );
          }
        }
        for (final child in node.children) {
          visit(child);
        }
      }

      visit(body);
    }

    final stale = <int>[];
    for (final entry in _images.entries) {
      final request = requests[entry.key];
      if (request == null || request.src != entry.value.request.src) {
        stale.add(entry.key);
      }
    }
    for (final nodeId in stale) {
      _images.remove(nodeId)?.dispose();
    }

    final resolver = _imageResolver;
    if (resolver == null) return;
    for (final request in requests.values) {
      if (_images.containsKey(request.nodeId)) continue;
      final ImageProvider<Object>? provider;
      try {
        provider = resolver(request);
      } on Object {
        // A failing resolver is equivalent to an unavailable image; the
        // document remains renderable with alternative text.
        continue;
      }
      if (provider == null) continue;
      final entry = _ResolvedImage(request: request, provider: provider);
      entry.listener = ImageStreamListener(
        (info, synchronousCall) {
          entry.info?.dispose();
          entry.info = info;
          _handleImageUpdate();
        },
        onError: (error, stackTrace) {
          _handleImageUpdate();
        },
      );
      try {
        entry.stream = provider.resolve(_imageConfiguration)
          ..addListener(entry.listener!);
      } on Object {
        entry.dispose();
        continue;
      }
      _images[request.nodeId] = entry;
    }
  }

  void _handleImageUpdate() {
    if (!attached) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!attached) return;
        _invalidateLayout();
      });
      return;
    }
    _invalidateLayout();
  }

  Map<int, ui.Image> get _resolvedImages {
    final result = <int, ui.Image>{};
    for (final entry in _images.entries) {
      final info = entry.value.info;
      if (info != null) result[entry.key] = info.image;
    }
    return result;
  }

  void _clearImages() {
    for (final entry in _images.values) {
      entry.dispose();
    }
    _images.clear();
  }

  WeftLinkRegion? linkAt(Offset position) {
    return _layout?.linkAt(position);
  }

  /// Resolves the selection anchor at [position] in surface-local
  /// coordinates, or null when the point hits no painted text.
  TextAnchor? anchorAt(Offset position) => _layout?.anchorAt(position);

  /// Resolves the whole-word selection at [position] in surface-local
  /// coordinates, or null when the point hits no painted text.
  TextSelectionRange? wordSelectionAt(Offset position) =>
      _layout?.wordSelectionAt(position);

  /// The logical text covered by [selection], with block boundaries rendered
  /// as newlines, or null when the selection is collapsed or no longer
  /// resolves against the current layout. Hosts own clipboard policies; the
  /// surface only reads the resolved text.
  String? selectionText(TextSelectionRange? selection) {
    final layout = _layout;
    if (layout == null || selection == null) return null;
    return layout.selectionText(selection);
  }

  /// Touch targets and suggested placements for the selection chrome
  /// overlays — drag handles and the copy button — in surface-local
  /// coordinates, or null when there is nothing to show.
  ///
  /// Derived on top of the cached selection rectangles without solving new
  /// text geometry. The overlays themselves are widgets owned by the view
  /// layer (WeftView); a standalone surface exposes this query but paints no
  /// chrome of its own beyond the caret.
  WeftSelectionControlsGeometry? selectionControlsGeometry() {
    final layout = _layout;
    final selection = _selection;
    if (layout == null || selection == null || selection.isCollapsed) {
      return null;
    }
    if (!_showSelectionHandles && !_showCopyButton) return null;
    final rects = _selectionRectsFor(layout, selection);
    if (rects.isEmpty) return null;

    final first = rects.first;
    final last = rects.last;
    ui.Rect? startHandle;
    ui.Rect? endHandle;
    if (_showSelectionHandles) {
      // The start handle reaches left of its anchor, the end handle right of
      // it, so the two targets never overlap and each offers grab space on
      // the side its drag extends toward.
      startHandle = _handleTargetRect(
        ui.Offset(first.left, first.bottom),
        reachLeft: true,
      );
      endHandle = _handleTargetRect(
        ui.Offset(last.right, last.bottom),
        reachLeft: false,
      );
    }
    ui.Rect? copyButton;
    if (_showCopyButton) {
      copyButton = _copyButtonRect(rects, handleRects: [
        if (startHandle != null) startHandle,
        if (endHandle != null) endHandle,
      ]);
    }
    return WeftSelectionControlsGeometry(
      startAnchor: ui.Offset(first.left, first.bottom),
      endAnchor: ui.Offset(last.right, last.bottom),
      startHandle: startHandle,
      endHandle: endHandle,
      copyButton: copyButton,
    );
  }

  /// Suggests a copy button rect above the selection bounds, falling back to
  /// below them when the button would leave the surface at the top. The
  /// below-fallback clears the handle touch targets so the button never sits
  /// inside a handle's grab area; when the surface has no room left the
  /// bottom clamp wins and a late overlap is accepted.
  ui.Rect _copyButtonRect(
    List<ui.Rect> rects, {
    required List<ui.Rect> handleRects,
  }) {
    var union = rects.first;
    for (var i = 1; i < rects.length; i++) {
      union = union.expandToInclude(rects[i]);
    }
    const size = kWeftCopyButtonSize;
    final bounds = ui.Offset.zero & this.size;
    final left = (union.center.dx - size.width / 2)
        .clamp(
          bounds.left,
          math.max(bounds.left, bounds.right - size.width),
        )
        .toDouble();
    var top = union.top - kWeftCopyButtonVerticalGap - size.height;
    if (top < bounds.top) {
      var lowest = union.bottom;
      for (final handle in handleRects) {
        lowest = math.max(lowest, handle.bottom);
      }
      top = lowest + kWeftCopyButtonVerticalGap;
    }
    top = math.min(top, math.max(bounds.top, bounds.bottom - size.height));
    return ui.Rect.fromLTWH(left, top, size.width, size.height);
  }

  /// The touch target for a drag handle anchored at the bottom edge of a
  /// selection rectangle.
  ///
  /// Horizontal placement shifts instead of shrinking when the anchor sits
  /// within one target extent of the surface edge, so the target keeps its
  /// full width and still contains the anchor. Vertical placement shrinks
  /// instead of shifting: the anchor sits on the bottom edge of the selected
  /// line, and shifting the box up would put the grab area on top of the
  /// line the handle belongs to.
  ui.Rect _handleTargetRect(ui.Offset anchor, {required bool reachLeft}) {
    const extent = kWeftSelectionHandleTouchExtent;
    final bounds = ui.Offset.zero & size;
    var left = reachLeft ? anchor.dx - extent : anchor.dx;
    var right = reachLeft ? anchor.dx : anchor.dx + extent;
    if (left < bounds.left) {
      right += bounds.left - left;
      left = bounds.left;
    } else if (right > bounds.right) {
      left -= right - bounds.right;
      right = bounds.right;
    }
    final bottom = math.min(anchor.dy + extent, bounds.bottom);
    final top = math.min(anchor.dy, bounds.bottom);
    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    // The canvas is still in the parent's coordinate space here, so the
    // visible window must be resolved before translating to local space.
    final visible = _visibleLocalRect(canvas, offset);
    canvas.translate(offset.dx, offset.dy);
    debugPaintChunks(canvas, visible: visible);
    // Selection highlight and caret paint after the chunk pictures and must
    // never be recorded into them: selection changes would then rebuild
    // pictures (breaking the chunked rendering cache counters).
    _paintSelection(canvas, visible);
    canvas.restore();
  }

  /// The visible portion of this surface in surface-local coordinates.
  ///
  /// Conservative layers, most precise first:
  ///
  /// 1. The canvas clip bounds. Whenever an ancestor clips on this recording
  ///    canvas (a non-composited scrollable, the common host), these bounds
  ///    are exact.
  /// 2. The enclosing viewport's own bounds mapped through its paint
  ///    transform, which covers composited clips whose layer clip never
  ///    reaches this canvas. It is inflated by the viewport cache extent so
  ///    viewports without their own clip still over-approximate.
  /// 3. The full surface bounds: draw everything.
  ///
  /// Culling with a too-large rect only repaints extra chunks; a too-small
  /// rect would drop visible content, so every layer must over-approximate
  /// the clip and this method must never fail.
  ui.Rect _visibleLocalRect(ui.Canvas canvas, Offset offset) {
    final own = offset & size;
    final clip = canvas.getLocalClipBounds();
    // An unclipped canvas reports unbounded bounds, and a clip containing the
    // whole surface carries no culling information either.
    if (!_coversRect(clip, own)) {
      return clip.intersect(own).shift(-offset);
    }
    final Object? viewport = RenderAbstractViewport.maybeOf(this);
    final RenderBox? viewportBox = viewport is RenderBox ? viewport : null;
    if (viewportBox != null && viewportBox.hasSize && attached) {
      // getOffsetToReveal cannot provide this window: its results describe
      // where content would sit at a computed scroll offset and are
      // independent of the current position. The paint transform, in contrast,
      // has the current scroll offset baked in.
      final transform = viewportBox.getTransformTo(this);
      if (transform.determinant() != 0) {
        final window = MatrixUtils.transformRect(
          transform,
          Offset.zero & viewportBox.size,
        ).inflate(RenderAbstractViewport.defaultCacheExtent);
        return window.intersect(Offset.zero & size);
      }
    }
    return Offset.zero & size;
  }

  /// Whether [outer] fully covers [inner]; [ui.Rect.contains] only accepts
  /// points, so coverage of a whole rect needs the four edge comparisons.
  static bool _coversRect(ui.Rect outer, ui.Rect inner) {
    return outer.left <= inner.left &&
        outer.top <= inner.top &&
        outer.right >= inner.right &&
        outer.bottom >= inner.bottom;
  }

  /// Records and draws the visible chunk pictures onto [canvas], which must
  /// already be in surface-local coordinates.
  ///
  /// [visible] is the visible window in local coordinates; chunks outside it
  /// are skipped and the chrome chunk is always drawn. Passing null draws
  /// every chunk. Production [paint] and the paint benchmarks share this
  /// entry point.
  @visibleForTesting
  void debugPaintChunks(ui.Canvas canvas, {ui.Rect? visible}) {
    final layout = _layout;
    if (layout == null) return;
    if (!identical(_chunksLayout, layout)) {
      // performLayout can replace the layout without _invalidateLayout when a
      // parent relays this surface, so key the cache to the layout instance.
      _discardPaintCache();
      _chunksLayout = layout;
    }
    final chunks = _chunks ??= WeftChunk.partition(
      document: _document,
      commands: layout.commands,
    );
    for (final chunk in chunks) {
      if (!chunk.isChrome &&
          visible != null &&
          !chunk.bounds.overlaps(visible)) {
        continue;
      }
      canvas.drawPicture(_pictureFor(chunk));
      _debugPaintedChunkCount++;
    }
  }

  ui.Picture _pictureFor(WeftChunk chunk) {
    final cached = _chunkPictures[chunk.key];
    if (cached != null) return cached;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final command in chunk.commands) {
      command.paint(canvas, Offset.zero);
    }
    final picture = recorder.endRecording();
    _chunkPictures[chunk.key] = picture;
    _debugRebuiltChunkCount++;
    return picture;
  }

  void _paintSelection(ui.Canvas canvas, ui.Rect visible) {
    final layout = _layout;
    final selection = _selection;
    if (layout == null || selection == null) return;
    if (selection.isCollapsed) {
      if (!_showCaret) return;
      final caret = _caretRectFor(layout, selection);
      if (caret == null) return;
      final clipped = caret.intersect(visible);
      if (!clipped.isEmpty) {
        canvas.drawRect(clipped, Paint()..color = kWeftSelectionColor);
      }
      return;
    }
    final rects = _selectionRectsFor(layout, selection);
    final paint = Paint()..color = const Color(0x339E9E9E);
    for (final rect in rects) {
      final clipped = rect.intersect(visible);
      if (!clipped.isEmpty) {
        canvas.drawRect(clipped, paint);
      }
    }
  }

  ui.Rect? _caretRectFor(
      WeftLayoutResult layout, TextSelectionRange selection) {
    if (!identical(_caretRectLayout, layout) || _caretRectKey != selection) {
      _caretRectLayout = layout;
      _caretRectKey = selection;
      _caretRect = layout.caretRectForAnchor(selection.anchor);
    }
    return _caretRect;
  }

  List<ui.Rect> _selectionRectsFor(
    WeftLayoutResult layout,
    TextSelectionRange selection,
  ) {
    if (!identical(_selectionRectsLayout, layout) ||
        _selectionRectsKey != selection) {
      _selectionRectsLayout = layout;
      _selectionRectsKey = selection;
      _selectionRects = layout.selectionRects(selection);
      _debugSelectionRectBuildCount++;
    }
    return _selectionRects;
  }

  @override
  void dispose() {
    _discardPaintCache();
    _layout?.dispose();
    _layout = null;
    _clearImages();
    super.dispose();
  }
}

final class _ResolvedImage {
  _ResolvedImage({required this.request, required this.provider});

  final WeftImageRequest request;
  final ImageProvider<Object> provider;
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;

  void dispose() {
    final activeStream = stream;
    final activeListener = listener;
    if (activeStream != null && activeListener != null) {
      activeStream.removeListener(activeListener);
    }
    info?.dispose();
    info = null;
    stream = null;
    listener = null;
  }
}
