import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';

final class WeftStyleResolver {
  const WeftStyleResolver(this.styleSheet);

  final WeftStyleSheet styleSheet;

  WeftComputedStyle resolve(
    WeftElement element, {
    required WeftComputedStyle parent,
    required List<WeftElement> ancestors,
  }) {
    final builder = _StyleBuilder.fromParent(parent)
      ..applyTagDefaults(element.tag, parent);

    final matched = <_MatchedRule>[];
    for (final rule in styleSheet.rules) {
      WeftSpecificity? best;
      for (final selector in rule.selectors) {
        if (!selector.matches(element, ancestors)) continue;
        final specificity = selector.specificity;
        if (best == null || specificity.compareTo(best) > 0) {
          best = specificity;
        }
      }
      if (best != null) {
        matched.add(_MatchedRule(rule, best));
      }
    }

    matched.sort((left, right) {
      final bySpecificity = left.specificity.compareTo(right.specificity);
      if (bySpecificity != 0) return bySpecificity;
      return left.rule.order.compareTo(right.rule.order);
    });

    final winning = <String, String>{};
    for (final candidate in matched) {
      _mergeDeclarations(winning, candidate.rule.declarations);
    }
    _mergeDeclarations(winning, element.inlineStyle);
    builder.applyCascaded(winning, parent);
    return builder.build();
  }

  void _mergeDeclarations(
    Map<String, String> target,
    Map<String, String> declarations,
  ) {
    for (final declaration in declarations.entries) {
      final property = declaration.key;
      final value = declaration.value;
      if (property == 'border') {
        target['border-top'] = value;
        target['border-right'] = value;
        target['border-bottom'] = value;
        target['border-left'] = value;
      } else if (property == 'margin' || property == 'padding') {
        final parts = value
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.isEmpty || parts.length > 4) continue;
        final expanded = switch (parts.length) {
          1 => [parts[0], parts[0], parts[0], parts[0]],
          2 => [parts[0], parts[1], parts[0], parts[1]],
          3 => [parts[0], parts[1], parts[2], parts[1]],
          _ => parts,
        };
        target['$property-top'] = expanded[0];
        target['$property-right'] = expanded[1];
        target['$property-bottom'] = expanded[2];
        target['$property-left'] = expanded[3];
      } else {
        target[property] = value;
      }
    }
  }
}

final class _MatchedRule {
  const _MatchedRule(this.rule, this.specificity);

  final WeftStyleRule rule;
  final WeftSpecificity specificity;
}

final class _StyleBuilder {
  _StyleBuilder.fromParent(WeftComputedStyle parent)
      : fontSize = parent.fontSize,
        fontWeight = parent.fontWeight,
        fontStyle = parent.fontStyle,
        fontFamily = parent.fontFamily,
        color = parent.color,
        lineHeight = parent.lineHeight,
        textAlign = parent.textAlign,
        textDecoration = parent.textDecoration,
        whiteSpace = parent.whiteSpace,
        listStyle = parent.listStyle,
        display = WeftDisplay.inline;

  double fontSize;
  FontWeight fontWeight;
  FontStyle fontStyle;
  String? fontFamily;
  Color color;
  double lineHeight;
  TextAlign textAlign;
  TextDecoration textDecoration;
  WeftWhiteSpace whiteSpace;
  WeftListStyle listStyle;
  WeftDisplay display;
  Color? backgroundColor;
  double marginTop = 0;
  double marginRight = 0;
  double marginBottom = 0;
  double marginLeft = 0;
  double paddingTop = 0;
  double paddingRight = 0;
  double paddingBottom = 0;
  double paddingLeft = 0;
  double? width;
  double? minWidth;
  double? maxWidth;
  WeftBoxSizing boxSizing = WeftBoxSizing.contentBox;
  WeftFloat float = WeftFloat.none;
  WeftClear clear = WeftClear.none;
  WeftBorderSide borderTop = WeftBorderSide.none;
  WeftBorderSide borderRight = WeftBorderSide.none;
  WeftBorderSide borderBottom = WeftBorderSide.none;
  WeftBorderSide borderLeft = WeftBorderSide.none;

