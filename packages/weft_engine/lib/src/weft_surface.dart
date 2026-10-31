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
import 'tag_renderer.dart';

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
  /// Creates the geometry from the selection's rectangles.
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
  /// Creates a surface that lays out and paints [document].
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
    this.lazyOverscan = 250,
    this.viewportHeight,
    this.initialViewportPixels = 0,
    this.onLazyExtentCorrection,
    this.onLazySettlingChanged,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
    this.copyButtonLabel = '复制',
    this.tagRenderers = const <String, WeftTagRenderer>{},
    this.onTagTap,
  });

  /// The normalized document snapshot to lay out and paint.
  final WeftDocumentSnapshot document;

  /// The active selection, or null when nothing is selected.
  final TextSelectionRange? selection;

  /// Text scaling applied to the laid-out text.
  final TextScaler textScaler;

  /// Resolves document images; null leaves every image unresolved so its
  /// alternative text paints instead.
  final WeftImageResolver? imageResolver;

  /// Called when a tap lands on a link region.
  final ValueChanged<WeftLinkRegion>? onLinkTap;

  /// Activates links through assistive technology. Defaults to [onLinkTap];
  /// WeftView supplies this separately so pointer gestures keep one owner.
  final ValueChanged<WeftLinkRegion>? onSemanticsLinkTap;

  /// Called when copy is triggered through assistive technology, with the
  /// logical text to copy.
  final ValueChanged<String>? onSemanticsCopy;

  /// Whether the surface lays out lazily, materializing only blocks near the
  /// viewport. Requires [viewportHeight].
  final bool enableLazyLayout;

  /// Document pixels laid out beyond the visible viewport before and after.
  final double lazyOverscan;

  /// Height of the visible viewport in pixels; required for lazy layout.
  final double? viewportHeight;

  /// Initial scroll offset within the document, for hosts that manage their
  /// own scrolling.
  final double initialViewportPixels;

  /// Called when a lazy layout corrects its estimated extent, so the host
  /// can adjust its scroll metrics.
  final ValueChanged<double>? onLazyExtentCorrection;

  /// Called when a budgeted lazy pass starts or finishes filling the
  /// viewport window (ADR 0037).
  ///
  /// Surfaces never paint an overlay themselves; hosts use this signal to
  /// place their own placeholder. The callback runs post-frame and reports
  /// each transition once.
  final ValueChanged<bool>? onLazySettlingChanged;

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

  /// Trusted custom tag renderers (ADR 0033). The engine renders a custom
  /// tag as an opaque content box; hosts must also allowlist the tag in
  /// `WeftNormalizer.customTags`.
  final Map<String, WeftTagRenderer> tagRenderers;

  /// Receives taps that land on a custom tag region and not on a link.
  final ValueChanged<WeftTagRegion>? onTagTap;

  @override
  State<WeftSurface> createState() => _WeftSurfaceState();
}

class _WeftSurfaceState extends State<WeftSurface> {
  final _surfaceKey = GlobalKey();

  void _handleTapUp(TapUpDetails details) {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderWeftSurface) return;
    final link = renderObject.linkAt(details.localPosition);
    if (link != null) {
      widget.onLinkTap?.call(link);
      return;
    }
    final tag = renderObject.tagAt(details.localPosition);
    if (tag != null) widget.onTagTap?.call(tag);
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
      lazyOverscan: widget.lazyOverscan,
      viewportHeight: widget.viewportHeight,
      initialViewportPixels: widget.initialViewportPixels,
      onLazyExtentCorrection: widget.onLazyExtentCorrection,
      onLazySettlingChanged: widget.onLazySettlingChanged,
      showSelectionHandles: widget.showSelectionHandles,
      showCaret: widget.showCaret,
      showCopyButton: widget.showCopyButton,
      tagRenderers: widget.tagRenderers,
      onTagTap: widget.onTagTap,
    );
    if (widget.onLinkTap == null && widget.onTagTap == null) return surface;
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
    this.lazyOverscan = 250,
    this.viewportHeight,
    this.initialViewportPixels = 0,
    this.onLazyExtentCorrection,
    this.onLazySettlingChanged,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
    this.tagRenderers = const <String, WeftTagRenderer>{},
    this.onTagTap,
  });

  /// The normalized document snapshot to lay out and paint.
  final WeftDocumentSnapshot document;

  /// The active selection, or null when nothing is selected.
  final TextSelectionRange? selection;

  /// Text scaling applied to the laid-out text.
  final TextScaler textScaler;

  /// Resolves document images; null leaves every image unresolved.
  final WeftImageResolver? imageResolver;

  /// Activates links through assistive technology.
  final ValueChanged<WeftLinkRegion>? onSemanticsLinkTap;

  /// Called when copy is triggered through assistive technology, with the
  /// logical text to copy.
  final ValueChanged<String>? onSemanticsCopy;

  /// Whether the render object lays out lazily; requires [viewportHeight].
  final bool enableLazyLayout;

  /// Document pixels laid out beyond the visible viewport before and after.
  final double lazyOverscan;

  /// Height of the visible viewport in pixels; required for lazy layout.
  final double? viewportHeight;

  /// Initial scroll offset within the document.
  final double initialViewportPixels;

  /// Called when a lazy layout corrects its estimated extent.
  final ValueChanged<double>? onLazyExtentCorrection;

  /// Called when a budgeted lazy pass starts or finishes settling.
  final ValueChanged<bool>? onLazySettlingChanged;

  /// Whether drag handle touch targets are exposed to the view layer.
  final bool showSelectionHandles;

  /// Whether a collapsed selection paints a caret bar on the canvas.
  final bool showCaret;

  /// Whether a copy button placement is suggested to the view layer.
  final bool showCopyButton;

  /// Trusted custom tag renderers (ADR 0033).
  final Map<String, WeftTagRenderer> tagRenderers;

  /// Called when a tap lands on a custom tag region and not on a link.
  final ValueChanged<WeftTagRegion>? onTagTap;

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
      lazyOverscan: lazyOverscan,
      viewportHeight: viewportHeight,
      initialViewportPixels: initialViewportPixels,
      onLazyExtentCorrection: onLazyExtentCorrection,
      onLazySettlingChanged: onLazySettlingChanged,
      imageConfiguration: createLocalImageConfiguration(context),
      showSelectionHandles: showSelectionHandles,
      showCaret: showCaret,
      showCopyButton: showCopyButton,
      tagRenderers: tagRenderers,
      onTagTap: onTagTap,
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
      ..lazyOverscan = lazyOverscan
      ..viewportHeight = viewportHeight
      ..onLazyExtentCorrection = onLazyExtentCorrection
      ..onLazySettlingChanged = onLazySettlingChanged
      ..showSelectionHandles = showSelectionHandles
      ..showCaret = showCaret
      ..showCopyButton = showCopyButton
      ..tagRenderers = tagRenderers
      ..onTagTap = onTagTap;
  }
}

