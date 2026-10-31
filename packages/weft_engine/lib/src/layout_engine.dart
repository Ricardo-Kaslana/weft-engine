import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:weft_document/weft_document.dart';

import 'computed_style.dart';
import 'layout_result.dart';
import 'line_break_rules.dart';
import 'style_resolver.dart';
import 'tag_renderer.dart';
import 'text_index.dart';

part 'inline_flow.part.dart';
part 'lazy_layout.part.dart';
part 'table_layout.part.dart';

/// Lays out a normalized document snapshot into paint commands, boxes and
/// link/tag regions.
///
/// The engine is immutable and stateless: all inputs come from the arguments
/// and all outputs are returned in a [WeftLayoutResult]. Prefer [layout] for
/// full-document layouts and [layoutViewport] for progressive lazy layout.
final class WeftLayoutEngine {
  /// Creates an engine with the given custom tag renderers.
  const WeftLayoutEngine(
      {this.tagRenderers = const <String, WeftTagRenderer>{}});

  /// Trusted renderers for custom tags. A normalized custom tag without a
  /// renderer lays out as an empty block; hosts keep this map in sync with
  /// `WeftNormalizer.customTags` (ADR 0033).
  final Map<String, WeftTagRenderer> tagRenderers;

  /// Reuses unchanged top-level blocks from [previous] when all inputs match.
  /// Dispose [previous] after this call; a result that transferred commands
  /// cannot seed another incremental layout.
  WeftLayoutResult layout(
    WeftDocumentSnapshot document, {
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
    Map<int, ui.Image> images = const {},
    WeftLineBreakRules lineBreakRules = const WeftLineBreakRules(),
    WeftLayoutResult? previous,
  }) {
    return _layoutDocument(
      document,
      width: width,
      textScaler: textScaler,
      images: images,
      lineBreakRules: lineBreakRules,
      previous: previous,
    );
  }

  /// Lays out only the blocks intersecting the viewport extent, for hosts
  /// that drive progressive lazy layout themselves.
  ///
  /// Blocks fully outside `[viewportStart, viewportEnd)` are estimated rather
  /// than laid out, so the result's total height is approximate until the
  /// host scrolls them into view and lays them out. Pass [focusNodeId] when
  /// jumping to an anchor so its block is always laid out, and [maxNewBlocks]
  /// to bound the synchronous work per call.
  WeftLayoutResult layoutViewport(
    WeftDocumentSnapshot document, {
    required double width,
    required double viewportStart,
    required double viewportEnd,
    NodeId? focusNodeId,
    int? maxNewBlocks,
    TextScaler textScaler = TextScaler.noScaling,
    Map<int, ui.Image> images = const {},
    WeftLineBreakRules lineBreakRules = const WeftLineBreakRules(),
    WeftLayoutResult? previous,
  }) {
    return _layoutDocument(
      document,
      width: width,
      textScaler: textScaler,
      images: images,
      lineBreakRules: lineBreakRules,
      previous: previous,
      viewportStart: viewportStart,
      viewportEnd: viewportEnd,
      focusNodeId: focusNodeId,
      maxNewBlocks: maxNewBlocks,
    );
  }

