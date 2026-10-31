import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'style_resolver.dart';

final RegExp _collapsibleWhitespace = RegExp(r'\s+');
final RegExp _leadingCollapsibleWhitespace = RegExp(r'^\s+');
final RegExp _trailingCollapsibleWhitespace = RegExp(r'\s+$');

/// One text node in the logical text stream, with the node's painted text
/// (whitespace collapsed for `white-space: normal`, raw otherwise).
final class WeftTextEntry {
  /// Creates an entry for one text node at [globalStart] in the stream.
  const WeftTextEntry({
    required this.nodeId,
    required this.text,
    required this.globalStart,
  });

  /// Id of the text node this entry was built from.
  final NodeId nodeId;

  /// The node's painted text, with whitespace collapsed when the node's
  /// style calls for it.
  final String text;

  /// Offset of this entry's text inside the logical stream.
  final int globalStart;

  /// Offset just past this entry's text in the logical stream.
  int get globalEnd => globalStart + text.length;
}

/// Emit state captured after each top-level body child during a walk, so an
/// incremental rebuild can resume from a verified prefix (ADR 0044).
final class _BlockCheckpoint {
  const _BlockCheckpoint({
    required this.entryCount,
    required this.nextGlobalStart,
    required this.hardBreaks,
    required this.blockBreakPending,
    required this.lastEmittedBreak,
    required this.atLeadingEdge,
  });

  /// Number of entries emitted up to this boundary.
  final int entryCount;

  /// Walk position of the global offset counter, including the boundary
  /// entry's untrimmed trailing whitespace and pending break advances.
  final int nextGlobalStart;

  /// `<br>` breaks seen but not yet consumed by an entry.
  final int hardBreaks;

  /// Whether a block boundary is still waiting to be written.
  final bool blockBreakPending;

  /// Whether the last entry ended a break run (always false today; carried
  /// so future emit-rule changes stay resume-safe).
  final bool lastEmittedBreak;

  /// Whether no content has been emitted yet.
  final bool atLeadingEdge;
}

/// Shared walk state for the full and incremental index builders. The two
/// paths run the same [emit], [visitNode] and [finish] code, so an
/// incremental rebuild is equivalent by construction and the equality tests
/// only have to pin the inputs (ADR 0044).
final class _TextIndexBuilder {
  _TextIndexBuilder(this.styleResolver);

  final WeftStyleResolver styleResolver;
  final List<WeftTextEntry> entries = [];
  final List<_BlockCheckpoint> checkpoints = [];
  var globalStart = 0;
  var hardBreaks = 0;
  var blockBreakPending = false;
  var atLeadingEdge = true;
  var lastEmittedBreak = false;
  var trailingTrimmedTail = '';
  WeftTextEntry? trailingRemovedEntry;

  /// Entries adopted from the previous index by an incremental build —
  /// verbatim for a reused prefix (ADR 0048), shifted and id-remapped for a
  /// carried suffix (ADR 0051); zero for a full build.
  var reusedEntryCount = 0;