/// Render object that lays out and paints one normalized document on a
/// single surface.
///
/// Beyond painting, it answers hit queries (links, tags, text anchors),
/// exposes selection geometry to the view layer, and publishes a semantic
/// forest for the document. Hosts drive scrolling through
/// [setViewportPixels] and lazy layout through the enable/lazy properties.
class RenderWeftSurface extends RenderBox {
  /// Creates a render object for [document].
  RenderWeftSurface({
    required WeftDocumentSnapshot document,
    TextSelectionRange? selection,
    TextScaler textScaler = TextScaler.noScaling,
    WeftImageResolver? imageResolver,
    ValueChanged<WeftLinkRegion>? onSemanticsLinkTap,
    ValueChanged<String>? onSemanticsCopy,
    bool enableLazyLayout = false,
    double lazyOverscan = 250,
    double? viewportHeight,
    double initialViewportPixels = 0,
    ValueChanged<double>? onLazyExtentCorrection,
    ValueChanged<bool>? onLazySettlingChanged,
    ImageConfiguration imageConfiguration = ImageConfiguration.empty,
    bool showSelectionHandles = true,
    bool showCaret = true,
    bool showCopyButton = true,
    Map<String, WeftTagRenderer> tagRenderers =
        const <String, WeftTagRenderer>{},
    ValueChanged<WeftTagRegion>? onTagTap,
  })  : _document = document,
        _selection = selection,
        _textScaler = textScaler,
        _imageResolver = imageResolver,
        _onSemanticsLinkTap = onSemanticsLinkTap,
        _onSemanticsCopy = onSemanticsCopy,
        _enableLazyLayout = enableLazyLayout,
        _lazyOverscan = lazyOverscan,
        _viewportHeight = viewportHeight,
        _viewportPixels = initialViewportPixels,
        _onLazyExtentCorrection = onLazyExtentCorrection,
        _onLazySettlingChanged = onLazySettlingChanged,
        _imageConfiguration = imageConfiguration,
        _showSelectionHandles = showSelectionHandles,
        _showCaret = showCaret,
        _showCopyButton = showCopyButton,
        _tagRenderers = tagRenderers,
        _onTagTap = onTagTap {
    if (selection != null) {
      _fullLayoutRequired = true;
      _debugFullLayoutReason = 'selection';
    }
  }

  /// Layout engine honouring the active renderer set. Renderer identity
  /// participates in block reuse decisions, so the map instance is kept.
  WeftLayoutEngine get _engine => WeftLayoutEngine(tagRenderers: _tagRenderers);

  /// Cap on newly measured top-level blocks per frame when a scroll move
  /// lands the viewport beyond the measured frontier by more than one screen
  /// (ADR 0031). Bounds the synchronous relayout of deep jumps and cold seeds;
  /// the post-frame continuation advances the frontier across frames until
  /// the window is measured.
  static const int _lazyMeasureBudget = 32;

  WeftDocumentSnapshot _document;
  TextSelectionRange? _selection;
  TextScaler _textScaler;
  WeftImageResolver? _imageResolver;
  ValueChanged<WeftLinkRegion>? _onSemanticsLinkTap;
  ValueChanged<String>? _onSemanticsCopy;
  Map<String, WeftTagRenderer> _tagRenderers;
  ValueChanged<WeftTagRegion>? _onTagTap;
  bool _enableLazyLayout;
  double _lazyOverscan;
  double? _viewportHeight;
  double _viewportPixels;
  ValueChanged<double>? _onLazyExtentCorrection;
  ValueChanged<bool>? _onLazySettlingChanged;
  bool _lazySettling = false;
  bool _reportedLazySettling = false;
  bool _lazySettlingReportScheduled = false;
  bool _fullLayoutRequired = false;
  String? _debugFullLayoutReason;
  bool _followLazyBottom = false;
  bool _lazyCorrectionScheduled = false;
  double _pendingLazyCorrection = 0;
  int _lazyGeneration = 0;
  int _anchorMeasureGeneration = 0;
  bool _lazyMeasureContinuationScheduled = false;
  ImageConfiguration _imageConfiguration;
  bool _showSelectionHandles;
  bool _showCaret;
  bool _showCopyButton;
  WeftLayoutResult? _layout;
  final Map<int, _ResolvedImage> _images = <int, _ResolvedImage>{};
  WeftDocumentSnapshot? _imageRequestsDocument;
  Map<int, WeftImageRequest> _imageRequests = const <int, WeftImageRequest>{};

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
  int _debugLazyCorrectionCount = 0;

