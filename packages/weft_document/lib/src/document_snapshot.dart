import 'document_node.dart';
import 'style_sheet.dart';
import 'support_report.dart';

/// Immutable output of normalization: the renderable node tree plus the
/// stylesheet, support report and the re-serialized markup. Views and the
/// layout engine only ever see snapshots — raw HTML never crosses this
/// boundary. Encode/decode with [WeftDocumentJson] to ship one over the
/// wire (ADR 0034).
final class WeftDocumentSnapshot {
  /// Creates a snapshot; prefer [WeftNormalizer.normalize] over building
  /// one by hand.
  const WeftDocumentSnapshot({
    required this.id,
    required this.revision,
    required this.normalizedHtml,
    this.supportReport = const SupportReport.empty(),
    this.body,
    this.styleSheet = const WeftStyleSheet.empty(),
  }) : assert(revision >= 0);

  /// A snapshot with no content and no issues.
  static const empty = WeftDocumentSnapshot(
    id: 'empty',
    revision: 0,
    normalizedHtml: '',
  );

  /// Host-assigned document identifier used for cache/selection identity.
  final String id;

  /// Monotonic revision for streaming updates of the same [id].
  final int revision;

  /// Re-serialization of the body's children (escaped, normalized);
  /// empty exactly when the body has no children.
  final String normalizedHtml;

  /// Diagnostics and fallback requirements produced during normalization.
  final SupportReport supportReport;

  /// The normalized `body` element, or null when nothing was renderable.
  final WeftElement? body;

  /// Rules parsed from the document's `<style>` elements.
  final WeftStyleSheet styleSheet;
}
