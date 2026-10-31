import 'package:flutter/painting.dart';

enum WeftDisplay { block, inline, listItem, none }

enum WeftWhiteSpace { normal, pre, preWrap }

enum WeftListStyle { none, disc, decimal }

enum WeftBoxSizing { contentBox, borderBox }

enum WeftFloat { none, left, right }

enum WeftClear { none, left, right, both }

enum WeftBorderCollapse { separate, collapse }

enum WeftVerticalAlign { top, middle, bottom }

/// Vertical alignment of inline replaced content (image atoms) inside a line
/// box. Table cells keep [WeftVerticalAlign]; this enum only exists because
/// CSS `vertical-align: baseline` and `middle` mean different things for
/// inline atoms than the merged table semantics.
enum WeftInlineVerticalAlign { baseline, middle }

final class WeftBorderSide {
  const WeftBorderSide({required this.width, required this.color});

  static const none = WeftBorderSide(width: 0, color: Color(0x00000000));

  final double width;
  final Color color;

  bool get isVisible => width > 0 && color.a > 0;
}

final class WeftComputedStyle {
  const WeftComputedStyle({
    required this.display,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.color,
    required this.lineHeight,
    required this.textAlign,
    required this.textDecoration,
    required this.whiteSpace,
    required this.listStyle,
    this.fontFamily,
    this.backgroundColor,
    this.marginTop = 0,
    this.marginRight = 0,
    this.marginBottom = 0,
    this.marginLeft = 0,
    this.marginLeftAuto = false,
    this.marginRightAuto = false,
    this.paddingTop = 0,
    this.paddingRight = 0,
    this.paddingBottom = 0,
    this.paddingLeft = 0,
    this.width,
    this.minWidth,
    this.maxWidth,
    this.height,
    this.widthPercent,
    this.heightPercent,
    this.boxSizing = WeftBoxSizing.contentBox,
    this.float = WeftFloat.none,
    this.clear = WeftClear.none,
    this.borderCollapse = WeftBorderCollapse.separate,
    this.borderSpacingHorizontal = 2,
    this.borderSpacingVertical = 2,
    this.verticalAlign = WeftVerticalAlign.top,
    this.inlineVerticalAlign = WeftInlineVerticalAlign.baseline,
    this.borderTop = WeftBorderSide.none,
    this.borderRight = WeftBorderSide.none,
    this.borderBottom = WeftBorderSide.none,
    this.borderLeft = WeftBorderSide.none,
    this.direction = TextDirection.ltr,
    this.lang,
  });

  static const initial = WeftComputedStyle(
    display: WeftDisplay.inline,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    color: Color(0xFF1F2328),
    lineHeight: 1.5,
    textAlign: TextAlign.start,
    textDecoration: TextDecoration.none,
    whiteSpace: WeftWhiteSpace.normal,
    listStyle: WeftListStyle.none,
  );

  final WeftDisplay display;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String? fontFamily;
  final Color color;
  final Color? backgroundColor;
  final double lineHeight;
  final TextAlign textAlign;
  final TextDecoration textDecoration;
  final WeftWhiteSpace whiteSpace;
  final WeftListStyle listStyle;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;

  /// `margin-left/right: auto`. Block layout distributes the space left over
  /// after the resolved box width and the non-auto horizontal margins to
  /// these sides (negative slack keeps them at zero). The parsed numeric
  /// margin stays 0 whenever the flag is set, so consumers that do not
  /// implement auto distribution — replaced images, floats and table cells —
  /// keep treating auto as zero. Vertical auto margins never carry a flag;
  /// they resolve to zero at parse time.
  final bool marginLeftAuto;
  final bool marginRightAuto;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;
  final double? width;
  final double? minWidth;
  final double? maxWidth;

  /// Explicit CSS height in px/em/rem. Block boxes size their border box to
  /// it (box-sizing converted like width, ADR 0009) and let overflowing
  /// content paint unclipped; percentage heights resolve as auto. Replaced
  /// content (images) consumes it for intrinsic ratio sizing (ADR 0018).
  final double? height;

  /// Percentage width (e.g. `50` for `width: 50%`). Block boxes and replaced
  /// content resolve it against the containing block's content width before
  /// the box's own margins. The resolver only ever fills this or [width], not
  /// both; if both were present this value wins.
  final double? widthPercent;

  /// Percentage height. Stored for diagnostics but resolved as auto: the
  /// parent height is unknown while content flows.
  final double? heightPercent;
  final WeftBoxSizing boxSizing;
  final WeftFloat float;
  final WeftClear clear;
  final WeftBorderCollapse borderCollapse;

  /// Cell spacing between table columns/rows in the separate borders model.
  final double borderSpacingHorizontal;
  final double borderSpacingVertical;
  final WeftVerticalAlign verticalAlign;

  /// Inline atom alignment; distinct from [verticalAlign] so table cell
  /// semantics (which merge baseline into middle) stay untouched.
  final WeftInlineVerticalAlign inlineVerticalAlign;
  final WeftBorderSide borderTop;
  final WeftBorderSide borderRight;
  final WeftBorderSide borderBottom;
  final WeftBorderSide borderLeft;

  /// Base text direction for the block's inline content (ADR 0042). Derived
  /// from the `dir` attribute (`auto` resolves through the first-strong
  /// scan) or the CSS `direction` property; inline content inherits it.
  /// Physical start alignment, list marker placement and caret edges follow
  /// this value; box geometry itself stays direction-neutral.
  final TextDirection direction;

  /// The `lang` attribute value (BCP-47-ish), forwarded to TextPainter as
  /// its locale so line breaking and font fallback match the content. Null
  /// keeps the engine's default `Locale('zh')` — the value every pre-ADR
  /// 0042 document was laid out with.
  final String? lang;

  double get horizontalPadding => paddingLeft + paddingRight;

  double get verticalPadding => paddingTop + paddingBottom;

  double get horizontalBorder => borderLeft.width + borderRight.width;

  double get verticalBorder => borderTop.width + borderBottom.width;

  TextStyle toTextStyle({bool includeBackground = false}) {
    return TextStyle(
      color: color,
      backgroundColor: includeBackground ? backgroundColor : null,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      fontFamily: fontFamily,
      height: lineHeight,
      // CSS distributes line-height leading evenly above and below the
      // content area (half-leading). Flutter's default is proportional,
      // which shifts glyphs ~1-2px downward at common sizes.
      leadingDistribution: TextLeadingDistribution.even,
      decoration: textDecoration,
    );
  }
}