  WeftLayoutResult? _semanticsFragmentsLayout;
  List<_WeftSemanticFragment> _semanticsFragments =
      const <_WeftSemanticFragment>[];
  Map<Key, SemanticsNode> _semanticsChildNodes = <Key, SemanticsNode>{};
  Map<Key, ui.Rect> _semanticAbsoluteRects = <Key, ui.Rect>{};

  /// The document snapshot being laid out.
  WeftDocumentSnapshot get document => _document;

  /// Sets the document snapshot; identical snapshots keep the current
  /// layout, and a changed document id also drops resolved images and
  /// semantics state and exits lazy mode.
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

  /// The active selection.
  TextSelectionRange? get selection => _selection;

  /// Sets the selection; a non-null selection forces the next layout to be
  /// a full (non-lazy) layout.
  set selection(TextSelectionRange? value) {
    if (_selection == value) return;
    _selection = value;
    if (value != null) _requireFullLayout('selection');
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// Callback for link activations through assistive technology.
  ValueChanged<WeftLinkRegion>? get onSemanticsLinkTap => _onSemanticsLinkTap;

  /// Sets the callback and refreshes semantics.
  set onSemanticsLinkTap(ValueChanged<WeftLinkRegion>? value) {
    if (identical(_onSemanticsLinkTap, value)) return;
    _onSemanticsLinkTap = value;
    markNeedsSemanticsUpdate();
  }

  /// Callback for copy actions through assistive technology.
  ValueChanged<String>? get onSemanticsCopy => _onSemanticsCopy;

  /// Sets the callback and refreshes semantics.
  set onSemanticsCopy(ValueChanged<String>? value) {
    if (identical(_onSemanticsCopy, value)) return;
    _onSemanticsCopy = value;
    markNeedsSemanticsUpdate();
  }

  /// Trusted custom tag renderers (ADR 0033).
  Map<String, WeftTagRenderer> get tagRenderers => _tagRenderers;

  /// Sets the renderers and relayouts; the map instance participates in
  /// block reuse decisions.
  set tagRenderers(Map<String, WeftTagRenderer> value) {
    if (identical(_tagRenderers, value)) return;
    _tagRenderers = value;
    markNeedsLayout();
  }

  /// Callback for taps that land on a custom tag region and not on a link.
  ValueChanged<WeftTagRegion>? get onTagTap => _onTagTap;

  /// Sets the callback and refreshes semantics.
  set onTagTap(ValueChanged<WeftTagRegion>? value) {
    if (identical(_onTagTap, value)) return;
    _onTagTap = value;
    markNeedsSemanticsUpdate();
  }

  /// Whether lazy layout is enabled.
  bool get enableLazyLayout => _enableLazyLayout;

  /// Enables or disables lazy layout; disabling also exits the current lazy
  /// state.
  set enableLazyLayout(bool value) {
    if (_enableLazyLayout == value) return;
    _enableLazyLayout = value;
    if (!value) _exitLazyMode();
    _invalidateLayout();
  }

  /// Document pixels laid out beyond the visible viewport.
  double get lazyOverscan => _lazyOverscan;

  /// Sets the overscan, clamped to zero or more.
  set lazyOverscan(double value) {
    if (_lazyOverscan == value) return;
    _lazyOverscan = math.max(0, value);
    markNeedsLayout();
  }

  /// Height of the visible viewport in pixels, or null when the host does
  /// not track one.
  double? get viewportHeight => _viewportHeight;

  /// Sets the viewport height; null or non-positive values exit lazy mode.
  set viewportHeight(double? value) {
    if (_viewportHeight == value) return;
    _viewportHeight = value;
    if (value == null || value <= 0) _exitLazyMode();
    markNeedsLayout();
  }

  /// Sets the callback invoked when a lazy pass corrects its estimated
  /// extent.
  set onLazyExtentCorrection(ValueChanged<double>? value) {
    _onLazyExtentCorrection = value;
  }

  /// Whether a budgeted lazy pass is still filling the viewport window.
  ///
  /// True between a deep jump or deep initial seed and the frame that
  /// materializes the target window (ADR 0037). False for synchronous
  /// near-frontier scrolls, async anchor measurement, and after lazy mode
  /// ends. Updated during layout, so reads observe the last completed frame.
  bool get isLazySettling => _lazySettling;

  /// Receives [isLazySettling] transitions from a post-frame callback.
  ///
  /// Never invoked during build or layout, and equal consecutive values are
  /// not repeated. Installing a callback while settling reports true on the
  /// next frame. No callback fires after detach or dispose; hosts must treat
  /// unmount as settled.
  ValueChanged<bool>? get onLazySettlingChanged => _onLazySettlingChanged;

  /// Sets the settling callback; see [onLazySettlingChanged].
  set onLazySettlingChanged(ValueChanged<bool>? value) {
    if (_onLazySettlingChanged == value) return;
    _onLazySettlingChanged = value;
    if (value == null) {
      _reportedLazySettling = false;
      return;
    }
    if (_lazySettling && !_reportedLazySettling) {
      _scheduleLazySettlingReport();
    }
  }

  void _updateLazySettling(bool settling) {
    if (_lazySettling == settling) return;
    _lazySettling = settling;
    if (_onLazySettlingChanged == null) return;
    if (_reportedLazySettling == settling) return;
    _scheduleLazySettlingReport();
  }

  void _scheduleLazySettlingReport() {
    if (_lazySettlingReportScheduled || _onLazySettlingChanged == null) return;
    _lazySettlingReportScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _lazySettlingReportScheduled = false;
      if (!attached) return;
      final callback = _onLazySettlingChanged;
      if (callback == null || _reportedLazySettling == _lazySettling) return;
      _reportedLazySettling = _lazySettling;
      callback(_lazySettling);
    });
  }

  /// Updates the scroll offset within the document and triggers a relayout
  /// when the viewport moves beyond the measured lazy window.
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
    _updateLazySettling(false);
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

  /// Text scaling applied to the laid-out text.
  TextScaler get textScaler => _textScaler;

  /// Sets the text scaling and relayouts.
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _invalidateLayout();
  }

  /// Resolves document images.
  WeftImageResolver? get imageResolver => _imageResolver;

  /// Sets the resolver, drops every resolved image, and relayouts.
  set imageResolver(WeftImageResolver? value) {
    if (identical(_imageResolver, value)) return;
    _imageResolver = value;
    _invalidateLayout();
    _clearImages();
  }

  /// Configuration used to resolve images (device pixel ratio, locale, and
  /// so on).
  ImageConfiguration get imageConfiguration => _imageConfiguration;

  /// Sets the configuration, drops every resolved image, and relayouts.
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

  /// Sets whether handle touch targets are exposed; repaints.
  set showSelectionHandles(bool value) {
    if (_showSelectionHandles == value) return;
    _showSelectionHandles = value;
    markNeedsPaint();
  }

  /// Whether a collapsed selection paints a caret bar on the canvas.
  bool get showCaret => _showCaret;

  /// Sets whether a collapsed selection paints a caret bar; repaints.
  set showCaret(bool value) {
    if (_showCaret == value) return;
    _showCaret = value;
    markNeedsPaint();
  }

  /// Whether [selectionControlsGeometry] suggests a copy button placement.
  bool get showCopyButton => _showCopyButton;

  /// Sets whether a copy button placement is suggested; repaints.
  set showCopyButton(bool value) {
    if (_showCopyButton == value) return;
    _showCopyButton = value;
    markNeedsPaint();
  }

  /// The current layout result, for tests.
  @visibleForTesting
  WeftLayoutResult? get debugLayout => _layout;

  /// Number of images resolved so far, for tests.
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

  /// Current chunk list, for tests.
  @visibleForTesting
  List<WeftChunk>? get debugChunks => _chunks;

  /// Whether the next layout must be a full (non-lazy) layout, for tests.
  @visibleForTesting
  bool get debugFullLayoutRequired => _fullLayoutRequired;

  /// Why a full layout was required, for tests.
  @visibleForTesting
  String? get debugFullLayoutReason => _debugFullLayoutReason;

  /// Current scroll offset within the document, for tests.
  @visibleForTesting
  double get debugViewportPixels => _viewportPixels;

  /// Whether lazy layout is following the document's bottom edge after a
  /// downward extent correction, for tests.
  @visibleForTesting
  bool get debugFollowLazyBottom => _followLazyBottom;

  /// Extent correction awaiting its post-frame callback, for tests.
  @visibleForTesting
  double get debugPendingLazyCorrection => _pendingLazyCorrection;

  /// Total number of lazy extent corrections delivered to the host.
  @visibleForTesting
  int get debugLazyCorrectionCount => _debugLazyCorrectionCount;

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
    final measureBudget =
        useLazy ? _lazyMeasureBudgetFor(previous, viewportHeight) : null;
    final current = useLazy
        ? _engine.layoutViewport(
            _document,
            width: width,
            viewportStart: math.max(0, _viewportPixels - _lazyOverscan),
            viewportEnd: _viewportPixels + viewportHeight + _lazyOverscan,
            maxNewBlocks: measureBudget,
            textScaler: _textScaler,
            images: _resolvedImages,
            previous: previous,
          )
        : _engine.layout(
            _document,
            width: width,
            textScaler: _textScaler,
            images: _resolvedImages,
            previous: previous,
          );
    if (useLazy && !current.debugIsLazy) {
      _markFullLayoutRequired('engine-fallback');
    }
    if (measureBudget != null && current.debugIsLazy) {
      _scheduleLazyMeasureContinuation();
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
    _updateLazySettling(
      useLazy &&
          current.debugIsLazy &&
          measureBudget != null &&
          _needsLazyRelayout(),
    );
  }

  /// The block measurement budget for this lazy pass, or null when the pass
  /// should measure everything it needs synchronously.
  ///
  /// Two situations would otherwise measure an unbounded contiguous prefix in
  /// one frame: a scroll move whose viewport end lies more than one screen
  /// past the measured frontier, and the first layout for a document when the
  /// seeded scroll offset starts deep. Both get [_lazyMeasureBudget] new
  /// blocks per pass and converge through the post-frame continuation; small
  /// scrolls near the frontier keep the previous single-pass behavior.
  int? _lazyMeasureBudgetFor(
      WeftLayoutResult? previous, double viewportHeight) {
    final cache = previous?.incrementalCache;
    if (cache != null &&
        cache.isLazy &&
        identical(cache.document, _document) &&
        cache.width == constraints.maxWidth &&
        cache.textScaler == _textScaler &&
        cache.blocks.isNotEmpty) {
      if (cache.measuredPrefixLength >= cache.childCount) return null;
      final measuredEnd = cache.viewportState?.measuredEnd ??
          (cache.blocks.last.top + cache.blocks.last.height);
      final end = _viewportPixels + viewportHeight + _lazyOverscan;
      if (end > measuredEnd + viewportHeight) {
        return _lazyMeasureBudget;
      }
      return null;
    }
    if (math.max(0.0, _viewportPixels - _lazyOverscan) > 0) {
      return _lazyMeasureBudget;
    }
    return null;
  }

  /// Keeps advancing the measured frontier across frames after a budgeted
  /// pass: each post-frame callback schedules one more budgeted layout until
  /// [_needsLazyRelayout] reports nothing pending. The lazy generation
  /// cancels the loop on full upgrades, document changes and mode exits.
  void _scheduleLazyMeasureContinuation() {
    if (_lazyMeasureContinuationScheduled) return;
    _lazyMeasureContinuationScheduled = true;
    final generation = _lazyGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _lazyMeasureContinuationScheduled = false;
      if (!attached || generation != _lazyGeneration || _fullLayoutRequired) {
        return;
      }
      if (_layout?.debugIsLazy != true || !_needsLazyRelayout()) return;
      markNeedsLayout();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  bool _needsLazyRelayout() {
    if (_fullLayoutRequired) return false;
    final layout = _layout;
    final cache = layout?.incrementalCache;
    final viewportHeight = _viewportHeight;
    if (layout?.debugIsLazy != true ||
        cache == null ||
        viewportHeight == null) {
      return false;
    }
    final start = math.max(0.0, _viewportPixels - _lazyOverscan);
    final end = _viewportPixels + viewportHeight + _lazyOverscan;
    final state = cache.viewportState;
    if (state != null) return state.needsLayout(start, end);
    final body = _document.body;
    if (body == null) return false;
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
    _followLazyBottom = !_fullLayoutRequired &&
        cache != null &&
        cache.isLazy &&
        cache.document.id == _document.id &&
        viewportHeight != null &&
        cache.measuredPrefixLength < cache.childCount &&
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
      final callback = _onLazyExtentCorrection;
      if (callback != null) {
        _debugLazyCorrectionCount++;
        callback(correction);
      }
    });
  }

  void _ensureFullLayoutForQuery(String reason) {
    final previous = _layout;
    if (previous?.debugIsLazy != true) return;
    _markFullLayoutRequired(reason);
    final current = _engine.layout(
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
        if (fragment.indexInParent != null) {
          childConfig.indexInParent = fragment.indexInParent;
        }
      } else {
        childConfig
          ..textDirection = TextDirection.ltr
          ..label = fragment.label
          ..value = fragment.value
          ..isImage = fragment.isImage
          ..isSelected = fragment.isSelected
          ..isHeader = fragment.isHeader
          ..isLink = fragment.link != null || fragment.isLinkFlag
          ..isButton = fragment.isButton
          ..liveRegion = fragment.isLiveRegion;
        if (fragment.headingLevel > 0) {
          childConfig.headingLevel = fragment.headingLevel;
        }
        final link = fragment.link;
        if (link != null && _onSemanticsLinkTap != null) {
          childConfig.onTap = () => _onSemanticsLinkTap?.call(link);
        }
        final tag = fragment.tag;
        if (tag != null && _onTagTap != null) {
          childConfig.onTap = () => _onTagTap?.call(tag);
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
    var requests = _imageRequests;
    if (!identical(_imageRequestsDocument, _document)) {
      requests = <int, WeftImageRequest>{};
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
      _imageRequestsDocument = _document;
      _imageRequests = requests;
    }

    // Only discovery is cached; unavailable requests must still be retried.
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

  /// The link region at [position] in surface-local coordinates, or null.
  WeftLinkRegion? linkAt(Offset position) {
    return _layout?.linkAt(position);
  }

  /// The custom tag region at [position] in surface-local coordinates, or
  /// null.
  WeftTagRegion? tagAt(Offset position) {
    return _layout?.tagAt(position);
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
      final focused = _engine.layoutViewport(
        _document,
        width: size.width,
        viewportStart: math.max(0, _viewportPixels - _lazyOverscan),
        viewportEnd: _viewportPixels + viewportHeight + _lazyOverscan,
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
      final focused = _engine.layoutViewport(
        _document,
        width: size.width,
        viewportStart: math.max(0, _viewportPixels - _lazyOverscan),
        viewportEnd: _viewportPixels + viewportHeight + _lazyOverscan,
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
  void detach() {
    _lazySettling = false;
    _reportedLazySettling = false;
    _lazySettlingReportScheduled = false;
    super.detach();
  }

  @override
  void dispose() {
    _anchorMeasureGeneration += 1;
    _onLazySettlingChanged = null;
    _lazySettling = false;
    _reportedLazySettling = false;
    _exitLazyMode();
    _discardPaintCache();
    _layout?.dispose();
    _layout = null;
    _clearImages();
    super.dispose();
  }
}

final class _WeftSemanticContainerSpec {
  const _WeftSemanticContainerSpec({
    required this.id,
    required this.role,
    this.indexInParent,
  });

  final NodeId id;
  final SemanticsRole role;
  final int? indexInParent;
}

final class _WeftSemanticFragment {
  const _WeftSemanticFragment({
    required this.key,
    required this.rect,
    this.absoluteRect,
    this.role,
    this.indexInParent,
    this.children = const [],
    this.containers = const [],
    this.label = '',
    this.value = '',
    this.isImage = false,
    this.isSelected = false,
    this.isSelection = false,
    this.isHeader = false,
    this.headingLevel = 0,
    this.isLiveRegion = false,
    this.isButton = false,
    this.isLinkFlag = false,
    this.link,
    this.tag,
    this.globalStart,
    this.globalEnd,
  });

  final Key key;
  final ui.Rect rect;
  final ui.Rect? absoluteRect;
  final SemanticsRole? role;
  final int? indexInParent;
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
  final bool isLiveRegion;
  final bool isButton;
  final bool isLinkFlag;
  final WeftLinkRegion? link;
  final WeftTagRegion? tag;
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
      isLiveRegion: isLiveRegion,
      isButton: isButton,
      isLinkFlag: isLinkFlag,
      link: link,
      tag: tag,
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
          indexInParent: spec.indexInParent,
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

bool? _liveRegionSetting(WeftNode node) {
  if (node is! WeftElement) return null;
  final value = node.attribute('aria-live')?.trim().toLowerCase();
  return switch (value) {
    'polite' || 'assertive' => true,
    'off' => false,
    _ => null,
  };
}

/// Elements whose structural role trees (table/row/cell) must not be
/// collapsed into a single leaf: `aria-label` accessible names and
/// `aria-atomic` group announcements fall back to the per-leaf behavior on
/// them because Flutter's debug validation requires table containers to
/// have row children (ADR 0040).
const _ariaStructuralTags = <String>{
  'col',
  'colgroup',
  'html',
  'body',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
};

bool _ariaHidden(WeftNode node) {
  if (node is! WeftElement) return false;
  return node.attribute('aria-hidden')?.trim().toLowerCase() == 'true';
}

/// The element's explicit `role` value, lowercased; the normalizer only
/// keeps values from the HTML spec's supported role set, so anything
/// non-null here is understood by the semantic layer.
String? _explicitRole(WeftNode node) {
  if (node is! WeftElement) return null;
  final value = node.attribute('role')?.trim().toLowerCase();
  return value == null || value.isEmpty ? null : value;
}

bool _isPresentationRole(String? role) {
  return role == 'presentation' || role == 'none';
}

int _semanticListStart(WeftElement element) {
  if (element.tag != 'ol') return 1;
  return int.tryParse(element.attribute('start') ?? '') ?? 1;
}

int? _semanticListItemValue(WeftElement element) {
  if (element.tag != 'li') return null;
  return int.tryParse(element.attribute('value') ?? '');
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
  final tags = <int, WeftTagRegion>{
    for (final region in layout.tagRegions) region.nodeId: region,
  };
  final fragments = <_WeftSemanticFragment>[];
  final activeContainers = <_WeftSemanticContainerSpec>[];

  void addText(
    int nodeId,
    String text,
    WeftLinkRegion? link,
    int headingLevel,
    bool isHeader,
    bool isLiveRegion,
    bool isButton,
    bool isLinkFlag,
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
              previous.isLiveRegion == isLiveRegion &&
              previous.isButton == isButton &&
              previous.isLinkFlag == isLinkFlag &&
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
              isLiveRegion: previous.isLiveRegion,
              isButton: previous.isButton,
              isLinkFlag: previous.isLinkFlag,
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
                isLiveRegion: isLiveRegion,
                isButton: isButton,
                isLinkFlag: isLinkFlag,
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

  /// Emits one leaf fragment representing [node]'s whole subtree — used for
  /// `aria-label` accessible names, `role=img` and `aria-atomic` live-region
  /// group announcements (ADR 0040). When [label] is null the flattened
  /// subtree text is announced instead. Nothing is emitted when the subtree
  /// has no visible geometry (no text rects and no resolved images) or the
  /// resulting name is empty; list markers do not survive collapsing.
  void addCollapsedSubtree(
    WeftElement node, {
    String? label,
    bool isImage = false,
    bool isLiveRegion = false,
    WeftLinkRegion? link,
    int headingLevel = 0,
    bool isHeader = false,
    bool isButton = false,
    bool isLinkFlag = false,
  }) {
    ui.Rect? geometry;
    final text = StringBuffer();
    void collect(WeftNode child) {
      if (child is WeftText) {
        final entry = textIndex.entryByNode[child.id];
        if (entry == null || entry.text.isEmpty) return;
        final rect = _unionRects(
          layout.textRectsForNode(child.id, 0, entry.text.length),
        );
        if (rect != null) {
          geometry = geometry == null ? rect : geometry!.expandToInclude(rect);
        }
        if (text.isNotEmpty) text.write(' ');
        text.write(entry.text.replaceAll('\n', ' '));
        return;
      }
      if (child is! WeftElement) return;
      if (child.tag == 'img') {
        final image = images[child.id];
        final alt = child.attribute('aria-label')?.trim() ??
            child.attribute('alt')?.trim() ??
            '';
        if (image != null) {
          final destination = image.destination;
          if (destination.isFinite && !destination.isEmpty) {
            geometry = geometry == null
                ? destination
                : geometry!.expandToInclude(destination);
          }
        }
        if (alt.isNotEmpty) {
          if (text.isNotEmpty) text.write(' ');
          text.write(alt);
        }
        return;
      }
      final tagRegion = tags[child.id];
      if (tagRegion != null) {
        final rect = tagRegion.rect;
        if (rect.isFinite && !rect.isEmpty) {
          geometry = geometry == null ? rect : geometry!.expandToInclude(rect);
        }
        final tagLabel = tagRegion.label ?? '';
        if (tagLabel.isNotEmpty) {
          if (text.isNotEmpty) text.write(' ');
          text.write(tagLabel);
        }
        return;
      }
      for (final grandchild in child.children) {
        collect(grandchild);
      }
    }

    for (final child in node.children) {
      collect(child);
    }
    final name = (label ?? text.toString()).trim();
    if (name.isEmpty) return;
    final rect = _clippedSemanticsRect(geometry, bounds);
    if (rect == null) return;
    fragments.add(
      _WeftSemanticFragment(
        key: ValueKey<String>('aria:${node.id}'),
        rect: rect,
        label: name,
        isImage: isImage,
        containers: List<_WeftSemanticContainerSpec>.unmodifiable(
          activeContainers,
        ),
        isHeader: isHeader,
        headingLevel: headingLevel,
        isLiveRegion: isLiveRegion,
        isButton: isButton,
        isLinkFlag: isLinkFlag,
        link: link,
      ),
    );
  }

  void visit(
    WeftNode node,
    WeftLinkRegion? currentLink,
    int headingLevel,
    bool isHeader,
    bool isLive,
    List<String?>? prefixBox, {
    bool isButton = false,
    bool isLinkFlag = false,
  }) {
    if (node is WeftText) {
      final entry = textIndex.entryByNode[node.id];
      if (entry != null) {
        addText(
          node.id,
          entry.text,
          currentLink,
          headingLevel,
          isHeader,
          isLive,
          isButton,
          isLinkFlag,
          prefixBox,
          entryGlobalStart: entry.globalStart,
        );
      }
      return;
    }
    if (node is! WeftElement) return;
    if (_ariaHidden(node)) return;
    final role = _explicitRole(node);
    final presentation = _isPresentationRole(role);
    final roleLive = role == 'alert' || role == 'status';
    final childLive = _liveRegionSetting(node) ?? (roleLive ? true : isLive);
    if (node.tag == 'img') {
      // A presentation/none image is removed from the accessibility tree
      // while still painting (ADR 0040).
      if (presentation) return;
      final image = images[node.id];
      // aria-label is the stronger accessible name per the ARIA name
      // computation; alt is the fallback.
      final alt = node.attribute('aria-label')?.trim() ??
          node.attribute('alt')?.trim() ??
          '';
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
              isLiveRegion: childLive,
              isButton: isButton,
              isLinkFlag: isLinkFlag,
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
          childLive,
          isButton,
          isLinkFlag,
          prefixBox,
        );
      }
      return;
    }
    final tagRegion = tags[node.id];
    if (tagRegion != null) {
      final rect = _clippedSemanticsRect(tagRegion.rect, bounds);
      if (rect != null && (tagRegion.label ?? '').isNotEmpty) {
        fragments.add(
          _WeftSemanticFragment(
            key: ValueKey<String>('tag:${node.id}'),
            rect: rect,
            label: tagRegion.label!,
            containers: List<_WeftSemanticContainerSpec>.unmodifiable(
              activeContainers,
            ),
            isHeader: isHeader,
            headingLevel: headingLevel,
            isLiveRegion: childLive,
            isButton: isButton,
            isLinkFlag: isLinkFlag,
            tag: tagRegion,
          ),
        );
      }
      // Custom tag content is opaque: attribute-driven, so no subtree visit.
      return;
    }
    // An explicit role overrides the element's implicit link semantics:
    // `<a role="button">` announces as a button without the link flag or tap
    // action (ADR 0040).
    final roleOverride =
        presentation || role == 'button' || role == 'img' || role == 'heading';
    final link =
        node.tag == 'a' && !roleOverride ? links[node.id] : currentLink;
    final childHeading = presentation
        ? headingLevel
        : switch (node.tag) {
            'h1' => 1,
            'h2' => 2,
            'h3' => 3,
            'h4' => 4,
            'h5' => 5,
            'h6' => 6,
            // ARIA gives `role=heading` without a level the default level 2.
            _ => role == 'heading' ? 2 : headingLevel,
          };
    final childHeader = !presentation &&
        (isHeader ||
            node.tag == 'th' ||
            node.tag == 'h1' ||
            node.tag == 'h2' ||
            node.tag == 'h3' ||
            node.tag == 'h4' ||
            node.tag == 'h5' ||
            node.tag == 'h6');
    final childButton = isButton || role == 'button';
    final childLinkFlag = isLinkFlag || role == 'link';
    // Dialog roles are container roles Flutter validates as
    // `_noCheckRequired`, so they are safe to push as semantic containers.
    final dialogSpec =
        presentation || (role != 'dialog' && role != 'alertdialog')
            ? null
            : _WeftSemanticContainerSpec(
                id: node.id,
                role: role == 'dialog'
                    ? SemanticsRole.dialog
                    : SemanticsRole.alertDialog,
              );
    if (dialogSpec != null) {
      activeContainers.add(dialogSpec);
    }
    final structural = _ariaStructuralTags.contains(node.tag);
    final ariaLabel = node.attribute('aria-label')?.trim() ?? '';
    // `aria-atomic` only groups announcements inside a live region;
    // `role=alert`/`status` imply live + atomic per ARIA. Structural role
    // trees fall back to the per-leaf behavior instead of collapsing.
    final atomic = childLive &&
        (roleLive ||
            node.attribute('aria-atomic')?.trim().toLowerCase() == 'true');
    if (!structural && (ariaLabel.isNotEmpty || role == 'img' || atomic)) {
      addCollapsedSubtree(
        node,
        label: ariaLabel.isNotEmpty ? ariaLabel : null,
        isImage: role == 'img',
        isLiveRegion: childLive,
        link: link,
        headingLevel: childHeading,
        isHeader: childHeader,
        isButton: childButton,
        isLinkFlag: childLinkFlag,
      );
      if (dialogSpec != null) activeContainers.removeLast();
      return;
    }
    if (node.tag == 'ul' || node.tag == 'ol') {
      // A presentation list keeps announcing its content but loses the
      // list/listItem containers and the `1. `/`• ` markers (ADR 0040).
      if (!presentation) {
        activeContainers.add(
          _WeftSemanticContainerSpec(id: node.id, role: SemanticsRole.list),
        );
      }
      var itemIndex = 0;
      var itemNumber =
          !presentation && node.tag == 'ol' ? _semanticListStart(node) : 0;
      for (final child in node.children) {
        List<String?>? childPrefix;
        if (!presentation && child is WeftElement && child.tag == 'li') {
          itemIndex += 1;
          if (node.tag == 'ol') {
            final explicit = _semanticListItemValue(child);
            if (explicit != null) itemNumber = explicit;
            childPrefix = <String?>['$itemNumber. '];
            itemNumber += 1;
          } else {
            childPrefix = <String?>['• '];
          }
          activeContainers.add(
            _WeftSemanticContainerSpec(
              id: child.id,
              role: SemanticsRole.listItem,
              indexInParent: itemIndex - 1,
            ),
          );
          visit(
            child,
            link,
            childHeading,
            childHeader,
            childLive,
            childPrefix,
            isButton: childButton,
            isLinkFlag: childLinkFlag,
          );
          activeContainers.removeLast();
        } else {
          visit(
            child,
            link,
            childHeading,
            childHeader,
            childLive,
            childPrefix,
            isButton: childButton,
            isLinkFlag: childLinkFlag,
          );
        }
      }
      if (!presentation) {
        activeContainers.removeLast();
      }
      if (dialogSpec != null) activeContainers.removeLast();
      return;
    }
    if (node.tag == 'table') {
      // A presentation table keeps announcing cell text but loses the
      // table/row/cell containers; descendant `th` header flags survive
      // (documented simplification in ADR 0040).
      if (presentation) {
        for (final child in node.children) {
          visit(
            child,
            link,
            childHeading,
            childHeader,
            childLive,
            null,
            isButton: childButton,
            isLinkFlag: childLinkFlag,
          );
        }
        if (dialogSpec != null) activeContainers.removeLast();
        return;
      }
      for (final child in node.children) {
        if (child is WeftElement && child.tag == 'caption') {
          visit(child, link, childHeading, childHeader, childLive, null);
        }
      }
      activeContainers.add(
        _WeftSemanticContainerSpec(id: node.id, role: SemanticsRole.table),
      );
      var nextRowIndex = 0;
      void visitRow(WeftElement row) {
        final rowIndex = nextRowIndex++;
        activeContainers.add(
          _WeftSemanticContainerSpec(
            id: row.id,
            role: SemanticsRole.row,
            indexInParent: rowIndex,
          ),
        );
        var cellIndex = 0;
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
              indexInParent: cellIndex,
            ),
          );
          cellIndex += 1;
          visit(
            cell,
            link,
            childHeading,
            childHeader,
            childLive,
            null,
            isButton: childButton,
            isLinkFlag: childLinkFlag,
          );
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
      if (dialogSpec != null) activeContainers.removeLast();
      return;
    }
    for (final child in node.children) {
      visit(
        child,
        link,
        childHeading,
        childHeader,
        childLive,
        prefixBox,
        isButton: childButton,
        isLinkFlag: childLinkFlag,
      );
    }
    if (dialogSpec != null) activeContainers.removeLast();
  }

  final bodyLive = _liveRegionSetting(body) ?? false;
  if (!_ariaHidden(body)) {
    for (final child in body.children) {
      visit(child, null, 0, false, bodyLive, null);
    }
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