  /// Adopts the reused prefix entries and resumes the walk state from
  /// [boundary], the checkpoint recorded at the end of the last reused
  /// top-level child.
  void adoptPrefix(
      List<WeftTextEntry> reusedEntries, _BlockCheckpoint boundary) {
    entries.addAll(reusedEntries);
    globalStart = boundary.nextGlobalStart;
    hardBreaks = boundary.hardBreaks;
    blockBreakPending = boundary.blockBreakPending;
    lastEmittedBreak = boundary.lastEmittedBreak;
    atLeadingEdge = boundary.atLeadingEdge;
  }

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
        hardBreaks + (blockBreakPending && entries.isNotEmpty ? 1 : 0);
    if (breaks > 0 && entries.isNotEmpty) {
      globalStart += breaks;
    }
    hardBreaks = 0;
    blockBreakPending = false;
    lastEmittedBreak = false;
    atLeadingEdge = false;
    entries.add(
      WeftTextEntry(nodeId: nodeId, text: painted, globalStart: globalStart),
    );
    globalStart += painted.length;
  }

  void visitNode(
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
      visitNode(child, childStyle, childAncestors);
    }
  }

  /// Walks the body's children, resolving the body itself first, and
  /// records one checkpoint per child for incremental resumes.
  void visitBodyChildren(WeftElement body) {
    final bodyStyle = styleResolver.resolve(
      body,
      parent: WeftComputedStyle.initial,
      ancestors: const [],
    );
    if (bodyStyle.display == WeftDisplay.none) return;
    if (bodyStyle.display != WeftDisplay.inline) {
      blockBreakPending = true;
    }
    for (final child in body.children) {
      visitNode(child, bodyStyle, [body]);
      _recordCheckpoint();
    }
  }

  void _recordCheckpoint() {
    checkpoints.add(
      _BlockCheckpoint(
        entryCount: entries.length,
        nextGlobalStart: globalStart,
        hardBreaks: hardBreaks,
        blockBreakPending: blockBreakPending,
        lastEmittedBreak: lastEmittedBreak,
        atLeadingEdge: atLeadingEdge,
      ),
    );
  }

  /// Applies the trailing-whitespace trim and joins the logical stream.
  WeftTextIndex finish() {
    if (entries.isNotEmpty) {
      final last = entries.last;
      final trimmed =
          last.text.replaceFirst(_trailingCollapsibleWhitespace, '');
      if (trimmed.isEmpty) {
        // The last entry is pure whitespace; keep it aside so an
        // incremental rebuild can restore it when content follows.
        trailingRemovedEntry = last;
        entries.removeLast();
      } else if (trimmed.length != last.text.length) {
        trailingTrimmedTail = last.text.substring(trimmed.length);
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
      List.unmodifiable(checkpoints),
      trailingTrimmedTail,
      trailingRemovedEntry,
      reusedEntryCount,
    );
  }
}

/// The logical text model of one document snapshot.
///
/// Anchors address a text node and an offset inside the node's painted
/// text. Entries are joined with newlines: every `<br>` contributes one,
/// and a block boundary contributes one (idempotently across nested block
/// containers). The model is rebuilt for every layout result and never
/// outlives its snapshot, so anchors that cannot be mapped after a content
/// change are dropped rather than clamped (see ADR 0013). Streaming
/// snapshots rebuild it incrementally from the previous snapshot's index
/// when the layout's block diff proves a prefix unchanged (ADR 0044).
final class WeftTextIndex {
  const WeftTextIndex._(
    this.entries,
    this.entryByNode,
    this._logical,
    this._checkpoints,
    this._trailingTrimmedTail,
    this._trailingRemovedEntry,
    this._reusedEntryCount,
  );

  /// Text entries in reading order.
  final List<WeftTextEntry> entries;

  /// Maps each text node id to its entry in [entries].
  final Map<NodeId, WeftTextEntry> entryByNode;
  final String _logical;
  final List<_BlockCheckpoint> _checkpoints;
  final String _trailingTrimmedTail;
  final WeftTextEntry? _trailingRemovedEntry;
  final int _reusedEntryCount;

  /// Entries adopted from the previous snapshot's index by an incremental
  /// build — verbatim for a reused prefix (ADR 0048), shifted and
  /// id-remapped for a carried suffix (ADR 0051). Hosts cannot consume this
  /// directly; the profile tool and tests read it to pin which rebuild path
  /// ran. Zero when the index came from a full build.
  int get debugReusedEntryCount => _reusedEntryCount;

  /// Length of the logical text stream in UTF-16 code units.
  int get length => _logical.length;

  /// The whole logical text of the document.
  String get text => _logical;

  /// Number of per-top-level-child checkpoints recorded by the walk. Hosts
  /// cannot consume checkpoints directly; the layout engine compares this
  /// count against the previous snapshot's body children to prove the
  /// reused prefix aligns before building incrementally.
  int get checkpointCount => _checkpoints.length;

