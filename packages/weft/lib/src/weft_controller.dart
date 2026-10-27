import 'package:flutter/foundation.dart';
import 'package:weft_document/weft_document.dart';

/// Host-side state holder feeding [WeftView].
///
/// The controller owns the current [WeftDocumentSnapshot] and the active
/// [TextSelectionRange]; WeftView listens and re-lays-out on changes. It
/// never parses or stores raw HTML — build snapshots with
/// `WeftNormalizer.normalize` (or decode a `WeftDocumentJson` payload from
/// a trusted server) and hand the snapshot here.
final class WeftController extends ChangeNotifier {
  WeftDocumentSnapshot? _document;
  TextSelectionRange? _selection;

  /// The document currently shown, or null when cleared.
  WeftDocumentSnapshot? get document => _document;

  /// The current logical selection, or null when collapsed/absent.
  TextSelectionRange? get selection => _selection;

  /// Replaces the document and clears the selection.
  ///
  /// Loading the identical snapshot instance is a no-op, so re-building
  /// widgets that hold the same snapshot does not reset layout state.
  void loadDocument(WeftDocumentSnapshot document) {
    if (identical(_document, document)) return;
    _document = document;
    _selection = null;
    notifyListeners();
  }

  /// Replaces the selection; no-op when [selection] equals the current one.
  void updateSelection(TextSelectionRange? selection) {
    if (_selection == selection) return;
    _selection = selection;
    notifyListeners();
  }

  /// Removes the document and selection; no-op when already empty.
  void clear() {
    if (_document == null && _selection == null) return;
    _document = null;
    _selection = null;
    notifyListeners();
  }
}
