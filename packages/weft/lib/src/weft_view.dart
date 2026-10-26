import 'dart:math' as math;

import 'package:flutter/gestures.dart' show LongPressDownDetails;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

import 'weft_controller.dart';
import 'weft_selection_chrome.dart';

typedef WeftFallbackBuilder = Widget Function(
  BuildContext context,
  SupportReport report,
);

/// Snapshot of the current selection reported through
/// [WeftView.onSelectionChanged].
final class WeftSelectionInfo {
  const WeftSelectionInfo({required this.text, required this.isCollapsed});

  /// The selected logical text with block boundaries rendered as newlines,
  /// or null when the selection is collapsed or no longer resolves against
  /// the current layout.
  final String? text;

  /// Whether the selection is a single caret position.
  final bool isCollapsed;

  @override
  bool operator ==(Object other) {
    return other is WeftSelectionInfo &&
        other.text == text &&
        other.isCollapsed == isCollapsed;
  }

  @override
  int get hashCode => Object.hash(text, isCollapsed);
}

class WeftView extends StatefulWidget {
  const WeftView({
    super.key,
    required this.controller,
    this.scrollController,
    this.fallbackBuilder,
    this.onLinkTap,
    this.onSelectionChanged,
    this.imageResolver,
    this.enableLazyLayout = true,
    this.showSelectionHandles = true,
    this.showCaret = true,
    this.showCopyButton = true,
    this.copyButtonLabel = '复制',
  });

  final WeftController controller;

  /// Optional controller for the view's internal vertical scroll view
  /// (ADR 0020). The view always scrolls its own content — the surface is
  /// laid out at the full document height — and never joins the primary
  /// scroll group, so a host passes a controller here to read or drive the
  /// scroll offset, not to opt out of internal scrolling.
  final ScrollController? scrollController;

  final WeftFallbackBuilder? fallbackBuilder;
  final ValueChanged<WeftLinkRegion>? onLinkTap;

  /// Reports every applied selection change as collapsed-caret or selected
  /// text. Never invoked synchronously during build; internal gestures call
  /// back from their event handlers and external controller mutations defer
  /// to a post-frame callback.
  final ValueChanged<WeftSelectionInfo?>? onSelectionChanged;

  final WeftImageResolver? imageResolver;

  /// Whether simple documents lazily materialize only the visible block
  /// window. Selection and Semantics still upgrade to a complete layout.
  final bool enableLazyLayout;

  /// Whether drag handles overlay the current selection. Forwarded to the
  /// surface's geometry query and used to gate the overlay widgets here.
  final bool showSelectionHandles;

  /// Whether a collapsed selection shows a caret bar, painted by the surface
  /// itself. Forwarded to [WeftSurface].
  final bool showCaret;

  /// Whether the copy button overlays an expanded selection. Forwarded to
  /// the surface's geometry query and used to gate the overlay widget here.
  final bool showCopyButton;

  /// Label of the copy button overlay.
  final String copyButtonLabel;

  @override
  WeftViewState createState() => WeftViewState();
}

/// State for [WeftView].
///
/// Exposed so hosts can read the current selection's text through
/// [WeftViewState.selectionText] via a [GlobalKey]. Clipboard policies stay
/// with the weft layer; the engine never writes to the system clipboard.
class WeftViewState extends State<WeftView> {
  final _surfaceKey = GlobalKey();
  final _internalScrollController = ScrollController();

  ScrollController get _scrollController =>
      widget.scrollController ?? _internalScrollController;

  bool _viewportSyncScheduled = false;
  int _anchorScrollGeneration = 0;

  double get _viewportPixelsSeed {
    final controller = _scrollController;
    return controller.hasClients
        ? controller.offset
        : controller.initialScrollOffset;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scheduleViewportSync();
  }

