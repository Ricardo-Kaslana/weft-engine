# Changelog

## Unreleased

- Added controlled HTML normalization with tag/attribute filtering, URL checks, node limits, structured support diagnostics, and explicit fallback for complex content.
- Added structured CSS selector parsing, declaration filtering, specificity-aware cascade, inline styles, inheritance, and shorthand expansion for margins and padding.
- Added basic static layout and painting for headings, paragraphs, inline emphasis, links, lists, blockquotes, preformatted code, horizontal rules, and line breaks.
- Added single-surface scrolling integration, text scaling, long-document smoke tests, CJK layout tests, and the Stage 1A Weft Lab article.
- Table and image elements currently trigger fallback rather than silent content removal.

## 0.1.0-dev.1

- Initialized the Dart Pub workspace and six-package dependency boundary.
- Added immutable document, support report, logical selection, runtime, and capability contracts.
- Added the Weft Lab bootstrap application and initial unit/widget tests.
- Added architecture, delivery, quality, security, and project-management documentation.

This is a project scaffold. HTML parsing, layout, painting, and native JavaScript execution are not implemented yet.
