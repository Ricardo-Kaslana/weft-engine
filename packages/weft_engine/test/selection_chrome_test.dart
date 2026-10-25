import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeftLayoutResult.caretRectForAnchor', () {
    test('builds a caret-width bar at the anchor glyph box', () {
      final document = _normalize('<p>Alpha block</p>', 'caret-hit');
      final layout = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(layout.dispose);
      final node = layout.textIndex!.entries.single.nodeId;
      final glyphRects = layout.textRectsForNode(node, 2, 3);
      expect(glyphRects, isNotEmpty);

      final caret = layout.caretRectForAnchor(TextAnchor(node, 2));
      expect(caret, isNotNull);
      expect(caret!.left, glyphRects.first.left);
      expect(caret.width, WeftLayoutResult.caretWidth);
      expect(caret.top, glyphRects.first.top);
      expect(caret.bottom, glyphRects.first.bottom);
    });

    test('returns null for unknown nodes and end-of-node offsets', () {
      final document = _normalize('<p>Alpha block</p>', 'caret-miss');
      final layout = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(layout.dispose);
      final entry = layout.textIndex!.entries.single;

      expect(
        layout.caretRectForAnchor(const TextAnchor(9999, 0)),
        isNull,
        reason: 'unknown nodes never map',
      );
      expect(
        layout.caretRectForAnchor(TextAnchor(entry.nodeId, entry.text.length)),
        isNull,
        reason: 'the offset past the last glyph has no box to anchor to',
      );
    });
  });

  group('RenderWeftSurface.selectionControlsGeometry', () {
    test('anchors handles at the first and last selection rectangles', () {
      final document = _normalize(
        '<p>Alpha block</p><p>Beta block</p><p>Gamma block</p>',
        'chrome-geometry',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(layout.dispose);
      final entries = layout.textIndex!.entries;
      // Start the selection in the second paragraph so the space above its
      // bounds is large enough for the above-the-selection placement.
      final selection = TextSelectionRange(
        anchor: TextAnchor(entries[1].nodeId, 2),
        extent: TextAnchor(entries[2].nodeId, 4),
      );
      final rects = layout.selectionRects(selection);
      expect(rects.length, greaterThanOrEqualTo(2));

      final surface = RenderWeftSurface(
        document: document,
        selection: selection,
      );
      surface.layout(const BoxConstraints.tightFor(width: 280));
      addTearDown(surface.dispose);

      final geometry = surface.selectionControlsGeometry();
      expect(geometry, isNotNull);
      expect(
        geometry!.startAnchor,
        ui.Offset(rects.first.left, rects.first.bottom),
      );
      expect(
        geometry.endAnchor,
        ui.Offset(rects.last.right, rects.last.bottom),
      );
      // Handles keep the full 44px width; the height only shrinks when the
      // drop area would run past the surface bottom edge.
      final surfaceHeight = surface.size.height;
      double targetHeight(ui.Offset anchor) =>
          math.min(kWeftSelectionHandleTouchExtent, surfaceHeight - anchor.dy);
      expect(
        geometry.startHandle!.size,
        Size(kWeftSelectionHandleTouchExtent,
            targetHeight(geometry.startAnchor)),
      );
      expect(
        geometry.endHandle!.size,
        Size(kWeftSelectionHandleTouchExtent, targetHeight(geometry.endAnchor)),
      );

      // The copy button is suggested above the selection bounds.
      var union = rects.first;
      for (final rect in rects.skip(1)) {
        union = union.expandToInclude(rect);
      }
      expect(geometry.copyButton!.size, kWeftCopyButtonSize);
      expect(
        geometry.copyButton!.bottom,
        union.top - kWeftCopyButtonVerticalGap,
      );
    });

    test('falls back below the handles when the top leaves the surface', () {
      final document = _normalize(
        '<p>Alpha block</p><p>Beta block</p><p>Gamma block</p>',
        'chrome-button-below',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(layout.dispose);
      final entries = layout.textIndex!.entries;
      final selection = TextSelectionRange(
        anchor: TextAnchor(entries[0].nodeId, 2),
        extent: TextAnchor(entries[0].nodeId, 6),
      );
      final rects = layout.selectionRects(selection);
      expect(rects, isNotEmpty);

      RenderWeftSurface surface({required bool showSelectionHandles}) {
        final result = RenderWeftSurface(
          document: document,
          selection: selection,
          showSelectionHandles: showSelectionHandles,
        );
        result.layout(const BoxConstraints.tightFor(width: 280));
        addTearDown(result.dispose);
        return result;
      }

      // Handles shown: the below-fallback clears their touch targets.
      final geometry =
          surface(showSelectionHandles: true).selectionControlsGeometry();
      expect(geometry, isNotNull);
      expect(
        geometry!.copyButton!.top,
        rects.first.bottom +
            kWeftSelectionHandleTouchExtent +
            kWeftCopyButtonVerticalGap,
      );

      // Handles hidden: the button sits directly below the selection.
      final withoutHandles =
          surface(showSelectionHandles: false).selectionControlsGeometry();
      expect(withoutHandles, isNotNull);
      expect(
        withoutHandles!.copyButton!.top,
        rects.first.bottom + kWeftCopyButtonVerticalGap,
      );
    });

    test('returns null without an expandable selection', () {
      final document = _normalize(
        '<p>Alpha block</p>',
        'chrome-null',
      );
      final surface = RenderWeftSurface(document: document);
      surface.layout(const BoxConstraints.tightFor(width: 280));
      addTearDown(surface.dispose);
      expect(surface.selectionControlsGeometry(), isNull);

      final probe = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(probe.dispose);
      final collapsed = TextSelectionRange.collapsed(
        TextAnchor(probe.textIndex!.entries.single.nodeId, 2),
      );
      final collapsedSurface = RenderWeftSurface(
        document: document,
        selection: collapsed,
      );
      collapsedSurface.layout(const BoxConstraints.tightFor(width: 280));
      addTearDown(collapsedSurface.dispose);
      expect(collapsedSurface.selectionControlsGeometry(), isNull);
    });

    test('gates handle and copy button rects by the show flags', () {
      final document = _normalize(
        '<p>Alpha block</p><p>Beta block</p>',
        'chrome-flags',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 280);
      addTearDown(layout.dispose);
      final entries = layout.textIndex!.entries;
      final selection = TextSelectionRange(
        anchor: TextAnchor(entries[0].nodeId, 2),
        extent: TextAnchor(entries[1].nodeId, 4),
      );
      expect(
        layout.selectionRects(selection),
        isNotEmpty,
        reason: 'the test needs a resolvable selection',
      );

      RenderWeftSurface surfaceWith(
          {required bool handles, bool button = true}) {
        final surface = RenderWeftSurface(
          document: document,
          selection: selection,
          showSelectionHandles: handles,
          showCopyButton: button,
        );
        surface.layout(const BoxConstraints.tightFor(width: 280));
        addTearDown(surface.dispose);
        return surface;
      }

      final noHandles = surfaceWith(handles: false);
      final noHandlesGeometry = noHandles.selectionControlsGeometry();
      expect(noHandlesGeometry, isNotNull);
      expect(noHandlesGeometry!.startHandle, isNull);
      expect(noHandlesGeometry.endHandle, isNull);
      expect(noHandlesGeometry.copyButton, isNotNull);

      final noButton = surfaceWith(handles: true, button: false);
      final noButtonGeometry = noButton.selectionControlsGeometry();
      expect(noButtonGeometry, isNotNull);
      expect(noButtonGeometry!.startHandle, isNotNull);
      expect(noButtonGeometry.endHandle, isNotNull);
      expect(noButtonGeometry.copyButton, isNull);

      final neither = surfaceWith(handles: false, button: false);
      expect(neither.selectionControlsGeometry(), isNull);
    });

    test('clamps touch targets inside the surface bounds', () {
      final document = _normalize(
        '<p>Alpha block</p><p>Beta block</p><p>Gamma block</p>',
        'chrome-clamp',
      );
      const width = 280.0;
      final layout = const WeftLayoutEngine().layout(document, width: width);
      addTearDown(layout.dispose);
      final entries = layout.textIndex!.entries;
      final selection = TextSelectionRange(
        anchor: TextAnchor(entries[0].nodeId, 0),
        extent: TextAnchor(entries[2].nodeId, 4),
      );
      final rects = layout.selectionRects(selection);
      expect(rects.last.bottom + kWeftSelectionHandleTouchExtent,
          greaterThan(layout.size.height),
          reason: 'the test needs an end handle that would leave the surface');

      final surface = RenderWeftSurface(
        document: document,
        selection: selection,
      );
      surface.layout(const BoxConstraints.tightFor(width: width));
      addTearDown(surface.dispose);
      final geometry = surface.selectionControlsGeometry();
      expect(geometry, isNotNull);
      expect(geometry!.endHandle!.bottom, surface.size.height);
      // Vertical clamping shrinks the targets instead of shifting them, so
      // the grab area never lands on top of the selected lines.
      expect(geometry.startHandle!.top, rects.first.bottom);
      expect(geometry.endHandle!.top, rects.last.bottom);

      final bounds = ui.Offset.zero & surface.size;
      final targets = [
        geometry.startHandle,
        geometry.endHandle,
        geometry.copyButton,
      ];
      for (final rect in targets) {
        expect(rect, isNotNull);
        expect(_withinBounds(rect!, bounds), isTrue,
            reason: '$rect must stay inside $bounds');
      }
    });
  });
}

bool _withinBounds(ui.Rect rect, ui.Rect bounds) {
  return rect.left >= bounds.left &&
      rect.top >= bounds.top &&
      rect.right <= bounds.right &&
      rect.bottom <= bounds.bottom;
}

WeftDocumentSnapshot _normalize(String html, String id) {
  final document = const WeftNormalizer().normalize(html, id: id);
  if (!document.supportReport.canRender) {
    throw StateError(
      'Test document "$id" is not renderable: '
      '${document.supportReport.issues.map((issue) => issue.code).join(', ')}',
    );
  }
  return document;
}