  void _scheduleViewportSync() {
    if (_viewportSyncScheduled) return;
    _viewportSyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportSyncScheduled = false;
      if (mounted) _handleScroll();
    });
  }

  @override
  void didUpdateWidget(WeftView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      (oldWidget.scrollController ?? _internalScrollController)
          .removeListener(_handleScroll);
      _scrollController.addListener(_handleScroll);
      _anchorScrollGeneration += 1;
      _surfaceRenderObject?.setViewportPixels(_viewportPixelsSeed);
      _scheduleViewportSync();
    }
  }

  void _handleScroll() {
    _surfaceRenderObject?.setViewportPixels(_scrollController.offset);
  }

  void _correctLazyExtent(double delta) {
    if (_scrollController.hasClients) {
      _scrollController.position.correctBy(delta);
    }
  }

  @override
  void dispose() {
    _anchorScrollGeneration += 1;
    _scrollController.removeListener(_handleScroll);
    _internalScrollController.dispose();
    super.dispose();
  }

  /// Where the long press started, recorded on pointer down so the word
  /// selection is taken from the touch origin even if the start callback
  /// reports a slightly adjusted position.
  Offset? _longPressOrigin;

  /// Whether a selection handle drag is currently in flight. While it is,
  /// the last overlay geometry is kept even when the selection collapses,
  /// so the dragged widget is not torn out from under the gesture.
  bool _activeHandleDrag = false;
  WeftSelectionControlsGeometry? _lastOverlayGeometry;

  bool _overlaySyncScheduled = false;
  bool _selectionReportScheduled = false;

  /// Last selection value reported through [WeftView.onSelectionChanged].
  TextSelectionRange? _reportedSelection;

  RenderWeftSurface? get _surfaceRenderObject {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderWeftSurface ? renderObject : null;
  }

  /// The single funnel for every selection this state applies: it updates
  /// the controller and reports synchronously, because gesture callbacks are
  /// event handlers. The build phase must never report synchronously; it
  /// defers through [_scheduleSelectionReportIfNeeded] instead.
  void _setSelection(TextSelectionRange? selection) {
    widget.controller.updateSelection(selection);
    _reportSelectionIfNeeded();
  }

  void _reportSelectionIfNeeded() {
    final callback = widget.onSelectionChanged;
    if (callback == null) return;
    final selection = widget.controller.selection;
    if (selection == _reportedSelection) return;
    _reportedSelection = selection;
    if (selection == null) {
      callback(null);
    } else if (selection.isCollapsed) {
      callback(const WeftSelectionInfo(text: null, isCollapsed: true));
    } else {
      callback(WeftSelectionInfo(
        text: _surfaceRenderObject?.selectionText(selection),
        isCollapsed: false,
      ));
    }
  }

  /// Reports selection changes that did not come through this state's own
  /// handlers — the host mutating the controller directly, for example.
  void _scheduleSelectionReportIfNeeded() {
    if (widget.onSelectionChanged == null) return;
    if (widget.controller.selection == _reportedSelection) return;
    if (_selectionReportScheduled) return;
    _selectionReportScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _selectionReportScheduled = false;
      if (mounted) _reportSelectionIfNeeded();
    });
  }

  /// Schedules one post-frame rebuild when the render object still carries
  /// the previous frame's selection.
  ///
  /// Without this, a selection established in an event handler would never
  /// surface its overlays: the build that applies the selection queries the
  /// render object before its update lands. The rebuild converges, because
  /// the render object equals the controller's selection afterwards.
  void _scheduleOverlaySyncIfNeeded() {
    if (_overlaySyncScheduled) return;
    final surface = _surfaceRenderObject;
    if (surface != null && surface.selection == widget.controller.selection) {
      return;
    }
    _overlaySyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _overlaySyncScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _handleTapUp(TapUpDetails details) {
    final surface = _surfaceRenderObject;
    if (surface == null) return;
    // The GestureDetector wraps the surface, which is the Stack's sizing
    // child at the origin, so this position is already surface-local.
    final position = details.localPosition;
    final link = surface.linkAt(position);
    if (link != null) {
      // Quick taps only follow links; long press owns selection expansion.
      widget.onLinkTap?.call(link);
      return;
    }
    // ADR 0019 evolves ADR 0015's "tap always clears": a tap on text places
    // the caret there, and only a tap on no text clears the selection.
    final anchor = surface.anchorAt(position);
    _setSelection(anchor == null ? null : TextSelectionRange.collapsed(anchor));
  }

  void _handleLongPressDown(LongPressDownDetails details) {
    _longPressOrigin = details.localPosition;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final surface = _surfaceRenderObject;
    if (surface == null) return;
    final range = surface.wordSelectionAt(
      _longPressOrigin ?? details.localPosition,
    );
    if (range != null) _setSelection(range);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final surface = _surfaceRenderObject;
    if (surface == null) return;
    final selection = widget.controller.selection;
    if (selection == null) return;
    final extent = surface.anchorAt(details.localPosition);
    // Off-text points keep the previous extent instead of collapsing the
    // selection; the anchor stays at the long-pressed word's start.
    if (extent == null) return;
    _setSelection(
      TextSelectionRange(anchor: selection.anchor, extent: extent),
    );
  }

  void _handleHandleDragUpdate(bool isEnd, Offset position) {
    _activeHandleDrag = true;
    final surface = _surfaceRenderObject;
    if (surface == null) return;
    final selection = widget.controller.selection;
    if (selection == null) return;
    final anchor = surface.anchorAt(position);
    // Off-text drag points keep the previous endpoint (ADR 0013 safe drop),
    // so the selection stays visible for the whole gesture.
    if (anchor == null) return;
    _setSelection(
      isEnd
          ? TextSelectionRange(anchor: selection.anchor, extent: anchor)
          : TextSelectionRange(anchor: anchor, extent: selection.extent),
    );
  }

  void _handleHandleDragEnd() {
    if (!_activeHandleDrag) return;
    _activeHandleDrag = false;
    // Drop the held geometry and re-query with the settled selection, which
    // may have collapsed under the drag.
    setState(() {});
  }

  void _handleCopyTap() {
    final text = selectionText();
    if (text == null) return;
    _copyText(text);
  }

  void _copyText(String text) {
    // The clipboard write lives in the weft layer; the engine never touches
    // the system clipboard. Copying keeps the selection.
    Clipboard.setData(ClipboardData(text: text));
  }

  /// The logical text covered by the controller's current selection, with
  /// block boundaries rendered as newlines, or null when the selection is
  /// empty or no longer resolves against the current layout.
  String? selectionText() {
    final surface = _surfaceRenderObject;
    if (surface == null) return null;
    return surface.selectionText(widget.controller.selection);
  }

  /// Scrolls the internal view so [anchor] is placed according to
  /// [alignment] (0 top, 1 bottom).
  ///
  /// Returns true when the anchor resolves and a scroll has been scheduled
  /// for the next frame. Invalid anchors return false without changing the
  /// scroll offset or forcing lazy layout to become full.
  bool scrollToAnchor(TextAnchor anchor, {double alignment = 0.0}) {
    assert(
      alignment.isFinite && alignment >= 0 && alignment <= 1,
      'alignment must be finite and between 0 and 1',
    );
    if (!alignment.isFinite || alignment < 0 || alignment > 1) return false;
    final surface = _surfaceRenderObject;
    final controller = _scrollController;
    if (surface == null || !controller.hasClients) return false;
    final rect = surface.textRectForAnchor(anchor);
    if (rect == null) return false;

    final generation = ++_anchorScrollGeneration;
    final document = widget.controller.document;
    final documentId = document?.id;
    final revision = document?.revision;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _anchorScrollGeneration) return;
      final current = widget.controller.document;
      if (current?.id != documentId || current?.revision != revision) return;
      final currentController = _scrollController;
      if (!currentController.hasClients) return;
      final position = currentController.position;
      final target = rect.top -
          alignment * math.max(0, position.viewportDimension - rect.height);
      final clamped = target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      position.jumpTo(clamped);
    });
    SchedulerBinding.instance.scheduleFrame();
    return true;
  }

  /// Scrolls to the first text inside document element [nodeId].
  bool scrollToNode(NodeId nodeId, {double alignment = 0.0}) {
    final anchor = _surfaceRenderObject?.firstTextAnchorInNode(nodeId);
    if (anchor == null) return false;
    return scrollToAnchor(anchor, alignment: alignment);
  }

  /// Resolves [anchor] across animation frames, then scrolls to it.
  ///
  /// Returns false when the anchor is invalid or the request is superseded
  /// by another navigation, a document change, or widget disposal.
  Future<bool> scrollToAnchorAsync(
    TextAnchor anchor, {
    double alignment = 0.0,
    int maxNewBlocks = 32,
  }) async {
    assert(
      alignment.isFinite && alignment >= 0 && alignment <= 1,
      'alignment must be finite and between 0 and 1',
    );
    if (!alignment.isFinite || alignment < 0 || alignment > 1) return false;
    final surface = _surfaceRenderObject;
    final controller = _scrollController;
    if (surface == null || !controller.hasClients) return false;
    final generation = ++_anchorScrollGeneration;
    final document = widget.controller.document;
    final documentId = document?.id;
    final revision = document?.revision;
    final rect = await surface.measureAnchorAsync(
      anchor,
      maxNewBlocks: maxNewBlocks,
    );
    if (!mounted ||
        generation != _anchorScrollGeneration ||
        rect == null ||
        widget.controller.document?.id != documentId ||
        widget.controller.document?.revision != revision) {
      return false;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _anchorScrollGeneration) return;
      final currentController = _scrollController;
      if (!currentController.hasClients) return;
      final position = currentController.position;
      final target = rect.top -
          alignment * math.max(0, position.viewportDimension - rect.height);
      position.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
    SchedulerBinding.instance.scheduleFrame();
    return true;
  }

  /// Positions the selection chrome overlays from the render object's
  /// geometry query.
  ///
  /// The render object absorbs this frame's selection and layout updates
  /// only after the build, so the query here may lag one frame;
  /// [_scheduleOverlaySyncIfNeeded] rebuilds with settled values.
  ///
  /// While a handle drag is in flight the overlays freeze on the geometry
  /// they had when the drag started: the dragged box must not move under the
  /// pointer (pan updates report positions relative to the box the pointer
  /// went down on), and a selection collapsing under the drag must not tear
  /// the widget out of the tree. Selection updates still flow through the
  /// controller, so the highlight itself keeps following the pointer.
  List<Widget> _buildSelectionOverlays() {
    final surface = _surfaceRenderObject;
    if (surface == null) return const [];
    var geometry = surface.selectionControlsGeometry();
    if (_activeHandleDrag) {
      geometry ??= _lastOverlayGeometry;
    } else if (geometry != null) {
      _lastOverlayGeometry = geometry;
    }
    if (geometry == null) return const [];
    final startHandle = geometry.startHandle;
    final endHandle = geometry.endHandle;
    final copyButton = geometry.copyButton;
    return [
      if (startHandle != null)
        Positioned.fromRect(
          rect: startHandle,
          child: WeftSelectionHandle(
            anchor: geometry.startAnchor - startHandle.topLeft,
            isEnd: false,
            onDragUpdate: (local) =>
                _handleHandleDragUpdate(false, startHandle.topLeft + local),
            onDragEnd: _handleHandleDragEnd,
          ),
        ),
      if (endHandle != null)
        Positioned.fromRect(
          rect: endHandle,
          child: WeftSelectionHandle(
            anchor: geometry.endAnchor - endHandle.topLeft,
            isEnd: true,
            onDragUpdate: (local) =>
                _handleHandleDragUpdate(true, endHandle.topLeft + local),
            onDragEnd: _handleHandleDragEnd,
          ),
        ),
      if (copyButton != null)
        Positioned.fromRect(
          rect: copyButton,
          child: WeftCopyButton(
            label: widget.copyButtonLabel,
            onTap: _handleCopyTap,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        _scheduleSelectionReportIfNeeded();
        final document = widget.controller.document;
        if (document == null) return const SizedBox.shrink();

        if (!document.supportReport.canRender) {
          final fallback = widget.fallbackBuilder;
          if (fallback != null) {
            return fallback(context, document.supportReport);
          }
          throw FlutterError(
            'Weft cannot render this document. '
            'Provide WeftView.fallbackBuilder for unsupported content.',
          );
        }

        final textScaler =
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
        return LayoutBuilder(
          builder: (context, constraints) {
            final surface = WeftSurface(
              key: _surfaceKey,
              document: document,
              selection: widget.controller.selection,
              textScaler: textScaler,
              imageResolver: widget.imageResolver,
              onSemanticsLinkTap: widget.onLinkTap,
              onSemanticsCopy: _copyText,
              enableLazyLayout: widget.enableLazyLayout,
              viewportHeight:
                  constraints.hasBoundedHeight ? constraints.maxHeight : null,
              initialViewportPixels: _viewportPixelsSeed,
              onLazyExtentCorrection: _correctLazyExtent,
              showSelectionHandles: widget.showSelectionHandles,
              showCaret: widget.showCaret,
              showCopyButton: widget.showCopyButton,
              copyButtonLabel: widget.copyButtonLabel,
            );
            // The view owns the content gesture surface: tap resolves links and
            // places the caret through the render object itself, so link taps,
            // caret placement and selection clearing share one tap handler and
            // WeftSurface builds without its own detector. Handle and copy
            // button chrome sits in the Stack above; its opaque gesture
            // detectors win the arena before this handler ever sees a pointer.
            final content = GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              excludeFromSemantics: true,
              onTapUp: _handleTapUp,
              onLongPressDown: _handleLongPressDown,
              onLongPressStart: _handleLongPressStart,
              onLongPressMoveUpdate: _handleLongPressMoveUpdate,
              child: surface,
            );
            _scheduleOverlaySyncIfNeeded();
            // The surface reports an estimated or exact document extent. Its
            // block window follows this controller, while selection chrome
            // keeps the same document-local coordinates as the content.
            return SingleChildScrollView(
              controller: _scrollController,
              primary: false,
              child: Stack(
                children: [
                  content,
                  ..._buildSelectionOverlays(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