  /// Builds the index for one document snapshot by walking its body.
  ///
  /// The [styleResolver] decides which nodes are hidden and how their text
  /// is painted; block boundaries and `<br>` elements contribute the
  /// newlines that join entries in the logical stream.
  static WeftTextIndex build({
    required WeftDocumentSnapshot document,
    required WeftStyleResolver styleResolver,
  }) {
    final builder = _TextIndexBuilder(styleResolver);
    final body = document.body;
    if (body != null) {
      builder.visitBodyChildren(body);
    }
    return builder.finish();
  }

  /// Builds the index for a streaming snapshot by reusing the previous
  /// snapshot's entries for the verified prefix and walking only the
  /// suffix.
  ///
  /// [reusedTopLevelBlocks] is the count of leading body children the
  /// layout engine's block diff proved unchanged between the snapshots
  /// (`_sameNode` over every descendant, so node ids, text and attributes
  /// of the reused entries are identical by construction). The previous
  /// index must come from the same document identity and stylesheet, must
  /// carry one checkpoint per previous body child, and the engine only
  /// engages this path when its raw diff prefix is non-empty; any other
  /// caller should use [build] — an incorrect [reusedTopLevelBlocks]
  /// silently corrupts the logical offsets. Because the previous index
  /// trimmed (or dropped) the stream's trailing whitespace, the reused
  /// range is restored to its untrimmed form first and this build's own
  /// trim re-applies at the new end, which also makes an incremental
  /// rebuild of a byte-identical snapshot equal the previous index.
  ///
  /// The previous index's per-child checkpoints are carried over for the
  /// reused range, so the result again carries one checkpoint per body
  /// child and chained streaming rounds keep engaging this path (ADR 0048).
  static WeftTextIndex buildIncremental({
    required WeftDocumentSnapshot document,
    required WeftStyleResolver styleResolver,
    required WeftTextIndex previous,
    required int reusedTopLevelBlocks,
  }) {
    assert(reusedTopLevelBlocks >= 1, 'the diff prefix must be non-empty');
    assert(
      reusedTopLevelBlocks <= previous._checkpoints.length,
      'the reused prefix must be covered by the previous checkpoints',
    );
    final body = document.body;
    assert(body != null, 'the index needs a body');
    final builder = _TextIndexBuilder(styleResolver);
    final boundary = previous._checkpoints[reusedTopLevelBlocks - 1];
    final reused = previous.entries.take(boundary.entryCount).toList();
    // The reused range contains the previous document's final entry when it
    // reaches the stream's end — either because every child is reused, or
    // because the children past the boundary emitted nothing (hidden or
    // empty blocks). That final entry's trailing whitespace finish()
    // trimmed away, or its whitespace-only text finish() dropped entirely,
    // must be restored: mid-stream it is interior whitespace, and the
    // boundary's nextGlobalStart already counted it (ADR 0048).
    final streamEndEntryCount = previous.entries.length +
        (previous._trailingRemovedEntry != null ? 1 : 0);
    final restoresTail = reusedTopLevelBlocks == previous._checkpoints.length ||
        boundary.entryCount >= streamEndEntryCount;
    if (restoresTail) {
      if (previous._trailingRemovedEntry != null) {
        reused.add(previous._trailingRemovedEntry);
      } else if (previous._trailingTrimmedTail.isNotEmpty &&
          reused.isNotEmpty) {
        final last = reused.last;
        reused[reused.length - 1] = WeftTextEntry(
          nodeId: last.nodeId,
          text: last.text + previous._trailingTrimmedTail,
          globalStart: last.globalStart,
        );
      }
    }
    builder.reusedEntryCount = boundary.entryCount;
    builder.adoptPrefix(reused, boundary);
    // The diff proved the reused children unchanged, so their walk state is
    // the previous build's; carrying the checkpoints keeps one per body
    // child, which is what lets the next streaming round reuse again.
    builder.checkpoints
        .addAll(previous._checkpoints.take(reusedTopLevelBlocks));
    final bodyStyle = styleResolver.resolve(
      body!,
      parent: WeftComputedStyle.initial,
      ancestors: const [],
    );
    // The body container itself was entered while building the reused
    // prefix, so its block break is already reflected in the boundary
    // state; only the suffix children are walked here.
    assert(bodyStyle.display != WeftDisplay.none);
    for (var i = reusedTopLevelBlocks; i < body.children.length; i++) {
      builder.visitNode(body.children[i], bodyStyle, [body]);
      builder._recordCheckpoint();
    }
    return builder.finish();
  }

