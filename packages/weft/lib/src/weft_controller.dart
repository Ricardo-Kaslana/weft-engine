import 'package:flutter/foundation.dart';
import 'package:weft_document/weft_document.dart';

final class WeftController extends ChangeNotifier {
  WeftDocumentSnapshot? _document;
  TextSelectionRange? _selection;

  WeftDocumentSnapshot? get document => _document;

  TextSelectionRange? get selection => _selection;

  void loadDocument(WeftDocumentSnapshot document) {
    if (identical(_document, document)) return;
    _document = document;
    _selection = null;
    notifyListeners();
  }

  void updateSelection(TextSelectionRange? selection) {
    if (_selection == selection) return;
    _selection = selection;
    notifyListeners();
  }

  void clear() {
    if (_document == null && _selection == null) return;
    _document = null;
    _selection = null;
    notifyListeners();
  }
}
