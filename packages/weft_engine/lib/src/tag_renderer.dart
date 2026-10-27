import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

/// Input handed to a [WeftTagRenderer].
///
/// Custom tags are opaque block-level boxes: the renderer owns everything
/// inside the element's content box. Elements reach the renderer only when
/// the host allowlists the tag in `WeftNormalizer.customTags` and registers a
/// renderer for it on the layout engine; the two lists are the host's
/// contract and must agree (ADR 0033).
final class WeftTagLayoutContext {
  /// Creates the input for one layout pass over a custom tag element.
  const WeftTagLayoutContext({
    required this.element,
    required this.contentWidth,
    required this.textScaler,
  });

  /// The normalized element. Custom tags are leaves: their content is
  /// attribute-driven, and markup children are dropped during normalization.
  final WeftElement element;

  /// Content-box width the renderer may use.
  final double contentWidth;

  /// Host text scaling; text ops are shaped with it by the engine.
  final TextScaler textScaler;
}

/// One paint primitive produced by a [WeftTagRenderer].
///
/// Coordinates are relative to the custom tag's content box. The engine
/// attributes every primitive to the element's [NodeId], converts rects into
/// regular rectangle commands, shapes text ops with a real `TextPainter`,
/// and drops primitives that fall outside the content box.
sealed class WeftTagOp {
  /// Subclasses provide the concrete paint primitive.
  const WeftTagOp();
}

/// Filled rectangle, the only box primitive the supported subset paints.
final class WeftTagRectOp extends WeftTagOp {
  /// Creates a filled rectangle primitive.
  const WeftTagRectOp({required this.rect, required this.color});

  /// Rectangle to fill, relative to the tag's content box.
  final Rect rect;

  /// Fill color applied to [rect].
  final Color color;
}

/// Single-style text run. The engine wraps at `min(maxWidth, remaining
/// content width)`; the renderer is responsible for choosing a font size that
/// fits the declared height.
final class WeftTagTextOp extends WeftTagOp {
  /// Creates a text primitive painted at [offset].
  const WeftTagTextOp({
    required this.offset,
    required this.text,
    this.style = const TextStyle(),
    this.maxWidth,
  });

  /// Position of the run's top-left corner, relative to the content box.
  final Offset offset;

  /// The text to shape and paint.
  final String text;

  /// Style used to shape and paint [text].
  final TextStyle style;

  /// Width at which the engine wraps the run; defaults to the remaining
  /// content width when null.
  final double? maxWidth;
}

/// Renderer output: the content-box height plus primitives and an optional
/// accessibility label.
final class WeftTagLayout {
  /// Creates the renderer output for one custom tag.
  const WeftTagLayout({
    required this.height,
    this.ops = const <WeftTagOp>[],
    this.semanticsLabel,
  });

  /// Height the custom tag contributes to the block flow. Negative values
  /// are clamped to zero.
  final double height;

  /// Paint primitives to draw inside the tag's content box.
  final List<WeftTagOp> ops;

  /// Accessibility label announced for the whole tag. When null the engine
  /// falls back to the element's `aria-label` attribute, then to its tag name.
  final String? semanticsLabel;
}

/// Trusted Dart extension for a custom tag (architecture doc, section 7).
///
/// Renderers never receive layout internals, JS access, or host privileges;
/// they turn one immutable element plus a content width into paint primitives.
abstract interface class WeftTagRenderer {
  /// Computes the layout (height, primitives, semantics label) for one
  /// custom tag from [context].
  WeftTagLayout layout(WeftTagLayoutContext context);
}
