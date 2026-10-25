import 'package:flutter/gestures.dart' show LongPressDownDetails;
import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

import 'weft_controller.dart';

typedef WeftFallbackBuilder = Widget Function(
  BuildContext context,
  SupportReport report,
);

class WeftView extends StatefulWidget {
  const WeftView({
    super.key,
    required this.controller,
    this.fallbackBuilder,
    this.onLinkTap,
    this.imageResolver,
  });

  final WeftController controller;
  final WeftFallbackBuilder? fallbackBuilder;
  final ValueChanged<WeftLinkRegion>? onLinkTap;
  final WeftImageResolver? imageResolver;

  @override
  WeftViewState createState() => WeftViewState();
}

/// State for [WeftView].
///
/// Exposed so hosts can read the current selection's text through
/// [WeftViewState.selectionText] via a [GlobalKey]. Clipboard policies stay
/// with the host; the engine never writes to the system clipboard.
class WeftViewState extends State<WeftView> {
  final _surfaceKey = GlobalKey();

  /// Where the long press started, recorded on pointer down so the word
  /// selection is taken from the touch origin even if the start callback
  /// reports a slightly adjusted position.
  Offset? _longPressOrigin;

  RenderWeftSurface? get _surfaceRenderObject {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderWeftSurface ? renderObject : null;
  }

  void _handleTapUp(TapUpDetails details) {
    final surface = _surfaceRenderObject;
    if (surface == null) return;
    final link = surface.linkAt(details.localPosition);
    if (link != null) {
      // Quick taps only follow links; long press owns selection changes.
      widget.onLinkTap?.call(link);
      return;
    }
    widget.controller.updateSelection(null);
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
    if (range != null) widget.controller.updateSelection(range);
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
    widget.controller.updateSelection(
      TextSelectionRange(anchor: selection.anchor, extent: extent),
    );
  }

  /// The logical text covered by the controller's current selection, with
  /// block boundaries rendered as newlines, or null when the selection is
  /// empty or no longer resolves against the current layout.
  String? selectionText() {
    final surface = _surfaceRenderObject;
    if (surface == null) return null;
    return surface.selectionText(widget.controller.selection);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
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
        // The view owns the full gesture surface: tap resolves links through
        // the render object itself, so link taps and selection clearing share
        // one tap handler and WeftSurface builds without its own detector.
        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          excludeFromSemantics: true,
          onTapUp: _handleTapUp,
          onLongPressDown: _handleLongPressDown,
          onLongPressStart: _handleLongPressStart,
          onLongPressMoveUpdate: _handleLongPressMoveUpdate,
          child: WeftSurface(
            key: _surfaceKey,
            document: document,
            selection: widget.controller.selection,
            textScaler: textScaler,
            imageResolver: widget.imageResolver,
          ),
        );
      },
    );
  }
}
