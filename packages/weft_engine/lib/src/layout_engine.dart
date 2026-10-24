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
    // Margins of the body's first/last block descendants collapse through the
    // body's own margins. They sit outside its border box, so they must be
    // measured before the box is placed and added to the document extent.
    final outerTop = context.outerMarginTop(body, bodyStyle, const []);
    final outerBottom = context.outerMarginBottom(body, bodyStyle, const []);
    final bodyLayout = context.layoutBlock(
      element: body,
      style: bodyStyle,
      availableWidth: width,
      left: 0,
      top: outerTop,
      ancestors: const [],
    );

    return WeftLayoutResult(
      size: Size(width, outerTop + bodyLayout.height + outerBottom),
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
      return const _BlockLayout(height: 0);
    }

    final boxX = left + style.marginLeft;
    final availableBoxWidth = math.max(
      0.0,
      availableWidth - style.marginLeft - style.marginRight,
    );
    final horizontalChrome = style.horizontalPadding + style.horizontalBorder;
    final boxWidth = _resolveBoxWidth(
      style: style,
      availableWidth: availableBoxWidth,
      horizontalChrome: horizontalChrome,
    );
    final contentX = boxX + style.borderLeft.width + style.paddingLeft;
    final contentY = top + style.borderTop.width + style.paddingTop;
    final contentWidth = math.max(0.0, boxWidth - horizontalChrome);
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
    final height = style.verticalBorder + style.verticalPadding + contentHeight;

    var insertIndex = commandStart;
    final background = style.backgroundColor;
    if (background != null && background.a > 0) {
      commands.insert(
        insertIndex,
        WeftRectPaintCommand(
          nodeId: element.id,
          rect: Rect.fromLTWH(boxX, top, boxWidth, height),
          color: background,
        ),
      );
      insertIndex += 1;
    }

    for (final command in _borderCommands(
      nodeId: element.id,
      style: style,
      boxX: boxX,
      top: top,
      boxWidth: boxWidth,
      height: height,
    )) {
      commands.insert(insertIndex, command);
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

    if (boxWidth > 0 && height > 0) {
      boxes.add(
        WeftLayoutBox(
          nodeId: element.id,
          rect: Rect.fromLTWH(boxX, top, boxWidth, height),
        ),
      );
    }

    return _BlockLayout(height: height);
  }

  double _resolveBoxWidth({
    required WeftComputedStyle style,
    required double availableWidth,
    required double horizontalChrome,
  }) {
    var boxWidth = style.width == null
        ? availableWidth
        : style.boxSizing == WeftBoxSizing.borderBox
            ? style.width!
            : style.width! + horizontalChrome;
    boxWidth = math.min(boxWidth, availableWidth);

    final maxWidth = style.maxWidth;
    if (maxWidth != null) {
      final maxBoxWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? maxWidth
          : maxWidth + horizontalChrome;
      boxWidth = math.min(boxWidth, maxBoxWidth);
    }
    final minWidth = style.minWidth;
    if (minWidth != null) {
      final minBoxWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? minWidth
          : minWidth + horizontalChrome;
      boxWidth = math.max(boxWidth, minBoxWidth);
    }

    boxWidth = boxWidth.clamp(0.0, availableWidth).toDouble();
    return math.max(boxWidth, math.min(horizontalChrome, availableWidth));
  }

  Iterable<WeftRectPaintCommand> _borderCommands({
    required int nodeId,
    required WeftComputedStyle style,
    required double boxX,
    required double top,
    required double boxWidth,
    required double height,
  }) sync* {
    final topSide = style.borderTop;
    final rightSide = style.borderRight;
    final bottomSide = style.borderBottom;
    final leftSide = style.borderLeft;
    if (topSide.isVisible) {
      yield WeftRectPaintCommand(
        nodeId: nodeId,
        rect: Rect.fromLTWH(boxX, top, boxWidth, topSide.width),
        color: topSide.color,
      );
    }
    if (rightSide.isVisible) {
      yield WeftRectPaintCommand(
        nodeId: nodeId,
        rect: Rect.fromLTWH(
          boxX + boxWidth - rightSide.width,
          top,
          rightSide.width,
          height,
        ),
        color: rightSide.color,
      );
    }
    if (bottomSide.isVisible) {
      yield WeftRectPaintCommand(
        nodeId: nodeId,
        rect: Rect.fromLTWH(
          boxX,
          top + height - bottomSide.width,
          boxWidth,
          bottomSide.width,
        ),
        color: bottomSide.color,
      );
    }
    if (leftSide.isVisible) {
      yield WeftRectPaintCommand(
        nodeId: nodeId,
        rect: Rect.fromLTWH(boxX, top, leftSide.width, height),
        color: leftSide.color,
      );
    }
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
    var hasPendingMargin = false;
    // A block with no top border or padding lets its first in-flow block
    // child's top margin collapse into its own outer margin.
    var leadingCollapses = style.borderTop.width == 0 && style.paddingTop == 0;
    var trailingCollapses =
        style.borderBottom.width == 0 && style.paddingBottom == 0;
    var orderedItem = 0;
    final inline = _InlineAccumulator(this);

    double flushInline() {
      if (!inline.hasContent) return 0;
      if (hasPendingMargin) {
        // A margin accumulated before inline content cannot collapse with it.
        // When the margin still belongs to the leading edge, the outer margin
        // already includes it, so it must not be applied twice.
        if (!leadingCollapses) cursor += pendingMargin;
        pendingMargin = 0;
        hasPendingMargin = false;
      }
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
      leadingCollapses = false;
      trailingCollapses = false;
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

      final outerTop = outerMarginTop(child, childStyle, childAncestors);
      final outerBottom = outerMarginBottom(child, childStyle, childAncestors);
      final selfCollapsing = _isSelfCollapsing(
        child,
        childStyle,
        childAncestors,
      );

      if (selfCollapsing) {
        // Collapse-through blocks have no border box to place. Their margins
        // merge with the surrounding margins instead of advancing the cursor.
        pendingMargin = hasPendingMargin
            ? _collapseMargins(pendingMargin, outerTop, outerBottom)
            : _collapseMargins(outerTop, outerBottom);
        hasPendingMargin = true;
        // Leading fold-through is only applied when the outer margin chain
        // accounted for the empty child; keep later content positioned by the
        // accumulated margin instead.
        leadingCollapses = false;
        trailingCollapses = false;
        continue;
      }

      final gap = leadingCollapses
          ? 0.0
          : hasPendingMargin
              ? _collapseMargins(pendingMargin, outerTop)
              : outerTop;
      cursor += gap;
      pendingMargin = 0;
      hasPendingMargin = false;
      leadingCollapses = false;
      trailingCollapses =
          style.borderBottom.width == 0 && style.paddingBottom == 0;

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
      pendingMargin = outerBottom;
      hasPendingMargin = true;
    }

    flushInline();
    if (hasPendingMargin && !trailingCollapses) {
      cursor += pendingMargin;
    }
    return math.max(0, cursor - contentY);
  }

  /// Collapses margins following CSS 2.1: the largest positive margin plus the
  /// smallest negative margin. Adjacent margins never sum.
  double _collapseMargins(double first, [double? second, double? third]) {
    var positive = math.max(0.0, first);
    var negative = math.min(0.0, first);
    for (final margin in <double?>[second, third]) {
      if (margin == null) continue;
      positive = math.max(positive, math.max(0.0, margin));
      negative = math.min(negative, math.min(0.0, margin));
    }
    return positive + negative;
  }

  /// The top margin that ends up outside [element]'s border box, following the
  /// first in-flow block child chain while no top border or padding blocks it.
  double outerMarginTop(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors,
  ) {
    var margin = style.marginTop;
    var current = element;
    var currentStyle = style;
    var currentAncestors = ancestors;
    for (var depth = 0; depth < 32; depth++) {
      if (currentStyle.borderTop.width > 0 || currentStyle.paddingTop > 0) {
        break;
      }
      if (current.tag == 'hr') break;
      final edge = _firstBlockChild(current, currentStyle, currentAncestors);
      if (edge == null) break;
      if (_isSelfCollapsing(edge.element, edge.style, edge.ancestors)) {
        // Treat empty children as ordinary in-flow space so leading margins of
        // later siblings are not counted twice.
        break;
      }
      margin = _collapseMargins(margin, edge.style.marginTop);
      current = edge.element;
      currentStyle = edge.style;
      currentAncestors = edge.ancestors;
    }
    return margin;
  }

  /// The bottom margin that ends up outside [element]'s border box.
  double outerMarginBottom(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors,
  ) {
    var margin = style.marginBottom;
    var current = element;
    var currentStyle = style;
    var currentAncestors = ancestors;
    for (var depth = 0; depth < 32; depth++) {
      if (currentStyle.borderBottom.width > 0 ||
          currentStyle.paddingBottom > 0) {
        break;
      }
      if (current.tag == 'hr') break;
      final edge = _lastBlockChild(current, currentStyle, currentAncestors);
      if (edge == null) break;
      if (_isSelfCollapsing(edge.element, edge.style, edge.ancestors)) break;
      margin = _collapseMargins(margin, edge.style.marginBottom);
      current = edge.element;
      currentStyle = edge.style;
      currentAncestors = edge.ancestors;
    }
    return margin;
  }

  _FlowEdge? _firstBlockChild(
    WeftElement parent,
    WeftComputedStyle parentStyle,
    List<WeftElement> ancestors,
  ) {
    final childAncestors = <WeftElement>[...ancestors, parent];
    for (final child in parent.children) {
      if (child is WeftText) {
        if (_isBlankText(child.text, parentStyle.whiteSpace)) continue;
        return null;
      }
      if (child is! WeftElement) continue;
      final style = styleResolver.resolve(
        child,
        parent: parentStyle,
        ancestors: childAncestors,
      );
      if (style.display == WeftDisplay.none) continue;
      if (style.display == WeftDisplay.inline) {
        if (_isInlineEmpty(child, style, childAncestors)) continue;
        return null;
      }
      return _FlowEdge(child, style, childAncestors);
    }
    return null;
  }

  _FlowEdge? _lastBlockChild(
    WeftElement parent,
    WeftComputedStyle parentStyle,
    List<WeftElement> ancestors,
  ) {
    final childAncestors = <WeftElement>[...ancestors, parent];
    for (final child in parent.children.reversed) {
      if (child is WeftText) {
        if (_isBlankText(child.text, parentStyle.whiteSpace)) continue;
        return null;
      }
      if (child is! WeftElement) continue;
      final style = styleResolver.resolve(
        child,
        parent: parentStyle,
        ancestors: childAncestors,
      );
      if (style.display == WeftDisplay.none) continue;
      if (style.display == WeftDisplay.inline) {
        if (_isInlineEmpty(child, style, childAncestors)) continue;
        return null;
      }
      return _FlowEdge(child, style, childAncestors);
    }
    return null;
  }

  /// A block with no border, padding or visible content collapses its own top
  /// and bottom margins together and contributes no height.
  bool _isSelfCollapsing(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors, [
    int depth = 0,
  ]) {
    if (depth > 32) return false;
    if (style.borderTop.width > 0 ||
        style.borderBottom.width > 0 ||
        style.paddingTop > 0 ||
        style.paddingBottom > 0) {
      return false;
    }
    if (element.tag == 'hr') return false;
    // An empty list item still renders a marker, so it must be laid out.
    if (style.display == WeftDisplay.listItem) return false;
    final childAncestors = <WeftElement>[...ancestors, element];
    for (final child in element.children) {
      if (child is WeftText) {
        if (!_isBlankText(child.text, style.whiteSpace)) return false;
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
        if (!_isInlineEmpty(child, childStyle, childAncestors)) return false;
        continue;
      }
      if (!_isSelfCollapsing(
        child,
        childStyle,
        childAncestors,
        depth + 1,
      )) {
        return false;
      }
    }
    return true;
  }

  bool _isInlineEmpty(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors,
  ) {
    final childAncestors = <WeftElement>[...ancestors, element];
    for (final child in element.children) {
      if (child is WeftText) {
        if (!_isBlankText(child.text, style.whiteSpace)) return false;
        continue;
      }
      if (child is! WeftElement) continue;
      if (child.tag == 'br') return false;
      final childStyle = styleResolver.resolve(
        child,
        parent: style,
        ancestors: childAncestors,
      );
      if (childStyle.display == WeftDisplay.none) continue;
      if (!_isInlineEmpty(child, childStyle, childAncestors)) return false;
    }
    return true;
  }

  static bool _isBlankText(String text, WeftWhiteSpace whiteSpace) {
    if (text.isEmpty) return true;
    if (whiteSpace == WeftWhiteSpace.normal) return text.trim().isEmpty;
    return false;
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
  const _BlockLayout({required this.height});

  final double height;
}

final class _FlowEdge {
  const _FlowEdge(this.element, this.style, this.ancestors);

  final WeftElement element;
  final WeftComputedStyle style;
  final List<WeftElement> ancestors;
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
