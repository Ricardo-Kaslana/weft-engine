# Changelog

## Unreleased

- Added controlled HTML normalization with tag/attribute filtering, URL checks, node limits, structured support diagnostics, and explicit fallback for complex content.
- Added structured CSS selector parsing, declaration filtering, specificity-aware cascade, inline styles, inheritance, and shorthand expansion for margins and padding.
- Added basic static layout and painting for headings, paragraphs, inline emphasis, links, lists, blockquotes, preformatted code, horizontal rules, and line breaks.
- Added single-surface scrolling integration, text scaling, long-document smoke tests, CJK layout tests, and the Stage 1A Weft Lab article.
- Added per-line link hit regions, hit testing across wrapped links, and the public `WeftView.onLinkTap` callback.
- Added block-level width, min/max width, box-sizing, and solid border support with content-box/border-box layout tests.
- Added six representative conformance fixtures, a structural corpus test, and a diagnostic Chrome/Edge browser screenshot generator.
- Added bundled Roboto/Roboto Mono fixtures, two Flutter pixel baselines, a Windows CI golden job, and a Pillow-based cross-engine difference report.
- Added CSS 2.1 adjacent, parent-child, and collapse-through block margin collapsing, including negative margins and padding/border blockers.
- Matched CSS half-leading with `TextLeadingDistribution.even`; block geometry now aligns with Chromium within 0.5px for the pixel fixtures.
- Table and image elements currently trigger fallback rather than silent content removal.

## 0.1.0-dev.1

- Initialized the Dart Pub workspace and six-package dependency boundary.
- Added immutable document, support report, logical selection, runtime, and capability contracts.
- Added the Weft Lab bootstrap application and initial unit/widget tests.
- Added architecture, delivery, quality, security, and project-management documentation.

This is a project scaffold. HTML parsing, layout, painting, and native JavaScript execution are not implemented yet.
