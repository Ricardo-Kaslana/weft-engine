import 'dart:ui' as ui;

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

  void _invalidateLayout() {
    _layout?.dispose();
    _layout = null;
    markNeedsLayout();
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

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    context.canvas.save();
    context.canvas.clipRect(offset & size);
    for (final command in layout.commands) {
      command.paint(context.canvas, offset);
    }
    final selection = _selection;
    if (selection != null) {
      final rects = layout.selectionRects(selection);
      final paint = Paint()..color = const Color(0x339E9E9E);
      for (final rect in rects) {
        context.canvas.drawRect(rect.shift(offset), paint);
      }
    }
    context.canvas.restore();
  }

  @override
  void dispose() {
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
