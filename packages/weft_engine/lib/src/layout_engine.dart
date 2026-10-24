import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'layout_result.dart';
import 'style_resolver.dart';

final class WeftLayoutEngine {
  const WeftLayoutEngine();

  WeftLayoutResult layout(
    WeftDocumentSnapshot document, {
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (!width.isFinite || width <= 0) {
      return WeftLayoutResult(
        size: Size.zero,
        boxes: const [],
        commands: const [],
        links: const [],
      );
    }

    final body = document.body;
    if (body == null) {
      return WeftLayoutResult(
        size: Size(width, 0),
        boxes: const [],
        commands: const [],
        links: const [],
      );
    }

    final context = _LayoutContext(
      styleResolver: WeftStyleResolver(document.styleSheet),
      textScaler: textScaler,
    );
    final bodyStyle = context.styleResolver.resolve(
      body,
      parent: WeftComputedStyle.initial,
      ancestors: const [],
    );
    final bodyLayout = context.layoutBlock(
      element: body,
      style: bodyStyle,
      availableWidth: width,
      left: 0,
      top: 0,
      ancestors: const [],
    );

    return WeftLayoutResult(
      size: Size(width, bodyLayout.height),
      boxes: context.boxes,
      commands: context.commands,
      links: context.links,
    );
  }
}

final class _LayoutContext {
  _LayoutContext({
    required this.styleResolver,
    required this.textScaler,
  });

  final WeftStyleResolver styleResolver;
  final TextScaler textScaler;
  final List<WeftLayoutBox> boxes = <WeftLayoutBox>[];
  final List<WeftPaintCommand> commands = <WeftPaintCommand>[];
  final List<WeftLinkRegion> links = <WeftLinkRegion>[];

  _BlockLayout layoutBlock({
    required WeftElement element,
    required WeftComputedStyle style,
    required double availableWidth,
    required double left,
    required double top,
    required List<WeftElement> ancestors,
    String? marker,
  }) {
    if (style.display == WeftDisplay.none) {
      return const _BlockLayout(height: 0, marginTop: 0, marginBottom: 0);
    }

    final borderX = left + style.marginLeft;
    final borderWidth = math.max(
      0.0,
      availableWidth - style.marginLeft - style.marginRight,
    );
    final contentX = borderX + style.paddingLeft;
    final contentY = top + style.paddingTop;
    final contentWidth = math.max(0.0, borderWidth - style.horizontalPadding);
    final commandStart = commands.length;
    final childAncestors = <WeftElement>[...ancestors, element];

    final contentHeight = element.tag == 'hr'
        ? 1.0
        : _layoutChildren(
            element: element,
            style: style,
            contentX: contentX,
            contentY: contentY,
            contentWidth: contentWidth,
            childAncestors: childAncestors,
          );
    final height = style.verticalPadding + contentHeight;

    var insertIndex = commandStart;
    final background = style.backgroundColor;
    if (background != null && background.a > 0) {
      commands.insert(
        insertIndex,
        WeftRectPaintCommand(
          nodeId: element.id,
          rect: Rect.fromLTWH(borderX, top, borderWidth, height),
          color: background,
        ),
      );
      insertIndex += 1;
    }

    if (marker != null && contentWidth > 0) {
      final markerCommand = _createMarker(
        marker: marker,
        style: style,
        contentX: contentX,
        contentY: contentY,
        nodeId: element.id,
      );
      if (markerCommand != null) {
        commands.insert(insertIndex, markerCommand);
      }
    }

    if (borderWidth > 0 && height > 0) {
      boxes.add(
        WeftLayoutBox(
          nodeId: element.id,
          rect: Rect.fromLTWH(borderX, top, borderWidth, height),
        ),
      );
    }

    return _BlockLayout(
      height: height,
      marginTop: style.marginTop,
      marginBottom: style.marginBottom,
    );
  }

