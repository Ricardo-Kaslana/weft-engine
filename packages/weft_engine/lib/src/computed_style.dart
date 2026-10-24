import 'package:flutter/painting.dart';

enum WeftDisplay { block, inline, listItem, none }

enum WeftWhiteSpace { normal, pre, preWrap }

enum WeftListStyle { none, disc, decimal }

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

  double get horizontalPadding => paddingLeft + paddingRight;

  double get verticalPadding => paddingTop + paddingBottom;

  TextStyle toTextStyle({bool includeBackground = false}) {
    return TextStyle(
      color: color,
      backgroundColor: includeBackground ? backgroundColor : null,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      fontFamily: fontFamily,
      height: lineHeight,
      decoration: textDecoration,
    );
  }
}