  WeftLayoutResult _layoutDocument(
    WeftDocumentSnapshot document, {
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
    Map<int, ui.Image> images = const {},
    WeftLineBreakRules lineBreakRules = const WeftLineBreakRules(),
    WeftLayoutResult? previous,
    double? viewportStart,
    double? viewportEnd,
    NodeId? focusNodeId,
    int? maxNewBlocks,
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

    // Computed styles and the logical text index depend only on the snapshot
    // (its stylesheet and text are part of it), never on width, text scaling
    // or images. When the snapshot instance is unchanged, the previous
    // result's caches stay valid and the relayout skips their O(document)
    // rebuilds; a streaming snapshot rebuilds the text index incrementally
    // from the block diff's verified prefix (ADR 0044) and falls back to the
    // full build whenever that prefix cannot be trusted.
    final previousCache = previous?.incrementalCache;
    final sameSnapshot =
        previousCache != null && identical(previousCache.document, document);
    final styleCache = sameSnapshot
        ? previousCache.styleCache
        : <WeftElement, WeftComputedStyle>{};
    final styleResolver = WeftStyleResolver(
      document.styleSheet,
      customTags: tagRenderers.keys.toSet(),
    );
    final reusableState = viewportStart != null &&
            viewportEnd != null &&
            sameSnapshot &&
            previousCache.viewportState is _LazyLayoutState &&
            _sameLayoutInputs(previousCache, width, textScaler, images,
                lineBreakRules, tagRenderers)
        ? previousCache.viewportState as _LazyLayoutState
        : null;
    var eligibilityVisits = 0;
    final lazy = viewportStart != null &&
        viewportEnd != null &&
        (reusableState != null ||
            _supportsLazyLayout(
              document: document,
              styleResolver: styleResolver,
              images: images,
              styleCache: styleCache,
              onVisit: () => eligibilityVisits++,
            ));
    final _ReusableBlockMaps reusedMaps = reusableState != null
        ? const (
            prefix: <int, WeftCachedLayoutBlock>{},
            suffix: <int, WeftCachedLayoutBlock>{},
            ids: <int, int>{},
          )
        : _reusableLayoutBlocks(
            document: document,
            previous: previous,
            width: width,
            textScaler: textScaler,
            images: images,
            lineBreakRules: lineBreakRules,
            allowLazy: lazy,
            tagRenderers: tagRenderers,
          );
    final context = _LayoutContext(
      styleResolver: styleResolver,
      textScaler: textScaler,
      images: images,
      lineBreakRules: lineBreakRules,
      body: body,
      reusableBlocks: reusedMaps.prefix,
      suffixBlocks: reusedMaps.suffix,
      suffixIds: reusedMaps.ids,
      viewportStart: lazy ? viewportStart : null,
      viewportEnd: lazy ? viewportEnd : null,
      focusOrdinal: lazy && focusNodeId != null
          ? WeftChunk.topLevelOrdinalForNode(document, focusNodeId)
          : null,
      maxNewBlocks: lazy ? maxNewBlocks : null,
      styleCache: styleCache,
      tagRenderers: tagRenderers,
      lazyState: reusableState,
    );
    final reusedTextIndex = sameSnapshot ? previous?.textIndex : null;
    final textIndex = reusedTextIndex ??
        _incrementalTextIndex(
          document: document,
          body: body,
          styleResolver: context.styleResolver,
          previousCache: previousCache,
          previous: previous,
          reusableBlocks: reusedMaps.prefix,
        ) ??
        WeftTextIndex.build(
          document: document,
          styleResolver: context.styleResolver,
        );
    final bodyStyle = context.styleFor(
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
    final viewportState = context.lazyState;
    final cachedBlocks = viewportState?.blocks ?? context.topLevelBlocks;

    final result = WeftLayoutResult(
      size: Size(
        width,
        math.max(
            normalBottom, viewportState?.floats.maxBottom ?? floats.maxBottom),
      ),
      boxes: context.boxes,
      commands: context.commands,
      links: context.links,
      tagRegions: context.tagRegions,
      textIndex: textIndex,
      debugReusedBlockCount: context.reusedBlockCount,
      debugLaidOutBlockCount:
          lazy ? context.laidOutBlockCount : context.topLevelBlocks.length,
      debugMaterializedBlockCount:
          lazy ? context.materializedBlockCount : context.topLevelBlocks.length,
      debugVisitedBlockCount: context.visitedBlockCount,
      debugEstimatedBlockCount: context.estimatedBlockCount,
      debugEligibilityVisitCount: eligibilityVisits,
      debugIsLazy: lazy,
    );
    if (lazy && !context.topLevelCacheEligible) {
      if (context.reusedCommands.isNotEmpty) {
        previous?.transferCommands(context.reusedCommands);
      }
      result.dispose();
      return _layoutDocument(
        document,
        width: width,
        textScaler: textScaler,
        images: images,
        lineBreakRules: lineBreakRules,
        previous: previous,
      );
    }
    if (context.topLevelCacheEligible &&
        (lazy || !floats.hasExclusions) &&
        (lazy || context.topLevelBlocks.length == body.children.length)) {
      result.incrementalCache = WeftIncrementalLayoutCache(
        document: document,
        width: width,
        textScaler: textScaler,
        images: images,
        lineBreakRules: lineBreakRules,
        blocks: cachedBlocks,
        measuredPrefixLength: cachedBlocks.length,
        isLazy: lazy,
        estimatedExtent: result.size.height,
        tagRenderers: tagRenderers,
        styleCache: context.styleCache,
        viewportState: viewportState,
      );
    }
    if (context.reusedCommands.isNotEmpty || reusableState != null) {
      previous?.transferCommands(context.reusedCommands);
    }
    return result;
  }
}

/// Builds the streaming snapshot's text index from the previous index's
/// verified prefix, or returns null when that prefix cannot be trusted and
/// the caller must fall back to the full build (ADR 0044).
///
/// The block diff in [reusableBlocks] verified its prefix by recursive
/// `_sameNode` comparison, which covers every descendant's id, text and
/// attributes; the entry model is a pure function of exactly those inputs
/// plus the stylesheet (already signature-compared before the diff ran),
/// and never of geometry — so whether the previous cache measured the
/// whole body or just a lazy window does not matter (ADR 0048). What must
/// align is the index side: the previous index carries one checkpoint per
/// previous body child, and the count below walks the new body's raw
/// children, stopping at the first one the diff did not map — body-level
/// whitespace only costs reuse (a shorter prefix or the full build), never
/// correctness. A head insert maps no children and stays a full build.
WeftTextIndex? _incrementalTextIndex({
  required WeftDocumentSnapshot document,
  required WeftElement body,
  required WeftStyleResolver styleResolver,
  required WeftIncrementalLayoutCache? previousCache,
  required WeftLayoutResult? previous,
  required Map<int, WeftCachedLayoutBlock> reusableBlocks,
}) {
  if (previousCache == null || reusableBlocks.isEmpty) return null;
  final previousBody = previousCache.document.body;
  final previousIndex = previous?.textIndex;
  if (previousBody == null || previousIndex == null) return null;
  final previousChildren = previousBody.children.length;
  if (previousIndex.checkpointCount != previousChildren) {
    return null;
  }
  var reused = 0;
  for (final child in body.children) {
    if (!reusableBlocks.containsKey(child.id)) break;
    reused++;
  }
  if (reused == 0 || reused > previousIndex.checkpointCount) return null;
  return WeftTextIndex.buildIncremental(
    document: document,
    styleResolver: styleResolver,
    previous: previousIndex,
    reusedTopLevelBlocks: reused,
  );
}

bool _sameLayoutInputs(
  WeftIncrementalLayoutCache cache,
  double width,
  TextScaler textScaler,
  Map<int, ui.Image> images,
  WeftLineBreakRules lineBreakRules,
  Map<String, WeftTagRenderer> tagRenderers,
) {
  return cache.width == width &&
      cache.textScaler == textScaler &&
      identical(cache.tagRenderers, tagRenderers) &&
      _sameImages(cache.images, images) &&
      _sameInts(cache.lineBreakRules.lineStartProhibited,
          lineBreakRules.lineStartProhibited) &&
      _sameInts(cache.lineBreakRules.lineEndProhibited,
          lineBreakRules.lineEndProhibited);
}

/// The block diff's reusable maps: [prefix] holds the continuous forward
/// match (`newChild.id -> old block`, positions and node ids expected
/// unchanged) and [suffix] the backward match past the changed region —
/// content-identical blocks the walk may reuse shifted by one shared
/// vertical delta. Node ids are pre-order positions, so any node-count
/// change in the middle shifts every suffix id: [ids] maps each suffix
/// node's old id to its new id and the shifted clones re-map their nodeIds
/// through it (ADR 0046).
typedef _ReusableBlockMaps = ({
  Map<int, WeftCachedLayoutBlock> prefix,
  Map<int, WeftCachedLayoutBlock> suffix,
  Map<int, int> ids,
});

_ReusableBlockMaps _reusableLayoutBlocks({
  required WeftDocumentSnapshot document,
  required WeftLayoutResult? previous,
  required double width,
  required TextScaler textScaler,
  required Map<int, ui.Image> images,
  required WeftLineBreakRules lineBreakRules,
  bool allowLazy = false,
  Map<String, WeftTagRenderer> tagRenderers = const <String, WeftTagRenderer>{},
}) {
  final cache = previous?.incrementalCache;
  if (cache != null && !identical(cache.tagRenderers, tagRenderers)) {
    // A different renderer set may paint custom tags differently; cached
    // blocks cannot be reused across the change.
    return const (prefix: {}, suffix: {}, ids: {});
  }
  final oldBody = cache?.document.body;
  final newBody = document.body;
  // An unchanged snapshot instance carries its stylesheet and body, so the
  // recursive node diff and the stylesheet signature comparison are trivially
  // satisfied and skipped. A new snapshot (streaming update) still pays for
  // the full comparison.
  final sameSnapshot = cache != null && identical(cache.document, document);
  if (cache == null ||
      (cache.isLazy && !allowLazy) ||
      oldBody == null ||
      newBody == null ||
      cache.document.id != document.id ||
      cache.width != width ||
      cache.textScaler != textScaler ||
      (!sameSnapshot &&
          !_sameStyleSheet(cache.document.styleSheet, document.styleSheet)) ||
      (!sameSnapshot && !_sameNodeShell(oldBody, newBody)) ||
      !_sameImages(cache.images, images) ||
      !_sameInts(
        cache.lineBreakRules.lineStartProhibited,
        lineBreakRules.lineStartProhibited,
      ) ||
      !_sameInts(
        cache.lineBreakRules.lineEndProhibited,
        lineBreakRules.lineEndProhibited,
      ) ||
      cache.blocks.length != cache.measuredPrefixLength ||
      (!allowLazy && cache.blocks.length != oldBody.children.length)) {
    return const (prefix: {}, suffix: {}, ids: {});
  }

  final prefix = <int, WeftCachedLayoutBlock>{};
  final oldChildren = allowLazy
      ? oldBody.children.whereType<WeftElement>().toList()
      : oldBody.children;
  final newChildren = allowLazy
      ? newBody.children.whereType<WeftElement>().toList()
      : newBody.children;
  final count = math.min(cache.blocks.length, newChildren.length);
  for (var i = 0; i < count; i++) {
    final oldChild = oldChildren[i];
    final newChild = newChildren[i];
    final block = cache.blocks[i];
    if (oldChild is! WeftElement || newChild is! WeftElement) {
      break;
    }
    if (!sameSnapshot &&
        (!_sameNode(oldChild, newChild) ||
            !identical(block.element, oldChild))) {
      break;
    }
    prefix[newChild.id] = block;
  }

  // Suffix translation (ADR 0046): a second, backward pass maps unchanged
  // trailing blocks past the change so the walk can reuse them shifted by
  // one vertical delta instead of re-measuring them. Plain passes only —
  // lazy seeding consumes the map as a continuous prefix and must not see
  // entries after a gap. Every old block is mapped at most once: the scan
  // stops where the forward match ends (k = prefix.length), so the two maps
  // never share a new id.
  final suffix = <int, WeftCachedLayoutBlock>{};
  final suffixIds = <int, int>{};
  if (!allowLazy && !sameSnapshot) {
    var oldIndex = oldChildren.length - 1;
    var newIndex = newChildren.length - 1;
    final stop = prefix.length;
    while (oldIndex >= stop && newIndex >= stop) {
      final oldChild = oldChildren[oldIndex];
      final newChild = newChildren[newIndex];
      if (oldChild is! WeftElement || newChild is! WeftElement) {
        break;
      }
      if (oldChild.tag == 'li' || newChild.tag == 'li') {
        // Ordered-list markers are the one cross-block counter; their
        // numbers are baked into the cached commands, so a shifted li
        // could renumber wrongly.
        break;
      }
      final block = cache.blocks[oldIndex];
      if (!identical(block.element, oldChild)) {
        break;
      }
      // Node ids shift with the middle's node count, so the pair compares
      // shape only and collects the old->new id mapping the shifted clones
      // need (ADR 0046).
      final pairIds = <int, int>{};
      if (!_sameNodeShape(oldChild, newChild, pairIds)) {
        break;
      }
      suffix[newChild.id] = block;
      suffixIds.addAll(pairIds);
      oldIndex--;
      newIndex--;
    }
  }
  return (prefix: prefix, suffix: suffix, ids: suffixIds);
}

/// Shape equality of two subtrees, ignoring node ids (which are pre-order
/// positions and shift with the changed middle) while collecting the
/// old->new id pairs into [ids]. Mirrors `_sameNode`'s field comparisons
/// exactly otherwise.
bool _sameNodeShape(
  WeftNode first,
  WeftNode second,
  Map<int, int> ids,
) {
  if (first is WeftText && second is WeftText) {
    if (first.text != second.text) return false;
    ids[first.id] = second.id;
    return true;
  }
  if (first is! WeftElement || second is! WeftElement) return false;
  if (first.tag != second.tag ||
      !_sameStrings(first.attributes, second.attributes) ||
      !_sameStrings(first.inlineStyle, second.inlineStyle) ||
      first.children.length != second.children.length) {
    return false;
  }
  ids[first.id] = second.id;
  for (var i = 0; i < first.children.length; i++) {
    if (!_sameNodeShape(first.children[i], second.children[i], ids)) {
      return false;
    }
  }
  return true;
}

bool _sameNode(WeftNode first, WeftNode second) {
  if (first.id != second.id) return false;
  if (first is WeftText && second is WeftText) {
    return first.text == second.text;
  }
  if (first is! WeftElement || second is! WeftElement) return false;
  if (!_sameNodeShell(first, second) ||
      first.children.length != second.children.length) {
    return false;
  }
  for (var i = 0; i < first.children.length; i++) {
    if (!_sameNode(first.children[i], second.children[i])) return false;
  }
  return true;
}

bool _sameNodeShell(WeftElement first, WeftElement second) {
  return first.id == second.id &&
      first.tag == second.tag &&
      _sameStrings(first.attributes, second.attributes) &&
      _sameStrings(first.inlineStyle, second.inlineStyle);
}

bool _sameStrings(Map<String, String> first, Map<String, String> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}

bool _sameImages(Map<int, ui.Image> first, Map<int, ui.Image> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    final other = second[entry.key];
    if (!identical(entry.value, other) ||
        entry.value.width != other?.width ||
        entry.value.height != other?.height) {
      return false;
    }
  }
  return true;
}

bool _sameInts(Set<int> first, Set<int> second) {
  return first.length == second.length && first.containsAll(second);
}

bool _sameStyleSheet(WeftStyleSheet first, WeftStyleSheet second) {
  return _styleSheetSignature(first) == _styleSheetSignature(second);
}

String _styleSheetSignature(WeftStyleSheet sheet) {
  final result = StringBuffer();
  for (final rule in sheet.rules) {
    result.write('${rule.order}{');
    for (final selector in rule.selectors) {
      for (var i = 0; i < selector.parts.length; i++) {
        if (i > 0) result.write(selector.combinators[i - 1].name);
        final part = selector.parts[i];
        final classes = part.classes.toList()..sort();
        result.write('${part.tag}|${part.id}|${classes.join(',')};');
      }
      result.write('/');
    }
    final keys = rule.declarations.keys.toList()..sort();
    for (final key in keys) {
      result.write('$key:${rule.declarations[key]};');
    }
    result.write('}');
  }
  return result.toString();
}

bool _supportsLazyLayout({
  required WeftDocumentSnapshot document,
  required WeftStyleResolver styleResolver,
  required Map<int, ui.Image> images,
  required Map<WeftElement, WeftComputedStyle> styleCache,
  required void Function() onVisit,
}) {
  final body = document.body;
  if (body == null) return false;

  WeftComputedStyle resolve(
    WeftElement element, {
    required WeftComputedStyle parent,
    required List<WeftElement> ancestors,
  }) {
    final cached = styleCache[element];
    if (cached != null) return cached;
    final style = styleResolver.resolve(
      element,
      parent: parent,
      ancestors: ancestors,
    );
    styleCache[element] = style;
    return style;
  }

  bool visit(
    WeftElement element,
    WeftComputedStyle parent,
    List<WeftElement> ancestors,
    bool underInlineAncestor,
  ) {
    onVisit();
    final style = resolve(
      element,
      parent: parent,
      ancestors: ancestors,
    );
    if (style.display == WeftDisplay.none) return false;
    if (style.float != WeftFloat.none) {
      if (element.tag != 'img' ||
          images[element.id] == null ||
          underInlineAncestor) {
        return false;
      }
    }
    if (element.tag == 'img' && images[element.id] == null) return false;
    final childAncestors = <WeftElement>[...ancestors, element];
    final childrenUnderInline =
        underInlineAncestor || style.display == WeftDisplay.inline;
    for (final child in element.children) {
      if (child is WeftText && identical(element, body)) {
        if (style.whiteSpace != WeftWhiteSpace.normal ||
            !RegExp(r'^[ \t\r\n\f]*$').hasMatch(child.text)) return false;
        continue;
      }
      if (child is! WeftElement) continue;
      if (identical(element, body)) {
        final childStyle = resolve(
          child,
          parent: style,
          ancestors: childAncestors,
        );
        if (childStyle.display == WeftDisplay.inline &&
            childStyle.float == WeftFloat.none) {
          return false;
        }
      }
      if (!visit(child, style, childAncestors, childrenUnderInline)) {
        return false;
      }
    }
    return true;
  }

  return visit(body, WeftComputedStyle.initial, const [], false);
}

final class _LayoutContext {
  _LayoutContext({
    required this.styleResolver,
    required this.textScaler,
    required this.images,
    required this.body,
    required this.reusableBlocks,
    required this.suffixBlocks,
    required this.suffixIds,
    this.viewportStart,
    this.viewportEnd,
    this.focusOrdinal,
    this.maxNewBlocks,
    this.lineBreakRules = const WeftLineBreakRules(),
    required this.styleCache,
    this.tagRenderers = const <String, WeftTagRenderer>{},
    this.lazyState,
  });