  double _layoutChildren({
    required WeftElement element,
    required WeftComputedStyle style,
    required double contentX,
    required double contentY,
    required double contentWidth,
    required List<WeftElement> childAncestors,
  }) {
    var cursor = contentY;
    var pendingMargin = 0.0;
    var orderedItem = 0;
    final inline = _InlineAccumulator(this);

    double flushInline() {
      if (!inline.hasContent) return 0;
      cursor += pendingMargin;
      pendingMargin = 0;
      final height = _appendInline(
        inline,
        parentNodeId: element.id,
        parentStyle: style,
        x: contentX,
        y: cursor,
        width: contentWidth,
      );
      cursor += height;
      inline.reset();
      return height;
    }

    for (final child in element.children) {
      if (child is WeftText) {
        inline.addText(child, style);
        continue;
      }
      if (child is! WeftElement) continue;

      final childStyle = styleResolver.resolve(
        child,
        parent: style,
        ancestors: childAncestors,
      );
      if (childStyle.display == WeftDisplay.none) continue;

      if (childStyle.display == WeftDisplay.inline) {
        inline.collectElement(child, childStyle, childAncestors);
        continue;
      }

      flushInline();
      if (child.tag == 'li' && childStyle.listStyle == WeftListStyle.decimal) {
        orderedItem += 1;
      }

      final gap = math.max(pendingMargin, childStyle.marginTop);
      cursor += gap;
      final marker = _markerFor(
        child: child,
        childStyle: childStyle,
        orderedItem: orderedItem,
      );
      final result = layoutBlock(
        element: child,
        style: childStyle,
        availableWidth: contentWidth,
        left: contentX,
        top: cursor,
        ancestors: childAncestors,
        marker: marker,
      );
      cursor += result.height;
      pendingMargin = childStyle.marginBottom;
    }

    flushInline();
    cursor += pendingMargin;
    return math.max(0, cursor - contentY);
  }

  double _appendInline(
    _InlineAccumulator inline, {
    required int parentNodeId,
    required WeftComputedStyle parentStyle,
    required double x,
    required double y,
    required double width,
  }) {
    if (width <= 0) return 0;
    final inlineLayout = inline.buildLayout(
      parentStyle: parentStyle,
      width: width,
      textScaler: textScaler,
    );
    if (inlineLayout == null) return 0;
    final painter = inlineLayout.painter;
    final height = painter.height;
    if (height <= 0) {
      painter.dispose();
      return 0;
    }
    final offset = Offset(x, y);
    commands.add(
      WeftTextPaintCommand(
        nodeId: parentNodeId,
        painter: painter,
        offset: offset,
      ),
    );
    for (final link in inlineLayout.links) {
      links.add(link.shift(offset));
    }
    return height;
  }

  String? _markerFor({
    required WeftElement child,
    required WeftComputedStyle childStyle,
    required int orderedItem,
  }) {
    if (child.tag != 'li' || childStyle.listStyle == WeftListStyle.none) {
      return null;
    }
    if (childStyle.listStyle == WeftListStyle.decimal) {
      return '$orderedItem.';
    }
    return '\u2022';
  }

  WeftTextPaintCommand? _createMarker({
    required String marker,
    required WeftComputedStyle style,
    required double contentX,
    required double contentY,
    required int nodeId,
  }) {
    final textStyle = style.toTextStyle().copyWith(
          decoration: TextDecoration.none,
          backgroundColor: null,
          height: 1,
        );
    final painter = TextPainter(
      text: TextSpan(text: marker, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      locale: const Locale('zh'),
    )..layout();
    if (painter.width <= 0 || painter.height <= 0) {
      painter.dispose();
      return null;
    }
    final lineHeight = style.fontSize * style.lineHeight;
    final y = contentY + math.max(0.0, (lineHeight - painter.height) / 2);
    final x = math.max(0.0, contentX - painter.width - 8);
    return WeftTextPaintCommand(
      nodeId: nodeId,
      painter: painter,
      offset: Offset(x, y),
    );
  }
}

final class _BlockLayout {
  const _BlockLayout({
    required this.height,
    required this.marginTop,
    required this.marginBottom,
  });

  final double height;
  final double marginTop;
  final double marginBottom;
}

final class _InlineRun {
  _InlineRun(
    this.nodeId,
    this.style,
    this.text, {
    this.href,
    this.linkNodeId,
  });

  final int nodeId;
  final WeftComputedStyle style;
  final String? href;
  final int? linkNodeId;
  String text;
}

final class _LinkTarget {
  const _LinkTarget({required this.nodeId, required this.href});

  final int nodeId;
  final String href;
}

final class _LinkRunRange {
  _LinkRunRange({
    required this.nodeId,
    required this.href,
    required this.start,
    required this.end,
  });

  final int nodeId;
  final String href;
  int start;
  int end;
}

final class _InlineLayout {
  const _InlineLayout({required this.painter, required this.links});

  final TextPainter painter;
  final List<WeftLinkRegion> links;
}

final class _InlineAccumulator {
  _InlineAccumulator(this.context);

  final _LayoutContext context;
  final List<_InlineRun> _runs = <_InlineRun>[];
  var _lastWasSpace = true;

  bool get hasContent => _runs.any((run) => run.text.isNotEmpty);

