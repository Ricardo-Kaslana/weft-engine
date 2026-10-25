part of 'layout_engine.dart';

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
      consumed = _adjustForLineBreakRules(
        plainText,
        offset,
        consumed,
        parentStyle.whiteSpace,
        context.lineBreakRules,
      );
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

  /// Applies kinsoku adjustments to a proposed break at [consumed].
  ///
  /// A break may not leave a prohibited character at the start of the next
  /// line or at the end of the current one; the neighbouring character is
  /// pulled to the other line instead. [floor] keeps at least one character
  /// on the current line, so input made entirely of prohibited characters
  /// still advances instead of looping, and the bounded guard caps how far
  /// the break may retreat.
  static int _adjustForLineBreakRules(
    String text,
    int start,
    int consumed,
    WeftWhiteSpace whiteSpace,
    WeftLineBreakRules rules,
  ) {
    if (rules.lineStartProhibited.isEmpty && rules.lineEndProhibited.isEmpty) {
      return consumed;
    }
    final floor = start + _nextCodeUnitLength(text, start);
    var adjusted = consumed;
    for (var guard = 0; guard < 64 && adjusted > floor; guard++) {
      var scan = adjusted;
      if (whiteSpace == WeftWhiteSpace.normal) {
        // Leading collapsible spaces are skipped before a line paints, so a
        // prohibited character sitting behind a space run at the break is
        // just as illegal as one directly at [adjusted]. Only spaces and
        // tabs are crossed here; a hard newline ends the scan.
        while (scan < text.length &&
            (text.codeUnitAt(scan) == 0x20 || text.codeUnitAt(scan) == 0x09)) {
          scan++;
        }
      }
      final opensWithProhibited = scan < text.length &&
          rules.lineStartProhibited.contains(text.codeUnitAt(scan));
      final endsWithProhibited =
          rules.lineEndProhibited.contains(text.codeUnitAt(adjusted - 1));
      if (!opensWithProhibited && !endsWithProhibited) break;
      final target = _previousCodePointStart(text, adjusted);
      if (target < floor) break;
      adjusted = target;
    }
    return adjusted;
  }

  /// Start index of the code point immediately before [index], keeping
  /// surrogate pairs intact when the break would otherwise split one.
  static int _previousCodePointStart(String text, int index) {
    if (index >= 2) {
      final previous = text.codeUnitAt(index - 1);
      if (previous >= 0xDC00 && previous <= 0xDFFF) {
        final before = text.codeUnitAt(index - 2);
        if (before >= 0xD800 && before <= 0xDBFF) return index - 2;
      }
    }
    return index - 1;
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