  void applyTagDefaults(String tag, WeftComputedStyle parent) {
    switch (tag) {
      case 'body':
        display = WeftDisplay.block;
        lineHeight = 1.5;
      case 'div':
      case 'dl':
      case 'dt':
      case 'dd':
        display = WeftDisplay.block;
      case 'p':
        display = WeftDisplay.block;
        marginTop = fontSize;
        marginBottom = fontSize;
      case 'blockquote':
        display = WeftDisplay.block;
        marginTop = fontSize;
        marginBottom = fontSize;
        marginLeft = 40;
        marginRight = 40;
      case 'pre':
        display = WeftDisplay.block;
        fontFamily = 'monospace';
        fontSize = parent.fontSize * 0.875;
        lineHeight = 1.45;
        marginTop = parent.fontSize;
        marginBottom = parent.fontSize;
        paddingTop = 12;
        paddingRight = 12;
        paddingBottom = 12;
        paddingLeft = 12;
        backgroundColor = const Color(0xFFF6F8FA);
        whiteSpace = WeftWhiteSpace.pre;
      case 'ul':
        display = WeftDisplay.block;
        marginTop = fontSize;
        marginBottom = fontSize;
        paddingLeft = 40;
        listStyle = WeftListStyle.disc;
      case 'ol':
        display = WeftDisplay.block;
        marginTop = fontSize;
        marginBottom = fontSize;
        paddingLeft = 40;
        listStyle = WeftListStyle.decimal;
      case 'li':
        display = WeftDisplay.listItem;
      case 'h1':
        display = WeftDisplay.block;
        fontSize = parent.fontSize * 2;
        fontWeight = FontWeight.w700;
        lineHeight = 1.25;
        marginTop = fontSize * 0.67;
        marginBottom = fontSize * 0.67;
      case 'h2':
        display = WeftDisplay.block;
        fontSize = parent.fontSize * 1.5;
        fontWeight = FontWeight.w700;
        lineHeight = 1.3;
        marginTop = fontSize * 0.83;
        marginBottom = fontSize * 0.83;
      case 'h3':
        display = WeftDisplay.block;
        fontSize = parent.fontSize * 1.17;
        fontWeight = FontWeight.w700;
        lineHeight = 1.35;
        marginTop = fontSize * 0.83;
        marginBottom = fontSize * 0.83;
      case 'h4':
        display = WeftDisplay.block;
        fontWeight = FontWeight.w700;
        lineHeight = 1.4;
        marginTop = fontSize * 1.33;
        marginBottom = fontSize * 1.33;
      case 'h5':
        display = WeftDisplay.block;
        fontSize = parent.fontSize * 0.83;
        fontWeight = FontWeight.w700;
        lineHeight = 1.4;
        marginTop = fontSize * 1.67;
        marginBottom = fontSize * 1.67;
      case 'h6':
        display = WeftDisplay.block;
        fontSize = parent.fontSize * 0.67;
        fontWeight = FontWeight.w700;
        lineHeight = 1.4;
        marginTop = fontSize * 2.33;
        marginBottom = fontSize * 2.33;
      case 'hr':
        display = WeftDisplay.block;
        marginTop = fontSize;
        marginBottom = fontSize;
        backgroundColor = const Color(0xFFD0D7DE);
      case 'strong':
      case 'b':
        fontWeight = FontWeight.w700;
      case 'em':
      case 'i':
        fontStyle = FontStyle.italic;
      case 'u':
        textDecoration = TextDecoration.underline;
      case 's':
        textDecoration = TextDecoration.lineThrough;
      case 'small':
        fontSize = parent.fontSize * 0.85;
      case 'sub':
      case 'sup':
        fontSize = parent.fontSize * 0.75;
      case 'code':
        fontFamily = 'monospace';
        fontSize = parent.fontSize * 0.9;
        backgroundColor = const Color(0xFFEFF1F3);
      case 'a':
        color = const Color(0xFF0969DA);
        textDecoration = TextDecoration.underline;
      default:
        break;
    }
  }

