part of 'layout_engine.dart';

extension _TableLayoutMethods on _LayoutContext {
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
        final cellStyle = styleFor(
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

    // ---- Column track declarations from colgroup/col. They are collected
    // wherever they appear among the table's children: CSS only allows them
    // before the first row, but tolerating later placement keeps controlled
    // content from silently losing its column widths (ADR 0022).
    final tracks = _collectColumnTracks(
      element,
      style: style,
      ancestors: tableAncestors,
    );
    var declaredColumns = 0;
    for (final track in tracks) {
      declaredColumns += track.span;
    }
    // Rows may declare more columns than the tracks; the surplus stays auto.
    columnCount = math.max(columnCount, declaredColumns);

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
        final captionStyle = styleFor(
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

    // ---- Per-column track declarations. A pinned column keeps its declared
    // width measured between the edge centre lines (the cell border-box width
    // in the separate model); a percentage column records an expectation
    // against the resolved grid width. The first declaration covering a
    // column wins.
    final pinnedContentWidth = List<double?>.filled(columnCount, null);
    final columnPercent = List<double?>.filled(columnCount, null);
    var trackColumn = 0;
    for (final track in tracks) {
      for (var offset = 0;
          offset < track.span && trackColumn < columnCount;
          offset++, trackColumn++) {
        if (track.fixedWidth == null && track.percentWidth == null) continue;
        if (pinnedContentWidth[trackColumn] != null ||
            columnPercent[trackColumn] != null) {
          continue;
        }
        if (track.fixedWidth != null) {
          final halfEdges = collapse
              ? (verticalEdges[trackColumn].width +
                      verticalEdges[trackColumn + 1].width) /
                  2
              : 0.0;
          pinnedContentWidth[trackColumn] = math.max(
            0.0,
            track.fixedWidth! - halfEdges,
          );
        } else {
          columnPercent[trackColumn] = track.percentWidth;
        }
      }
    }

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
      // Pinned columns keep their declared width, so a spanning cell only
      // pushes the need left over after subtracting them into the flexible
      // columns it covers; when the pinned columns already provide enough,
      // nothing is distributed and the cell overflows as usual (ADR 0022).
      var pinned = 0.0;
      for (var column = cell.column;
          column < cell.column + cell.columnSpan;
          column++) {
        pinned += pinnedContentWidth[column] ?? 0;
      }
      _distributeSpanWidth(
        columnMin,
        cell.column,
        cell.columnSpan,
        cell.minWidth - spacingH * (cell.columnSpan - 1) - pinned,
        flexible: (column) => pinnedContentWidth[column] == null,
      );
      _distributeSpanWidth(
        columnMax,
        cell.column,
        cell.columnSpan,
        cell.maxWidth - spacingH * (cell.columnSpan - 1) - pinned,
        flexible: (column) => pinnedContentWidth[column] == null,
      );
    }
    // Pinned columns override whatever their cells measured.
    for (var column = 0; column < columnCount; column++) {
      final pinned = pinnedContentWidth[column];
      if (pinned == null) continue;
      columnMin[column] = pinned;
      columnMax[column] = pinned;
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
    // Chrome treats a specified table width as the span between the outer
    // edge centre lines, so in the collapsed model the outer half edges do
    // not consume the column budget once column tracks exist. Track-less
    // tables keep the ADR 0012 approximation where the whole grid fits the
    // box (ADR 0022).
    final columnsBudget = math.max(
      0,
      gridWidth -
          spacingTotal -
          allEdgesTotal +
          (style.width != null && tracks.isNotEmpty ? outerEdges : 0.0),
    );

    // Pinned columns take their declared width first and never join the
    // redistribution.
    var pinnedSum = 0.0;
    for (var column = 0; column < columnCount; column++) {
      final pinned = pinnedContentWidth[column];
      if (pinned == null) continue;
      contentWidths[column] = pinned;
      pinnedSum += pinned;
    }

    // Percentage columns hold an expectation against the resolved grid width
    // (the table content box) and keep it while the auto columns consume the
    // budget left after the pinned tracks (ADR 0022).
    var percentSum = 0.0;
    for (var column = 0; column < columnCount; column++) {
      final percent = columnPercent[column];
      if (percent == null) continue;
      final halfEdges = collapse
          ? (verticalEdges[column].width + verticalEdges[column + 1].width) / 2
          : 0.0;
      final target = math.max(0.0, percent / 100 * gridWidth - halfEdges);
      contentWidths[column] = target;
      percentSum += target;
    }

    var autoMinSum = 0.0;
    var autoMaxSum = 0.0;
    var autoCount = 0;
    for (var column = 0; column < columnCount; column++) {
      if (pinnedContentWidth[column] != null || columnPercent[column] != null) {
        continue;
      }
      autoMinSum += columnMin[column];
      autoMaxSum += columnMax[column];
      autoCount += 1;
    }
    final autoBudget = math.max(0, columnsBudget - pinnedSum - percentSum);
    if (autoCount > 0 && autoBudget >= autoMaxSum) {
      final extra = autoBudget - autoMaxSum;
      for (var column = 0; column < columnCount; column++) {
        if (pinnedContentWidth[column] != null ||
            columnPercent[column] != null) {
          continue;
        }
        final share = autoMaxSum > 0
            ? extra * columnMax[column] / autoMaxSum
            : extra / autoCount;
        contentWidths[column] = columnMax[column] + share;
      }
    } else if (autoCount > 0 && autoBudget >= autoMinSum) {
      final extra = autoBudget - autoMinSum;
      for (var column = 0; column < columnCount; column++) {
        if (pinnedContentWidth[column] != null ||
            columnPercent[column] != null) {
          continue;
        }
        final share = autoMaxSum > 0
            ? extra * columnMax[column] / autoMaxSum
            : extra / autoCount;
        contentWidths[column] = columnMin[column] + share;
      }
    } else if (autoCount > 0) {
      final scale = autoMinSum > 0 ? autoBudget / autoMinSum : 1.0;
      for (var column = 0; column < columnCount; column++) {
        if (pinnedContentWidth[column] != null ||
            columnPercent[column] != null) {
          continue;
        }
        contentWidths[column] = columnMin[column] * scale;
      }
    }

    // Percentage tracks are re-solved proportionally once the auto columns
    // have taken their share: they shrink when the pinned tracks alone
    // overflow the budget, and stretch to consume whatever is left when no
    // auto column exists to absorb it (ADR 0022).
    if (percentSum > 0) {
      var autoSum = 0.0;
      for (var column = 0; column < columnCount; column++) {
        if (pinnedContentWidth[column] != null ||
            columnPercent[column] != null) {
          continue;
        }
        autoSum += contentWidths[column];
      }
      final leftover = math.max(0, columnsBudget - pinnedSum - autoSum);
      final scale = leftover / percentSum;
      if (scale != 1.0) {
        for (var column = 0; column < columnCount; column++) {
          if (pinnedContentWidth[column] != null ||
              columnPercent[column] == null) {
            continue;
          }
          contentWidths[column] *= scale;
        }
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
      final captionStyle = styleFor(
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
        // widths are the centre-line distances including interior edges, so
        // the slice sums to the full span; the shared half edges become
        // synthetic padding so content stays clear of borders while the
        // background extends beneath them, like a browser.
        final edgeLeft = verticalEdges[cell.column].width;
        final edgeRight = verticalEdges[cell.column + cell.columnSpan].width;
        borderBoxWidth = _sum(
          columnWidths.sublist(
            cell.column,
            cell.column + cell.columnSpan,
          ),
        );
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
      final childStyle = styleFor(
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

  /// Distributes a spanning cell's required width into the columns it covers.
  /// Columns where [flexible] returns false are skipped entirely: they keep
  /// the width a col declaration pinned, so the caller reduces the
  /// requirement by what those columns already provide.
  void _distributeSpanWidth(
    List<double> columns,
    int start,
    int span,
    double required, {
    bool Function(int column)? flexible,
  }) {
    var current = 0.0;
    var flexibleCount = 0;
    for (var index = start; index < start + span; index++) {
      if (flexible?.call(index) ?? true) {
        current += columns[index];
        flexibleCount += 1;
      }
    }
    if (flexibleCount == 0 || required <= current) return;
    final deficit = required - current;
    final weights = <double>[
      for (var index = start; index < start + span; index++)
        if (flexible?.call(index) ?? true) columns[index],
    ];
    final total = _sum(weights);
    var weightIndex = 0;
    for (var index = start; index < start + span; index++) {
      if (!(flexible?.call(index) ?? true)) continue;
      final share = total > 0
          ? deficit * weights[weightIndex] / total
          : deficit / flexibleCount;
      columns[index] += share;
      weightIndex += 1;
    }
  }

  double _sum(List<double> values) {
    var total = 0.0;
    for (final value in values) {
      total += value;
    }
    return total;
  }

  int _spanAttribute(WeftElement element, String name) {
    final value = element.attribute(name);
    final parsed = value == null ? null : int.tryParse(value);
    if (parsed == null || parsed < 1) return 1;
    return parsed.clamp(1, 1000);
  }

  /// Column track declarations from the colgroup/col children of [element].
  /// A colgroup without col children declares placeholder tracks for its own
  /// span; per HTML the span attribute is ignored once col children exist.
  /// Widths come from CSS first and the width attribute second, so a px value
  /// pins its columns while a percentage records an expectation.
  List<_ColumnTrack> _collectColumnTracks(
    WeftElement element, {
    required WeftComputedStyle style,
    required List<WeftElement> ancestors,
  }) {
    final tracks = <_ColumnTrack>[];
    void addCol(WeftElement col) {
      final colStyle = styleFor(
        col,
        parent: style,
        ancestors: ancestors,
      );
      double? fixed;
      double? percent;
      final attributePercent = _attributePercent(col, 'width');
      if (colStyle.width != null) {
        fixed = colStyle.width;
      } else if (colStyle.widthPercent != null) {
        percent = colStyle.widthPercent;
      } else if (attributePercent != null) {
        percent = attributePercent;
      } else {
        fixed = _attributeLength(col, 'width');
      }
      tracks.add(
        _ColumnTrack(
          span: _spanAttribute(col, 'span'),
          fixedWidth: fixed,
          percentWidth: percent,
        ),
      );
    }

    for (final child in element.children) {
      if (child is! WeftElement) continue;
      switch (child.tag) {
        case 'colgroup':
          final cols = child.children
              .whereType<WeftElement>()
              .where((col) => col.tag == 'col')
              .toList();
          if (cols.isEmpty) {
            for (var index = 0;
                index < _spanAttribute(child, 'span');
                index++) {
              tracks.add(_ColumnTrack());
            }
          } else {
            for (final col in cols) {
              addCol(col);
            }
          }
        case 'col':
          addCol(child);
      }
    }
    return tracks;
  }
}

double? _attributeLength(WeftElement element, String name) {
  final value = element.attribute(name);
  if (value == null) return null;
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return parsed;
}

/// Parses a col width attribute percentage (25 for `width="25%"`), or null
/// for any other value.
double? _attributePercent(WeftElement element, String name) {
  final value = element.attribute(name);
  if (value == null || !value.endsWith('%')) return null;
  final parsed = double.tryParse(value.substring(0, value.length - 1));
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return parsed;
}

/// One column track declaration collected from colgroup/col elements. Fixed
/// and percentage widths are mutually exclusive; a track with neither is a
/// pure placeholder that keeps its columns auto-sized.
final class _ColumnTrack {
  _ColumnTrack({this.span = 1, this.fixedWidth, this.percentWidth});

  final int span;
  final double? fixedWidth;
  final double? percentWidth;
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
