import 'package:flutter/widgets.dart';
import 'package:weft_engine/weft_engine.dart';

/// A selection drag handle anchored at one end of the current selection.
///
/// This is a chrome overlay, not a content node: [WeftView] positions it in
/// a [Stack] above [WeftSurface] from
/// [RenderWeftSurface.selectionControlsGeometry]. The widget paints a
/// dot-and-stem marker at [anchor] and claims pan gestures across its whole
/// box (the touch target rect from the geometry query), so a handle drag wins
/// arbitration over an enclosing scrollable and a tap on the handle never
/// reaches the surface's tap handler.
final class WeftSelectionHandle extends StatelessWidget {
  const WeftSelectionHandle({
    super.key,
    required this.anchor,
    required this.isEnd,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.color = kWeftSelectionColor,
  });

  /// Marker position in the handle's local coordinates; the touch box around
  /// it is positioned by the view.
  final Offset anchor;

  /// Whether this handle drags the selection's extent (end) rather than its
  /// anchor (start).
  final bool isEnd;

  /// Reports the pointer position in the handle's local coordinates while a
  /// drag is in flight. The view translates it into surface-local
  /// coordinates before mapping it through the layout.
  final ValueChanged<Offset> onDragUpdate;

  final VoidCallback onDragEnd;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so pointers on the touch target never reach the surface
      // underneath: a tap would otherwise place a caret or clear the
      // selection, and a drag would compete with the outer scrollable.
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDragUpdate(details.localPosition),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: CustomPaint(
        painter: _SelectionHandlePainter(color: color, anchor: anchor),
      ),
    );
  }
}

final class _SelectionHandlePainter extends CustomPainter {
  const _SelectionHandlePainter({required this.color, required this.anchor});

  final Color color;
  final Offset anchor;

  static const double _stemWidth = 3;
  static const double _stemHeight = 10;
  static const double _dotRadius = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // A short stem hangs straight down from the selection edge into the dot,
    // so both handles share one shape regardless of which end they anchor.
    canvas.drawRect(
      Rect.fromLTWH(
        anchor.dx - _stemWidth / 2,
        anchor.dy,
        _stemWidth,
        _stemHeight,
      ),
      paint,
    );
    canvas.drawCircle(
      Offset(anchor.dx, anchor.dy + _stemHeight + _dotRadius),
      _dotRadius,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SelectionHandlePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.anchor != anchor;
  }
}

/// The copy button shown near an active selection.
///
/// Chrome overlay like [WeftSelectionHandle]: the view positions it from the
/// geometry query and owns the clipboard write on tap. Tapping the button
/// must not change the selection, so the opaque gesture detector shields the
/// surface's tap handler underneath.
final class WeftCopyButton extends StatelessWidget {
  const WeftCopyButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  static const Color _borderColor = Color(0xFFDADCE0);
  static const Color _textColor = Color(0xFF202124);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: _textColor),
        ),
      ),
    );
  }
}
