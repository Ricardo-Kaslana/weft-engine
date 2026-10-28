part of 'layout_engine.dart';

final class _LazyChild {
  const _LazyChild({
    required this.element,
    required this.style,
    required this.ordinal,
    required this.gap,
    required this.marker,
    required this.minimumPaintOffset,
  });

  final WeftElement element;
  final WeftComputedStyle style;
  final int ordinal;
  final double gap;
  final String? marker;
  final double minimumPaintOffset;

  bool get isFloat => style.float != WeftFloat.none;

  double? get fixedHeight {
    if (isFloat) return 0;
    final height = style.height;
    if (height == null) return null;
    return style.boxSizing == WeftBoxSizing.borderBox
        ? height
        : height + style.verticalBorder + style.verticalPadding;
  }
}

final class _LazyBlockIndex {
  _LazyBlockIndex(int length) {
    while (_capacity < length) {
      _capacity *= 2;
    }
    _tops = List.filled(_capacity * 2, double.infinity);
    _bottoms = List.filled(_capacity * 2, double.negativeInfinity);
  }

  var _capacity = 1;
  late final List<double> _tops;
  late final List<double> _bottoms;

  void add(int ordinal, WeftCachedLayoutBlock block) {
    var slot = _capacity + ordinal;
    _tops[slot] = block.top;
    _bottoms[slot] = block.top + block.height;
    if (!block.paintBounds.isEmpty) {
      _tops[slot] = math.min(_tops[slot], block.paintBounds.top);
      _bottoms[slot] = math.max(_bottoms[slot], block.paintBounds.bottom);
    }
    while (slot > 1) {
      slot ~/= 2;
      _tops[slot] = math.min(_tops[slot * 2], _tops[slot * 2 + 1]);
      _bottoms[slot] = math.max(_bottoms[slot * 2], _bottoms[slot * 2 + 1]);
    }
  }

  List<int> candidates(double start, double end) {
    final result = <int>[];
    void visit(int slot) {
      if (_tops[slot] >= end || _bottoms[slot] <= start) return;
      if (slot >= _capacity) {
        result.add(slot - _capacity);
      } else {
        visit(slot * 2);
        visit(slot * 2 + 1);
      }
    }

    visit(1);
    return result;
  }
}

final class _LazyLayoutState implements WeftViewportLayoutState {
  _LazyLayoutState(this.children, this.contentY, this.trailingMargin)
      : cursor = contentY,
        index = _LazyBlockIndex(children.length) {
    for (final child in children) {
      remainingExtent += child.gap;
      final fixed = child.fixedHeight;
      if (fixed != null) {
        remainingExtent += fixed;
      } else {
        final tag = child.element.tag;
        remainingCounts[tag] = (remainingCounts[tag] ?? 0) + 1;
        remainingExtent += estimate(tag);
      }
    }
    minimumAdvances = List.filled(children.length, 0);
    var suffix = 0.0;
    for (var i = children.length - 1; i >= 0; i--) {
      ordinalIndices[children[i].ordinal] = i;
      suffix =
          children[i].gap + math.min(children[i].minimumPaintOffset, suffix);
      minimumAdvances[i] = suffix;
    }
  }

  final List<_LazyChild> children;
  final double contentY;
  final double trailingMargin;
  final _LazyBlockIndex index;
  final _FloatContext floats = _FloatContext();
  final List<WeftCachedLayoutBlock> _blocks = [];
  final List<int> floatStarts = [];
  final Set<int> materialized = {};
  final Map<String, int> remainingCounts = {};
  final Map<String, List<double>> samples = {};
  final Map<int, int> ordinalIndices = {};
  late final List<double> minimumAdvances;
  double remainingExtent = 0;
  double cursor;

  @override
  late final List<WeftCachedLayoutBlock> blocks = UnmodifiableListView(_blocks);

  @override
  int get childCount => children.length;

  @override
  double get measuredEnd {
    if (_blocks.length == childCount) return double.infinity;
    // Unmeasured upward overflow can pull later content back into the window.
    return cursor + minimumAdvances[_blocks.length];
  }

  double topFor(_LazyChild child) {
    if (child.isFloat) return cursor;
    return math.max(cursor + child.gap, floats.clearBottom(child.style.clear));
  }

  bool intersects(int ordinal, double start, double end) {
    final block = _blocks[ordinal];
    return (block.top < end && block.top + block.height > start) ||
        (block.paintBounds.top < end && block.paintBounds.bottom > start);
  }

  List<int> window(double start, double end) => [
        for (final ordinal in index.candidates(start, end))
          if (intersects(ordinal, start, end)) ordinal,
      ];

  @override
  bool needsLayout(double start, double end) {
    if (end > measuredEnd) return true;
    final needed = window(start, end);
    return needed.length != materialized.length ||
        needed.any((ordinal) => !materialized.contains(ordinal));
  }