  _LazyLayoutState? lazyState;
  int visitedBlockCount = 0;
  int estimatedBlockCount = 0;

  /// Resolves computed styles for the walk.
  final WeftStyleResolver styleResolver;

  /// Text scaling applied to every shaped text run.
  final TextScaler textScaler;

  /// Decoded images keyed by node id, provided by the host.
  final Map<int, ui.Image> images;

  /// Root element the block walk starts from.
  final WeftElement body;

  /// Reusable top-level blocks carried over from the previous result.
  final Map<int, WeftCachedLayoutBlock> reusableBlocks;

  /// Backward-matched blocks past the changed region (ADR 0046): content
  /// the walk may reuse shifted by one shared vertical delta. Empty on lazy
  /// passes.
  final Map<int, WeftCachedLayoutBlock> suffixBlocks;

  /// Old->new node id mapping for [suffixBlocks]; node ids are pre-order
  /// positions and shift with the changed middle, so the shifted clones
  /// re-map their nodeIds through it.
  final Map<int, int> suffixIds;

  /// Viewport top in document coordinates; null disables lazy layout.
  final double? viewportStart;

  /// Viewport bottom in document coordinates; null disables lazy layout.
  final double? viewportEnd;

  /// Ordinal of the focus block that must be laid out even when offscreen.
  final int? focusOrdinal;

