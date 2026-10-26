import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'style_resolver.dart';

final RegExp _collapsibleWhitespace = RegExp(r'\s+');
final RegExp _leadingCollapsibleWhitespace = RegExp(r'^\s+');
final RegExp _trailingCollapsibleWhitespace = RegExp(r'\s+$');

/// One text node in the logical text stream, with the node's painted text
/// (whitespace collapsed for `white-space: normal`, raw otherwise).
final class WeftTextEntry {
  const WeftTextEntry({
    required this.nodeId,
    required this.text,
    required this.globalStart,
  });

  final NodeId nodeId;
  final String text;

  /// Offset of this entry's text inside the logical stream.
  final int globalStart;

  int get globalEnd => globalStart + text.length;
}

/// The logical text model of one document snapshot.
///
/// Anchors address a text node and an offset inside the node's painted
/// text. Entries are joined with newlines: every `<br>` contributes one,
/// and a block boundary contributes one (idempotently across nested block
/// containers). The model is rebuilt with every layout and never outlives
/// its snapshot, so anchors that cannot be mapped after a content change
/// are dropped rather than clamped (see ADR 0013).
final class WeftTextIndex {
  const WeftTextIndex._(this.entries, this.entryByNode, this._logical);

  /// Text entries in reading order.
  final List<WeftTextEntry> entries;

  final Map<NodeId, WeftTextEntry> entryByNode;
  final String _logical;

  int get length => _logical.length;

  /// The whole logical text of the document.
  String get text => _logical;

  static WeftTextIndex build({
    required WeftDocumentSnapshot document,
    required WeftStyleResolver styleResolver,
  }) {
    final entries = <WeftTextEntry>[];
    final buffer = StringBuffer();
    var globalStart = 0;
    var hardBreaks = 0;
    var blockBreakPending = false;
    var atLeadingEdge = true;
    var lastEmittedBreak = false;

    void emit(String text, NodeId nodeId) {
      if (text.isEmpty) return;
      var painted = text;
      if (hardBreaks == 0) {
        // Strip whitespace at the stream's leading edge and after breaks;
        // interior seams between nodes keep their whitespace because the
        // line boxes paint it. Trailing whitespace is removed after the
        // walk.
        if (atLeadingEdge || lastEmittedBreak) {
          painted = painted.replaceFirst(_leadingCollapsibleWhitespace, '');
        }
        if (painted.isEmpty) {
          // Pure whitespace before any content; the breaks stay pending.
          return;
        }
      }
      final breaks =
          hardBreaks + (blockBreakPending && buffer.isNotEmpty ? 1 : 0);
      if (breaks > 0 && buffer.isNotEmpty) {
        buffer.write('\n' * breaks);
        globalStart += breaks;
      }
      hardBreaks = 0;
      blockBreakPending = false;
      lastEmittedBreak = false;
      atLeadingEdge = false;
      entries.add(
        WeftTextEntry(nodeId: nodeId, text: painted, globalStart: globalStart),
      );
      buffer.write(painted);
      globalStart += painted.length;
    }

    void visit(
      WeftNode node,
      WeftComputedStyle style,
      List<WeftElement> ancestors,
    ) {
      if (node is WeftText) {
        final painted = style.whiteSpace == WeftWhiteSpace.normal
            ? node.text.replaceAll(_collapsibleWhitespace, ' ')
            : node.text;
        emit(painted, node.id);
        return;
      }
      if (node is! WeftElement) return;
      if (node.tag == 'br') {
        hardBreaks += 1;
        return;
      }
      final childAncestors = <WeftElement>[...ancestors, node];
      final childStyle = styleResolver.resolve(
        node,
        parent: style,
        ancestors: ancestors,
      );
      if (childStyle.display == WeftDisplay.none) return;
      if (childStyle.display != WeftDisplay.inline) {
        // Entering a block container breaks the inline run once, regardless
        // of how deeply blocks nest.
        blockBreakPending = true;
      }
      if (node.tag == 'img') {
        // Replaced content contributes no logical text.
        return;
      }
      for (final child in node.children) {
        visit(child, childStyle, childAncestors);
      }
    }

    final body = document.body;
    if (body != null) {
      visit(
        body,
        styleResolver.resolve(
          body,
          parent: WeftComputedStyle.initial,
          ancestors: const [],
        ),
        const [],
      );
    }

    // The stream's trailing whitespace never paints; drop it from the last
    // entry. Interior whitespace between nodes stays because the line boxes
    // paint it as the seam between runs.
    if (entries.isNotEmpty) {
      final last = entries.last;
      final trimmed =
          last.text.replaceFirst(_trailingCollapsibleWhitespace, '');
      if (trimmed.isEmpty) {
        entries.removeLast();
      } else if (trimmed.length != last.text.length) {
        entries[entries.length - 1] = WeftTextEntry(
          nodeId: last.nodeId,
          text: trimmed,
          globalStart: last.globalStart,
        );
      }
    }

    final logical = StringBuffer();
    var previousEnd = 0;
    for (final entry in entries) {
      final gaps = entry.globalStart - previousEnd;
      if (gaps > 0) logical.write('\n' * gaps);
      logical.write(entry.text);
      previousEnd = entry.globalEnd;
    }

    return WeftTextIndex._(
      List.unmodifiable(entries),
      Map.unmodifiable({for (final entry in entries) entry.nodeId: entry}),
      logical.toString(),
    );
  }

