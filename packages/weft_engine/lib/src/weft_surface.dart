import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart'
    show
        OrdinalSortKey,
        RenderAbstractViewport,
        SemanticsConfiguration,
        SemanticsNode,
        SemanticsRole;
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
    this.onSemanticsLinkTap,
    this.onSemanticsCopy,
    this.enableLazyLayout = false,
    this.viewportHeight,
    this.initialViewportPixels = 0,
    this.onLazyExtentCorrection,
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

  /// Activates links through assistive technology. Defaults to [onLinkTap];
  /// WeftView supplies this separately so pointer gestures keep one owner.
  final ValueChanged<WeftLinkRegion>? onSemanticsLinkTap;
  final ValueChanged<String>? onSemanticsCopy;
  final bool enableLazyLayout;
  final double? viewportHeight;
  final double initialViewportPixels;
  final ValueChanged<double>? onLazyExtentCorrection;

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
      onSemanticsLinkTap: widget.onSemanticsLinkTap ?? widget.onLinkTap,
      onSemanticsCopy: widget.onSemanticsCopy,
      enableLazyLayout: widget.enableLazyLayout,
      viewportHeight: widget.viewportHeight,
      initialViewportPixels: widget.initialViewportPixels,
      onLazyExtentCorrection: widget.onLazyExtentCorrection,
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
    this.onSemanticsLinkTap,
    this.onSemanticsCopy,
    this.enableLazyLayout = false,
    this.viewportHeight,
    this.initialViewportPixels = 0,
    this.onLazyExtentCorrection,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
  });

  final WeftDocumentSnapshot document;
  final TextSelectionRange? selection;
  final TextScaler textScaler;
  final WeftImageResolver? imageResolver;
  final ValueChanged<WeftLinkRegion>? onSemanticsLinkTap;
  final ValueChanged<String>? onSemanticsCopy;
  final bool enableLazyLayout;
  final double? viewportHeight;
  final double initialViewportPixels;
  final ValueChanged<double>? onLazyExtentCorrection;
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
      onSemanticsLinkTap: onSemanticsLinkTap,
      onSemanticsCopy: onSemanticsCopy,
      enableLazyLayout: enableLazyLayout,
      viewportHeight: viewportHeight,
      initialViewportPixels: initialViewportPixels,
      onLazyExtentCorrection: onLazyExtentCorrection,
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
      ..onSemanticsLinkTap = onSemanticsLinkTap
      ..onSemanticsCopy = onSemanticsCopy
      ..enableLazyLayout = enableLazyLayout
      ..viewportHeight = viewportHeight
      ..onLazyExtentCorrection = onLazyExtentCorrection
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
    ValueChanged<WeftLinkRegion>? onSemanticsLinkTap,
    ValueChanged<String>? onSemanticsCopy,
    bool enableLazyLayout = false,
    double? viewportHeight,
    double initialViewportPixels = 0,
    ValueChanged<double>? onLazyExtentCorrection,
    ImageConfiguration imageConfiguration = ImageConfiguration.empty,
    bool showSelectionHandles = true,
    bool showCaret = true,
    bool showCopyButton = true,
  })  : _document = document,
        _selection = selection,
        _textScaler = textScaler,
        _imageResolver = imageResolver,
        _onSemanticsLinkTap = onSemanticsLinkTap,
        _onSemanticsCopy = onSemanticsCopy,
        _enableLazyLayout = enableLazyLayout,
        _viewportHeight = viewportHeight,
        _viewportPixels = initialViewportPixels,
        _onLazyExtentCorrection = onLazyExtentCorrection,
        _imageConfiguration = imageConfiguration,
        _showSelectionHandles = showSelectionHandles,
        _showCaret = showCaret,
        _showCopyButton = showCopyButton {
    if (selection != null) {
      _fullLayoutRequired = true;
      _debugFullLayoutReason = 'selection';
    }
  }

  static const _layoutEngine = WeftLayoutEngine();

  WeftDocumentSnapshot _document;
  TextSelectionRange? _selection;
  TextScaler _textScaler;
  WeftImageResolver? _imageResolver;
  ValueChanged<WeftLinkRegion>? _onSemanticsLinkTap;
  ValueChanged<String>? _onSemanticsCopy;
  bool _enableLazyLayout;
  double? _viewportHeight;
  double _viewportPixels;
  ValueChanged<double>? _onLazyExtentCorrection;
  bool _fullLayoutRequired = false;
  String? _debugFullLayoutReason;
  bool _followLazyBottom = false;
  bool _lazyCorrectionScheduled = false;
  double _pendingLazyCorrection = 0;
  int _lazyGeneration = 0;
  int _anchorMeasureGeneration = 0;
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

  WeftLayoutResult? _semanticsFragmentsLayout;
  List<_WeftSemanticFragment> _semanticsFragments =
      const <_WeftSemanticFragment>[];
  Map<Key, SemanticsNode> _semanticsChildNodes = <Key, SemanticsNode>{};
  Map<Key, ui.Rect> _semanticAbsoluteRects = <Key, ui.Rect>{};

  WeftDocumentSnapshot get document => _document;

  set document(WeftDocumentSnapshot value) {
    if (identical(_document, value)) return;
    final documentIdChanged = _document.id != value.id;
    _document = value;
    _invalidateLayout(preservePrevious: true);
    if (documentIdChanged) {
      _clearImages();
      _semanticsChildNodes.clear();
      _semanticAbsoluteRects.clear();
      _fullLayoutRequired = false;
      _debugFullLayoutReason = null;
      _exitLazyMode();
    }
  }

  TextSelectionRange? get selection => _selection;

  set selection(TextSelectionRange? value) {
    if (_selection == value) return;
    _selection = value;
    if (value != null) _requireFullLayout('selection');
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ValueChanged<WeftLinkRegion>? get onSemanticsLinkTap => _onSemanticsLinkTap;

  set onSemanticsLinkTap(ValueChanged<WeftLinkRegion>? value) {
    if (identical(_onSemanticsLinkTap, value)) return;
    _onSemanticsLinkTap = value;
    markNeedsSemanticsUpdate();
  }

  ValueChanged<String>? get onSemanticsCopy => _onSemanticsCopy;

  set onSemanticsCopy(ValueChanged<String>? value) {
    if (identical(_onSemanticsCopy, value)) return;
    _onSemanticsCopy = value;
    markNeedsSemanticsUpdate();
  }

  bool get enableLazyLayout => _enableLazyLayout;

  set enableLazyLayout(bool value) {
    if (_enableLazyLayout == value) return;
    _enableLazyLayout = value;
    if (!value) _exitLazyMode();
    _invalidateLayout();
  }

  double? get viewportHeight => _viewportHeight;

  set viewportHeight(double? value) {
    if (_viewportHeight == value) return;
    _viewportHeight = value;
    if (value == null || value <= 0) _exitLazyMode();
    markNeedsLayout();
  }

  set onLazyExtentCorrection(ValueChanged<double>? value) {
    _onLazyExtentCorrection = value;
  }

  void setViewportPixels(double value) {
    if (_viewportPixels == value) return;
    _viewportPixels = value;
    if (_layout?.debugIsLazy != true) return;
    _updateLazyBottomFollow();
    if (_needsLazyRelayout()) markNeedsLayout();
  }

  void _exitLazyMode() {
    _followLazyBottom = false;
    _pendingLazyCorrection = 0;
    _lazyCorrectionScheduled = false;
    _lazyGeneration += 1;
  }

  void _markFullLayoutRequired(String reason) {
    if (!_fullLayoutRequired) {
      _fullLayoutRequired = true;
      _debugFullLayoutReason = reason;
    }
    _exitLazyMode();
    _anchorMeasureGeneration += 1;
  }

  void _requireFullLayout(String reason) {
    final hadLazyLayout = _layout?.debugIsLazy == true;
    _markFullLayoutRequired(reason);
    if (hadLazyLayout) _invalidateLayout();
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

  @visibleForTesting
  bool get debugFullLayoutRequired => _fullLayoutRequired;

  @visibleForTesting
  String? get debugFullLayoutReason => _debugFullLayoutReason;

  @visibleForTesting
  double get debugViewportPixels => _viewportPixels;

  @visibleForTesting
  bool get debugFollowLazyBottom => _followLazyBottom;

  @visibleForTesting
  double get debugPendingLazyCorrection => _pendingLazyCorrection;

  void _invalidateLayout({bool preservePrevious = false}) {
    if (preservePrevious) {
      _discardSelectionCache();
    } else {
      _discardPaintCache();
      _layout?.dispose();
      _layout = null;
    }
    markNeedsLayout();
  }

  void _discardPaintCache() {
    _chunks = null;
    _chunksLayout = null;
    for (final picture in _chunkPictures.values) {
      picture.dispose();
    }
    _chunkPictures.clear();
    _discardSelectionCache();
  }

  void _discardSelectionCache() {
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
    if (_selection != null && !_fullLayoutRequired) {
      _markFullLayoutRequired('selection');
    }
    final width = constraints.maxWidth;
    final previous = _layout;
    final viewportHeight = _viewportHeight;
    final useLazy = _enableLazyLayout &&
        !_fullLayoutRequired &&
        viewportHeight != null &&
        viewportHeight > 0;
    if (useLazy && previous?.debugIsLazy == true) {
      _updateLazyBottomFollow();
    }
    final oldHeight = previous?.size.height ?? 0;
    final current = useLazy
        ? _layoutEngine.layoutViewport(
            _document,
            width: width,
            viewportStart: math.max(0, _viewportPixels - 250),
            viewportEnd: _viewportPixels + viewportHeight + 250,
            textScaler: _textScaler,
            images: _resolvedImages,
            previous: previous,
          )
        : _layoutEngine.layout(
            _document,
            width: width,
            textScaler: _textScaler,
            images: _resolvedImages,
            previous: previous,
          );
    if (useLazy && !current.debugIsLazy) {
      _markFullLayoutRequired('engine-fallback');
    }
    // Hand the laid-out snapshot to the result so hit queries can build
    // their chunk index (ADR 0020); without it they fall back to full scans.
    current.attachDocument(_document);
    _layout = current;
    previous?.dispose();
    size = constraints.constrain(Size(width, current.size.height));
    if (current.debugIsLazy) {
      _scheduleLazyExtentCorrection(oldHeight, current.size.height);
    }
  }

  bool _needsLazyRelayout() {
    if (_fullLayoutRequired) return false;
    final layout = _layout;
    final cache = layout?.incrementalCache;
    final viewportHeight = _viewportHeight;
    final body = _document.body;
    if (layout?.debugIsLazy != true ||
        cache == null ||
        viewportHeight == null ||
        body == null) {
      return false;
    }
    final start = math.max(0, _viewportPixels - 250);
    final end = _viewportPixels + viewportHeight + 250;
    for (final block in cache.blocks) {
      final needed = (block.top < end && block.top + block.height > start) ||
          (block.paintBounds.top < end && block.paintBounds.bottom > start);
      if (needed != block.materialized) return true;
    }
    if (cache.measuredPrefixLength < body.children.length) {
      if (cache.blocks.isEmpty) return true;
      final last = cache.blocks.last;
      return end > last.top + last.height;
    }
    return false;
  }

  void _updateLazyBottomFollow() {
    final cache = _layout?.incrementalCache;
    final viewportHeight = _viewportHeight;
    final childCount = _document.body?.children.length ?? 0;
    _followLazyBottom = !_fullLayoutRequired &&
        cache != null &&
        cache.isLazy &&
        cache.document.id == _document.id &&
        viewportHeight != null &&
        cache.measuredPrefixLength < childCount &&
        _viewportPixels >=
            math.max(0, _layout!.size.height - viewportHeight) - 1;
  }

  void _scheduleLazyExtentCorrection(double oldHeight, double newHeight) {
    if (!_followLazyBottom || oldHeight <= 0 || oldHeight == newHeight) return;
    _pendingLazyCorrection += newHeight - oldHeight;
    if (_lazyCorrectionScheduled) return;
    _lazyCorrectionScheduled = true;
    final expectedPixels = _viewportPixels;
    final generation = _lazyGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (generation != _lazyGeneration) return;
      _lazyCorrectionScheduled = false;
      if (!attached ||
          _fullLayoutRequired ||
          _layout?.debugIsLazy != true ||
          !_followLazyBottom ||
          _viewportPixels != expectedPixels ||
          _pendingLazyCorrection == 0) {
        _pendingLazyCorrection = 0;
        return;
      }
      final correction = _pendingLazyCorrection;
      _pendingLazyCorrection = 0;
      _onLazyExtentCorrection?.call(correction);
    });
  }

  void _ensureFullLayoutForQuery(String reason) {
    final previous = _layout;
    if (previous?.debugIsLazy != true) return;
    _markFullLayoutRequired(reason);
    final current = _layoutEngine.layout(
      _document,
      width: size.width,
      textScaler: _textScaler,
      images: _resolvedImages,
      previous: previous,
    );
    current.attachDocument(_document);
    _layout = current;
    previous?.dispose();
    markNeedsLayout();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    _ensureFullLayoutForQuery('semantics');
    final layout = _layout;
    final fragments = <_WeftSemanticFragment>[];
    if (layout != null) {
      if (!identical(_semanticsFragmentsLayout, layout)) {
        _semanticsFragmentsLayout = layout;
        _semanticsFragments = _buildContentSemantics(
          document: _document,
          layout: layout,
          bounds: Offset.zero & layout.size,
        );
      }
      fragments.addAll(_semanticsFragments);
      final selection = _selection;
      if (selection != null && !selection.isCollapsed) {
        final text = layout.selectionText(selection);
        final rect = _clippedSemanticsRect(
          _unionRects(_selectionRectsFor(layout, selection)),
          Offset.zero & layout.size,
        );
        if (text != null && text.isNotEmpty && rect != null) {
          fragments.add(
            _WeftSemanticFragment(
              key: const ValueKey<String>('weft-selection'),
              rect: rect,
              value: text,
              isSelected: true,
              isSelection: true,
            ),
          );
        }
      }
    }

    final nextCache = <Key, SemanticsNode>{};
    final nextAbsoluteRects = <Key, ui.Rect>{};
    final parentClip = node.parentPaintClipRect;

    SemanticsNode buildNode(_WeftSemanticFragment fragment, int index) {
      final child = _semanticsChildNodes[fragment.key] ??
          SemanticsNode(
            key: fragment.key,
            showOnScreen: _createSemanticsShowOnScreen(fragment.key),
          );
      final childConfig = SemanticsConfiguration()
        ..sortKey = OrdinalSortKey(index.toDouble());
      if (fragment.role != null) {
        childConfig.role = fragment.role!;
      } else {
        childConfig
          ..textDirection = TextDirection.ltr
          ..label = fragment.label
          ..value = fragment.value
          ..isImage = fragment.isImage
          ..isSelected = fragment.isSelected
          ..isHeader = fragment.isHeader
          ..isLink = fragment.link != null;
        final link = fragment.link;
        if (link != null && _onSemanticsLinkTap != null) {
          childConfig.onTap = () => _onSemanticsLinkTap?.call(link);
        }
        if (fragment.isSelection && _onSemanticsCopy != null) {
          childConfig.onCopy = () => _onSemanticsCopy?.call(fragment.value);
        }
      }
      if (parentClip != null) {
        childConfig.isHidden =
            parentClip.intersect(fragment.documentRect).isEmpty &&
                !fragment.documentRect.isEmpty;
      }
      final childNodes = <SemanticsNode>[
        for (var i = 0; i < fragment.children.length; i++)
          buildNode(fragment.children[i], i),
      ];
      child
        ..updateWith(
          config: childConfig,
          childrenInInversePaintOrder: childNodes,
        )
        ..rect = fragment.rect;
      nextCache[fragment.key] = child;
      nextAbsoluteRects[fragment.key] = fragment.documentRect;
      return child;
    }

    final nextChildren = <SemanticsNode>[
      for (var i = 0; i < fragments.length; i++) buildNode(fragments[i], i),
    ];
    _semanticsChildNodes = nextCache;
    _semanticAbsoluteRects = nextAbsoluteRects;
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: nextChildren,
    );
  }

  VoidCallback _createSemanticsShowOnScreen(Key key) {
    return () {
      if (!attached) return;
      final node = _semanticsChildNodes[key];
      final rect = _semanticAbsoluteRects[key];
      if (node == null || rect == null) return;
      showOnScreen(descendant: this, rect: rect);
    };
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _semanticsFragmentsLayout = null;
    _semanticsFragments = const <_WeftSemanticFragment>[];
    _semanticsChildNodes.clear();
    _semanticAbsoluteRects.clear();
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
    if (_layout?.debugIsLazy == true) {
      _markFullLayoutRequired('image');
    }
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

  /// The painted rectangle for the one-character range starting at [anchor],
  /// in surface-local coordinates, or null when the anchor does not resolve.
  ///
  /// A lazy layout upgrades to the complete layout to obtain exact geometry.
  /// Invalid anchors are rejected before that upgrade, following the
  /// selection model's safe-drop semantics.
  ui.Rect? textRectForAnchor(TextAnchor anchor) {
    if (!hasSize || size.width <= 0) return null;
    final before = _layout;
    final entry = before?.textIndex?.entryByNode[anchor.nodeId];
    if (before == null ||
        entry == null ||
        anchor.offset < 0 ||
        anchor.offset >= entry.text.length) {
      return null;
    }
    final viewportHeight = _viewportHeight;
    if (before.debugIsLazy &&
        !_fullLayoutRequired &&
        _enableLazyLayout &&
        viewportHeight != null &&
        viewportHeight > 0) {
      _exitLazyMode();
      final focused = _layoutEngine.layoutViewport(
        _document,
        width: size.width,
        viewportStart: math.max(0, _viewportPixels - 250),
        viewportEnd: _viewportPixels + viewportHeight + 250,
        focusNodeId: anchor.nodeId,
        textScaler: _textScaler,
        images: _resolvedImages,
        previous: before,
      );
      focused.attachDocument(_document);
      _layout = focused;
      before.dispose();
      if (!focused.debugIsLazy) {
        _markFullLayoutRequired('engine-fallback');
      }
      markNeedsLayout();
    } else {
      _ensureFullLayoutForQuery('anchor');
    }
    var layout = _layout;
    if (layout == null) return null;
    var rect = _unionRects(
      layout.textRectsForNode(anchor.nodeId, anchor.offset, anchor.offset + 1),
    );
    if (rect == null && layout.debugIsLazy) {
      _ensureFullLayoutForQuery('anchor');
      layout = _layout;
      if (layout == null) return null;
      rect = _unionRects(
        layout.textRectsForNode(
            anchor.nodeId, anchor.offset, anchor.offset + 1),
      );
    }
    return rect;
  }

  Future<ui.Rect?> measureAnchorAsync(
    TextAnchor anchor, {
    int maxNewBlocks = 32,
  }) async {
    assert(maxNewBlocks > 0);
    if (maxNewBlocks <= 0 || !hasSize || size.width <= 0) return null;
    var layout = _layout;
    final entry = layout?.textIndex?.entryByNode[anchor.nodeId];
    if (layout == null ||
        entry == null ||
        anchor.offset < 0 ||
        anchor.offset >= entry.text.length) {
      return null;
    }
    ui.Rect? available() => _unionRects(
          layout!.textRectsForNode(
            anchor.nodeId,
            anchor.offset,
            anchor.offset + 1,
          ),
        );
    final immediate = available();
    if (immediate != null) return immediate;
    if (!layout.debugIsLazy || _fullLayoutRequired) return null;
    final viewportHeight = _viewportHeight;
    if (!_enableLazyLayout || viewportHeight == null || viewportHeight <= 0) {
      return null;
    }

    final generation = ++_anchorMeasureGeneration;
    while (attached && generation == _anchorMeasureGeneration) {
      final previous = _layout;
      if (previous?.debugIsLazy != true) return null;
      final previousPrefix =
          previous!.incrementalCache?.measuredPrefixLength ?? 0;
      _exitLazyMode();
      final focused = _layoutEngine.layoutViewport(
        _document,
        width: size.width,
        viewportStart: math.max(0, _viewportPixels - 250),
        viewportEnd: _viewportPixels + viewportHeight + 250,
        focusNodeId: anchor.nodeId,
        maxNewBlocks: maxNewBlocks,
        textScaler: _textScaler,
        images: _resolvedImages,
        previous: previous,
      );
      focused.attachDocument(_document);
      _layout = focused;
      layout = focused;
      previous.dispose();
      if (!focused.debugIsLazy) {
        _markFullLayoutRequired('engine-fallback');
        return null;
      }
      markNeedsLayout();
      final rect = available();
      if (rect != null) return rect;
      if ((focused.incrementalCache?.measuredPrefixLength ?? 0) <=
          previousPrefix) {
        return null;
      }
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    return null;
  }

  /// The first painted text anchor inside [nodeId], or null when the node or
  /// its painted text cannot be resolved.
  TextAnchor? firstTextAnchorInNode(NodeId nodeId) {
    final layout = _layout;
    final body = _document.body;
    final index = layout?.textIndex;
    if (layout == null || body == null || index == null) return null;

    TextAnchor? first(WeftNode node) {
      if (node is WeftText) {
        final entry = index.entryByNode[node.id];
        if (entry != null && entry.text.isNotEmpty) {
          return TextAnchor(entry.nodeId, 0);
        }
        return null;
      }
      if (node is! WeftElement) return null;
      for (final child in node.children) {
        final found = first(child);
        if (found != null) return found;
      }
      return null;
    }

    WeftNode? located;
    bool visit(WeftNode node) {
      if (node.id == nodeId) {
        located = node;
        return true;
      }
      if (node is WeftElement) {
        for (final child in node.children) {
          if (visit(child)) return true;
        }
      }
      return false;
    }

    if (!visit(body) || located == null) return null;
    return first(located!);
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
    if (!identical(_chunksLayout, layout) || _chunks == null) {
      _updateChunks(layout);
    }
    final chunks = _chunks!;
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

  void _updateChunks(WeftLayoutResult layout) {
    final nextChunks = WeftChunk.partition(
      document: _document,
      commands: layout.commands,
    );
    final oldChunks = <int, WeftChunk>{
      for (final chunk in _chunks ?? const <WeftChunk>[]) chunk.key: chunk,
    };
    final retained = <int, ui.Picture>{};
    for (final chunk in nextChunks) {
      final old = oldChunks[chunk.key];
      final picture = _chunkPictures[chunk.key];
      if (old != null && picture != null && _sameChunk(old, chunk)) {
        retained[chunk.key] = picture;
      }
    }
    for (final entry in _chunkPictures.entries) {
      if (!identical(retained[entry.key], entry.value)) entry.value.dispose();
    }
    _chunkPictures
      ..clear()
      ..addAll(retained);
    _chunks = nextChunks;
    _chunksLayout = layout;
    _discardSelectionCache();
  }

  bool _sameChunk(WeftChunk first, WeftChunk second) {
    if (first.bounds != second.bounds ||
        first.commands.length != second.commands.length) {
      return false;
    }
    for (var i = 0; i < first.commands.length; i++) {
      if (!identical(first.commands[i], second.commands[i])) return false;
    }
    return true;
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
    _anchorMeasureGeneration += 1;
    _exitLazyMode();
    _discardPaintCache();
    _layout?.dispose();
    _layout = null;
    _clearImages();
    super.dispose();
  }
}

final class _WeftSemanticContainerSpec {
  const _WeftSemanticContainerSpec({required this.id, required this.role});

  final NodeId id;
  final SemanticsRole role;
}

final class _WeftSemanticFragment {
  const _WeftSemanticFragment({
    required this.key,
    required this.rect,
    this.absoluteRect,
    this.role,
    this.children = const [],
    this.containers = const [],
    this.label = '',
    this.value = '',
    this.isImage = false,
    this.isSelected = false,
    this.isSelection = false,
    this.isHeader = false,
    this.headingLevel = 0,
    this.link,
    this.globalStart,
    this.globalEnd,
  });

  final Key key;
  final ui.Rect rect;
  final ui.Rect? absoluteRect;
  final SemanticsRole? role;
  final List<_WeftSemanticFragment> children;
  final List<_WeftSemanticContainerSpec> containers;
  ui.Rect get documentRect => absoluteRect ?? rect;
  final String label;
  final String value;
  final bool isImage;
  final bool isSelected;
  final bool isSelection;
  final bool isHeader;
  final int headingLevel;
  final WeftLinkRegion? link;
  final int? globalStart;
  final int? globalEnd;

  _WeftSemanticFragment withRect(ui.Rect localRect) {
    return _WeftSemanticFragment(
      key: key,
      rect: localRect,
      absoluteRect: documentRect,
      label: label,
      value: value,
      isImage: isImage,
      isSelected: isSelected,
      isSelection: isSelection,
      isHeader: isHeader,
      headingLevel: headingLevel,
      link: link,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
  }
}

final class _SemanticTreeBuilder {
  _SemanticTreeBuilder(this.spec);

  final _WeftSemanticContainerSpec? spec;
  final List<Object> entries = <Object>[];
  final Map<String, _SemanticTreeBuilder> children =
      <String, _SemanticTreeBuilder>{};

  ui.Rect get absoluteBounds {
    ui.Rect? bounds;
    for (final entry in entries) {
      final rect = entry is _WeftSemanticFragment
          ? entry.documentRect
          : (entry as _SemanticTreeBuilder).absoluteBounds;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds ?? ui.Rect.zero;
  }
}

List<_WeftSemanticFragment> _buildSemanticForest(
  List<_WeftSemanticFragment> leaves,
) {
  final root = _SemanticTreeBuilder(null);
  for (final leaf in leaves) {
    var cursor = root;
    for (final spec in leaf.containers) {
      final key = '${spec.role.name}:${spec.id}';
      final existing = cursor.children[key];
      if (existing != null) {
        cursor = existing;
      } else {
        final child = _SemanticTreeBuilder(spec);
        cursor.children[key] = child;
        cursor.entries.add(child);
        cursor = child;
      }
    }
    cursor.entries.add(leaf);
  }

  List<_WeftSemanticFragment> convert(
    _SemanticTreeBuilder builder,
    ui.Offset parentOrigin,
  ) {
    final result = <_WeftSemanticFragment>[];
    for (final entry in builder.entries) {
      if (entry is _WeftSemanticFragment) {
        result.add(entry.withRect(entry.documentRect.shift(-parentOrigin)));
        continue;
      }
      final child = entry as _SemanticTreeBuilder;
      final absolute = child.absoluteBounds;
      final spec = child.spec!;
      result.add(
        _WeftSemanticFragment(
          key: ValueKey<String>('role-${spec.role.name}:${spec.id}'),
          rect: absolute.shift(-parentOrigin),
          absoluteRect: absolute,
          role: spec.role,
          children: convert(child, absolute.topLeft),
        ),
      );
    }
    return result;
  }

  return convert(root, ui.Offset.zero);
}

bool _sameContainers(
  List<_WeftSemanticContainerSpec> first,
  List<_WeftSemanticContainerSpec> second,
) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (!identical(first[i], second[i])) return false;
  }
  return true;
}

List<_WeftSemanticFragment> _buildContentSemantics({
  required WeftDocumentSnapshot document,
  required WeftLayoutResult layout,
  required ui.Rect bounds,
}) {
  final textIndex = layout.textIndex;
  final body = document.body;
  if (textIndex == null || body == null) return const [];
  final links = <int, WeftLinkRegion>{
    for (final link in layout.links) link.nodeId: link,
  };
  final images = <int, WeftImagePaintCommand>{
    for (final command in layout.commands.whereType<WeftImagePaintCommand>())
      command.nodeId: command,
  };
  final fragments = <_WeftSemanticFragment>[];
  final activeContainers = <_WeftSemanticContainerSpec>[];

  void addText(
    int nodeId,
    String text,
    WeftLinkRegion? link,
    int headingLevel,
    bool isHeader,
    List<String?>? prefixBox, {
    int? entryGlobalStart,
  }) {
    var start = 0;
    for (var i = 0; i <= text.length; i++) {
      if (i < text.length && text.codeUnitAt(i) != 0x0A) continue;
      if (i > start) {
        final rect = _clippedSemanticsRect(
          _unionRects(layout.textRectsForNode(nodeId, start, i)),
          bounds,
        );
        if (rect != null) {
          final globalStart =
              entryGlobalStart == null ? null : entryGlobalStart + start;
          final globalEnd =
              entryGlobalStart == null ? null : entryGlobalStart + i;
          final key = ValueKey<String>(
            '${link == null ? 'text' : 'link-${link.nodeId}'}:$nodeId:$start',
          );
          final previous = fragments.isEmpty ? null : fragments.last;
          final canMerge = previous != null &&
              !previous.isImage &&
              !previous.isSelected &&
              previous.link?.nodeId == link?.nodeId &&
              _sameContainers(previous.containers, activeContainers) &&
              previous.isHeader == isHeader &&
              previous.headingLevel == headingLevel &&
              previous.globalEnd != null &&
              previous.globalEnd == globalStart;
          if (canMerge) {
            fragments[fragments.length - 1] = _WeftSemanticFragment(
              key: previous.key,
              rect: previous.rect.expandToInclude(rect),
              label: previous.label + text.substring(start, i),
              link: previous.link,
              containers: previous.containers,
              isHeader: previous.isHeader,
              headingLevel: previous.headingLevel,
              globalStart: previous.globalStart,
              globalEnd: globalEnd,
            );
          } else {
            final prefix = prefixBox?[0] ?? '';
            if (prefix.isNotEmpty) prefixBox![0] = null;
            fragments.add(
              _WeftSemanticFragment(
                key: key,
                rect: rect,
                label: '$prefix${text.substring(start, i)}',
                link: link,
                containers: List<_WeftSemanticContainerSpec>.unmodifiable(
                  activeContainers,
                ),
                isHeader: isHeader,
                headingLevel: headingLevel,
                globalStart: globalStart,
                globalEnd: globalEnd,
              ),
            );
          }
        }
      }
      start = i + 1;
    }
  }

  void visit(
    WeftNode node,
    WeftLinkRegion? currentLink,
    int headingLevel,
    bool isHeader,
    List<String?>? prefixBox,
  ) {
    if (node is WeftText) {
      final entry = textIndex.entryByNode[node.id];
      if (entry != null) {
        addText(
          node.id,
          entry.text,
          currentLink,
          headingLevel,
          isHeader,
          prefixBox,
          entryGlobalStart: entry.globalStart,
        );
      }
      return;
    }
    if (node is! WeftElement) return;
    if (node.tag == 'img') {
      final image = images[node.id];
      final alt = node.attribute('alt')?.trim() ?? '';
      if (image != null) {
        final rect = _clippedSemanticsRect(image.destination, bounds);
        if (alt.isNotEmpty && rect != null) {
          final prefix = prefixBox?[0] ?? '';
          if (prefix.isNotEmpty) prefixBox![0] = null;
          fragments.add(
            _WeftSemanticFragment(
              key: ValueKey<String>('image:${node.id}'),
              rect: rect,
              label: '$prefix$alt',
              isImage: true,
              containers: List<_WeftSemanticContainerSpec>.unmodifiable(
                activeContainers,
              ),
              isHeader: isHeader,
              headingLevel: headingLevel,
            ),
          );
        }
      } else if (alt.isNotEmpty) {
        addText(
          node.id,
          alt,
          currentLink,
          headingLevel,
          isHeader,
          prefixBox,
        );
      }
      return;
    }
    final link = node.tag == 'a' ? links[node.id] : currentLink;
    final childHeading = switch (node.tag) {
      'h1' => 1,
      'h2' => 2,
      'h3' => 3,
      'h4' => 4,
      'h5' => 5,
      'h6' => 6,
      _ => headingLevel,
    };
    final childHeader = isHeader ||
        node.tag == 'th' ||
        node.tag == 'h1' ||
        node.tag == 'h2' ||
        node.tag == 'h3' ||
        node.tag == 'h4' ||
        node.tag == 'h5' ||
        node.tag == 'h6';
    if (node.tag == 'ul' || node.tag == 'ol') {
      activeContainers.add(
        _WeftSemanticContainerSpec(id: node.id, role: SemanticsRole.list),
      );
      var itemIndex = 0;
      for (final child in node.children) {
        List<String?>? childPrefix;
        if (child is WeftElement && child.tag == 'li') {
          itemIndex += 1;
          childPrefix = <String?>[
            node.tag == 'ol' ? '$itemIndex. ' : '• ',
          ];
          activeContainers.add(
            _WeftSemanticContainerSpec(
              id: child.id,
              role: SemanticsRole.listItem,
            ),
          );
          visit(child, link, childHeading, childHeader, childPrefix);
          activeContainers.removeLast();
        } else {
          visit(child, link, childHeading, childHeader, childPrefix);
        }
      }
      activeContainers.removeLast();
      return;
    }
    if (node.tag == 'table') {
      for (final child in node.children) {
        if (child is WeftElement && child.tag == 'caption') {
          visit(child, link, childHeading, childHeader, null);
        }
      }
      activeContainers.add(
        _WeftSemanticContainerSpec(id: node.id, role: SemanticsRole.table),
      );
      void visitRow(WeftElement row) {
        activeContainers.add(
          _WeftSemanticContainerSpec(id: row.id, role: SemanticsRole.row),
        );
        for (final cell in row.children) {
          if (cell is! WeftElement || (cell.tag != 'td' && cell.tag != 'th')) {
            continue;
          }
          activeContainers.add(
            _WeftSemanticContainerSpec(
              id: cell.id,
              role: cell.tag == 'th'
                  ? SemanticsRole.columnHeader
                  : SemanticsRole.cell,
            ),
          );
          visit(cell, link, childHeading, childHeader, null);
          activeContainers.removeLast();
        }
        activeContainers.removeLast();
      }

      for (final child in node.children) {
        if (child is! WeftElement) continue;
        if (child.tag == 'tr') {
          visitRow(child);
        } else if (child.tag == 'thead' ||
            child.tag == 'tbody' ||
            child.tag == 'tfoot') {
          for (final row in child.children) {
            if (row is WeftElement && row.tag == 'tr') visitRow(row);
          }
        }
      }
      activeContainers.removeLast();
      return;
    }
    for (final child in node.children) {
      visit(child, link, childHeading, childHeader, prefixBox);
    }
  }

  for (final child in body.children) {
    visit(child, null, 0, false, null);
  }
  return _buildSemanticForest(fragments);
}

ui.Rect? _unionRects(Iterable<ui.Rect> rects) {
  ui.Rect? result;
  for (final rect in rects) {
    if (!rect.isFinite || rect.isEmpty) continue;
    result = result == null ? rect : result.expandToInclude(rect);
  }
  return result;
}

ui.Rect? _clippedSemanticsRect(ui.Rect? rect, ui.Rect bounds) {
  if (rect == null ||
      !rect.isFinite ||
      rect.isEmpty ||
      !rect.overlaps(bounds)) {
    return null;
  }
  final clipped = rect.intersect(bounds);
  return clipped.isEmpty ? null : clipped;
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