  /// Cap on how many new blocks one lazy pass may lay out.
  final int? maxNewBlocks;

  /// Kinsoku tables applied by the line-by-line inline layout path.
  final WeftLineBreakRules lineBreakRules;

  /// Computed styles per element, shared across relayouts of one unchanged
  /// snapshot (owned by the incremental cache). Within a layout every element
  /// resolves once; across scroll frames the map makes the block walk reuse
  /// the previous pass's styles instead of re-matching selectors.
  final Map<WeftElement, WeftComputedStyle> styleCache;

  /// Renderers for custom tags, resolved once against the snapshot.
  final Map<String, WeftTagRenderer> tagRenderers;

  /// Boxes accumulated by the walk, in paint order.
  final List<WeftLayoutBox> boxes = <WeftLayoutBox>[];

  /// Paint commands accumulated by the walk, in paint order.
  final List<WeftPaintCommand> commands = <WeftPaintCommand>[];

  /// Link hit regions accumulated by the walk.
  final List<WeftLinkRegion> links = <WeftLinkRegion>[];

  /// Custom tag hit regions accumulated by the walk.
  final List<WeftTagRegion> tagRegions = <WeftTagRegion>[];

  /// Cached top-level blocks emitted by this pass, seeded into the next
  /// incremental layout's [WeftIncrementalLayoutCache].
  final List<WeftCachedLayoutBlock> topLevelBlocks = <WeftCachedLayoutBlock>[];

  /// Commands this pass copied from reused blocks; transferred back to the
  /// previous result on dispose so its painters stay alive.
  final Set<WeftPaintCommand> reusedCommands = <WeftPaintCommand>{};

  /// Whether top-level blocks may be cached for reuse by the next pass;
  /// cleared when a construct (float, margin collapse) makes reuse unsound.
  bool topLevelCacheEligible = true;

  /// Set when a block's reused position no longer matches, which invalidates
  /// positional reuse for every later top-level block.
  bool reuseStopped = false;

  /// Vertical shift shared by the reused suffix blocks (ADR 0046); null
  /// until the first shifted block fixes it.
  double? suffixDelta;

  /// Debug counter of blocks copied from the previous result.
  int reusedBlockCount = 0;

  /// Debug counter of blocks laid out fresh in this pass.
  int laidOutBlockCount = 0;

  /// Debug counter of reused blocks materialized into paint commands.
  int materializedBlockCount = 0;

  /// Whether this pass is bounded to a viewport extent.
  bool get isLazy => viewportStart != null && viewportEnd != null;

  /// Resolves [element]'s computed style through [styleCache]. An element has
  /// exactly one parent in the immutable snapshot, so its inputs — parent
  /// style and ancestor chain — are fully determined by the tree and the
  /// result is stable for the layout's lifetime and any relayout of the same
  /// snapshot instance.
  WeftComputedStyle styleFor(
    WeftElement element, {
    required WeftComputedStyle parent,
    required List<WeftElement> ancestors,
  }) {
    final cached = styleCache[element];
    if (cached != null) return cached;
    final style = styleResolver.resolve(
      element,
      parent: parent,
      ancestors: ancestors,
    );
    styleCache[element] = style;
    return style;
  }

  (int, int, int, int, int)? _startTopLevelBlock(
    WeftElement parent,
    _FloatContext floats,
  ) {
    if (!identical(parent, body)) return null;
    return (
      commands.length,
      boxes.length,
      links.length,
      tagRegions.length,
      floats.exclusionCount,
    );
  }

