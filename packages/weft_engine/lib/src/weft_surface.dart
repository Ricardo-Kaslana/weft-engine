import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';

import 'layout_engine.dart';
import 'layout_result.dart';

class WeftSurface extends StatefulWidget {
  const WeftSurface({
    super.key,
    required this.document,
    this.selection,
    this.textScaler = TextScaler.noScaling,
    this.onLinkTap,
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
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
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;

  @override
  RenderWeftSurface createRenderObject(BuildContext context) {
    return RenderWeftSurface(
      document: document,
      selection: selection,
      textScaler: textScaler,
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
      ..textScaler = textScaler;
  }
}

class RenderWeftSurface extends RenderBox {
  RenderWeftSurface({
    required WeftDocumentSnapshot document,
    TextSelectionRange? selection,
    TextScaler textScaler = TextScaler.noScaling,
  })  : _document = document,
        _selection = selection,
        _textScaler = textScaler;

  static const _layoutEngine = WeftLayoutEngine();

  WeftDocumentSnapshot _document;
  TextSelectionRange? _selection;
  TextScaler _textScaler;
  WeftLayoutResult? _layout;

  WeftDocumentSnapshot get document => _document;

  set document(WeftDocumentSnapshot value) {
    if (identical(_document, value)) return;
    _document = value;
    _layout?.dispose();
    _layout = null;
    markNeedsLayout();
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

    final width = constraints.maxWidth;
    final previous = _layout;
    final current = _layoutEngine.layout(
      _document,
      width: width,
      textScaler: _textScaler,
    );
    _layout = current;
    previous?.dispose();
    size = constraints.constrain(Size(width, current.size.height));
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
    context.canvas.restore();
  }

  @override
  void dispose() {
    _layout?.dispose();
    _layout = null;
    super.dispose();
  }
}