  void applyCascaded(
    Map<String, String> declarations,
    WeftComputedStyle parent,
  ) {
    final fontSizeValue = declarations['font-size'];
    if (fontSizeValue != null) {
      final parsed = _fontSize(fontSizeValue, parent.fontSize);
      if (parsed != null) fontSize = parsed;
    }

    final fontFamilyValue = declarations['font-family'];
    if (fontFamilyValue != null) {
      fontFamily = _fontFamily(fontFamilyValue);
    }

    final fontWeightValue = declarations['font-weight'];
    if (fontWeightValue != null) {
      fontWeight = _fontWeight(fontWeightValue) ?? fontWeight;
    }

    final fontStyleValue = declarations['font-style'];
    if (fontStyleValue == 'italic' || fontStyleValue == 'oblique') {
      fontStyle = FontStyle.italic;
    } else if (fontStyleValue == 'normal') {
      fontStyle = FontStyle.normal;
    }

    final colorValue = declarations['color'];
    if (colorValue != null) {
      final parsed = _color(colorValue, parent.color);
      if (parsed != null) color = parsed;
    }

    final backgroundValue = declarations['background-color'];
    if (backgroundValue != null) {
      final normalized = backgroundValue.trim().toLowerCase();
      backgroundColor =
          normalized == 'transparent' ? null : _color(backgroundValue, color);
    }

    final boxSizingValue = declarations['box-sizing'];
    if (boxSizingValue != null) {
      boxSizing = boxSizingValue.trim().toLowerCase() == 'border-box'
          ? WeftBoxSizing.borderBox
          : WeftBoxSizing.contentBox;
    }

    final widthValue = declarations['width'];
    if (widthValue != null) {
      final normalized = widthValue.trim().toLowerCase();
      width = normalized == 'auto' ? null : _length(widthValue, fontSize);
    }
    final minWidthValue = declarations['min-width'];
    if (minWidthValue != null) {
      final normalized = minWidthValue.trim().toLowerCase();
      minWidth = normalized == 'auto' || normalized == 'none'
          ? null
          : _length(minWidthValue, fontSize);
    }
    final maxWidthValue = declarations['max-width'];
    if (maxWidthValue != null) {
      final normalized = maxWidthValue.trim().toLowerCase();
      maxWidth = normalized == 'none' || normalized == 'auto'
          ? null
          : _length(maxWidthValue, fontSize);
    }

    final lineHeightValue = declarations['line-height'];
    if (lineHeightValue != null) {
      final parsed = _lineHeight(lineHeightValue, fontSize);
      if (parsed != null) lineHeight = parsed;
    }

    final textAlignValue = declarations['text-align'];
    if (textAlignValue != null) {
      textAlign = _textAlign(textAlignValue) ?? textAlign;
    }

    final decorationValue = declarations['text-decoration'];
    if (decorationValue != null) {
      textDecoration = _textDecoration(decorationValue) ?? textDecoration;
    }

    final whiteSpaceValue = declarations['white-space'];
    if (whiteSpaceValue == 'pre') {
      whiteSpace = WeftWhiteSpace.pre;
    } else if (whiteSpaceValue == 'pre-wrap') {
      whiteSpace = WeftWhiteSpace.preWrap;
    } else if (whiteSpaceValue == 'normal') {
      whiteSpace = WeftWhiteSpace.normal;
    }

    final displayValue = declarations['display'];
    if (displayValue != null) {
      display = switch (displayValue.trim().toLowerCase()) {
        'block' => WeftDisplay.block,
        'inline' => WeftDisplay.inline,
        'list-item' => WeftDisplay.listItem,
        'none' => WeftDisplay.none,
        _ => display,
      };
    }

    final listStyleValue = declarations['list-style-type'];
    if (listStyleValue != null) {
      listStyle = switch (listStyleValue.trim().toLowerCase()) {
        'none' => WeftListStyle.none,
        'disc' || 'circle' || 'square' => WeftListStyle.disc,
        'decimal' => WeftListStyle.decimal,
        _ => listStyle,
      };
    }

    final floatValue = declarations['float'];
    if (floatValue != null) {
      float = switch (floatValue.trim().toLowerCase()) {
        'left' => WeftFloat.left,
        'right' => WeftFloat.right,
        'none' => WeftFloat.none,
        _ => float,
      };
    }

    final clearValue = declarations['clear'];
    if (clearValue != null) {
      clear = switch (clearValue.trim().toLowerCase()) {
        'left' => WeftClear.left,
        'right' => WeftClear.right,
        'both' => WeftClear.both,
        'none' => WeftClear.none,
        _ => clear,
      };
    }

    marginTop = _length(
          declarations['margin-top'],
          fontSize,
          allowNegative: true,
        ) ??
        marginTop;
    marginRight = _length(
          declarations['margin-right'],
          fontSize,
          allowNegative: true,
        ) ??
        marginRight;
    marginBottom = _length(
          declarations['margin-bottom'],
          fontSize,
          allowNegative: true,
        ) ??
        marginBottom;
    marginLeft = _length(
          declarations['margin-left'],
          fontSize,
          allowNegative: true,
        ) ??
        marginLeft;
    paddingTop = _length(declarations['padding-top'], fontSize) ?? paddingTop;
    paddingRight =
        _length(declarations['padding-right'], fontSize) ?? paddingRight;
    paddingBottom =
        _length(declarations['padding-bottom'], fontSize) ?? paddingBottom;
    paddingLeft =
        _length(declarations['padding-left'], fontSize) ?? paddingLeft;

    borderTop =
        _borderSide(declarations['border-top'], fontSize, color) ?? borderTop;
    borderRight = _borderSide(declarations['border-right'], fontSize, color) ??
        borderRight;
    borderBottom =
        _borderSide(declarations['border-bottom'], fontSize, color) ??
            borderBottom;
    borderLeft =
        _borderSide(declarations['border-left'], fontSize, color) ?? borderLeft;
  }