  void _cacheTopLevelBlock({
    required WeftElement parent,
    required WeftElement child,
    required double left,
    required double top,
    required double height,
    required int? ordinal,
    required _FloatContext floats,
    required (int, int, int, int, int)? start,
  }) {
    if (start == null) return;
    if (isLazy) laidOutBlockCount += 1;
    final blockCommands = commands.sublist(start.$1);
    final blockBoxes = boxes.sublist(start.$2);
    final blockLinks = links.sublist(start.$3);
    final blockTagRegions = tagRegions.sublist(start.$4);
    final blockExclusions = floats.snapshotFrom(start.$5);
    final paintBounds = _commandsPaintBounds(blockCommands);
    final materialize = _shouldMaterialize(
      top: top,
      height: height,
      paintBounds: paintBounds,
      ordinal: ordinal,
    );
    if (!materialize) {
      for (final command in blockCommands) {
        command.dispose();
      }
      commands.removeRange(start.$1, commands.length);
      boxes.removeRange(start.$2, boxes.length);
      links.removeRange(start.$3, links.length);
      tagRegions.removeRange(start.$4, tagRegions.length);
    } else if (isLazy) {
      materializedBlockCount += 1;
    }
    topLevelBlocks.add(
      WeftCachedLayoutBlock(
        element: child,
        left: left,
        top: top,
        height: height,
        materialized: materialize,
        paintBounds: paintBounds,
        boxes: materialize ? blockBoxes : const [],
        commands: materialize ? blockCommands : const [],
        links: materialize ? blockLinks : const [],
        tagRegions: materialize ? blockTagRegions : const [],
        floatExclusions: blockExclusions,
      ),
    );
  }

  double? _reuseTopLevelBlock({
    required WeftElement parent,
    required WeftElement child,
    required double left,
    required double top,
    required int? ordinal,
    required _FloatContext floats,
  }) {
    if (!identical(parent, body) || reuseStopped) return null;
    final block = reusableBlocks[child.id];
    if (block != null) {
      if (block.left != left || block.top != top) {
        reuseStopped = true;
        return null;
      }
      return _adoptBlock(
        block: block,
        child: child,
        left: left,
        top: top,
        ordinal: ordinal,
        floats: floats,
        shift: ui.Offset.zero,
        ids: null,
      );
    }
    final suffixBlock = suffixBlocks[child.id];
    if (suffixBlock == null) return null;
    if (suffixBlock.left != left) {
      // Horizontal positions must match exactly; only the flow's vertical
      // position may shift.
      reuseStopped = true;
      return null;
    }
    final delta = top - suffixBlock.top;
    var sharedDelta = suffixDelta;
    if (sharedDelta == null) {
      // The first shifted block fixes the shared delta. No exclusion from
      // the reused prefix or the fresh middle may reach the shifted region
      // at either its old or its new start; suffix-internal floats move
      // with their blocks, so their relative geometry is self-preserving.
      if (floats.maxBottom > math.min(top, suffixBlock.top)) {
        reuseStopped = true;
        return null;
      }
      sharedDelta = delta;
      suffixDelta = delta;
    } else if (delta != sharedDelta) {
      // Heights or margins diverged from the previous layout, so the shift
      // is no longer provably uniform across the suffix.
      reuseStopped = true;
      return null;
    }
    return _adoptBlock(
      block: suffixBlock,
      child: child,
      left: left,
      top: top,
      ordinal: ordinal,
      floats: floats,
      shift: ui.Offset(0, sharedDelta),
      ids: suffixIds,
    );
  }

  /// Adopts one reused block into this pass. With a zero [shift] the cached
  /// command objects are carried over as-is (previous ownership semantics);
  /// with a vertical shift every positioned output is cloned at its new
  /// location — nodeIds re-mapped through [ids], because pre-order ids
  /// shift with the changed middle — while the originals are registered in
  /// [reusedCommands] so the previous result skips them on dispose and each
  /// TextPainter is disposed exactly once, by this result's clones
  /// (ADR 0046).
  double? _adoptBlock({
    required WeftCachedLayoutBlock block,
    required WeftElement child,
    required double left,
    required double top,
    required int? ordinal,
    required _FloatContext floats,
    required ui.Offset shift,
    required Map<int, int>? ids,
  }) {
    final shifted = shift != ui.Offset.zero;
    assert(!shifted || ids != null, 'shifted clones need the id mapping');
    final materialize = _shouldMaterialize(
      top: top,
      height: block.height,
      paintBounds: block.paintBounds.shift(shift),
      ordinal: ordinal,
    );
    if (isLazy && materialize && !block.materialized) return null;
    // Build every cloned output before touching the walk state so an
    // unmappable command could still fall back to a fresh layout.
    final List<WeftFloatExclusion> shiftedExclusions;
    final List<WeftPaintCommand> blockCommands;
    final List<WeftLayoutBox> blockBoxes;
    final List<WeftLinkRegion> blockLinks;
    final List<WeftTagRegion> blockTagRegions;
    if (!materialize) {
      shiftedExclusions = block.floatExclusions;
      blockCommands = const [];
      blockBoxes = const [];
      blockLinks = const [];
      blockTagRegions = const [];
    } else if (!shifted) {
      shiftedExclusions = block.floatExclusions;
      blockCommands = block.commands;
      blockBoxes = block.boxes;
      blockLinks = block.links;
      blockTagRegions = block.tagRegions;
    } else {
      final map = ids!;
      shiftedExclusions = <WeftFloatExclusion>[
        for (final exclusion in block.floatExclusions)
          WeftFloatExclusion(
            side: exclusion.side,
            rect: exclusion.rect.shift(shift),
          ),
      ];
      blockCommands = <WeftPaintCommand>[
        for (final command in block.commands)
          _shiftCommand(command, shift, map),
      ];
      blockBoxes = <WeftLayoutBox>[
        for (final box in block.boxes)
          WeftLayoutBox(
            nodeId: map[box.nodeId]!,
            rect: box.rect.shift(shift),
          ),
      ];
      blockLinks = <WeftLinkRegion>[
        for (final link in block.links)
          WeftLinkRegion(
            nodeId: map[link.nodeId]!,
            href: link.href,
            text: link.text,
            rects: [for (final rect in link.rects) rect.shift(shift)],
          ),
      ];
      blockTagRegions = <WeftTagRegion>[
        for (final region in block.tagRegions)
          WeftTagRegion(
            nodeId: map[region.nodeId]!,
            tag: region.tag,
            rect: region.rect.shift(shift),
            label: region.label,
          ),
      ];
    }
    floats.addExclusions(shiftedExclusions);
    commands.addAll(blockCommands);
    boxes.addAll(blockBoxes);
    links.addAll(blockLinks);
    tagRegions.addAll(blockTagRegions);
    topLevelBlocks.add(
      WeftCachedLayoutBlock(
        element: child,
        left: block.left,
        top: top,
        height: block.height,
        materialized: materialize,
        paintBounds: block.paintBounds.shift(shift),
        boxes: blockBoxes,
        commands: blockCommands,
        links: blockLinks,
        tagRegions: blockTagRegions,
        floatExclusions: shiftedExclusions,
      ),
    );
    reusedCommands.addAll(block.commands);
    reusedBlockCount += 1;
    if (isLazy && materialize) materializedBlockCount += 1;
    return block.height;
  }

