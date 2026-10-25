import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';

import 'image_resources.dart';
import 'layout_engine.dart';
import 'layout_result.dart';

class WeftSurface extends StatefulWidget {
  const WeftSurface({
    super.key,
    required this.document,
    this.selection,
    this.textScaler = TextScaler.noScaling,
    this.imageResolver,
    this.onLinkTap,
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
  final WeftImageResolver? imageResolver;
  final ValueChanged<WeftLinkRegion>? onLinkTap;

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
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
  final WeftImageResolver? imageResolver;

  @override
  RenderWeftSurface createRenderObject(BuildContext context) {
    return RenderWeftSurface(
      document: document,
      selection: selection,
      textScaler: textScaler,
      imageResolver: imageResolver,
      imageConfiguration: createLocalImageConfiguration(context),
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
      ..imageResolver = imageResolver;
  }
}

class RenderWeftSurface extends RenderBox {
  RenderWeftSurface({
    required WeftDocumentSnapshot document,
    TextSelectionRange? selection,
    TextScaler textScaler = TextScaler.noScaling,
    WeftImageResolver? imageResolver,
    ImageConfiguration imageConfiguration = ImageConfiguration.empty,
  })  : _document = document,
        _selection = selection,
        _textScaler = textScaler,
        _imageResolver = imageResolver,
        _imageConfiguration = imageConfiguration;

  static const _layoutEngine = WeftLayoutEngine();

  WeftDocumentSnapshot _document;
  TextSelectionRange? _selection;
  TextScaler _textScaler;
  WeftImageResolver? _imageResolver;
  ImageConfiguration _imageConfiguration;
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
    final rects = _selectionRectsFor(layout, selection);
    final paint = Paint()..color = const Color(0x339E9E9E);
    for (final rect in rects) {
      final clipped = rect.intersect(visible);
      if (!clipped.isEmpty) {
        canvas.drawRect(clipped, paint);
      }
    }
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