  double estimate(String tag) {
    final heights = samples[tag];
    if (heights != null && heights.isNotEmpty) {
      final sorted = heights.toList()..sort();
      return sorted[sorted.length ~/ 2];
    }
    return switch (tag) {
      'table' => 240,
      'img' => 96,
      _ => 48,
    };
  }

  void append(WeftCachedLayoutBlock block, int floatStart) {
    final ordinal = _blocks.length;
    final child = children[ordinal];
    final tag = child.element.tag;
    final oldEstimate = estimate(tag);
    remainingExtent -= child.gap + (child.fixedHeight ?? oldEstimate);
    if (child.fixedHeight == null) {
      remainingCounts[tag] = remainingCounts[tag]! - 1;
    }
    if (block.height.isFinite && block.height > 0) {
      final heights = samples.putIfAbsent(tag, () => []);
      heights.add(block.height);
      if (heights.length > 16) heights.removeAt(0);
      remainingExtent +=
          (estimate(tag) - oldEstimate) * (remainingCounts[tag] ?? 0);
    }
    _blocks.add(block);
    floatStarts.add(floatStart);
    index.add(ordinal, block);
    if (block.materialized) materialized.add(ordinal);
    if (!child.isFloat) cursor = block.top + block.height;
    if (_blocks.length == childCount) remainingExtent = 0;
  }
}

extension _LazyLayout on _LayoutContext {
  double _minimumPaintOffset(WeftElement element) {
    final style = styleCache[element]!;
    var minimum =
        style.float == WeftFloat.none ? 0.0 : math.min(0.0, style.marginTop);
    void visit(WeftElement parent) {
      for (final child in parent.children) {
        if (child is! WeftElement) continue;
        final childStyle = styleCache[child]!;
        minimum += math.min(0, childStyle.marginTop) +
            math.min(0, childStyle.marginBottom);
        visit(child);
      }
    }

    visit(element);
    return minimum;
  }

  _LazyLayoutState? _prepareLazyState(
    WeftComputedStyle style,
    double contentY,
    List<WeftElement> ancestors,
  ) {
    final children = <_LazyChild>[];
    var leading = style.borderTop.width == 0 && style.paddingTop == 0;
    double? pendingMargin;
    var orderedItem = 0;
    for (var ordinal = 0; ordinal < body.children.length; ordinal++) {
      visitedBlockCount++;
      final node = body.children[ordinal];
      if (node is! WeftElement) continue;
      final childStyle = styleFor(node, parent: style, ancestors: ancestors);
      if (_isSelfCollapsing(node, childStyle, ancestors)) return null;
      final floating = childStyle.float != WeftFloat.none;
      final top = node.tag == 'table' || node.tag == 'img'
          ? childStyle.marginTop
          : outerMarginTop(node, childStyle, ancestors);
      final bottom = node.tag == 'table' || node.tag == 'img'
          ? childStyle.marginBottom
          : outerMarginBottom(node, childStyle, ancestors);
      final gap = floating || leading
          ? 0.0
          : pendingMargin == null
              ? top
              : _collapseMargins(pendingMargin, top);
      if (!floating) {
        pendingMargin = bottom;
        leading = false;
      }
      if (node.tag == 'li' && childStyle.listStyle == WeftListStyle.decimal) {
        orderedItem++;
      }
      children.add(_LazyChild(
        element: node,
        style: childStyle,
        ordinal: ordinal,
        gap: gap,
        minimumPaintOffset: _minimumPaintOffset(node),
        marker: _markerFor(
          child: node,
          childStyle: childStyle,
          orderedItem: orderedItem,
        ),
      ));
    }
    estimatedBlockCount += children.length;
    final state = _LazyLayoutState(
      children,
      contentY,
      style.borderBottom.width == 0 && style.paddingBottom == 0
          ? 0
          : pendingMargin ?? 0,
    );
    return state;
  }