  /// Builds the index for a streaming snapshot whose change sits at the
  /// head: the layout engine's backward diff proved the trailing body
  /// children unchanged (ADR 0046), so their previous entries are adopted
  /// with their logical offsets shifted past the fresh head walk and their
  /// node ids re-mapped into the new document (ADR 0051).
  ///
  /// [carriedTopLevelBlocks] is the count of trailing raw body children the
  /// diff proved shape-identical (`_sameNodeShape`, which ignores node ids
  /// because a head change shifts every pre-order id). The carried children
  /// are considered one at a time: adoption starts at the first child whose
  /// seam — the walk state entering it — matches the previous build's
  /// checkpoint flag for flag. The flags decide because they are the only
  /// state that changes how a child emits (leading-edge whitespace
  /// stripping, pending break payment, hard-break runs): given equal flags
  /// and diff-proven equal content, the child and everything after it emit
  /// exactly the previous build's entries shifted by one constant offset.
  /// A mismatch is re-walked fresh instead — the stream's leading edge is
  /// the one state that cannot be adopted across, because the previous
  /// build stripped its first entry's leading whitespace and this build
  /// (whose head already emitted) must not — and the next seam is compared
  /// against the just-walked child's checkpoint. Walking every carried
  /// child degrades to exactly [build], so the fallback is the full build
  /// itself, never a divergence.
  ///
  /// [shiftedIds] maps every adopted entry's old node id to its new id; the
  /// adopted range consists solely of diff-proven element subtrees whose
  /// every node the diff paired, so the mapping is total over it by
  /// construction (asserted). An incorrect [carriedTopLevelBlocks] or an
  /// incomplete [shiftedIds] silently corrupts the logical offsets — only
  /// the layout engine's backward diff may drive this path; any other
  /// caller should use [build].
  ///
  /// Like [buildIncremental], the previous index's trailing-trim state is
  /// restored before this build's own trim re-applies at the same stream
  /// end, and the adopted checkpoints keep one checkpoint per body child so
  /// the next streaming round can reuse again.
  static WeftTextIndex buildFromSuffix({
    required WeftDocumentSnapshot document,
    required WeftStyleResolver styleResolver,
    required WeftTextIndex previous,
    required int carriedTopLevelBlocks,
    required Map<int, int> shiftedIds,
  }) {
    assert(carriedTopLevelBlocks >= 1, 'the diff suffix must be non-empty');
    assert(
      carriedTopLevelBlocks <= previous._checkpoints.length,
      'the carried suffix must be covered by the previous checkpoints',
    );
    final body = document.body;
    assert(body != null, 'the index needs a body');
    final previousChildren = previous._checkpoints.length;
    final freshCount = body!.children.length - carriedTopLevelBlocks;
    final builder = _TextIndexBuilder(styleResolver);
    final bodyStyle = styleResolver.resolve(
      body,
      parent: WeftComputedStyle.initial,
      ancestors: const [],
    );
    assert(bodyStyle.display != WeftDisplay.none);
    // Mirror visitBodyChildren: entering a non-inline body opens the block
    // run before the first child, so the head walk's checkpoints record the
    // same pending state a canonical build would and the next round's
    // prefix adoption resumes from a faithful state.
    if (bodyStyle.display != WeftDisplay.inline) {
      builder.blockBreakPending = true;
    }
    void walkChild(WeftNode child) {
      builder.visitNode(child, bodyStyle, [body]);
      builder._recordCheckpoint();
    }

    for (var i = 0; i < freshCount; i++) {
      walkChild(body.children[i]);
    }
    for (var j = 0; j < carriedTopLevelBlocks; j++) {
      // The seam entering carried child j: the previous build's state after
      // its child at the paired position, or the builder's own initial
      // state (with the body's block break applied) when the carried range
      // covers the previous stream from its very first child.
      final seamIndex = previousChildren - carriedTopLevelBlocks + j - 1;
      final seam = seamIndex < 0 ? null : previous._checkpoints[seamIndex];
      final matches = builder.hardBreaks == (seam?.hardBreaks ?? 0) &&
          builder.blockBreakPending ==
              (seam?.blockBreakPending ??
                  bodyStyle.display != WeftDisplay.inline) &&
          builder.lastEmittedBreak == (seam?.lastEmittedBreak ?? false) &&
          builder.atLeadingEdge == (seam?.atLeadingEdge ?? true);
      if (!matches) {
        walkChild(body.children[freshCount + j]);
        continue;
      }
      final seamEntryCount = seam?.entryCount ?? 0;
      final delta = builder.globalStart - (seam?.nextGlobalStart ?? 0);
      final streamEndEntryCount = previous.entries.length +
          (previous._trailingRemovedEntry != null ? 1 : 0);
      // The adopted range always reaches the previous stream's end, so the
      // trailing-trim restore applies whenever the range is non-empty (the
      // mirror of buildIncremental's restoresTail, ADR 0048). When the
      // range is empty the trimmed tail belonged to content before the
      // seam, which this build re-walked or discarded — restoring it would
      // duplicate text the canonical build does not have.
      final freshEntryCount = builder.entries.length;
      var adoptedCount = 0;
      for (var i = seamEntryCount; i < streamEndEntryCount; i++) {
        final entry = i < previous.entries.length
            ? previous.entries[i]
            : previous._trailingRemovedEntry!;
        final newId = shiftedIds[entry.nodeId];
        assert(
          newId != null,
          'adopted entries live in the diff-proven subtrees, whose node '
          'ids the diff remapped',
        );
        final isStreamEnd = i == streamEndEntryCount - 1;
        final restoredTail = isStreamEnd &&
            previous._trailingRemovedEntry == null &&
            previous._trailingTrimmedTail.isNotEmpty;
        builder.entries.add(
          WeftTextEntry(
            nodeId: newId!,
            text: restoredTail
                ? entry.text + previous._trailingTrimmedTail
                : entry.text,
            globalStart: entry.globalStart + delta,
          ),
        );
        adoptedCount++;
      }
      builder.reusedEntryCount = adoptedCount;
      // The adopted children's checkpoints shift with the entries; carrying
      // them keeps one checkpoint per body child, which is what lets the
      // next streaming round reuse again (ADR 0048).
      for (var c = seamIndex + 1; c < previousChildren; c++) {
        final old = previous._checkpoints[c];
        builder.checkpoints.add(
          _BlockCheckpoint(
            entryCount: freshEntryCount + (old.entryCount - seamEntryCount),
            nextGlobalStart: old.nextGlobalStart + delta,
            hardBreaks: old.hardBreaks,
            blockBreakPending: old.blockBreakPending,
            lastEmittedBreak: old.lastEmittedBreak,
            atLeadingEdge: old.atLeadingEdge,
          ),
        );
      }
      // Nothing walks after the adoption, but leave the builder's state at
      // the shifted stream end instead of a stale seam value.
      final last = previous._checkpoints[previousChildren - 1];
      builder.globalStart = last.nextGlobalStart + delta;
      builder.hardBreaks = last.hardBreaks;
      builder.blockBreakPending = last.blockBreakPending;
      builder.lastEmittedBreak = last.lastEmittedBreak;
      builder.atLeadingEdge = last.atLeadingEdge;
      break;
    }
    return builder.finish();
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
