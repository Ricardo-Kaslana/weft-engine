import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'layout_result.dart';
import 'style_resolver.dart';
import 'text_index.dart';

part 'inline_flow.part.dart';
part 'table_layout.part.dart';

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
    final textIndex = WeftTextIndex.build(
      document: document,
      styleResolver: context.styleResolver,
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
      textIndex: textIndex,
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

      if (child.tag == 'table') {
        flushInline();
        // Tables are block-level boxes whose inner margins never collapse
        // through the table box, so the table itself is never
        // self-collapsing.
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

        final result = layoutTable(
          element: child,
          style: childStyle,
          availableWidth: contentWidth,
          left: contentX,
          top: cursor,
          ancestors: childAncestors,
        );
        cursor += result.height;
        pendingMargin = outerBottom;
        hasPendingMargin = true;
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
      if (current.tag == 'hr' || current.tag == 'table') break;
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
      if (current.tag == 'hr' || current.tag == 'table') break;
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
    // A table box never collapses through itself.
    if (element.tag == 'table') return false;
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
            runs: inline.runSpecs(line.textStart, line.textEnd),
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
        runs: inline.runSpecs(0, inlineLayout.textEnd),
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
