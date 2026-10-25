import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'layout_result.dart';
import 'style_resolver.dart';
import 'text_index.dart';

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

  _BlockLayout layoutTable({
    required WeftElement element,
    required WeftComputedStyle style,
    required double availableWidth,
    required double left,
    required double top,
    required List<WeftElement> ancestors,
  }) {
    final collapse = style.borderCollapse == WeftBorderCollapse.collapse;
    final spacingH =
        collapse ? 0.0 : math.max(0.0, style.borderSpacingHorizontal);
    final spacingV =
        collapse ? 0.0 : math.max(0.0, style.borderSpacingVertical);
    final commandStart = commands.length;
    final tableAncestors = <WeftElement>[...ancestors, element];

    // ---- Collect the caption and the row/cell structure.
    WeftElement? caption;
    final rowElements = <WeftElement>[];
    final rowAncestorChains = <List<WeftElement>>[];
    void collectRows(WeftElement parent, List<WeftElement> chain) {
      for (final child in parent.children) {
        if (child is! WeftElement) continue;
        switch (child.tag) {
          case 'caption':
            caption ??= child;
          case 'tr':
            rowElements.add(child);
            rowAncestorChains.add(<WeftElement>[...chain, child]);
          case 'thead':
          case 'tbody':
          case 'tfoot':
            collectRows(child, <WeftElement>[...chain, child]);
        }
      }
    }

    collectRows(element, tableAncestors);

    // ---- Place cells into the slot grid, honouring colspan/rowspan.
    final cells = <_TableCell>[];
    final occupied = <int, Set<int>>{};
    var columnCount = 0;
    for (var row = 0; row < rowElements.length; row++) {
      final tr = rowElements[row];
      final cellAncestors = rowAncestorChains[row];
      var column = 0;
      for (final child in tr.children) {
        if (child is! WeftElement) continue;
        if (child.tag != 'td' && child.tag != 'th') continue;
        final cellStyle = styleResolver.resolve(
          child,
          parent: style,
          ancestors: cellAncestors,
        );
        if (cellStyle.display == WeftDisplay.none) continue;
        while ((occupied[row] ?? const <int>{}).contains(column)) {
          column += 1;
        }
        final cell = _TableCell(
          element: child,
          style: cellStyle,
          ancestors: cellAncestors,
          row: row,
          column: column,
          rowSpan: _spanAttribute(child, 'rowspan'),
          columnSpan: _spanAttribute(child, 'colspan'),
        );
        cells.add(cell);
        for (var spanRow = 0; spanRow < cell.rowSpan; spanRow++) {
          final rowSlots = occupied.putIfAbsent(
            row + spanRow,
            () => <int>{},
          );
          for (var spanColumn = 0; spanColumn < cell.columnSpan; spanColumn++) {
            rowSlots.add(column + spanColumn);
          }
        }
        columnCount = math.max(columnCount, column + cell.columnSpan);
        column += cell.columnSpan;
      }
    }
    var rowCount = rowElements.length;
    for (final cell in cells) {
      rowCount = math.max(rowCount, cell.row + cell.rowSpan);
    }

    final boxX = left + style.marginLeft;
    final availableBoxWidth = math.max(
      0.0,
      availableWidth - style.marginLeft - style.marginRight,
    );
    final tableChromeH = style.horizontalPadding + style.horizontalBorder;

    if (cells.isEmpty || columnCount == 0 || rowCount == 0) {
      var contentHeight = 0.0;
      final captionElement = caption;
      if (captionElement != null) {
        final captionStyle = styleResolver.resolve(
          captionElement,
          parent: style,
          ancestors: tableAncestors,
        );
        if (captionStyle.display != WeftDisplay.none) {
          contentHeight = _layoutCaption(
            element: captionElement,
            style: captionStyle,
            availableWidth: math.max(
              0,
              availableBoxWidth - tableChromeH,
            ),
            left: boxX + style.borderLeft.width + style.paddingLeft,
            top: top + style.borderTop.width + style.paddingTop,
            ancestors: tableAncestors,
          );
        }
      }
      final height =
          style.verticalBorder + style.verticalPadding + contentHeight;
      _paintTableChrome(
        element: element,
        style: style,
        boxX: boxX,
        top: top,
        boxWidth: math.min(availableBoxWidth, tableChromeH),
        height: height,
        commandStart: commandStart,
      );
      return _BlockLayout(height: height);
    }

    // ---- Collapsed edges are decided by cell styles alone (CSS 2.1 §17.6.2).
    final verticalEdges = List<WeftBorderSide>.filled(
      columnCount + 1,
      WeftBorderSide.none,
    );
    final horizontalEdges = List<WeftBorderSide>.filled(
      rowCount + 1,
      WeftBorderSide.none,
    );
    if (collapse) {
      // Table borders lose to cell borders at equal widths, so seed them
      // first and let cells override with >= comparisons.
      verticalEdges[0] = style.borderLeft;
      verticalEdges[columnCount] = style.borderRight;
      horizontalEdges[0] = style.borderTop;
      horizontalEdges[rowCount] = style.borderBottom;
      for (final cell in cells) {
        final cellStyle = cell.style;
        if (cellStyle.borderRight.width >=
            verticalEdges[cell.column + cell.columnSpan].width) {
          verticalEdges[cell.column + cell.columnSpan] = cellStyle.borderRight;
        }
        if (cellStyle.borderLeft.width >= verticalEdges[cell.column].width) {
          verticalEdges[cell.column] = cellStyle.borderLeft;
        }
        if (cellStyle.borderBottom.width >=
            horizontalEdges[cell.row + cell.rowSpan].width) {
          horizontalEdges[cell.row + cell.rowSpan] = cellStyle.borderBottom;
        }
        if (cellStyle.borderTop.width >= horizontalEdges[cell.row].width) {
          horizontalEdges[cell.row] = cellStyle.borderTop;
        }
      }
    }
    final outerEdges = collapse
        ? (verticalEdges[0].width + verticalEdges[columnCount].width) / 2
        : 0.0;

    // ---- Pass 1: intrinsic widths per column. Column intrinsics carry
    // content plus padding (and the cell's own borders in the separate
    // model); collapsed edges are accounted by the grid arithmetic instead.
    final columnMin = List<double>.filled(columnCount, 0);
    final columnMax = List<double>.filled(columnCount, 0);
    for (final cell in cells) {
      final sizes = _measureCellContent(cell, collapse: collapse);
      cell.minWidth = sizes.min;
      cell.maxWidth = sizes.max;
      if (cell.columnSpan == 1) {
        columnMin[cell.column] = math.max(columnMin[cell.column], sizes.min);
        columnMax[cell.column] = math.max(columnMax[cell.column], sizes.max);
      }
    }
    for (final cell in cells) {
      if (cell.columnSpan == 1) continue;
      _distributeSpanWidth(
        columnMin,
        cell.column,
        cell.columnSpan,
        cell.minWidth - spacingH * (cell.columnSpan - 1),
      );
      _distributeSpanWidth(
        columnMax,
        cell.column,
        cell.columnSpan,
        cell.maxWidth - spacingH * (cell.columnSpan - 1),
      );
    }

    // The full table border-box width covers the content plus every edge:
    // interior edges once, outer edges fully, plus the cell gutters. In the
    // separate model the spacing also pads the table edges.
    final spacingTotal = spacingH * (columnCount + 1);
    final allEdgesTotal = collapse
        ? _sum([
            for (var column = 0; column <= columnCount; column++)
              verticalEdges[column].width,
          ])
        : 0.0;
    final contentSumMin = _sum(columnMin);
    final contentSumMax = _sum(columnMax);
    final tableSumMin = contentSumMin + spacingTotal + allEdgesTotal;
    final tableSumMax = contentSumMax + spacingTotal + allEdgesTotal;

    // ---- Resolve the table grid width.
    double gridWidth;
    if (style.width != null) {
      final boxWidth = _resolveBoxWidth(
        style: style,
        availableWidth: availableBoxWidth,
        horizontalChrome: tableChromeH,
      );
      gridWidth = math.max(0, boxWidth - tableChromeH);
    } else {
      final availableGrid = math.max(0.0, availableBoxWidth - tableChromeH);
      gridWidth = math.min(tableSumMax, availableGrid);
      gridWidth = math.max(gridWidth, math.min(tableSumMin, availableGrid));
    }

    final contentWidths = List<double>.filled(columnCount, 0);
    final columnsBudget = math.max(
      0,
      gridWidth - spacingTotal - allEdgesTotal,
    );
    if (columnsBudget >= contentSumMax) {
      final extra = columnsBudget - contentSumMax;
      final totalMax = _sum(columnMax);
      for (var column = 0; column < columnCount; column++) {
        final share = totalMax > 0
            ? extra * columnMax[column] / totalMax
            : extra / columnCount;
        contentWidths[column] = columnMax[column] + share;
      }
    } else if (columnsBudget >= contentSumMin) {
      final extra = columnsBudget - contentSumMin;
      final totalMax = _sum(columnMax);
      for (var column = 0; column < columnCount; column++) {
        final share = totalMax > 0
            ? extra * columnMax[column] / totalMax
            : extra / columnCount;
        contentWidths[column] = columnMin[column] + share;
      }
    } else {
      final totalMin = contentSumMin;
      final scale = totalMin > 0 ? columnsBudget / totalMin : 1.0;
      for (var column = 0; column < columnCount; column++) {
        contentWidths[column] = columnMin[column] * scale;
      }
    }

    // Distances between edge centre lines (or plain widths when separate).
    final columnWidths = List<double>.filled(columnCount, 0);
    for (var column = 0; column < columnCount; column++) {
      final halfEdges = collapse
          ? (verticalEdges[column].width + verticalEdges[column + 1].width) / 2
          : 0.0;
      columnWidths[column] = contentWidths[column] + halfEdges;
    }

    final gridContentWidth = _sum(columnWidths) + spacingTotal;
    final boxWidth = math.min(
      availableBoxWidth,
      gridContentWidth + outerEdges + tableChromeH,
    );

    // ---- Caption above the grid.
    var contentTop = top + style.borderTop.width + style.paddingTop;
    var captionHeight = 0.0;
    final captionElement = caption;
    if (captionElement != null) {
      final captionStyle = styleResolver.resolve(
        captionElement,
        parent: style,
        ancestors: tableAncestors,
      );
      if (captionStyle.display != WeftDisplay.none) {
        captionHeight = _layoutCaption(
          element: captionElement,
          style: captionStyle,
          availableWidth: boxWidth - tableChromeH,
          left: boxX + style.borderLeft.width + style.paddingLeft,
          top: contentTop,
          ancestors: tableAncestors,
        );
        contentTop += captionHeight;
      }
    }

    // ---- Pass 2: lay every cell out at the origin and record its extent.
    final rowHeights = List<double>.filled(rowCount, 0);
    for (final cell in cells) {
      final cellStyle = cell.style;
      double borderBoxWidth;
      double? paddingLeft;
      double? paddingRight;
      if (collapse) {
        // The cell box spans from one edge centerline to the next. Column
        // widths already carry cell padding, so only the shared half edges
        // are added; they become synthetic padding so content stays clear of
        // borders while the background extends beneath them, like a browser.
        final edgeLeft = verticalEdges[cell.column].width;
        final edgeRight = verticalEdges[cell.column + cell.columnSpan].width;
        borderBoxWidth = _sum(
              contentWidths.sublist(
                cell.column,
                cell.column + cell.columnSpan,
              ),
            ) +
            (edgeLeft + edgeRight) / 2;
        paddingLeft = cellStyle.paddingLeft + edgeLeft / 2;
        paddingRight = cellStyle.paddingRight + edgeRight / 2;
      } else {
        borderBoxWidth = _sum(
              columnWidths.sublist(
                cell.column,
                cell.column + cell.columnSpan,
              ),
            ) +
            spacingH * (cell.columnSpan - 1);
      }
      double? paddingTop;
      double? paddingBottom;
      if (collapse) {
        paddingTop = cellStyle.paddingTop + horizontalEdges[cell.row].width / 2;
        paddingBottom = cellStyle.paddingBottom +
            horizontalEdges[cell.row + cell.rowSpan].width / 2;
      }
      cell.boxWidth = borderBoxWidth;
      final synthesized = _cellLayoutStyle(
        cellStyle,
        borderBoxWidth,
        stripBorders: collapse,
        paddingLeft: paddingLeft,
        paddingRight: paddingRight,
        paddingTop: paddingTop,
        paddingBottom: paddingBottom,
      );
      cell.commandStart = commands.length;
      cell.boxStart = boxes.length;
      cell.linkStart = links.length;
      final result = layoutBlock(
        element: cell.element,
        style: synthesized,
        availableWidth: borderBoxWidth,
        left: 0,
        top: 0,
        ancestors: cell.ancestors,
        floats: _FloatContext(),
      );
      cell.commandEnd = commands.length;
      cell.boxEnd = boxes.length;
      cell.linkEnd = links.length;
      cell.height = result.height;
      if (cell.rowSpan == 1) {
        // In the collapsed model the synthesized padding already carries the
        // half edges, so the border-box height is the centerline distance.
        rowHeights[cell.row] = math.max(
          rowHeights[cell.row],
          result.height,
        );
      }
    }
    // Spanning cells grow their final spanned row when they do not fit.
    final spanning = cells.where((cell) => cell.rowSpan > 1).toList()
      ..sort((a, b) => a.row.compareTo(b.row));
    for (final cell in spanning) {
      var allocated = 0.0;
      for (var row = cell.row; row < cell.row + cell.rowSpan; row++) {
        allocated += rowHeights[row];
      }
      if (!collapse) {
        allocated += spacingV * (cell.rowSpan - 1);
      }
      if (cell.height > allocated) {
        rowHeights[cell.row + cell.rowSpan - 1] += cell.height - allocated;
      }
    }

    // ---- Shift every cell into its grid slot.
    final columnX = List<double>.filled(columnCount + 1, 0);
    final rowY = List<double>.filled(rowCount + 1, 0);
    // In the separate model the spacing also separates the cells from the
    // table edges. In the collapsed model cells start at the first edge
    // centerline.
    columnX[0] = spacingH + (collapse ? verticalEdges[0].width / 2 : 0);
    rowY[0] =
        contentTop + spacingV + (collapse ? horizontalEdges[0].width / 2 : 0);
    for (var column = 0; column < columnCount; column++) {
      columnX[column + 1] = columnX[column] + columnWidths[column] + spacingH;
    }
    for (var row = 0; row < rowCount; row++) {
      rowY[row + 1] = rowY[row] + rowHeights[row] + spacingV;
    }
    final gridTop =
        rowY[0] - spacingV - (collapse ? horizontalEdges[0].width / 2 : 0);
    // rowY[rowCount] already carries the trailing gutter from the loop; the
    // collapsed model extends one further half edge below the last
    // centerline.
    final gridBottom =
        rowY[rowCount] + (collapse ? horizontalEdges[rowCount].width / 2 : 0);

    for (final cell in cells) {
      final dx = columnX[cell.column];
      var slotHeight = 0.0;
      for (var row = cell.row; row < cell.row + cell.rowSpan; row++) {
        slotHeight += rowHeights[row];
      }
      var dy = rowY[cell.row];
      if (!collapse) {
        slotHeight += spacingV * (cell.rowSpan - 1);
      }
      final freeSpace = math.max(0, slotHeight - cell.height);
      switch (cell.style.verticalAlign) {
        case WeftVerticalAlign.top:
          break;
        case WeftVerticalAlign.middle:
          dy += freeSpace / 2;
        case WeftVerticalAlign.bottom:
          dy += freeSpace;
      }
      _shiftRange(
        commandStart: cell.commandStart!,
        commandEnd: cell.commandEnd!,
        boxStart: cell.boxStart!,
        boxEnd: cell.boxEnd!,
        linkStart: cell.linkStart!,
        linkEnd: cell.linkEnd!,
        offset: Offset(dx, dy),
      );
      // Browsers stretch the cell box, background and borders to the full
      // row slot; only the content moves with vertical alignment.
      if (freeSpace > 0) {
        _stretchCellToSlot(cell, dx, rowY[cell.row], slotHeight);
      }
    }

    // ---- Paint collapsed edges on top of the cell backgrounds.
    if (collapse) {
      final leftX = boxX + style.borderLeft.width + style.paddingLeft;
      final rightEnd = leftX + columnX[columnCount];
      for (var column = 0; column <= columnCount; column++) {
        final edge = verticalEdges[column];
        if (!edge.isVisible) continue;
        final x = leftX + columnX[column] - edge.width / 2;
        commands.add(
          WeftRectPaintCommand(
            nodeId: element.id,
            rect: Rect.fromLTWH(
              x,
              gridTop,
              edge.width,
              gridBottom - gridTop,
            ),
            color: edge.color,
          ),
        );
      }
      for (var row = 0; row <= rowCount; row++) {
        final edge = horizontalEdges[row];
        if (!edge.isVisible) continue;
        final y = rowY[row] - spacingV - edge.width / 2;
        commands.add(
          WeftRectPaintCommand(
            nodeId: element.id,
            rect: Rect.fromLTWH(
              leftX - verticalEdges[0].width / 2,
              y,
              rightEnd -
                  leftX +
                  (verticalEdges[0].width + verticalEdges[columnCount].width) /
                      2,
              edge.width,
            ),
            color: edge.color,
          ),
        );
      }
    }

    final height = style.verticalBorder +
        style.verticalPadding +
        captionHeight +
        (gridBottom - gridTop);
    _paintTableChrome(
      element: element,
      style: style,
      boxX: boxX,
      top: top,
      boxWidth: boxWidth,
      height: height,
      commandStart: commandStart,
    );
    return _BlockLayout(height: height);
  }

  void _paintTableChrome({
    required WeftElement element,
    required WeftComputedStyle style,
    required double boxX,
    required double top,
    required double boxWidth,
    required double height,
    required int commandStart,
  }) {
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
    if (boxWidth > 0 && height > 0) {
      boxes.add(
        WeftLayoutBox(
          nodeId: element.id,
          rect: Rect.fromLTWH(boxX, top, boxWidth, height),
        ),
      );
    }
  }

  double _layoutCaption({
    required WeftElement element,
    required WeftComputedStyle style,
    required double availableWidth,
    required double left,
    required double top,
    required List<WeftElement> ancestors,
  }) {
    if (style.display == WeftDisplay.none) return 0;
    final synthesized = _cellLayoutStyle(
      style,
      availableWidth,
      stripBorders: false,
    );
    final result = layoutBlock(
      element: element,
      style: synthesized,
      availableWidth: availableWidth,
      left: left,
      top: top,
      ancestors: ancestors,
      floats: _FloatContext(),
    );
    return result.height;
  }

  /// Lays a cell out with a forced border-box width. Cell margins never apply
  /// in table layout; collapsed cells lose their own borders to the shared
  /// edge model and receive the half edges as synthetic padding so content
  /// stays clear of the borders while the box spans centerline to
  /// centerline.
  WeftComputedStyle _cellLayoutStyle(
    WeftComputedStyle style,
    double borderBoxWidth, {
    required bool stripBorders,
    double? paddingLeft,
    double? paddingRight,
    double? paddingTop,
    double? paddingBottom,
  }) {
    return WeftComputedStyle(
      display: WeftDisplay.block,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      fontFamily: style.fontFamily,
      color: style.color,
      backgroundColor: style.backgroundColor,
      lineHeight: style.lineHeight,
      textAlign: style.textAlign,
      textDecoration: style.textDecoration,
      whiteSpace: style.whiteSpace,
      listStyle: style.listStyle,
      paddingTop: paddingTop ?? style.paddingTop,
      paddingRight: paddingRight ?? style.paddingRight,
      paddingBottom: paddingBottom ?? style.paddingBottom,
      paddingLeft: paddingLeft ?? style.paddingLeft,
      width: math.max(0, borderBoxWidth),
      minWidth: style.minWidth,
      maxWidth: style.maxWidth,
      boxSizing: WeftBoxSizing.borderBox,
      verticalAlign: style.verticalAlign,
      borderTop: stripBorders ? WeftBorderSide.none : style.borderTop,
      borderRight: stripBorders ? WeftBorderSide.none : style.borderRight,
      borderBottom: stripBorders ? WeftBorderSide.none : style.borderBottom,
      borderLeft: stripBorders ? WeftBorderSide.none : style.borderLeft,
    );
  }

  void _shiftRange({
    required int commandStart,
    required int commandEnd,
    required int boxStart,
    required int boxEnd,
    required int linkStart,
    required int linkEnd,
    required Offset offset,
  }) {
    if (offset == Offset.zero) return;
    for (var index = commandStart; index < commandEnd; index++) {
      commands[index] = commands[index].shift(offset);
    }
    for (var index = boxStart; index < boxEnd; index++) {
      final box = boxes[index];
      boxes[index] = WeftLayoutBox(
        nodeId: box.nodeId,
        rect: box.rect.shift(offset),
      );
    }
    for (var index = linkStart; index < linkEnd; index++) {
      links[index] = links[index].shift(offset);
    }
  }

  /// Extends a cell's own box, background and border commands to cover the
  /// full row slot, matching how browsers stretch table cells whose content
  /// is shorter than the row.
  void _stretchCellToSlot(
    _TableCell cell,
    double dx,
    double slotTop,
    double slotHeight,
  ) {
    final slotRect = Rect.fromLTWH(
      dx,
      slotTop,
      cell.boxWidth,
      slotHeight,
    );
    for (var index = cell.boxEnd! - 1; index >= cell.boxStart!; index--) {
      if (boxes[index].nodeId == cell.element.id) {
        boxes[index] = WeftLayoutBox(
          nodeId: cell.element.id,
          rect: slotRect,
        );
        break;
      }
    }

    // The cell's own chrome commands sit at the front of its range in the
    // same order layoutBlock produced them: background, then border sides.
    var index = cell.commandStart!;
    final background = cell.style.backgroundColor;
    if (background != null &&
        background.a > 0 &&
        index < cell.commandEnd! &&
        commands[index] is WeftRectPaintCommand &&
        commands[index].nodeId == cell.element.id) {
      commands[index] = WeftRectPaintCommand(
        nodeId: cell.element.id,
        rect: slotRect,
        color: background,
      );
      index += 1;
    }
    for (final command in _borderCommands(
      nodeId: cell.element.id,
      style: cell.style,
      boxX: dx,
      top: slotTop,
      boxWidth: cell.boxWidth,
      height: slotHeight,
    )) {
      if (index >= cell.commandEnd!) break;
      final existing = commands[index];
      if (existing is! WeftRectPaintCommand ||
          existing.nodeId != cell.element.id) {
        break;
      }
      commands[index] = command;
      index += 1;
    }
  }

  /// Intrinsic min/max content widths of a cell. The result carries content
  /// plus padding and, in the separate model, the cell's own borders; the
  /// collapsed border model keeps edges out of column intrinsics entirely.
  ({double min, double max}) _measureCellContent(
    _TableCell cell, {
    required bool collapse,
  }) {
    final style = cell.style;
    final chrome =
        style.horizontalPadding + (collapse ? 0.0 : style.horizontalBorder);
    if (style.width != null) {
      final box = style.boxSizing == WeftBoxSizing.borderBox
          ? style.width!
          : style.width! + chrome;
      return (min: box, max: box);
    }
    final sizes = _measureChildren(cell.element, style, cell.ancestors);
    return (min: sizes.min + chrome, max: sizes.max + chrome);
  }

  ({double min, double max}) _measureChildren(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors,
  ) {
    var min = 0.0;
    var max = 0.0;
    final inline = _InlineAccumulator(this);
    final childAncestors = <WeftElement>[...ancestors, element];
    void flushInline() {
      final sizes = _measureInline(inline, style);
      min = math.max(min, sizes.min);
      max = math.max(max, sizes.max);
      inline.reset();
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
      if (child.tag == 'br') {
        inline.addBreak(child.id, childStyle);
        continue;
      }
      if (childStyle.display == WeftDisplay.inline &&
          !(child.tag == 'img' && childStyle.float == WeftFloat.none)) {
        inline.collectElement(child, childStyle, childAncestors);
        continue;
      }
      if (childStyle.float != WeftFloat.none) {
        // Out-of-flow content does not contribute intrinsic width.
        continue;
      }
      flushInline();
      final sizes = _measureBlock(child, childStyle, childAncestors);
      min = math.max(min, sizes.min);
      max = math.max(max, sizes.max);
    }
    flushInline();
    return (min: min, max: max);
  }

  ({double min, double max}) _measureBlock(
    WeftElement element,
    WeftComputedStyle style,
    List<WeftElement> ancestors,
  ) {
    if (element.tag == 'hr') {
      final chrome = style.horizontalPadding + style.horizontalBorder;
      return (min: chrome + 1, max: chrome + 1);
    }
    if (element.tag == 'img') {
      final chrome = style.horizontalPadding + style.horizontalBorder;
      var width = _attributeLength(element, 'width');
      final cssWidth = style.width;
      if (cssWidth != null) {
        width = style.boxSizing == WeftBoxSizing.borderBox
            ? cssWidth
            : cssWidth + chrome;
      }
      width ??= images[element.id]?.width.toDouble() ?? 120;
      return (min: width + chrome, max: width + chrome);
    }
    final sizes = _measureChildren(element, style, ancestors);
    var min = sizes.min + style.horizontalPadding + style.horizontalBorder;
    var max = sizes.max + style.horizontalPadding + style.horizontalBorder;
    if (style.width != null) {
      final chrome = style.horizontalPadding + style.horizontalBorder;
      final box = style.boxSizing == WeftBoxSizing.borderBox
          ? style.width!
          : style.width! + chrome;
      min = box;
      max = math.max(max, box);
    }
    min += style.marginLeft + style.marginRight;
    max += style.marginLeft + style.marginRight;
    return (min: min, max: max);
  }

  ({double min, double max}) _measureInline(
    _InlineAccumulator inline,
    WeftComputedStyle parentStyle,
  ) {
    if (!inline.hasContent) return (min: 0, max: 0);
    final layout = inline.buildLayout(
      parentStyle: parentStyle,
      width: double.infinity,
      textScaler: textScaler,
    );
    if (layout == null) return (min: 0, max: 0);
    final min = layout.painter.minIntrinsicWidth;
    final max = layout.painter.maxIntrinsicWidth;
    layout.painter.dispose();
    return (min: min, max: max);
  }

  static void _distributeSpanWidth(
    List<double> columns,
    int start,
    int span,
    double required,
  ) {
    var current = 0.0;
    for (var index = start; index < start + span; index++) {
      current += columns[index];
    }
    if (required <= current) return;
    final deficit = required - current;
    final weights = <double>[
      for (var index = start; index < start + span; index++) columns[index],
    ];
    final total = _sum(weights);
    for (var offset = 0; offset < span; offset++) {
      final share =
          total > 0 ? deficit * weights[offset] / total : deficit / span;
      columns[start + offset] += share;
    }
  }

  static double _sum(List<double> values) {
    var total = 0.0;
    for (final value in values) {
      total += value;
    }
    return total;
  }

  static int _spanAttribute(WeftElement element, String name) {
    final value = element.attribute(name);
    final parsed = value == null ? null : int.tryParse(value);
    if (parsed == null || parsed < 1) return 1;
    return parsed.clamp(1, 1000);
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

/// A table cell placed in the slot grid. Laid out at the origin, then
/// shifted into its grid slot once row heights are resolved.
final class _TableCell {
  _TableCell({
    required this.element,
    required this.style,
    required this.ancestors,
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.columnSpan,
  });

  final WeftElement element;
  final WeftComputedStyle style;
  final List<WeftElement> ancestors;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;

  double minWidth = 0;
  double maxWidth = 0;
  double boxWidth = 0;
  double height = 0;
  int? commandStart;
  int? commandEnd;
  int? boxStart;
  int? boxEnd;
  int? linkStart;
  int? linkEnd;
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
    required this.textStart,
    required this.textEnd,
  });

  final double x;
  final double y;
  final TextPainter painter;

  /// Range of this line inside the accumulator's flushed plain text.
  final int textStart;
  final int textEnd;
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
  const _InlineLayout({
    required this.painter,
    required this.links,
    required this.textEnd,
  });

  final TextPainter painter;
  final List<WeftLinkRegion> links;

  /// End of the painted text inside the accumulator's flushed plain text.
  final int textEnd;
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
    return _InlineLayout(
      painter: painter,
      links: links,
      textEnd: plainText.length,
    );
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
        lines.add(
          _InlineLine(
            x: slot.left,
            y: y,
            painter: painter,
            textStart: offset,
            textEnd: paintEnd,
          ),
        );
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

  /// Maps the flushed plain-text range [start, end) onto painter-relative
  /// and node-relative coordinates. Each text node contributes one run per
  /// flush, so node offsets stay stable across line-split painters.
  List<WeftTextPainterRun> runSpecs(int start, int end) {
    final specs = <WeftTextPainterRun>[];
    var cursor = 0;
    for (final run in _runs) {
      final runStart = cursor;
      final runEnd = cursor + run.text.length;
      cursor = runEnd;
      if (runEnd <= start || runStart >= end) continue;
      final sliceStart = math.max(runStart, start);
      final sliceEnd = math.min(runEnd, end);
      if (sliceEnd <= sliceStart) continue;
      specs.add(
        WeftTextPainterRun(
          nodeId: run.nodeId,
          painterStart: sliceStart - start,
          painterEnd: sliceEnd - start,
          nodeStart: sliceStart - runStart,
          nodeEnd: sliceEnd - runStart,
        ),
      );
    }
    return specs;
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
