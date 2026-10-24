import 'package:flutter/painting.dart';

enum WeftDisplay { block, inline, listItem, none }

enum WeftWhiteSpace { normal, pre, preWrap }

enum WeftListStyle { none, disc, decimal }

enum WeftBoxSizing { contentBox, borderBox }

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
    this.paddingTop = 0,
    this.paddingRight = 0,
    this.paddingBottom = 0,
    this.paddingLeft = 0,
    this.width,
    this.minWidth,
    this.maxWidth,
    this.boxSizing = WeftBoxSizing.contentBox,
    this.borderTop = WeftBorderSide.none,
    this.borderRight = WeftBorderSide.none,
    this.borderBottom = WeftBorderSide.none,
    this.borderLeft = WeftBorderSide.none,
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
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;
  final double? width;
  final double? minWidth;
  final double? maxWidth;
  final WeftBoxSizing boxSizing;
  final WeftBorderSide borderTop;
  final WeftBorderSide borderRight;
  final WeftBorderSide borderBottom;
  final WeftBorderSide borderLeft;

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