  /// Orders two anchors by document position, or null when either anchor
  /// cannot be located in this index.
  (TextAnchor, TextAnchor)? order(TextSelectionRange selection) {
    final startEntry = entryByNode[selection.anchor.nodeId];
    final endEntry = entryByNode[selection.extent.nodeId];
    if (startEntry == null || endEntry == null) return null;
    final anchorOrder = entries.indexOf(startEntry);
    final extentOrder = entries.indexOf(endEntry);
    final forward = anchorOrder < extentOrder ||
        (anchorOrder == extentOrder &&
            selection.anchor.offset <= selection.extent.offset);
    return forward
        ? (selection.anchor, selection.extent)
        : (selection.extent, selection.anchor);
  }

  /// Entries intersecting the ordered anchor range with clamped node-local
  /// offsets.
  Iterable<(WeftTextEntry, int, int)> between(
    TextAnchor start,
    TextAnchor end,
  ) sync* {
    final startEntry = entryByNode[start.nodeId];
    final endEntry = entryByNode[end.nodeId];
    if (startEntry == null || endEntry == null) return;
    final startIndex = entries.indexOf(startEntry);
    final endIndex = entries.indexOf(endEntry);
    if (startIndex < 0 || endIndex < 0 || startIndex > endIndex) return;
    final globalStart =
        startEntry.globalStart + start.offset.clamp(0, startEntry.text.length);
    final globalEnd =
        endEntry.globalStart + end.offset.clamp(0, endEntry.text.length);
    for (var index = startIndex; index <= endIndex; index++) {
      final entry = entries[index];
      if (entry.globalEnd <= globalStart || entry.globalStart >= globalEnd) {
        continue;
      }
      final nodeStart =
          (globalStart - entry.globalStart).clamp(0, entry.text.length).toInt();
      final nodeEnd =
          (globalEnd - entry.globalStart).clamp(0, entry.text.length).toInt();
      if (nodeEnd > nodeStart) {
        yield (entry, nodeStart, nodeEnd);
      }
    }
  }

  /// Logical text between two ordered anchors.
  String textBetween(TextAnchor start, TextAnchor end) {
    final startEntry = entryByNode[start.nodeId];
    final endEntry = entryByNode[end.nodeId];
    if (startEntry == null || endEntry == null) return '';
    final globalStart =
        startEntry.globalStart + start.offset.clamp(0, startEntry.text.length);
    final globalEnd =
        endEntry.globalStart + end.offset.clamp(0, endEntry.text.length);
    if (globalEnd <= globalStart) return '';
    return _logical.substring(globalStart, globalEnd);
  }
}
