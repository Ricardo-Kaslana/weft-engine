/// How much a diagnostic matters: `info` is advisory, `warning` means
/// content was degraded or dropped, `error` means nothing renderable
/// (typically alongside `requiresWebView`).
enum SupportSeverity { info, warning, error }

/// One structured diagnostic. Codes are stable strings (`html.parse.failed`,
/// `html.table.nested`, `css.property.unsupported`, ...) that hosts can
/// branch on; messages are human-readable and may change between releases.
final class SupportIssue {
  /// Creates an issue; [code] and [message] must be non-empty.
  const SupportIssue({
    required this.code,
    required this.message,
    this.severity = SupportSeverity.warning,
    this.requiresWebView = false,
  });

  /// Stable machine-readable category, e.g. `html.script.unsupported`.
  final String code;

  /// Human-readable explanation of what was dropped or degraded.
  final String message;

  /// How severe the issue is.
  final SupportSeverity severity;

  /// Whether this content can only be rendered by a full WebView (ADR 0006).
  final bool requiresWebView;
}

/// Immutable collection of [SupportIssue]s for one normalization run.
///
/// The engine contract (ADR 0006): unsupported content never renders
/// silently — every drop or degradation appears here, and hosts decide
/// fallback policy from [requiresWebView] / [canRender].
final class SupportReport {
  /// Collects [issues] into an immutable report.
  factory SupportReport(Iterable<SupportIssue> issues) {
    return SupportReport._(List<SupportIssue>.unmodifiable(issues));
  }

  const SupportReport._(this.issues);

  /// A report with no issues.
  const SupportReport.empty() : this._(const <SupportIssue>[]);

  /// All issues in normalization order.
  final List<SupportIssue> issues;

  /// Whether any issue has error severity (nothing renderable).
  bool get hasErrors =>
      issues.any((issue) => issue.severity == SupportSeverity.error);

  /// Whether any content demands a WebView fallback.
  bool get requiresWebView => issues.any((issue) => issue.requiresWebView);

  /// Whether the engine can render this content natively.
  bool get canRender => !hasErrors && !requiresWebView;
}
