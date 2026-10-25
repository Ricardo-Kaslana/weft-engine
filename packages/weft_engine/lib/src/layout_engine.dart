import 'dart:math' as math;
import 'dart:ui' as ui;

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
    Map<int, ui.Image> images = const {},
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
      images: images,
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
    final floats = _FloatContext();
    final bodyLayout = context.layoutBlock(
      element: body,
      style: bodyStyle,
      availableWidth: width,
      left: 0,
      top: outerTop,
      ancestors: const [],
      floats: floats,
    );
    final normalBottom = outerTop + bodyLayout.height + outerBottom;

    return WeftLayoutResult(
      size: Size(
        width,
        math.max(normalBottom, floats.maxBottom),
      ),
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
    required this.images,
  });

  final WeftStyleResolver styleResolver;
  final TextScaler textScaler;
  final Map<int, ui.Image> images;
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
    required _FloatContext floats,
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
            floats: floats,
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
    required _FloatContext floats,
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
        floats: floats,
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

      if (child.tag == 'img') {
        final image = images[child.id];
        if (image != null) {
          if (childStyle.float != WeftFloat.none) {
            flushInline();
            _placeFloatImage(
              element: child,
              style: childStyle,
              image: image,
              contentX: contentX,
              contentWidth: contentWidth,
              top: cursor,
              floats: floats,
            );
            continue;
          }

          flushInline();
          final outerTop = childStyle.marginTop;
          final outerBottom = childStyle.marginBottom;
          final gap = leadingCollapses
              ? 0.0
              : hasPendingMargin
                  ? _collapseMargins(pendingMargin, outerTop)
                  : outerTop;
          cursor += gap;
          if (childStyle.clear != WeftClear.none) {
            cursor = math.max(cursor, floats.clearBottom(childStyle.clear));
          }
          pendingMargin = 0;
          hasPendingMargin = false;
          leadingCollapses = false;
          trailingCollapses =
              style.borderBottom.width == 0 && style.paddingBottom == 0;

          final metrics = _layoutImageBlock(
            element: child,
            style: childStyle,
            image: image,
            availableWidth: contentWidth,
            left: contentX,
            top: cursor,
          );
          if (metrics != null) {
            cursor += metrics.boxHeight;
          }
          pendingMargin = outerBottom;
          hasPendingMargin = true;
          continue;
        }

        // Unresolved images participate as alternative text, matching how a
        // browser keeps content meaningful when a resource is unavailable.
        final alt = child.attribute('alt')?.trim() ?? '';
        if (alt.isNotEmpty) {
          inline.addText(
            WeftText(id: child.id, text: alt),
            childStyle,
          );
        }
        continue;
      }

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
      if (childStyle.clear != WeftClear.none) {
        cursor = math.max(cursor, floats.clearBottom(childStyle.clear));
      }
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
        floats: floats,
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

  _ImageBoxMetrics? _imageMetrics({
    required WeftElement element,
    required WeftComputedStyle style,
    required ui.Image image,
    required double availableWidth,
  }) {
    final available = availableWidth - style.marginLeft - style.marginRight;
    if (available <= 0) return null;

    final naturalWidth = image.width.toDouble();
    final naturalHeight = image.height.toDouble();
    if (naturalWidth <= 0 || naturalHeight <= 0) return null;

    final attributeWidth = _attributeLength(element, 'width');
    final attributeHeight = _attributeLength(element, 'height');
    final ratio = attributeWidth != null && attributeHeight != null
        ? attributeWidth / attributeHeight
        : naturalWidth / naturalHeight;

    final chromeWidth = style.horizontalPadding + style.horizontalBorder;
    final chromeHeight = style.verticalPadding + style.verticalBorder;
    final cssWidth = style.width;

    double contentWidth;
    double? explicitHeight;
    if (cssWidth != null) {
      contentWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? cssWidth - chromeWidth
          : cssWidth;
      explicitHeight = attributeHeight;
    } else if (attributeWidth != null && attributeHeight != null) {
      contentWidth = attributeWidth;
      explicitHeight = attributeHeight;
    } else if (attributeWidth != null) {
      contentWidth = attributeWidth;
    } else if (attributeHeight != null) {
      contentWidth = attributeHeight * ratio;
      explicitHeight = attributeHeight;
    } else {
      contentWidth = naturalWidth;
    }
    contentWidth = math.max(0, contentWidth);

    var boxWidth = contentWidth + chromeWidth;
    final maxWidth = style.maxWidth;
    if (maxWidth != null) {
      final limit = style.boxSizing == WeftBoxSizing.borderBox
          ? maxWidth
          : maxWidth + chromeWidth;
      boxWidth = math.min(boxWidth, limit);
    }
    final minWidth = style.minWidth;
    if (minWidth != null) {
      final floor = style.boxSizing == WeftBoxSizing.borderBox
          ? minWidth
          : minWidth + chromeWidth;
      boxWidth = math.max(boxWidth, floor);
    }
    boxWidth = boxWidth
        .clamp(
          math.min(chromeWidth, available),
          available,
        )
        .toDouble();

    contentWidth = math.max(0, boxWidth - chromeWidth);
    final contentHeight = explicitHeight ?? contentWidth / ratio;
    return _ImageBoxMetrics(
      boxWidth: boxWidth,
      boxHeight: contentHeight + chromeHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
  }

  _ImageBoxMetrics? _layoutImageBlock({
    required WeftElement element,
    required WeftComputedStyle style,
    required ui.Image image,
    required double availableWidth,
    required double left,
    required double top,
  }) {
    final metrics = _imageMetrics(
      element: element,
      style: style,
      image: image,
      availableWidth: availableWidth,
    );
    if (metrics == null || metrics.boxWidth <= 0 || metrics.boxHeight <= 0) {
      return null;
    }
    final boxX = left + style.marginLeft;
    _paintImageBox(
      element: element,
      style: style,
      image: image,
      boxX: boxX,
      top: top,
      metrics: metrics,
    );
    return metrics;
  }

  void _placeFloatImage({
    required WeftElement element,
    required WeftComputedStyle style,
    required ui.Image image,
    required double contentX,
    required double contentWidth,
    required double top,
    required _FloatContext floats,
  }) {
    final metrics = _imageMetrics(
      element: element,
      style: style,
      image: image,
      availableWidth: contentWidth,
    );
    if (metrics == null || metrics.boxWidth <= 0 || metrics.boxHeight <= 0) {
      return;
    }
    final side = style.float;
    final outerWidth = style.marginLeft + metrics.boxWidth + style.marginRight;
    if (outerWidth > contentWidth) return;
    final outerHeight =
        style.marginTop + metrics.boxHeight + style.marginBottom;

    var outerTop = math.max(top, floats.clearBottom(style.clear));
    for (var guard = 0; guard < 64; guard++) {
      var shifted = false;
      for (final exclusion in floats.exclusions) {
        final overlapsVertically =
            exclusion.rect.top < outerTop + outerHeight &&
                exclusion.rect.bottom > outerTop;
        if (!overlapsVertically) continue;
        final mustStack = exclusion.side == side ||
            outerWidth + exclusion.rect.width > contentWidth;
        if (mustStack) {
          outerTop = exclusion.rect.bottom;
          shifted = true;
          break;
        }
      }
      if (!shifted) break;
    }

    final boxX = side == WeftFloat.left
        ? contentX + style.marginLeft
        : contentX + contentWidth - style.marginRight - metrics.boxWidth;
    final boxTop = outerTop + style.marginTop;
    _paintImageBox(
      element: element,
      style: style,
      image: image,
      boxX: boxX,
      top: boxTop,
      metrics: metrics,
    );

    final outerLeft =
        side == WeftFloat.left ? contentX : boxX - style.marginLeft;
    final outerRight = side == WeftFloat.left
        ? boxX + metrics.boxWidth + style.marginRight
        : contentX + contentWidth;
    floats.add(
      _FloatExclusion(
        side: side,
        rect: Rect.fromLTRB(
          outerLeft,
          outerTop,
          outerRight,
          outerTop + outerHeight,
        ),
      ),
    );
  }

  void _paintImageBox({
    required WeftElement element,
    required WeftComputedStyle style,
    required ui.Image image,
    required double boxX,
    required double top,
    required _ImageBoxMetrics metrics,
  }) {
    final commandStart = commands.length;
    var insertIndex = commandStart;
    final background = style.backgroundColor;
    if (background != null && background.a > 0) {
      commands.insert(
        insertIndex,
        WeftRectPaintCommand(
          nodeId: element.id,
          rect: Rect.fromLTWH(
            boxX,
            top,
            metrics.boxWidth,
            metrics.boxHeight,
          ),
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
      boxWidth: metrics.boxWidth,
      height: metrics.boxHeight,
    )) {
      commands.insert(insertIndex, command);
      insertIndex += 1;
    }

    final contentX = boxX + style.borderLeft.width + style.paddingLeft;
    final contentY = top + style.borderTop.width + style.paddingTop;
    commands.add(
      WeftImagePaintCommand(
        nodeId: element.id,
        image: image,
        destination: Rect.fromLTWH(
          contentX,
          contentY,
          metrics.contentWidth,
          metrics.contentHeight,
        ),
      ),
    );
    boxes.add(
      WeftLayoutBox(
        nodeId: element.id,
        rect: Rect.fromLTWH(
          boxX,
          top,
          metrics.boxWidth,
          metrics.boxHeight,
        ),
      ),
    );
  }

  static double? _attributeLength(WeftElement element, String name) {
    final value = element.attribute(name);
    if (value == null) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return parsed;
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
        if (style.float != WeftFloat.none) continue;
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
        if (style.float != WeftFloat.none) continue;
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
      if (childStyle.float != WeftFloat.none) {
        // Out-of-flow content still paints even when it adds no block height.
        return false;
      }
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
      if (child.tag == 'img') {
        if (childStyle.float != WeftFloat.none) continue;
        return false;
      }
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
    required _FloatContext floats,
  }) {
    if (width <= 0) return 0;
    if (floats.hasExclusions) {
      final lines = inline.buildLines(
        parentStyle: parentStyle,
        left: x,
        right: x + width,
        top: y,
        textScaler: textScaler,
        floats: floats,
      );
      if (lines == null) return 0;
      for (final line in lines.lines) {
        commands.add(
          WeftTextPaintCommand(
            nodeId: parentNodeId,
            painter: line.painter,
            offset: Offset(line.x, line.y),
          ),
        );
      }
      links.addAll(lines.links);
      return math.max(0, lines.bottom - y);
    }

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

final class _ImageBoxMetrics {
  const _ImageBoxMetrics({
    required this.boxWidth,
    required this.boxHeight,
    required this.contentWidth,
    required this.contentHeight,
  });

  final double boxWidth;
  final double boxHeight;
  final double contentWidth;
  final double contentHeight;
}

final class _FloatExclusion {
  const _FloatExclusion({required this.side, required this.rect});

  final WeftFloat side;
  final Rect rect;
}

final class _LineSlot {
  const _LineSlot({
    required this.top,
    required this.left,
    required this.right,
  });

  final double top;
  final double left;
  final double right;
}

final class _FloatContext {
  final List<_FloatExclusion> exclusions = <_FloatExclusion>[];

  bool get hasExclusions => exclusions.isNotEmpty;

  double get maxBottom {
    var bottom = 0.0;
    for (final exclusion in exclusions) {
      bottom = math.max(bottom, exclusion.rect.bottom);
    }
    return bottom;
  }

  void add(_FloatExclusion exclusion) {
    exclusions.add(exclusion);
  }

  double clearBottom(WeftClear clear) {
    if (clear == WeftClear.none) return double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final exclusion in exclusions) {
      final matches = switch (clear) {
        WeftClear.left => exclusion.side == WeftFloat.left,
        WeftClear.right => exclusion.side == WeftFloat.right,
        WeftClear.both => true,
        WeftClear.none => false,
      };
      if (matches) bottom = math.max(bottom, exclusion.rect.bottom);
    }
    return bottom;
  }

  double? nextBottomAfter(double y, {double lineHeight = 0}) {
    double? next;
    for (final exclusion in exclusions) {
      if (exclusion.rect.bottom <= y) continue;
      if (lineHeight > 0 && exclusion.rect.top >= y + lineHeight) continue;
      next = next == null
          ? exclusion.rect.bottom
          : math.min(next, exclusion.rect.bottom);
    }
    return next;
  }

  _LineSlot lineSlot({
    required double left,
    required double right,
    required double top,
    required double lineHeight,
  }) {
    var current = top;
    for (var guard = 0; guard < 64; guard++) {
      var availableLeft = left;
      var availableRight = right;
      for (final exclusion in exclusions) {
        final overlaps = exclusion.rect.top < current + lineHeight &&
            exclusion.rect.bottom > current;
        if (!overlaps) continue;
        if (exclusion.side == WeftFloat.left) {
          availableLeft = math.max(availableLeft, exclusion.rect.right);
        } else {
          availableRight = math.min(availableRight, exclusion.rect.left);
        }
      }
      if (availableRight - availableLeft > 1) {
        return _LineSlot(
          top: current,
          left: availableLeft,
          right: availableRight,
        );
      }
      final next = nextBottomAfter(current, lineHeight: lineHeight);
      if (next == null || next <= current) break;
      current = next;
    }
    return _LineSlot(top: current, left: left, right: right);
  }
}

final class _InlineLine {
  const _InlineLine({
    required this.x,
    required this.y,
    required this.painter,
  });

  final double x;
  final double y;
  final TextPainter painter;
}

final class _InlineLines {
  const _InlineLines({
    required this.lines,
    required this.links,
    required this.bottom,
  });

  final List<_InlineLine> lines;
  final List<WeftLinkRegion> links;
  final double bottom;
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
    if (element.tag == 'img') {
      final alt = element.attribute('alt')?.trim() ?? '';
      if (context.images[element.id] == null && alt.isNotEmpty) {
        addText(
          WeftText(id: element.id, text: alt),
          style,
          link: link,
        );
      }
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

  _InlineLines? buildLines({
    required WeftComputedStyle parentStyle,
    required double left,
    required double right,
    required double top,
    required TextScaler textScaler,
    required _FloatContext floats,
  }) {
    _trimTrailingCollapsibleSpace();
    if (!hasContent || right <= left) return null;

    final plainText = _runs.map((run) => run.text).join();
    if (plainText.isEmpty) return null;
    final linkRanges = _linkRanges();
    final linkHrefs = <int, String>{};
    final linkTexts = <int, String>{};
    final linkRects = <int, List<Rect>>{};
    for (final range in linkRanges) {
      linkHrefs[range.nodeId] = range.href;
      linkTexts[range.nodeId] = plainText.substring(range.start, range.end);
    }

    final lines = <_InlineLine>[];
    var offset = 0;
    var y = top;
    for (var guard = 0; guard < 10000 && offset < plainText.length; guard++) {
      if (parentStyle.whiteSpace == WeftWhiteSpace.normal) {
        while (offset < plainText.length &&
            _isCollapsibleSpace(plainText.codeUnitAt(offset))) {
          offset++;
        }
        if (offset >= plainText.length) break;
      }

      final estimate = parentStyle.fontSize * parentStyle.lineHeight;
      final slot = floats.lineSlot(
        left: left,
        right: right,
        top: y,
        lineHeight: estimate,
      );
      y = slot.top;
      final lineWidth = slot.right - slot.left;
      if (lineWidth <= 1) {
        final next = floats.nextBottomAfter(y, lineHeight: estimate);
        if (next == null) break;
        y = next;
        continue;
      }

      final probe = TextPainter(
        text: _spanForRange(offset, plainText.length, parentStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        locale: const Locale('zh'),
        maxLines: 1,
        textWidthBasis: TextWidthBasis.parent,
      )..layout(maxWidth: lineWidth);
      final metrics = probe.computeLineMetrics();
      if (metrics.isEmpty) {
        probe.dispose();
        break;
      }
      final lineMetrics = metrics.first;
      var consumed =
          _lineBreakEnd(probe, offset, plainText.length, lineMetrics);
      probe.dispose();
      if (consumed <= offset) {
        consumed = offset + _nextCodeUnitLength(plainText, offset);
      }
      if (consumed < plainText.length &&
          plainText.codeUnitAt(consumed) == 0x0A &&
          consumed > offset) {
        consumed += 1;
      }

      final paintEnd = _paintableEnd(
        plainText,
        offset,
        math.min(consumed, plainText.length),
        parentStyle.whiteSpace,
      );
      if (paintEnd > offset) {
        final painter = _buildLinePainter(
          offset,
          paintEnd,
          parentStyle,
          lineWidth,
          textScaler,
        );
        lines.add(_InlineLine(x: slot.left, y: y, painter: painter));
        for (final range in linkRanges) {
          final start = math.max(offset, range.start);
          final end = math.min(paintEnd, range.end);
          if (end <= start) continue;
          final boxes = painter.getBoxesForSelection(
            TextSelection(
              baseOffset: start - offset,
              extentOffset: end - offset,
            ),
          );
          final target = linkRects.putIfAbsent(range.nodeId, () => <Rect>[]);
          for (final box in boxes) {
            final rect = Rect.fromLTRB(
              box.left + slot.left,
              box.top + y,
              box.right + slot.left,
              box.bottom + y,
            );
            if (rect.width > 0 && rect.height > 0) target.add(rect);
          }
        }
        y += painter.height;
      } else {
        // A hard line break still occupies one line box.
        y += lineMetrics.height;
      }
      offset = consumed;
    }

    if (lines.isEmpty) return null;
    final links = <WeftLinkRegion>[];
    for (final entry in linkRects.entries) {
      final href = linkHrefs[entry.key];
      final text = linkTexts[entry.key];
      if (href == null || text == null || entry.value.isEmpty) continue;
      links.add(
        WeftLinkRegion(
          nodeId: entry.key,
          href: href,
          text: text,
          rects: entry.value,
        ),
      );
    }
    return _InlineLines(lines: lines, links: links, bottom: y);
  }

  TextSpan _spanForRange(
    int start,
    int end,
    WeftComputedStyle parentStyle,
  ) {
    final children = <TextSpan>[];
    var cursor = 0;
    for (final run in _runs) {
      final runStart = cursor;
      final runEnd = cursor + run.text.length;
      cursor = runEnd;
      if (runEnd <= start || runStart >= end) continue;
      final localStart = math.max(start, runStart) - runStart;
      final localEnd = math.min(end, runEnd) - runStart;
      if (localEnd <= localStart) continue;
      children.add(
        TextSpan(
          text: run.text.substring(localStart, localEnd),
          style: run.style.toTextStyle(includeBackground: true),
        ),
      );
    }
    return TextSpan(
      style: parentStyle.toTextStyle(),
      children: children,
    );
  }

  TextPainter _buildLinePainter(
    int start,
    int end,
    WeftComputedStyle parentStyle,
    double width,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: _spanForRange(start, end, parentStyle),
      textAlign: parentStyle.textAlign,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      locale: const Locale('zh'),
      maxLines: 1,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(minWidth: width, maxWidth: width);
    return painter;
  }

  static int _lineBreakEnd(
    TextPainter probe,
    int offset,
    int total,
    ui.LineMetrics metrics,
  ) {
    final caretX = metrics.width <= 0 ? 0.0 : metrics.width;
    final caretY = metrics.baseline - metrics.ascent + metrics.height / 2;
    final position = probe.getPositionForOffset(Offset(caretX, caretY));
    final boundary = probe.getLineBoundary(position);
    if (boundary.end > boundary.start) return offset + boundary.end;
    return offset + position.offset;
  }

  static int _paintableEnd(
    String text,
    int start,
    int end,
    WeftWhiteSpace whiteSpace,
  ) {
    var result = end;
    if (result > start && text.codeUnitAt(result - 1) == 0x0A) result--;
    if (whiteSpace == WeftWhiteSpace.normal) {
      while (
          result > start && _isCollapsibleSpace(text.codeUnitAt(result - 1))) {
        result--;
      }
    }
    return result;
  }

  static int _nextCodeUnitLength(String text, int offset) {
    if (offset >= text.length) return 1;
    final code = text.codeUnitAt(offset);
    final isHighSurrogate = code >= 0xD800 && code <= 0xDBFF;
    return isHighSurrogate && offset + 1 < text.length ? 2 : 1;
  }

  static bool _isCollapsibleSpace(int code) {
    return code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
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