  void reset() {
    _runs.clear();
    _lastWasSpace = true;
  }

  void addText(
    WeftText node,
    WeftComputedStyle style, {
    _LinkTarget? link,
  }) {
    if (node.text.isEmpty) return;
    if (style.whiteSpace == WeftWhiteSpace.normal) {
      var text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (_lastWasSpace && text.startsWith(' ')) {
        text = text.substring(1);
      }
      if (text.isEmpty) return;
      _runs.add(
        _InlineRun(
          node.id,
          style,
          text,
          href: link?.href,
          linkNodeId: link?.nodeId,
        ),
      );
      _lastWasSpace = text.endsWith(' ');
      return;
    }

    _runs.add(
      _InlineRun(
        node.id,
        style,
        node.text,
        href: link?.href,
        linkNodeId: link?.nodeId,
      ),
    );
    _lastWasSpace = _endsWithSpace(node.text);
  }

  void addBreak(int nodeId, WeftComputedStyle style) {
    _trimTrailingCollapsibleSpace();
    _runs.add(_InlineRun(nodeId, style, '\n'));
    _lastWasSpace = true;
  }

  void collectElement(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors, {
    _LinkTarget? link,
  }) {
    if (style.display == WeftDisplay.none) return;
    if (element.tag == 'br') {
      addBreak(element.id, style);
      return;
    }

    final href = element.tag == 'a' ? element.attribute('href') : null;
    final activeLink = href == null || href.isEmpty
        ? link
        : _LinkTarget(nodeId: element.id, href: href);
    final childAncestors = <WeftElement>[...ancestors, element];
    for (final child in element.children) {
      if (child is WeftText) {
        addText(child, style, link: activeLink);
      } else if (child is WeftElement) {
        final childStyle = context.styleResolver.resolve(
          child,
          parent: style,
          ancestors: childAncestors,
        );
        collectElement(
          child,
          childStyle,
          childAncestors,
          link: activeLink,
        );
      }
    }
  }

  _InlineLayout? buildLayout({
    required WeftComputedStyle parentStyle,
    required double width,
    required TextScaler textScaler,
  }) {
    _trimTrailingCollapsibleSpace();
    if (!hasContent) return null;

    final children = <TextSpan>[];
    for (final run in _runs) {
      if (run.text.isEmpty) continue;
      children.add(
        TextSpan(
          text: run.text,
          style: run.style.toTextStyle(includeBackground: true),
        ),
      );
    }
    if (children.isEmpty) return null;

    final painter = TextPainter(
      text: TextSpan(
        style: parentStyle.toTextStyle(),
        children: children,
      ),
      textAlign: parentStyle.textAlign,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      locale: const Locale('zh'),
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: width);

    final plainText = painter.text?.toPlainText() ?? '';
    final links = <WeftLinkRegion>[];
    for (final range in _linkRanges()) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      final rects = boxes
          .map((box) {
            return Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
          })
          .where((rect) => rect.width > 0 && rect.height > 0)
          .toList();
      if (rects.isEmpty) continue;
      links.add(
        WeftLinkRegion(
          nodeId: range.nodeId,
          href: range.href,
          text: plainText.substring(range.start, range.end),
          rects: rects,
        ),
      );
    }
    return _InlineLayout(painter: painter, links: links);
  }

  List<_LinkRunRange> _linkRanges() {
    final result = <_LinkRunRange>[];
    var offset = 0;
    for (final run in _runs) {
      if (run.text.isEmpty) continue;
      final href = run.href;
      final nodeId = run.linkNodeId;
      if (href != null && nodeId != null) {
        final end = offset + run.text.length;
        if (result.isNotEmpty &&
            result.last.nodeId == nodeId &&
            result.last.href == href &&
            result.last.end == offset) {
          result.last.end = end;
        } else {
          result.add(
            _LinkRunRange(
              nodeId: nodeId,
              href: href,
              start: offset,
              end: end,
            ),
          );
        }
      }
      offset += run.text.length;
    }
    return result;
  }

  void _trimTrailingCollapsibleSpace() {
    while (_runs.isNotEmpty) {
      final last = _runs.last;
      if (last.style.whiteSpace != WeftWhiteSpace.normal) return;
      final trimmed = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed.isEmpty) {
        _runs.removeLast();
        continue;
      }
      last.text = trimmed;
      return;
    }
  }

  static bool _endsWithSpace(String text) {
    if (text.isEmpty) return false;
    final code = text.codeUnitAt(text.length - 1);
    return code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
  }
}
