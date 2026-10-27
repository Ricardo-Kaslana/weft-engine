import 'package:flutter/material.dart';
import 'package:weft/weft.dart';

/// Builds the host-provided WebView surface for content Weft cannot render.
///
/// The host owns the raw markup: Weft only reports that the content needs a
/// fallback engine (ADR 0006); this callback receives the same HTML string
/// the host normalized.
typedef WebViewFallbackBuilder = Widget Function(
  BuildContext context,
  String html,
  SupportReport report,
);

/// Turns a [SupportReport] into the surface the host should show.
///
/// Decision table (docs/supported-subset.md, architecture §8):
/// - content renders        → [WeftFallbackPlan.render]
/// - `requiresWebView`      → [WeftFallbackPlan.webView] with the raw HTML
/// - errors without a
///   WebView requirement    → [WeftFallbackPlan.errorCard]
enum WeftFallbackAction { render, webView, errorCard }

final class WeftFallbackPlan {
  const WeftFallbackPlan.render()
      : action = WeftFallbackAction.render,
        html = null;

  const WeftFallbackPlan.webView(String this.html)
      : action = WeftFallbackAction.webView;

  const WeftFallbackPlan.errorCard()
      : action = WeftFallbackAction.errorCard,
        html = null;

  final WeftFallbackAction action;

  /// The raw markup to hand to the WebView; non-null only for
  /// [WeftFallbackAction.webView].
  final String? html;
}

/// Decides what a host should show for [report]. Pure logic, unit tested.
/// WebView plans carry an empty [WeftFallbackPlan.html]; the caller fills in
/// the raw markup it normalized (the engine never stores un-normalized
/// input — see [WeftFallbackCoordinator]).
WeftFallbackPlan decideWeftFallback(SupportReport report) {
  if (report.canRender) return const WeftFallbackPlan.render();
  if (report.requiresWebView) {
    return const WeftFallbackPlan.webView('');
  }
  return const WeftFallbackPlan.errorCard();
}

/// Wires [decideWeftFallback] into [WeftView.fallbackBuilder].
///
/// The coordinator keeps a reference to the raw HTML the host asked Weft to
/// render so the WebView builder can load exactly that markup — the engine
/// itself never stores un-normalized input.
final class WeftFallbackCoordinator {
  const WeftFallbackCoordinator({
    required this.html,
    required this.webViewBuilder,
  });

  /// Raw markup of the document currently shown; used by
  /// [fallbackBuilder] when the report requires a WebView.
  final String html;

  final WebViewFallbackBuilder webViewBuilder;

  WeftFallbackBuilder get fallbackBuilder {
    return (BuildContext context, SupportReport report) {
      final plan = report.requiresWebView
          ? WeftFallbackPlan.webView(html)
          : decideWeftFallback(report);
      switch (plan.action) {
        case WeftFallbackAction.render:
          return const SizedBox.shrink();
        case WeftFallbackAction.webView:
          return webViewBuilder(context, plan.html!, report);
        case WeftFallbackAction.errorCard:
          return _FallbackIssueCard(report: report);
      }
    };
  }
}

final class _FallbackIssueCard extends StatelessWidget {
  const _FallbackIssueCard({required this.report});

  final SupportReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '该内容无法渲染，且不需要 WebView 回退。以下是诊断报告：',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final issue in report.issues)
          ListTile(
            dense: true,
            leading: Text(issue.severity.name),
            title: Text(issue.code),
            subtitle: Text(issue.message),
          ),
      ],
    );
  }
}
