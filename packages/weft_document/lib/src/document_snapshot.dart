import 'document_node.dart';
import 'style_sheet.dart';
import 'support_report.dart';

final class WeftDocumentSnapshot {
  const WeftDocumentSnapshot({
    required this.id,
    required this.revision,
    required this.normalizedHtml,
    this.supportReport = const SupportReport.empty(),
    this.body,
    this.styleSheet = const WeftStyleSheet.empty(),
  }) : assert(revision >= 0);

  static const empty = WeftDocumentSnapshot(
    id: 'empty',
    revision: 0,
    normalizedHtml: '',
  );

  final String id;
  final int revision;
  final String normalizedHtml;
  final SupportReport supportReport;
  final WeftElement? body;
  final WeftStyleSheet styleSheet;
}
