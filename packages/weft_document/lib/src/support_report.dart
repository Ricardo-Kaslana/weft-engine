enum SupportSeverity { info, warning, error }

final class SupportIssue {
  const SupportIssue({
    required this.code,
    required this.message,
    this.severity = SupportSeverity.warning,
    this.requiresWebView = false,
  });

  final String code;
  final String message;
  final SupportSeverity severity;
  final bool requiresWebView;
}

final class SupportReport {
  factory SupportReport(Iterable<SupportIssue> issues) {
    return SupportReport._(List<SupportIssue>.unmodifiable(issues));
  }

  const SupportReport._(this.issues);

  const SupportReport.empty() : this._(const <SupportIssue>[]);

  final List<SupportIssue> issues;

  bool get hasErrors =>
      issues.any((issue) => issue.severity == SupportSeverity.error);

  bool get requiresWebView => issues.any((issue) => issue.requiresWebView);

  bool get canRender => !hasErrors && !requiresWebView;
}