  double _layoutLazyChildren({
    required WeftComputedStyle style,
    required double contentX,
    required double contentY,
    required double contentWidth,
    required List<WeftElement> childAncestors,
  }) {
    var state = lazyState;
    if (state == null) {
      state = _prepareLazyState(style, contentY, childAncestors);
      if (state == null) {
        topLevelCacheEligible = false;
        return 0;
      }
      lazyState = state;
      for (final child in state.children) {
        final old = reusableBlocks[child.element.id];
        if (old == null ||
            old.left != contentX ||
            old.top != state.topFor(child)) {
          break;
        }
        visitedBlockCount++;
        final floatStart = state.floats.exclusionCount;
        state.floats.addExclusions(old.floatExclusions);
        state.append(_copyLazyBlock(old, element: child.element), floatStart);
      }
    }
    final oldPrefix = state.blocks.length;
    reusedBlockCount = oldPrefix;
    final needed = state.window(viewportStart!, viewportEnd!).toSet();
    final focus = focusOrdinal;
    if (focus != null) {
      final focusIndex = state.ordinalIndices[focus];
      if (focusIndex != null && focusIndex < oldPrefix) needed.add(focusIndex);
    }
    for (final ordinal in state.materialized.toList()) {
      if (needed.contains(ordinal)) continue;
      visitedBlockCount++;
      state._blocks[ordinal] =
          _copyLazyBlock(state.blocks[ordinal], materialize: false);
      state.materialized.remove(ordinal);
    }
    final ordered = needed.toList()..sort();
    for (final ordinal in ordered) {
      visitedBlockCount++;
      final block = state.blocks[ordinal];
      if (block.materialized) {
        commands.addAll(block.commands);
        boxes.addAll(block.boxes);
        links.addAll(block.links);
        tagRegions.addAll(block.tagRegions);
        reusedCommands.addAll(block.commands);
      } else {
        final floats = _FloatContext()
          ..exclusions
              .addAll(state.floats.exclusions.take(state.floatStarts[ordinal]));
        final rebuilt = _layoutLazyBlock(
          state.children[ordinal],
          contentX,
          block.top,
          contentWidth,
          childAncestors,
          floats,
        );
        assert(rebuilt.height == block.height);
        state._blocks[ordinal] = rebuilt;
        state.materialized.add(ordinal);
      }
    }
    var newBlocks = 0;
    while (state.blocks.length < state.childCount) {
      final child = state.children[state.blocks.length];
      final top = state.topFor(child);
      if (maxNewBlocks != null && newBlocks >= maxNewBlocks!) break;
      if (state.measuredEnd >= viewportEnd! &&
          (focus == null || child.ordinal > focus)) {
        break;
      }
      visitedBlockCount++;
      estimatedBlockCount++;
      final floatStart = state.floats.exclusionCount;
      final block = _layoutLazyBlock(
        child,
        contentX,
        top,
        contentWidth,
        childAncestors,
        state.floats,
      );
      state.append(block, floatStart);
      newBlocks++;
    }
    materializedBlockCount = state.materialized.length;
    return math.max(0,
        state.cursor - contentY + state.remainingExtent + state.trailingMargin);
  }

  WeftCachedLayoutBlock _layoutLazyBlock(
    _LazyChild child,
    double left,
    double top,
    double width,
    List<WeftElement> ancestors,
    _FloatContext floats,
  ) {
    final start = _startTopLevelBlock(body, floats)!;
    final element = child.element;
    final style = child.style;
    double height;
    if (element.tag == 'img') {
      final image = images[element.id]!;
      if (child.isFloat) {
        _placeFloatImage(
            element: element,
            style: style,
            image: image,
            contentX: left,
            contentWidth: width,
            top: top,
            floats: floats);
        height = 0;
      } else {
        final metrics = _layoutImageBlock(
            element: element,
            style: style,
            image: image,
            availableWidth: width,
            left: left,
            top: top);
        if (metrics == null) topLevelCacheEligible = false;
        height = metrics?.boxHeight ?? 0;
      }
    } else if (element.tag == 'table') {
      height = layoutTable(
              element: element,
              style: style,
              availableWidth: width,
              left: left,
              top: top,
              ancestors: ancestors)
          .height;
    } else {
      height = layoutBlock(
              element: element,
              style: style,
              availableWidth: width,
              left: left,
              top: top,
              ancestors: ancestors,
              floats: floats,
              marker: child.marker)
          .height;
    }
    laidOutBlockCount++;
    final blockCommands = commands.sublist(start.$1);
    final blockBoxes = boxes.sublist(start.$2);
    final blockLinks = links.sublist(start.$3);
    final blockTags = tagRegions.sublist(start.$4);
    final paintBounds = _commandsPaintBounds(blockCommands);
    final materialize = _shouldMaterialize(
        top: top,
        height: height,
        paintBounds: paintBounds,
        ordinal: child.ordinal);
    if (!materialize) {
      for (final command in blockCommands) {
        command.dispose();
      }
      commands.removeRange(start.$1, commands.length);
      boxes.removeRange(start.$2, boxes.length);
      links.removeRange(start.$3, links.length);
      tagRegions.removeRange(start.$4, tagRegions.length);
    }
    return WeftCachedLayoutBlock(
      element: element,
      left: left,
      top: top,
      height: height,
      materialized: materialize,
      paintBounds: paintBounds,
      commands: materialize ? blockCommands : const [],
      boxes: materialize ? blockBoxes : const [],
      links: materialize ? blockLinks : const [],
      tagRegions: materialize ? blockTags : const [],
      floatExclusions: floats.snapshotFrom(start.$5),
    );
  }

  WeftCachedLayoutBlock _copyLazyBlock(
    WeftCachedLayoutBlock block, {
    WeftElement? element,
    bool? materialize,
  }) {
    final held = materialize ?? block.materialized;
    return WeftCachedLayoutBlock(
      element: element ?? block.element,
      left: block.left,
      top: block.top,
      height: block.height,
      materialized: held,
      paintBounds: block.paintBounds,
      commands: held ? block.commands : const [],
      boxes: held ? block.boxes : const [],
      links: held ? block.links : const [],
      tagRegions: held ? block.tagRegions : const [],
      floatExclusions: block.floatExclusions,
    );
  }
}
