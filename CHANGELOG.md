# Changelog

## Unreleased (Stage 5)

- Document snapshot JSON wire format (`WeftDocumentJson`): canonical deterministic encoding, strict decode with format/version gates — a server may normalize once and clients consume the snapshot directly (ADR 0034).
- Normalization consistency vectors: 21 pinned vectors under `conformance/normalization/` (conformance corpus + synthetic cases incl. custom tags, nested-table fallback, CJK, entities); CI re-normalizes every input byte-for-byte, regeneration requires reviewed diffs.
- Seed-based fuzzing: CI suite (400+ iterations x 2 seeds) plus `tool/fuzz.dart` release sweep CLI; hardened two real defects it found — uncapped diagnostic paths bypassing `maxIssues`, and `package:html`'s `ParseError.toString()` crashing on hostile input (diagnostics now degrade to the runtime type).
- Capability policy matrix tests: all 8 subsets of the built-in capabilities — enabled probes pass, disabled namespaces are gateway-rejected with zero network side effects; JS is closed entirely by not opening a `WeftDocumentRuntime`.
- WebView fallback example (`example/weft_fallback`): `decideWeftFallback` render/webview/error-card decision, `WeftFallbackCoordinator` with injectable platform WebView; `webview_flutter` stays an example-only dependency.
- Release runbook (`docs/release-runbook.md`): unified version policy, compatibility anchor table (`WeftDocumentJson.version=1`, `bridgeVersion: 1`, `weft/bootstrap`), release checklist, rollback levels — with an automated rollback rehearsal test (`release_compat_test.dart`).
- API doc coverage gate (`tool/doc_coverage.dart`, wired into `tool/check.sh`): every exported public declaration must carry dartdoc; the public API surface is now fully documented.
- Device matrix plan (`docs/device-matrix.md`) with device tiers, runbook and pass criteria; `weft_lab` gained a performance-overlay toggle for device runs.

## Unreleased (Stage 3 & 4)

- Added stable logical text index with 100k-character cross-paragraph selection, copy, and remapping on streaming updates; selection chrome with drag handles, caret, and copy button (ADR 0013/0015/0019).
- Added chunked painting with visible-window culling, single-surface semantics (headings, tables, lists, links, images, selection actions), and anchor navigation with async frame-budgeted measurement (ADR 0017/0020/0024/0026/0028/0030/0027/0029/0031).
- Added progressive lazy layout for long documents, deep-jump framing, identical-snapshot reuse, and corpus structural gates (lossless, non-overlapping, in-bounds) with hostile-input diagnostics (ADR 0025/0031/0032).
- Added the vendored QuickJS 2024-01-13 engine behind a flat C shim (`native/weft_glue.c`) with native wall-clock, heap, stack, and microtask budget enforcement (ADR 0033).
- Added the per-document JS host `WeftDocumentRuntime` with `weft.state`/`weft.events`/`weft.net` capability modules, policy-gated visibility, redirect whitelist enforcement, network journaling, recovery without replay, and `(sessionId, sequence)` dedup.
- Added `WeftTagRenderer` custom tags: normalizer allowlist, attribute-driven leaf elements, engine-clamped paint ops, hit regions, tap callbacks, and semantics labels.
- Added the backend-neutral `weft_runtime_contract` suite and the scripted `weft_runtime_fake` backend; the QuickJS FFI and fake backends pass the same contract tests.
- Added a stage-4 Weft Lab demo (badge renderer plus FakeRuntime state/events) and the QuickJS native build script with a CI build step.

## Unreleased (Stage 1 & 2)

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
- Added controlled `<img>` normalization with `src/alt/width/height`, protocol filtering, dimension diagnostics, and `alt` fallback.
- Added host-provided image resolution, async decode invalidation, `ImageInfo` lifecycle management, and `WeftImagePaintCommand`.
- Added block image layout with intrinsic ratio, width constraints, borders, and padding.
- Added left/right image floats, per-line text wrapping across paragraphs, `clear`, same-side stacking, opposite-side pairing, and float-aware link regions.
- Table elements currently trigger fallback rather than silent content removal.

## 0.1.0-dev.1

- Initialized the Dart Pub workspace and six-package dependency boundary.
- Added immutable document, support report, logical selection, runtime, and capability contracts.
- Added the Weft Lab bootstrap application and initial unit/widget tests.
- Added architecture, delivery, quality, security, and project-management documentation.

This is a project scaffold. HTML parsing, layout, painting, and native JavaScript execution are not implemented yet.