  /// Clones one command into the shifted suffix: same painter or image
  /// resource, position moved by [shift], nodeId re-mapped from the old
  /// pre-order position to the new one.
  WeftPaintCommand _shiftCommand(
    WeftPaintCommand command,
    ui.Offset shift,
    Map<int, int> ids,
  ) {
    final nodeId = ids[command.nodeId]!;
    if (command is WeftTextPaintCommand) {
      return WeftTextPaintCommand(
        nodeId: nodeId,
        painter: command.painter,
        offset: command.offset + shift,
        runs: [
          for (final run in command.runs)
            WeftTextPainterRun(
              nodeId: ids[run.nodeId]!,
              painterStart: run.painterStart,
              painterEnd: run.painterEnd,
              nodeStart: run.nodeStart,
              nodeEnd: run.nodeEnd,
            ),
        ],
      );
    }
    if (command is WeftRectPaintCommand) {
      return WeftRectPaintCommand(
        nodeId: nodeId,
        rect: command.rect.shift(shift),
        color: command.color,
      );
    }
    if (command is WeftImagePaintCommand) {
      return WeftImagePaintCommand(
        nodeId: nodeId,
        image: command.image,
        destination: command.destination.shift(shift),
      );
    }
    throw StateError('Unhandled paint command ${command.runtimeType}');
  }

  bool _shouldMaterialize({
    required double top,
    required double height,
    required ui.Rect paintBounds,
    required int? ordinal,
  }) {
    if (!isLazy) return true;
    if (ordinal != null && ordinal == focusOrdinal) return true;
    final start = viewportStart!;
    final end = viewportEnd!;
    return (top < end && top + height > start) ||
        (paintBounds.top < end && paintBounds.bottom > start);
  }

  ui.Rect _commandsPaintBounds(Iterable<WeftPaintCommand> commands) {
    var bounds = ui.Rect.zero;
    var first = true;
    for (final command in commands) {
      bounds = first ? command.bounds : bounds.expandToInclude(command.bounds);
      first = false;
    }
    return bounds;
  }

  void _disableTopLevelCache(WeftElement parent) {
    if (identical(parent, body)) topLevelCacheEligible = false;
  }

  /// Lays out one block-level box. [availableWidth] is the containing block's
  /// content width before this box's own margins are subtracted: percentage
  /// widths (ADR 0021) resolve against it, while the non-percentage width
  /// clamp and the fill default use the space left after the margins.
  ///
  /// Block overflow is never clipped: an explicit `height` fixes the border
  /// box while overflowing content keeps painting past its bottom edge, and
  /// the same holds for content wider than a constrained box.
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

    final horizontalChrome = style.horizontalPadding + style.horizontalBorder;
    final availableBoxWidth = math.max(
      0.0,
      availableWidth - style.marginLeft - style.marginRight,
    );
    final boxWidth = _resolveBoxWidth(
      style: style,
      availableWidth: availableBoxWidth,
      containingWidth: availableWidth,
      horizontalChrome: horizontalChrome,
    );
    // Auto horizontal margins absorb the space left over after the resolved
    // box width and the non-auto margins. Only the left offset affects block
    // placement: both auto sides split the slack (centering), a lone left
    // auto takes all of it, and a lone right auto leaves the box at its
    // parsed left margin. Negative slack keeps the parsed (zero) margins,
    // and an auto-width box fills the line so it never has slack to
    // distribute.
    var effectiveMarginLeft = style.marginLeft;
    if (style.marginLeftAuto || style.marginRightAuto) {
      final slack = math.max(
        0.0,
        availableWidth - boxWidth - style.marginLeft - style.marginRight,
      );
      if (style.marginLeftAuto) {
        effectiveMarginLeft = style.marginRightAuto ? slack / 2 : slack;
      }
    }
    final boxX = left + effectiveMarginLeft;
    final contentX = boxX + style.borderLeft.width + style.paddingLeft;
    final contentY = top + style.borderTop.width + style.paddingTop;
    final contentWidth = math.max(0.0, boxWidth - horizontalChrome);
    final commandStart = commands.length;
    final childAncestors = <WeftElement>[...ancestors, element];

    final tagRenderer = tagRenderers[element.tag];
    final contentHeight = element.tag == 'hr'
        ? 1.0
        : tagRenderer != null
            ? _layoutCustomTag(
                element: element,
                renderer: tagRenderer,
                contentX: contentX,
                contentY: contentY,
                contentWidth: contentWidth,
              )
            : _layoutChildren(
                element: element,
                style: style,
                contentX: contentX,
                contentY: contentY,
                contentWidth: contentWidth,
                childAncestors: childAncestors,
                floats: floats,
              );
    // An explicit CSS height overrides the content-driven height after the
    // same box-sizing conversion width uses (ADR 0009). Overflowing content
    // keeps painting below the border box; nothing is clipped or grown.
    final height = style.height == null
        ? style.verticalBorder + style.verticalPadding + contentHeight
        : style.boxSizing == WeftBoxSizing.borderBox
            ? style.height!
            : style.height! + style.verticalBorder + style.verticalPadding;

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
        contentWidth: contentWidth,
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