  WeftComputedStyle build() {
    return WeftComputedStyle(
      display: display,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      fontFamily: fontFamily,
      color: color,
      backgroundColor: backgroundColor,
      lineHeight: lineHeight,
      textAlign: textAlign,
      textDecoration: textDecoration,
      whiteSpace: whiteSpace,
      listStyle: listStyle,
      marginTop: marginTop,
      marginRight: marginRight,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      paddingTop: paddingTop,
      paddingRight: paddingRight,
      paddingBottom: paddingBottom,
      paddingLeft: paddingLeft,
      width: width,
      minWidth: minWidth,
      maxWidth: maxWidth,
      boxSizing: boxSizing,
      float: float,
      clear: clear,
      borderTop: borderTop,
      borderRight: borderRight,
      borderBottom: borderBottom,
      borderLeft: borderLeft,
    );
  }

  static WeftBorderSide? _borderSide(
    String? raw,
    double fontSize,
    Color currentColor,
  ) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'none' || value == '0') return WeftBorderSide.none;
    if (!RegExp(r'(?:^|\s)solid(?:\s|$)').hasMatch(value)) {
      return WeftBorderSide.none;
    }

    var width = 3.0;
    if (RegExp(r'(?:^|\s)thin(?:\s|$)').hasMatch(value)) {
      width = 1;
    } else if (RegExp(r'(?:^|\s)medium(?:\s|$)').hasMatch(value)) {
      width = 3;
    } else if (RegExp(r'(?:^|\s)thick(?:\s|$)').hasMatch(value)) {
      width = 5;
    } else if (RegExp(r'(?:^|\s)0(?:\s|$)').hasMatch(value)) {
      width = 0;
    } else {
      final match = RegExp(r'(\d+(?:\.\d+)?)(px|em|rem)').firstMatch(value);
      if (match != null) {
        final number = double.tryParse(match.group(1)!);
        if (number != null) {
          width = switch (match.group(2)) {
            'em' => number * fontSize,
            'rem' => number * 16,
            _ => number,
          };
        }
      }
    }

    final cleaned = value
        .replaceAll(RegExp(r'(\d+(?:\.\d+)?)(px|em|rem)'), ' ')
        .replaceAll(RegExp(r'(?:thin|medium|thick)'), ' ')
        .replaceAll(RegExp(r'(?:solid|none)'), ' ')
        .trim();
    var color = currentColor;
    if (cleaned.isNotEmpty) {
      color = _color(cleaned, currentColor) ?? currentColor;
    }
    return WeftBorderSide(width: math.max(0, width), color: color);
  }

  static double? _length(
    String? raw,
    double fontSize, {
    bool allowNegative = false,
  }) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value == '0') return 0;
    double? parsed;
    if (value.endsWith('px')) {
      parsed = double.tryParse(value.substring(0, value.length - 2));
    } else if (value.endsWith('rem')) {
      final number = double.tryParse(value.substring(0, value.length - 3));
      if (number != null) parsed = number * 16;
    } else if (value.endsWith('em')) {
      final number = double.tryParse(value.substring(0, value.length - 2));
      if (number != null) parsed = number * fontSize;
    } else {
      parsed = double.tryParse(value);
    }
    if (parsed == null || !parsed.isFinite) return null;
    if (!allowNegative && parsed < 0) return null;
    return parsed;
  }

  static double? _fontSize(String raw, double parentSize) {
    final value = raw.trim().toLowerCase();
    final keywords = <String, double>{
      'xx-small': 9,
      'x-small': 10,
      'small': 13,
      'medium': 16,
      'large': 18,
      'x-large': 24,
      'xx-large': 32,
    };
    final keyword = keywords[value];
    if (keyword != null) return keyword;
    if (value.endsWith('%')) {
      final number = double.tryParse(value.substring(0, value.length - 1));
      return number == null ? null : parentSize * number / 100;
    }
    return _length(value, parentSize);
  }

  static double? _lineHeight(String raw, double fontSize) {
    final value = raw.trim().toLowerCase();
    if (value == 'normal') return 1.2;
    if (value.endsWith('%')) {
      final number = double.tryParse(value.substring(0, value.length - 1));
      return number == null ? null : number / 100;
    }
    if (value.endsWith('px')) {
      final number = double.tryParse(value.substring(0, value.length - 2));
      if (number == null || fontSize <= 0) return null;
      return number / fontSize;
    }
    final number = double.tryParse(value);
    return number == null || number <= 0 ? null : number;
  }

  static FontWeight? _fontWeight(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'normal') return FontWeight.w400;
    if (value == 'bold') return FontWeight.w700;
    if (value == 'bolder') return FontWeight.w700;
    if (value == 'lighter') return FontWeight.w300;
    final number = int.tryParse(value);
    if (number == null) return null;
    final clamped = number.clamp(100, 900).toInt();
    final index = ((clamped / 100).round() - 1).clamp(0, 8).toInt();
    return FontWeight.values[index];
  }

  static String? _fontFamily(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('monospace')) return 'monospace';
    if (value.contains('serif') && !value.contains('sans-serif')) {
      return 'serif';
    }
    if (value.contains('sans-serif')) return null;
    final first = raw.split(',').first.trim().replaceAll('"', '').replaceAll(
          "'",
          '',
        );
    return first.isEmpty ? null : first;
  }

  static TextAlign? _textAlign(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      'start' => TextAlign.start,
      'end' => TextAlign.end,
      _ => null,
    };
  }

  static TextDecoration? _textDecoration(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'none') return TextDecoration.none;
    if (value.contains('underline')) return TextDecoration.underline;
    if (value.contains('line-through')) return TextDecoration.lineThrough;
    if (value.contains('overline')) return TextDecoration.overline;
    return null;
  }

  static Color? _color(String raw, Color currentColor) {
    final value = raw.trim().toLowerCase();
    if (value == 'currentcolor') return currentColor;
    if (value == 'transparent') return null;
    const names = <String, Color>{
      'black': Color(0xFF000000),
      'silver': Color(0xFFC0C0C0),
      'gray': Color(0xFF808080),
      'grey': Color(0xFF808080),
      'white': Color(0xFFFFFFFF),
      'maroon': Color(0xFF800000),
      'red': Color(0xFFFF0000),
      'purple': Color(0xFF800080),
      'fuchsia': Color(0xFFFF00FF),
      'green': Color(0xFF008000),
      'lime': Color(0xFF00FF00),
      'olive': Color(0xFF808000),
      'yellow': Color(0xFFFFFF00),
      'navy': Color(0xFF000080),
      'blue': Color(0xFF0000FF),
      'teal': Color(0xFF008080),
      'aqua': Color(0xFF00FFFF),
      'orange': Color(0xFFFFA500),
    };
    final named = names[value];
    if (named != null) return named;

    if (value.startsWith('#')) {
      var hex = value.substring(1);
      if (hex.length == 3 || hex.length == 4) {
        hex = hex.split('').map((digit) => '$digit$digit').join();
      }
      if (hex.length == 6) hex = 'ff$hex';
      if (hex.length != 8) return null;
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(parsed);
    }

    final rgb = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([\d.]+))?\s*\)$',
    ).firstMatch(value);
    if (rgb == null) return null;
    final red = int.parse(rgb.group(1)!).clamp(0, 255).toInt();
    final green = int.parse(rgb.group(2)!).clamp(0, 255).toInt();
    final blue = int.parse(rgb.group(3)!).clamp(0, 255).toInt();
    final alpha = rgb.group(4) == null
        ? 1.0
        : double.parse(rgb.group(4)!).clamp(0.0, 1.0).toDouble();
    return Color.fromARGB(
      (alpha * 255).round(),
      red,
      green,
      blue,
    );
  }
}