  /// Lays out one custom tag's content box through its trusted renderer.
  ///
  /// Ops are clamped to the content box, attributed to the element, and
  /// converted into regular paint commands so chunking, hit culling and
  /// command reuse keep working unchanged. A throwing renderer degrades to an
  /// empty box instead of failing the whole document.
  double _layoutCustomTag({
    required WeftElement element,
    required WeftTagRenderer renderer,
    required double contentX,
    required double contentY,
    required double contentWidth,
  }) {
    final WeftTagLayout tagLayout;
    try {
      tagLayout = renderer.layout(WeftTagLayoutContext(
        element: element,
        contentWidth: contentWidth,
        textScaler: textScaler,
      ));
    } catch (_) {
      return 0;
    }
    final height = math.max(0.0, tagLayout.height);
    if (contentWidth <= 0 || height <= 0) {
      return height;
    }
    final contentBox = Rect.fromLTWH(contentX, contentY, contentWidth, height);
    for (final op in tagLayout.ops) {
      switch (op) {
        case WeftTagRectOp():
          final rect = Rect.fromLTWH(
            contentX + op.rect.left,
            contentY + op.rect.top,
            op.rect.width,
            op.rect.height,
          ).intersect(contentBox);
          if (rect.width <= 0 || rect.height <= 0) continue;
          commands.add(WeftRectPaintCommand(
            nodeId: element.id,
            rect: rect,
            color: op.color,
          ));
        case WeftTagTextOp():
          if (op.text.isEmpty) continue;
          final left = contentX + op.offset.dx;
          final maxWidth = math.min(
            op.maxWidth ?? double.infinity,
            contentX + contentWidth - left,
          );
          if (maxWidth <= 0) continue;
          final painter = TextPainter(
            text: TextSpan(text: op.text, style: op.style),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout(maxWidth: maxWidth);
          commands.add(WeftTextPaintCommand(
            nodeId: element.id,
            painter: painter,
            offset: Offset(left, contentY + op.offset.dy),
          ));
      }
    }
    final rendererLabel = tagLayout.semanticsLabel?.trim() ?? '';
    final attributeLabel = element.attribute('aria-label')?.trim() ?? '';
    tagRegions.add(WeftTagRegion(
      nodeId: element.id,
      tag: element.tag,
      rect: contentBox,
      label: rendererLabel.isNotEmpty
          ? rendererLabel
          : attributeLabel.isNotEmpty
              ? attributeLabel
              : element.tag,
    ));
    return height;
  }

  /// Resolves the used border-box width following ADR 0009. [availableWidth]
  /// is the space left after the box's own margins and caps every result;
  /// [containingWidth] is the containing block's content width that
  /// percentage widths resolve against (CSS percentages never subtract the
  /// box's own margins first). Percentage `min-width`/`max-width` are not
  /// supported and stay length-only. The table grid omits [containingWidth]
  /// because it guards the call with an explicit `width`, so percentages
  /// keep resolving as auto there.
  double _resolveBoxWidth({
    required WeftComputedStyle style,
    required double availableWidth,
    double? containingWidth,
    required double horizontalChrome,
  }) {
    final percent = style.widthPercent;
    double boxWidth;
    if (percent != null &&
        containingWidth != null &&
        containingWidth.isFinite) {
      // Cyclic cases (intrinsic measurement with an infinite width) treat a
      // percentage as auto, matching ADR 0018's image sizing.
      final resolved = containingWidth * percent / 100;
      boxWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? resolved
          : resolved + horizontalChrome;
    } else if (style.width != null) {
      boxWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? style.width!
          : style.width! + horizontalChrome;
    } else {
      boxWidth = availableWidth;
    }
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
    if (isLazy && identical(element, body)) {
      return _layoutLazyChildren(
        style: style,
        contentX: contentX,
        contentY: contentY,
        contentWidth: contentWidth,
        childAncestors: childAncestors,
      );
    }
    var cursor = contentY;
    var pendingMargin = 0.0;
    var hasPendingMargin = false;
    // A block with no top border or padding lets its first in-flow block
    // child's top margin collapse into its own outer margin.
    var leadingCollapses = style.borderTop.width == 0 && style.paddingTop == 0;
    var trailingCollapses =
        style.borderBottom.width == 0 && style.paddingBottom == 0;
    var orderedItem = _orderedListStart(element) - 1;
    final inline = _InlineAccumulator(this, containingWidth: contentWidth);

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

    final children = element.children;
    for (var childIndex = 0; childIndex < children.length; childIndex++) {
      final child = children[childIndex];
      final ordinal = identical(element, body) ? childIndex : null;
      if (child is WeftText) {
        _disableTopLevelCache(element);
        inline.addText(child, style);
        continue;
      }
      if (child is! WeftElement) continue;

      final childStyle = styleFor(
        child,
        parent: style,
        ancestors: childAncestors,
      );
      if (childStyle.display == WeftDisplay.none) {
        _disableTopLevelCache(element);
        continue;
      }

      if (child.tag == 'img') {
        final image = images[child.id];
        if (image != null) {
          if (childStyle.float != WeftFloat.none) {
            flushInline();
            if (identical(element, body)) {
              final reused = _reuseTopLevelBlock(
                parent: element,
                child: child,
                left: contentX,
                top: cursor,
                ordinal: ordinal,
                floats: floats,
              );
              if (reused != null) continue;
              final start = _startTopLevelBlock(element, floats);
              _placeFloatImage(
                element: child,
                style: childStyle,
                image: image,
                contentX: contentX,
                contentWidth: contentWidth,
                top: cursor,
                floats: floats,
              );
              _cacheTopLevelBlock(
                parent: element,
                child: child,
                left: contentX,
                top: cursor,
                height: 0,
                ordinal: ordinal,
                floats: floats,
                start: start,
              );
            } else {
              _placeFloatImage(
                element: child,
                style: childStyle,
                image: image,
                contentX: contentX,
                contentWidth: contentWidth,
                top: cursor,
                floats: floats,
              );
            }
            continue;
          }

          // Inline-displayed resolved images join the line as atomic
          // placeholders instead of becoming block items.
          if (childStyle.display == WeftDisplay.inline) {
            inline.addImageAtom(child, childStyle, image);
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

          final reusedHeight = _reuseTopLevelBlock(
            parent: element,
            child: child,
            left: contentX,
            top: cursor,
            ordinal: ordinal,
            floats: floats,
          );
          if (reusedHeight != null) {
            cursor += reusedHeight;
          } else {
            final start = _startTopLevelBlock(element, floats);
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
              _cacheTopLevelBlock(
                parent: element,
                child: child,
                left: contentX,
                top: cursor - metrics.boxHeight,
                height: metrics.boxHeight,
                ordinal: ordinal,
                floats: floats,
                start: start,
              );
            } else {
              _disableTopLevelCache(element);
            }
          }
          pendingMargin = outerBottom;
          hasPendingMargin = true;
          continue;
        }

        // Unresolved images participate as alternative text, matching how a
        // browser keeps content meaningful when a resource is unavailable.
        _disableTopLevelCache(element);
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

        final reusedHeight = _reuseTopLevelBlock(
          parent: element,
          child: child,
          left: contentX,
          top: cursor,
          ordinal: ordinal,
          floats: floats,
        );
        if (reusedHeight != null) {
          cursor += reusedHeight;
        } else {
          final start = _startTopLevelBlock(element, floats);
          final result = layoutTable(
            element: child,
            style: childStyle,
            availableWidth: contentWidth,
            left: contentX,
            top: cursor,
            ancestors: childAncestors,
          );
          cursor += result.height;
          _cacheTopLevelBlock(
            parent: element,
            child: child,
            left: contentX,
            top: cursor - result.height,
            height: result.height,
            ordinal: ordinal,
            floats: floats,
            start: start,
          );
        }
        pendingMargin = outerBottom;
        hasPendingMargin = true;
        continue;
      }

      if (childStyle.display == WeftDisplay.inline) {
        _disableTopLevelCache(element);
        inline.collectElement(child, childStyle, childAncestors);
        continue;
      }

      flushInline();
      if (child.tag == 'li') {
        if (element.tag == 'ol') {
          final explicit = _orderedListItemValue(child);
          if (explicit != null) orderedItem = explicit - 1;
          orderedItem += 1;
        } else if (childStyle.listStyle == WeftListStyle.decimal) {
          orderedItem += 1;
        }
      }

      final outerTop = outerMarginTop(child, childStyle, childAncestors);
      final outerBottom = outerMarginBottom(child, childStyle, childAncestors);
      final selfCollapsing = _isSelfCollapsing(
        child,
        childStyle,
        childAncestors,
      );

      if (selfCollapsing) {
        _disableTopLevelCache(element);
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
      final reusedHeight = _reuseTopLevelBlock(
        parent: element,
        child: child,
        left: contentX,
        top: cursor,
        ordinal: ordinal,
        floats: floats,
      );
      if (reusedHeight != null) {
        cursor += reusedHeight;
      } else {
        final start = _startTopLevelBlock(element, floats);
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
        _cacheTopLevelBlock(
          parent: element,
          child: child,
          left: contentX,
          top: cursor - result.height,
          height: result.height,
          ordinal: ordinal,
          floats: floats,
          start: start,
        );
      }
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
    final cssHeight = style.height;
    // Percentage heights resolve as auto: the parent height is unknown while
    // content flows, so no percentage can be computed against it.
    final resolvedHeight = cssHeight == null
        ? null
        : math.max(
            0.0,
            style.boxSizing == WeftBoxSizing.borderBox
                ? cssHeight - chromeHeight
                : cssHeight,
          );

    double contentWidth;
    double? explicitHeight;
    if (cssWidth != null) {
      contentWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? cssWidth - chromeWidth
          : cssWidth;
      explicitHeight = resolvedHeight ?? attributeHeight;
    } else if (style.widthPercent != null) {
      // Percentage widths resolve against the containing block's content
      // width before the image's own margins shorten the usable space.
      // Intrinsic measurement passes an infinite width, where percentages
      // behave as auto and fall back to the natural size, matching CSS.
      final resolved = availableWidth.isFinite
          ? availableWidth * style.widthPercent! / 100
          : naturalWidth;
      contentWidth = style.boxSizing == WeftBoxSizing.borderBox
          ? resolved - chromeWidth
          : resolved;
      explicitHeight = resolvedHeight ?? attributeHeight;
    } else if (resolvedHeight != null) {
      // An explicit CSS height with an auto width derives the width from the
      // ratio. No explicit height is recorded here, so the min/max clamps
      // below rescale both axes together and keep the ratio intact.
      contentWidth = resolvedHeight * ratio;
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
      // CSS folds the last child's bottom margin through only when the box
      // height is auto, so an explicit height ends the chain here.
      if (currentStyle.height != null) break;
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
      final style = styleFor(
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
      final style = styleFor(
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
    // CSS only folds margins through a box with an auto height; an explicit
    // height always produces a border box with extent. Percentage heights
    // resolve as auto and keep collapsing.
    if (style.height != null) return false;
    if (element.tag == 'hr') return false;
    // A table box never collapses through itself.
    if (element.tag == 'table') return false;
    // Replaced content always contributes height, so a box holding only an
    // image never collapses through.
    if (element.tag == 'img') return false;
    // An empty list item still renders a marker, so it must be laid out.
    if (style.display == WeftDisplay.listItem) return false;
    // Custom tags carry renderer-owned content and never collapse through.
    if (tagRenderers.containsKey(element.tag)) return false;
    final childAncestors = <WeftElement>[...ancestors, element];
    for (final child in element.children) {
      if (child is WeftText) {
        if (!_isBlankText(child.text, style.whiteSpace)) return false;
        continue;
      }
      if (child is! WeftElement) continue;
      final childStyle = styleFor(
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
    // Replaced content is never empty, even though it has no children for
    // the recursion below to inspect.
    if (element.tag == 'img') return false;
    final childAncestors = <WeftElement>[...ancestors, element];
    for (final child in element.children) {
      if (child is WeftText) {
        if (!_isBlankText(child.text, style.whiteSpace)) return false;
        continue;
      }
      if (child is! WeftElement) continue;
      if (child.tag == 'br') return false;
      final childStyle = styleFor(
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
            runs: inline.runSpecs(
              line.textStart,
              line.textEnd,
              cursors: lines.cursors,
            ),
          ),
        );
        _addAtomCommands(line.atomPlacements, Offset(line.x, line.y));
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
    _addAtomCommands(inlineLayout.atomPlacements, offset);
    for (final link in inlineLayout.links) {
      links.add(link.shift(offset));
    }
    return height;
  }

  /// Emits one image command per inline atom at its laid-out content rect.
  void _addAtomCommands(List<_AtomPlacement> placements, ui.Offset offset) {
    for (final placement in placements) {
      commands.add(
        WeftImagePaintCommand(
          nodeId: placement.nodeId,
          image: placement.image,
          destination: placement.destination.shift(offset),
        ),
      );
      boxes.add(
        WeftLayoutBox(
          nodeId: placement.nodeId,
          rect: placement.boxRect.shift(offset),
        ),
      );
    }
  }

  int _orderedListStart(WeftElement element) {
    if (element.tag != 'ol') return 1;
    return int.tryParse(element.attribute('start') ?? '') ?? 1;
  }

  int? _orderedListItemValue(WeftElement element) {
    if (element.tag != 'li') return null;
    return int.tryParse(element.attribute('value') ?? '');
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
    required double contentWidth,
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
      // Marker glyphs are direction-neutral digits/bullets; only placement
      // mirrors with the block direction (ADR 0042).
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      locale: _localeFor(style.lang),
    )..layout();
    if (painter.width <= 0 || painter.height <= 0) {
      painter.dispose();
      return null;
    }
    final lineHeight = style.fontSize * style.lineHeight;
    final y = contentY + math.max(0.0, (lineHeight - painter.height) / 2);
    final double x;
    if (style.direction == TextDirection.rtl) {
      // The marker sits outside the content box's start edge: the right
      // edge for RTL, mirroring the UA `padding-inline-start` indent.
      x = contentX + contentWidth + 8;
    } else {
      x = math.max(0.0, contentX - painter.width - 8);
    }
    return WeftTextPaintCommand(
      nodeId: nodeId,
      painter: painter,
      offset: Offset(x, y),
    );
  }
}

/// Resolves the `lang` attribute into a TextPainter locale (ADR 0042).
/// Documents without a language keep the engine's default `Locale('zh')` —
/// the value every pre-0042 layout used — so existing line breaking is
/// untouched.
Locale _localeFor(String? lang) {
  final value = lang?.trim() ?? '';
  if (value.isEmpty) return const Locale('zh');
  final parts = value.split(RegExp('[-_]'));
  final languageCode = parts.first.toLowerCase();
  if (languageCode.isEmpty || languageCode.length > 8) {
    return const Locale('zh');
  }
  String? scriptCode;
  String? countryCode;
  for (final part in parts.skip(1)) {
    if (part.length == 4 && scriptCode == null) {
      scriptCode = part;
    } else if (part.isNotEmpty && part.length <= 3 && countryCode == null) {
      countryCode = part.toUpperCase();
    }
  }
  return Locale.fromSubtags(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
}

final class _ImageBoxMetrics {
  const _ImageBoxMetrics({
    required this.boxWidth,
    required this.boxHeight,
    required this.contentWidth,
    required this.contentHeight,
  });

  /// Border-box width of the image element.
  final double boxWidth;

  /// Border-box height of the image element.
  final double boxHeight;

  /// Content-box width available to the image itself.
  final double contentWidth;

  /// Content-box height the image is sized into.
  final double contentHeight;
}
